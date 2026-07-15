import Testing
@testable import AgentCore

// StatusSummary turns a frozen AgentState into an ordered, human-readable readout —
// the single abstraction both the menu-bar dropdown and the avatar's right-click menu
// render from, so the two surfaces can never disagree. These tests exist to pin the
// deterministic shape (section/row order, exact wording) both AppKit call sites depend
// on, and to guard against a partial Mode/Emotion mapping silently mislabeling a real
// state (Constants.baseEmotionByMode/modeDwellMsRange both already omit `.happy` on
// purpose — a lookup table here would repeat that gap for a state a user can see).
struct StatusSummaryTests {

    // MARK: - Exhaustive mode/emotion coverage

    @Test func everyMode_hasANonFallbackDisplayName() {
        for mode in Mode.allCases {
            let state = Self.populatedState(mode: mode)
            let row = state.statusSummary(now: 0).row(section: "Body", label: "Mode")
            #expect(row != nil)
            #expect(row?.isEmpty == false)
        }
    }

    @Test func everyEmotion_hasANonFallbackDisplayName() {
        for emotion in Emotion.allCases {
            let state = Self.populatedState(emotion: emotion)
            let row = state.statusSummary(now: 0).row(section: "Body", label: "Emotion")
            #expect(row != nil)
            #expect(row?.isEmpty == false)
        }
    }

    // MARK: - Body section

    @Test func mode_wander_displaysAsWandering() {
        let state = Self.populatedState(mode: .wander)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Mode") == "Wandering")
    }

    @Test func mode_happy_displaysAsHappy() {
        let state = Self.populatedState(mode: .happy)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Mode") == "Happy")
    }

    @Test func mode_flee_displaysAsFleeing() {
        let state = Self.populatedState(mode: .flee)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Mode") == "Fleeing")
    }

    @Test func emotion_curious_displaysAsCurious() {
        let state = Self.populatedState(emotion: .curious)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Emotion") == "Curious")
    }

    @Test func moving_true_displaysAsYes() {
        let state = Self.populatedState(moving: true)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Moving") == "yes")
    }

    @Test func moving_false_displaysAsNo() {
        let state = Self.populatedState(moving: false)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Moving") == "no")
    }

    @Test func dragging_true_displaysAsYes() {
        let state = Self.populatedState(dragging: true)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Dragging") == "yes")
    }

    @Test func position_formatsAsRoundedCoordinatePair() {
        let state = Self.populatedState(position: Point(x: 100.4, y: 200.6))
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Position") == "(100, 201)")
    }

    @Test func target_formatsAsRoundedCoordinatePair() {
        let state = Self.populatedState(target: Point(x: 500, y: 600))
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Target") == "(500, 600)")
    }

    @Test func size_formatsAsWidthByHeight() {
        let state = Self.populatedState(size: Size(width: 78, height: 62))
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Size") == "78\u{00D7}62")
    }

