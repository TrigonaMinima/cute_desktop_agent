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

## D13. Gaze spine specifics

The doc's candidate list maps onto v0 cheap signals as: cursor (position +
derived velocity), onset (frontmost app/window identity change; the first
frame is baseline, so launching next to an open window is not an event), user
proxy (caret → focused-window center → screen front-and-center, in that
order, so "look back at you" always exists), motion (active scrolling in the
frontmost window — the only cheap on-screen-motion signal we have), own
locomotion target, and neutral rest (body center, 60 px down).

Salience: non-neutral candidates scale by arousal (floor 0.25 — a sleepy
Jiggy's eyes flatten home to neutral, and even a salience-1.0 candidate can't
clear the neutral-plus-margin bar) and by per-kind habituation (one shared
`Habituation` store, keyed by kind; the reflex arc will key the same store by
stimulus). Curiosity multiplies onset, sociability lerps the user candidate —
this is how calm "glances rather than stares" (its baselines are low) without
a dedicated novelty-weight temperament field.

Hysteresis: switch margin 0.15 + minimum dwell 350 ms, in one testable
`shouldSwitch` rule. `snap(to:)` is the reflex override: instant jump,
attention pinned to 1, bypassing both.

Pursuit: saccade tau 40 ms for the first 120 ms after a switch, then pursuit
tau lerped 0.35 s → 0.08 s by attention. An earlier draft *also* blended the
pursued point toward neutral by attention — that double-modeled looseness
(the slow tau already is the loose tracking, and drifting home happens via
the arbiter when flattened salience lets neutral win) and broke pursuit lock;
removed.

One test expectation was corrected against the doc rather than the code: a
stale onset releases to the **user** candidate when a focused window is still
present ("drift to a window that just opened, then settle back on the user"),
not to neutral.

Idle micro-saccades and blink during neutral gaze are Brain-tick touches
(they need the injected RNG), deferred to the Brain integration task, not
GazeSystem state.

## D14. Reflex arc shape

One detected stimulus in v0: the cursor darting at the body — close (≤250 px)
and *closing* fast (velocity projected onto the cursor→body line, so a cursor
racing away never triggers). Effective intensity = raw closing speed ×
`temperament.reflexGain` × (1 − habituation), thresholded into the doc's
startle (≥0.5) / flinch (≥0.25) / wary-watch (≥0.12) / nothing ladder — the
interrupt and the anti-repetition progression are literally one multiply.

Reflex habituation is event-based (each dart deposits 3 s of equivalent
exposure into the shared store under key "cursorDart"), unlike gaze's
continuous per-tick exposure — a poke is an event, not a duration. Recovery
is the store's normal decay, driven once per tick by the Brain, so "leave it
alone and sensitivity recovers" needs no extra mechanism. A tuned-out
stimulus still deepens habituation.

The arc detects and times; it does not apply consequences. The Brain maps a
fired event to gaze `snap`, the `DriveImpulse.startle` arousal spike, the
surprised face, and — per the doc's "resume or re-arbitrate" rule — a forced
re-score when the event ends (default re-arbitrate, never blind resume).
Wary watch is eyes-only: `steeringForce` returns nil for it, so the body
never twitches on the third poke, only the gaze sharpens.

Window-onset-near-body as a second reflex stimulus is deferred — the dart
covers the doc's canonical case; the arc's detect/tier/duration split makes
adding stimuli additive.

## D15. Arbiter shape (behavior scoring + softmax pick)

Behavior menu for v0: idle / rest / wander / inspect / yield. Reflexes are
deliberately not in this list — they preempt whoever holds the body and are
never scored, which is how "arbiter hysteresis never gates reflexes" is made
structural rather than a rule someone must remember.

Scores are live drive levels, shaped by two multipliers:

- **Spontaneity** = `max(livelinessFloor(mode), deference(mode) × arousal)`.
  Liveliness floors are *minimums* that prevent collapse-to-lifeless (the doc's
  collapse trap), never ceilings; deference (media 0.15, focus-typing 0.4,
  otherwise 1.0) is what suppresses spontaneous movement in considerate modes.
  Wander and inspect are spontaneous (scaled); rest and idle are not — being
  tired or simply present defers to nothing.
