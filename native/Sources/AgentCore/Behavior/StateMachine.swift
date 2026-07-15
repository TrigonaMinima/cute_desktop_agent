import Foundation

// The avatar's behavior state machine — mode selection, movement, drag, blink, and
// emotion triggers. Its logic and literal timings are carried over unchanged from
// electron-poc/renderer/blob.js (lines ~90-431): startMode, transitionToNextMode,
// updateMovement, maybeAdvanceMode, triggerHappy/updateHappy, updateBlink,
// updateEmotionTriggers/computeDesiredEmotion, and the mousedown/mousemove/mouseup drag
// handlers — see each function's doc comment for where a literal looks inconsistent but
// is preserved deliberately rather than "fixed" to look tidier.
//
// `StateMachine` is the sole writer of `AgentState` (see AgentState.swift's doc
// comment) — everything else (Perception, AvatarView) reads a frozen copy each frame.
// RNG and time are injected (`RandomProvider`, `Clock`) so every timer and weighted
// choice is deterministic under test; production code wires `SystemRandom`/`SystemClock`.
//
// The ported functions below are `internal` (not `public`) — visible to AgentApp only
// through `tick`/`beginDrag`/`updateDrag`/`endDrag`, but individually testable via
// `@testable import AgentCore` at the same granularity as the JS source, so a failing
// test names exactly which ported function regressed.
public final class StateMachine {
    private let rng: RandomProvider
    private let clock: Clock

    public init(rng: RandomProvider, clock: Clock) {
        self.rng = rng
        self.clock = clock
    }

    /// One frame: advance movement/mode/happy-resume (unless dragging, which owns
    /// position itself via `updateDrag`, or an active timer, which pins position the
    /// same way — see `state.timer`), then blink and emotion — both of which keep
    /// running even mid-drag/mid-timer, matching the JS original's unconditional tail of
    /// `tick()`.
    public func tick(state: inout AgentState, dt: Double) {
        let now = clock.now()
        // Net-new, beyond blob.js parity: derive the region to avoid every tick, even
        // while dragging — it's surfaced in the menu/status rows regardless, and
        // `maybeYield` below is what actually gates the reaction on not-dragging.
        state.body.attentionZone = attentionZone(from: state.world)
        if !state.body.dragging && !(state.timer?.active == true) {
            reconcilePosition(state: &state)
            updateHappy(state: &state, now: now)
            maybeYield(state: &state, now: now)
            updateMovement(state: &state, dt: dt, now: now)
            maybeAdvanceMode(state: &state, now: now)
        }
        updateBlink(state: &state, now: now)
        updateEmotionTriggers(state: &state, now: now)
        state.body.emotion = computeDesiredEmotion(state: state, now: now)
    }

    // MARK: - Boot

    /// Mechanical port of blob.js's inline `state`/`cursor` object literals (lines
    /// 147-167) — the one-time boot state, before any tick runs. Deliberately NOT a
    /// call to `startMode(.idle, ...)`: several of these seed values use ranges
    /// distinct from the steady-state reschedule logic (see Constants' initial* doc
    /// comments), matching the JS source exactly rather than reusing the tick-time paths.
    public func makeInitialState(screens: [ScreenInfo], avatarSize: Size, now: Double) -> AgentState {
        // Center of the primary display's rect — NOT of the global web origin: a
        // non-zero-origin primary (possible after display reconfiguration) must still
        // boot the avatar onto its own frame.
        let primary = screens[0].frame
        let center = Point(
            x: primary.origin.x + primary.size.width / 2,
            y: primary.origin.y + primary.size.height / 2
        )
        return AgentState(
            world: AgentWorld(screens: screens, cursor: center),
            body: AgentBody(
                position: center, mode: .idle, target: center, moving: false, emotion: .neutral,
                dragging: false, dragOffset: Vector(dx: 0, dy: 0), size: avatarSize
            ),
            memory: AgentMemory(
                modeEndsAt: now + Constants.initialModeEndsAtDelayMs,
                happyUntil: 0,
                happyResumeMode: .idle,
                nextBlinkAt: now + randomRange(Constants.initialBlinkDelayMsRange),
                blinking: false,
                blinkEndsAt: 0,
                quirkEmotion: nil,
                quirkUntil: 0,
                nextQuirkAt: now + randomRange(Constants.initialQuirkDelayMsRange),
                proximityUntil: 0,
                proximityCooldownUntil: 0,
                yieldCooldownUntil: 0
            )
        )
    }

