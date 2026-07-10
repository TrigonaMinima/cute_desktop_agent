import Foundation

/// The emergent brain's motor body (design doc layer 7): a unit-mass point integrated at
/// a fixed timestep, plus a spring-damper deformation state (`squash`) excited by real
/// acceleration. Expression is a side effect of forces — there is no "happy bounce"
/// clip; the render layer maps `squash` to scale, and it looks different every time
/// because it follows actual acceleration.
///
/// `position` is the avatar's top-left corner in web space, same convention as
/// `AgentBody.position`, so the render/hit-test seams need no translation.
public struct PhysicsBody: Codable, Equatable {
    public var position: Point
    /// px/sec, web space.
    public var velocity: Vector
    /// Dimensionless deformation state per axis (0 = relaxed). The render layer maps
    /// this to squash/stretch scale; the spring in `FixedStepper` keeps it near zero.
    public var squash: Vector
    public var squashVelocity: Vector

    public init(position: Point) {
        self.position = position
        velocity = Vector(dx: 0, dy: 0)
        squash = Vector(dx: 0, dy: 0)
        squashVelocity = Vector(dx: 0, dy: 0)
    }
}

/// Fixed-timestep integrator (decision log D7: 120 Hz): accumulates variable frame
/// deltas and advances the body in exact `MindConstants.physicsStepSeconds` substeps,
/// carrying the remainder — so the same inputs produce the same trajectory regardless
/// of how the display slices time. The applied force is held constant across one
/// frame's substeps; it changes at most once per display frame anyway.
public struct FixedStepper: Codable, Equatable {
    public private(set) var accumulator: Double = 0

    public init() {}

    /// Advances `body` by `frameDt` seconds under `force` (px/s², unit mass), capping
    /// speed at `maxSpeed`. Negative or zero `frameDt` is a no-op.
    public mutating func advance(
        _ body: inout PhysicsBody, force: Vector, maxSpeed: Double, frameDt: Double
    ) {
        guard frameDt > 0 else { return }
        accumulator += frameDt
        let h = MindConstants.physicsStepSeconds
        while accumulator >= h {
            accumulator -= h
            substep(&body, force: force, maxSpeed: maxSpeed, h: h)
        }
    }

    private func substep(_ body: inout PhysicsBody, force: Vector, maxSpeed: Double, h: Double) {
        // Unit mass: acceleration = applied force minus linear drag.
        let ax = force.dx - MindConstants.linearDampingPerSecond * body.velocity.dx
        let ay = force.dy - MindConstants.linearDampingPerSecond * body.velocity.dy

        body.velocity.dx += ax * h
        body.velocity.dy += ay * h
        let speed = body.velocity.magnitude
        if speed > maxSpeed, speed > 0 {
            let scale = maxSpeed / speed
            body.velocity.dx *= scale
            body.velocity.dy *= scale
        }

        body.position.x += body.velocity.dx * h
        body.position.y += body.velocity.dy * h

        // Deformation spring, per axis: pulled home by stiffness, damped, excited by
        // this substep's acceleration. Clamped so an extreme frame can never fold the
        // avatar inside out.
        let gain = MindConstants.accelSquashGain
        body.squashVelocity.dx += (-MindConstants.squashStiffness * body.squash.dx
            - MindConstants.squashDamping * body.squashVelocity.dx + gain * ax) * h
        body.squashVelocity.dy += (-MindConstants.squashStiffness * body.squash.dy
            - MindConstants.squashDamping * body.squashVelocity.dy + gain * ay) * h
        body.squash.dx = clamp(body.squash.dx + body.squashVelocity.dx * h,
                               min: -MindConstants.maxSquash, max: MindConstants.maxSquash)
        body.squash.dy = clamp(body.squash.dy + body.squashVelocity.dy * h,
                               min: -MindConstants.maxSquash, max: MindConstants.maxSquash)
    }
}
