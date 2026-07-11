# Jiggy: Emergent Behavior Design

**Status:** North star. Design decisions resolved, ready to build Phase 0.
**Scope:** How Jiggy's movement, reactions, and idle behavior become genuinely emergent and non-repetitive, and how a learning layer bolts onto that later without making the system unshippable.

---

## Core principle

You are not animating a blob. You are simulating a tiny nervous system and letting the animation fall out of it.

Every quality you want (looks alive, non-repetitive, intentional) is a symptom of internal state meeting a perceived world. None of it is authored directly. Once you commit to this, "fixed animation triggered by fixed condition" stops being the unit of work, and the behaviors you never wrote become the ones that sell it.

One boundary governs the whole system, including the future ML:

> **Rules own reflexes, physics, and safety. Models only shape preferences. The model never picks an action and never moves the body. It tilts the landscape that a rule-based arbiter chooses over.**

Get that boundary right and you can add learning without ever making Jiggy undebuggable or unsafe.

---

## The spine is attention, not mood

Before drives, before personality, the strongest aliveness signal is what Jiggy is looking at and how much it cares. Gaze is cheap and it makes the user feel seen. Eyes that track the cursor, drift to a window that just opened, then settle back on the user cross most of the uncanny gap before the body moves an inch.

Model two continuous variables above everything else:

- **Gaze target:** a point on screen, smoothly pursued.
- **Attention level:** how locked-on Jiggy is.

Almost every behavior reduces to "pick what to attend to, and how hard." A creature that attends convincingly reads as alive even while idle.

---

## Gaze: how attention gets allocated

Calling attention the spine and then not saying how the gaze target is chosen leaves the most-read layer unspecified. Choosing between the cursor, a window that just opened, and settling back on the user is itself an arbiter: a small salience contest with its own weighting and its own hysteresis, separate from the behavior arbiter below it. It runs on the fast side of cognition, because a late glance reads as dead.

### Candidates

At any moment a handful of things compete for the eyes:

- The cursor, weighted up when it moves fast or approaches Jiggy.
- An onset: a window that just opened, closed, or flashed. Novelty is the strongest raw pull.
- The user, stood in for by a stable proxy (the focused window, the active caret, or simply front-and-center), so "look back at you" is always a candidate.
- On-screen motion, such as a playing video region.
- Jiggy's own locomotion target, so when it moves with purpose the eyes lead the body.
- A neutral resting gaze (ahead, slightly down) that wins when nothing else does.

### Scoring salience

Each candidate scores as a weighted sum:

- **Intrinsic salience.** Onset beats motion beats static. A window appearing is high; a static icon is low.
- **Proximity and relevance.** Things near Jiggy or near the cursor matter more.
- **Habituation.** A candidate loses salience the longer it is attended, using the same habituation counters as the reflex arc, so the eyes do not lock forever on the thing that just opened.
- **Drive and temperament modulation.** Curiosity lifts novelty, sociability lifts the user candidate, low arousal or sleepiness flattens everything. Calm weights novelty low and the user and neutral candidates high, so it glances rather than stares.

### Committing

Salience picks a winner, but the eyes only move if the winner clears the current target by a margin, not by a hair. That margin is gaze's own hysteresis, and a short minimum dwell holds a new target briefly before another switch is allowed, so attention never strobes.

Motion has two modes: a fast saccade to acquire a target, then smooth pursuit if it moves. That pair, snap-to then track, is itself a strong aliveness cue and is most of what sells the eyes. The attention level scales the pursuit: high attention tracks tightly and stays glued, low attention tracks loosely and drifts back toward neutral.

A reflex overrides all of this. A startle snaps gaze to its source instantly, ignoring the margin and the dwell, exactly as it preempts the body. Gaze and motor obey the same interrupt contract.

Two cheap touches keep the eyes from ever being dead: small idle saccades and occasional blinks during neutral gaze, and the rule that gaze leads locomotion, orienting a beat before the body commits. Gaze is the spine because it does most of the aliveness work at almost no cost. The body only moves when the arbiter decides the gaze target is worth the trip.

---

## Architecture: two pathways, one body

The system is not a single scoring loop. It is a fast reflex arc and a slower deliberative arbiter, both writing to the same physics body, with a constraint layer wrapping the output. Separating the two is what lets a startle interrupt a committed wander without either one feeling wrong.

