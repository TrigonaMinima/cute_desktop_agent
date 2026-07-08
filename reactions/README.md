# Jiggy reaction sheet

Standalone SVG/PNG exports of every distinct face Jiggy can show. Generated from
`generate_reactions.py`, a mechanical port of the actual Swift renderer
(`native/Sources/AgentApp/Render/Avatars/SlimeAvatar.swift`'s `faceSpec()` +
`native/Sources/AgentApp/Render/PathShapes.swift`) — not a re-imagining, so these
match what the running app draws.

There are exactly 8 reactions because the avatar's face is driven entirely by the
`Emotion` enum (`native/Sources/AgentCore/State/Enums.swift`); `Mode` never draws
directly, it only maps to a base emotion (see `Constants.baseEmotionByMode`).
Transient overlays (blink, drag/moving squash, the happy bounce) are per-frame
animation on top of these faces, not separate reactions, and are not depicted here.

| File | Emotion | Bubble | Triggered by |
|---|---|---|---|
| `neutral.svg`/`.png` | neutral | — | Base emotion of `idle` and `wander` modes; the default. |
| `happy.svg`/`.png` | happy | ♪ | `happy` mode — the 500ms bounce right after a drag-and-drop. |
| `curious.svg`/`.png` | curious | ? | Base emotion of `peek` mode (peeking from a screen edge). |
| `surprised.svg`/`.png` | surprised | ! | While being dragged; a cursor-proximity startle; or base emotion of `flee` mode (yielding the user's caret/attention zone). |
| `sleepy.svg`/`.png` | sleepy | 💤 | Base emotion of `rest` mode (resting in a screen corner). |
| `thinking.svg`/`.png` | thinking | ⋯ | Random idle-only quirk. |
| `annoyed.svg`/`.png` | annoyed | 💢 | Random idle-only quirk. |
| `blush.svg`/`.png` | blush | ♡ | Random idle-only quirk. |

## Regenerating

```
make reactions
```

runs `generate_reactions.py` (stdlib-only Python) to (re)write the 8 SVGs, then
rasterizes each to PNG via macOS's built-in `qlmanage` QuickLook thumbnailer (no
third-party SVG renderer is installed on this machine — rsvg-convert, cairosvg,
and Inkscape were all checked and are absent).

**Per `CLAUDE.md`: any new or updated reaction must be generated here and confirmed
by the user before being wired into anything else** — do not skip the review step.
