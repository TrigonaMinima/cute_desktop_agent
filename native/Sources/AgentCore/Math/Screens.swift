import Foundation

// Multi-screen geometry. Screens live in global web space (top-left origin, y-down,
// flipped against the primary display's height at the AppKit boundary), so a secondary
// display's rect routinely has a non-zero — even negative — origin. Every rect here is
// a display's *visibleFrame* (dock and menu bar excluded): confinement to it is what
// keeps the avatar from sinking below the dock.

/// One attached display as the behavior core sees it. `frame` is the display's
/// visibleFrame in global web space; `name` is the display's localized name, carried
/// for `StatusSummary` only. Index 0 in any `[ScreenInfo]` is the primary display,
/// and the array is never empty (Perception guarantees a last-known-good fallback).
public struct ScreenInfo: Codable, Equatable {
    public var frame: Rect
    public var name: String

    public init(frame: Rect, name: String) {
        self.frame = frame
        self.name = name
    }
}

/// The index of the screen whose frame contains `point`, or nil if it lies in a dead
/// zone between displays. Origin edges are inclusive, far edges exclusive, so a point
/// on the seam of two flush-adjacent screens belongs to exactly one of them.
public func screenIndex(containing point: Point, screens: [ScreenInfo]) -> Int? {
    screens.firstIndex { screen in
        let f = screen.frame
        return point.x >= f.origin.x && point.x < f.origin.x + f.size.width
            && point.y >= f.origin.y && point.y < f.origin.y + f.size.height
    }
}

/// The index of the screen `point` belongs to: containment wins outright; otherwise
/// the screen with the smallest distance from `point` to its clamped-into-rect
/// counterpart, ties resolving to the lower index. Total (never nil) because
/// `screens` is never empty — this is what re-homes the avatar after a display
/// disappears mid-glide or mid-rest.
public func nearestScreenIndex(to point: Point, screens: [ScreenInfo]) -> Int {
    if let contained = screenIndex(containing: point, screens: screens) {
        return contained
    }
    var bestIndex = 0
    var bestDistance = Double.infinity
    for (index, screen) in screens.enumerated() {
        let f = screen.frame
        let clampedX = clamp(point.x, min: f.origin.x, max: f.origin.x + f.size.width)
        let clampedY = clamp(point.y, min: f.origin.y, max: f.origin.y + f.size.height)
        let d = distance(ax: point.x, ay: point.y, bx: clampedX, by: clampedY)
        if d < bestDistance {
            bestDistance = d
            bestIndex = index
        }
    }
    return bestIndex
}

/// `nearestScreenIndex` resolved to its `ScreenInfo` — for callers that need the
/// screen itself, not its position in the list.
public func nearestScreen(to point: Point, screens: [ScreenInfo]) -> ScreenInfo {
    screens[nearestScreenIndex(to: point, screens: screens)]
}

/// Homes a point: resolves the screen `point` belongs to and clamps the blob fully
/// inside it, in one call. This is THE confinement operation for the common case where
/// the same point both picks the screen and gets clamped — sites that pick the screen
/// from a different point (drag clamps the blob into the *cursor's* screen) compose
/// `nearestScreen` + `clampToScreen` explicitly instead.
public func confine(point: Point, screens: [ScreenInfo], blobSize: Size) -> Point {
    clampToScreen(point: point, screen: nearestScreen(to: point, screens: screens), blobSize: blobSize)
}

/// Full confinement: the avatar's top-left corner clamped so the whole `blobSize`
/// footprint sits inside `screen`'s frame — zero off-screen tolerance (this replaced
/// the old `clampVisible` and its `minVisible` slack, the source of the below-edge
/// bug). If the blob is larger than the screen on an axis, it pins to the screen's
/// origin rather than oscillating between an inverted min/max pair.
public func clampToScreen(point: Point, screen: ScreenInfo, blobSize: Size) -> Point {
    let f = screen.frame
    let maxX = Swift.max(f.origin.x, f.origin.x + f.size.width - blobSize.width)
    let maxY = Swift.max(f.origin.y, f.origin.y + f.size.height - blobSize.height)
    return Point(
        x: clamp(point.x, min: f.origin.x, max: maxX),
        y: clamp(point.y, min: f.origin.y, max: maxY)
    )
}
