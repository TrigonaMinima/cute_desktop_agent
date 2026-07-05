import Foundation

// Plain, AppKit-free 2D primitives — used everywhere in AgentCore instead of CGPoint/
// CGSize/CGVector so this target has zero Foundation-adjacent-framework dependency
// beyond Foundation itself. AgentApp is responsible for converting to/from CGPoint at
// the AppKit boundary (see Perception/CoordinateSpace.swift, Phase 5).

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Codable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Vector: Codable, Equatable {
    public var dx: Double
    public var dy: Double

    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }

    /// Euclidean length — used to turn a velocity vector into a scalar speed for
    /// threshold comparisons (see `AgentWorld.cursorMoving`). Delegates to the same
    /// `hypot` call `Geometry.distance` uses, rather than re-deriving the sqrt formula.
    public var magnitude: Double {
        Foundation.hypot(dx, dy)
    }
}

public struct Rect: Codable, Equatable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }
}