    // MARK: - Drag (avatar-owned mousedown/mousemove/mouseup)

    public func beginDrag(state: inout AgentState) {
        state.body.dragging = true
        state.body.moving = false
        state.body.dragOffset = Vector(
            dx: state.world.cursor.x - state.body.position.x,
            dy: state.world.cursor.y - state.body.position.y
        )
    }

    /// Fully confined to the cursor's screen — `nearestScreenIndex` resolves dead-zone
    /// cursor positions (between non-aligned displays) to whichever screen is closest,
    /// so a drag through a dead zone slides along the nearer screen's edge instead of
    /// vanishing.
    public func updateDrag(state: inout AgentState) {
        let raw = Point(
            x: state.world.cursor.x - state.body.dragOffset.dx,
            y: state.world.cursor.y - state.body.dragOffset.dy
        )
        let screen = nearestScreen(to: state.world.cursor, screens: state.world.screens)
        state.body.position = clampToScreen(point: raw, screen: screen, blobSize: state.body.size)
    }

    public func endDrag(state: inout AgentState, now: Double) {
        state.body.dragging = false
        triggerHappy(state: &state, now: now)
    }

    // MARK: - Mode transitions

    /// Equivalent to the JS original's `randomRange`: `lerp` from `min` to `max` by a
    /// uniform random fraction.
    private func randomRange(_ range: Constants.MsRange) -> Double {
        lerp(range.min, range.max, rng.nextUnit())
    }

    /// Uniform random index into a fixed-size collection — `Int(rng.nextUnit() * count)`.
    private func randomIndex(_ count: Int) -> Int {
        Int(rng.nextUnit() * Double(count))
    }

    func startMode(_ mode: Mode, state: inout AgentState, now: Double) {
        state.body.mode = mode
        // Polite bias (net-new, beyond blob.js parity — see Math/Avoidance.swift): shared
        // by wander/rest below via `biasedIndex`, each picks the edge/corner farthest
        // from the current activity anchor instead of a uniform index.
        let anchor = activityAnchor(from: state.world)
        switch mode {
        case .wander:
            // Screen pick draws FIRST (before the bias tie-break / along / depth draws)
            // so single-screen sequences stay byte-identical — see pickTargetScreenIndex.
            let screen = state.world.screens[pickTargetScreenIndex(state: state)].frame
            let edgeCandidates = (0..<4).map {
                pickBorderPoint(
                    screen: screen, margin: Constants.roamMargin, blobSize: state.body.size,
                    bandDepth: Constants.borderBandDepth, edgeIndex: $0, rngAlong: 0.5, rngDepth: 0.5
                )
            }
            let edgeIndex = biasedIndex(anchor: anchor, candidates: edgeCandidates)
            let rngAlong = rng.nextUnit()
            let rngDepth = rng.nextUnit()
            state.body.target = pickBorderPoint(
                screen: screen, margin: Constants.roamMargin, blobSize: state.body.size,
                bandDepth: Constants.borderBandDepth, edgeIndex: edgeIndex, rngAlong: rngAlong, rngDepth: rngDepth
            )
            state.body.moving = true
        case .rest:
            // Corners have no randomness of their own, so the candidates themselves are
            // the four possible final targets.
            let screen = state.world.screens[pickTargetScreenIndex(state: state)].frame
            let cornerCandidates = (0..<4).map {
                pickCorner(
                    screen: screen, margin: Constants.restMargin, blobSize: state.body.size,
                    cornerIndex: $0
                )
            }
            state.body.target = cornerCandidates[biasedIndex(anchor: anchor, candidates: cornerCandidates)]
            state.body.moving = true
        case .flee:
            // Net-new, beyond blob.js parity: `maybeYield` computes the escape target
            // (it has the zone data this generic switch doesn't) and sets
            // `state.body.target` before calling `startMode(.flee, ...)` — this case
            // only marks the mode as moving, deliberately leaving the target untouched.
            state.body.moving = true
        case .idle, .happy:
            // The JS original's final `else` branch — reached only by `.idle` in
            // practice (transitionToNextMode's weights never produce `.happy`;
            // `triggerHappy` sets `.happy` directly without going through startMode).
            state.body.moving = false
            state.memory.modeEndsAt = now + randomRange(Constants.modeDwellMsRange[.idle]!)
        }
    }

