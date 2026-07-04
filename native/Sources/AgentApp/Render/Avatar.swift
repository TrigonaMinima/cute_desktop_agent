import QuartzCore
import AgentCore

/// The layer handles `AvatarView` needs to drive per frame, returned once by
/// `Avatar.buildLayerTree()`. `eyeLeft`/`eyeRight`/`mouth` are exposed individually so
/// `AvatarView` can apply an `EmotionFaceSpec` (and the blink squash) without walking the
/// avatar's own sublayer tree on every call. `body` already contains every visual
/// sublayer (highlights, eyes, mouth, blush) as its `sublayers` — `bubble` is a sibling,
/// added directly to the hosting view's layer, since it moves independently of the body
/// (see blob.js's separate `bubbleEl.style.transform`).
public struct AvatarLayers {
    public let body: CALayer
    public let eyeLeft: CAShapeLayer
    public let eyeRight: CAShapeLayer
    public let mouth: CAShapeLayer
    public let blushLeft: CALayer
    public let blushRight: CALayer
    public let bubble: CATextLayer

    public init(
        body: CALayer, eyeLeft: CAShapeLayer, eyeRight: CAShapeLayer, mouth: CAShapeLayer,
        blushLeft: CALayer, blushRight: CALayer, bubble: CATextLayer
    ) {
        self.body = body
        self.eyeLeft = eyeLeft
        self.eyeRight = eyeRight
        self.mouth = mouth
        self.blushLeft = blushLeft
        self.blushRight = blushRight
        self.bubble = bubble
    }
}

/// The avatar-agnostic rendering seam — the only interface `AvatarView` depends on.
/// Concrete conformers (currently only one, under `Render/Avatars/`) own their own shape, colors, and
/// per-emotion face geometry; everything else (squash math, blink, emotion diffing,
/// bubble-pop animation, the frame clock) is generic and lives in `AvatarView`. Adding a
/// new avatar means adding a sibling conformer and flipping `config.avatar` — nothing
/// else changes.
public protocol Avatar {
    /// Footprint used both for `AgentBody.size` (behavior/collision) and to size this
    /// avatar's `CALayer` tree.
    var intrinsicSize: Size { get }

    /// Builds this avatar's full layer tree once, at launch. The body layer must have
    /// `anchorPoint = (0.5, 0.5)` so squash/stretch pivots about center, matching CSS
    /// `transform: scale()`.
    func buildLayerTree() -> AvatarLayers

    /// Per-emotion face geometry (eye paths/transforms, mouth visibility, blush style).
    func faceSpec(for emotion: Emotion) -> EmotionFaceSpec

    /// Applies this frame's squash/stretch to the body layer. Bob/position are handled
    /// generically by `AvatarView` (they only move the layer, they don't reshape it);
    /// squash is avatar-owned in case a future avatar wants a different pivot or to
    /// distribute the squash across more than one layer.
    func applySquash(_ motion: BodyMotion, to layers: AvatarLayers)
}