### Clock rates

Three rates, deliberately decoupled:

- **Physics, fixed timestep.** The spring-damper body integrates at a fixed step (interpolated to the display), independent of render rate and of cognition. A variable timestep makes the same drop wobble differently every frame, which reads as jank, not life.
- **Reflexes, fast tick.** Evaluated often enough that a flinch is never late. A startle that waits is a dead startle.
- **Cognition, slow tick.** Perception, situation, drives, and arbitration run at roughly 5 to 10 Hz. Deliberation does not need frame rate; the body does.

### The layers

**1. Perception (rule-based, cheap to compute).** Sense the world and emit a context feature vector. No intelligence here. Window and screen state, focused app plus fullscreen flag, whether video or audio is playing, cursor position and velocity, typing cadence, idle time, time of day. Feeds both pathways. (Cheap to compute is not the same as cheap to gather; see the perception budget below.)

**2. Reflex arc (rule-based, fast, preemptive).** Startle, flinch, recoil. Evaluated on the fast tick, straight from perception to motor, bypassing deliberation. This is the layer that can seize the body mid-motion. Its gain is set by habituation, so the same poke produces a weaker reflex each time.

**3. Situation model.** Collapse the feature vector into a coarse mode: focus/typing, media/watching, idle/away, casual/browsing. Rule-based thresholds to start, a small learned classifier later. This mode conditions everything below it and is the key the drag-away learning uses. Its label set is a frozen contract (see build path).

**4. Drives (rule-based dynamics).** energy, curiosity, sociability, comfort, arousal, boredom. Each drifts on its own and gets pushed by events, with a circadian bias on the baselines. This continuous state is what guarantees no two moments are identical. Stability requirements are their own section below, because six coupled integrators misbehave if you let them.

**5. Habituation and memory.** Two speeds. Short: per-stimulus habituation counters that suppress repeated reactions and recover with rest, which is also the gain control on the reflex arc. Long: a persisted per-context preference store where learning accumulates over time.

**6. Arbitration (deliberative).** Candidate behaviors each score themselves from drives, mode, and noise. Softmax pick, with hysteresis so Jiggy commits instead of flickering between wander, inspect, and rest. Hysteresis lives here and only here. It never gates reflexes. Learned pieces enter at this layer only as bias terms on the scores and as a spatial cost field, never as the selector.

**7. Motor and physics (rule-based, always on).** Steering behaviors (seek, flee, wander, arrive, avoid-edges) produce forces. A spring-damper body turns forces into squash, lean, and wobble. Animation-principle filters add anticipation, commitment, and follow-through. Expression is a side effect of forces, so it never repeats. There is no "happy bounce" clip; there is a body that bounces because arousal is high, and it looks different every time because it follows real acceleration.

**8. Constraint layer (rule-based, non-negotiable, wraps everything).** Never steal focus. Clicks that miss Jiggy pass through to whatever is underneath. Never cover the active text caret. Never end up permanently offscreen. The model cannot reach past this. It is the seatbelt.

Jiggy cannot be a purely click-through overlay, because then you could never grab it. So the window is click-through by default and becomes hit-catching only over Jiggy's actual silhouette, by toggling mouse-event handling from a live hit test against the body shape rather than the window rectangle. The empty space around Jiggy stays fully clickable, the blob itself is grabbable, and the guarantee is about the space around it and never stealing focus, not about the blob being inert.

### The interrupt contract

The reflex arc and the arbiter both want the motor, so the rules of possession must be explicit:

- **Reflexes preempt.** A reflex can seize the motor from any committed deliberate behavior, at any point in its motion. Hysteresis does not apply to reflexes; it only stops the arbiter from flickering between deliberate behaviors.
- **Habituation gates the seize.** Repeated stimuli produce progressively weaker preemption, so the startle-to-flinch-to-ignore progression and the interrupt system are the same mechanism.
- **Resume or re-arbitrate.** When a reflex completes, the interrupted behavior resumes only if its preconditions still hold. Otherwise the arbiter re-scores from the new state. Default to re-scoring, because a reflex usually fires precisely because the world just changed.

---

## The three engines of non-repetition

Adding more animations does not fix repetition. Making the mapping from situation to behavior history-dependent and continuous does.

1. **Continuous internal state.** Behaviors are scored against live drive levels plus perception plus noise, so no behavior is ever bit-for-bit identical.

