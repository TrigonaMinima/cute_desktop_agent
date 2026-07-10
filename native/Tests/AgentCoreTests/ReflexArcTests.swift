import Testing
@testable import AgentCore

// The reflex arc (design doc layer 2): rule-based, evaluated on the fast tick, straight
// from perception to motor. Its gain is habituation-times-temperament, so one mechanism
// yields the startle → flinch → wary-watch → nothing progression on repeated stimuli,
// with sensitivity recovering after rest. v0's stimulus is the cursor darting at the
// body (fast closing speed within range). Reflexes are never gated by arbiter
// hysteresis — that's the Brain's contract, verified here by the arc being a pure
// detector the Brain must obey.
struct ReflexArcTests {

    private let bodyCenter = Point(x: 500, y: 400)

    /// A cursor `distance` px left of the body, closing at `speed` px/s.
    private func dartingWorld(distance: Double, speed: Double) -> AgentWorld {
        AgentWorld(
            screens: TestFixtures.screens,
            cursor: Point(x: 500 - distance, y: 400),
            cursorVelocity: Vector(dx: speed, dy: 0)
        )
    }

    private func fire(
        _ arc: inout ReflexArc, _ habituation: inout Habituation,
        world: AgentWorld, temperament: Temperament, now: Double
    ) -> ReflexEvent? {
        arc.tick(
            world: world, bodyCenter: bodyCenter, habituation: &habituation,
            temperament: temperament, now: now
        )
    }

    // MARK: Detection gates

    @Test func tick_slowCursor_firesNothing() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let event = fire(&arc, &habituation, world: dartingWorld(distance: 100, speed: 200),
                         temperament: .calm, now: 0)
        #expect(event == nil)
    }

    @Test func tick_fastCursorFarAway_firesNothing() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let event = fire(&arc, &habituation, world: dartingWorld(distance: 600, speed: 2500),
                         temperament: .calm, now: 0)
        #expect(event == nil)
    }

    @Test func tick_fastRecedingCursor_firesNothing() {
        var arc = ReflexArc()
        var habituation = Habituation()
        // Same position, velocity pointing away from the body.
        let world = AgentWorld(
            screens: TestFixtures.screens,
            cursor: Point(x: 400, y: 400),
            cursorVelocity: Vector(dx: -2500, dy: 0)
        )
        let event = fire(&arc, &habituation, world: world, temperament: .calm, now: 0)
        #expect(event == nil)
    }

    @Test func tick_fastApproachingCursor_firesStartle() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let event = fire(&arc, &habituation, world: dartingWorld(distance: 100, speed: 2200),
                         temperament: .calm, now: 0)
        #expect(event?.kind == .startle)
    }

    // MARK: Habituation progression (the anti-repetition weapon)

    @Test func tick_repeatedDarts_weakenStartleToFlinchToWaryToNothing() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let world = dartingWorld(distance: 100, speed: 2200)
        var kinds: [ReflexKind?] = []
        var now: Double = 0
        for _ in 0..<4 {
            let event = fire(&arc, &habituation, world: world, temperament: .calm, now: now)
            kinds.append(event?.kind)
            // Step past the event and refractory window so each dart is a fresh fire
            // opportunity, but too soon for interest to recover.
            now += 2000
        }
        #expect(kinds[0] == .startle)
        #expect(kinds[1] == .flinch)
        #expect(kinds[2] == .waryWatch)
        #expect(kinds[3] == nil)
    }

    @Test func tick_afterLongRest_sensitivityRecovers() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let world = dartingWorld(distance: 100, speed: 2200)
        var now: Double = 0
        for _ in 0..<4 {
            _ = fire(&arc, &habituation, world: world, temperament: .calm, now: now)
            now += 2000
        }
        // A minute of rest: the shared store's recovery (normally driven each tick by
        // the Brain) brings interest back.
        habituation.recover(dt: 90, except: nil)
        let event = fire(&arc, &habituation, world: world, temperament: .calm, now: now + 90_000)
        #expect(event?.kind == .startle)
    }

    @Test func tick_duringActiveReflex_doesNotRefire() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let world = dartingWorld(distance: 100, speed: 2200)
        let first = fire(&arc, &habituation, world: world, temperament: .calm, now: 0)
        let second = fire(&arc, &habituation, world: world, temperament: .calm, now: 100)
        #expect(first != nil)
        #expect(second == nil)
    }

    // MARK: Temperament gain

    @Test func tick_sameDart_gremlinStartlesWhereCalmFlinches() {
        var calmArc = ReflexArc()
        var calmHabituation = Habituation()
        var gremlinArc = ReflexArc()
        var gremlinHabituation = Habituation()
        let world = dartingWorld(distance: 100, speed: 1300)
        let calmEvent = fire(&calmArc, &calmHabituation, world: world, temperament: .calm, now: 0)
        let gremlinEvent = fire(&gremlinArc, &gremlinHabituation, world: world, temperament: .gremlin, now: 0)
        #expect(calmEvent?.kind == .flinch)
        #expect(gremlinEvent?.kind == .startle)
    }

    // MARK: Motor seize

    @Test func steeringForce_duringStartle_pushesAwayFromSource() {
        var arc = ReflexArc()
        var habituation = Habituation()
        _ = fire(&arc, &habituation, world: dartingWorld(distance: 100, speed: 2200),
                 temperament: .calm, now: 0)
        let force = arc.steeringForce(
            bodyCenter: bodyCenter, velocity: Vector(dx: 0, dy: 0), maxSpeed: 300, now: 100
        )
        // Source is left of the body, so the escape push is rightward.
        #expect(force != nil)
        #expect(force!.dx > 0)
    }

    @Test func steeringForce_duringWaryWatch_isNil_gazeOnly() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let world = dartingWorld(distance: 100, speed: 2200)
        var now: Double = 0
        var event: ReflexEvent?
        // Habituate down to the wary-watch tier.
        for _ in 0..<3 {
            event = fire(&arc, &habituation, world: world, temperament: .calm, now: now)
            now += 2000
        }
        #expect(event?.kind == .waryWatch)
        let force = arc.steeringForce(
            bodyCenter: bodyCenter, velocity: Vector(dx: 0, dy: 0), maxSpeed: 300, now: now - 1900
        )
        #expect(force == nil)
    }

    @Test func steeringForce_afterEventEnds_isNil() {
        var arc = ReflexArc()
        var habituation = Habituation()
        _ = fire(&arc, &habituation, world: dartingWorld(distance: 100, speed: 2200),
                 temperament: .calm, now: 0)
        let force = arc.steeringForce(
            bodyCenter: bodyCenter, velocity: Vector(dx: 0, dy: 0), maxSpeed: 300, now: 10_000
        )
        #expect(force == nil)
    }

    // MARK: Event payload

    @Test func firedEvent_carriesSourceAndPostGainIntensity() {
        var arc = ReflexArc()
        var habituation = Habituation()
        let event = fire(&arc, &habituation, world: dartingWorld(distance: 100, speed: 2200),
                         temperament: .calm, now: 0)
        #expect(event?.source == Point(x: 400, y: 400))
        #expect(event!.intensity > 0)
        #expect(event!.intensity <= 1.0)
    }
}
