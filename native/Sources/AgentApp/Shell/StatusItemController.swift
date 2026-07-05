import AppKit
import AgentCore

/// Menu-bar status item — the only UI chrome this accessory app has. Glyph is
/// config-driven (`config.statusItemTitle`) and never changes; the dropdown instead
/// shows the live agent state, rebuilt fresh each time it opens (`NSMenuDelegate.
/// menuNeedsUpdate`) rather than pushed per tick, since menu contents only matter while
/// the menu is actually visible. Quit stays pinned at the bottom.
public final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    /// Pull hook for live state — set by `AppDelegate` to read its current `AgentState`.
    /// `nil`/omitted just yields an empty-sections summary (e.g. before first tick).
    public var summaryProvider: (() -> StatusSummary)?

    public init(title: String) {
        // .variableLength, not .squareLength — the latter is sized for an icon-only
        // button and clips a text/emoji title.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = title
        statusItem.isVisible = true

        menu.delegate = self
        statusItem.menu = menu
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let summary = summaryProvider?() ?? StatusSummary(sections: [])
        for item in StatusMenuBuilder.build(for: summary) {
            menu.addItem(item)
        }
    }
}
