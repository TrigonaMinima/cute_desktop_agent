import Foundation

/// Perception snapshot of `NSWorkspace.frontmostApplication`, kept AppKit-free here —
/// `AgentApp`'s Perception layer is responsible for reading the real `NSRunningApplication`
/// and converting it to this struct each tick.
public struct AppInfo: Codable, Equatable {
    public var bundleIdentifier: String?
    public var name: String

    public init(bundleIdentifier: String?, name: String) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
    }
}
