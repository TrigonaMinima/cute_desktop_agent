import Foundation

/// Temperament is one parameter vector (design doc "The v0 temperament preset"): drive
/// baselines, habituation rate, solitude term, per-context liveliness floors, reflex
/// gain, and tempo. The four archetypes are the same vector moved, not other code —
/// switching preset swaps this value and lets the drives' own leaky dynamics ease the
/// body into it over seconds.
public struct Temperament: Codable, Equatable {
    /// Resting drive values the leaky integrators relax toward (before circadian bias).
    public var baselines: Drives
    /// Multiplier on how fast per-stimulus habituation accumulates. Calm habituates
    /// fast (repeated pokes fade quickly); gremlin slow (keeps reacting).
    public var habituationRate: Double
    /// 0...1: how content being left alone is. High solitude means alone-time reads as
    /// contentment, not a penalty — the honest version of the collapse guard.
    public var solitude: Double
    /// Per-context liveliness floor (0...1): the intrinsic "present and expressive"
    /// baseline value per situation mode — near zero during fullscreen media, higher on
    /// an idle desktop. Per-context, not one global dial (doc: the collapse trap).
    public var livelinessFloors: [SituationMode: Double]
    /// Startle/flinch magnitude multiplier (1 = neutral reference).
    public var reflexGain: Double
    /// Motion and arbitration tempo multiplier (1 = neutral reference). Calm is slow.
    public var tempo: Double

    public init(
        baselines: Drives, habituationRate: Double, solitude: Double,
        livelinessFloors: [SituationMode: Double], reflexGain: Double, tempo: Double
    ) {
        self.baselines = baselines
        self.habituationRate = habituationRate
        self.solitude = solitude
        self.livelinessFloors = livelinessFloors
        self.reflexGain = reflexGain
        self.tempo = tempo
    }

    // MARK: Presets — the doc's four archetypes as points in the same vector space.

    /// The v0 default: rests more, spikes less, habituates fast, content alone, low
    /// floors, gentle reflexes, unhurried tempo. Errs toward ignorable — the
    /// recoverable direction for something living on top of every window.
    public static let calm = Temperament(
        baselines: Drives(
            energy: 0.5, curiosity: 0.45, sociability: 0.3,
            comfort: 0.7, arousal: 0.25, boredom: 0.2
        ),
        habituationRate: 1.6,
        solitude: 0.8,
        livelinessFloors: [
            .focusTyping: 0.10, .mediaWatching: 0.05, .idleAway: 0.05, .casualBrowsing: 0.25,
        ],
        reflexGain: 0.6,
        tempo: 0.8
    )

    /// High arousal, slow habituation, low solitude, high floors, big reflexes, fast.
    public static let gremlin = Temperament(
        baselines: Drives(
            energy: 0.7, curiosity: 0.7, sociability: 0.6,
            comfort: 0.5, arousal: 0.6, boredom: 0.35
        ),
        habituationRate: 0.6,
        solitude: 0.3,
        livelinessFloors: [
            .focusTyping: 0.35, .mediaWatching: 0.20, .idleAway: 0.10, .casualBrowsing: 0.60,
        ],
        reflexGain: 1.4,
        tempo: 1.4
    )

    /// Low sociability and high solitude like calm, but sharper reactions.
    public static let aloofCat = Temperament(
        baselines: Drives(
            energy: 0.5, curiosity: 0.5, sociability: 0.15,
            comfort: 0.65, arousal: 0.3, boredom: 0.25
        ),
        habituationRate: 1.2,
        solitude: 0.9,
        livelinessFloors: [
            .focusTyping: 0.12, .mediaWatching: 0.05, .idleAway: 0.05, .casualBrowsing: 0.30,
        ],
        reflexGain: 1.1,
        tempo: 1.0
    )

    /// High sociability, low solitude — alone-time reads as wanting you.
    public static let needyPet = Temperament(
        baselines: Drives(
            energy: 0.6, curiosity: 0.5, sociability: 0.85,
            comfort: 0.55, arousal: 0.45, boredom: 0.3
        ),
        habituationRate: 0.9,
        solitude: 0.1,
        livelinessFloors: [
            .focusTyping: 0.30, .mediaWatching: 0.15, .idleAway: 0.10, .casualBrowsing: 0.50,
        ],
        reflexGain: 1.0,
        tempo: 1.1
    )
}
