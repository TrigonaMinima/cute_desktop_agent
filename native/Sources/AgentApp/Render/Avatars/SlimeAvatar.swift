import AppKit
import QuartzCore
import AgentCore

// The ONLY file in the render layer permitted to contain the word "slime" — see the plan's
// naming discipline. This is the one concrete `Avatar` conformer today; a future avatar is a
// sibling file plus a `config.avatar` flip, touching nothing else in Render/. `AppConfig.
// makeAvatar()` is the sole place outside this file that names the type — it's the config-
// driven selection point the plan itself calls out, not a naming-discipline leak.
//
// Mechanical port of electron-poc/renderer/index.html's #blob layer tree and
// styles.css's #blob/.eye/.mouth/.blush rules (dome body #bfe8fb, navy #1c3b5a line-art
// faces, pink #f7a8c4 blush). Body dome bezier and inset gloss/shadow are a first-pass
// approximation of the CSS multi-radius `border-radius`/`box-shadow` — exact visual
// tuning is Phase 6 polish, not blocking here.
public struct SlimeAvatar: Avatar {
    // MARK: Body footprint + colors (electron-poc/renderer/styles.css `#blob`)

    private static let bodySize = CGSize(width: 78, height: 62)
    private static let bodyFill = NSColor(calibratedRed: 0.749, green: 0.910, blue: 0.984, alpha: 1).cgColor
    private static let navy = NSColor(calibratedRed: 0.1098, green: 0.2314, blue: 0.3529, alpha: 1).cgColor
    private static let blushPink = NSColor(calibratedRed: 0.9686, green: 0.6588, blue: 0.7686, alpha: 1).cgColor

    public var intrinsicSize: Size { Size(width: Double(Self.bodySize.width), height: Double(Self.bodySize.height)) }

    public init() {}

    // MARK: Layer tree (electron-poc/renderer/index.html's #blob children)

    public func buildLayerTree() -> AvatarLayers {
        let body = CAShapeLayer()
        body.bounds = CGRect(origin: .zero, size: Self.bodySize)
        body.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        body.path = cornerRadiiPath(size: Self.bodySize, radii: Self.domeRadii)
        body.fillColor = Self.bodyFill
        // box-shadow: 0 10px 16px rgba(20,60,100,.28) — the inset gloss/shade terms in
        // the CSS have no direct CALayer equivalent; the two highlight ellipses below
        // carry the gloss read for now (see file header).
        body.shadowColor = NSColor(calibratedRed: 0.078, green: 0.235, blue: 0.392, alpha: 0.28).cgColor
        body.shadowOffset = CGSize(width: 0, height: 10)
        body.shadowRadius = 8
        body.shadowOpacity = 1

        let highlight = CAShapeLayer()
        highlight.path = dotPath(size: CGSize(width: Self.bodySize.width * 0.36, height: Self.bodySize.height * 0.24))
        highlight.bounds = CGRect(origin: .zero, size: CGSize(width: Self.bodySize.width * 0.36, height: Self.bodySize.height * 0.24))
        highlight.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        highlight.position = CGPoint(
            x: Self.bodySize.width * 0.14 + Self.bodySize.width * 0.18,
            y: Self.bodySize.height * 0.10 + Self.bodySize.height * 0.12
        )
        highlight.fillColor = NSColor(white: 1, alpha: 0.9).cgColor
        highlight.transform = CATransform3DMakeRotation(-20 * .pi / 180, 0, 0, 1)

        let highlight2 = CAShapeLayer()
        let h2Size = CGSize(width: Self.bodySize.width * 0.09, height: Self.bodySize.height * 0.09)
        highlight2.path = dotPath(size: h2Size)
        highlight2.bounds = CGRect(origin: .zero, size: h2Size)
        highlight2.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        highlight2.position = CGPoint(
            x: Self.bodySize.width * 0.10 + h2Size.width / 2,
            y: Self.bodySize.height * 0.32 + h2Size.height / 2
        )
        highlight2.fillColor = NSColor(white: 1, alpha: 0.75).cgColor

        let eyeLeft = CAShapeLayer()
        let eyeRight = CAShapeLayer()
        let mouth = CAShapeLayer()
        [eyeLeft, eyeRight, mouth].forEach { $0.lineCap = .round }

        let blushLeft = CAShapeLayer()
        let blushRight = CAShapeLayer()
        let blushSize = CGSize(width: 12, height: 7)
        let blushLayers: [(CAShapeLayer, CGFloat)] = [(blushLeft, 0.11), (blushRight, 0.75)]
        for (blush, leftFraction) in blushLayers {
            blush.path = dotPath(size: blushSize)
            blush.bounds = CGRect(origin: .zero, size: blushSize)
            blush.anchorPoint = .zero
            blush.position = CGPoint(x: Self.bodySize.width * leftFraction, y: Self.bodySize.height * 0.52)
            blush.fillColor = Self.blushPink
            blush.opacity = 0
        }

        body.addSublayer(highlight)
        body.addSublayer(highlight2)
        body.addSublayer(eyeLeft)
        body.addSublayer(eyeRight)
        body.addSublayer(mouth)
        body.addSublayer(blushLeft)
        body.addSublayer(blushRight)

        let bubble = CATextLayer()
        bubble.fontSize = 15
        bubble.alignmentMode = .center
        bubble.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        bubble.bounds = CGRect(x: 0, y: 0, width: 24, height: 20)
        bubble.anchorPoint = .zero
        bubble.opacity = 0

        return AvatarLayers(
            body: body, eyeLeft: eyeLeft, eyeRight: eyeRight, mouth: mouth,
            blushLeft: blushLeft, blushRight: blushRight, bubble: bubble
        )
    }