2. **Habituation, the real anti-repetition weapon.** Real creatures stop reacting to repeated stimuli. Cursor darts at Jiggy: big startle, squash, `!`. Cursor keeps buzzing it: each startle weaker, then a flinch, then a wary watch, then nothing. Leave it alone and sensitivity recovers. One stimulus, an evolving response, a dozen felt beats with nothing extra authored.

3. **Drive conflict, which looks like deliberation.** When two drives disagree, the visible dithering reads as a mind deciding. Sociability wants attention while the user types fast; comfort and deference say "he's busy." Output is a small "should I? ...no" wiggle at the periphery. Hesitation nobody scripted, emergent by definition. Approach-avoidance is the most alive-looking thing a character can do.

---

## Nested timescales

An inner life comes from many clocks running at once:

- **Sub-second:** breathing, micro weight-shifts, eye saccades. Never fully still.
- **Seconds:** the current action (wander, inspect, flee, rest).
- **Minutes:** mood as a slow bias on all the fast systems. Grumpy just raises the threshold for play and lowers cursor tolerance. Not a state, a dial.
- **Session:** short-term memory and micro-personality. Startled a lot this session, jumpier baseline. Handled gently, more trusting.
- **Day:** a circadian curve. Late night drifts sleepy, slower, longer rests, yawns. Morning perks up. Same behaviors, different tempo and thresholds.

Stack these and the user's brain infers a persistent creature, because the evidence stays consistent across time.

---

## The emergence guardrail

Pure emergence drifts toward noise, which reads as glitchy, not alive. The filter is classic animation principle:

- **Anticipation:** telegraph before acting.
- **Commitment:** hysteresis so behaviors do not flicker.
- **Follow-through:** trail off, do not snap.

Alive minus those three equals broken. That is the whole difference. Note that this smooths the *output* only. Keeping the internal *state* stable is a separate job, below.

---

## Keeping the drives stable

Six coupled, drifting integrators are the first engine of non-repetition and also the easiest way to accidentally build a creature that latches into permanent grumpiness. The emergence guardrail does nothing for this, because it acts on motion, not on state. Stability is a requirement on the drives themselves:

- **Bounded ranges.** Every drive is clamped. None can run to a rail and stick there.
- **Decay toward baseline.** Leaky integration, so each drive relaxes back to its circadian-biased resting value when nothing is pushing it. Homeostasis, not accumulation.
- **Limited, mostly one-directional coupling.** Drives influence each other weakly, and you avoid two-way links, so you never build a loop where high arousal raises boredom raises arousal.
- **Events are impulses, not level sets.** A startle spikes arousal briefly and the decay brings it home. One bad evening cannot become a personality.

---

## Perception budget and the trust cost

Perception is cheap to compute and expensive to gather. Continuously sampling window titles, app identity, media state, and screen content is screen-recording-tier permission on macOS, a real battery draw, and the single biggest reason a user distrusts a desktop pet. Treat perception as a budget, not a free input.

Split signals by their true cost:

- **Cheap and non-invasive:** cursor position and velocity, typing cadence, idle time, time of day, focused-app identity, fullscreen flag, is-audio-or-video-playing flag. Most come from ordinary system APIs without reading a single pixel.
- **Expensive and invasive:** screen content, window text, anything that needs screen-recording permission.

Rule: the entire aliveness spine (gaze, drives, wander, habituation, the whole Phase 0 win) must run on cheap signals alone. Screen-content sampling has to justify itself signal by signal against its permission and battery cost, stays off by default, and never leaves the device. A pet that watches your screen has to earn every frame it looks at, and most of the charm never requires looking.

---

## Power: sleeping when you leave

A pet that lives on top of every window all day has to disappear as a resource when nobody is watching. The rule is simple: when the user walks away, Jiggy sleeps, stops moving, and the runtime suspends itself to effectively zero active cost.

Two tiers, off the idle and away signals the situation model already produces:

- **Doze (present but briefly idle).** A short lull with the user still around. Jiggy settles, lowers its energy, dims its reactions. The loops still run, just slow. This is ordinary rest, reversible in an instant.
- **Sleep (away, locked, display off, or fully occluded).** Extended idle, a locked screen, the display asleep, a full-screen app covering Jiggy, or the user on another Space. Jiggy plays a settle-and-sleep beat, then the system quiesces: the physics body is at rest so its fixed-timestep tick halts, the cognition tick is cancelled, and rendering stops because nothing on screen is changing.

