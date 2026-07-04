import CoreGraphics
import AgentCore

/// One eye layer's full geometry for a single emotion. `boxOrigin`/`boxSize` mirror the
/// CSS `left`/`top`/`width`/`height` box in the body layer's local space (top-left
/// origin, y down); `anchorFraction` mirrors CSS `transform-origin` as a fraction of
/// `boxSize` — (0.5, 0.5) unless overridden, since thinking/annoyed pivot from an outer
/// edge (`transform-origin: right center` / `left center`) so the lines converge rather
/// than just rotating in place. `path` is drawn in local (0,0)-`boxSize` coordinates.
public struct EyeSpec {
    public var boxOrigin: CGPoint
    public var boxSize: CGSize
    public var anchorFraction: CGPoint
    public var rotationDegrees: CGFloat
    public var path: CGPath
    public var fillColor: CGColor?
    public var strokeColor: CGColor?
    public var lineWidth: CGFloat

    public init(
        boxOrigin: CGPoint, boxSize: CGSize, anchorFraction: CGPoint = CGPoint(x: 0.5, y: 0.5),
        rotationDegrees: CGFloat, path: CGPath, fillColor: CGColor?, strokeColor: CGColor?,
        lineWidth: CGFloat = 0
    ) {
        self.boxOrigin = boxOrigin
        self.boxSize = boxSize
        self.anchorFraction = anchorFraction
        self.rotationDegrees = rotationDegrees
        self.path = path
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
    }
}

/// The mouth layer's geometry for a single emotion — hidden for neutral/wander/curious/
/// thinking/annoyed (CSS `opacity: 0`), shown for surprised/sleepy.
public struct MouthSpec {
    public var visible: Bool
    public var boxOrigin: CGPoint
    public var boxSize: CGSize
    public var path: CGPath
    public var fillColor: CGColor?
    public var strokeColor: CGColor?
    public var lineWidth: CGFloat

    public init(
        visible: Bool, boxOrigin: CGPoint = .zero, boxSize: CGSize = .zero,
        path: CGPath = CGMutablePath(), fillColor: CGColor? = nil, strokeColor: CGColor? = nil,
        lineWidth: CGFloat = 0
    ) {
        self.visible = visible
        self.boxOrigin = boxOrigin
        self.boxSize = boxSize
        self.path = path
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
    }
}

/// Per-emotion face geometry an `Avatar` hands back to `AvatarView` — the generic render
/// layer applies these to its eye/mouth/blush layers without knowing which concrete
/// avatar produced them. Mirrors electron-poc/renderer/styles.css's per-emotion
/// `.eye`/`.mouth`/`.blush` rules (`#blob.emo-*` selectors).
public struct EmotionFaceSpec {
    public var leftEye: EyeSpec
    public var rightEye: EyeSpec
    public var mouth: MouthSpec
    public var blushStyle: BlushStyle

    public init(leftEye: EyeSpec, rightEye: EyeSpec, mouth: MouthSpec, blushStyle: BlushStyle) {
        self.leftEye = leftEye
        self.rightEye = rightEye
        self.mouth = mouth
        self.blushStyle = blushStyle
    }
}
