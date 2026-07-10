import Testing
@testable import AgentCore

// The physics layer (design doc layer 7, "Motor and physics"): a point-mass integrated
// at a fixed timestep (decision log D7 — variable timesteps make the same drop wobble
// differently every frame, which reads as jank), plus a spring-damper deformation state
// excited by real acceleration so squash/lean never repeat exactly and are never
// authored. Steering forces come later (Task 5); here forces are plain inputs.
struct PhysicsBodyTests {

    private let h = MindConstants.physicsStepSeconds

    private func makeBody() -> PhysicsBody {
        PhysicsBody(position: Point(x: 500, y: 400))
    }

    // MARK: Fixed timestep + determinism

    @Test func advance_sameTotalTimeDifferentFrameSlicing_isIdentical() {
        var stepperA = FixedStepper()
        var stepperB = FixedStepper()
        var bodyA = makeBody()
        var bodyB = bodyA
        let force = Vector(dx: 120, dy: -40)
        for _ in 0..<60 {
            stepperA.advance(&bodyA, force: force, maxSpeed: 200, frameDt: 1.0 / 60.0)
        }
        for _ in 0..<30 {
            stepperB.advance(&bodyB, force: force, maxSpeed: 200, frameDt: 1.0 / 30.0)
        }
        #expect(bodyA == bodyB)
    }

    @Test func advance_zeroDt_changesNothing() {
        var stepper = FixedStepper()
        var body = makeBody()
        let before = body
        stepper.advance(&body, force: Vector(dx: 100, dy: 100), maxSpeed: 200, frameDt: 0)
        #expect(body == before)
    }

    @Test func advance_dtSmallerThanStep_accumulatesInsteadOfDropping() {
        var stepper = FixedStepper()
        var body = makeBody()
        let force = Vector(dx: 100, dy: 0)
        // Three sub-step-sized frames sum to > one 1/120s step, so movement must appear
        // by the third even though each frame alone is below the step size.
        for _ in 0..<3 {
            stepper.advance(&body, force: force, maxSpeed: 200, frameDt: h * 0.4)
        }
        #expect(body.position.x > 500)
    }

    // MARK: Point-mass dynamics

    @Test func advance_atRestNoForce_staysAtRest() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 0, dy: 0), maxSpeed: 200, frameDt: 1.0)
        #expect(body.position == Point(x: 500, y: 400))
    }

    @Test func advance_constantForce_movesAlongForceDirection() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 200, dy: 0), maxSpeed: 400, frameDt: 1.0)
        #expect(body.position.x > 500)
        #expect(body.position.y == 400)
    }

    @Test func advance_forceRemoved_velocityDecaysTowardZero() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 300, dy: 0), maxSpeed: 400, frameDt: 1.0)
        let movingSpeed = body.velocity.magnitude
        stepper.advance(&body, force: Vector(dx: 0, dy: 0), maxSpeed: 400, frameDt: 3.0)
        #expect(body.velocity.magnitude < movingSpeed * 0.05)
    }

    @Test func advance_hugeForce_speedNeverExceedsMaxSpeed() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 100_000, dy: 0), maxSpeed: 150, frameDt: 2.0)
        #expect(body.velocity.magnitude <= 150.000001)
    }

    // MARK: Spring-damper deformation (squash falls out of acceleration)

    @Test func advance_acceleration_excitesSquash() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 400, dy: 0), maxSpeed: 400, frameDt: 0.25)
        #expect(body.squash != Vector(dx: 0, dy: 0))
    }

    @Test func advance_afterForceRemoved_squashSettlesBackToZero() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 400, dy: 200), maxSpeed: 400, frameDt: 0.5)
        stepper.advance(&body, force: Vector(dx: 0, dy: 0), maxSpeed: 400, frameDt: 6.0)
        #expect(abs(body.squash.dx) < 0.005)
        #expect(abs(body.squash.dy) < 0.005)
    }

    @Test func advance_extremeForce_squashStaysBounded() {
        var stepper = FixedStepper()
        var body = makeBody()
        stepper.advance(&body, force: Vector(dx: 1_000_000, dy: 1_000_000), maxSpeed: 5000, frameDt: 2.0)
        #expect(abs(body.squash.dx) <= MindConstants.maxSquash)
        #expect(abs(body.squash.dy) <= MindConstants.maxSquash)
    }

    // MARK: Impulses (drag release hand-off)

    @Test func applyImpulse_setsVelocityUsedByNextAdvance() {
        var stepper = FixedStepper()
        var body = makeBody()
        body.velocity = Vector(dx: 90, dy: 0)
        stepper.advance(&body, force: Vector(dx: 0, dy: 0), maxSpeed: 200, frameDt: 0.1)
        #expect(body.position.x > 500)
    }
}
