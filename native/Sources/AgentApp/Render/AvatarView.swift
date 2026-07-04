import AppKit
import QuartzCore
import AgentCore

/// Layer-backed host for the active `Avatar`. Generic over any conformer — everything
/// avatar-specific comes through the `Avatar` protocol; this file owns the per-frame
/// orchestration that's the same regardless of shape: positioning, squash, blink,
/// emotion diffing, and the bubble-pop animation.
///
/// `isFlipped = true` puts the view's own layer coordinate space in top-left-origin,
/// y-down — the same space `AgentCore`'s `Point`/`Rect` math uses — so `AgentBody.position`
/// maps straight into `CALayer.position` with no per-frame arithmetic.
public final class AvatarView: NSView {
    private let avatar: Avatar
    private let layers: AvatarLayers
    private var appliedEmotion: Emotion?
    private var currentFace: EmotionFaceSpec?

    /// Forwarded raw `NSResponder` mouse events — this view has no state of its own to
    /// mutate; `AppDelegate` owns translating these into `StateMachine.beginDrag`/
    /// `updateDrag`/`endDrag` calls, preserving single-writer discipline on `AgentState`.
    /// The point passed is already in this view's (flipped, top-left-origin) coordinate
    /// space, i.e. the same "web space" `AgentBody.position` uses — no conversion needed.
    public var onMouseDown: ((CGPoint) -> Void)?
    public var onMouseDragged: ((CGPoint) -> Void)?
    public var onMouseUp: (() -> Void)?

    public override var isFlipped: Bool { true }

    public init(avatar: Avatar) {
        self.avatar = avatar
        self.layers = avatar.buildLayerTree()
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(layers.body)
        layer?.addSublayer(layers.bubble)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override func mouseDown(with event: NSEvent) {
        onMouseDown?(convert(event.locationInWindow, from: nil))
    }

    public override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(convert(event.locationInWindow, from: nil))
    }

