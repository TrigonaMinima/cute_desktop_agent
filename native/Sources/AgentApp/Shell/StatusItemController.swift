import AppKit
import AgentCore

/// Menu-bar status item — the only UI chrome this accessory app has. Glyph is
/// config-driven (`config.statusItemTitle`) and never changes; the dropdown instead
/// shows the live agent state via a `LiveMenuController`, which rebuilds on open and
/// keeps refreshing while the dropdown stays open (see its doc comment). Quit stays
/// pinned at the bottom.
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let liveMenu: LiveMenuController

    /// - Parameter summaryProvider: pull hook for live state, read once per menu open and
    ///   again each frame while open. `AppDelegate` supplies one reading its current
    ///   `AgentState`; a `nil` state (e.g. before first tick) is its caller's concern, not
    ///   this type's.
    /// - Parameter launchAtLogin: forwarded straight through to the underlying
    ///   `LiveMenuController` so the "Launch at Login" row shows up in this dropdown too —
    ///   see `StatusMenuBuilder.build(for:launchAtLogin:temperament:)`.
    /// - Parameter temperament: forwarded the same way for the "Temperament" preset
    ///   submenu (emergent brain only).
    public init(
        title: String,
        summaryProvider: @escaping () -> StatusSummary,
        launchAtLogin: LaunchAtLoginController? = nil,
        temperament: TemperamentMenuController? = nil
    ) {
        // .variableLength, not .squareLength — the latter is sized for an icon-only
        // button and clips a text/emoji title.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        liveMenu = LiveMenuController(
            summaryProvider: summaryProvider, launchAtLogin: launchAtLogin,
            temperament: temperament
        )
        super.init()
        statusItem.button?.title = title
        statusItem.isVisible = true
        statusItem.menu = liveMenu.menu
    }

    /// Forwarded to the per-frame `FrameClock` tick by `AppDelegate` — a no-op unless the
    /// dropdown is currently open.
    public func refreshIfOpen(now: Double) {
        liveMenu.refreshIfOpen(now: now)
    }
}
