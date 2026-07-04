import CoreGraphics

// Avatar-agnostic CGPath builders used by EmotionFaceSpec's per-emotion eye/mouth
// geometry and by concrete Avatar conformers for their body shape. Each approximates a
// CSS visual (solid bar, open border-arc, ring, filled dot, multi-radius rounded rect) —
// close, not pixel-identical; exact tuning against electron-poc/renderer/styles.css is
// Phase 6 polish, not blocking here.

/// Standard cubic-bezier "kappa" constant for approximating a quarter ellipse.
private let bezierKappa: CGFloat = 0.5523

/// A filled rounded bar — the base/thinking/annoyed eye look (CSS: solid background,
/// small `border-radius`).
public func barPath(size: CGSize, cornerRadius: CGFloat) -> CGPath {
    let r = min(cornerRadius, size.width / 2, size.height / 2)
    return CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// An open, stroked crescent — approximates CSS's "`border-top`/`border-bottom`: Npx
/// solid, `border-radius: 50%`, transparent background" eye/mouth look (happy/curious/
/// sleepy/blush). `opensDownward` picks the bottom arc (blush's "worried" look, sleepy's
/// mouth) vs. the top arc (happy/curious eyes).
public func crescentPath(size: CGSize, opensDownward: Bool) -> CGPath {
    let path = CGMutablePath()
    let rect = CGRect(origin: .zero, size: size)
    let transform = CGAffineTransform(scaleX: size.width / 2, y: size.height / 2)
        .concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
    let startAngle: CGFloat = opensDownward ? 0 : .pi
    let endAngle: CGFloat = opensDownward ? .pi : 2 * .pi
    path.addArc(center: .zero, radius: 1, startAngle: startAngle, endAngle: endAngle, clockwise: false, transform: transform)
    return path
}

/// A stroked, unfilled ring — the surprised eye look (CSS: `border` on all sides,
/// `border-radius: 50%`, transparent background).
public func ringPath(size: CGSize) -> CGPath {
    CGPath(ellipseIn: CGRect(origin: .zero, size: size), transform: nil)
}

/// A filled circle — the surprised mouth dot.
public func dotPath(size: CGSize) -> CGPath {
    CGPath(ellipseIn: CGRect(origin: .zero, size: size), transform: nil)
}

/// Independent per-corner elliptical radii, in px: (horizontal, vertical) for each of
/// the 4 corners — the general shape behind CSS's two-value `border-radius: H / V`
/// shorthand (e.g. `50% 50% 46% 46% / 70% 70% 30% 30%`).
public struct CornerRadii {
    public var topLeft: CGSize
    public var topRight: CGSize
    public var bottomRight: CGSize
    public var bottomLeft: CGSize

    public init(topLeft: CGSize, topRight: CGSize, bottomRight: CGSize, bottomLeft: CGSize) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }
}

/// A rounded rect with independent elliptical corner radii, each corner approximated by
/// a quarter-ellipse cubic bezier. Radii are scaled down (preserving proportions) if a
/// pair sharing an edge would otherwise overlap — the same overlap-avoidance CSS's
/// border-radius resolution does.
public func cornerRadiiPath(size: CGSize, radii: CornerRadii) -> CGPath {
    let w = size.width, h = size.height
    let fx = min(
        1,
        w / max(radii.topLeft.width + radii.topRight.width, 0.0001),
        w / max(radii.bottomLeft.width + radii.bottomRight.width, 0.0001)
    )
    let fy = min(
        1,
        h / max(radii.topLeft.height + radii.bottomLeft.height, 0.0001),
        h / max(radii.topRight.height + radii.bottomRight.height, 0.0001)
    )
    let tl = CGSize(width: radii.topLeft.width * fx, height: radii.topLeft.height * fy)
    let tr = CGSize(width: radii.topRight.width * fx, height: radii.topRight.height * fy)
    let br = CGSize(width: radii.bottomRight.width * fx, height: radii.bottomRight.height * fy)
    let bl = CGSize(width: radii.bottomLeft.width * fx, height: radii.bottomLeft.height * fy)
    let k = bezierKappa

    let path = CGMutablePath()
    path.move(to: CGPoint(x: tl.width, y: 0))
    path.addLine(to: CGPoint(x: w - tr.width, y: 0))
    path.addCurve(
        to: CGPoint(x: w, y: tr.height),
        control1: CGPoint(x: w - tr.width * (1 - k), y: 0),
        control2: CGPoint(x: w, y: tr.height * (1 - k))
    )
    path.addLine(to: CGPoint(x: w, y: h - br.height))
    path.addCurve(
        to: CGPoint(x: w - br.width, y: h),
        control1: CGPoint(x: w, y: h - br.height * (1 - k)),
        control2: CGPoint(x: w - br.width * (1 - k), y: h)
    )
    path.addLine(to: CGPoint(x: bl.width, y: h))
    path.addCurve(
        to: CGPoint(x: 0, y: h - bl.height),
        control1: CGPoint(x: bl.width * (1 - k), y: h),
        control2: CGPoint(x: 0, y: h - bl.height * (1 - k))
    )
    path.addLine(to: CGPoint(x: 0, y: tl.height))
    path.addCurve(
        to: CGPoint(x: tl.width, y: 0),
        control1: CGPoint(x: 0, y: tl.height * (1 - k)),
        control2: CGPoint(x: tl.width * (1 - k), y: 0)
    )
    path.closeSubpath()
    return path
}