    @Test func onScreen_singleScreen_showsIndexCountAndName() {
        let state = Self.populatedState(position: Point(x: 100, y: 100))
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "On screen") == "1 of 1 (Main)")
    }

    @Test func onScreen_positionOnSecondScreen_showsItsIndexAndName() {
        let state = Self.populatedState(position: Point(x: 1500, y: 400), screens: TestFixtures.twoScreens)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "On screen") == "2 of 2 (Side)")
    }

    @Test func onScreen_deadZonePosition_resolvesToTheNearestScreen() {
        // x=1150 is 50px from Side's left edge vs 150px from Main's right edge.
        let state = Self.populatedState(position: Point(x: 1150, y: 400), screens: TestFixtures.twoScreens)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "On screen") == "2 of 2 (Side)")
    }

    @Test func attentionZone_nil_displaysAsEmDash() {
        let state = Self.populatedState(attentionZone: nil)
        #expect(state.statusSummary(now: 0).row(section: "Body", label: "Avoiding") == "\u{2014}")
    }

    @Test func attentionZone_present_formatsAsOriginAndSize() {
        let state = Self.populatedState(
            attentionZone: Rect(origin: Point(x: 10, y: 20), size: Size(width: 30, height: 40))
        )
        #expect(
            state.statusSummary(now: 0).row(section: "Body", label: "Avoiding")
                == "(10, 20) 30\u{00D7}40"
        )
    }

    // MARK: - World section

    @Test func cursor_formatsAsRoundedCoordinatePair() {
        let state = Self.populatedState(cursor: Point(x: 42, y: 84))
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Cursor") == "(42, 84)")
    }

    @Test func cursorMoving_false_displaysAsNo() {
        let state = Self.populatedState(cursorVelocity: Vector(dx: 0, dy: 0))
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Cursor moving") == "no")
    }

    @Test func cursorMoving_true_displaysAsYesWithSpeed() {
        let state = Self.populatedState(cursorVelocity: Vector(dx: 30, dy: 40))
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Cursor moving") == "yes (50 px/s)")
    }

    @Test func frontmostApp_nil_displaysAsEmDash() {
        let state = Self.populatedState(frontmostApp: nil)
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Frontmost app") == "\u{2014}")
    }

    @Test func frontmostApp_present_displaysItsName() {
        let state = Self.populatedState(frontmostApp: AppInfo(bundleIdentifier: "com.apple.Terminal", name: "Terminal"))
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Frontmost app") == "Terminal")
    }

    @Test func screens_singleScreen_showsCountNameAndSize() {
        let state = Self.populatedState(
            screens: [ScreenInfo(
                frame: Rect(origin: Point(x: 0, y: 0), size: Size(width: 1920, height: 1080)),
                name: "Built-in"
            )]
        )
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Screens")
            == "1: Built-in 1920\u{00D7}1080")
    }

    @Test func screens_twoScreens_listsEachNameAndSizeInOrder() {
        let state = Self.populatedState(screens: TestFixtures.twoScreens)
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Screens")
            == "2: Main 1000\u{00D7}800; Side 800\u{00D7}600")
    }

    @Test func typing_true_displaysAsYes() {
        let state = Self.populatedState(typing: true)
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Typing") == "yes")
    }

    @Test func typing_false_displaysAsNo() {
        let state = Self.populatedState(typing: false)
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Typing") == "no")
    }

    @Test func typingLocation_nil_displaysAsEmDash() {
        let state = Self.populatedState(typingLocation: nil)
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Typing location") == "\u{2014}")
    }

    @Test func typingLocation_present_formatsAsOriginAndSize() {
        let state = Self.populatedState(
            typingLocation: Rect(origin: Point(x: 10, y: 20), size: Size(width: 30, height: 40))
        )
        #expect(
            state.statusSummary(now: 0).row(section: "World", label: "Typing location")
                == "(10, 20) 30\u{00D7}40"
        )
    }

    @Test func scrolling_false_displaysAsNo() {
        let state = Self.populatedState(scrolling: false, scrollVelocity: Vector(dx: 0, dy: 0))
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Scrolling") == "no")
    }

    @Test func scrolling_true_displaysAsYesWithSpeed() {
        let state = Self.populatedState(scrolling: true, scrollVelocity: Vector(dx: 0, dy: -240))
        #expect(state.statusSummary(now: 0).row(section: "World", label: "Scrolling") == "yes (240 px/s)")
    }

    // MARK: - Memory section

    @Test func modeEndsAt_future_formatsAsCountdown() {
        let state = Self.populatedState(modeEndsAt: 2_300)
        #expect(state.statusSummary(now: 0).row(section: "Memory", label: "Mode ends") == "in 2.3s")
    }

    @Test func modeEndsAt_past_formatsAsNow() {
        let state = Self.populatedState(modeEndsAt: 500)
        #expect(state.statusSummary(now: 1_000).row(section: "Memory", label: "Mode ends") == "now")
    }

    @Test func blinking_true_displaysAsYes() {
        let state = Self.populatedState(blinking: true)
        #expect(state.statusSummary(now: 0).row(section: "Memory", label: "Blinking") == "yes")
    }

    @Test func blinking_false_displaysAsNo() {
        let state = Self.populatedState(blinking: false)
        #expect(state.statusSummary(now: 0).row(section: "Memory", label: "Blinking") == "no")
    }

    @Test func nextBlinkAt_formatsAsCountdown() {
        let state = Self.populatedState(nextBlinkAt: 4_000)
        #expect(state.statusSummary(now: 1_000).row(section: "Memory", label: "Next blink") == "in 3.0s")
    }

    @Test func quirkEmotion_nil_displaysAsNone() {
        let state = Self.populatedState(quirkEmotion: nil)
        #expect(state.statusSummary(now: 0).row(section: "Memory", label: "Quirk emotion") == "none")
    }

    @Test func quirkEmotion_present_displaysItsName() {
        let state = Self.populatedState(quirkEmotion: .blush)
        #expect(state.statusSummary(now: 0).row(section: "Memory", label: "Quirk emotion") == "Blushing")
    }

    @Test func proximityCooldownUntil_formatsAsCountdown() {
        let state = Self.populatedState(proximityCooldownUntil: 9_000)
        #expect(state.statusSummary(now: 1_000).row(section: "Memory", label: "Proximity cooldown") == "in 8.0s")
    }

    @Test func yieldCooldownUntil_formatsAsCountdown() {
        let state = Self.populatedState(yieldCooldownUntil: 5_000)
        #expect(state.statusSummary(now: 1_000).row(section: "Memory", label: "Yield cooldown") == "in 4.0s")
    }

    // MARK: - Timer section (present only when state.timer != nil)

    @Test func timer_nil_noTimerSection() {
        let state = Self.populatedState(timer: nil)
        let titles = state.statusSummary(now: 0).sections.map(\.title)
        #expect(!titles.contains("Timer"))
    }

    @Test func timer_present_addsTimerSection() {
        let state = Self.populatedState(
            timer: TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 0)
        )
        let titles = state.statusSummary(now: 0).sections.map(\.title)
        #expect(titles.contains("Timer"))
    }

    @Test func timer_running_stateRowDisplaysRunning() {
        let state = Self.populatedState(
            timer: TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 0)
        )
        #expect(state.statusSummary(now: 0).row(section: "Timer", label: "State") == "Running")
    }

    @Test func timer_paused_stateRowDisplaysPaused() {
        let state = Self.populatedState(
            timer: TimerState(active: true, running: false, durationMs: 60_000, elapsedMs: 0)
        )
        #expect(state.statusSummary(now: 0).row(section: "Timer", label: "State") == "Paused")
    }

    @Test func timer_remainingRow_matchesRemainingString() {
        let timer = TimerState(active: true, running: true, durationMs: 25 * 60_000, elapsedMs: 2_000)
        let state = Self.populatedState(timer: timer)
        #expect(state.statusSummary(now: 0).row(section: "Timer", label: "Remaining") == "24:58")
    }

    @Test func timer_totalRow_matchesTotalString() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 90_000)
        let state = Self.populatedState(timer: timer)
        #expect(state.statusSummary(now: 0).row(section: "Timer", label: "Total") == "01:30")
    }

    @Test func timer_notOvertime_overtimeRowDisplaysNo() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 0)
        let state = Self.populatedState(timer: timer)
        #expect(state.statusSummary(now: 0).row(section: "Timer", label: "Overtime") == "no")
    }

    @Test func timer_overtime_overtimeRowDisplaysYes() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 65_000)
        let state = Self.populatedState(timer: timer)
        #expect(state.statusSummary(now: 0).row(section: "Timer", label: "Overtime") == "yes")
    }

    // MARK: - Deterministic overall shape

    @Test func summary_hasBodyWorldMemorySections_inThatOrder() {
        let state = Self.populatedState()
        let titles = state.statusSummary(now: 0).sections.map(\.title)
        #expect(titles == ["Body", "World", "Memory"])
    }

    @Test func summary_isEquatable_forIdenticalStates() {
        let a = Self.populatedState()
        let b = Self.populatedState()
        #expect(a.statusSummary(now: 0) == b.statusSummary(now: 0))
    }

    @Test func summary_differsWhenModeDiffers() {
        let a = Self.populatedState(mode: .idle)
        let b = Self.populatedState(mode: .rest)
        #expect(a.statusSummary(now: 0) != b.statusSummary(now: 0))
    }

    @Test func summary_isPure_unaffectedByFieldsItDoesNotDisplay() {
        // dragOffset isn't shown anywhere in the summary; changing it must not change
        // the summary output, proving statusSummary only reads what it displays.
        var state = Self.populatedState()
        let before = state.statusSummary(now: 0)
        state.body.dragOffset = Vector(dx: 999, dy: 999)
        let after = state.statusSummary(now: 0)
        #expect(before == after)
    }

    // MARK: - Fixture

    static func populatedState(
        mode: Mode = .idle,
        emotion: Emotion = .neutral,
        moving: Bool = false,
        dragging: Bool = false,
        position: Point = Point(x: 100, y: 100),
        target: Point = Point(x: 100, y: 100),
        size: Size = Size(width: 78, height: 62),
        cursor: Point = Point(x: 0, y: 0),
        cursorVelocity: Vector = Vector(dx: 0, dy: 0),
        frontmostApp: AppInfo? = nil,
        screens: [ScreenInfo] = TestFixtures.screens,
        typing: Bool = false,
        typingLocation: Rect? = nil,
        scrolling: Bool = false,
        scrollVelocity: Vector = Vector(dx: 0, dy: 0),
        modeEndsAt: Double = 0,
        blinking: Bool = false,
        nextBlinkAt: Double = 0,
        quirkEmotion: Emotion? = nil,
        proximityCooldownUntil: Double = 0,
        attentionZone: Rect? = nil,
        yieldCooldownUntil: Double = 0,
        timer: TimerState? = nil
    ) -> AgentState {
        AgentState(
            world: AgentWorld(
                screens: screens, cursor: cursor, cursorVelocity: cursorVelocity,
                frontmostApp: frontmostApp, windowBelow: nil, typing: typing, typingLocation: typingLocation,
                scrolling: scrolling, scrollVelocity: scrollVelocity
            ),
            body: AgentBody(
                position: position, mode: mode, target: target, moving: moving, emotion: emotion,
                dragging: dragging, dragOffset: Vector(dx: 0, dy: 0), size: size, attentionZone: attentionZone
            ),
            memory: AgentMemory(
                modeEndsAt: modeEndsAt, happyUntil: 0, happyResumeMode: .idle,
                nextBlinkAt: nextBlinkAt, blinking: blinking, blinkEndsAt: 0, quirkEmotion: quirkEmotion,
                quirkUntil: 0, nextQuirkAt: 0, proximityUntil: 0, proximityCooldownUntil: proximityCooldownUntil,
                yieldCooldownUntil: yieldCooldownUntil
            ),
            timer: timer
        )
    }
}

private extension StatusSummary {
    /// Test-only lookup: the row value for `label` within `section`, or `nil` if either
    /// is missing. Production call sites (menu builders) render `sections` in order
    /// instead of looking up by name.
    func row(section: String, label: String) -> String? {
        sections.first { $0.title == section }?.rows.first { $0.label == label }?.value
    }
}
