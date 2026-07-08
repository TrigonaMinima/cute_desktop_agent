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
    // Shares `clock` with `stateMachine` for the same reason as above — the typing
    // signal's "how long since the last keystroke" comparison must use the same clock
    // instance the rest of the tick's timers do.
    private lazy var perception = Perception(clock: clock)
    // See `LaunchAtLoginController`'s doc comment for why this must be a stored property.
    private let launchAtLogin = LaunchAtLoginController()

    /// The avatar's live behavior/perception state — mutated once per frame by `tick`
    /// below and directly by the drag handlers (see AgentCore's `StateMachine`
    /// single-writer doc comment). Kept as its own property rather than folded into
    /// `Runtime` below, so `stateMachine.tick(state: &state, ...)` and the drag calls
    /// can pass it `inout` without reaching through an optional struct field each time.
    private var state: AgentState!

    /// Everything else built once in `applicationDidFinishLaunching` and torn down
    /// together at quit — grouped into one optional so `AppDelegate` doesn't carry a
    /// separate implicitly-unwrapped optional per object. All of these are either
    /// present together (after launch finishes) or absent together (before it does),
    /// so one `Runtime?` says that directly instead of seven `T!`s each promising it
    /// individually.
    private struct Runtime {
        let screenFrame: NSRect
        let panel: OverlayPanel
        let avatarView: AvatarView
        let frameClock: FrameClock
        let statusItemController: StatusItemController
        let contextMenu: LiveMenuController
    }
    private var runtime: Runtime?

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
        let screenFrame = screen.frame // full frame, not visibleFrame — matches the POC

        let avatar = config.makeAvatar()
        let bounds = Size(width: Double(screenFrame.width), height: Double(screenFrame.height))
        state = stateMachine.makeInitialState(bounds: bounds, avatarSize: avatar.intrinsicSize, now: clock.now())

        let avatarView = AvatarView(avatar: avatar)
        avatarView.frame = NSRect(origin: .zero, size: screenFrame.size)
        wireDrag(avatarView)

        let panel = OverlayPanel(screenFrame: screenFrame, contentView: avatarView)
        panel.orderFrontRegardless()

        // One provider shared by both menu surfaces (status-item dropdown + avatar
        // right-click) so their live refresh reads the identical snapshot rule by
        // construction — see `summarySnapshot()`.
        let summaryProvider: () -> StatusSummary = { [weak self] in
            self?.summarySnapshot() ?? StatusSummary(sections: [])
        }
        let statusItemController = StatusItemController(
            title: config.statusItemTitle, summaryProvider: summaryProvider, launchAtLogin: launchAtLogin)
        let contextMenu = LiveMenuController(summaryProvider: summaryProvider, launchAtLogin: launchAtLogin)
        wireContextMenu(avatarView, contextMenu: contextMenu)

        // Forces `perception`'s lazy init now — its Accessibility prompt + global keydown
        // and scroll-wheel monitor registration are synchronous IPC with WindowServer/TCC,
        // which must not land on the first `frameClock` tick (a 60Hz display-link callback).
        _ = perception

        let frameClock = FrameClock(hostView: avatarView, clock: clock) { [weak self] now, dt in
            self?.tick(now: now, dt: dt)
        }

        runtime = Runtime(
            screenFrame: screenFrame, panel: panel, avatarView: avatarView, frameClock: frameClock,
            statusItemController: statusItemController, contextMenu: contextMenu
        )
        frameClock.start()
    }

    /// The per-frame driver `FrameClock` calls: poll perception, advance the state
    /// machine, render, refresh hit-testing, then push the live menus — in that order
    /// (mirrors the POC's `tick()`; see AgentCore's `StateMachine.tick` doc comment for
    /// why blink/emotion must run even mid-drag).
    private func tick(now: Double, dt: Double) {
        guard let runtime else { return }
        applyPerception(dt: dt, screenFrame: runtime.screenFrame)
        stateMachine.tick(state: &state, dt: dt)
        runtime.avatarView.render(state: state, now: now)
        updateHitTest(panel: runtime.panel)
        refreshMenus(runtime, now: now)
    }

    /// Polls this frame's OS-observed signals and folds them into `state.world` — the
    /// one mapping call `AgentWorld.apply(_:)` replaces the old field-by-field copy.
    private func applyPerception(dt: Double, screenFrame: NSRect) {
        let snapshot = perception.poll(screenFrame: screenFrame, dt: dt)
        state.world.apply(snapshot)
    }

    /// Pushes this frame's state into both live menu surfaces. No-ops unless their menu
    /// is currently open — see `LiveMenuController`'s doc comment for why a per-frame
    /// push (rather than a `menuWillOpen`-scoped Timer) is what keeps an open menu's
    /// rows tracking live state.
    private func refreshMenus(_ runtime: Runtime, now: Double) {
        runtime.statusItemController.refreshIfOpen(now: now)
        runtime.contextMenu.refreshIfOpen(now: now)
    }

    /// The single reading of `state` both live menus push into their rows, on open and
    /// every frame while open. `nil` only before the first tick (`state` unset).
    private func summarySnapshot() -> StatusSummary? {
        state?.statusSummary(now: clock.now())
    }

    public func applicationWillTerminate(_ notification: Notification) {
        runtime?.frameClock.stop()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // This is a persistent background agent, not a document-window app — its one window
        // closing isn't a quit signal (mirrors the `disableAutomaticTermination` call above).
        false
    }

    // MARK: - Drag (avatar-owned mousedown/mousemove/mouseup)

    private func wireDrag(_ avatarView: AvatarView) {
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

    private func wireContextMenu(_ avatarView: AvatarView, contextMenu: LiveMenuController) {
        avatarView.onBuildContextMenu = { [weak self] point in
            guard let self else { return nil }
            let cursor = Point(x: Double(point.x), y: Double(point.y))
            // Safety net against the one-frame click-through window `updateHitTest`
            // hasn't caught up to yet — same box check that drives hover/hit-testing.
            guard AgentCore.isHovering(cursor: cursor, position: self.state.body.position, size: self.state.body.size)
            else { return nil }

            // The persistent `LiveMenuController` menu, not a throwaway one — its delegate
            // rebuilds rows on this open and `refreshIfOpen()` keeps them live afterward.
            return contextMenu.menu
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

    private func updateHitTest(panel: OverlayPanel) {
        let hovering = AgentCore.isHovering(cursor: state.world.cursor, position: state.body.position, size: state.body.size)
        let wantsEvents = state.body.dragging || hovering
        if wantsEvents == !panel.ignoresMouseEvents { return }
        panel.ignoresMouseEvents = !wantsEvents
    }
}
