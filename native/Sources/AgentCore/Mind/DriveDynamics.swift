import Foundation

/// Discrete events that push the drives (design doc: "events are impulses, not level
/// sets") — each applies a one-shot additive kick via `DriveDynamics.apply`, and the
/// leaky decay in `tick` brings the drive home. One bad evening cannot become a
/// personality because nothing here sets a level.
public enum DriveImpulse: Equatable {
    /// A startle/flinch fired with the given post-habituation intensity in [0, 1].
    case startle(intensity: Double)
    /// Something new appeared (window onset, novel app).
    case novelty
    /// The user petted/played with the agent (hover dwell, gentle drag).
    case pettedOrPlayed
    /// A drag ended with a gentle drop.
    case droppedGently
    /// The user came back after being away.
    case userReturned
    /// The user went away / went idle.
    case userLeft
}

/// Pure drive dynamics (no rng, no clock): leaky integration toward circadian-biased
/// baselines, bounded ranges, impulse events, and weak one-directional coupling
/// (low arousal → boredom grows → curiosity lifts; never a cycle back). Stability
/// properties are the doc's "Keeping the drives stable" section, enforced structurally:
/// every write path ends in a clamp, every drive decays toward baseline, and coupling
/// terms only read upstream drives.
public enum DriveDynamics {

    // MARK: Circadian bias

    /// Smooth 24h cosine in [0, 1]: trough at 03:00 (sleepy), peak at 15:00.
    public static func circadianFactor(hourOfDay: Double) -> Double {
        0.5 - 0.5 * cos((hourOfDay - MindConstants.circadianTroughHour) / 24 * 2 * .pi)
    }

    /// The temperament baselines with the circadian bias applied — energy dips hardest
    /// at night, arousal a little; the other four drives are circadian-flat.
    public static func effectiveBaselines(temperament: Temperament, hourOfDay: Double) -> Drives {
        let factor = circadianFactor(hourOfDay: hourOfDay)
        var base = temperament.baselines
        base.energy *= lerp(MindConstants.circadianEnergyNightScale, 1, factor)
        base.arousal *= lerp(MindConstants.circadianArousalNightScale, 1, factor)
        return base
    }

    // MARK: Per-tick dynamics (cognition rate, dt in seconds)

    /// One cognition tick: exponential leak toward the effective baseline per drive
    /// (exact `exp` form, so any dt is stable, not just small ones), then the two
    /// one-directional coupling growth terms, then the clamp.
    public static func tick(
        _ drives: inout Drives, temperament: Temperament, hourOfDay: Double, dt: Double
    ) {
        guard dt > 0 else { return }
        let base = effectiveBaselines(temperament: temperament, hourOfDay: hourOfDay)

        for path in Drives.allDrivePaths {
            let tau = MindConstants.driveRelaxationTauSeconds[keyPath: path]
            let target = base[keyPath: path]
            let current = drives[keyPath: path]
            drives[keyPath: path] = target + (current - target) * exp(-dt / tau)
        }

        // Coupling, strictly one-directional (doc: avoid two-way links):
        // understimulation grows boredom...
        drives.boredom += (1 - drives.arousal) * MindConstants.boredomGrowthPerSecond * dt
        // ...and excess boredom lifts curiosity. Nothing feeds back the other way.
        drives.curiosity += max(0, drives.boredom - MindConstants.boredomCuriosityThreshold)
            * MindConstants.boredomCuriosityCouplingPerSecond * dt

        clampAll(&drives)
    }

    /// Applies one impulse event's additive deltas, clamped. Startle scales by the
    /// temperament's reflex gain; the alone/return pair scales by its solitude term
    /// (being left alone is contentment for a high-solitude temperament, mild loss for
    /// a needy one).
    public static func apply(
        _ impulse: DriveImpulse, to drives: inout Drives, temperament: Temperament
    ) {
        switch impulse {
        case .startle(let intensity):
            let kick = clamp(intensity, min: 0, max: 1) * temperament.reflexGain
            drives.arousal += 0.5 * kick
            drives.comfort -= 0.3 * kick
            drives.boredom -= 0.2 * kick
        case .novelty:
            drives.curiosity += 0.25
            drives.boredom -= 0.3
            drives.arousal += 0.1
        case .pettedOrPlayed:
            drives.sociability += 0.3
            drives.comfort += 0.25
            drives.boredom -= 0.4
        case .droppedGently:
            drives.comfort += 0.15
            drives.arousal += 0.1
        case .userReturned:
            drives.sociability += 0.2
            drives.arousal += 0.15
        case .userLeft:
            drives.sociability -= 0.1 * (1 - temperament.solitude)
            drives.comfort += 0.1 * temperament.solitude
        }
        clampAll(&drives)
    }

    /// Bounded ranges: every drive clamped to [0, 1]; none can run to a rail and stick.
    private static func clampAll(_ drives: inout Drives) {
        for path in Drives.allDrivePaths {
            drives[keyPath: path] = clamp(drives[keyPath: path], min: 0, max: 1)
        }
    }
}
