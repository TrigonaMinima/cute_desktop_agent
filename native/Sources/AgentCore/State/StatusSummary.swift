import Foundation

/// A pure, ordered readout of a frozen `AgentState`, meant to be rendered verbatim by
/// both AppKit surfaces that expose agent state to the user (the menu-bar dropdown and
/// the avatar's right-click menu) — a single shared shape so the two can never disagree.
/// Built once, on demand (menu-open), never diffed per frame: see
/// `AgentState.statusSummary(now:)` below.
public struct StatusSummary: Equatable {
    public struct Row: Equatable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public struct Section: Equatable {
        public let title: String
        public let rows: [Row]

        public init(title: String, rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    public let sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections
    }
}

public extension AgentState {
    /// Builds a `StatusSummary` from this frozen state. `now` (same ms clock as
    /// everywhere else in `AgentCore` — see `Clock.swift`) is taken explicitly, not read
    /// from a hidden clock, so memory-timer countdowns stay pure and testable.
    func statusSummary(now: Double) -> StatusSummary {
        StatusSummary(sections: [
            StatusSummary.Section(title: "Body", rows: [
                .init(label: "Mode", value: StatusSummary.displayName(for: body.mode)),
                .init(label: "Emotion", value: StatusSummary.displayName(for: body.emotion)),
                .init(label: "Moving", value: StatusSummary.yesNo(body.moving)),
                .init(label: "Dragging", value: StatusSummary.yesNo(body.dragging)),
                .init(label: "Position", value: StatusSummary.formatPoint(body.position)),
                .init(label: "On screen", value: StatusSummary.formatOnScreen(position: body.position, screens: world.screens)),
                .init(label: "Target", value: StatusSummary.formatPoint(body.target)),
                .init(label: "Size", value: StatusSummary.formatSize(body.size)),
                .init(label: "Avoiding", value: body.attentionZone.map(StatusSummary.formatRect) ?? "\u{2014}"),
            ]),
            StatusSummary.Section(title: "World", rows: [
                .init(label: "Cursor", value: StatusSummary.formatPoint(world.cursor)),
                .init(label: "Cursor moving", value: StatusSummary.formatCursorMoving(world)),
                .init(label: "Frontmost app", value: world.frontmostApp?.name ?? "\u{2014}"),
                .init(label: "Screens", value: StatusSummary.formatScreens(world.screens)),
                .init(label: "Typing", value: StatusSummary.yesNo(world.typing)),
                .init(label: "Typing location", value: world.typingLocation.map(StatusSummary.formatRect) ?? "\u{2014}"),
                .init(label: "Scrolling", value: StatusSummary.formatScrolling(world)),
            ]),
            StatusSummary.Section(title: "Memory", rows: [
                .init(label: "Mode ends", value: StatusSummary.formatCountdown(target: memory.modeEndsAt, now: now)),
                .init(label: "Blinking", value: StatusSummary.yesNo(memory.blinking)),
                .init(label: "Next blink", value: StatusSummary.formatCountdown(target: memory.nextBlinkAt, now: now)),
                .init(label: "Quirk emotion", value: memory.quirkEmotion.map(StatusSummary.displayName) ?? "none"),
                .init(
                    label: "Proximity cooldown",
                    value: StatusSummary.formatCountdown(target: memory.proximityCooldownUntil, now: now)
                ),
                .init(
                    label: "Yield cooldown",
                    value: StatusSummary.formatCountdown(target: memory.yieldCooldownUntil, now: now)
                ),
            ]),
        ])
    }
}

private extension StatusSummary {
    /// Exhaustive by construction (`switch`, not a dictionary lookup) so a future `Mode`
    /// case fails to compile here instead of silently falling back — unlike
    /// `Constants.baseEmotionByMode`/`modeDwellMsRange`, which deliberately omit `.happy`
    /// for the state machine's own purposes but would mislabel it if reused here.
    static func displayName(for mode: Mode) -> String {
        switch mode {
        case .idle: return "Idle"
        case .wander: return "Wandering"
        case .rest: return "Resting"
        case .happy: return "Happy"
        case .flee: return "Fleeing"
        }
    }

    /// Exhaustive by construction — see `displayName(for: Mode)` above.
    static func displayName(for emotion: Emotion) -> String {
        switch emotion {
        case .neutral: return "Neutral"
        case .happy: return "Happy"
        case .curious: return "Curious"
        case .surprised: return "Surprised"
        case .sleepy: return "Sleepy"
        case .thinking: return "Thinking"
        case .annoyed: return "Annoyed"
        case .blush: return "Blushing"
        }
    }

    static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    static func formatPoint(_ point: Point) -> String {
        "(\(Int(point.x.rounded())), \(Int(point.y.rounded())))"
    }

    static func formatSize(_ size: Size) -> String {
        "\(Int(size.width.rounded()))\u{00D7}\(Int(size.height.rounded()))"
    }

    static func formatCursorMoving(_ world: AgentWorld) -> String {
        guard world.cursorMoving else { return "no" }
        return "yes (\(Int(world.cursorVelocity.magnitude.rounded())) px/s)"
    }

    static func formatScrolling(_ world: AgentWorld) -> String {
        guard world.scrolling else { return "no" }
        return "yes (\(Int(world.scrollVelocity.magnitude.rounded())) px/s)"
    }

    static func formatRect(_ rect: Rect) -> String {
        "\(formatPoint(rect.origin)) \(formatSize(rect.size))"
    }

    /// "1 of 2 (Main)" — which display the avatar is on right now, via the same
    /// `nearestScreenIndex` the state machine confines with, so a dead-zone position
    /// (mid-glide between non-aligned displays) reads as its closest screen instead of
    /// "nowhere". 1-based, matching how people count monitors.
    static func formatOnScreen(position: Point, screens: [ScreenInfo]) -> String {
        let index = nearestScreenIndex(to: position, screens: screens)
        return "\(index + 1) of \(screens.count) (\(screens[index].name))"
    }

    /// "2: Main 1000×800; Side 800×600" — count, then each display's name and size in
    /// list order (index 0 is always the primary).
    static func formatScreens(_ screens: [ScreenInfo]) -> String {
        let entries = screens.map { "\($0.name) \(formatSize($0.frame.size))" }
        return "\(screens.count): \(entries.joined(separator: "; "))"
    }

    /// `target`/`now` are both ms (see `Clock.swift`); rendered as seconds to one
    /// decimal place. A timer already in the past (or exactly due) reads "now" rather
    /// than a negative countdown.
    static func formatCountdown(target: Double, now: Double) -> String {
        let remainingMs = target - now
        guard remainingMs > 0 else { return "now" }
        return String(format: "in %.1fs", remainingMs / 1000)
    }
}
