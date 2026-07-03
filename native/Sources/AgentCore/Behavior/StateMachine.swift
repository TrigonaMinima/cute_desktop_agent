import Foundation

// Mechanical port of the runtime behavior in electron-poc/renderer/blob.js (lines
// ~90-431): startMode, transitionToNextMode, updateMovement, maybeAdvanceMode,
// triggerHappy/updateHappy, updateBlink, updateEmotionTriggers/computeDesiredEmotion,
// and the mousedown/mousemove/mouseup drag handlers.
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
        if !state.body.dragging {
            updateHappy(state: &state, now: now)
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
                proximityCooldownUntil: 0
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
        switch mode {
        case .wander:
            let edgeIndex = randomIndex(4)
            let rngAlong = rng.nextUnit()
            let rngDepth = rng.nextUnit()
            state.body.target = pickBorderPoint(
                bounds: state.world.screenBounds, margin: Constants.roamMargin, blobSize: state.body.size,
                bandDepth: Constants.borderBandDepth, edgeIndex: edgeIndex, rngAlong: rngAlong, rngDepth: rngDepth
            )
            state.body.moving = true
        case .rest:
            let cornerIndex = randomIndex(4)
            state.body.target = pickCorner(
                bounds: state.world.screenBounds, margin: Constants.restMargin, blobSize: state.body.size,
                cornerIndex: cornerIndex
            )
            state.body.moving = true
        case .peek:
            let edgeIndex = randomIndex(4)
            let rngAlong = rng.nextUnit()
            state.body.target = pickEdgeTarget(
                bounds: state.world.screenBounds, blobSize: state.body.size, edgeIndex: edgeIndex, rngAlong: rngAlong
            )
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
            return
        }
        let step = Constants.moveSpeed * dt
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
