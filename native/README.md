# native/ — Swift/AppKit desktop agent

Native rewrite of the desktop overlay agent (see `../electron-poc/` for the original
Electron POC and `../README.md` for the project overview). Built with `swift build`
only — no Xcode.app dependency for the build itself (Xcode may still be installed
separately for Instruments profiling and the Debug View Hierarchy).

Branding lives in `config.json`, not in code:

```json
{ "displayName": "Jiggy", "bundleIdentifier": "com.jiggy.agent",
  "statusItemTitle": "🟢", "avatar": "slime" }
```

Change `displayName`/`bundleIdentifier`/`statusItemTitle` to rebrand; change `avatar` to
pick a different `Avatar` conformer (only `slime` exists today — see
`Sources/AgentApp/Render/Avatars/SlimeAvatar.swift`).

## Layout

- **`Sources/AgentCore/`** — Foundation-only pure logic (math helpers, target picking,
  `AgentState`, the behavior state machine). No AppKit import; fully unit-tested headless
  via `swift test`.
- **`Sources/AgentApp/`** — the AppKit shell: overlay window, status item, display link,
  perception, avatar rendering. Imports `AgentCore`.
- **`Sources/Spike/`** — throwaway Phase 0 gate code (see below). Not shipped.
- **`Tests/AgentCoreTests/`** — unit tests for `AgentCore`.

## Phase 0 gate — status: PASSED

Before any behavior/render/state code was built, `Sources/Spike/main.swift` proved (with
a plain animated colored square, run via `swift run --package-path native Spike`) that a
Command-Line-Tools-only build can produce an overlay window that:

| Check | Result |
|---|---|
| (a) Floats over everything, including native-fullscreen apps, on all Spaces | ✅ confirmed via screenshot against fullscreen iTerm2 |
| (b) Click-through by default, with a per-tick hit-test toggling it off over the square | ✅ confirmed via console logs |
| (c) Does not steal app activation when clicked (frontmost app stays truthful) | ✅ confirmed — `NSPanel(.nonactivatingPanel)` + `canBecomeKey=false` |
| (d) Drives a live per-frame animation via `CADisplayLink` | ✅ confirmed — fired ~120 times/2s on this display; no `CVDisplayLink` fallback needed |

No fallback was needed for any check. This settles the single biggest risk in the native
approach — see `.claude/plans/enter-the-plan-mode-misty-cook.md` for the full plan and
risk writeup. Re-run the spike any time with:

```
swift run --package-path native Spike
```

## Phase 1 gate — status: bundling mechanism verified

`build-app.sh` reads `config.json` and assembles `build/<displayName>.app` (correct
`Info.plist` substitution, ad-hoc `codesign`, binary renamed to `displayName`). Full
behavioral re-verification against the Phase 0 checklist is deferred until `AgentApp`
has a real overlay window (Phase 4/5) — right now `AgentApp/main.swift` is a placeholder
that prints and exits.

## Toolchain notes

**`swift test` needs extra linker/search-path flags for Swift Testing to work.** This
CLT install has no `XCTest.swiftmodule` at all (XCTest is Xcode-distributed), so tests
use **Swift Testing** (`import Testing`, `@Test`, `#expect`) instead — it ships with the
Swift 6.3 toolchain itself. But its `Testing.framework` lives under an Xcode-oriented
path (`CommandLineTools/Library/Developer/Frameworks`) that `swift test` doesn't search
or rpath by default when there's no Xcode.app installed, and `Testing.framework` itself
links a second dylib (`lib_TestingInterop.dylib`) from a sibling path. Without Xcode.app,
`swift test` needs both paths supplied explicitly — one as a `-F` module/link search
path, both as linker `-rpath`s so the built `.xctest` bundle can `dlopen` them at
runtime (env vars like `DYLD_FRAMEWORK_PATH` get stripped before the test-bundle
subprocess launches, so only baked-in rpaths work). `make native-test` wires this up —
see the `TESTING_FRAMEWORK_DIR`/`TESTING_LIB_DIR` flags in the root `Makefile`. Always
use `make native-test`, not a bare `swift test --package-path native`. If Xcode.app is
installed later, these flags likely become unnecessary but are harmless to keep.

Also note: `native/Package.swift` stays pinned at `// swift-tools-version:5.9`, not 6.0
— bumping it turns on Swift 6's strict-concurrency-by-default checking, which broke the
already-verified `Spike` target (`Sendable` errors on `CADisplayLink`/`AppDelegate`).
5.9 was sufficient for Swift Testing once the flags above were added.

## Build & run

```
make native-test    # swift test --package-path native, with Swift Testing flags wired in
make native-build    # swift build -c release + assemble/sign the .app (build-app.sh)
make native-run       # build, then open the .app
```
