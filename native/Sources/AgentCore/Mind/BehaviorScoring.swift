import Foundation

/// The behaviors the arbiter can hand the body to (design doc layer 5). Reflexes are
/// not in this list on purpose — they preempt whoever holds the body and are never
/// scored, so arbiter hysteresis can never gate them.
public enum BehaviorKind: String, Codable, Equatable {
    /// Present but unhurried: micro-motion only, the default posture.
    case idle
    /// Settle and recover — energy's behavior.
    case rest
    /// Amble somewhere else on screen — boredom's behavior.
    case wander
    /// Drift toward whatever gaze is engaged with — curiosity's behavior.
    case inspect
    /// Get out of the user's working zone — deference's one hard override.
    case yield
}

/// Arbitration scoring (design doc "Arbitration": scores in, softmax + hysteresis out).
/// Pure functions: behaviors score against live drives, the situation mode sets how
/// much deference suppresses spontaneous movement, and the temperament's per-context
/// liveliness floor keeps a minimum of presence (floors are minimums that prevent
/// collapse-to-lifeless, never ceilings). The pick is a temperature softmax over the
/// scores plus a flat incumbent bonus — variety without twitchiness.
public enum BehaviorScoring {

    /// How willing the agent is to move of its own accord right now: deference scaled
    /// by arousal, floored by the temperament's per-context liveliness floor.
    public static func spontaneity(
        situation: SituationMode, arousal: Double, temperament: Temperament
    ) -> Double {
        return max(temperament.livelinessFloor(for: situation), deference(situation) * arousal)
    }

    /// How much the situation asks the agent to hold back — multiplies spontaneous
    /// scores rather than gating them, so a strong enough drive can still act (and the
    /// liveliness floor guarantees presence regardless).
    static func deference(_ situation: SituationMode) -> Double {
        switch situation {
        case .mediaWatching: return 0.15
        case .focusTyping: return 0.4
        case .idleAway, .casualBrowsing: return 1.0
        }
    }

    /// Scores every currently available behavior. Ordered array (not a dictionary) so
    /// the softmax pick's tie-breaking is deterministic, matching `weightedChoice`.
    public static func scores(
        drives: Drives, situation: SituationMode, temperament: Temperament,
        gazeKind: GazeTargetKind, gazeAttention: Double, overlapsUserZone: Bool
    ) -> [(BehaviorKind, Double)] {
        let spontaneity = spontaneity(
            situation: situation, arousal: drives.arousal, temperament: temperament
        )

        var scores: [(BehaviorKind, Double)] = [
            // A constant floor: doing nothing in particular is always a candidate.
            (.idle, MindConstants.idleBehaviorScore),
            // Slack keeps merely-average energy (calm's 0.5 baseline) from making rest
            // the default posture — only a genuine deficit outbids idle presence.
            (.rest, max(0, (1 - drives.energy) - MindConstants.restEnergySlack)),
            (.wander, drives.boredom * spontaneity),
            (.inspect, drives.curiosity * inspectEngagement(kind: gazeKind, attention: gazeAttention) * spontaneity),
        ]
        if overlapsUserZone {
            // Yield is only a candidate when there is something to yield to, and then
            // it dominates: sitting on the user's caret is never acceptable.
            scores.append((.yield, MindConstants.yieldBehaviorScore))
        }
        return scores
    }

    /// Inspect wants an external object of interest: gaze engaged on something in the
    /// world. Neutral rest and the agent's own locomotion target don't qualify.
    private static func inspectEngagement(kind: GazeTargetKind, attention: Double) -> Double {
        switch kind {
        case .neutral, .locomotion: return 0
        case .cursor, .onset, .user, .motion: return attention
        }
    }

    /// The commit rule: incumbent gets a flat bonus (hysteresis), then a temperature
    /// softmax turns scores into weights and one rng draw picks. Low temperature means
    /// clear winners nearly always win; near-ties stay genuinely stochastic.
    public static func pick(
        scores: [(BehaviorKind, Double)], incumbent: BehaviorKind?, rngValue: Double
    ) -> BehaviorKind {
        let adjusted = scores.map { kind, score in
            (kind, score + (kind == incumbent ? MindConstants.behaviorIncumbentBonus : 0))
        }
        // Shift by the max before exponentiating — standard softmax stabilization.
        let top = adjusted.map(\.1).max() ?? 0
        let weights = adjusted.map { kind, score in
            (kind, exp((score - top) / MindConstants.behaviorSoftmaxTemperature))
        }
        return weightedChoice(weights, rngValue: rngValue)
    }
}
