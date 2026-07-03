// ---- Pure helpers (no Date.now/Math.random inside — easy to unit test later) ----

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function lerp(a, b, t) {
  return a + (b - a) * t;
}

function distance(ax, ay, bx, by) {
  return Math.hypot(bx - ax, by - ay);
}

function weightedChoice(weights, rngValue) {
  const total = Object.values(weights).reduce((sum, w) => sum + w, 0);
  let acc = 0;
  const target = rngValue * total;
  for (const [key, weight] of Object.entries(weights)) {
    acc += weight;
    if (target <= acc) return key;
  }
  return Object.keys(weights)[0];
}

// All target-picking helpers below treat (x, y) as the blob's top-left corner,
// so they must subtract blobSize from the upper bound of their range — otherwise
// a "bottom-right corner" target sits almost entirely off-screen.

function innerBounds(bounds, margin, blobSize) {
  return {
    maxX: bounds.width - margin - blobSize.width,
    maxY: bounds.height - margin - blobSize.height,
  };
}

function pickCorner(bounds, margin, blobSize, cornerIndex) {
  const { maxX, maxY } = innerBounds(bounds, margin, blobSize);
  const corners = [
    { x: margin, y: margin },
    { x: maxX, y: margin },
    { x: margin, y: maxY },
    { x: maxX, y: maxY },
  ];
  return corners[cornerIndex % corners.length];
}

function pickBorderPoint(bounds, margin, blobSize, bandDepth, edgeIndex, rngAlong, rngDepth) {
  // A point that hugs one edge within a shallow band, so the pet tends to settle
  // along the border of the screen instead of over the middle of the work area.
  const { maxX, maxY } = innerBounds(bounds, margin, blobSize);
  const along = (min, max) => lerp(min, max, rngAlong);
  const depth = (min, max) => lerp(min, max, rngDepth);

  const bands = [
    { x: along(margin, maxX), y: depth(margin, margin + bandDepth) }, // top strip
    { x: along(margin, maxX), y: depth(maxY - bandDepth, maxY) }, // bottom strip
    { x: depth(margin, margin + bandDepth), y: along(margin, maxY) }, // left strip
    { x: depth(maxX - bandDepth, maxX), y: along(margin, maxY) }, // right strip
  ];
  return bands[edgeIndex % bands.length];
}

function pickEdgeTarget(bounds, blobSize, edgeIndex, rngAlong) {
  // Mostly-offscreen point hugging one edge, so the blob can "peek" back in —
  // but a slice of it (peekVisible) always stays on-screen.
  const peekVisibleX = blobSize.width * 0.4;
  const peekVisibleY = blobSize.height * 0.4;
  const edges = [
    { x: lerp(0, bounds.width - blobSize.width, rngAlong), y: -blobSize.height + peekVisibleY }, // top
    { x: lerp(0, bounds.width - blobSize.width, rngAlong), y: bounds.height - peekVisibleY }, // bottom
    { x: -blobSize.width + peekVisibleX, y: lerp(0, bounds.height - blobSize.height, rngAlong) }, // left
    { x: bounds.width - peekVisibleX, y: lerp(0, bounds.height - blobSize.height, rngAlong) }, // right
  ];
  return edges[edgeIndex % edges.length];
}

function clampVisible(point, bounds, blobSize, minVisible) {
  // Last-resort safety net: whatever produced this point, guarantee at least
  // `minVisible` px of the blob stays on-screen on every axis.
  return {
    x: clamp(point.x, -(blobSize.width - minVisible), bounds.width - minVisible),
    y: clamp(point.y, -(blobSize.height - minVisible), bounds.height - minVisible),
  };
}

// ---- Runtime wiring ----

const BLOB_WIDTH = 78;
const BLOB_HEIGHT = 62;
const BLOB_SIZE = { width: BLOB_WIDTH, height: BLOB_HEIGHT };
const ROAM_MARGIN = 24;
const REST_MARGIN = 24;
const BORDER_BAND_DEPTH = 160; // how deep the "stay out of the way" edge strip is
const MIN_VISIBLE = 20; // px of the blob guaranteed on-screen at all times
const MOVE_SPEED = 80; // px/sec — slow, calm roaming
const ARRIVE_THRESHOLD = 4;

