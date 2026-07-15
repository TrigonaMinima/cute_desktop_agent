import AppKit
import AgentCore

/// Builds the full state-readout menu — section headers, disabled rows, a separator,
/// then Quit — shared by both the status-item dropdown (`StatusItemController`) and the
/// avatar's right-click menu (`AppDelegate`) so the two surfaces can never diverge, in
/// row content or in the trailing Quit item.
enum StatusMenuBuilder {
    /// A built menu's full item list, plus a handle to just the disabled value rows (in
    /// `StatusSummary` order) so callers can mutate their titles in place on a live refresh
    /// without rebuilding headers, the separator, or Quit.
    struct Built {
        let items: [NSMenuItem]
        let rowItems: [NSMenuItem]
    }

    /// - Parameter brain: the "Brain" submenu, pinned as the very first item ahead of a
    ///   separator — both brains always support switching, so this is never omitted (D21).
    /// - Parameter timer: the "Timer" submenu, pinned right after Brain — always present
    ///   (a timer can be started/ended regardless of which brain is live), its contents
    ///   swap between presets/Custom… and Pause-Resume/End based on whether a timer is
    ///   active at open time (see `TimerMenuController`).
    /// - Parameter launchAtLogin: when non-nil, a "Launch at Login" toggle is inserted
    ///   between the state rows and Quit, sharing the trailing separator. `nil` omits it
    ///   entirely.
    /// - Parameter temperament: always constructed by the caller now (D21); its
    ///   `menuItem()` returns nil for the classic brain (see its doc comment), in which
    ///   case the "Temperament" row is simply omitted. Present ahead of the login toggle
    ///   when non-nil. Like the toggle, it is rebuilt per open rather than refreshed per
    ///   frame — its checkmark only changes through this very menu, which closes on
    ///   selection.
    static func build(
        for summary: StatusSummary,
        brain: BrainMenuController,
        temperament: TemperamentMenuController,
        timer: TimerMenuController,
        launchAtLogin: LaunchAtLoginController? = nil
    ) -> Built {
        // `rowItems` is built by walking sections/rows in the same nested order as
        // `orderedRows(for:)` below (by construction: both are just `sections` then each
        // section's `rows`) — that shared order is what lets a live refresh `zip` these
        // items against `rowTitles(for:)`'s output. The Brain/Timer items and the
        // login-item toggle below are deliberately NOT added to `rowItems`: their content
        // only changes across menu opens (a brain swap, a timer start/end, or a login
        // registration change closes the menu first), not per-frame state, so none of
        // them needs `refreshIfOpen`'s per-frame title push.
        var items: [NSMenuItem] = [brain.menuItem(), timer.menuItem(), .separator()]
        var rowItems: [NSMenuItem] = []
        for section in summary.sections {
            items.append(.sectionHeader(title: section.title))
            for row in section.rows {
                let item = NSMenuItem(title: rowTitle(for: row), action: nil, keyEquivalent: "")
                item.isEnabled = false
                items.append(item)
                rowItems.append(item)
            }
        }
        items.append(.separator())
        if let temperamentItem = temperament.menuItem() {
            items.append(temperamentItem)
        }
        if let launchAtLogin {
            let presentation = loginItemPresentation(for: launchAtLogin.status)
            let toggle = NSMenuItem(
                title: presentation.title,
                action: #selector(LaunchAtLoginController.toggle(_:)),
                keyEquivalent: "")
            toggle.target = launchAtLogin
            toggle.state = presentation.isChecked ? .on : .off
            toggle.isEnabled = presentation.isEnabled
            items.append(toggle)
        }
        items.append(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return Built(items: items, rowItems: rowItems)
    }

    /// The same `"label: value"` strings `build(for:)` assigns to `rowItems`, in the same
    /// order — used by a live refresh to update an already-built menu's row titles without
    /// rebuilding it.
    static func rowTitles(for summary: StatusSummary) -> [String] {
        orderedRows(for: summary).map(rowTitle(for:))
    }

    /// The single canonical row order both `build(for:)` and `rowTitles(for:)` rely on —
    /// factored out so there is exactly one traversal to keep in sync, not two that merely
    /// happen to agree.
    private static func orderedRows(for summary: StatusSummary) -> [StatusSummary.Row] {
        summary.sections.flatMap { $0.rows }
    }

    private static func rowTitle(for row: StatusSummary.Row) -> String {
        "\(row.label): \(row.value)"
    }
}
