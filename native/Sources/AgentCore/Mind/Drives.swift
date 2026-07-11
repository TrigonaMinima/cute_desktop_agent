import Foundation

/// The six continuous drives (design doc "Drives" layer). Each lives in [0, 1] and is a
/// leaky integrator: `DriveDynamics.tick` relaxes it toward its circadian-biased,
/// temperament-set baseline, events push it via `DriveDynamics.apply`, and clamping plus
/// decay-toward-baseline are what keep the coupled system stable (doc: "Keeping the
/// drives stable"). This continuous state is the first engine of non-repetition: behaviors
/// score against live drive levels, so no two moments are identical.
public struct Drives: Codable, Equatable {
    public var energy: Double
    public var curiosity: Double
    public var sociability: Double
    public var comfort: Double
    public var arousal: Double
    public var boredom: Double

    public init(
        energy: Double, curiosity: Double, sociability: Double,
        comfort: Double, arousal: Double, boredom: Double
    ) {
        self.energy = energy
        self.curiosity = curiosity
        self.sociability = sociability
        self.comfort = comfort
        self.arousal = arousal
        self.boredom = boredom
    }

    /// True when every drive sits inside [0, 1] — the bounded-ranges stability property.
    public var allWithinUnitRange: Bool {
        Self.allDrivePaths.allSatisfy { (0...1).contains(self[keyPath: $0]) }
    }

    /// Key paths to every drive, so leaky decay and clamping iterate one list instead of
    /// hand-unrolling six near-identical statements per call site.
    static let allDrivePaths: [WritableKeyPath<Drives, Double>] = [
        \.energy, \.curiosity, \.sociability, \.comfort, \.arousal, \.boredom,
    ]
}
