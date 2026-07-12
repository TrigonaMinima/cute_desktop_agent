# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small desktop overlay agent ("Jiggy") that roams the macOS screen — an animated blob
that floats above everything, wanders/rests/peeks on its own, reacts to cursor proximity
and hover, and can be dragged. Currently mid-rewrite: `electron-poc/` is the original,
working Electron proof-of-concept (kept only as a RAM baseline for comparison);
`native/` is the active Swift/AppKit port and is where new work happens unless told
otherwise.

## Commands

Run everything from the repo root via the root `Makefile`:

```
make native-test     # swift test with Swift Testing flags wired in — ALWAYS use this, not bare `swift test`
make native-build     # swift build -c release --package-path native, then native/build-app.sh
make native-run       # native-build, then open the assembled .app
make native-clean     # rm -rf native/.build native/build
make electron-run     # launch the Electron POC for side-by-side comparison
make electron-install # npm install in electron-poc/
make reactions        # (re)generate reactions/*.svg + *.png — see "Reactions / avatar assets" below
make clean            # native-clean + electron-clean
```

To run a single Swift test, pass `--filter` through to the underlying `swift test`
invocation, e.g. `swift test --package-path native --filter StateMachineTransitionTests`
— but for a full run always go through `make native-test`, since it supplies the
`-F`/`-rpath` flags Swift Testing needs on a Command-Line-Tools-only toolchain (see
"Toolchain quirks" below).

## Architecture (native/)

Two-target Swift package plus a throwaway spike, defined in `native/Package.swift`:

- **`Sources/AgentCore`** — Foundation-only pure logic: math (`Math/Geometry.swift`,
  `Math/TargetPicking.swift`), the two brains (below), and the `AgentState` model
  (`State/AgentState.swift`). No AppKit import, fully unit-testable headless via
  `swift test`. Two brains conform to the `AgentBrain` seam
  (`Behavior/AgentBrain.swift`). `config.json`'s `"brain"` key picks the boot
  default; the menu-bar/avatar-context "Brain" submenu (first item — see
  `Shell/BrainMenuController.swift`) switches live afterward and persists the
  choice in UserDefaults across relaunches (D21):
  - `Behavior/StateMachine.swift` — the **classic** brain, a **mechanical port** of
    `electron-poc/renderer/blob.js` (lines ~90-431). When its behavior looks odd,
    check the doc comments explaining the JS source parity rather than "fixing" it
    to look more idiomatic. Boot default override: `"brain": "classic"`.
  - `Mind/` — the **emergent** brain (the default): `EmergentBrain.swift` composes
    layered systems — drives (`Drives.swift`, `DriveDynamics.swift`,
    `Temperament.swift`), situation model (`SituationModel.swift`), fixed-timestep
    physics + steering (`Physics/PhysicsBody.swift`, `Physics/Steering.swift`),
    gaze/attention (`GazeSystem.swift`, `Habituation.swift`), reflex arc
    (`ReflexArc.swift`), behavior arbitration (`BehaviorScoring.swift`), and the
    doze/sleep power ladder (`PowerPolicy.swift`) — all tuned via
    `MindConstants.swift`, with the belief state in `MindState.swift`
    (`state.mind`, nil on the classic path). Design rationale lives in
    `docs/emergent_behavior_design.md`; every build decision is logged in
    `docs/phase0_decision_log.md` (D1-D19).
- **`Sources/AgentApp`** — the AppKit shell: overlay window (`Shell/OverlayPanel.swift`),
  menu-bar status item (`Shell/StatusItemController.swift`), the shared live-refreshing
  status menu (`Shell/LiveMenuController.swift`, `Shell/StatusMenuBuilder.swift`) both the
  status item and the avatar's right-click menu build on, the temperament preset submenu
  (`Shell/TemperamentMenuController.swift`, persisted under the `temperamentPreset`
  UserDefaults key), the sleep-tier wake monitors (`Shell/PowerController.swift`), the
  app delegate (`Shell/AppDelegate.swift`) that wires everything together,
  cursor/frontmost-app polling (`Perception/Perception.swift`), and Core Animation
  avatar rendering (`Render/AvatarView.swift`, `Render/Avatar.swift`,
  `Render/Avatars/SlimeAvatar.swift`). Imports `AgentCore`.
- **`Sources/Spike`** — throwaway Phase 0 gate code proving the overlay window
  behaviors (float over fullscreen, click-through, no activation stealing,
  `CADisplayLink`) work without Xcode.app. Not shipped; rerun with
  `swift run --package-path native Spike` if ever needed again.
