import Foundation

// Mechanical port of electron-poc/renderer/blob.js lines 25-85. All helpers treat
// `point`/the returned Point as the avatar's top-left corner (web space: top-left
// origin, y grows down) — the same convention as the rest of AgentCore. Y-flip to
// AppKit's bottom-left coordinate space happens only in AgentApp's
// Perception/CoordinateSpace.swift, never here.

public struct InnerBounds: Equatable {
    public let maxX: Double
    public let maxY: Double
}

/// The valid range for the avatar's top-left corner, `margin` px inset from the
/// screen edges on every side (subtracting `blobSize` from the far edge — otherwise a
/// "bottom-right corner" target would sit almost entirely off-screen).
public func innerBounds(bounds: Size, margin: Double, blobSize: Size) -> InnerBounds {
    InnerBounds(
        maxX: bounds.width - margin - blobSize.width,
        maxY: bounds.height - margin - blobSize.height
    )
}

public func pickCorner(bounds: Size, margin: Double, blobSize: Size, cornerIndex: Int) -> Point {
    let inner = innerBounds(bounds: bounds, margin: margin, blobSize: blobSize)
    let corners = [
        Point(x: margin, y: margin),
        Point(x: inner.maxX, y: margin),
        Point(x: margin, y: inner.maxY),
        Point(x: inner.maxX, y: inner.maxY),
    ]
    return corners[cornerIndex % corners.count]
}

/// A point that hugs one edge within a shallow `bandDepth` band, so the agent tends to
/// settle along the border of the screen instead of over the middle of the work area.
public func pickBorderPoint(
    bounds: Size, margin: Double, blobSize: Size, bandDepth: Double,
    edgeIndex: Int, rngAlong: Double, rngDepth: Double
) -> Point {
    let inner = innerBounds(bounds: bounds, margin: margin, blobSize: blobSize)
    let along = { (min: Double, max: Double) in lerp(min, max, rngAlong) }
    let depth = { (min: Double, max: Double) in lerp(min, max, rngDepth) }

    let bands = [
        Point(x: along(margin, inner.maxX), y: depth(margin, margin + bandDepth)), // top strip
        Point(x: along(margin, inner.maxX), y: depth(inner.maxY - bandDepth, inner.maxY)), // bottom strip
        Point(x: depth(margin, margin + bandDepth), y: along(margin, inner.maxY)), // left strip
        Point(x: depth(inner.maxX - bandDepth, inner.maxX), y: along(margin, inner.maxY)), // right strip
    ]
    return bands[edgeIndex % bands.count]
}

/// A mostly-offscreen point hugging one edge, so the avatar can "peek" back in — but a
/// slice of it (`peekVisible`) always stays on-screen.
public func pickEdgeTarget(bounds: Size, blobSize: Size, edgeIndex: Int, rngAlong: Double) -> Point {
    let peekVisibleX = blobSize.width * 0.4
    let peekVisibleY = blobSize.height * 0.4
    let edges = [
        Point(x: lerp(0, bounds.width - blobSize.width, rngAlong), y: -blobSize.height + peekVisibleY), // top
        Point(x: lerp(0, bounds.width - blobSize.width, rngAlong), y: bounds.height - peekVisibleY), // bottom
        Point(x: -blobSize.width + peekVisibleX, y: lerp(0, bounds.height - blobSize.height, rngAlong)), // left
        Point(x: bounds.width - peekVisibleX, y: lerp(0, bounds.height - blobSize.height, rngAlong)), // right
    ]
    return edges[edgeIndex % edges.count]
}

/// Last-resort safety net: whatever produced `point`, guarantee at least `minVisible`
/// px of the avatar stays on-screen on every axis.
public func clampVisible(point: Point, bounds: Size, blobSize: Size, minVisible: Double) -> Point {
    Point(
        x: clamp(point.x, min: -(blobSize.width - minVisible), max: bounds.width - minVisible),
        y: clamp(point.y, min: -(blobSize.height - minVisible), max: bounds.height - minVisible)
    )
}
