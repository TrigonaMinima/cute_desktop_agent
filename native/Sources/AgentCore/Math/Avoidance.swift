import Foundation

// Net-new, beyond blob.js parity: pure geometry backing the attention-avoidance behavior
// described in CLAUDE.md's movement-brain plan (see Behavior/Attention.swift for the
// signal-to-zone side). No rng/clock here — mirrors TargetPicking.swift's pure-helper
// style and coordinate convention: `Point`/`Rect` origins are the avatar's top-left
// corner, web space (top-left origin, y grows down).

/// AABB overlap test — true when `a` and `b` share any area. Touching edges only (no
/// area in common) do not count as overlap, matching the strict `<`/`>` comparisons.
public func rectsOverlap(_ a: Rect, _ b: Rect) -> Bool {
    a.origin.x < b.origin.x + b.size.width &&
        a.origin.x + a.size.width > b.origin.x &&
        a.origin.y < b.origin.y + b.size.height &&
        a.origin.y + a.size.height > b.origin.y
}

/// The nearest on-screen point (avatar's top-left corner) that clears `zone` by `padding`
/// px, starting from `avatarPosition`. Tries the four "just past the zone" positions
/// (left/right/up/down), keeps whichever still clears the zone after `clampVisible`'s
/// on-screen floor is applied, and returns the smallest move. If none of the four
/// candidates clears the zone after clamping (e.g. a zone spanning the whole screen),
/// falls back to whichever clamped candidate ends up farthest from the zone's center —
/// maximum clearance rather than an arbitrary pick.
public func escapePoint(
    avatarPosition: Point, avatarSize: Size, zone: Rect, bounds: Size,
    padding: Double, minVisible: Double
) -> Point {
    let rawCandidates = [
        Point(x: zone.origin.x - padding - avatarSize.width, y: avatarPosition.y), // left
        Point(x: zone.origin.x + zone.size.width + padding, y: avatarPosition.y), // right
        Point(x: avatarPosition.x, y: zone.origin.y - padding - avatarSize.height), // up
        Point(x: avatarPosition.x, y: zone.origin.y + zone.size.height + padding), // down
    ]
    let clamped = rawCandidates.map {
        clampVisible(point: $0, bounds: bounds, blobSize: avatarSize, minVisible: minVisible)
    }
    let clearing = clamped.filter { !rectsOverlap(Rect(origin: $0, size: avatarSize), zone) }

    if !clearing.isEmpty {
        return clearing.min {
            distance(ax: avatarPosition.x, ay: avatarPosition.y, bx: $0.x, by: $0.y)
                < distance(ax: avatarPosition.x, ay: avatarPosition.y, bx: $1.x, by: $1.y)
        }!
    }

    // Fallback: nothing clears the zone even after clamping. Push toward whichever
    // clamped candidate is farthest from the zone's center — maximum clearance available.
    let zoneCenter = Point(x: zone.origin.x + zone.size.width / 2, y: zone.origin.y + zone.size.height / 2)
    return clamped.max {
        distance(ax: zoneCenter.x, ay: zoneCenter.y, bx: $0.x, by: $0.y)
            < distance(ax: zoneCenter.x, ay: zoneCenter.y, bx: $1.x, by: $1.y)
    }!
}

/// Picks the index into `candidates` whose point is farthest from `anchor` — the "polite"
/// bias for wander/rest/peek target-picking, replacing a uniform `randomIndex` so the
/// agent tends to settle away from the user's current activity. Ties are broken by
/// `rngValue` (uniform in [0, 1]) so behavior stays deterministic under test.
public func farthestIndex(anchor: Point, candidates: [Point], rngValue: Double) -> Int {
    let distances = candidates.map { distance(ax: anchor.x, ay: anchor.y, bx: $0.x, by: $0.y) }
    let maxDistance = distances.max() ?? 0
    let farthestIndices = distances.indices.filter { distances[$0] == maxDistance }
    let tieBreak = Int(rngValue * Double(farthestIndices.count))
    return farthestIndices[Swift.min(tieBreak, farthestIndices.count - 1)]
}
