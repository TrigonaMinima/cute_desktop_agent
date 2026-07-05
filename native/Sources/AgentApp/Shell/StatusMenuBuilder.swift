import AppKit
import AgentCore

/// Builds the full state-readout menu — section headers, disabled rows, a separator,
/// then Quit — shared by both the status-item dropdown (`StatusItemController`) and the
/// avatar's right-click menu (`AppDelegate`) so the two surfaces can never diverge, in
/// row content or in the trailing Quit item.
enum StatusMenuBuilder {
    static func build(for summary: StatusSummary) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for section in summary.sections {
            items.append(.sectionHeader(title: section.title))
            for row in section.rows {
                let item = NSMenuItem(title: "\(row.label): \(row.value)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                items.append(item)
            }
        }
        items.append(.separator())
        items.append(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return items
    }
}
