import Foundation

/// Descriptor for a single OS window: who owns it, its title, and its frame (web space).
/// Two `AgentWorld` fields use this shape with different sourcing:
/// - `windowBelow` — reserved for "what window is under the agent," deliberately
///   **unpopulated this round**. Reading it requires `CGWindowListCopyWindowInfo` /
///   Screen Recording permission (TCC-gated, re-prompts on every ad-hoc rebuild), which
///   this round's scope explicitly defers. Stays `nil`; this type exists so the shape of
///   a future populated value is already decided.
/// - `frontmostWindow` — the frontmost app's focused/main window, populated via the
///   Accessibility API (no Screen Recording prompt needed). Best-effort like
///   `typingLocation`: degrades to `nil` when the frontmost app exposes no AX window.
public struct WindowInfo: Codable, Equatable {
    public var ownerName: String
    public var title: String?
    public var frame: Rect

    public init(ownerName: String, title: String?, frame: Rect) {
        self.ownerName = ownerName
        self.title = title
        self.frame = frame
    }
}