    func transitionToNextMode(state: inout AgentState, now: Double) {
        let next: Mode = weightedChoice(Constants.modeWeights, rngValue: rng.nextUnit())
        startMode(next, state: &state, now: now)
    }

    /// Shared by `startMode`'s wander/rest polite-bias branches — see `farthestIndex`
    /// (Math/Avoidance.swift) for the actual distance/tie-break logic.
    private func biasedIndex(anchor: Point, candidates: [Point]) -> Int {
        farthestIndex(anchor: anchor, candidates: candidates, rngValue: rng.nextUnit())
    }

    /// Which display a freshly-started wander/rest should target. Consumes the
    /// `screenSwitchProbability` draw ONLY when more than one screen is attached —
    /// single-display setups draw the exact same RNG sequence as before multi-screen
    /// support, keeping every seeded test byte-identical. On a switch, picks uniformly
    /// among the other screens (no draw needed when there's exactly one other).
    private func pickTargetScreenIndex(state: AgentState) -> Int {
        let screens = state.world.screens
        let current = nearestScreenIndex(to: state.body.position, screens: screens)
        guard screens.count > 1 else { return current }
        guard rng.nextUnit() < Constants.screenSwitchProbability else { return current }
        let others = screens.indices.filter { $0 != current }
        if others.count == 1 { return others[0] }
        return others[randomIndex(others.count)]
    }

    // MARK: - Attention avoidance (net-new, beyond blob.js parity — see
    // Behavior/Attention.swift, Math/Avoidance.swift)

    /// Reactive yield: preempts the current mode into `.flee` when the avatar overlaps
    /// `state.body.attentionZone` (the caret's keep-out zone) or when the cursor makes
    /// contact while the user is actively typing/scrolling. Gated on not dragging, not
    /// happy (a drag-drop bounce takes priority), and past `yieldCooldownUntil` (the
    /// short lockout set on flee arrival, so overlap re-checks don't thrash). Recomputes
    /// the escape target every tick these conditions hold — including while already
    /// `.flee` — so a caret that keeps moving re-aims the flight path.
    func maybeYield(state: inout AgentState, now: Double) {
        guard !state.body.dragging, state.body.mode != .happy, now >= state.memory.yieldCooldownUntil else { return }
        let avatarRect = Rect(origin: state.body.position, size: state.body.size)
        let zoneToEscape: Rect
        if let zone = state.body.attentionZone, rectsOverlap(avatarRect, zone) {
            zoneToEscape = zone
        } else if cursorContactShouldFlee(world: state.world, position: state.body.position, size: state.body.size) {
            zoneToEscape = Rect(origin: state.world.cursor, size: Size(width: 0, height: 0))
        } else {
            return
        }
        state.body.target = escapePoint(
            avatarPosition: state.body.position, avatarSize: state.body.size, zone: zoneToEscape,
            screen: nearestScreen(to: state.body.position, screens: state.world.screens),
            padding: Constants.escapePadding
        )
        startMode(.flee, state: &state, now: now)
    }

    func updateMovement(state: inout AgentState, dt: Double, now: Double) {
        guard state.body.moving else { return }
        let d = distance(
            ax: state.body.position.x, ay: state.body.position.y,
            bx: state.body.target.x, by: state.body.target.y
        )
        if d <= Constants.arriveThreshold {
            // Snap fully inside the target's nearest screen — belt-and-braces for a
            // target computed against a screen list that changed mid-glide (the
            // steady-state case is a no-op: wander/rest targets are already inset).
            state.body.position = confine(
                point: state.body.target, screens: state.world.screens, blobSize: state.body.size
            )
            state.body.moving = false
            let dwell = Constants.modeDwellMsRange[state.body.mode] ?? Constants.modeDwellMsRange[.idle]!
            state.memory.modeEndsAt = now + randomRange(dwell)
            if state.body.mode == .flee {
                // Beyond blob.js parity: short lockout before another overlap can
                // re-trigger .flee — see AgentMemory.yieldCooldownUntil's doc comment.
                state.memory.yieldCooldownUntil = now + Constants.yieldCooldownMs
            }
            return
        }
        // Beyond blob.js parity: fleeing is a deliberate scoot, faster than the calm
        // moveSpeed roam — see Constants.fleeSpeed's doc comment.
        let speed = state.body.mode == .flee ? Constants.fleeSpeed : Constants.moveSpeed
        let step = speed * dt
        let t = clamp(step / d, min: 0, max: 1)
        // Deliberately unclamped mid-glide: both endpoints live inside a screen, but the
        // straight line between two displays may cross a dead zone (non-aligned
        // monitors). Clamping each step would yank the avatar sideways along an edge;
        // letting it briefly leave all screens reads as a clean glide instead. Arrival
        // (above) and reconcilePosition (each tick) do the confinement.
        state.body.position = Point(
            x: lerp(state.body.position.x, state.body.target.x, t),
            y: lerp(state.body.position.y, state.body.target.y, t)
        )
    }

