import AppKit
import AgentCore

/// Owns one `NSMenu` and keeps it live while the user has it open — the status-item
/// dropdown and the avatar right-click menu each hold one of these so their rows track
/// the agent state as it changes, instead of freezing at whatever it was when the menu
/// was opened.
///
/// `NSMenuDelegate.menuNeedsUpdate(_:)` only fires once per open (pull-on-open), so a
/// second push is needed for updates *while* the menu is being shown. That push comes
/// from `refreshIfOpen()`, called once per frame from `AppDelegate`'s existing
/// `FrameClock` closure — the same closure that already reads `state` to render the
/// avatar, so this is one more read-only view of it, not a second writer or a second
/// timer. This works because `FrameClock`'s `CADisplayLink` is registered in `.common`
/// run-loop mode, which keeps it eligible to fire during `NSMenu`'s own tracking loop
/// (`NSEventTrackingRunLoopMode` is a `.common` mode) — confirmed empirically before this
/// was written: the display link kept ticking at its normal ~60Hz cadence across a
/// held-open menu with no multi-second stall.
public final class LiveMenuController: NSObject, NSMenuDelegate {
    /// Row text only ever changes at whole-tenths-of-a-second resolution (countdowns are
    /// formatted to one decimal — see `StatusSummary`'s `String(format:)` calls), so
    /// rebuilding on every ~60Hz frame is 5-6x more often than the text could ever visibly
    /// change. Throttling here keeps `refreshIfOpen` cheap without giving up the "ride the
    /// existing FrameClock, don't add a Timer" design.
    private static let refreshInterval: Double = 0.1

    public let menu = NSMenu()
    private let summaryProvider: () -> StatusSummary
    private var rowItems: [NSMenuItem] = []
    private var isOpen = false
    private var lastRefreshAt: Double?

    public init(summaryProvider: @escaping () -> StatusSummary) {
        self.summaryProvider = summaryProvider
        super.init()
        menu.delegate = self
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let built = StatusMenuBuilder.build(for: summaryProvider())
        for item in built.items {
            menu.addItem(item)
        }
        rowItems = built.rowItems
    }

    public func menuWillOpen(_ menu: NSMenu) {
        isOpen = true
    }

    public func menuDidClose(_ menu: NSMenu) {
        isOpen = false
    }

    /// Called once per frame; a no-op unless this menu is currently open, throttled to
    /// `refreshInterval` so it doesn't rebuild `StatusSummary` on every single frame.
    /// Updates row titles in place — headers, the separator, and Quit never change, so
    /// only the value rows need touching. Falls back to a full rebuild if the row count
    /// doesn't match (e.g. `StatusSummary`'s shape changed underfoot), rather than
    /// mutating past the end of `rowItems`.
    public func refreshIfOpen(now: Double) {
        guard isOpen else { return }
        if let lastRefreshAt, now - lastRefreshAt < Self.refreshInterval { return }
        lastRefreshAt = now

        let titles = StatusMenuBuilder.rowTitles(for: summaryProvider())
        guard titles.count == rowItems.count else {
            menuNeedsUpdate(menu)
            return
        }
        for (item, title) in zip(rowItems, titles) where item.title != title {
            item.title = title
        }
    }
}
