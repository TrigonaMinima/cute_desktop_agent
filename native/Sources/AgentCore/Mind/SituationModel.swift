import Foundation

/// The situation model (design doc layer 3): collapses the perceived world into one
/// coarse `SituationMode` via rule-based thresholds on cheap signals only, with its own
/// commit hysteresis — a raw candidate must hold continuously for
/// `MindConstants.situationSwitchDwellMs` before the committed mode moves, so the mode
/// conditions everything below it without flickering.
///
/// Priority order of the rules (see `rawMode`):
/// 1. media/watching — frontmost window effectively fullscreen and hands off for a few
///    seconds. Checked before idle/away on purpose: a 90-minute movie is zero input but
///    the user is present, so fullscreen-and-quiet must never age into "away".
/// 2. idle/away — no input activity (typing, scrolling, cursor motion) past the
///    threshold.
/// 3. focus/typing — actively typing.
/// 4. casual/browsing — everything else.
///
/// v0 has no true "audio/video playing" cheap signal on macOS, so media detection is the
/// fullscreen-plus-stillness proxy (decision log D6) — the frozen label is the contract,
/// the detector is replaceable.
public struct SituationModel: Codable, Equatable {
    /// The committed mode — only moves after a candidate survives the dwell window.
    public private(set) var mode: SituationMode
    /// The raw candidate currently trying to displace `mode`, and since when (ms).
    var candidateMode: SituationMode
    var candidateSince: Double
    /// When input activity (typing/scrolling/cursor motion) was last observed (ms).
    /// Boot counts as activity: a fresh launch shouldn't open in idle/away.
    var lastActivityAt: Double

    public init(now: Double) {
        mode = .casualBrowsing
        candidateMode = .casualBrowsing
        candidateSince = now
        lastActivityAt = now
    }

    /// One cognition tick: refresh the activity baseline, classify raw, and commit only
    /// past the dwell. Same-as-committed candidates reset the window, so a mode must be
    /// *continuously* contradicted to change.
    public mutating func update(world: AgentWorld, now: Double) {
        if Self.hasInputActivity(world) {
            lastActivityAt = now
        }
        let raw = Self.rawMode(world: world, secondsSinceActivity: secondsSinceActivity(now: now))
        if raw == mode {
            candidateMode = raw
            candidateSince = now
            return
        }
        if raw != candidateMode {
            candidateMode = raw
            candidateSince = now
            return
        }
        if now - candidateSince >= MindConstants.situationSwitchDwellMs {
            mode = raw
        }
    }

    /// Seconds since the last observed input activity — also consumed by the doze/sleep
    /// power policy, which tiers off the same idle signal this model produces.
    public func secondsSinceActivity(now: Double) -> Double {
        max(0, now - lastActivityAt) / 1000
    }

    /// Typing, scrolling, or real cursor motion. `cursorMoving` already floors OS jitter.
    static func hasInputActivity(_ world: AgentWorld) -> Bool {
        world.typing || world.scrolling || world.cursorMoving
    }

    /// The stateless classification rules — see the type doc comment for the priority
    /// rationale. Split from `update` so the thresholds are testable without simulating
    /// dwell windows.
    static func rawMode(world: AgentWorld, secondsSinceActivity: Double) -> SituationMode {
        if isEffectivelyFullscreen(window: world.frontmostWindow, screens: world.screens),
           secondsSinceActivity >= MindConstants.mediaStillnessSeconds {
            return .mediaWatching
        }
        if secondsSinceActivity >= MindConstants.idleAwayAfterSeconds {
            return .idleAway
        }
        if world.typing {
            return .focusTyping
        }
        return .casualBrowsing
    }

    /// Whether `window` covers (essentially all of) its nearest screen — the v0 media
    /// surface proxy. Area-ratio test, not frame equality, so a fullscreen window that
    /// hangs a few pixels over (or a menu-bar-inset visibleFrame mismatch) still counts.
    static func isEffectivelyFullscreen(window: WindowInfo?, screens: [ScreenInfo]) -> Bool {
        guard let window else { return false }
        let center = Point(
            x: window.frame.origin.x + window.frame.size.width / 2,
            y: window.frame.origin.y + window.frame.size.height / 2
        )
        let screen = nearestScreen(to: center, screens: screens).frame
        let screenArea = screen.size.width * screen.size.height
        guard screenArea > 0 else { return false }
        return intersectionArea(window.frame, screen) / screenArea
            >= MindConstants.fullscreenCoverageRatio
    }

    private static func intersectionArea(_ a: Rect, _ b: Rect) -> Double {
        let width = min(a.origin.x + a.size.width, b.origin.x + b.size.width)
            - max(a.origin.x, b.origin.x)
        let height = min(a.origin.y + a.size.height, b.origin.y + b.size.height)
            - max(a.origin.y, b.origin.y)
        return max(0, width) * max(0, height)
    }
}
