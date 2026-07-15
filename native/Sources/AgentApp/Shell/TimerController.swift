import Foundation
import AgentCore

/// Canonical, shell-owned timer data — the AppKit-side counterpart to `AgentCore`'s
/// read-only `TimerState`. Not unit-tested itself (the AppKit shell isn't — see
/// CLAUDE.md); the pause/resume elapsed-time math it delegates to (`timerElapsedMs`) is
/// unit-tested in `AgentCore`.
///
/// `AppDelegate` owns one instance for the app's lifetime and calls `snapshot(now:)` once
/// per frame (`applyTimer`) to write `state.timer` — this is what makes the timer survive
/// `switchBrain` for free: rebuilding `state` doesn't touch this controller, and the very
/// next frame's `applyTimer` re-populates `state.timer` from it.
public final class TimerController {
    private static let durationKey = "timerDurationMs"
    private static let defaultDurationMs: Double = 25 * 60_000

    public private(set) var active = false
    private var durationMs: Double = 0
    /// Time banked from prior running segments (ms) — frozen while paused.
    private var accumulatedMs: Double = 0
    /// Clock ms the *current* running segment began; nil while paused or inactive.
    /// `running` is always exactly this being non-nil, so it's derived rather than
    /// tracked as a second, separately-settable field.
    private var segmentStartedAt: Double?
    private var running: Bool { segmentStartedAt != nil }

    public init() {}

    /// The last duration the user actually started a timer with, persisted across
    /// relaunches (D10/D21-style UserDefaults persistence) — not a *running* timer,
    /// only its last chosen length, so a fresh launch never resumes counting on its own.
    public var lastUsedDurationMs: Double {
        let stored = UserDefaults.standard.double(forKey: Self.durationKey)
        return stored > 0 ? stored : Self.defaultDurationMs
    }

    public func start(durationMs: Double, now: Double) {
        self.durationMs = durationMs
        accumulatedMs = 0
        segmentStartedAt = now
        active = true
        UserDefaults.standard.set(durationMs, forKey: Self.durationKey)
    }

    /// No-ops while inactive — the on-screen button and the menu row are both only
    /// reachable while a timer is active, but this stays defensive rather than relying
    /// on callers to check first.
    public func togglePause(now: Double) {
        guard active else { return }
        if running {
            accumulatedMs = elapsedMs(now: now)
            segmentStartedAt = nil
        } else {
            segmentStartedAt = now
        }
    }

    /// Clears the timer entirely — the freeze in both brains lifts on the very next
    /// tick once `snapshot(now:)` reports `active == false`.
    public func end() {
        active = false
        segmentStartedAt = nil
        accumulatedMs = 0
    }

    public func elapsedMs(now: Double) -> Double {
        timerElapsedMs(accumulatedMs: accumulatedMs, running: running, segmentStartedAt: segmentStartedAt, now: now)
    }

    /// What `applyTimer` writes into `state.timer` each frame. `nil` while inactive, so a
    /// stopped timer leaves no stale snapshot behind for the brains/renderer to trip on.
    public func snapshot(now: Double) -> TimerState? {
        guard active else { return nil }
        return TimerState(active: active, running: running, durationMs: durationMs, elapsedMs: elapsedMs(now: now))
    }
}