- **`Tests/AgentCoreTests`** — unit tests for `AgentCore` only; the AppKit shell is not
  unit-tested (it's driven manually via `make native-run`).

### Data flow / state ownership

`AgentState` (`world` = perceived environment, `body` = the agent's own
position/mode/emotion, `memory` = timers/cooldowns, `mind` = the emergent brain's
belief state, nil on the classic path) is the single source of truth, designed to
double as a future LLM/agent context object (see its doc comment). Strict
single-writer discipline:

- **The active brain** (`StateMachine` or `EmergentBrain`, held by the shell as one
  `AgentBrain` existential) is the *sole* writer of `state.body` and `state.memory` —
  and, on the emergent path, `state.mind` — driven once per frame by `tick(state:dt:)`.
  RNG and time are injected (`RandomProvider`, `Clock`; the emergent brain also takes an
  `hourOfDay` reader for its circadian baselines) so behavior is deterministic under
  test — production wires `SystemRandom`/`SystemClock`, tests use fakes (see
  `Tests/AgentCoreTests/TestFixtures.swift`).
- **`Perception`** (in `AgentApp`) writes `state.world` once per frame (cursor position,
  frontmost app), polled rather than event-driven.
- **`AvatarView`** and everything else only *reads* a frozen `AgentState` copy per frame
  to render — never mutates it.
- Drag is the one interaction that bypasses the normal tick flow: `AppDelegate` calls
  `brain.beginDrag`/`updateDrag`/`endDrag` directly from mouse callbacks. Temperament
  switching (`EmergentBrain.adoptTemperament`) works the same way, from the menu action.

Frame driving: `FrameClock` (backed by `CADisplayLink`) calls into `AppDelegate`'s
closure once per frame, which does perception poll → `brain.tick` → `avatarView.render`
→ hit-test update → live-menu refresh → sleep check, in that order. When the emergent
brain reports `mind.power == .sleeping` (no user input for 5 minutes), the shell stops
the `FrameClock` entirely and `PowerController`'s event monitors restart it on the first
sign of the user (see decision log D18).

### Live status menus

The menu-bar dropdown and the avatar's right-click menu both read the same
`AgentState.statusSummary(now:)` (→ `StatusSummary`), rendered into `NSMenuItem`s by the
shared `StatusMenuBuilder` (`Shell/StatusMenuBuilder.swift`) and kept refreshing while open
by `LiveMenuController` (`Shell/LiveMenuController.swift`) — one instance per surface.
`NSMenuDelegate.menuNeedsUpdate` only fires once per open, so `refreshIfOpen(now:)` is also
called once per frame from `AppDelegate`'s `FrameClock` closure (a no-op unless that menu
is currently open, throttled to 10Hz) — this works because `FrameClock`'s `CADisplayLink`
runs in `.common` mode, which stays eligible to fire during `NSMenu`'s own event-tracking
loop. Because both surfaces are built from the identical builder/controller pair, a new
`StatusSummary` row shows up — and live-updates — on both without extra wiring.

### Extensibility seams

- **Avatars**: `Avatar` protocol (`Render/Avatar.swift`) is the only interface `AvatarView`
  depends on. Adding a new avatar = new conformer under `Render/Avatars/` + a case in
  `AppConfig.makeAvatar()` (`Config/AppConfig.swift`) — nothing else in the render layer
  changes. Only `SlimeAvatar` exists today.
- **Brains**: `AgentBrain` protocol (`Behavior/AgentBrain.swift`) is the only interface
  the shell drives — swapping brains is pure configuration, no per-brain branches in the
  frame driver or drag wiring. `config.json`'s `"brain"` key (`emergent` default, `classic`
  rollback) picks the boot default; `Shell/BrainMenuController.swift` swaps the live brain
  from the menu afterward, persisted in UserDefaults (D21).
- **Branding**: display name, bundle identifier, status-item glyph, avatar choice, and the
  brain boot default live in `native/config.json`, never as literals in code — `AppConfig`
  decodes it at runtime from the app bundle's `Resources/`, and `build-app.sh` reads the
  same file at bundle-assembly time for `Info.plist` substitution.

## Toolchain quirks (native/)

- **Swift Testing, not XCTest.** This is a Command-Line-Tools-only toolchain (no
  Xcode.app dependency for building), so `XCTest.swiftmodule` isn't available; tests use
  Swift Testing (`import Testing`, `@Test`, `#expect`) instead. Its framework lives under
  an Xcode-oriented CLT path that `swift test` doesn't search by default, so bare
  `swift test --package-path native` will fail to link/run — always use `make native-test`,
  which supplies the required `-F` and `-rpath` flags (see `native/README.md` "Toolchain
  notes" for the full explanation).
- **`Package.swift` is pinned at `// swift-tools-version:5.9`, not 6.0.** Bumping it turns
  on Swift 6's strict-concurrency-by-default checking, which breaks the `Spike` target
  (`Sendable` errors on `CADisplayLink`/`AppDelegate`). Do not bump this without addressing
  those errors first.
- `make native-run` always launches the assembled `.app` bundle, never a raw binary —
  `config.json` and other resources are only present inside the bundle.


## Reactions / avatar assets

`reactions/` holds standalone SVG/PNG exports of every face Jiggy can show (see
`reactions/README.md`), mechanically generated from the render code by
`reactions/generate_reactions.py` (`make reactions`).

Any new reaction — or any update to an existing reaction — must be **generated and
saved as an asset in `reactions/` first**, then presented to the user for
**confirmation before moving on to any subsequent step**. Do not wire a new or
changed reaction into further work (avatar code, docs, anything else) until the
user has reviewed the generated asset.

## Instructions

- After every merge, kill the previous instance of jiggy and launch a new instance with the new code.
- If a new state attribute is added then it should also be added to `StatusSummary` — both
  the menu bar dropdown and the avatar right-click context menu pick it up automatically
  (see "Live status menus" above), with no per-surface wiring needed.

