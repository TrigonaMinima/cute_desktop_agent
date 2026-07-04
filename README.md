# cute_desktop_agent

A small desktop overlay agent that roams around your macOS screen — currently mid-rewrite
from an Electron POC to a native Swift/AppKit core.

- **`electron-poc/`** — the original Electron proof-of-concept. Working, kept for
  side-by-side comparison and as the RAM baseline to beat.
- **`native/`** — the native Swift/AppKit port. See `native/README.md` for the
  architecture (a `AgentCore` library + `AgentApp` shell) and status.

## What Jiggy does

- **Lives on your desktop.** A small animated blob floats on top of everything, even
  full-screen apps, on any virtual desktop.
- **Roams on its own.** Left alone it idles, wanders, rests in a corner, or peeks off the
  edge of the screen and comes back — a mix of moods, not a fixed loop.
- **Reacts to you.** Gets startled if your cursor comes close, notices when you hover over
  it, and only "catches" clicks meant for it — everything underneath stays clickable. You
  can pick it up and drag it around; drop it and it bounces happily.
- **Has moods.** Its face and little speech-bubble icons (`!`, `?`, `💤`, `♪`) show emotions
  like curious, sleepy, surprised, annoyed, or happy, and its body squashes and wobbles
  differently depending on what it's doing.
- **Stays out of the way.** No Dock icon, never steals focus from whatever app you're
  using, lives quietly in the menu bar with a Quit option.
- **Runs light.** The native rewrite uses ~12 MB of memory instead of the original
  Electron prototype's ~226 MB — about 18x lighter, same behavior (see below).

Not yet there: it doesn't see what's inside the windows it floats over, doesn't talk or
use any AI/LLM smarts, and only comes in one look (the slime avatar) — planned for later.

## RAM comparison

Measured with `footprint` (physical footprint, both apps idle at the desktop with no
interaction), same machine:

| Build | Physical footprint |
|---|---|
| `native/build/Jiggy.app` | **12 MB** |
| `electron-poc` (main + renderer + GPU + network helper) | **226 MB** |

~18x lower. The Electron side's GPU helper process alone (138 MB) accounts for over half
of its total — Chromium's compositor overhead for what is a small animated sprite.

Branding (app display name, bundle id, status-item glyph, avatar choice) lives in
`native/config.json`, not in code — see `native/README.md`.

See `.claude/plans` history for design context.

## Quick start

```
make native-test    # run AgentCore unit tests
make native-build    # build + ad-hoc sign the .app
make native-run       # build and launch it
make electron-run     # launch the Electron POC for comparison
```