    public override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }

    /// Applies one frame of `state` to the layer tree. Every per-frame layer write is
    /// wrapped with implicit actions disabled — otherwise Core Animation's ~0.25s
    /// implicit animation smears the display-link-driven squash/position into a visible
    /// lag. Explicit animations (the bubble-pop keyframe animation below) are unaffected
    /// by `setDisableActions` and still play.
    public func render(state: AgentState, now: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let motion = computeBodyMotion(state: state, now: now)
        let size = avatar.intrinsicSize
        let origin = CGPoint(x: CGFloat(state.body.position.x), y: CGFloat(state.body.position.y))
        layers.body.position = CGPoint(
            x: origin.x + CGFloat(size.width) / 2,
            y: origin.y + CGFloat(size.height) / 2 + CGFloat(motion.bobY)
        )
        avatar.applySquash(motion, to: layers)

        if state.body.emotion != appliedEmotion {
            appliedEmotion = state.body.emotion
            let face = avatar.faceSpec(for: state.body.emotion)
            currentFace = face
            apply(face.leftEye, to: layers.eyeLeft)
            apply(face.rightEye, to: layers.eyeRight)
            apply(face.mouth, to: layers.mouth)
            applyBlush(face.blushStyle, left: layers.blushLeft, right: layers.blushRight)
            applyBubble(for: state.body.emotion)
        }

        // Blink is a transient on top of the applied face, re-composed every frame
        // (independent of the emotion-change branch above) since it toggles far more
        // often than the emotion does.
        if let face = currentFace {
            applyEyeTransform(face.leftEye, blinking: state.memory.blinking, to: layers.eyeLeft)
            applyEyeTransform(face.rightEye, blinking: state.memory.blinking, to: layers.eyeRight)
        }

        // blob.js: bubbleEl translate(state.x + BLOB_WIDTH/2 - 9, state.y - 16).
        layers.bubble.position = CGPoint(x: origin.x + CGFloat(size.width) / 2 - 9, y: origin.y - 16)

        CATransaction.commit()
    }

    // MARK: Eyes/mouth — box position/size/path/color change only on an emotion swap;
    // rotation + blink are recombined every frame by `applyEyeTransform`.

    private func applyBox(
        origin: CGPoint, size: CGSize, anchor: CGPoint,
        path: CGPath, fillColor: CGColor?, strokeColor: CGColor?, lineWidth: CGFloat,
        to layer: CAShapeLayer
    ) {
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.anchorPoint = anchor
        layer.position = CGPoint(x: origin.x + anchor.x * size.width, y: origin.y + anchor.y * size.height)
        layer.path = path
        layer.fillColor = fillColor
        layer.strokeColor = strokeColor
        layer.lineWidth = lineWidth
    }

    private func apply(_ spec: EyeSpec, to layer: CAShapeLayer) {
        applyBox(
            origin: spec.boxOrigin, size: spec.boxSize, anchor: spec.anchorFraction,
            path: spec.path, fillColor: spec.fillColor, strokeColor: spec.strokeColor, lineWidth: spec.lineWidth,
            to: layer
        )
    }

    private func applyEyeTransform(_ spec: EyeSpec, blinking: Bool, to layer: CAShapeLayer) {
        let rotation = CATransform3DMakeRotation(spec.rotationDegrees * .pi / 180, 0, 0, 1)
        let blinkScaleY: CGFloat = blinking ? 0.15 : 1
        layer.transform = CATransform3DScale(rotation, 1, blinkScaleY, 1)
    }

    private func apply(_ spec: MouthSpec, to layer: CAShapeLayer) {
        layer.isHidden = !spec.visible
        guard spec.visible else { return }
        applyBox(
            origin: spec.boxOrigin, size: spec.boxSize, anchor: CGPoint(x: 0.5, y: 0.5),
            path: spec.path, fillColor: spec.fillColor, strokeColor: spec.strokeColor, lineWidth: spec.lineWidth,
            to: layer
        )
    }

    // MARK: Blush — electron-poc/renderer/styles.css `.blush.show`/`.blush.hatch.show`
    // opacities. The hatch diagonal-line texture overlay is a visual detail deferred to
    // Phase 6 polish; only the opacity level is ported here.

    private func applyBlush(_ style: BlushStyle, left: CALayer, right: CALayer) {
        let opacity: Float
        switch style {
        case .none: opacity = 0
        case .plain: opacity = 0.55
        case .hatch: opacity = 0.85
        }
        left.opacity = opacity
        right.opacity = opacity
    }

    // MARK: Bubble — electron-poc/renderer/styles.css `@keyframes bubble-pop`.

    private func applyBubble(for emotion: Emotion) {
        guard let glyph = Constants.bubbleByEmotion[emotion] else {
            layers.bubble.opacity = 0
            return
        }
        layers.bubble.string = glyph
        layers.bubble.foregroundColor = NSColor.black.cgColor
        firePop(layers.bubble)
    }

    private func firePop(_ bubble: CATextLayer) {
        let times: [NSNumber] = [0, 0.2, 0.75, 1.0]
        let opacities: [NSNumber] = [0, 1, 1, 0]
        let transforms: [NSValue] = [
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(0.6, 0.6, 1), CATransform3DMakeTranslation(0, 4, 0))),
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(1.05, 1.05, 1), CATransform3DMakeTranslation(0, -4, 0))),
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(1, 1, 1), CATransform3DMakeTranslation(0, -8, 0))),
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale(0.9, 0.9, 1), CATransform3DMakeTranslation(0, -14, 0))),
        ]

        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.keyTimes = times
        opacityAnim.values = opacities

        let transformAnim = CAKeyframeAnimation(keyPath: "transform")
        transformAnim.keyTimes = times
        transformAnim.values = transforms

        let group = CAAnimationGroup()
        group.animations = [opacityAnim, transformAnim]
        group.duration = 1.1
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards

        bubble.opacity = 0 // model value once the fire-and-forget animation ends
        bubble.add(group, forKey: "bubble-pop")
    }
}
