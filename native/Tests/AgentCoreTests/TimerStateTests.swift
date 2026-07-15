import Testing
@testable import AgentCore

// TimerState is the read-only per-frame snapshot Jiggy's timer mode renders from — the
// pure math (remaining/overtime/formatting) lives here so it's unit-testable without
// AppKit; `TimerController` (AgentApp, untested) is a thin shell wrapper that produces
// this snapshot each frame via `timerElapsedMs` below.
struct TimerStateTests {

    // MARK: - remainingMs / isOvertime

    @Test func remainingMs_computesDurationMinusElapsed() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 20_000)
        #expect(timer.remainingMs == 40_000)
    }

    @Test func isOvertime_false_whenRemainingIsPositive() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 20_000)
        #expect(!timer.isOvertime)
    }

    @Test func isOvertime_false_atExactlyZeroRemaining() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 60_000)
        #expect(!timer.isOvertime)
    }

    @Test func isOvertime_true_pastZeroRemaining() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 60_001)
        #expect(timer.isOvertime)
    }

    // MARK: - remainingString

    @Test func remainingString_formatsMinutesAndSeconds() {
        let timer = TimerState(active: true, running: true, durationMs: 25 * 60_000, elapsedMs: 2_000)
        #expect(timer.remainingString == "24:58")
    }

    @Test func remainingString_pastSixtyMinutes_includesHours() {
        let timer = TimerState(active: true, running: true, durationMs: 90 * 60_000, elapsedMs: 0)
        #expect(timer.remainingString == "1:30:00")
    }

    @Test func remainingString_overtime_prefixesPlusSign() {
        // 1 minute duration, 2 min 14s elapsed -> 1m14s over.
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 134_000)
        #expect(timer.remainingString == "+01:14")
    }

    @Test func remainingString_justPastZero_readsAsPlusZero() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 60_500)
        #expect(timer.remainingString == "+00:00")
    }

    // MARK: - totalString (elapsed since start, independent of duration)

    @Test func totalString_formatsElapsedRegardlessOfDuration() {
        let timer = TimerState(active: true, running: true, durationMs: 60_000, elapsedMs: 90_000)
        #expect(timer.totalString == "01:30")
    }

    @Test func totalString_pastSixtyMinutes_includesHours() {
        let timer = TimerState(active: true, running: true, durationMs: 0, elapsedMs: 3_661_000)
        #expect(timer.totalString == "1:01:01")
    }

    // MARK: - timerElapsedMs (pure elapsed-accumulation math — the shell-facing seam
    // `TimerController` calls each frame; see Math/Geometry.swift)

    @Test func timerElapsedMs_whileRunning_addsTimeSinceSegmentStart() {
        let elapsed = timerElapsedMs(accumulatedMs: 5_000, running: true, segmentStartedAt: 1_000, now: 4_000)
        #expect(elapsed == 8_000)
    }

    @Test func timerElapsedMs_whilePaused_freezesAtAccumulated() {
        // running=false ignores now entirely, regardless of how far the clock has moved.
        let elapsed = timerElapsedMs(accumulatedMs: 12_000, running: false, segmentStartedAt: nil, now: 999_000)
        #expect(elapsed == 12_000)
    }

    @Test func timerElapsedMs_resumeAfterPause_continuesFromAccumulated() {
        // Simulates: ran 5s, paused, resumed, ran 2s more.
        let afterFirstSegment = timerElapsedMs(accumulatedMs: 0, running: true, segmentStartedAt: 0, now: 5_000)
        let resumed = timerElapsedMs(
            accumulatedMs: afterFirstSegment, running: true, segmentStartedAt: 10_000, now: 12_000
        )
        #expect(resumed == 7_000)
    }

    @Test func timerElapsedMs_runningWithNilSegmentStart_fallsBackToAccumulated() {
        // Defensive: a running timer always has a segment start in practice, but a
        // caller-side inconsistency shouldn't crash or extrapolate from a bogus time.
        let elapsed = timerElapsedMs(accumulatedMs: 3_000, running: true, segmentStartedAt: nil, now: 50_000)
        #expect(elapsed == 3_000)
    }
}
