import Foundation

/// Per-frame squash/stretch scale + vertical bob for the avatar body. The transform math
/// is carried over unchanged from electron-poc/renderer/blob.js's `render()`. A pure
/// function of `(state, now)` — like `computeDesiredEmotion` — so it needs no injected
/// Clock and is fully unit-testable; the AppKit render layer calls this every tick and
/// applies the result to the body layer's `transform`.
public struct BodyMotion: Equatable {
    public var scaleX: Double
    public var scaleY: Double
    public var bobY: Double
    /// Unit-clamped look direction for pupil deflection (see `GazeSystem.direction`).
    /// Zero when no mind is driving — the classic brain's eyes stay centered, exactly
    /// as before the emergent path landed. Carried here rather than read from
    /// `state.mind` in the render layer, so `AvatarView` stays brain-agnostic and the
    /// value is computed once per frame, not once per panel.
    public var gazeDirection: Vector = Vector(dx: 0, dy: 0)
}

/// Branch priority mirrors blob.js exactly: dragging > happy mode > moving > idle
/// breathing. `now` and `state.memory.happyUntil` are both in ms (matches
/// `performance.now()`); `wobble` is computed from `now/1000` seconds, per the JS source.
public func computeBodyMotion(state: AgentState, now: Double) -> BodyMotion {
    let wobble = sin(now / 1000 * Constants.wobbleFrequency)
    let bobY = (state.body.dragging || state.body.mode == .happy) ? 0 : wobble * Constants.bobAmplitude

    let scaleX: Double
    let scaleY: Double
    if state.body.dragging {
        scaleX = Constants.dragScale.x
        scaleY = Constants.dragScale.y
    } else if let mind = state.mind {
        // Emergent path: deformation is the physics spring's state, excited by real
        // acceleration (design doc layer 7 — no canned move-squash clip), composed
        // with the same idle breathing wobble so a settled body still reads alive.
        scaleX = 1 - wobble * Constants.idleWobbleScaleX + mind.physics.squash.dx
        scaleY = 1 + wobble * Constants.idleWobbleScaleY + mind.physics.squash.dy
    } else if state.body.mode == .happy {
        let progress = clamp(1 - (state.memory.happyUntil - now) / Constants.happyDurationMs, min: 0, max: 1)
        let bounce = sin(progress * Double.pi * 3) * (1 - progress)
        scaleY = 1 + bounce * Constants.happyBounceScaleY
        scaleX = 1 - bounce * Constants.happyBounceScaleX
    } else if state.body.moving {
        scaleX = Constants.movingScale.x
        scaleY = Constants.movingScale.y
    } else {
        scaleY = 1 + wobble * Constants.idleWobbleScaleY
        scaleX = 1 - wobble * Constants.idleWobbleScaleX
    }

    let gazeDirection = state.mind?.gaze
        .direction(from: center(of: Rect(origin: state.body.position, size: state.body.size)))
        ?? Vector(dx: 0, dy: 0)

    return BodyMotion(scaleX: scaleX, scaleY: scaleY, bobY: bobY, gazeDirection: gazeDirection)
}
