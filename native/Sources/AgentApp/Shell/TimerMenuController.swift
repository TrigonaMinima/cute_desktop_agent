import AppKit
import AgentCore

/// The "Timer" submenu both status surfaces embed — mirrors `BrainMenuController`'s
/// shape. Inactive: preset durations (5/15/25/45/60 min) plus a "Custom…" row that opens
/// `CustomTimerDialog`. Active: "End Timer" plus a Pause/Resume row, for parity with the
/// on-screen button (which stays the primary way to pause/resume).
public final class TimerMenuController: NSObject {
    static let presetMinutes = [5, 15, 25, 45, 60]

    private let isActive: () -> Bool
    private let isRunning: () -> Bool
    private let onStart: (Double) -> Void
    private let onEnd: () -> Void
    private let onTogglePause: () -> Void

    public init(
        isActive: @escaping () -> Bool,
        isRunning: @escaping () -> Bool,
        onStart: @escaping (Double) -> Void,
        onEnd: @escaping () -> Void,
        onTogglePause: @escaping () -> Void
    ) {
        self.isActive = isActive
        self.isRunning = isRunning
        self.onStart = onStart
        self.onEnd = onEnd
        self.onTogglePause = onTogglePause
    }

    /// A freshly built "Timer" item, its contents keyed on whether a timer is active at
    /// open time. Built per menu open (the live menus rebuild in `menuNeedsUpdate`), same
    /// discipline as `BrainMenuController`. `NSMenuItem` holds its target weakly — the
    /// menu controllers retain this object, which is what keeps the actions alive.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Timer", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Timer")
        if isActive() {
            let pauseRow = NSMenuItem(
                title: isRunning() ? "Pause" : "Resume", action: #selector(togglePause), keyEquivalent: ""
            )
            pauseRow.target = self
            submenu.addItem(pauseRow)
            let endRow = NSMenuItem(title: "End Timer", action: #selector(endTimer), keyEquivalent: "")
            endRow.target = self
            submenu.addItem(endRow)
        } else {
            for minutes in Self.presetMinutes {
                let row = NSMenuItem(
                    title: "\(minutes) min", action: #selector(selectPreset(_:)), keyEquivalent: ""
                )
                row.target = self
                row.representedObject = minutes
                submenu.addItem(row)
            }
            submenu.addItem(.separator())
            let customRow = NSMenuItem(title: "Custom…", action: #selector(selectCustom), keyEquivalent: "")
            customRow.target = self
            submenu.addItem(customRow)
        }
        item.submenu = submenu
        return item
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        onStart(Double(minutes) * 60_000)
    }

    /// "Custom…" duration entry. `CustomTimerDialog` briefly activates the accessory app
    /// (same tradeoff `NSAlert` had) — accepted per the plan, since Start/Custom are
    /// already menu-driven, infrequent actions, not something on the 60Hz render path.
    @objc private func selectCustom() {
        guard let minutes = CustomTimerDialog.run() else { return }
        onStart(minutes * 60_000)
    }

    @objc private func togglePause() {
        onTogglePause()
    }

    @objc private func endTimer() {
        onEnd()
    }
}