// Favor sitting still (idle/rest) over roaming, and keep resting/wandering
// spots along the screen border rather than the middle of the work area.
const MODE_WEIGHTS = { idle: 0.5, wander: 0.2, rest: 0.25, peek: 0.05 };
const MODE_DWELL_MS = {
  idle: [3000, 6000],
  wander: [2500, 5000], // pause at the border spot before deciding what's next
  rest: [6000, 12000],
  peek: [800, 1600],
};

// Emotions: 'happy'/'surprised' come from direct interaction (click, drag),
// the rest are ambient — either the resting behavior mode or a randomized
// idle quirk/cursor-proximity startle layered on top of it.
const BASE_EMOTION_BY_MODE = { idle: 'neutral', wander: 'neutral', rest: 'sleepy', peek: 'curious' };
const QUIRK_EMOTIONS = ['blush', 'thinking', 'annoyed'];
const BUBBLE_BY_EMOTION = {
  surprised: '!',
  curious: '?',
  sleepy: '\u{1F4A4}',
  thinking: '\u{22EF}',
  annoyed: '\u{1F4A2}',
  blush: '♡',
  happy: '♪',
};

// Which blush treatment (if any) each emotion wears — 'hatch' for stronger
// reactions, 'plain' for a soft ambient flush, none for neutral/alert moods.
const BLUSH_STYLE_BY_EMOTION = {
  neutral: 'none',
  curious: 'none',
  surprised: 'none',
  annoyed: 'none',
  sleepy: 'plain',
  thinking: 'plain',
  blush: 'hatch',
  happy: 'hatch',
};

const blobEl = document.getElementById('blob');
const eyeLeft = document.querySelector('.eye.left');
const eyeRight = document.querySelector('.eye.right');
const blushLeft = document.querySelector('.blush.left');
const blushRight = document.querySelector('.blush.right');
const bubbleEl = document.getElementById('bubble');
const bubbleTextEl = bubbleEl.querySelector('.bubble-text');

const bounds = { width: window.innerWidth, height: window.innerHeight };

const state = {
  x: bounds.width / 2,
  y: bounds.height / 2,
  mode: 'idle',
  target: { x: bounds.width / 2, y: bounds.height / 2 },
  modeEndsAt: performance.now() + 1500,
  moving: false,
  happyUntil: 0,
  happyResumeMode: 'idle',
  nextBlinkAt: performance.now() + randomRange(2000, 5000),
  dragging: false,
  dragOffset: { x: 0, y: 0 },
  appliedEmotion: null,
  quirkEmotion: null,
  quirkUntil: 0,
  nextQuirkAt: performance.now() + randomRange(4000, 9000),
  proximityUntil: 0,
  proximityCooldownUntil: 0,
};

const cursor = { x: bounds.width / 2, y: bounds.height / 2 };
let isHovering = false;

function randomRange(min, max) {
  return min + Math.random() * (max - min);
}

function startMode(mode, now) {
  state.mode = mode;

  if (mode === 'wander') {
    const p = pickBorderPoint(
      bounds,
      ROAM_MARGIN,
      BLOB_SIZE,
      BORDER_BAND_DEPTH,
      Math.floor(Math.random() * 4),
      Math.random(),
      Math.random()
    );
    state.target = p;
    state.moving = true;
  } else if (mode === 'rest') {
    const p = pickCorner(bounds, REST_MARGIN, BLOB_SIZE, Math.floor(Math.random() * 4));
    state.target = p;
    state.moving = true;
  } else if (mode === 'peek') {
    const p = pickEdgeTarget(bounds, BLOB_SIZE, Math.floor(Math.random() * 4), Math.random());
    state.target = p;
    state.moving = true;
  } else {
    state.moving = false;
    const [min, max] = MODE_DWELL_MS.idle;
    state.modeEndsAt = now + randomRange(min, max);
  }
}

