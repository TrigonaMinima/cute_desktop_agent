import Foundation

/// The read-only per-frame timer snapshot — shell-written into `AgentState.timer` by
/// `AgentApp`'s `TimerController` (mirrors how `Perception` writes `AgentWorld`), read by
/// both brains (to freeze movement) and by the renderer/`StatusSummary` (to display it).
/// All the countdown/overtime/formatting math lives here so it's unit-testable without
/// AppKit — `TimerController` itself is a thin, untested shell wrapper around it.
public struct TimerState: Codable, Equatable {
    /// Whether a timer is currently set up at all (running or paused). `false`/absent
    /// (`AgentState.timer == nil`) both mean "no timer" — brains and the renderer check
    /// `state.timer?.active == true`, not just non-nil, so a stale snapshot never freezes
    /// movement after `end()`.
    public var active: Bool
    /// Whether the timer is actively accumulating time right now (vs. paused).
    public var running: Bool
    /// The countdown target, milliseconds.
    public var durationMs: Double
    /// Time accumulated since `start()`, across pause/resume segments — see
    /// `timerElapsedMs` in Math/TimerControls.swift for how the shell derives this.
    public var elapsedMs: Double

    public init(active: Bool, running: Bool, durationMs: Double, elapsedMs: Double) {
        self.active = active
        self.running = running
        self.durationMs = durationMs
        self.elapsedMs = elapsedMs
    }

    /// Negative once past the countdown target — that's what `isOvertime` keys off.
    public var remainingMs: Double { durationMs - elapsedMs }

    /// `false` at exactly zero remaining (the boundary reads as "still counting down",
    /// not overtime yet) — flips true only once `elapsedMs` exceeds `durationMs`.
    public var isOvertime: Bool { remainingMs < 0 }

    /// The middle value in the on-screen row: counts down normally, then past 00:00
    /// switches to a "+"-prefixed count of the overage. Color (white vs. orange) is the
    /// renderer's job, driven by `isOvertime` — this only owns the digits/sign.
    public var remainingString: String {
        isOvertime
            ? "+" + TimerState.formatDuration(ms: -remainingMs)
            : TimerState.formatDuration(ms: remainingMs)
    }

    /// Total elapsed time since the timer started, independent of `durationMs` — the
    /// parenthesized value the renderer shows only once `isOvertime` is true.
    public var totalString: String {
        TimerState.formatDuration(ms: elapsedMs)
    }

    /// `"MM:SS"` under an hour, `"H:MM:SS"` (unpadded hour) at or past it. `ms` is assumed
    /// non-negative — callers of `remainingString` pass `-remainingMs` in overtime rather
    /// than a raw negative value. Truncates (not rounds) to whole seconds, so e.g. 500ms
    /// past zero still reads "+00:00" for one more tick rather than jumping to "+00:01".
    private static func formatDuration(ms: Double) -> String {
        let totalSeconds = Int(ms / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        guard hours > 0 else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
