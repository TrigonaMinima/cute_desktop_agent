import AppKit
import AgentCore

/// Bootstraps the overlay: loads config, builds the state machine + avatar, and drives
/// them from a `FrameClock` — perception polling, hover hit-testing, drag, and the status
/// item's quit action are all wired here. One overlay panel per attached display, all
/// rendering the same global-web-space state each frame (each panel just offsets by its
/// display's origin) — see `ScreenLayout`.
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

    /// Kept past launch (unlike every other launch-time local) because a display-change
    /// rebuild needs to make fresh `Avatar` instances — layer trees can't be shared
    /// across views, so each new panel's view gets its own conformer from the config.
    private var config: AppConfig!

    /// The avatar's live behavior/perception state — mutated once per frame by `tick`
    /// below and directly by the drag handlers (see AgentCore's `StateMachine`
    /// single-writer doc comment). Kept as its own property rather than folded into
    /// `Runtime` below, so `stateMachine.tick(state: &state, ...)` and the drag calls
    /// can pass it `inout` without reaching through an optional struct field each time.
    private var state: AgentState!

    /// One display's slice of the overlay: its layout snapshot entry, the panel
    /// covering its full frame, and that panel's avatar view.
    private struct ScreenPanel {
        let display: ScreenLayout.Display
        let panel: OverlayPanel
        let avatarView: AvatarView
    }

    /// Everything built once in `applicationDidFinishLaunching` and torn down together
    /// at quit — grouped into one optional so `AppDelegate` doesn't carry a separate
    /// implicitly-unwrapped optional per object. `layout`/`panels`/`frameClock` are
    /// `var`: a display change swaps them together in `rebuildScreens()`; the two menu
    /// controllers survive rebuilds (the status item must not blink out of the menu bar
    /// because a monitor was unplugged).
    private struct Runtime {
        var layout: ScreenLayout
        var panels: [ScreenPanel]
        var frameClock: FrameClock
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

        do {
            config = try AppConfig.loadFromBundle()
        } catch {
            fatalError("AgentApp: failed to load config.json from bundle: \(error)")
        }

        guard let layout = ScreenLayout.current(fallback: nil) else { fatalError("AgentApp: no screen") }

        state = stateMachine.makeInitialState(
            screens: layout.screens, avatarSize: config.makeAvatar().intrinsicSize, now: clock.now()
        )

        // One provider shared by both menu surfaces (status-item dropdown + avatar
        // right-click) so their live refresh reads the identical snapshot rule by
        // construction — see `summarySnapshot()`.
        let summaryProvider: () -> StatusSummary = { [weak self] in
            self?.summarySnapshot() ?? StatusSummary(sections: [])
        }
        let statusItemController = StatusItemController(
            title: config.statusItemTitle, summaryProvider: summaryProvider, launchAtLogin: launchAtLogin)
        let contextMenu = LiveMenuController(summaryProvider: summaryProvider, launchAtLogin: launchAtLogin)

        // Forces `perception`'s lazy init now — its Accessibility prompt + global keydown
        // and scroll-wheel monitor registration are synchronous IPC with WindowServer/TCC,
        // which must not land on the first `frameClock` tick (a 60Hz display-link callback).
        _ = perception

        let panels = buildPanels(layout: layout, contextMenu: contextMenu)
        runtime = Runtime(
            layout: layout, panels: panels, frameClock: makeFrameClock(panels: panels),
            statusItemController: statusItemController, contextMenu: contextMenu
        )
        runtime?.frameClock.start()

        // Display attach/detach/resolution changes: coalesce the notification burst one
        // reconfiguration fires (often 2-4 back to back) into a single rebuild.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    /// One panel + avatar view per display, covering its FULL frame (not visibleFrame —
    /// confinement to the visible area is AgentCore's clamp, and the speech bubble may
    /// legitimately rise into the menu-bar strip).
    private func buildPanels(layout: ScreenLayout, contextMenu: LiveMenuController) -> [ScreenPanel] {
        layout.displays.map { display in
            let avatarView = AvatarView(avatar: config.makeAvatar())
            avatarView.frame = NSRect(origin: .zero, size: display.cocoaFrame.size)
            avatarView.worldOrigin = display.fullFrameWeb.origin
            wireDrag(avatarView)
            wireContextMenu(avatarView, contextMenu: contextMenu)

            let panel = OverlayPanel(screenFrame: display.cocoaFrame, contentView: avatarView)
            panel.orderFrontRegardless()
            return ScreenPanel(display: display, panel: panel, avatarView: avatarView)
        }
    }

    /// `FrameClock` needs a host view for `NSView.displayLink` — the primary display's
    /// avatar view. One clock drives every panel's render; per-panel display links would
    /// tick the state machine more than once a frame.
    private func makeFrameClock(panels: [ScreenPanel]) -> FrameClock {
        FrameClock(hostView: panels[0].avatarView, clock: clock) { [weak self] now, dt in
            self?.tick(now: now, dt: dt)
        }
    }

    @objc private func screenParametersDidChange() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(rebuildScreens), object: nil)
        perform(#selector(rebuildScreens), with: nil, afterDelay: 0.3)
    }

    /// Tears down every panel and rebuilds against the new display list. The state
    /// machine needs no special handling: the next perception poll stamps the new
    /// `screens` into `world`, and `reconcilePosition` pulls a stranded avatar onto a
    /// surviving screen on the same tick.
    @objc private func rebuildScreens() {
        guard var runtime else { return }
        guard let layout = ScreenLayout.current(fallback: runtime.layout) else { return }

        runtime.frameClock.stop()
        runtime.panels.forEach { $0.panel.close() }

        runtime.layout = layout
        runtime.panels = buildPanels(layout: layout, contextMenu: runtime.contextMenu)
        runtime.frameClock = makeFrameClock(panels: runtime.panels)
        self.runtime = runtime
        runtime.frameClock.start()
    }

    /// The per-frame driver `FrameClock` calls: poll perception, advance the state
    /// machine, render every panel, refresh hit-testing, then push the live menus — in
    /// that order (mirrors the POC's `tick()`; see AgentCore's `StateMachine.tick` doc
    /// comment for why blink/emotion must run even mid-drag).
    private func tick(now: Double, dt: Double) {
        guard let runtime else { return }
        applyPerception(dt: dt, layout: runtime.layout)
        stateMachine.tick(state: &state, dt: dt)
        // Squash/bob is panel-invariant — compute once, share across every panel's render.
        let motion = computeBodyMotion(state: state, now: now)
        for screenPanel in runtime.panels {
            screenPanel.avatarView.render(state: state, motion: motion)
        }
        updateHitTest(panels: runtime.panels)
        refreshMenus(runtime, now: now)
    }

    /// Polls this frame's OS-observed signals and folds them into `state.world` — the
    /// one mapping call `AgentWorld.apply(_:)` replaces the old field-by-field copy.
    private func applyPerception(dt: Double, layout: ScreenLayout) {
        let snapshot = perception.poll(layout: layout, dt: dt)
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
        // This is a persistent background agent, not a document-window app — its windows
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
    // into click-through and abandon the drag. Per panel, events are only wanted where the
    // avatar's rect actually intersects that display — every other panel stays fully
    // click-through. Mid-drag this can enable two panels at once (avatar straddling an
    // edge), which is harmless: AppKit keeps routing the drag to the mouse-down window.

    private func updateHitTest(panels: [ScreenPanel]) {
        let hovering = AgentCore.isHovering(cursor: state.world.cursor, position: state.body.position, size: state.body.size)
        let avatarRect = Rect(origin: state.body.position, size: state.body.size)
        for screenPanel in panels {
            let onThisDisplay = rectsOverlap(avatarRect, screenPanel.display.fullFrameWeb)
            let wantsEvents = (state.body.dragging || hovering) && onThisDisplay
            if wantsEvents == !screenPanel.panel.ignoresMouseEvents { continue }
            screenPanel.panel.ignoresMouseEvents = !wantsEvents
        }
    }
}