Sleep is stopped, not slow. There is no polling. The app parks on OS notifications (system wake, screen lock and unlock, display sleep, Space changes) and a single global input monitor, so it burns no cycles until one of them fires. Waking is therefore event-driven, not a timer: when activity returns, Jiggy comes up with a stretch or a yawn, one of the authored set pieces, and the loops spin back up from a rested state, so the return reads as waking rather than resuming. Because the loops are suspended rather than throttled, the away state is genuinely close to zero CPU and GPU, which is the whole point on a laptop. A parked process waiting on an event is not literally zero, but it does no work.

---

## Where learning goes

Four things are worth learning. None of them is deep reinforcement learning.

| What | Form | Feedback |
|---|---|---|
| **Spatial preference** | Per-context cost field over semantic anchors. Steering flows around it as a bias field. | Where the user lets Jiggy sit vs drags it away, per mode. |
| **Activity budget** | A scalar per context for how lively vs quiet to be. | Being shoved or dismissed when too active in a mode. |
| **Engagement timing** | A bandit over moments: when a bid for attention lands well vs badly. | Reaction right after a bid (played with vs pushed away). |
| **Temperament drift** | Slow adjustment of drive baselines to the user over weeks. | Long-run aggregate of all the above. |

What they share: low-dimensional, conditioned on context, learned from implicit feedback, and each only biases a rule-based system. That is contextual-bandit and online-preference territory, not Markov Decision Process territory.

You almost certainly never need value functions, rollouts, or temporal credit assignment for a desktop pet. Reaching for full RL is the fastest way to a project that never ships. The realistic ceiling is a set of small preference models feeding a hand-built arbiter, and that ceiling is plenty high.

### Anchor the spatial field to meaning, not pixels

The spatial preference field is keyed to semantic anchors, never absolute screen coordinates. A cost map over raw pixels breaks the moment a monitor is plugged in, DPI or resolution changes, or the user rearranges windows, and it fails silently, because the old coordinates still look like valid coordinates while pointing at the wrong place. Key it to things that survive layout changes: regions relative to the screen edges and the dock, and zones relative to the focused window (over the media surface, near the active caret, beside the active window). Semantic anchors move with the layout. Pixels poison the model.

### Why "bias the field, do not pick the action" matters

A model that can only tilt preferences cannot invent a behavior you did not design, cannot violate a constraint, and cannot do anything catastrophic. Worst case it biases toward a slightly wrong spot, and the rule layer still keeps it legal and legible. You keep the personalization win and drop the unshippability risk.

---

## Worked example: learning to stay out of the way

The user drags Jiggy off the bottom of the screen while watching a movie, or shoves it aside while reading or typing. Jiggy should learn the region and mode and avoid it next time. Clean problem, and all the traps are in the details.

### Signal design
Implicit reward, per (context, anchored region):

- **Strong negative:** user grabs Jiggy, drags it out of a region, and it stays out. Stronger if repeated in the same context.
- **Weak negative:** shoving it with the cursor, or dismissing it.
- **Weak positive:** sitting undisturbed in a spot for a long time in that context, because it was not in the way.
- **Strong positive:** user drags Jiggy toward a spot, or pets and plays with it.

### Trap 1: attribution
Dragging Jiggy during typing is ambiguous. Avoid that region, or be less active while typing? Those update different models (spatial vs activity budget). Instrument enough to disentangle: was it moving, from where to where, in what mode. When unsure, split credit weakly across both and let repetition sharpen it.

### Trap 2: confounds
If the user is dragging lots of windows at that moment, they are rearranging the desktop, not judging Jiggy. Discount feedback that co-occurs with general window churn.

### Trap 3: the collapse trap (the important one)
If "being moved" is the only negative and "unnoticed" is neutral, the optimal policy is to hide in a corner and do nothing forever. Every naive pet-RL project rediscovers this.

Fix: an intrinsic liveliness term so "present and expressive" always carries positive baseline value, and that floor is **per-context, not one global dial.** This matters because the headline case, staying out of the way during fullscreen video, is exactly where you want the floor near zero, while an idle empty desktop wants a higher floor. A single global floor forces a bad trade: annoying during movies, or collapse-prone when idle. The floor shares its shape with the per-context activity budget (a scalar per mode), so it is not new machinery. Temperament sets the overall level of these floors: a cat sits lower everywhere than a needy pet.

