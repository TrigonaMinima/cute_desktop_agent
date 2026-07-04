import Foundation

/// Per-frame squash/stretch scale + vertical bob, mechanically ported from
/// electron-poc/renderer/blob.js's `render()` transform math. A pure function of
/// `(state, now)` — like `computeDesiredEmotion` — so it needs no injected Clock and is
/// fully unit-testable; the AppKit render layer calls this every tick and applies the
/// result to the body layer's `transform`.
public struct BodyMotion: Equatable {
    public var scaleX: Double
    public var scaleY: Double
    public var bobY: Double
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

    return BodyMotion(scaleX: scaleX, scaleY: scaleY, bobY: bobY)
}
