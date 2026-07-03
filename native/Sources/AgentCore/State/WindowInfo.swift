import Foundation

/// Reserved perception type for "what window is under the agent" — deliberately
/// **unpopulated this round**. Reading it requires `CGWindowListCopyWindowInfo` /
/// Screen Recording permission (TCC-gated, re-prompts on every ad-hoc rebuild), which
/// this round's scope explicitly defers. `AgentWorld.windowBelow` stays `nil`; this
/// type exists so the shape of a future populated value is already decided.
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