### Trap 4: exploration on someone's screen
In RL you explore by trying things. Here, exploration means occasionally being annoying on purpose, which is user-hostile. Keep exploration tiny and safe: small perturbations around known-good spots, never "let me cover the video to see if they mind." The rule layer's built-in behavioral diversity supplies most of the exploration for free, so the learned part can stay near-greedy.

### Stability and privacy
- Conservative learning rate, regularized toward the shipped rule-based prior, so one grumpy evening cannot poison the model.
- Slow non-zero rate so it still tracks real habit changes (new job, new layout) instead of freezing.
- Everything on-device. This system reads screen and app activity, which is sensitive, so learning must never leave the machine.
- Ship a population prior for cold start, adapt locally from there.

---

## Where rules beat models, on purpose

Some things should never be learned, because learning them is strictly worse.

- **Safety and contract behavior.** Focus never stolen, clicks off Jiggy pass through, caret never covered, never stranded offscreen. Correctness guarantees. A model that violates them even rarely is one you cannot ship. Hard rules, above the model.
- **Cold-start aliveness.** A fresh install has zero data and still has to feel alive on day one. Rules give a strong day one; the model only refines over weeks.
- **Legibility.** When Jiggy does something odd you need to know why. A rule you can read beats a policy you have to reverse-engineer, and it is what lets you honestly offer a "reset personality" and a sense of control.
- **Expressive set pieces.** Zoomies, yawns, the peek off the edge and back, the pleased wobble on a gentle drop. Rare, high-charm, and no feedback signal is dense enough to learn a charming yawn. Author these, trigger them from thresholds.
- **Motor polish.** Anticipation, hysteresis, follow-through, squash timing. Always applied. You do not want a policy learning to skip anticipation to shave 80ms.
- **Anything sample-starved.** You get maybe a few dozen meaningful feedback events a day. Fine for a low-dimensional preference field with strong priors, starvation for anything hungrier.

**Rough test:** if it is a reflex, a guarantee, or a piece of craft, it is a rule. If it is a taste that varies per person and shows up in feedback, it is a model.

---

## Measurement and replay

The doc optimizes for "feels alive" and "legible." Both need to be observable, or they are just adjectives, and neither belongs bolted on at the end. Two capabilities, built during instrumentation:

- **Proxy metrics, watched over a dogfooding week:** drag-away rate per context, undisturbed dwell time, dismissal rate, petting and play rate. These are the same implicit-feedback signals the learner consumes, so the instrumentation does double duty as training data and as a health dashboard.
- **Deterministic record and replay:** log the full perception stream plus the seeded noise, so any behavior replays exactly. Bizarre moments become reproducible instead of anecdotal. The replay harness is also what makes "a rule you can read" a real promise rather than an aspiration, because legibility you cannot reconstruct is just a hope.

---

## Persistence: what Jiggy remembers

Jiggy persists. It carries what it learned from one session into the next, so the movie, reading, and typing preferences it picked up last week are still there when you relaunch. This was the one architectural fork in the doc, and it is now decided, because it sets the storage and consent model from the start rather than being retrofitted.

### The persistence boundary

The rule for what survives a restart is a single clean line, and it is the same line the nested timescales already draw:

- **Persist the slow, learned state.** The spatial preference fields, the activity budgets, the engagement-timing bandit, and the drifted temperament baselines. These accumulate over days and weeks and are the whole point of remembering.
- **Reset the fast, dynamical state.** Current drive levels, habituation counters, gaze target, physics, the session micro-personality. These re-derive or relax to baseline on launch.

So a relaunch feels like Jiggy waking up rested and still knowing you, not resuming a stale mood. What carries over is the shape of its preferences, never the arousal spike it happened to be in when you quit. This also means a single bad evening cannot survive a restart as a mood, because mood is not in the store. Only the slow, regularized learners are, and those already resist one-session poisoning by design.

### What is in the store

- Spatial preference fields, per context, keyed to semantic anchors, so the store survives a monitor or resolution change instead of pointing at the wrong place.
- Activity budgets and the per-context liveliness floors.
- Engagement-timing bandit state.
- Temperament drift: the drive baselines as adapted to this user.
- Metadata: schema version, the population-prior version it cold-started from, last-updated timestamp.