- **Inspect engagement**: inspect scores `curiosity × attention` only when gaze
  is on an external object (cursor/onset/user/motion) — neutral rest and the
  agent's own locomotion target don't count as something to inspect.

Yield only becomes a candidate when the body overlaps the user's working zone,
and then its constant score (3.0) dominates everything: sitting on the caret is
never acceptable, and making it a candidate-with-huge-score rather than a hard
override keeps one arbitration path instead of two.

Pick = flat incumbent bonus (0.15, the hysteresis) + temperature softmax
(T = 0.15) over scores via the existing `weightedChoice`. Low temperature means
clear winners nearly always win; near-ties stay genuinely stochastic — variety
without twitchiness. Committed behaviors also hold for a minimum 2500 ms unless
a forced re-arbitration (reflex end, arrival, yield trigger) cuts in.

Habituation ownership was refactored while wiring this: `GazeSystem` no longer
owns a store; the Brain owns one mind-wide `Habituation` (gaze and reflex both
key into it) and drives recovery exactly once per tick, so the reflex keys are
never double-decayed.

---

## D16. Brain tick order, motor policy, and the emotion ladder

**Decision**: `EmergentBrain` is a peer of the classic `StateMachine` with the
same seams (`makeInitialState` / `tick` / `beginDrag` / `updateDrag` / `endDrag`),
so the shell swap in the next task is a one-line substitution. Per display frame,
in order: attention-zone belief → drag short-circuit → reflex arc → cognition
(8 Hz gated) → steering + fixed-step physics + hard screen clamp → gaze + the
once-per-tick habituation recovery → blink → body write-back.

Load-bearing choices inside that order:

- **Reflex consequences apply on the frame the event fires** (gaze snap to the
  source, startle arousal impulse, `rearbitrateAt = event.endsAt`) — they never
  wait for the next cognition slice. Arbitration is skipped while a startle or
  flinch holds the body; wary watch only takes the eyes, so scoring continues.
- **Forced re-arbitration** (bypasses the 2500 ms commitment): a due
  `rearbitrateAt` (reflex just ended, drag just dropped, target just reached),
  zone overlap while not yielding, or yield with no overlap left. The last one
  means yield releases the moment the body clears the caret zone — escape just
  far enough, then re-score, rather than completing a stale trip.
- **Motor policy per behavior**: idle/rest apply no force (the edge cushion
  still does); wander is the heading-noise force with a fresh random heading
  drawn per commit; inspect arrives at a stand-off point 140 px short of the
  gaze target (leaning in to look, not sitting on the thing); yield arrives at
  the existing `escapePoint` at 220 px/s vs the 120 px/s × tempo cruise. Reflex
  flight (340 px/s) preempts all of them. Arrival within 12 px clears the
  target and forces a re-score.
- **Rest score slack**: rest = `max(0, (1 − energy) − 0.3)`. Without the slack,
  calm's 0.5 baseline energy made rest (0.5) permanently outbid idle (0.25) — a
  pet that naps by default. Only a genuine energy deficit now wins.
- **Emotion ladder** (existing faces only, highest priority first): dragging →
  blush; active startle/flinch → surprised, wary watch → curious; yield →
  annoyed; inspect → curious; rest-and-settled → sleepy; else neutral.
- **Display mapping** for the classic status surfaces: inspect renders as
  `wander` (purposeful motion), yield as `flee`; the new Mind section on both
  menus carries the real behavior plus situation, power tier, all six drives,
  gaze, active reflex, and the habituation peak.
- **Blink carries over** from the classic path unchanged; quirks do not —
  drive-flavored idling is meant to replace them (deferral below).

---

## D17. Shell wiring: the AgentBrain seam, config switch, and gaze rendering

**Decision**: a five-method `AgentBrain` protocol in AgentCore
(`makeInitialState` / `tick` / `beginDrag` / `updateDrag` / `endDrag`) is the
only thing the AppKit shell knows about. `StateMachine` conforms as-is;
`EmergentBrain` conforms via a protocol overload that defaults temperament to
`.calm` (the preset submenu in a later task overrides per-launch). Selection is
a new `"brain"` key in `config.json` — decoded to an enum like `avatar`, so an
unrecognized value is a launch-time decode error. **The key is optional and
defaults to `emergent`**; `"brain": "classic"` is the rollback switch.

