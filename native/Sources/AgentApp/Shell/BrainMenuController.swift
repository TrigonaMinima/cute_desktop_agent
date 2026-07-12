import AppKit
import AgentCore

/// The "Brain" submenu both status surfaces embed, pinned as the very first item (see
/// `StatusMenuBuilder.build`): `BrainKind.allCases`, checkmarked at the currently live
/// brain. Selecting a row asks `AppDelegate` to swap the live brain in place — unlike
/// `TemperamentMenuController`'s presets, both brains always support switching, so this
/// controller (and its menu item) is never optional.
public final class BrainMenuController: NSObject {
    private let current: () -> BrainKind
    private let onSelect: (BrainKind) -> Void

    public init(
        current: @escaping () -> BrainKind,
        onSelect: @escaping (BrainKind) -> Void
    ) {
        self.current = current
        self.onSelect = onSelect
    }

    /// A freshly built "Brain" item with its kind submenu. Built per menu open (the live
    /// menus rebuild in `menuNeedsUpdate`), so the checkmark always reflects the live
    /// brain at open time. `NSMenuItem` holds its target weakly — the menu controllers
    /// retain this object, which is what keeps the actions alive.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Brain", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Brain")
        let selected = current()
        for kind in BrainKind.allCases {
            let row = NSMenuItem(
                title: kind.displayName, action: #selector(select(_:)), keyEquivalent: ""
            )
            row.target = self
            row.representedObject = kind
            row.state = kind == selected ? .on : .off
            submenu.addItem(row)
        }
        item.submenu = submenu
        return item
    }

    @objc private func select(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? BrainKind else { return }
        onSelect(kind)
    }
}
