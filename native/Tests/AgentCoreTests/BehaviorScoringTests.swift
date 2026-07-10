import Testing
@testable import AgentCore

// The arbiter's scoring layer (design doc "Arbitration"): behaviors score against live
// drive levels modulated by the situation (deference) and temperament (liveliness
// floors), then a temperature-softmax pick with an incumbent commit bonus keeps choice
// varied but never twitchy. Pure functions: drives in, ordered candidate scores out;
// the rng draw is a plain [0,1] value so determinism is trivial under test.
struct BehaviorScoringTests {

    /// Neutral-ish drives to perturb per test.
    private func drives(
        energy: Double = 0.7, curiosity: Double = 0.45, sociability: Double = 0.3,
        comfort: Double = 0.6, arousal: Double = 0.5, boredom: Double = 0.3
    ) -> Drives {
        Drives(energy: energy, curiosity: curiosity, sociability: sociability,
               comfort: comfort, arousal: arousal, boredom: boredom)
    }

    private func scoreTable(
        drives: Drives, situation: SituationMode = .casualBrowsing,
        gazeKind: GazeTargetKind = .neutral, gazeAttention: Double = 0.2,
        overlapsUserZone: Bool = false
    ) -> [BehaviorKind: Double] {
        let scores = BehaviorScoring.scores(
            drives: drives, situation: situation, temperament: .calm,
            gazeKind: gazeKind, gazeAttention: gazeAttention,
            overlapsUserZone: overlapsUserZone
        )
        return Dictionary(uniqueKeysWithValues: scores)
    }

    private func topKind(of table: [BehaviorKind: Double]) -> BehaviorKind? {
        table.max { $0.value < $1.value }?.key
    }

    // MARK: Spontaneity (liveliness floor vs deference)

    @Test func spontaneity_zeroArousal_neverFallsBelowLivelinessFloor() {
        let value = BehaviorScoring.spontaneity(
            situation: .casualBrowsing, arousal: 0, temperament: .calm
        )
        #expect(value == Temperament.calm.livelinessFloors[.casualBrowsing])
    }

    @Test func spontaneity_mediaWatching_staysLowEvenAtHighArousal() {
        let value = BehaviorScoring.spontaneity(
            situation: .mediaWatching, arousal: 0.9, temperament: .calm
        )
        #expect(value < 0.2)
    }

    @Test func spontaneity_casualBrowsing_tracksArousal() {
        let value = BehaviorScoring.spontaneity(
            situation: .casualBrowsing, arousal: 0.8, temperament: .calm
        )
        #expect(value == 0.8)
    }

    // MARK: Drive-led dominance

    @Test func scores_calmBaselineDrives_idleBeatsRest() {
        // Calm's resting energy is 0.5; the rest score's slack keeps a merely
        // average-energy agent from defaulting to sleep over presence.
        let table = scoreTable(drives: drives(energy: 0.5, arousal: 0.25, boredom: 0.2))
        #expect(table[.idle]! > table[.rest]!)
    }

    @Test func scores_lowEnergy_restDominates() {
        let table = scoreTable(drives: drives(energy: 0.1, arousal: 0.25))
        #expect(topKind(of: table) == .rest)
    }

    @Test func scores_highBoredom_wanderDominates() {
        let table = scoreTable(drives: drives(arousal: 0.6, boredom: 0.9))
        #expect(topKind(of: table) == .wander)
    }

    @Test func scores_curiousAndGazeEngaged_inspectDominates() {
        let table = scoreTable(
            drives: drives(curiosity: 0.9, arousal: 0.7),
            gazeKind: .onset, gazeAttention: 0.9
        )
        #expect(topKind(of: table) == .inspect)
    }

    @Test func scores_neutralGaze_inspectScoresZero() {
        let table = scoreTable(
            drives: drives(curiosity: 0.9, arousal: 0.7),
            gazeKind: .neutral, gazeAttention: 0.9
        )
        #expect(table[.inspect] == 0)
    }

    // MARK: Deference (the doc's collapse-trap guard: floors are minimums, not ceilings)

    @Test func scores_mediaWatching_suppressesWanderBelowIdle() {
        let table = scoreTable(
            drives: drives(arousal: 0.6, boredom: 0.9), situation: .mediaWatching
        )
        #expect(table[.wander]! < table[.idle]!)
    }

    // MARK: Yield (caret-zone overlap must dominate everything)

    @Test func scores_overlapsUserZone_yieldDominates() {
        let table = scoreTable(
            drives: drives(curiosity: 0.9, arousal: 0.9, boredom: 0.9),
            gazeKind: .onset, gazeAttention: 1.0, overlapsUserZone: true
        )
        #expect(topKind(of: table) == .yield)
    }

    @Test func scores_noOverlap_yieldIsNotACandidate() {
        let table = scoreTable(drives: drives())
        #expect(table[.yield] == nil)
    }

    // MARK: Softmax pick + incumbent hysteresis

    @Test func pick_dominantScore_winsAtMidDraw() {
        let picked = BehaviorScoring.pick(
            scores: [(.idle, 0.25), (.wander, 0.8)], incumbent: nil, rngValue: 0.5
        )
        #expect(picked == .wander)
    }

    @Test func pick_nearTie_incumbentBonusHoldsTheCurrentBehavior() {
        let scores: [(BehaviorKind, Double)] = [(.idle, 0.30), (.wander, 0.35)]
        let held = BehaviorScoring.pick(scores: scores, incumbent: .idle, rngValue: 0.5)
        let free = BehaviorScoring.pick(scores: scores, incumbent: nil, rngValue: 0.5)
        #expect(held == .idle)
        #expect(free == .wander)
    }

    @Test func pick_sameInputs_isDeterministic() {
        let scores: [(BehaviorKind, Double)] = [(.idle, 0.4), (.rest, 0.5), (.wander, 0.45)]
        let first = BehaviorScoring.pick(scores: scores, incumbent: nil, rngValue: 0.37)
        let second = BehaviorScoring.pick(scores: scores, incumbent: nil, rngValue: 0.37)
        #expect(first == second)
    }
}