Rendering choices that came with the wiring:

- **Gaze is rendered as a whole-eye deflection**, not new pupil layers: the
  existing eye shapes shift up to 3 px toward `GazeSystem.direction(from:)`,
  composed into the same per-frame transform as rotation and blink. Zero when
  no mind is driving, so the classic path renders pixel-identical. Chosen over
  adding pupils because it changes no face geometry and therefore no reaction
  assets — the CLAUDE.md rule about presenting new/changed reactions for
  confirmation isn't triggered. If pupils are ever wanted, that's a
  user-reviewed reaction change first.
- **Squash on the emergent path is the physics spring's state**: 
  `computeBodyMotion` maps `mind.physics.squash` straight to scale, composed
  with the classic idle breathing wobble, and skips the canned moving-scale
  clip (deformation follows real acceleration — the design doc's "expression
  is a side effect of forces"). Dragging keeps the classic pinch scale.
- The emergent brain's `hourOfDay` is wired to the wall clock as a fractional
  hour (14:30 → 14.5) read via `Calendar` each cognition slice.

---

## D18. Power ladder mechanics: doze in the brain, sleep in the shell

**Decision**: the D11 tiers are implemented in two halves, split exactly along
the AgentCore/AppKit boundary.

- **Tier selection is pure and recomputed, not event-driven**: `PowerPolicy`
  maps `SituationModel.secondsSinceActivity(now:)` to a tier (`awake` < 90 s ≤
  `dozing` < 300 s ≤ `sleeping`), re-evaluated on every cognition slice. Waking
  therefore needs no plumbing inside AgentCore — any fresh input resets the
  situation model's activity clock, and the next slice reads `awake`.
- **Doze is brain-internal**: the cognition slice stretches from 125 ms to
  500 ms, and the energy/arousal drive baselines are scaled by 0.6 (a
  `baselineScale` parameter on `DriveDynamics.tick` — targets shift, dynamics
  untouched, so the other four drives and all stability properties are
  unaffected). Reflexes, physics, gaze, and rendering keep running per-frame:
  a dozing Jiggy still flinches.
- **Sleep is a shell decision keyed off brain state**: on the slice that reads
  `.sleeping`, the brain commits `.rest` (the pose it freezes in) and skips
  arbitration; `AppDelegate` sees `mind.power == .sleeping` at the end of the
  frame and stops the `FrameClock` outright — no display link, no perception
  polling, no rendering, ~0% CPU.
- **Wake is event-driven via `PowerController`**: a global `NSEvent` monitor
  (mouse move, left click, key down, scroll) plus workspace notifications
  (machine wake, screens wake, session became active) plus the distributed
  `com.apple.screenIsUnlocked`. Any of them restarts the clock. A **stale wake
  is deliberately harmless**: if no real input reached perception, the next
  cognition slice still reads `.sleeping` and the shell re-sleeps — chosen over
  filtering wake signals for freshness, which would duplicate the situation
  model's job in the shell.
- A display change while dormant rebuilds the panels but does **not** restart
  the clock; wake stays event-driven.

---

## Deferred follow-ups discovered during the build

- Authored yawn/stretch/wary-watch set-piece faces (need user-confirmed
  reaction assets first, per CLAUDE.md).
- Occlusion/Space-change detection for the sleep tier (D11).
- A real is-media-playing cheap signal to replace the D6 fullscreen proxy.
- Phase 1: telemetry log, deterministic record/replay, persistence store
  scaffolding.
- A `pettedOrPlayed` impulse producer (hover-dwell "petting" detection) — the
  drive impulse exists but nothing fires it on the emergent path yet.
- Quirk micro-expressions on the emergent path, if drive-flavored idling turns
  out too flat without them.
- Drag-release fling: `endDrag` currently lands with zero velocity; carrying
  the hand's velocity into the physics body would read more alive.
