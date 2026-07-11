import Foundation

/// Steering behaviors (design doc layer 7): pure functions producing forces (px/s²,
/// unit mass) for the `FixedStepper` to integrate. All use the desired-velocity model —
/// each behavior states the velocity it *wants*, and the force is the gain-scaled gap
/// between that and the current velocity — so behaviors compose by force addition and
/// character comes out of the physics, never from authored position lerps (decision
/// log D12). Positions are avatar top-left in web space, matching `PhysicsBody`.
public enum Steering {

    /// Move toward `target` at full speed, ramping desired speed down linearly inside
    /// `MindConstants.arriveSlowRadius` — at the target the desired velocity is zero, so
    /// any leftover momentum produces a braking force rather than an orbit.
    public static func arrive(
        position: Point, velocity: Vector, target: Point, maxSpeed: Double
    ) -> Vector {
        let gap = distance(position, target)
        guard gap > 0 else {
            return steer(desired: Vector(dx: 0, dy: 0), current: velocity)
        }
        let speed = maxSpeed * min(1, gap / MindConstants.arriveSlowRadius)
        return steer(
            desired: Vector(
                dx: (target.x - position.x) / gap * speed,
                dy: (target.y - position.y) / gap * speed
            ),
            current: velocity
        )
    }

    /// Full speed straight away from `threat`. A threat exactly on top of us has no
    /// away-direction, so it falls back to fleeing upward — better a fixed dash than a
    /// frozen blob under the cursor.
    public static func flee(
        position: Point, velocity: Vector, threat: Point, maxSpeed: Double
    ) -> Vector {
        let gap = distance(threat, position)
        guard gap > 0 else {
            return steer(desired: Vector(dx: 0, dy: -maxSpeed), current: velocity)
        }
        return steer(
            desired: Vector(
                dx: (position.x - threat.x) / gap * maxSpeed,
                dy: (position.y - threat.y) / gap * maxSpeed
            ),
            current: velocity
        )
    }

    /// Inward push when the avatar's box sits within `MindConstants.edgeAvoidMargin` of
    /// a `screen` edge, growing quadratically toward the edge. A raw force, not a
    /// desired velocity: it composes additively with whatever behavior is active, and
    /// the hard `Screens.confine` clamp downstream stays the true safety net.
    public static func avoidEdges(position: Point, size: Size, screen: Rect) -> Vector {
        let margin = MindConstants.edgeAvoidMargin
        func push(_ distanceToEdge: Double) -> Double {
            let penetration = margin - distanceToEdge
            guard penetration > 0 else { return 0 }
            let fraction = min(1, penetration / margin)
            return MindConstants.edgeAvoidStrength * fraction * fraction
        }
        let left = position.x - screen.origin.x
        let right = screen.origin.x + screen.size.width - (position.x + size.width)
        let top = position.y - screen.origin.y
        let bottom = screen.origin.y + screen.size.height - (position.y + size.height)
        return Vector(dx: push(left) - push(right), dy: push(top) - push(bottom))
    }

    /// Desired-velocity model: the force is the gap to the wanted velocity, scaled by
    /// the shared responsiveness gain.
    static func steer(desired: Vector, current: Vector) -> Vector {
        Vector(
            dx: (desired.dx - current.dx) * MindConstants.steeringGain,
            dy: (desired.dy - current.dy) * MindConstants.steeringGain
        )
    }
}

/// The one stateful steering behavior: a heading that random-walks smoothly, producing
/// a constant-magnitude amble force along it. Persisting the heading between ticks is
/// what makes the path curve organically instead of jittering — the classic Reynolds
/// wander, minus the projection-circle bookkeeping.
public struct WanderState: Codable, Equatable {
    /// Radians, web space (0 = +x, positive turns clockwise since y grows downward).
    public var heading: Double

    public init(heading: Double) {
        self.heading = heading
    }

    /// Drifts the heading by one bounded random turn and returns the amble force.
    public mutating func steer(rng: RandomProvider, dt: Double) -> Vector {
        let jitter = (rng.nextUnit() * 2 - 1) * MindConstants.wanderJitterRadiansPerSecond
        heading += jitter * dt
        return Vector(
            dx: cos(heading) * MindConstants.wanderStrength,
            dy: sin(heading) * MindConstants.wanderStrength
        )
    }
}
