import AppKit
import ServiceManagement
import AgentCore

/// Thin wrapper around `SMAppService.mainApp` — the modern (macOS 13+) login-item API,
/// which needs no separate helper bundle or LaunchAgent plist for a plain `LSUIElement`
/// app like this one. Not unit-tested: the actual registration is a real system side
/// effect that can't run headless (mirrors the repo convention that the AppKit shell is
/// driven manually via `make native-run`, not `swift test`). The pure part — how a
/// status renders as a menu row — lives in `AgentCore`'s `loginItemPresentation(for:)`
/// so *that* logic is covered by `make native-test`.
///
/// Held as a stored property by `AppDelegate` (not just passed through), because
/// `NSMenuItem.target` is a weak reference — nothing else would keep this alive between
/// menu opens.
public final class LaunchAtLoginController: NSObject {
    /// Reads `SMAppService.mainApp.status` fresh on every access — cheap, and the menu
    /// only reads this once per open (`StatusMenuBuilder.build`) plus doesn't need it to
    /// be pushed into `refreshIfOpen`'s per-frame update, since login-item state doesn't
    /// change from outside the menu itself.
    public var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    /// The "Launch at Login" menu item's action. Routes off the same
    /// `loginItemPresentation(for:)` the menu row itself was built from — rather than
    /// re-switching on `status` — so the "does this state open Settings instead of
    /// toggling?" decision has exactly one place it's made. `register()`/`unregister()`
    /// throw (the OS can refuse either), so failures are logged rather than propagated —
    /// there's no UI to surface an error into beyond the row itself, which self-corrects
    /// on the next menu open by re-reading `status`.
    @objc public func toggle(_ sender: Any?) {
        let presentation = loginItemPresentation(for: status)
        if presentation.opensSystemSettings {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        guard presentation.isEnabled else { return } // .notFound: nothing a click can do.
        do {
            if presentation.isChecked {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let action = presentation.isChecked ? "unregister" : "register"
            NSLog("LaunchAtLoginController: \(action)() failed: \(error)")
        }
    }
}
