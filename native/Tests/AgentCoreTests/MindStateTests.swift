import Foundation
import Testing
@testable import AgentCore

// The `mind` region (decision log D4): the emergent brain's belief state, a sibling of
// world/body/memory on `AgentState`, written only by the Brain. It defaults to nil so
// the classic path's shape (and its parity tests) are untouched, and it round-trips
// through Codable because AgentState is the future LLM context object.
struct MindStateTests {

    private let position = Point(x: 300, y: 200)

    @Test func init_startsAwakeAndIdle() {
        let mind = MindState(temperament: .calm, position: position, hourOfDay: 15, now: 0)
        #expect(mind.power == .awake)
        #expect(mind.behavior == .idle)
        #expect(mind.behaviorTarget == nil)
    }

    @Test func init_drivesStartAtTemperamentBaselinesForTheHour() {
        let mind = MindState(temperament: .calm, position: position, hourOfDay: 15, now: 0)
        #expect(mind.drives == Drives.atBaselines(of: .calm, hourOfDay: 15))
    }

    @Test func init_physicsBodyStartsAtRestAtThePosition() {
        let mind = MindState(temperament: .calm, position: position, hourOfDay: 15, now: 0)
        #expect(mind.physics.position == position)
        #expect(mind.physics.velocity == Vector(dx: 0, dy: 0))
    }

    @Test func agentState_mindDefaultsToNil() {
        let state = TestFixtures.makeState()
        #expect(state.mind == nil)
    }

    @Test func agentState_withMind_codableRoundTripsExactly() throws {
        var state = TestFixtures.makeState()
        state.mind = MindState(temperament: .calm, position: position, hourOfDay: 15, now: 0)
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AgentState.self, from: data)
        #expect(decoded == state)
    }

    @Test func agentState_withoutMind_omitsItFromJSON() throws {
        let state = TestFixtures.makeState()
        let data = try JSONEncoder().encode(state)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("\"mind\""))
    }

    // MARK: StatusSummary surfacing (project rule: every new state attribute shows up)

    @Test func statusSummary_withoutMind_hasNoMindSection() {
        let summary = TestFixtures.makeState().statusSummary(now: 0)
        #expect(!summary.sections.contains { $0.title == "Mind" })
    }

    @Test func statusSummary_withMind_addsAMindSection() {
        var state = TestFixtures.makeState()
        state.mind = MindState(temperament: .calm, position: position, hourOfDay: 15, now: 0)
        let summary = state.statusSummary(now: 0)
        let mindSection = summary.sections.first { $0.title == "Mind" }
        #expect(mindSection != nil)
        let labels = mindSection!.rows.map(\.label)
        #expect(labels.contains("Behavior"))
        #expect(labels.contains("Situation"))
        #expect(labels.contains("Power"))
        #expect(labels.contains("Energy"))
        #expect(labels.contains("Boredom"))
        #expect(labels.contains("Gaze"))
        #expect(labels.contains("Reflex"))
    }

    @Test func statusSummary_temperamentRow_showsThePresetName() {
        var state = TestFixtures.makeState()
        state.mind = MindState(temperament: .gremlin, position: position, hourOfDay: 15, now: 0)
        let summary = state.statusSummary(now: 0)
        let row = summary.sections.first { $0.title == "Mind" }?
            .rows.first { $0.label == "Temperament" }
        #expect(row?.value == "Gremlin")
    }

    @Test func statusSummary_temperamentRow_fallsBackToCustomForANonPresetVector() {
        var custom = Temperament.calm
        custom.tempo = 0.123
        var state = TestFixtures.makeState()
        state.mind = MindState(temperament: custom, position: position, hourOfDay: 15, now: 0)
        let summary = state.statusSummary(now: 0)
        let row = summary.sections.first { $0.title == "Mind" }?
            .rows.first { $0.label == "Temperament" }
        #expect(row?.value == "Custom")
    }
}
