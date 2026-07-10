import Testing
@testable import AgentCore

// Steering behaviors (design doc layer 7): pure force-producing functions — seek,
// arrive, flee, wander, avoid-edges — composed by the arbiter's active behavior and fed
// into the FixedStepper. All px/s² on the unit-mass body. Wander is the only stateful
// one (a smoothly drifting heading), and its randomness is injected.
struct SteeringTests {

    private let origin = Point(x: 500, y: 400)
    private let still = Vector(dx: 0, dy: 0)

    // MARK: seek

    @Test func seek_pointsTowardTarget() {
        let force = Steering.seek(
            position: origin, velocity: still, target: Point(x: 900, y: 400), maxSpeed: 100
        )
        #expect(force.dx > 0)
        #expect(abs(force.dy) < 0.001)
    }

    @Test func seek_atTarget_isZero() {
        let force = Steering.seek(position: origin, velocity: still, target: origin, maxSpeed: 100)
        #expect(force == Vector(dx: 0, dy: 0))
    }

    // MARK: arrive

    @Test func arrive_farFromTarget_matchesSeekMagnitude() {
        let target = Point(x: 2000, y: 400)
        let arrive = Steering.arrive(position: origin, velocity: still, target: target, maxSpeed: 100)
        let seek = Steering.seek(position: origin, velocity: still, target: target, maxSpeed: 100)
        #expect(abs(arrive.magnitude - seek.magnitude) < 0.001)
    }

    @Test func arrive_insideSlowRadius_wantsLessSpeedThanSeek() {
        let target = Point(x: origin.x + MindConstants.arriveSlowRadius / 2, y: origin.y)
        let arrive = Steering.arrive(position: origin, velocity: still, target: target, maxSpeed: 100)
        let seek = Steering.seek(position: origin, velocity: still, target: target, maxSpeed: 100)
        #expect(arrive.magnitude < seek.magnitude)
    }

    @Test func arrive_movingFastAtTarget_brakesAgainstVelocity() {
        let force = Steering.arrive(
            position: origin, velocity: Vector(dx: 200, dy: 0), target: origin, maxSpeed: 100
        )
        #expect(force.dx < 0)
    }

    // MARK: flee

    @Test func flee_pointsAwayFromThreat() {
        let force = Steering.flee(
            position: origin, velocity: still, threat: Point(x: 900, y: 400), maxSpeed: 100
        )
        #expect(force.dx < 0)
    }

    @Test func flee_threatExactlyAtPosition_stillProducesEscapeForce() {
        let force = Steering.flee(position: origin, velocity: still, threat: origin, maxSpeed: 100)
        #expect(force.magnitude > 0)
    }

    // MARK: wander

    @Test func wander_isDeterministicUnderSeededRng() {
        var stateA = WanderState(heading: 0)
        var stateB = WanderState(heading: 0)
        let rngA = ScriptedRandom([0.2, 0.8, 0.5])
        let rngB = ScriptedRandom([0.2, 0.8, 0.5])
        var forcesA: [Vector] = []
        var forcesB: [Vector] = []
        for _ in 0..<3 {
            forcesA.append(stateA.steer(rng: rngA, dt: 0.125))
            forcesB.append(stateB.steer(rng: rngB, dt: 0.125))
        }
        #expect(forcesA == forcesB)
    }

    @Test func wander_headingDriftsOverTicks() {
        var state = WanderState(heading: 0)
        let rng = ScriptedRandom([0.9])
        _ = state.steer(rng: rng, dt: 0.125)
        #expect(state.heading != 0)
    }

    @Test func wander_forceMagnitudeIsBounded() {
        var state = WanderState(heading: 1.3)
        let rng = ScriptedRandom([0.0])
        let force = state.steer(rng: rng, dt: 0.125)
        #expect(force.magnitude <= MindConstants.wanderStrength + 0.001)
    }

    // MARK: avoid-edges

    private let screen = Rect(origin: Point(x: 0, y: 0), size: Size(width: 1000, height: 800))
    private let blob = Size(width: 78, height: 62)

    @Test func avoidEdges_wellInsideScreen_isZero() {
        let force = Steering.avoidEdges(position: Point(x: 460, y: 370), size: blob, screen: screen)
        #expect(force == Vector(dx: 0, dy: 0))
    }

    @Test func avoidEdges_nearLeftEdge_pushesRight() {
        let force = Steering.avoidEdges(position: Point(x: 5, y: 370), size: blob, screen: screen)
        #expect(force.dx > 0)
        #expect(force.dy == 0)
    }

    @Test func avoidEdges_nearBottomEdge_pushesUp() {
        // Web space: y grows downward, so "up" is negative dy.
        let force = Steering.avoidEdges(
            position: Point(x: 460, y: 800 - blob.height - 5), size: blob, screen: screen
        )
        #expect(force.dy < 0)
    }

    @Test func avoidEdges_growsStrongerCloserToEdge() {
        let near = Steering.avoidEdges(position: Point(x: 5, y: 370), size: blob, screen: screen)
        let farther = Steering.avoidEdges(position: Point(x: 40, y: 370), size: blob, screen: screen)
        #expect(near.dx > farther.dx)
    }

    @Test func avoidEdges_inCorner_pushesDiagonallyInward() {
        let force = Steering.avoidEdges(position: Point(x: 5, y: 5), size: blob, screen: screen)
        #expect(force.dx > 0)
        #expect(force.dy > 0)
    }
}
