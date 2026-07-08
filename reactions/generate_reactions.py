#!/usr/bin/env python3
"""Generate Jiggy's 8 reaction faces as standalone SVGs.

This is a mechanical, stdlib-only port of the Swift render code so the output
matches what the running app actually draws, not a re-imagining of it:

  - native/Sources/AgentApp/Render/Avatars/SlimeAvatar.swift  (body + faceSpec())
  - native/Sources/AgentApp/Render/PathShapes.swift           (bar/crescent/ring/dot/dome paths)
  - native/Sources/AgentApp/Render/AvatarView.swift            (blush opacity, bubble placement)
  - native/Sources/AgentCore/State/Constants.swift             (bubbleByEmotion glyphs)

The renderer's own coordinate space (`isFlipped = true`, top-left origin, y-down
"web space") is exactly SVG's coordinate space, so every coordinate, size, and
rotation angle below is copied straight from the Swift source with no flipping
or re-deriving.

Run directly (`python3 generate_reactions.py`) or via `make reactions` from the
repo root. Writes one `<emotion>.svg` per emotion into this directory.
"""
import os

OUT_DIR = os.path.dirname(os.path.abspath(__file__))

# ---- Body footprint + colors (SlimeAvatar.swift bodySize/bodyFill/navy/blushPink) ----

BODY_W, BODY_H = 78.0, 62.0
BODY_FILL = "#BFE8FB"
NAVY = "#1C3B5A"
BLUSH_PINK = "#F7A8C4"
SHADOW_RGB = "rgb(20,60,100)"   # NSColor(0.078, 0.235, 0.392) -> ~ (20, 60, 100)
SHADOW_OPACITY = 0.28
KAPPA = 0.5523                  # cubic-bezier "kappa" constant, PathShapes.swift

CENTER = (0.5, 0.5)

# Base eye/mouth anchor boxes, constant across every emotion (SlimeAvatar.swift 123-126)
LEFT_EYE_TOP = (BODY_W * 0.21, BODY_H * 0.44)   # (16.38, 27.28)
RIGHT_EYE_TOP = (BODY_W * 0.60, BODY_H * 0.44)  # (46.80, 27.28)
MOUTH_TOP = (BODY_W * 0.44, BODY_H * 0.62)      # (34.32, 38.44)


# ---- Path primitives (PathShapes.swift), each returning SVG markup in LOCAL
# ---- box coordinates (0,0)-(w,h) -- positioning/rotation is applied by the
# ---- caller via positioned_group().

def bar_shape(w, h, corner_radius, fill):
    """Filled rounded bar -- barPath(). Base/thinking/annoyed eyes."""
    r = min(corner_radius, w / 2, h / 2)
    return f'<rect x="0" y="0" width="{w}" height="{h}" rx="{r}" ry="{r}" fill="{fill}"/>'


def crescent_shape(w, h, opens_downward, stroke, stroke_width):
    """Open, stroked half-ellipse arc -- crescentPath(). opens_downward=False is
    the top arc (dome/rainbow "^"-like closed-eye look); True is the bottom arc
    (worried/blush "u"-like look)."""
    sweep = 0 if opens_downward else 1
    return (
        f'<path d="M 0,{h / 2} A {w / 2},{h / 2} 0 0 {sweep} {w},{h / 2}" '
        f'fill="none" stroke="{stroke}" stroke-width="{stroke_width}" stroke-linecap="round"/>'
    )


def ring_shape(w, h, stroke, stroke_width):
    """Stroked, unfilled ellipse -- ringPath(). Surprised eyes."""
    return (
        f'<ellipse cx="{w / 2}" cy="{h / 2}" rx="{w / 2}" ry="{h / 2}" '
        f'fill="none" stroke="{stroke}" stroke-width="{stroke_width}"/>'
    )


def dot_shape(w, h, fill):
    """Filled ellipse -- dotPath(). Surprised mouth, blush dots, gloss highlights."""
    return f'<ellipse cx="{w / 2}" cy="{h / 2}" rx="{w / 2}" ry="{h / 2}" fill="{fill}"/>'


def positioned_group(inner_svg, box_origin, box_size, anchor=CENTER, rotation_deg=0):
    """Wraps `inner_svg` (drawn in local (0,0)-box_size coords) in a <g> that
    reproduces CALayer's position/anchorPoint/transform composition:

        parent = (boxOrigin + anchor*size) + R * (local - anchor*size)

    i.e. translate to the pivot, rotate about it, then translate back so the
    shape lands at boxOrigin -- this is what makes thinking/annoyed's
    anchorFraction=(1,0.5)/(0,0.5) pivot from an outer edge instead of the
    box center, so the brows visually converge when rotated.
    """
    px = box_origin[0] + anchor[0] * box_size[0]
    py = box_origin[1] + anchor[1] * box_size[1]
    tx = -anchor[0] * box_size[0]
    ty = -anchor[1] * box_size[1]
    transform = f"translate({px:.4f},{py:.4f}) rotate({rotation_deg}) translate({tx:.4f},{ty:.4f})"
    return f'<g transform="{transform}">{inner_svg}</g>'