Not in the store: momentary drives, habituation, physics and gaze, session micro-personality. Optionally, last screen position, purely for the small nicety of reappearing where you left it.

### Storage and write policy

- On-device only, per macOS user account, never synced, never leaves the machine. The store is a model of your habits and where you push the pet around, which is behavioral data, so it stays local by construction.
- The state is low-dimensional by design, so it serializes tiny. A single versioned file with atomic writes (write a temp file, then rename) is enough. The brain itself needs no database.
- Write periodically and on clean shutdown, not on every learning update. A dirty shutdown costs at most a few minutes of slow adaptation, which is nothing to a learner that moves over weeks.
- The telemetry and replay log from the Measurement section is a separate, capped, rotated local store. It is not the brain, and it can be cleared on its own.

### Versioning, migration, and cold start

- The store carries a schema version. On load, an older version migrates up. An unreadable or incompatible-future store falls back to the shipped population prior, backs up the bad file for debugging, and never crashes the app.
- The frozen mode taxonomy is what makes this safe. Because the context labels are a stable contract, the per-context stores stay meaningful even after the situation classifier is swapped from rules to a model in Phase 3. Persistence is a large part of why that freeze matters.
- First-ever launch: no store, so seed from the population prior and the v0 temperament preset, feel alive on day one from rules alone, and write the first store. Every later launch loads the store and restores the learned state.

### Consent and the reset surface

- Keeping perception on cheap, non-invasive signals keeps the consent ask soft. There is no screen-recording permission to justify, so the disclosure is simply that Jiggy learns your habits, stores what it learns on this Mac only, and sends nothing anywhere.
- A menu-bar **Reset personality** wipes the learned store and re-seeds from the preset, behind a confirmation because it is destructive. This is the legibility promise made real and the escape hatch if learning ever drifts somewhere odd. Consider two grains: reset the personality (the brain) versus clear the activity log (the telemetry), plus a full delete-all-data for uninstall, since macOS does not reliably clear Application Support on its own.

### Sequencing

The decision lands now because storage and consent shape the app from the first commit. Most of the persistence code, though, has nothing to persist until Phase 2, since Phases 0 and 1 hold only ephemeral state. So Phase 1 stands up the store scaffolding, the schema-version discipline, and the telemetry log, and the learned fields begin filling the store at Phase 2, when the first learner exists.

---

## The v0 temperament preset: calm, and switchable

The v0 default is calm, and temperament is switchable from the menu bar. Calm is the right default for something that lives on top of every window for hours: the failure mode of an always-present companion is fatigue, and calm errs toward ignorable, which is the recoverable direction. You can always dial up. You cannot un-annoy a first impression. It also makes the cold-start prior conservative, so the learners adapt upward toward liveliness where the user rewards it, rather than starting hot and forcing the user to push Jiggy away before it settles.

Calm is not the collapse trap. It still breathes, tracks gaze, rests, and does the occasional gentle behavior. The difference is baseline and magnitude, not presence. The per-context liveliness floors keep it present; calm just sets them low.

### Calm as a parameter vector

Temperament is the vector the doc already named (drive baselines, habituation rate, solitude term, per-context liveliness floors), plus the reflex gain and motion tempo that scale off it. Calm is one point in that space:

- **Low arousal baseline, higher comfort baseline.** Rests more, spikes less.
- **Moderate curiosity, low sociability baseline.** Notices things, does not constantly seek you.
- **Fast habituation.** Repeated stimuli fade quickly, so it does not keep reacting to the same poke.
- **High solitude term.** Being left alone is contentment, not a penalty, which also keeps the collapse guard honest.
- **Low liveliness floors,** near zero during fullscreen media, modestly higher on an idle desktop.
- **Gentle reflex gain and slow tempo.** Small startles, unhurried steering, long settles.

The other archetypes are the same vector moved, not other code. Gremlin is high arousal, slow habituation, low solitude, high floors, big reflex gain, fast tempo. Aloof cat is low sociability and high solitude but sharper reactions than calm. Needy pet is high sociability and a low solitude term so alone-time reads as wanting you. Shipping calm costs nothing toward shipping the rest.

### The menu-bar surface

