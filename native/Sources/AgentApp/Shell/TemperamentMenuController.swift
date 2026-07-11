import AppKit
import AgentCore

/// The "Temperament" submenu both status surfaces embed (emergent brain only): the four
/// D10 presets, checkmarked at the current one. Selecting persists the preset and swaps
/// the live brain's vector (both wired by `AppDelegate`); the drives then ease toward
/// the new baselines on their own — a mood shift, not a personality transplant.
public final class TemperamentMenuController: NSObject {
    private let current: () -> TemperamentPreset?
    private let onSelect: (TemperamentPreset) -> Void

    public init(
        current: @escaping () -> TemperamentPreset?,
        onSelect: @escaping (TemperamentPreset) -> Void
    ) {
        self.current = current
        self.onSelect = onSelect
    }

    /// A freshly built "Temperament" item with its preset submenu. Built per menu open
    /// (the live menus rebuild in `menuNeedsUpdate`), so the checkmark always reflects
    /// the preset at open time. `NSMenuItem` holds its target weakly — the menu
    /// controllers retain this object, which is what keeps the actions alive.
    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Temperament", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Temperament")
        let selected = current()
        for preset in TemperamentPreset.allCases {
            let row = NSMenuItem(
                title: preset.displayName, action: #selector(select(_:)), keyEquivalent: ""
            )
            row.target = self
            row.representedObject = preset
            row.state = preset == selected ? .on : .off
            submenu.addItem(row)
        }
        item.submenu = submenu
        return item
    }

    @objc private func select(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? TemperamentPreset else { return }
        onSelect(preset)
    }
}
