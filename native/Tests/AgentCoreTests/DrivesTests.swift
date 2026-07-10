import Testing
@testable import AgentCore

// The six drives (design doc "Drives" layer + "Keeping the drives stable"): bounded leaky
// integrators relaxing toward circadian-biased, temperament-set baselines, pushed by
// impulse events, with weak one-directional coupling. All pure math — no rng, no clock —
// so every property here is a plain function assertion.
struct DrivesTests {

    /// Steps `drives` forward `seconds` in fixed 0.125s cognition ticks (8 Hz, D7).
    private func run(
        _ drives: inout Drives, temperament: Temperament, hourOfDay: Double, seconds: Double
    ) {
        let dt = 0.125
        for _ in 0..<Int(seconds / dt) {
            DriveDynamics.tick(&drives, temperament: temperament, hourOfDay: hourOfDay, dt: dt)
        }
    }

    // MARK: Circadian curve

    @Test func circadianFactor_atNightTrough_isNearZero() {
        #expect(abs(DriveDynamics.circadianFactor(hourOfDay: 3)) < 0.001)
    }

    @Test func circadianFactor_atAfternoonPeak_isNearOne() {
        #expect(abs(DriveDynamics.circadianFactor(hourOfDay: 15) - 1) < 0.001)
    }

    @Test func circadianFactor_atMorningMidpoint_isNearHalf() {
        #expect(abs(DriveDynamics.circadianFactor(hourOfDay: 9) - 0.5) < 0.001)
    }

    @Test func effectiveBaselines_energyIsLowerAtNightThanAfternoon() {
        let night = DriveDynamics.effectiveBaselines(temperament: .calm, hourOfDay: 3)
        let day = DriveDynamics.effectiveBaselines(temperament: .calm, hourOfDay: 15)
        #expect(night.energy < day.energy)
    }

    // MARK: Decay toward baseline (homeostasis, not accumulation)

    @Test func tick_displacedArousal_relaxesTowardBaseline() {
        var drives = Drives.atBaselines(of: .calm, hourOfDay: 12)
        drives.arousal = 1.0
        let baseline = DriveDynamics.effectiveBaselines(temperament: .calm, hourOfDay: 12).arousal
        run(&drives, temperament: .calm, hourOfDay: 12, seconds: 120)
        #expect(abs(drives.arousal - baseline) < 0.05)
    }

    @Test func tick_zeroDt_changesNothing() {
        var drives = Drives.atBaselines(of: .calm, hourOfDay: 12)
        drives.arousal = 0.9
        let before = drives
        DriveDynamics.tick(&drives, temperament: .calm, hourOfDay: 12, dt: 0)
        #expect(drives == before)
    }

    @Test func tick_isDeterministic() {
        var a = Drives.atBaselines(of: .calm, hourOfDay: 12)
        var b = a
        run(&a, temperament: .calm, hourOfDay: 12, seconds: 30)
        run(&b, temperament: .calm, hourOfDay: 12, seconds: 30)
        #expect(a == b)
    }

    // MARK: Bounded ranges

    @Test func applyImpulse_neverLeavesUnitRange() {
        var drives = Drives.atBaselines(of: .gremlin, hourOfDay: 12)
        for _ in 0..<20 {
            DriveDynamics.apply(.startle(intensity: 1.0), to: &drives, temperament: .gremlin)
        }
        #expect(drives.allWithinUnitRange)
    }

    @Test func tick_longRunFromExtremes_staysWithinUnitRange() {
        var drives = Drives(energy: 0, curiosity: 1, sociability: 0, comfort: 1, arousal: 0, boredom: 1)
        run(&drives, temperament: .gremlin, hourOfDay: 3, seconds: 600)
        #expect(drives.allWithinUnitRange)
    }

    // MARK: Events are impulses, not level sets

    @Test func startle_spikesArousal() {
        var drives = Drives.atBaselines(of: .calm, hourOfDay: 12)
        let before = drives.arousal
        DriveDynamics.apply(.startle(intensity: 1.0), to: &drives, temperament: .calm)
        #expect(drives.arousal > before)
    }

    @Test func startle_decaysHomeAfterRest() {
        var drives = Drives.atBaselines(of: .calm, hourOfDay: 12)
        let baseline = DriveDynamics.effectiveBaselines(temperament: .calm, hourOfDay: 12).arousal
        DriveDynamics.apply(.startle(intensity: 1.0), to: &drives, temperament: .calm)
        run(&drives, temperament: .calm, hourOfDay: 12, seconds: 180)
        #expect(abs(drives.arousal - baseline) < 0.05)
    }

