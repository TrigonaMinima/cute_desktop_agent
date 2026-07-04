# cute_desktop_agent

A small desktop overlay agent that roams around your macOS screen — currently mid-rewrite
from an Electron POC to a native Swift/AppKit core.

- **`electron-poc/`** — the original Electron proof-of-concept. Working, kept for
  side-by-side comparison and as the RAM baseline to beat.
- **`native/`** — the native Swift/AppKit port. See `native/README.md` for the
  architecture (a `AgentCore` library + `AgentApp` shell) and status.

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