    /// Runs first in every non-dragging tick: keeps the avatar consistent with the
    /// current screen list (which Perception may have just changed under it — display
    /// unplugged, resolution changed). Not moving → position must sit fully inside its
    /// nearest screen (this is also the permanent below-the-edge fix). Moving → the
    /// position may legally be in a dead zone mid-glide, so only the *target* is
    /// re-clamped into a surviving screen.
    func reconcilePosition(state: inout AgentState) {
        let screens = state.world.screens
        if state.body.moving {
            state.body.target = confine(point: state.body.target, screens: screens, blobSize: state.body.size)
        } else {
            state.body.position = confine(point: state.body.position, screens: screens, blobSize: state.body.size)
        }
    }

    func maybeAdvanceMode(state: inout AgentState, now: Double) {
        guard !state.body.moving else { return }
        if now >= state.memory.modeEndsAt {
            transitionToNextMode(state: &state, now: now)
        }
    }

    // MARK: - Happy (drag-drop bounce)

    func triggerHappy(state: inout AgentState, now: Double) {
        if state.body.mode != .happy {
            state.memory.happyResumeMode = state.body.mode
        }
        state.body.mode = .happy
        state.memory.happyUntil = now + Constants.happyDurationMs
        state.body.moving = false
    }

    func updateHappy(state: inout AgentState, now: Double) {
        guard state.body.mode == .happy, now >= state.memory.happyUntil else { return }
        state.body.mode = state.memory.happyResumeMode
        // Constants.happyResumeDwellMsRange, NOT Constants.modeDwellMsRange[resumeMode] —
        // a distinct literal in the JS original, preserved exactly here.
        state.memory.modeEndsAt = now + randomRange(Constants.happyResumeDwellMsRange)
    }

    // MARK: - Blink

    /// `blinkEndsAt` stands in for the JS original's fire-and-forget
    /// `setTimeout(..., 120)` — see AgentMemory's doc comment. Turn off any blink
    /// that's finished before considering whether to start a new one.
    func updateBlink(state: inout AgentState, now: Double) {
        if state.memory.blinking && now >= state.memory.blinkEndsAt {
            state.memory.blinking = false
        }
        if now >= state.memory.nextBlinkAt {
            state.memory.blinking = true
            state.memory.blinkEndsAt = now + Constants.blinkActiveMs
            state.memory.nextBlinkAt = now + randomRange(Constants.blinkIntervalMsRange)
        }
    }

    // MARK: - Emotion triggers (quirks + proximity)
    // The priority ladder itself (computeDesiredEmotion) is a free function in
    // EmotionPriority.swift — it touches neither `rng` nor `clock`, so it doesn't need
    // to live on this class.

    func updateEmotionTriggers(state: inout AgentState, now: Double) {
        let idleAndAwake = !state.body.dragging && state.body.mode == .idle

        if idleAndAwake && now >= state.memory.quirkUntil && now >= state.memory.nextQuirkAt {
            state.memory.quirkEmotion = Constants.quirkEmotions[randomIndex(Constants.quirkEmotions.count)]
            let duration = randomRange(Constants.quirkDurationMsRange)
            state.memory.quirkUntil = now + duration
            state.memory.nextQuirkAt = now + duration + randomRange(Constants.quirkCooldownGapMsRange)
        }

        if idleAndAwake && now >= state.memory.proximityCooldownUntil {
            let centerX = state.body.position.x + state.body.size.width / 2
            let centerY = state.body.position.y + state.body.size.height / 2
            let d = distance(ax: state.world.cursor.x, ay: state.world.cursor.y, bx: centerX, by: centerY)
            if d < Constants.proximityRadius {
                state.memory.proximityUntil = now + Constants.proximityDurationMs
                state.memory.proximityCooldownUntil = now + randomRange(Constants.proximityCooldownMsRange)
            }
        }
    }
}
