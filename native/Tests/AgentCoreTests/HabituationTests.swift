import Testing
@testable import AgentCore

// Short-term habituation (design doc layers 2 and "Scoring salience"): per-stimulus
// counters that grow with exposure and recover in its absence. One shared store serves
// both the gaze salience contest and the reflex arc, per the doc — "using the same
// habituation counters as the reflex arc". Temperament's habituationRate scales growth
// (calm tires of stimuli quickly, gremlin stays engaged).
struct HabituationTests {

    @Test func strongest_emptyStore_isNil() {
        let habituation = Habituation()
        #expect(habituation.strongest() == nil)
    }

    @Test func strongest_returnsTheMostHabituatedKey() {
        var habituation = Habituation()
        habituation.expose("cursorDart", dt: 20, rate: 1)
        habituation.expose("cursor", dt: 2, rate: 1)
        #expect(habituation.strongest()?.key == "cursorDart")
    }

    @Test func level_unseenKey_isZero() {
        let habituation = Habituation()
        #expect(habituation.level(for: "cursor") == 0)
    }

    @Test func expose_growsLevelTowardOne() {
        var habituation = Habituation()
        habituation.expose("cursor", dt: 2.0, rate: 1.0)
        let early = habituation.level(for: "cursor")
        habituation.expose("cursor", dt: 30.0, rate: 1.0)
        let late = habituation.level(for: "cursor")
        #expect(early > 0)
        #expect(late > early)
        #expect(late <= 1.0)
    }

    @Test func expose_higherRate_growsFaster() {
        var calm = Habituation()
        var gremlin = Habituation()
        calm.expose("onset", dt: 3.0, rate: Temperament.calm.habituationRate)
        gremlin.expose("onset", dt: 3.0, rate: Temperament.gremlin.habituationRate)
        #expect(calm.level(for: "onset") > gremlin.level(for: "onset"))
    }

    @Test func recover_decaysLevelTowardZero() {
        var habituation = Habituation()
        habituation.expose("cursor", dt: 10.0, rate: 1.0)
        let exposed = habituation.level(for: "cursor")
        habituation.recover(dt: 60.0, except: nil)
        #expect(habituation.level(for: "cursor") < exposed * 0.2)
    }

    @Test func recover_skipsTheExceptedKey() {
        var habituation = Habituation()
        habituation.expose("cursor", dt: 10.0, rate: 1.0)
        let exposed = habituation.level(for: "cursor")
        habituation.recover(dt: 60.0, except: "cursor")
        #expect(habituation.level(for: "cursor") == exposed)
    }

    @Test func expose_longRun_staysWithinUnitRange() {
        var habituation = Habituation()
        for _ in 0..<1000 {
            habituation.expose("cursor", dt: 5.0, rate: 2.0)
        }
        #expect(habituation.level(for: "cursor") <= 1.0)
    }
}
