import AppKit
import AgentCore

/// Bootstraps the overlay: loads config, builds the state machine + avatar, and drives
/// them from a `FrameClock` — perception polling, hover hit-testing, drag, and the status
/// item's quit action are all wired here.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // Shared with `stateMachine` below — `render`'s `now` and `StateMachine.tick`'s internal
    // timer comparisons (modeEndsAt, happyUntil, ...) must read the same clock instance, or
    // every timer is off by however far apart the two instances were constructed.
    private let clock = SystemClock()
    private lazy var stateMachine = StateMachine(rng: SystemRandom(), clock: clock)
    private var state: AgentState!
    private var screenFrame: NSRect!
    private var panel: OverlayPanel!
    private var avatarView: AvatarView!
    private var frameClock: FrameClock!
    private var statusItemController: StatusItemController!
    private var contextMenu: LiveMenuController!
    // See `LaunchAtLoginController`'s doc comment for why this must be a stored property.
    private let launchAtLogin = LaunchAtLoginController()
    // Shares `clock` with `stateMachine` for the same reason as above — the typing
    // signal's "how long since the last keystroke" comparison must use the same clock
    // instance the rest of the tick's timers do.
    private lazy var perception = Perception(clock: clock)

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Without this, macOS's Automatic Termination silently kills accessory apps like this
        // one after a short idle window, since it holds no standard document window and looks
        // "idle" to the OS even while its display link is actively animating.
        ProcessInfo.processInfo.disableAutomaticTermination("AgentApp is a persistent background overlay agent")

        let config: AppConfig
        do {
            config = try AppConfig.loadFromBundle()
        } catch {
            fatalError("AgentApp: failed to load config.json from bundle: \(error)")
        }

        guard let screen = NSScreen.main else { fatalError("AgentApp: no screen") }
        screenFrame = screen.frame // full frame, not visibleFrame — matches the POC

        let avatar = config.makeAvatar()
        let bounds = Size(width: Double(screenFrame.width), height: Double(screenFrame.height))
        state = stateMachine.makeInitialState(bounds: bounds, avatarSize: avatar.intrinsicSize, now: clock.now())

        avatarView = AvatarView(avatar: avatar)
        avatarView.frame = NSRect(origin: .zero, size: screenFrame.size)
        wireDrag()

        panel = OverlayPanel(screenFrame: screenFrame, contentView: avatarView)
        panel.orderFrontRegardless()

        // One provider shared by both menu surfaces (status-item dropdown + avatar
        // right-click) so their live refresh reads the identical snapshot rule by
        // construction — see `summarySnapshot()`.
        let summaryProvider: () -> StatusSummary = { [weak self] in
            self?.summarySnapshot() ?? StatusSummary(sections: [])
        }
        statusItemController = StatusItemController(
            title: config.statusItemTitle, summaryProvider: summaryProvider, launchAtLogin: launchAtLogin)
        contextMenu = LiveMenuController(summaryProvider: summaryProvider, launchAtLogin: launchAtLogin)
        wireContextMenu()

        // Forces `perception`'s lazy init now — its Accessibility prompt + global keydown
        // and scroll-wheel monitor registration are synchronous IPC with WindowServer/TCC,
        // which must not land on the first `frameClock` tick (a 60Hz display-link callback).
        _ = perception

        frameClock = FrameClock(hostView: avatarView, clock: clock) { [weak self] now, dt in
            guard let self else { return }
            let perceived = self.perception.poll(screenFrame: self.screenFrame, dt: dt)
            self.state.world.cursor = perceived.cursor
            self.state.world.cursorVelocity = perceived.cursorVelocity
            self.state.world.frontmostApp = perceived.frontmostApp
            self.state.world.frontmostWindow = perceived.frontmostWindow
            self.state.world.typing = perceived.typing
            self.state.world.typingLocation = perceived.typingLocation
            self.state.world.scrolling = perceived.scrolling
            self.state.world.scrollVelocity = perceived.scrollVelocity

            self.stateMachine.tick(state: &self.state, dt: dt)
            self.avatarView.render(state: self.state, now: now)
            self.updateHitTest()

            // No-ops unless their menu is currently open — see `LiveMenuController`'s doc
            // comment for why a per-frame push (rather than a `menuWillOpen`-scoped Timer)
            // is what makes an open menu's rows track live state.
            self.statusItemController.refreshIfOpen(now: now)
            self.contextMenu.refreshIfOpen(now: now)
        }
        frameClock.start()
    }

    /// The single reading of `state` both live menus push into their rows, on open and
    /// every frame while open. `nil` only before the first tick (`state` unset).
    private func summarySnapshot() -> StatusSummary? {
        state?.statusSummary(now: clock.now())
    }

    public func applicationWillTerminate(_ notification: Notification) {
        frameClock.stop()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // This is a persistent background agent, not a document-window app — its one window
        // closing isn't a quit signal (mirrors the `disableAutomaticTermination` call above).
        false
    }

    // MARK: - Drag (avatar-owned mousedown/mousemove/mouseup)

    private func wireDrag() {
        avatarView.onMouseDown = { [weak self] point in
            guard let self else { return }
            self.state.world.cursor = Point(x: Double(point.x), y: Double(point.y))
            self.stateMachine.beginDrag(state: &self.state)
        }
        avatarView.onMouseDragged = { [weak self] point in
            guard let self else { return }
            self.state.world.cursor = Point(x: Double(point.x), y: Double(point.y))
            self.stateMachine.updateDrag(state: &self.state)
        }
        avatarView.onMouseUp = { [weak self] in
            guard let self else { return }
            self.stateMachine.endDrag(state: &self.state, now: self.clock.now())
        }
    }

    // MARK: - Right-click context menu (avatar-owned, mirrors the status item's rows)

    private func wireContextMenu() {
        avatarView.onBuildContextMenu = { [weak self] point in
            guard let self else { return nil }
            let cursor = Point(x: Double(point.x), y: Double(point.y))
            // Safety net against the one-frame click-through window `updateHitTest`
            // hasn't caught up to yet — same box check that drives hover/hit-testing.
            guard AgentCore.isHovering(cursor: cursor, position: self.state.body.position, size: self.state.body.size)
            else { return nil }

            // The persistent `LiveMenuController` menu, not a throwaway one — its delegate
            // rebuilds rows on this open and `refreshIfOpen()` keeps them live afterward.
            return self.contextMenu.menu
        }
    }

    // MARK: - Hover hit-test
    //
    // A `.ignoresMouseEvents` window gets no mouse-moved events except while the hit test
    // already has it enabled — see `Perception.swift` — so this polls `isHovering` (the
    // same AgentCore geometry the state machine's own proximity check uses) once a frame
    // instead. Mouse events are forced on for the whole drag regardless of hover, matching
    // the plan: letting the cursor outrun the avatar mid-drag must not drop the window back
    // into click-through and abandon the drag.

    private func updateHitTest() {
        let hovering = AgentCore.isHovering(cursor: state.world.cursor, position: state.body.position, size: state.body.size)
        let wantsEvents = state.body.dragging || hovering
        if wantsEvents == !panel.ignoresMouseEvents { return }
        panel.ignoresMouseEvents = !wantsEvents
    }
}
