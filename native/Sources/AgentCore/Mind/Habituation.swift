import Foundation

/// Short-term habituation: per-stimulus interest fatigue, 0 (fresh) to 1 (tuned out).
/// One shared store serves both the gaze salience contest and the reflex arc — the
/// design doc is explicit that they use the same counters, so a stimulus the eyes have
/// worn out doesn't still trigger full-strength reflexes.
///
/// Keys are free-form strings (gaze uses `GazeTargetKind.rawValue`; the reflex arc will
/// key by stimulus type). Both growth and recovery are exact exponentials, so levels are
/// stable at any dt and can never leave [0, 1].
public struct Habituation: Codable, Equatable {
    private var levels: [String: Double] = [:]

    public init() {}

    public func level(for key: String) -> Double {
        levels[key] ?? 0
    }

    /// Grows `key` toward 1 over `dt` seconds of exposure. `rate` scales the speed —
    /// `Temperament.habituationRate`, where calm (>1) tires of stimuli quickly and
    /// gremlin (<1) stays engaged. Floored so a pathological rate can't freeze growth.
    public mutating func expose(_ key: String, dt: Double, rate: Double) {
        let tau = MindConstants.habituationGrowTauSeconds / max(rate, 0.05)
        let current = levels[key] ?? 0
        levels[key] = current + (1 - current) * (1 - exp(-dt / tau))
    }

    /// Decays every key toward 0 over `dt` seconds — interest recovering in the
    /// stimulus's absence. `except` holds the currently-attended key steady so one call
    /// per tick can serve both halves (expose the attended, recover the rest).
    public mutating func recover(dt: Double, except: String?) {
        for key in levels.keys where key != except {
            levels[key]! *= exp(-dt / MindConstants.habituationRecoveryTauSeconds)
        }
    }
}
