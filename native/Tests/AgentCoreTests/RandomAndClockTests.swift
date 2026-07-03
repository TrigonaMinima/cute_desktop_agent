import Testing
@testable import AgentCore

// RandomProvider/Clock are injected everywhere the state machine needs randomness or
// time, which is what makes StateMachineTransitionTests (Phase 3) deterministic.
struct RandomAndClockTests {

    @Test func seededRandom_sameSeed_producesSameSequence() {
        let a = SeededRandom(seed: 42)
        let b = SeededRandom(seed: 42)
        let sequenceA = (0..<5).map { _ in a.nextUnit() }
        let sequenceB = (0..<5).map { _ in b.nextUnit() }
        #expect(sequenceA == sequenceB)
    }

    @Test func seededRandom_differentSeeds_produceDifferentSequences() {
        let a = SeededRandom(seed: 1)
        let b = SeededRandom(seed: 2)
        #expect(a.nextUnit() != b.nextUnit())
    }

    @Test func seededRandom_valuesStayWithinUnitRange() {
        let rng = SeededRandom(seed: 7)
        for _ in 0..<1000 {
            let value = rng.nextUnit()
            #expect(value >= 0 && value < 1)
        }
    }

    @Test func manualClock_startsAtGivenTime() {
        let clock = ManualClock(start: 1_000)
        #expect(clock.now() == 1_000)
    }

    @Test func manualClock_advanceMovesTimeForward() {
        let clock = ManualClock(start: 0)
        clock.advance(by: 250)
        #expect(clock.now() == 250)
    }

    @Test func manualClock_setJumpsToExactTime() {
        let clock = ManualClock(start: 0)
        clock.set(9_999)
        #expect(clock.now() == 9_999)
    }
}
