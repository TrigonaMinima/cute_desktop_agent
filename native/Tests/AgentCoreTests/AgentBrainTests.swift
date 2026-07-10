import Foundation
import Testing
@testable import AgentCore

// The shared brain seam: the classic StateMachine and the EmergentBrain expose the same
// five methods (makeInitialState / tick / beginDrag / updateDrag / endDrag), so the
// AppKit shell can hold either behind one `AgentBrain` existential and the swap is pure
// config — no per-brain branches in the shell's frame driver or drag wiring.
struct AgentBrainTests {

    private func boot(_ brain: AgentBrain, clock: ManualClock) -> AgentState {
        brain.makeInitialState(
            screens: TestFixtures.screens, avatarSize: TestFixtures.blobSize, now: clock.now()
        )
    }

    @Test func classicStateMachine_bootsThroughTheSeam_withoutAMind() {
        let clock = ManualClock()
        let brain: AgentBrain = StateMachine(rng: ScriptedRandom([]), clock: clock)
        let state = boot(brain, clock: clock)
        #expect(state.mind == nil)
        #expect(state.body.position == Point(x: 500, y: 400))
    }

    @Test func emergentBrain_bootsThroughTheSeam_withACalmMind() {
        let clock = ManualClock()
        let brain: AgentBrain = EmergentBrain(
            rng: ScriptedRandom([]), clock: clock, hourOfDay: { 15 }
        )
        let state = boot(brain, clock: clock)
        #expect(state.mind != nil)
        #expect(state.mind?.temperament == .calm)
        #expect(state.body.position == Point(x: 500, y: 400))
    }

    @Test func tick_throughTheSeam_advancesEitherBrain() {
        let clock = ManualClock()
        let brains: [AgentBrain] = [
            StateMachine(rng: ScriptedRandom([]), clock: clock),
            EmergentBrain(rng: ScriptedRandom([]), clock: clock, hourOfDay: { 15 }),
        ]
        for brain in brains {
            var state = boot(brain, clock: clock)
            clock.advance(by: 16.7)
            brain.tick(state: &state, dt: 0.0167)
            #expect(!state.body.dragging)
        }
    }

    @Test func dragSeam_worksThroughTheExistential() {
        let clock = ManualClock()
        let brain: AgentBrain = EmergentBrain(
            rng: ScriptedRandom([]), clock: clock, hourOfDay: { 15 }
        )
        var state = boot(brain, clock: clock)
        state.world.cursor = Point(x: 520, y: 420)
        brain.beginDrag(state: &state)
        #expect(state.body.dragging)
        state.world.cursor = Point(x: 620, y: 470)
        brain.updateDrag(state: &state)
        #expect(state.body.position == Point(x: 600, y: 450))
        brain.endDrag(state: &state, now: clock.now())
        #expect(!state.body.dragging)
    }
}
