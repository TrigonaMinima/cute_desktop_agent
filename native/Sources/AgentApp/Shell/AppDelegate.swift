import AppKit
import AgentCore

/// Bootstraps the overlay: loads config, builds the state machine + avatar, and drives
/// them from a `FrameClock` — perception polling, hover hit-testing, drag, and the status
/// item's quit action are all wired here. One overlay panel per attached display, all
/// rendering the same global-web-space state each frame (each panel just offsets by its
/// display's origin) — see `ScreenLayout`.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // Shared with `brain` below — `render`'s `now` and the brain's internal timer
    // comparisons (modeEndsAt, cognition slices, ...) must read the same clock instance,
    // or every timer is off by however far apart the two instances were constructed.
    private let clock = SystemClock()
    /// The active brain, selected from `storedBrainKind` at launch (config.json's `brain`
    /// key as the default, overridden by a persisted menu choice — see
    /// `storedBrainKind`/D21) — built in `applicationDidFinishLaunching` because it needs
    /// the decoded config, and swapped live afterward by `switchBrain(to:)`. Everything
    /// after construction goes through the `AgentBrain` seam, so the shell never branches
    /// on which brain is live.
    private var brain: AgentBrain!
    /// Which `BrainKind` `brain` currently is — kept alongside the existential because
    /// `AgentBrain` doesn't expose its own kind, and the "Brain" menu needs it both to
    /// checkmark the live row and to no-op a reselection of the already-active brain.
    /// Set everywhere `brain` is (re)assigned.
    private var currentBrainKind: BrainKind = .emergent
    // Shares `clock` with `brain` for the same reason as above — the typing signal's
    // "how long since the last keystroke" comparison must use the same clock instance
    // the rest of the tick's timers do.
    private lazy var perception = Perception(clock: clock)
    // See `LaunchAtLoginController`'s doc comment for why this must be a stored property.
    private let launchAtLogin = LaunchAtLoginController()
    /// Canonical timer data — see its own doc comment. Owned here (not per-brain, not
    /// rebuilt by `switchBrain`) so the timer survives a live brain swap for free.
    private let timerController = TimerController()
    /// Set for the duration of a mouse-down that landed on the on-screen pause button,
    /// so the matching drag/up callbacks don't also start/end a drag (see `wireDrag`).
    private var suppressDrag = false
    /// Non-nil while `body.position` is being animated toward the timer's pin corner
    /// (see `startTimer`/`advanceTimerPin`) — cleared on arrival, on a drag starting
    /// mid-travel, or on `endTimer`, whichever comes first.
    private var timerPinTarget: Point?

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

    /// True while the sleep tier has the frame clock stopped (see `enterSleepIfNeeded`).
    private var dormant = false
    private lazy var powerController = PowerController { [weak self] in
        self?.wakeFromSleep()
    }

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

        currentBrainKind = storedBrainKind
        brain = makeBrain(kind: currentBrainKind)
        state = brain.makeInitialState(
            screens: layout.screens, avatarSize: config.makeAvatar().intrinsicSize, now: clock.now()
        )
        let brainMenu = makeBrainMenu()
        let temperamentMenu = makeTemperamentMenu()
        let timerMenu = makeTimerMenu()

        // One provider shared by both menu surfaces (status-item dropdown + avatar
        // right-click) so their live refresh reads the identical snapshot rule by
        // construction — see `summarySnapshot()`.
        let summaryProvider: () -> StatusSummary = { [weak self] in
            self?.summarySnapshot() ?? StatusSummary(sections: [])
        }
        let statusItemController = StatusItemController(
            title: config.statusItemTitle, summaryProvider: summaryProvider, brain: brainMenu,
            temperament: temperamentMenu, timer: timerMenu, launchAtLogin: launchAtLogin)
        let contextMenu = LiveMenuController(
            summaryProvider: summaryProvider, brain: brainMenu, temperament: temperamentMenu, timer: timerMenu,
            launchAtLogin: launchAtLogin)

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
        // A display change while asleep doesn't restart the clock — the panels are
        // rebuilt (so the sleeping avatar reappears on the new layout when it wakes),
        // but wake stays event-driven via `PowerController`.
        if !dormant {
            runtime.frameClock.start()
        }
    }

    /// `UserDefaults` key holding the chosen temperament preset's raw value — read at
    /// boot, written by the menu (D10: the preset survives relaunches; nothing else does).
    private static let temperamentPresetKey = "temperamentPreset"

    private var storedTemperamentPreset: TemperamentPreset {
        UserDefaults.standard.string(forKey: Self.temperamentPresetKey)
            .flatMap(TemperamentPreset.init(rawValue:)) ?? .calm
    }

    /// `UserDefaults` key holding the chosen brain's raw value — read at boot (falling
    /// back to `config.json`'s `brain` key, `AppConfig.brainKind`), written by the
    /// "Brain" menu (D21: a live switch, mirroring D10's temperament persistence — the
    /// choice survives relaunches, config.json is just the first-ever-launch default).
    private static let brainKindKey = "brainKind"

    private var storedBrainKind: BrainKind {
        UserDefaults.standard.string(forKey: Self.brainKindKey)
            .flatMap(BrainKind.init(rawValue:)) ?? config.brainKind
    }

    /// Builds the given brain. Both share the delegate's clock (see the `clock` doc
    /// comment); the emergent brain also gets a wall-clock hour reader for its circadian
    /// baselines — fractional, so 14:30 reads as 14.5 — and boots at the persisted
    /// temperament preset. Does not touch `currentBrainKind` — callers (launch and
    /// `switchBrain(to:)`) own that assignment alongside `brain` itself.
    private func makeBrain(kind: BrainKind) -> AgentBrain {
        switch kind {
        case .classic:
            return StateMachine(rng: SystemRandom(), clock: clock)
        case .emergent:
            let calendar = Calendar.current
            return EmergentBrain(
                rng: SystemRandom(), clock: clock,
                hourOfDay: {
                    let parts = calendar.dateComponents([.hour, .minute], from: Date())
                    return Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
                },
                bootTemperament: storedTemperamentPreset.temperament
            )
        }
    }

    /// The "Brain" submenu's controller, pinned as the first item of both status
    /// surfaces (D21). Selection persists the choice and swaps the live brain in place
    /// via `switchBrain(to:)`.
    private func makeBrainMenu() -> BrainMenuController {
        BrainMenuController(
            current: { [weak self] in self?.currentBrainKind ?? .emergent },
            onSelect: { [weak self] kind in self?.switchBrain(to: kind) }
        )
    }

    /// Swaps the live brain in place (D21): no-ops if `kind` is already active; wakes the
    /// shell first if the previous brain had put it to sleep (the classic brain never
    /// requests runtime sleep, so a stopped clock would otherwise freeze the swap);
    /// persists the choice; then rebuilds `state` from the new brain's `makeInitialState`
    /// and carries the avatar's on-screen position/size over so it doesn't teleport to
    /// screen center. Everything past this point already goes through the `AgentBrain`
    /// seam, so no other call site needs to change.
    private func switchBrain(to kind: BrainKind) {
        guard kind != currentBrainKind, let runtime else { return }
        if dormant {
            wakeFromSleep()
        }
        UserDefaults.standard.set(kind.rawValue, forKey: Self.brainKindKey)

        let previousBody = state.body
        currentBrainKind = kind
        brain = makeBrain(kind: kind)
        state = brain.makeInitialState(
            screens: runtime.layout.screens, avatarSize: config.makeAvatar().intrinsicSize, now: clock.now()
        )
        state.body.position = previousBody.position
        state.body.size = previousBody.size
    }

    /// The "Temperament" submenu's controller. Constructed unconditionally (D21) — the
    /// live brain can now change after launch via the "Brain" menu, so this can't be
    /// built-or-omitted once at boot the way it was before switching existed;
    /// `isAvailable` gates the row per-open instead (see its doc comment for why that's a
    /// separate signal from `current`). Selection persists the preset and tells the live
    /// brain to adopt it in place (the drives ease over).
    private func makeTemperamentMenu() -> TemperamentMenuController {
        TemperamentMenuController(
            isAvailable: { [weak self] in self?.brain is TemperamentControlling },
            current: { [weak self] in
                self?.state?.mind.flatMap { TemperamentPreset.matching($0.temperament) }
            },
            onSelect: { [weak self] preset in
                guard let self else { return }
                UserDefaults.standard.set(preset.rawValue, forKey: Self.temperamentPresetKey)
                (self.brain as? TemperamentControlling)?
                    .adoptTemperament(preset.temperament, state: &self.state)
            }
        )
    }

    /// The "Timer" submenu's controller. Constructed unconditionally, like `Brain` — a
    /// timer can be started/ended regardless of which brain is live. Reads
    /// `timerController.active` directly (not `state.timer`) so the menu's Start/End
    /// split reflects reality even on the very first open, before any tick has run
    /// `applyTimer` to populate `state.timer`.
    private func makeTimerMenu() -> TimerMenuController {
        TimerMenuController(
            isActive: { [weak self] in self?.timerController.active ?? false },
            isRunning: { [weak self] in self?.state?.timer?.running ?? false },
            onStart: { [weak self] durationMs in self?.startTimer(durationMs: durationMs) },
            onEnd: { [weak self] in self?.endTimer() },
            onTogglePause: { [weak self] in self?.toggleTimerPause() }
        )
    }

    /// Starts a new timer: wakes the shell first if it was asleep (the dropdown/on-screen
    /// button are both dead with the frame clock stopped), sets `timerPinTarget` to the
    /// top-right corner of the avatar's current screen's visible frame — offset down by
    /// `timerRowClearance` so the label row above it, not the avatar itself, is what
    /// clears the menu bar — then starts the controller. `body.position` itself is left
    /// untouched here; `advanceTimerPin` hurries it to that corner over the next few
    /// frames rather than teleporting it there. Both brains freeze in place (wherever
    /// `body.position` currently is, corner or mid-travel) on their very next `tick` once
    /// `applyTimer` writes `state.timer.active == true`.
    private func startTimer(durationMs: Double) {
        if dormant { wakeFromSleep() }
        let screenIndex = nearestScreenIndex(to: state.body.position, screens: state.world.screens)
        let screenRect = state.world.screens[screenIndex].frame
        let size = state.body.size
        // The label row is left-aligned with `position.x` and extends further right than
        // the avatar itself (button+remaining+total, see `timerRowWidth`) — pinning by the
        // avatar's own width alone would leave the row's remaining/total slots rendering
        // past the screen's right edge.
        let pinWidth = max(size.width, timerRowWidth)
        timerPinTarget = Point(
            x: screenRect.origin.x + screenRect.size.width - pinWidth,
            y: screenRect.origin.y + timerRowClearance
        )
        timerController.start(durationMs: durationMs, now: clock.now())
    }

    /// Ends the active timer. The freeze lifts on the next tick (`applyTimer` writes
    /// `state.timer = nil`) and both brains resume wandering from wherever the avatar
    /// currently sits — no explicit "resume" call needed. Also cancels any in-flight
    /// pin travel, so ending mid-hop doesn't leave a stale target for a later timer to
    /// stumble over.
    private func endTimer() {
        timerController.end()
        timerPinTarget = nil
    }

    /// Steps `body.position` toward `timerPinTarget` at `timerPinTravelSpeedPxPerSecond`,
    /// clearing the target on arrival. Runs before `brain.tick` each frame, so the
    /// freeze branch (which just pins to whatever `body.position` already is) rides
    /// along frame-by-frame instead of needing to know travel is happening. A drag
    /// starting mid-travel (`wireDrag`) clears `timerPinTarget` itself — this only needs
    /// to stay out of the way once dragging is underway, which `state.body.dragging`
    /// already covers between mouse-down and the drag actually clearing the target.
    private func advanceTimerPin(dt: Double) {
        guard let target = timerPinTarget, !state.body.dragging else { return }
        state.body.position = moveToward(state.body.position, target, maxDistance: timerPinTravelSpeedPxPerSecond * dt)
        if state.body.position == target {
            timerPinTarget = nil
        }
    }

    private func toggleTimerPause() {
        timerController.togglePause(now: clock.now())
    }

    /// The per-frame driver `FrameClock` calls: poll perception, step any in-flight
    /// timer-pin travel, advance the brain, render every panel, refresh hit-testing, then
    /// push the live menus — in that order (mirrors the POC's `tick()`; see AgentCore's
    /// `StateMachine.tick` doc comment for why blink/emotion must run even mid-drag).
    private func tick(now: Double, dt: Double) {
        guard let runtime else { return }
        applyPerception(dt: dt, layout: runtime.layout)
        advanceTimerPin(dt: dt)
        applyTimer(now: now)
        brain.tick(state: &state, dt: dt)
        // Squash/bob is panel-invariant — compute once, share across every panel's render.
        let motion = computeBodyMotion(state: state, now: now)
        for screenPanel in runtime.panels {
            screenPanel.avatarView.render(state: state, motion: motion)
        }
        updateHitTest(panels: runtime.panels)
        refreshMenus(runtime, now: now)
        enterSleepIfNeeded()
    }

    /// The sleep tier's shell half (decision log D11): once the brain reports it wants
    /// runtime sleep — the emergent brain settles into the rest pose first, on the same
    /// cognition slice — stop the frame clock entirely and hand wake duty to
    /// `PowerController`. Runs last in `tick` so the frame that falls asleep still
    /// renders its final pose.
    private func enterSleepIfNeeded() {
        guard !dormant, brain.wantsRuntimeSleep(state: state), let runtime else { return }
        dormant = true
        runtime.frameClock.stop()
        powerController.beginSleep()
    }

    /// Restarts the clock on any wake signal. If the signal was stale (no real input
    /// reached perception), the next cognition slice re-reads `.sleeping` and
    /// `enterSleepIfNeeded` puts the shell straight back to sleep — cheap and safe.
    private func wakeFromSleep() {
        guard dormant else { return }
        dormant = false
        powerController.endSleep()
        runtime?.frameClock.start()
    }

    /// Polls this frame's OS-observed signals and folds them into `state.world` — the
    /// one mapping call `AgentWorld.apply(_:)` replaces the old field-by-field copy.
    private func applyPerception(dt: Double, layout: ScreenLayout) {
        let snapshot = perception.poll(layout: layout, dt: dt)
        state.world.apply(snapshot)
    }

    /// Writes this frame's read-only timer snapshot into `state.timer` — the timer
    /// analog of `applyPerception`, single-writer discipline preserved (see
    /// `AgentState.timer`'s doc comment). Runs before `brain.tick` so the freeze branch
    /// in both brains sees this frame's `active`/`running` values, not last frame's.
    private func applyTimer(now: Double) {
        state.timer = timerController.snapshot(now: now)
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
            let cursor = Point(x: Double(point.x), y: Double(point.y))
            // A tap on the on-screen play/pause button toggles pause instead of starting
            // a drag — checked before falling through to the normal beginDrag path, and
            // only while a timer is actually active (the button doesn't exist otherwise).
            if self.state.timer?.active == true,
               isWithin(point: cursor, rect: timerControlRect(position: self.state.body.position, size: self.state.body.size)) {
                self.toggleTimerPause()
                self.suppressDrag = true
                return
            }
            // A real drag starting mid-hop-to-corner takes over position outright — don't
            // let the pin travel resume fighting the user's hand once it lets go.
            self.timerPinTarget = nil
            self.state.world.cursor = cursor
            self.brain.beginDrag(state: &self.state)
        }
        avatarView.onMouseDragged = { [weak self] point in
            guard let self, !self.suppressDrag else { return }
            self.state.world.cursor = Point(x: Double(point.x), y: Double(point.y))
            self.brain.updateDrag(state: &self.state)
        }
        avatarView.onMouseUp = { [weak self] in
            guard let self else { return }
            guard !self.suppressDrag else {
                self.suppressDrag = false
                return
            }
            self.brain.endDrag(state: &self.state, now: self.clock.now())
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
        // While a timer is active, the hit-testable region widens to the whole row
        // (button + digits) above the avatar, not just the avatar's own box — otherwise
        // the on-screen button sits in permanently-click-through space and can never be
        // tapped. `isWithin` and `isHovering` are equivalent (both-edges-inclusive)
        // point-in-rect checks, so this single call covers both cases correctly.
        let interactiveRect = state.timer?.active == true
            ? timerInteractiveRect(position: state.body.position, size: state.body.size)
            : Rect(origin: state.body.position, size: state.body.size)
        let hovering = isWithin(point: state.world.cursor, rect: interactiveRect)
        for screenPanel in panels {
            let onThisDisplay = rectsOverlap(interactiveRect, screenPanel.display.fullFrameWeb)
            let wantsEvents = (state.body.dragging || hovering) && onThisDisplay
            if wantsEvents == !screenPanel.panel.ignoresMouseEvents { continue }
            screenPanel.panel.ignoresMouseEvents = !wantsEvents
        }
    }
}