    public func applySquash(_ motion: BodyMotion, to layers: AvatarLayers) {
        layers.body.transform = CATransform3DMakeScale(motion.scaleX, motion.scaleY, 1)
    }

    /// CSS `border-radius: 50% 50% 46% 46% / 70% 70% 30% 30%` on the 78x62 body —
    /// horizontal radii as % of width, vertical radii as % of height.
    private static let domeRadii = CornerRadii(
        topLeft: CGSize(width: bodySize.width * 0.50, height: bodySize.height * 0.70),
        topRight: CGSize(width: bodySize.width * 0.50, height: bodySize.height * 0.70),
        bottomRight: CGSize(width: bodySize.width * 0.46, height: bodySize.height * 0.30),
        bottomLeft: CGSize(width: bodySize.width * 0.46, height: bodySize.height * 0.30)
    )

    // MARK: Faces (electron-poc/renderer/styles.css `.eye`/`.mouth`/`#blob.emo-*`)

    // Base eye box position is constant across every emotion — CSS `position: absolute`
    // anchors top/left regardless of width/height overrides.
    private static let leftEyeTop = CGPoint(x: bodySize.width * 0.21, y: bodySize.height * 0.44)
    private static let rightEyeTop = CGPoint(x: bodySize.width * 0.60, y: bodySize.height * 0.44)
    private static let mouthTop = CGPoint(x: bodySize.width * 0.44, y: bodySize.height * 0.62)
    private static let center = CGPoint(x: 0.5, y: 0.5)

