import Foundation

/// The doze/sleep power ladder (decision log D11): a pure mapping from seconds of user
/// inactivity to the `PowerTier` the brain runs at. The Brain recomputes this every
/// cognition slice from the situation model's activity clock, so waking needs no event
/// plumbing inside AgentCore — fresh input reads as `.awake` on the next slice.
///
/// The tiers mean:
/// - `.awake` — everything at full rate.
/// - `.dozing` — brain-internal: cognition throttled to the doze slice and drive
///   baselines biased down (see `EmergentBrain`); reflexes and rendering keep running.
/// - `.sleeping` — the shell's cue to stop the frame clock entirely and wake
///   event-driven; the brain settles into `.rest` and stops arbitrating.
public enum PowerPolicy {
    public static func tier(secondsSinceActivity: Double) -> PowerTier {
        if secondsSinceActivity >= MindConstants.powerSleepAfterSeconds { return .sleeping }
        if secondsSinceActivity >= MindConstants.powerDozeAfterSeconds { return .dozing }
        return .awake
    }
}