def dome_path():
    """Body dome -- cornerRadiiPath() with CSS border-radius
    `50% 50% 46% 46% / 70% 70% 30% 30%` baked in for the 78x62 body."""
    w, h = BODY_W, BODY_H
    tl = (w * 0.50, h * 0.70)
    tr = (w * 0.50, h * 0.70)
    br = (w * 0.46, h * 0.30)
    bl = (w * 0.46, h * 0.30)

    fx = min(1, w / max(tl[0] + tr[0], 0.0001), w / max(bl[0] + br[0], 0.0001))
    fy = min(1, h / max(tl[1] + bl[1], 0.0001), h / max(tr[1] + br[1], 0.0001))
    tl = (tl[0] * fx, tl[1] * fy)
    tr = (tr[0] * fx, tr[1] * fy)
    br = (br[0] * fx, br[1] * fy)
    bl = (bl[0] * fx, bl[1] * fy)
    k = KAPPA

    return " ".join([
        f"M {tl[0]},0",
        f"L {w - tr[0]},0",
        f"C {w - tr[0] * (1 - k)},0 {w},{tr[1] * (1 - k)} {w},{tr[1]}",
        f"L {w},{h - br[1]}",
        f"C {w},{h - br[1] * (1 - k)} {w - br[0] * (1 - k)},{h} {w - br[0]},{h}",
        f"L {bl[0]},{h}",
        f"C {bl[0] * (1 - k)},{h} 0,{h - bl[1] * (1 - k)} 0,{h - bl[1]}",
        f"L 0,{tl[1]}",
        f"C 0,{tl[1] * (1 - k)} {tl[0] * (1 - k)},0 {tl[0]},0",
        "Z",
    ])


# ---- Per-emotion eye/mouth builders, mirroring SlimeAvatar.swift's barEye/
# ---- crescentEye/ringEye/barFace/pinchedBarFace helpers exactly.

def bar_eye(origin, size, deg, anchor=CENTER):
    return positioned_group(bar_shape(size[0], size[1], 2, NAVY), origin, size, anchor, deg)


def crescent_eye(origin, size, deg, opens_downward):
    inner = crescent_shape(size[0], size[1], opens_downward, NAVY, 2.5)
    return positioned_group(inner, origin, size, CENTER, deg)


def ring_eye(origin, size):
    return positioned_group(ring_shape(size[0], size[1], NAVY, 2.5), origin, size, CENTER, 0)


def bar_face(left_deg, right_deg):
    return (
        bar_eye(LEFT_EYE_TOP, (15, 3), left_deg),
        bar_eye(RIGHT_EYE_TOP, (15, 3), right_deg),
    )


def pinched_bar_face(width, deg):
    return (
        bar_eye(LEFT_EYE_TOP, (width, 3), deg, anchor=(1, 0.5)),
        bar_eye(RIGHT_EYE_TOP, (width, 3), -deg, anchor=(0, 0.5)),
    )


# ---- The 8 emotions (SlimeAvatar.swift faceSpec(), Constants.swift blush/bubble maps) ----

def build_emotions():
    emotions = {}

    emotions["neutral"] = {
        "eyes": bar_face(-6, 6),
        "mouth": None,
        "blush": "none",
        "bubble": None,
    }

    emotions["happy"] = {
        "eyes": (
            crescent_eye(LEFT_EYE_TOP, (17, 8), -8, opens_downward=False),
            crescent_eye(RIGHT_EYE_TOP, (17, 8), 10, opens_downward=False),
        ),
        "mouth": None,
        "blush": "hatch",
        "bubble": "♪",  # ♪
    }

    emotions["curious"] = {
        "eyes": (
            crescent_eye((LEFT_EYE_TOP[0], LEFT_EYE_TOP[1] - 2), (15, 8), -12, opens_downward=False),
            bar_eye(RIGHT_EYE_TOP, (15, 3), 4),
        ),
        "mouth": None,
        "blush": "none",
        "bubble": "?",
    }

    emotions["surprised"] = {
        "eyes": (
            ring_eye(LEFT_EYE_TOP, (10, 10)),
            ring_eye(RIGHT_EYE_TOP, (10, 10)),
        ),
        "mouth": positioned_group(dot_shape(7, 7, NAVY), MOUTH_TOP, (7, 7)),
        "blush": "none",
        "bubble": "!",
    }

    sleepy_mouth_size = (5.25, 5.25)
    sleepy_mouth_origin = (MOUTH_TOP[0] + (7 - 5.25) / 2, MOUTH_TOP[1] + (7 - 5.25) / 2)
    emotions["sleepy"] = {
        "eyes": (
            crescent_eye(LEFT_EYE_TOP, (16, 8), 14, opens_downward=False),
            crescent_eye(RIGHT_EYE_TOP, (16, 8), -14, opens_downward=False),
        ),
        "mouth": positioned_group(
            crescent_shape(sleepy_mouth_size[0], sleepy_mouth_size[1], False, NAVY, 2),
            sleepy_mouth_origin, sleepy_mouth_size,
        ),
        "blush": "plain",
        "bubble": "\U0001F4A4",  # 💤
    }

    emotions["thinking"] = {
        "eyes": pinched_bar_face(15, 16),
        "mouth": None,
        "blush": "plain",
        "bubble": "⋯",  # ⋯
    }

    emotions["annoyed"] = {
        "eyes": pinched_bar_face(18, 24),
        "mouth": None,
        "blush": "none",
        "bubble": "\U0001F4A2",  # 💢
    }

    emotions["blush"] = {
        "eyes": (
            crescent_eye((LEFT_EYE_TOP[0], LEFT_EYE_TOP[1] - 3), (16, 8), -16, opens_downward=True),
            crescent_eye((RIGHT_EYE_TOP[0], RIGHT_EYE_TOP[1] - 3), (16, 8), 16, opens_downward=True),
        ),
        "mouth": None,
        "blush": "hatch",
        "bubble": "♡",  # ♡
    }

    return emotions