    public func faceSpec(for emotion: Emotion) -> EmotionFaceSpec {
        switch emotion {
        case .neutral:
            return Self.barFace(leftDeg: -6, rightDeg: 6, blush: .none)
        case .happy:
            return EmotionFaceSpec(
                leftEye: Self.crescentEye(origin: Self.leftEyeTop, size: CGSize(width: 17, height: 8), degrees: -8, opensDownward: false),
                rightEye: Self.crescentEye(origin: Self.rightEyeTop, size: CGSize(width: 17, height: 8), degrees: 10, opensDownward: false),
                mouth: MouthSpec(visible: false),
                blushStyle: .hatch
            )
        case .curious:
            return EmotionFaceSpec(
                leftEye: Self.crescentEye(
                    origin: CGPoint(x: Self.leftEyeTop.x, y: Self.leftEyeTop.y - 2),
                    size: CGSize(width: 15, height: 8), degrees: -12, opensDownward: false
                ),
                rightEye: Self.barEye(origin: Self.rightEyeTop, size: CGSize(width: 15, height: 3), degrees: 4),
                mouth: MouthSpec(visible: false),
                blushStyle: .none
            )
        case .surprised:
            let eyeSize = CGSize(width: 10, height: 10)
            let mouthSize = CGSize(width: 7, height: 7)
            return EmotionFaceSpec(
                leftEye: Self.ringEye(origin: Self.leftEyeTop, size: eyeSize),
                rightEye: Self.ringEye(origin: Self.rightEyeTop, size: eyeSize),
                mouth: MouthSpec(
                    visible: true, boxOrigin: Self.mouthTop, boxSize: mouthSize,
                    path: dotPath(size: mouthSize), fillColor: Self.navy
                ),
                blushStyle: .none
            )
        case .sleepy:
            let mouthSize = CGSize(width: 5.25, height: 5.25)
            let mouthOrigin = CGPoint(x: Self.mouthTop.x + (7 - 5.25) / 2, y: Self.mouthTop.y + (7 - 5.25) / 2)
            return EmotionFaceSpec(
                leftEye: Self.crescentEye(origin: Self.leftEyeTop, size: CGSize(width: 16, height: 8), degrees: 14, opensDownward: false),
                rightEye: Self.crescentEye(origin: Self.rightEyeTop, size: CGSize(width: 16, height: 8), degrees: -14, opensDownward: false),
                mouth: MouthSpec(
                    visible: true, boxOrigin: mouthOrigin, boxSize: mouthSize,
                    path: crescentPath(size: mouthSize, opensDownward: false), fillColor: nil,
                    strokeColor: Self.navy, lineWidth: 2
                ),
                blushStyle: .plain
            )
        case .thinking:
            return Self.pinchedBarFace(width: 15, degrees: 16, blush: .plain)
        case .annoyed:
            return Self.pinchedBarFace(width: 18, degrees: 24, blush: .none)
        case .blush:
            return EmotionFaceSpec(
                leftEye: Self.crescentEye(
                    origin: CGPoint(x: Self.leftEyeTop.x, y: Self.leftEyeTop.y - 3),
                    size: CGSize(width: 16, height: 8), degrees: -16, opensDownward: true
                ),
                rightEye: Self.crescentEye(
                    origin: CGPoint(x: Self.rightEyeTop.x, y: Self.rightEyeTop.y - 3),
                    size: CGSize(width: 16, height: 8), degrees: 16, opensDownward: true
                ),
                mouth: MouthSpec(visible: false),
                blushStyle: .hatch
            )
        }
    }

    private static func barFace(leftDeg: CGFloat, rightDeg: CGFloat, blush: BlushStyle) -> EmotionFaceSpec {
        EmotionFaceSpec(
            leftEye: barEye(origin: leftEyeTop, size: CGSize(width: 15, height: 3), degrees: leftDeg),
            rightEye: barEye(origin: rightEyeTop, size: CGSize(width: 15, height: 3), degrees: rightDeg),
            mouth: MouthSpec(visible: false),
            blushStyle: blush
        )
    }

    private static func pinchedBarFace(width: CGFloat, degrees: CGFloat, blush: BlushStyle) -> EmotionFaceSpec {
        EmotionFaceSpec(
            leftEye: barEye(origin: leftEyeTop, size: CGSize(width: width, height: 3), degrees: degrees, anchorFraction: CGPoint(x: 1, y: 0.5)),
            rightEye: barEye(origin: rightEyeTop, size: CGSize(width: width, height: 3), degrees: -degrees, anchorFraction: CGPoint(x: 0, y: 0.5)),
            mouth: MouthSpec(visible: false),
            blushStyle: blush
        )
    }

    private static func barEye(origin: CGPoint, size: CGSize, degrees: CGFloat, anchorFraction: CGPoint = center) -> EyeSpec {
        EyeSpec(
            boxOrigin: origin, boxSize: size, anchorFraction: anchorFraction, rotationDegrees: degrees,
            path: barPath(size: size, cornerRadius: 2), fillColor: navy, strokeColor: nil
        )
    }

    private static func crescentEye(origin: CGPoint, size: CGSize, degrees: CGFloat, opensDownward: Bool) -> EyeSpec {
        EyeSpec(
            boxOrigin: origin, boxSize: size, anchorFraction: center, rotationDegrees: degrees,
            path: crescentPath(size: size, opensDownward: opensDownward), fillColor: nil,
            strokeColor: navy, lineWidth: 2.5
        )
    }

    private static func ringEye(origin: CGPoint, size: CGSize) -> EyeSpec {
        EyeSpec(
            boxOrigin: origin, boxSize: size, anchorFraction: center, rotationDegrees: 0,
            path: ringPath(size: size), fillColor: nil, strokeColor: navy, lineWidth: 2.5
        )
    }
}
