import Testing
@testable import AgentCore

// The priority ladder from blob.js's computeDesiredEmotion (highest first):
// dragging -> surprised, happy mode -> happy, active quirk, active proximity startle,
// else the base emotion for the current mode. Each rung must beat every rung below it
// even when multiple conditions are simultaneously true.
struct EmotionPriorityTests {

    @Test func dragging_beatsEverythingElse() {
        let state = TestFixtures.makeState(
            mode: .happy, dragging: true, quirkEmotion: .blush, quirkUntil: 5000, proximityUntil: 5000
        )
        #expect(computeDesiredEmotion(state: state, now: 1000) == .surprised)
    }

    @Test func happyMode_beatsQuirkAndProximity_whenNotDragging() {
        let state = TestFixtures.makeState(
            mode: .happy, dragging: false, quirkEmotion: .blush, quirkUntil: 5000, proximityUntil: 5000
        )
        #expect(computeDesiredEmotion(state: state, now: 1000) == .happy)
    }

    @Test func activeQuirk_beatsProximity_whenNotDraggingOrHappy() {
        let state = TestFixtures.makeState(
            mode: .idle, dragging: false, quirkEmotion: .annoyed, quirkUntil: 5000, proximityUntil: 5000
        )
        #expect(computeDesiredEmotion(state: state, now: 1000) == .annoyed)
    }

    @Test func activeProximity_beatsBaseEmotion_whenNoHigherRungActive() {
        let state = TestFixtures.makeState(mode: .idle, dragging: false, quirkUntil: 0, proximityUntil: 5000)
        #expect(computeDesiredEmotion(state: state, now: 1000) == .surprised)
    }

    @Test func expiredQuirk_fallsThroughToProximity() {
        let state = TestFixtures.makeState(
            mode: .idle, dragging: false, quirkEmotion: .thinking, quirkUntil: 500, proximityUntil: 5000
        )
        #expect(computeDesiredEmotion(state: state, now: 1000) == .surprised)
    }

    @Test func expiredProximity_fallsThroughToBaseEmotion() {
        let state = TestFixtures.makeState(mode: .rest, dragging: false, quirkUntil: 0, proximityUntil: 500)
        #expect(computeDesiredEmotion(state: state, now: 1000) == .sleepy)
    }

    @Test func baseEmotion_idle_isNeutral() {
        let state = TestFixtures.makeState(mode: .idle)
        #expect(computeDesiredEmotion(state: state, now: 1000) == .neutral)
    }

    @Test func baseEmotion_wander_isNeutral() {
        let state = TestFixtures.makeState(mode: .wander)
        #expect(computeDesiredEmotion(state: state, now: 1000) == .neutral)
    }

    @Test func baseEmotion_rest_isSleepy() {
        let state = TestFixtures.makeState(mode: .rest)
        #expect(computeDesiredEmotion(state: state, now: 1000) == .sleepy)
    }

    @Test func baseEmotion_peek_isCurious() {
        let state = TestFixtures.makeState(mode: .peek)
        #expect(computeDesiredEmotion(state: state, now: 1000) == .curious)
    }

    @Test func blushStyleByEmotion_mapsQuirkAndHappyToHatch_othersToPlainOrNone() {
        #expect(Constants.blushStyleByEmotion[.blush] == .hatch)
        #expect(Constants.blushStyleByEmotion[.happy] == .hatch)
        #expect(Constants.blushStyleByEmotion[.sleepy] == .plain)
        #expect(Constants.blushStyleByEmotion[.thinking] == .plain)
        // Spelled out as `BlushStyle.none` (not bare `.none`) — against an
        // Optional<BlushStyle> subscript result, bare `.none` resolves to
        // `Optional.none` (nil), not the wrapped enum's `.none` case.
        #expect(Constants.blushStyleByEmotion[.neutral] == BlushStyle.none)
    }

    @Test func bubbleByEmotion_hasNoBubbleForNeutralOrBaseModeEmotionsOutsideTheMap() {
        #expect(Constants.bubbleByEmotion[.neutral] == nil)
        #expect(Constants.bubbleByEmotion[.surprised] == "!")
        #expect(Constants.bubbleByEmotion[.curious] == "?")
    }
}