BLUSH_OPACITY = {"none": 0, "plain": 0.55, "hatch": 0.85}

# Gloss highlights (constant across every emotion, SlimeAvatar.swift 44-64)
HIGHLIGHT = positioned_group(
    dot_shape(BODY_W * 0.36, BODY_H * 0.24, "rgba(255,255,255,0.9)"),
    (BODY_W * 0.14, BODY_H * 0.10), (BODY_W * 0.36, BODY_H * 0.24), CENTER, -20,
)
HIGHLIGHT2 = positioned_group(
    dot_shape(BODY_W * 0.09, BODY_H * 0.09, "rgba(255,255,255,0.75)"),
    (BODY_W * 0.10, BODY_H * 0.32), (BODY_W * 0.09, BODY_H * 0.09), CENTER, 0,
)

# Blush dots (anchorPoint = .zero, so box_origin IS the position -- SlimeAvatar.swift 71-82)
BLUSH_SIZE = (12, 7)
BLUSH_LEFT_ORIGIN = (BODY_W * 0.11, BODY_H * 0.52)
BLUSH_RIGHT_ORIGIN = (BODY_W * 0.75, BODY_H * 0.52)

# Bubble box: bounds 24x20, anchorPoint .zero, position (bodyCenterX - 9, -16)
# (AvatarView.swift render(): bubble.position = origin + (w/2 - 9, -16))
BUBBLE_BOX_ORIGIN = (BODY_W / 2 - 9, -16)
BUBBLE_BOX_SIZE = (24, 20)
BUBBLE_CENTER = (
    BUBBLE_BOX_ORIGIN[0] + BUBBLE_BOX_SIZE[0] / 2,
    BUBBLE_BOX_ORIGIN[1] + BUBBLE_BOX_SIZE[1] / 2,
)


def render_svg(name, spec):
    left_eye_svg, right_eye_svg = spec["eyes"]
    mouth_svg = spec["mouth"] or ""
    blush_opacity = BLUSH_OPACITY[spec["blush"]]
    bubble_glyph = spec["bubble"]

    blush_svg = ""
    if blush_opacity > 0:
        blush_svg = (
            f'<g opacity="{blush_opacity}">'
            f'{positioned_group(dot_shape(*BLUSH_SIZE, BLUSH_PINK), BLUSH_LEFT_ORIGIN, BLUSH_SIZE, (0, 0))}'
            f'{positioned_group(dot_shape(*BLUSH_SIZE, BLUSH_PINK), BLUSH_RIGHT_ORIGIN, BLUSH_SIZE, (0, 0))}'
            f'</g>'
        )

    bubble_svg = ""
    if bubble_glyph:
        bubble_svg = (
            f'<text x="{BUBBLE_CENTER[0]}" y="{BUBBLE_CENTER[1]}" text-anchor="middle" '
            f'dominant-baseline="central" font-size="15" '
            f'font-family="-apple-system, Helvetica, Arial, sans-serif" fill="#000000">'
            f'{bubble_glyph}</text>'
        )

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="-12 -32 102 122" width="408" height="488">
  <title>Jiggy - {name}</title>
  <defs>
    <filter id="bodyShadow" x="-60%" y="-60%" width="220%" height="220%">
      <feDropShadow dx="0" dy="10" stdDeviation="4" flood-color="{SHADOW_RGB}" flood-opacity="{SHADOW_OPACITY}"/>
    </filter>
  </defs>
  <g filter="url(#bodyShadow)">
    <path d="{dome_path()}" fill="{BODY_FILL}"/>
  </g>
  {HIGHLIGHT}
  {HIGHLIGHT2}
  {left_eye_svg}
  {right_eye_svg}
  {mouth_svg}
  {blush_svg}
  {bubble_svg}
</svg>
'''
    path = os.path.join(OUT_DIR, f"{name}.svg")
    with open(path, "w", encoding="utf-8") as f:
        f.write(svg)
    return path


def main():
    emotions = build_emotions()
    written = []
    for name, spec in emotions.items():
        written.append(render_svg(name, spec))
    for path in written:
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
