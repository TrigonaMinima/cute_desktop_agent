import Foundation

// Pure geometry and weighted-selection helpers used throughout the behavior core.
// Ported unchanged from electron-poc/renderer/blob.js (lines 1-23). No
// Date.now()/Math.random() inside — RNG is always injected as an argument, which is
// what makes these (and everything built on top of them) unit-testable.

public func clamp(_ value: Double, min: Double, max: Double) -> Double {
    Swift.min(max, Swift.max(min, value))
}

public func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

public func distance(ax: Double, ay: Double, bx: Double, by: Double) -> Double {
    Foundation.hypot(bx - ax, by - ay)
}

public func distance(_ a: Point, _ b: Point) -> Double {
    distance(ax: a.x, ay: a.y, bx: b.x, by: b.y)
}

/// Picks a key from `weights` proportionally to its weight, given `rngValue` in [0, 1].
///
/// `weights` is an ordered array of (key, weight) pairs rather than a Dictionary — this
/// mirrors the JS original's `Object.entries()` insertion-order iteration, which the
/// tie-breaking rule (`target <= acc`) depends on: ties resolve to whichever key's
/// cumulative weight reaches the target first, in table order.
public func weightedChoice<Key>(_ weights: [(Key, Double)], rngValue: Double) -> Key {
    let total = weights.reduce(0) { $0 + $1.1 }
    var acc = 0.0
    let target = rngValue * total
    for (key, weight) in weights {
        acc += weight
        if target <= acc {
            return key
        }
    }
    return weights[0].0
}

/// Cursor-within-avatar-bounds hit-test — mechanical port of blob.js's
/// `updateHoverState`'s `withinX`/`withinY` inequalities (both edges inclusive).
/// `position` is the avatar's top-left corner. Pure geometry only; toggling
/// `ignoresMouseEvents` from the result is an AppKit side effect wired in Phase 5.
public func isHovering(cursor: Point, position: Point, size: Size) -> Bool {
    let withinX = cursor.x >= position.x && cursor.x <= position.x + size.width
    let withinY = cursor.y >= position.y && cursor.y <= position.y + size.height
    return withinX && withinY
}

/// Cursor velocity in px/sec, web space — a derived perceived signal, not something read
/// directly from the OS (macOS has no cursor-velocity API). `dt` is the frame delta in
/// seconds, matching `Constants.moveSpeed`'s px/sec convention. Guards `dt <= 0` (the
/// first poll with no prior frame, or FrameClock's `[0, 0.1]` floor) to zero rather than
/// dividing by zero/negative and producing NaN or a sign-flipped spike.
public func cursorVelocity(from previous: Point, to current: Point, dt: Double) -> Vector {
    guard dt > 0 else { return Vector(dx: 0, dy: 0) }
    return Vector(dx: (current.x - previous.x) / dt, dy: (current.y - previous.y) / dt)
}

/// Overload for callers that already have a displacement rather than two positions to
/// diff — e.g. `Perception`'s accumulated scroll delta. Delegates to the point-based
/// overload above so the `dt <= 0` guard lives in exactly one place.
public func cursorVelocity(from delta: Vector, dt: Double) -> Vector {
    cursorVelocity(from: Point(x: 0, y: 0), to: Point(x: delta.dx, y: delta.dy), dt: dt)
}

/// Whether a keystroke that happened `lastKeystrokeAt` still counts as "typing right now"
/// at `now` — a derived perceived signal, the typing analog of `cursorVelocity` just
/// above: raw primitives in, no `AgentState` touched, feeding `AgentWorld.typing`.
///
/// `lastKeystrokeAt == 0` is the "no keystroke observed yet" baseline (mirrors
/// `AgentApp.Perception`'s `lastCursor == nil` case) and always reads as not-typing,
/// rather than as "typed at time zero."
public func isTypingActive(lastKeystrokeAt: Double, now: Double, timeoutMs: Double) -> Bool {
    guard lastKeystrokeAt > 0 else { return false }
    return now - lastKeystrokeAt < timeoutMs
}

/// Whether a scroll-wheel event that happened `lastScrollAt` still counts as "scrolling
/// right now" at `now` — the scroll analog of `isTypingActive`: scroll events arrive in
/// discrete bursts (trackpad phases + momentum), so this smooths over the gaps between
/// them rather than flickering false between every event, feeding `AgentWorld.scrolling`.
///
/// `lastScrollAt == 0` is the "no scroll observed yet" baseline (mirrors
/// `isTypingActive`'s `lastKeystrokeAt == 0` case) and always reads as not-scrolling,
/// rather than as "scrolled at time zero."
public func isScrollActive(lastScrollAt: Double, now: Double, timeoutMs: Double) -> Bool {
    guard lastScrollAt > 0 else { return false }
    return now - lastScrollAt < timeoutMs
}
