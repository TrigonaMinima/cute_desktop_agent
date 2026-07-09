import Foundation

// Target-picking geometry for wander/rest — corner and border point selection within
// one screen's rect. Ported from electron-poc/renderer/blob.js (lines 25-85), then
// generalized from a size-anchored-at-origin to a `Rect`: secondary displays have
// non-zero origins in global web space, so every inset is relative to `screen.origin`,
// not (0, 0). All helpers treat `point`/the returned Point as the avatar's top-left
// corner (web space: top-left origin, y grows down) — the same convention as the rest
// of AgentCore. Y-flip to AppKit's bottom-left coordinate space happens only in
// AgentApp's Perception/CoordinateSpace.swift, never here.

public struct InnerBounds: Equatable {
    public let minX: Double
    public let minY: Double
    public let maxX: Double
    public let maxY: Double
}

/// The valid range for the avatar's top-left corner, `margin` px inset from the
/// screen's edges on every side (subtracting `blobSize` from the far edges — otherwise
/// a "bottom-right corner" target would sit almost entirely off-screen).
public func innerBounds(screen: Rect, margin: Double, blobSize: Size) -> InnerBounds {
    InnerBounds(
        minX: screen.origin.x + margin,
        minY: screen.origin.y + margin,
        maxX: screen.origin.x + screen.size.width - margin - blobSize.width,
        maxY: screen.origin.y + screen.size.height - margin - blobSize.height
    )
}

public func pickCorner(screen: Rect, margin: Double, blobSize: Size, cornerIndex: Int) -> Point {
    let inner = innerBounds(screen: screen, margin: margin, blobSize: blobSize)
    let corners = [
        Point(x: inner.minX, y: inner.minY),
        Point(x: inner.maxX, y: inner.minY),
        Point(x: inner.minX, y: inner.maxY),
        Point(x: inner.maxX, y: inner.maxY),
    ]
    return corners[cornerIndex % corners.count]
}

/// A point that hugs one edge within a shallow `bandDepth` band, so the agent tends to
/// settle along the border of the screen instead of over the middle of the work area.
public func pickBorderPoint(
    screen: Rect, margin: Double, blobSize: Size, bandDepth: Double,
    edgeIndex: Int, rngAlong: Double, rngDepth: Double
) -> Point {
    let inner = innerBounds(screen: screen, margin: margin, blobSize: blobSize)
    let along = { (min: Double, max: Double) in lerp(min, max, rngAlong) }
    let depth = { (min: Double, max: Double) in lerp(min, max, rngDepth) }

    let bands = [
        Point(x: along(inner.minX, inner.maxX), y: depth(inner.minY, inner.minY + bandDepth)), // top strip
        Point(x: along(inner.minX, inner.maxX), y: depth(inner.maxY - bandDepth, inner.maxY)), // bottom strip
        Point(x: depth(inner.minX, inner.minX + bandDepth), y: along(inner.minY, inner.maxY)), // left strip
        Point(x: depth(inner.maxX - bandDepth, inner.maxX), y: along(inner.minY, inner.maxY)), // right strip
    ]
    return bands[edgeIndex % bands.count]
}
