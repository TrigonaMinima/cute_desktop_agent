# Phase 0 build: decision log

Running log of every decision and assumption made while implementing
`docs/emergent_behavior_design.md` Phase 0 autonomously (2026-07-10 session).
Each entry: what was decided, why, and what would make us revisit it.
Newest entries are appended at the bottom.

---

## D1. Session ground rules

The user granted blanket commit rights for this build ("all commit rights are
granted") and asked for sane assumptions instead of questions. That overrides,
for this session only, the standing "ask before every commit" and "get plan
approval before code" conventions. Work happens on a worktree-backed feature
branch `feat/emergent-behavior-phase0` off `main` @ `1a0361d`, merged back at
the end per the usual workflow.

## D2. Scope: Phase 0 plus the two already-decided v0 items

Built now: the doc's Phase 0 list (fixed-timestep physics body, steering, gaze
and attention spine, drives with stability, reflex arc + short-term
habituation, doze/sleep power policy) plus the temperament preset vector with
the Calm default and the menu-bar preset switcher, because temperament
baselines are an input to the drives and the doc marks both as decided for v0.

Not built now: everything Phase 1+ (telemetry/replay harness, persistence
store, proxy metrics, all learners). The persistence section only requires
that storage/consent *decisions* land now, which they have (in the doc). The
temperament preset choice is stored in `UserDefaults` as an app setting; it is
not the learned store and does not preempt the Phase 1 schema.

**Revisit if:** the user wants Phase 1 instrumentation in this pass.

## D3. New brain lives beside the classic state machine, not inside it

`StateMachine` is documented as a mechanical blob.js parity port with
byte-identical seeded behavior and a large test suite. Rewriting it in place
would destroy that contract. Instead the new system is a separate `AgentCore`
composition root (`Brain`) with its own subsystem files, and the app shell
picks the driver via a new `"brain"` key in `native/config.json`:
`"emergent"` (new default) or `"classic"` (the parity port, kept as rollback
and comparison baseline). Nothing in the classic path is deleted.

**Revisit if:** carrying both paths starts costing real maintenance; then
delete classic in its own commit after the emergent brain has soaked.

## D4. State model: a new `mind` region on `AgentState`

The doc's cognition state (drives, situation mode, gaze/attention, habituation
counters, power tier) is agent-internal belief, not perceived world and not
outwardly-visible body condition. It gets its own region: `AgentState.mind`,
written only by the brain (same single-writer discipline as `body`/`memory`).
`world`/`body`/`memory` keep their existing shapes so the classic machine
still compiles and its tests still pass untouched. Every new attribute
surfaces in `StatusSummary` (project rule), which both menus pick up
automatically.

`AgentState` is not persisted anywhere today, so the Codable shape change only
requires updating test fixtures, not a migration.

## D5. No new reaction faces in this build

CLAUDE.md requires any new/changed reaction to be generated as an asset and
user-confirmed before being wired in. Running autonomously, that confirmation
is impossible, so Phase 0 maps every new behavior onto the existing eight
emotions: inspect → curious, doze/sleep → sleepy, startle/flinch → surprised,
wake set piece → happy (existing bounce), drive-flavored idling → existing
quirk set. Genuinely new faces the design wants eventually (yawn, stretch,
wary watch) are listed at the end of this log as deferred follow-ups.

## D6. Frozen mode taxonomy (the Phase 1 contract, named now)

`SituationMode` cases, frozen exactly as the doc names them: `focusTyping`,
`mediaWatching`, `idleAway`, `casualBrowsing`. String-backed for JSON
legibility. Detection is rule-based thresholds on cheap signals only.

Known approximation: macOS exposes no public "audio/video is playing" flag
without invasive permissions, so v0 `mediaWatching` is inferred as: frontmost
window effectively fullscreen on its screen AND the user neither typing nor
scrolling, with cursor mostly still. Logged as an approximation the Phase 3
classifier (or a better cheap signal) can replace; the *label* is the frozen
part, not the detector.

## D7. Clock rates

- Physics: fixed 120 Hz step via accumulator, interpolation handled by
  stepping to the display frame boundary (dt clamp at 0.1 s already exists in
  `FrameClock`).
- Reflexes + gaze pursuit: every display frame (a late flinch is a dead
  flinch).
- Cognition (situation, drives, arbitration): 8 Hz, inside the doc's 5-10 Hz
  band.

All rates are constants in one place; nothing reads the display rate directly.

## D8. Circadian input

The drives' circadian baseline bias needs wall-clock hour, which the injected
ms-since-launch `Clock` deliberately doesn't provide. A separate injected
`hourOfDay: () -> Double` provider (production: `Calendar.current` local time;
tests: fixed values) keeps drive dynamics deterministic under test. The curve
is a smooth cosine dip centered ~03:00 (sleepy) and peak ~15:00, scaled per
drive by the temperament vector.

## D9. RNG

All new stochastic pieces (wander noise, arbitration noise/softmax draw, idle
saccade timing) draw from the same injected `RandomProvider` seam the classic
machine uses. The emergent brain gets its own instance so enabling it cannot
perturb classic-path seeded tests.

## D10. Temperament presets

One parameter vector (`Temperament`), presets as static instances: `calm`
(default), `gremlin`, `aloofCat`, `needyPet`, per the doc's archetype
descriptions. Switching sets the base vector only; drives ease toward the new
baselines via their own leaky dynamics (no snap), matching the doc. Preset
choice persists in `UserDefaults` (key `temperamentPreset`).

## D11. Sleep tier mechanics

Sleep = FrameClock stopped + perception monitors idle; wake is event-driven:
NSWorkspace/NSDistributedNotificationCenter notifications (screen lock/unlock,
display sleep/wake, system sleep/wake) plus the already-installed global
keydown/scroll monitors and a temporary global mouse-move monitor installed
only while sleeping. Doze = loops keep running with cognition throttled and
drive baselines biased down; it is a brain-internal tier, not a runtime stop.
"User away" threshold for sleep: 5 minutes of no input events (doze after
90 s), constants in one place.

Occlusion-based sleep (fullscreen app covering Jiggy on every display) is
deferred: NSWindow.occlusionState on an overlay panel that floats *above*
everything reports visible even under a fullscreen Space, so a correct signal
needs Space-change tracking; logged as follow-up rather than shipping a wrong
heuristic.

## D12. What "movement" means now

The emergent path replaces mode-lerp movement with steering forces into the
spring-damper body: arbiter picks a behavior (idle / wander / rest / inspect /
flee-yield), behavior emits steering targets, physics integrates, and
squash/lean fall out of real acceleration instead of fixed `movingScale`
constants. The classic `computeBodyMotion` remains for the classic path; the
emergent path derives an equivalent `BodyMotion` from physics state so the
`Avatar`/`AvatarView` render seam is unchanged.

---

## Deferred follow-ups discovered during the build

- Authored yawn/stretch/wary-watch set-piece faces (need user-confirmed
  reaction assets first, per CLAUDE.md).
- Occlusion/Space-change detection for the sleep tier (D11).
- A real is-media-playing cheap signal to replace the D6 fullscreen proxy.
- Phase 1: telemetry log, deterministic record/replay, persistence store
  scaffolding.
