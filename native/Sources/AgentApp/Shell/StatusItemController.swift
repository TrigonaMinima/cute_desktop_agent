import AppKit

/// Menu-bar status item — the only UI chrome this accessory app has. Glyph is
/// config-driven (`config.statusItemTitle`); its one action is Quit.
public final class StatusItemController {
    private let statusItem: NSStatusItem

    public init(title: String) {
        // .variableLength, not .squareLength — the latter is sized for an icon-only
        // button and clips a text/emoji title.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = title
        statusItem.isVisible = true

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }
}