function transitionToNextMode(now) {
  const next = weightedChoice(MODE_WEIGHTS, Math.random());
  startMode(next, now);
}

function updateMovement(dt, now) {
  if (!state.moving) return;

  const d = distance(state.x, state.y, state.target.x, state.target.y);
  if (d <= ARRIVE_THRESHOLD) {
    const safeTarget = clampVisible(state.target, bounds, BLOB_SIZE, MIN_VISIBLE);
    state.x = safeTarget.x;
    state.y = safeTarget.y;
    state.moving = false;

    const [min, max] = MODE_DWELL_MS[state.mode];
    state.modeEndsAt = now + randomRange(min, max);

    // Peeking back inward after lingering at the edge.
    if (state.mode === 'peek') {
      state.pendingReturn = true;
    }
    return;
  }

  const step = MOVE_SPEED * dt;
  const t = clamp(step / d, 0, 1);
  state.x = lerp(state.x, state.target.x, t);
  state.y = lerp(state.y, state.target.y, t);

  const safe = clampVisible(state, bounds, BLOB_SIZE, MIN_VISIBLE);
  state.x = safe.x;
  state.y = safe.y;
}

function maybeAdvanceMode(now) {
  if (state.moving) return;

  if (state.mode === 'peek' && state.pendingReturn && now >= state.modeEndsAt) {
    state.pendingReturn = false;
    startMode('wander', now);
    return;
  }

  if (now >= state.modeEndsAt) {
    transitionToNextMode(now);
  }
}

function triggerHappy(now) {
  if (state.mode !== 'happy') {
    state.happyResumeMode = state.mode;
  }
  state.mode = 'happy';
  state.happyUntil = now + 500;
  state.moving = false;
}

function updateHappy(now) {
  if (state.mode === 'happy' && now >= state.happyUntil) {
    state.mode = state.happyResumeMode;
    state.modeEndsAt = now + randomRange(800, 1500);
  }
}

function updateBlink(now) {
  if (now >= state.nextBlinkAt) {
    eyeLeft.classList.add('blink');
    eyeRight.classList.add('blink');
    setTimeout(() => {
      eyeLeft.classList.remove('blink');
      eyeRight.classList.remove('blink');
    }, 120);
    state.nextBlinkAt = now + randomRange(2500, 6000);
  }
}

function updateHoverState() {
  // Ignore-state is forced off for the duration of a drag (see mousedown handler)
  // so a fast drag can't outrun the hover box and drop the mouseup event.
  if (state.dragging) return;

  const withinX = cursor.x >= state.x && cursor.x <= state.x + BLOB_WIDTH;
  const withinY = cursor.y >= state.y && cursor.y <= state.y + BLOB_HEIGHT;
  const hovering = withinX && withinY;

  if (hovering !== isHovering) {
    isHovering = hovering;
    window.cuteAgent.setIgnoreMouseEvents(!hovering);
  }
}

function updateEmotionTriggers(now) {
  const idleAndAwake = !state.dragging && state.mode === 'idle';

  if (idleAndAwake && now >= state.quirkUntil && now >= state.nextQuirkAt) {
    state.quirkEmotion = QUIRK_EMOTIONS[Math.floor(Math.random() * QUIRK_EMOTIONS.length)];
    const duration = randomRange(1200, 2200);
    state.quirkUntil = now + duration;
    state.nextQuirkAt = now + duration + randomRange(6000, 12000);
  }

  if (idleAndAwake && now >= state.proximityCooldownUntil) {
    const centerX = state.x + BLOB_WIDTH / 2;
    const centerY = state.y + BLOB_HEIGHT / 2;
    if (distance(cursor.x, cursor.y, centerX, centerY) < 70) {
      state.proximityUntil = now + 900;
      state.proximityCooldownUntil = now + randomRange(8000, 15000);
    }
  }
}