    @Test func startle_intensityScalesWithTemperamentReflexGain() {
        var calm = Drives.atBaselines(of: .calm, hourOfDay: 12)
        var gremlin = calm
        DriveDynamics.apply(.startle(intensity: 0.5), to: &calm, temperament: .calm)
        DriveDynamics.apply(.startle(intensity: 0.5), to: &gremlin, temperament: .gremlin)
        #expect(gremlin.arousal > calm.arousal)
    }

    // MARK: Boredom dynamics + one-directional coupling

    @Test func boredom_growsWhenArousalIsLow() {
        var drives = Drives.atBaselines(of: .calm, hourOfDay: 12)
        drives.arousal = 0.05
        let before = drives.boredom
        run(&drives, temperament: .calm, hourOfDay: 12, seconds: 180)
        #expect(drives.boredom > before)
    }

    @Test func boredom_growsSlowerWhenArousalIsHigh() {
        var lowArousal = Drives.atBaselines(of: .calm, hourOfDay: 12)
        var highArousal = lowArousal
        lowArousal.arousal = 0.0
        highArousal.arousal = 1.0
        // One cognition tick each: arousal itself decays over longer runs, so compare the
        // instantaneous growth, not a converged level.
        DriveDynamics.tick(&lowArousal, temperament: .calm, hourOfDay: 12, dt: 0.125)
        DriveDynamics.tick(&highArousal, temperament: .calm, hourOfDay: 12, dt: 0.125)
        #expect(lowArousal.boredom > highArousal.boredom)
    }

    @Test func highBoredom_liftsCuriosity() {
        var bored = Drives.atBaselines(of: .calm, hourOfDay: 12)
        var content = bored
        bored.boredom = 1.0
        content.boredom = 0.0
        run(&bored, temperament: .calm, hourOfDay: 12, seconds: 10)
        run(&content, temperament: .calm, hourOfDay: 12, seconds: 10)
        #expect(bored.curiosity > content.curiosity)
    }

    @Test func coupling_isOneDirectional_curiosityDoesNotFeedBoredom() {
        var curious = Drives.atBaselines(of: .calm, hourOfDay: 12)
        var incurious = curious
        curious.curiosity = 1.0
        incurious.curiosity = 0.0
        run(&curious, temperament: .calm, hourOfDay: 12, seconds: 10)
        run(&incurious, temperament: .calm, hourOfDay: 12, seconds: 10)
        #expect(curious.boredom == incurious.boredom)
    }

    // MARK: Temperament presets (one vector, four points — design doc "calm, and switchable")

    @Test func presets_allBaselinesWithinUnitRange() {
        for preset in [Temperament.calm, .gremlin, .aloofCat, .needyPet] {
            #expect(preset.baselines.allWithinUnitRange)
        }
    }

    @Test func presets_allLivelinessFloorsCoverEveryModeWithinUnitRange() {
        for preset in [Temperament.calm, .gremlin, .aloofCat, .needyPet] {
            for mode in SituationMode.allCases {
                let floor = preset.livelinessFloors[mode]
                #expect(floor != nil && floor! >= 0 && floor! <= 1)
            }
        }
    }

    @Test func calm_hasLowerArousalBaselineThanGremlin() {
        #expect(Temperament.calm.baselines.arousal < Temperament.gremlin.baselines.arousal)
    }

    @Test func calm_habituatesFasterThanGremlin() {
        #expect(Temperament.calm.habituationRate > Temperament.gremlin.habituationRate)
    }

    @Test func needyPet_hasLowerSolitudeThanAloofCat() {
        #expect(Temperament.needyPet.solitude < Temperament.aloofCat.solitude)
    }

    @Test func calm_mediaWatchingFloor_isNearZero() {
        #expect(Temperament.calm.livelinessFloors[.mediaWatching]! <= 0.1)
    }

    @Test func calm_floorsKeepItPresent_idleDesktopFloorAboveZero() {
        // Calm is not the collapse trap: the idle-desktop floor stays strictly positive.
        #expect(Temperament.calm.livelinessFloors[.casualBrowsing]! > 0)
    }
}