Configurability lives where the app already lives: a small preset submenu in the menu bar, Calm as default plus the other presets, alongside the existing Quit and the Reset personality item. This fits the minimal, menu-bar-only footprint. Sliders over the raw vector belong in a settings window later, if ever. A named-preset picker is enough for v0.

### What a switch does, and does not, touch

Switching preset is an explicit, authoritative statement of who Jiggy is, stronger than any implicit feedback, so it sets the temperament base vector directly. But it is surgical:

- **It resets the temperament base** to the new preset and lets the slow temperament drift re-accumulate from there, because the old drift was learned against the old base and is now stale.
- **It preserves the where and when.** The spatial preference field, the engagement timing, and the relative per-context activity deviations survive untouched. Switching to Playful makes Jiggy bouncier when present; it does not make it forget to stay out of the way during a movie. That separation is the whole payoff of keeping personality and environment learning in different stores.

Because the drives are leaky integrators relaxing toward their baselines, moving the base does not snap the body. Jiggy eases into the new temperament over seconds, the way a mood lifts, rather than transplanting instantly. The runtime switch feels organic for free.

### One small sub-choice: drift on, or locked

Temperament drift can wander a chosen preset over weeks. Recommended default: leave drift on but bounded and regularized, as designed, so it personalizes within a neighborhood of Calm, and expose a "let Jiggy's personality adapt over time" toggle so a user who wants Calm to stay exactly Calm can lock it. That keeps the drift consensual and legible, the same principle as the reset surface. If you would rather not ship the toggle in v0, default drift on and rely on Reset personality as the escape hatch.

---

## Build path

**Phase 0, no ML.** Physics body at fixed timestep, steering, the gaze and attention spine (salience arbiter plus saccade-and-pursuit), the drives with their stability properties, the reflex arc and short-term habituation, and the idle-to-sleep power policy. All rule-based, all on cheap perception signals only. This is the entire "feels alive" win and it ships on its own.

**Phase 1, instrument.** Before any model, log the context vector, Jiggy's state and action, and every user event (drag start and end with from and to, clicks, dismissals, idle onset). Add the proxy metrics and the deterministic record-replay harness here, not later. And freeze the mode taxonomy now: the label set and the meaning of each mode become a stable contract, so a later classifier swap does not orphan the data. Stand up the persistence store here too, the schema, the version stamp, atomic writes, and the local telemetry log, even though there is nothing learned to put in it yet. Data is the gate.

**Phase 2, spatial preference field.** The drag-away learner, keyed to semantic anchors. Highest value, most legible, safest, because it only biases steering. The first ML, and it directly delivers the movie, reading, and typing behavior. This is where the persistence store starts carrying real learned state across sessions.

**Phase 3, learned situation classifier.** Replace the threshold-based mode detector with a small model over the signals once the rules get brittle. It replaces the classifier's internals only; the frozen label set is unchanged, so Phase 2's preferences stay valid. Expect it to redraw boundaries at the margins and relabel a few points; the regularization toward the shipped prior absorbs that residue.

**Phase 4, engagement-timing and activity bandits.** Learn when to bid and how lively to be per context.

**Phase 5, probably skip.** Full temporal RL. For a desktop companion you likely never need it. Treat "we need real RL" as a prompt to recheck whether a bandit would do.

---

## Decisions

**Persistence: decided. Jiggy remembers.** It persists the slow learned state (spatial preference fields, activity budgets, engagement-timing bandit, and the drifted temperament baselines) to a local on-device store and reloads it on launch. The momentary state still resets each launch, so what carries over is what Jiggy learned, not the mood it was last in. The store, the consent model, and the reset surface are specified in the Persistence section above.

**Temperament: calm by default, switchable from the menu bar.** Temperament is one parameter vector (drive baselines, habituation rate, solitude term, per-context liveliness floors, reflex gain, tempo), and v0 ships the Calm point of that space. The other archetypes are presets in the same vector, selectable from a menu-bar submenu, with no code fork. A switch resets the temperament base and preserves the spatial and timing learning. The full definition and switch semantics are in the v0 temperament preset section above.

With that, the north star has no open architectural decisions left. The next move is **Phase 0:** the physics body, steering, the gaze and attention spine, the drives with their stability properties, the reflex arc, and short-term habituation, all rule-based on cheap signals. Build the calm creature first and prove it feels alive before any learning goes in.
