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

    /// - Parameter launchAtLogin: when non-nil, a "Launch at Login" toggle is inserted
    ///   between the state rows and Quit, sharing the trailing separator. `nil` omits it
    ///   entirely.
    /// - Parameter temperament: when non-nil (emergent brain only), a "Temperament"
    ///   preset submenu is inserted ahead of the login toggle. Like the toggle, it is
    ///   rebuilt per open rather than refreshed per frame — its checkmark only changes
    ///   through this very menu, which closes on selection.
    static func build(
        for summary: StatusSummary,
        launchAtLogin: LaunchAtLoginController? = nil,
        temperament: TemperamentMenuController? = nil
    ) -> Built {
        // `rowItems` is built by walking sections/rows in the same nested order as
        // `orderedRows(for:)` below (by construction: both are just `sections` then each
        // section's `rows`) — that shared order is what lets a live refresh `zip` these
        // items against `rowTitles(for:)`'s output. The login-item toggle below is
        // deliberately NOT added to `rowItems`: its title only changes across menu opens
        // (registration is user- or System-Settings-driven, not per-frame state), so it
        // doesn't need `refreshIfOpen`'s per-frame title push.
        var items: [NSMenuItem] = []
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
        if let temperament {
            items.append(temperament.menuItem())
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
