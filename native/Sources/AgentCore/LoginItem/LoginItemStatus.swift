import Foundation

/// An AppKit/ServiceManagement-free mirror of `SMAppService.Status`, so the
/// status→presentation mapping below can live here in `AgentCore` (Foundation-only,
/// unit-testable) rather than in the AppKit shell. `AgentApp`'s
/// `LaunchAtLoginController` is the only place that translates a real `SMAppService.Status`
/// into this enum.
public enum LoginItemStatus {
    /// Registered and approved — the app will launch at login.
    case enabled
    /// Registered, but the user must flip it on in System Settings > General > Login
    /// Items before it takes effect. A naive boolean mapping (`== .enabled`) collapses
    /// this into "off" and gives the user no way to discover why toggling again does
    /// nothing — this case exists to keep that distinction visible.
    case requiresApproval
    /// Never registered (the default, un-toggled state).
    case notRegistered
    /// The app isn't eligible for registration (e.g. running unbundled, or some other
    /// environment `SMAppService` refuses). Surfaced as a disabled row rather than a
    /// toggle that silently fails.
    case notFound
}

/// How a `LoginItemStatus` should render as the "Launch at Login" menu row — title,
/// checkmark, enabled state, and whether clicking it should deep-link to System Settings
/// instead of toggling registration directly.
public struct LoginItemPresentation: Equatable {
    public let title: String
    public let isChecked: Bool
    public let isEnabled: Bool
    public let opensSystemSettings: Bool

    public init(title: String, isChecked: Bool, isEnabled: Bool, opensSystemSettings: Bool) {
        self.title = title
        self.isChecked = isChecked
        self.isEnabled = isEnabled
        self.opensSystemSettings = opensSystemSettings
    }
}

/// The single source of truth for how each `LoginItemStatus` renders in the menu — kept
/// as one pure function (rather than inlined at each call site) so all four states are
/// enumerated exactly once and can't drift out of sync between the status-item dropdown
/// and the avatar right-click menu.
public func loginItemPresentation(for status: LoginItemStatus) -> LoginItemPresentation {
    switch status {
    case .enabled:
        return LoginItemPresentation(
            title: "Launch at Login", isChecked: true, isEnabled: true, opensSystemSettings: false)
    case .notRegistered:
        return LoginItemPresentation(
            title: "Launch at Login", isChecked: false, isEnabled: true, opensSystemSettings: false)
    case .requiresApproval:
        return LoginItemPresentation(
            title: "Launch at Login (Approve in Settings…)", isChecked: false, isEnabled: true,
            opensSystemSettings: true)
    case .notFound:
        return LoginItemPresentation(
            title: "Launch at Login (Unavailable)", isChecked: false, isEnabled: false,
            opensSystemSettings: false)
    }
}