function computeDesiredEmotion(now) {
  if (state.dragging) return 'surprised';
  if (state.mode === 'happy') return 'happy';
  if (now < state.quirkUntil) return state.quirkEmotion;
  if (now < state.proximityUntil) return 'surprised';
  return BASE_EMOTION_BY_MODE[state.mode] || 'neutral';
}

function applyBlush(emotion) {
  const style = BLUSH_STYLE_BY_EMOTION[emotion] || 'none';
  for (const el of [blushLeft, blushRight]) {
    el.classList.toggle('show', style !== 'none');
    el.classList.toggle('hatch', style === 'hatch');
  }
}

function applyEmotion(emotion) {
  if (emotion === state.appliedEmotion) return;
  if (state.appliedEmotion) blobEl.classList.remove(`emo-${state.appliedEmotion}`);
  blobEl.classList.add(`emo-${emotion}`);
  state.appliedEmotion = emotion;
  applyBlush(emotion);

  const text = BUBBLE_BY_EMOTION[emotion];
  if (text) {
    bubbleTextEl.textContent = text;
    bubbleTextEl.classList.remove('show');
    void bubbleTextEl.offsetWidth; // restart the pop animation
    bubbleTextEl.classList.add('show');
  }
}

function updateEmotion(now) {
  updateEmotionTriggers(now);
  applyEmotion(computeDesiredEmotion(now));
}

function render(now) {
  const t = now / 1000;
  const wobble = Math.sin(t * 2.2);
  const bobY = state.dragging || state.mode === 'happy' ? 0 : wobble * 3;

  let scaleX = 1;
  let scaleY = 1;

  if (state.dragging) {
    scaleX = 1.05;
    scaleY = 0.95;
  } else if (state.mode === 'happy') {
    const progress = clamp(1 - (state.happyUntil - now) / 500, 0, 1);
    const bounce = Math.sin(progress * Math.PI * 3) * (1 - progress);
    scaleY = 1 + bounce * 0.25;
    scaleX = 1 - bounce * 0.15;
  } else if (state.moving) {
    scaleX = 1.08;
    scaleY = 0.92;
  } else {
    scaleY = 1 + wobble * 0.03;
    scaleX = 1 - wobble * 0.02;
  }

  blobEl.style.transform =
    `translate(${state.x}px, ${state.y + bobY}px) scale(${scaleX}, ${scaleY})`;

  bubbleEl.style.transform = `translate(${state.x + BLOB_WIDTH / 2 - 9}px, ${state.y - 16}px)`;
}

let lastFrame = performance.now();

function tick(now) {
  const dt = clamp((now - lastFrame) / 1000, 0, 0.1);
  lastFrame = now;

  if (!state.dragging) {
    updateHappy(now);
    updateMovement(dt, now);
    maybeAdvanceMode(now);
  }
  updateBlink(now);
  updateEmotion(now);
  updateHoverState();
  render(now);

  requestAnimationFrame(tick);
}

window.addEventListener('mousemove', (e) => {
  cursor.x = e.clientX;
  cursor.y = e.clientY;

  if (state.dragging) {
    state.x = clamp(cursor.x - state.dragOffset.x, 0, bounds.width - BLOB_WIDTH);
    state.y = clamp(cursor.y - state.dragOffset.y, 0, bounds.height - BLOB_HEIGHT);
  }
});

blobEl.addEventListener('mousedown', (e) => {
  e.preventDefault();
  state.dragging = true;
  state.moving = false;
  state.dragOffset = { x: cursor.x - state.x, y: cursor.y - state.y };
  blobEl.classList.add('dragging');
  // Force mouse events on for the whole drag so a fast move can't outrun the
  // hover box and leave the click-through toggle stuck off.
  isHovering = true;
  window.cuteAgent.setIgnoreMouseEvents(false);
});

window.addEventListener('mouseup', () => {
  if (!state.dragging) return;
  state.dragging = false;
  blobEl.classList.remove('dragging');
  triggerHappy(performance.now());
});

requestAnimationFrame(tick);
