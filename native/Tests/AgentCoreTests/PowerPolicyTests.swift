import Testing
@testable import AgentCore

// The doze/sleep power ladder (decision log D11): a pure mapping from seconds of user
// inactivity to a PowerTier. Doze is a brain-internal tier (cognition throttled, drive
// baselines biased down); sleep is the shell's cue to stop the frame clock entirely and
// wake event-driven. Waking is instant by construction — the tier is recomputed from
// the activity clock every cognition slice, so fresh input reads as awake immediately.
struct PowerPolicyTests {

    @Test func tier_freshActivity_isAwake() {
        #expect(PowerPolicy.tier(secondsSinceActivity: 0) == .awake)
    }

    @Test func tier_justUnderTheDozeThreshold_staysAwake() {
        #expect(PowerPolicy.tier(secondsSinceActivity: 89.9) == .awake)
    }

    @Test func tier_atTheDozeThreshold_dozes() {
        #expect(PowerPolicy.tier(secondsSinceActivity: 90) == .dozing)
    }

    @Test func tier_justUnderTheSleepThreshold_staysDozing() {
        #expect(PowerPolicy.tier(secondsSinceActivity: 299.9) == .dozing)
    }

    @Test func tier_atTheSleepThreshold_sleeps() {
        #expect(PowerPolicy.tier(secondsSinceActivity: 300) == .sleeping)
    }
}
