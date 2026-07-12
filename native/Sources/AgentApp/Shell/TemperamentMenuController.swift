import AppKit
import AgentCore

/// The "Temperament" submenu both status surfaces embed (emergent brain only): the four
/// D10 presets, checkmarked at the current one. Selecting persists the preset and swaps
/// the live brain's vector (both wired by `AppDelegate`); the drives then ease toward
/// the new baselines on their own — a mood shift, not a personality transplant.
///
/// Constructed unconditionally by `AppDelegate` (D21) — the live brain can now change
/// underfoot via the "Brain" menu, so this controller can't be built-or-omitted once at
/// launch the way it was before. `isAvailable` gates whether `menuItem()` returns a row
/// at all; `current` is deliberately a *separate* signal, because mid-ease (drives easing
/// toward a newly adopted preset's baselines) `current()` legitimately returns nil for an
/// available, emergent-backed menu — that nil must not be read as "unavailable".
public final class TemperamentMenuController: NSObject {
    private let isAvailable: () -> Bool
    private let current: () -> TemperamentPreset?
    private let onSelect: (TemperamentPreset) -> Void

    public init(
        isAvailable: @escaping () -> Bool,
        current: @escaping () -> TemperamentPreset?,
        onSelect: @escaping (TemperamentPreset) -> Void
    ) {
        self.isAvailable = isAvailable
        self.current = current
        self.onSelect = onSelect
    }

    /// A freshly built "Temperament" item with its preset submenu, or `nil` when the live
    /// brain doesn't support temperament (the classic brain). Built per menu open (the
    /// live menus rebuild in `menuNeedsUpdate`), so both availability and the checkmark
    /// always reflect the live brain at open time. `NSMenuItem` holds its target weakly —
    /// the menu controllers retain this object, which is what keeps the actions alive.
    func menuItem() -> NSMenuItem? {
        guard isAvailable() else { return nil }
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
