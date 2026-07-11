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

    /// This panel's display's full-frame origin in GLOBAL web space. `AgentState` works
    /// in global web coordinates spanning all displays; each panel only covers its own
    /// display — so `render` subtracts this to place layers view-locally, and the mouse
    /// closures below add it back so `AppDelegate` (and through it the state machine)
    /// only ever sees global web points. Zero for the primary display's panel.
    public var worldOrigin: Point = Point(x: 0, y: 0)

    /// Forwarded raw `NSResponder` mouse events — this view has no state of its own to
    /// mutate; `AppDelegate` owns translating these into `StateMachine.beginDrag`/
    /// `updateDrag`/`endDrag` calls, preserving single-writer discipline on `AgentState`.
    /// The point passed is already converted from this view's (flipped, top-left-origin)
    /// local space into global web space via `worldOrigin` — no conversion needed by the
    /// receiver.
    public var onMouseDown: ((CGPoint) -> Void)?
    public var onMouseDragged: ((CGPoint) -> Void)?
    public var onMouseUp: (() -> Void)?

    /// Builds the right-click context menu for a click at `point` (same global web
    /// space as the closures above). `AppDelegate` guards this
    /// with the same `AgentCore.isHovering` box check `updateHitTest` uses and returns
    /// `nil` for a click that lands off the avatar during the one-frame window before
    /// hit-testing catches up.
    public var onBuildContextMenu: ((CGPoint) -> NSMenu?)?

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
        onMouseDown?(webPoint(from: event))
    }

    public override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(webPoint(from: event))
    }

    public override func mouseUp(with event: NSEvent) {
        onMouseUp?()
    }

    /// View-local (flipped) event location + this panel's `worldOrigin` = global web point.
    private func webPoint(from event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + CGFloat(worldOrigin.x), y: local.y + CGFloat(worldOrigin.y))
    }

    /// Right-click path. AppKit owns popup positioning and runs its own tracking loop
    /// for the returned menu, so — unlike a manual `rightMouseDown` + `NSMenu.popUp` —
    /// this needs no coordination with the `CADisplayLink`-driven frame clock or the
    /// panel's per-frame `ignoresMouseEvents` toggling.
    public override func menu(for event: NSEvent) -> NSMenu? {
        onBuildContextMenu?(webPoint(from: event))
    }

    /// Applies one frame of `state` to the layer tree. Every per-frame layer write is
    /// wrapped with implicit actions disabled — otherwise Core Animation's ~0.25s
    /// implicit animation smears the display-link-driven squash/position into a visible
    /// lag. Explicit animations (the bubble-pop keyframe animation below) are unaffected
    /// by `setDisableActions` and still play.
    ///
    /// `motion` is passed in rather than derived here: `computeBodyMotion` is
    /// panel-invariant (a pure function of `(state, now)`), and this method runs once
    /// per attached display each frame — `AppDelegate.tick` computes it once and shares
    /// it across every panel's render.
    public func render(state: AgentState, motion: BodyMotion) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let size = avatar.intrinsicSize
        // Global web position → this panel's local space. A position on another display
        // simply lands outside this view's bounds and the window server clips it — which
        // is exactly how a mid-glide avatar straddling two adjacent displays renders
        // seamlessly across both panels.
        let origin = CGPoint(
            x: CGFloat(state.body.position.x - worldOrigin.x),
            y: CGFloat(state.body.position.y - worldOrigin.y)
        )
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

        // Blink and gaze are transients on top of the applied face, re-composed every
        // frame (independent of the emotion-change branch above) since they change far
        // more often than the emotion does.
        if let face = currentFace {
            let gaze = CGPoint(
                x: CGFloat(motion.gazeDirection.dx) * gazeEyeDeflectionPx,
                y: CGFloat(motion.gazeDirection.dy) * gazeEyeDeflectionPx
            )
            applyEyeTransform(face.leftEye, blinking: state.memory.blinking, gazeOffset: gaze, to: layers.eyeLeft)
            applyEyeTransform(face.rightEye, blinking: state.memory.blinking, gazeOffset: gaze, to: layers.eyeRight)
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

    /// Max px the eyes shift toward the gaze target at full deflection — the emergent
    /// gaze spine made visible. Subtle on purpose: the eyes glance, they don't roam.
    /// The direction itself arrives pre-computed in `BodyMotion.gazeDirection` (already
    /// unit-clamped; web space and this flipped view share the same y-down axis, so no
    /// conversion) — this view never reads `state.mind`.
    private let gazeEyeDeflectionPx: CGFloat = 3

    private func applyEyeTransform(
        _ spec: EyeSpec, blinking: Bool, gazeOffset: CGPoint, to layer: CAShapeLayer
    ) {
        // Right-to-left on the layer: rotate/blink the eye shape in place, then shift
        // the whole eye toward the gaze point.
        let shift = CATransform3DMakeTranslation(gazeOffset.x, gazeOffset.y, 0)
        let rotated = CATransform3DRotate(shift, spec.rotationDegrees * .pi / 180, 0, 0, 1)
        let blinkScaleY: CGFloat = blinking ? 0.15 : 1
        layer.transform = CATransform3DScale(rotated, 1, blinkScaleY, 1)
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
