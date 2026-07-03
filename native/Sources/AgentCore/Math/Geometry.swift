import Foundation

// Mechanical port of the pure helpers in electron-poc/renderer/blob.js (lines 1-23).
// No Date.now()/Math.random() inside — RNG is always injected as an argument, which is
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
