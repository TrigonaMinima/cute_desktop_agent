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
    /// position itself via `updateDrag`), then blink and emotion — both of which keep
    /// running even mid-drag, matching the JS original's unconditional tail of `tick()`.
    public func tick(state: inout AgentState, dt: Double) {
        let now = clock.now()
        // Net-new, beyond blob.js parity: derive the region to avoid every tick, even
        // while dragging — it's surfaced in the menu/status rows regardless, and
        // `maybeYield` below is what actually gates the reaction on not-dragging.
        state.body.attentionZone = attentionZone(from: state.world)
        if !state.body.dragging {
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
    public func makeInitialState(bounds: Size, avatarSize: Size, now: Double) -> AgentState {
        let center = Point(x: bounds.width / 2, y: bounds.height / 2)
        return AgentState(
            world: AgentWorld(screenBounds: bounds, cursor: center),
            body: AgentBody(
                position: center, mode: .idle, target: center, moving: false, emotion: .neutral,
                dragging: false, dragOffset: Vector(dx: 0, dy: 0), size: avatarSize
            ),
            memory: AgentMemory(
                modeEndsAt: now + Constants.initialModeEndsAtDelayMs,
                happyUntil: 0,
                happyResumeMode: .idle,
                pendingReturn: false,
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

    /// Hard-clamped to `[0, bounds - blobSize]` — deliberately NOT `clampVisible`'s
    /// off-screen-tolerant floor. While actively dragged the avatar must stay fully
    /// on-screen; `clampVisible`'s negative floor is only for programmatic movement.
    public func updateDrag(state: inout AgentState) {
        let bounds = state.world.screenBounds
        let size = state.body.size
        let rawX = state.world.cursor.x - state.body.dragOffset.dx
        let rawY = state.world.cursor.y - state.body.dragOffset.dy
        state.body.position = Point(
            x: clamp(rawX, min: 0, max: bounds.width - size.width),
            y: clamp(rawY, min: 0, max: bounds.height - size.height)
        )
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
        // by wander/rest/peek below via `biasedIndex`, each picks the edge/corner farthest
        // from the current activity anchor instead of a uniform index.
        let anchor = activityAnchor(from: state.world)
        switch mode {
        case .wander:
            let edgeCandidates = (0..<4).map {
                pickBorderPoint(
                    bounds: state.world.screenBounds, margin: Constants.roamMargin, blobSize: state.body.size,
                    bandDepth: Constants.borderBandDepth, edgeIndex: $0, rngAlong: 0.5, rngDepth: 0.5
                )
            }
            let edgeIndex = biasedIndex(anchor: anchor, candidates: edgeCandidates)
            let rngAlong = rng.nextUnit()
            let rngDepth = rng.nextUnit()
            state.body.target = pickBorderPoint(
                bounds: state.world.screenBounds, margin: Constants.roamMargin, blobSize: state.body.size,
                bandDepth: Constants.borderBandDepth, edgeIndex: edgeIndex, rngAlong: rngAlong, rngDepth: rngDepth
            )
            state.body.moving = true
        case .rest:
            // Corners have no randomness of their own, so the candidates themselves are
            // the four possible final targets.
            let cornerCandidates = (0..<4).map {
                pickCorner(
                    bounds: state.world.screenBounds, margin: Constants.restMargin, blobSize: state.body.size,
                    cornerIndex: $0
                )
            }
            state.body.target = cornerCandidates[biasedIndex(anchor: anchor, candidates: cornerCandidates)]
            state.body.moving = true
        case .peek:
            let edgeCandidates = (0..<4).map {
                pickEdgeTarget(bounds: state.world.screenBounds, blobSize: state.body.size, edgeIndex: $0, rngAlong: 0.5)
            }
            let edgeIndex = biasedIndex(anchor: anchor, candidates: edgeCandidates)
            let rngAlong = rng.nextUnit()
            state.body.target = pickEdgeTarget(
                bounds: state.world.screenBounds, blobSize: state.body.size, edgeIndex: edgeIndex, rngAlong: rngAlong
            )
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

    /// Shared by `startMode`'s wander/rest/peek polite-bias branches — see `farthestIndex`
    /// (Math/Avoidance.swift) for the actual distance/tie-break logic.
    private func biasedIndex(anchor: Point, candidates: [Point]) -> Int {
        farthestIndex(anchor: anchor, candidates: candidates, rngValue: rng.nextUnit())
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
            bounds: state.world.screenBounds, padding: Constants.escapePadding, minVisible: Constants.minVisible
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
            let safeTarget = clampVisible(
                point: state.body.target, bounds: state.world.screenBounds, blobSize: state.body.size,
                minVisible: Constants.minVisible
            )
            state.body.position = safeTarget
            state.body.moving = false
            let dwell = Constants.modeDwellMsRange[state.body.mode] ?? Constants.modeDwellMsRange[.idle]!
            state.memory.modeEndsAt = now + randomRange(dwell)
            if state.body.mode == .peek {
                state.memory.pendingReturn = true
            }
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
        state.body.position = Point(
            x: lerp(state.body.position.x, state.body.target.x, t),
            y: lerp(state.body.position.y, state.body.target.y, t)
        )
        state.body.position = clampVisible(
            point: state.body.position, bounds: state.world.screenBounds, blobSize: state.body.size,
            minVisible: Constants.minVisible
        )
    }

    func maybeAdvanceMode(state: inout AgentState, now: Double) {
        guard !state.body.moving else { return }
        if state.body.mode == .peek && state.memory.pendingReturn && now >= state.memory.modeEndsAt {
            state.memory.pendingReturn = false
            startMode(.wander, state: &state, now: now)
            return
        }
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
