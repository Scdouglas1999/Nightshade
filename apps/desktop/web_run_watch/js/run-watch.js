/*
 * Nightshade Run-Watch — phone/tablet web client.
 *
 * Vanilla JS so the bundle stays tiny. Three concerns:
 *
 *  1. Pairing — first run prompts for the WORD-WORD-NNNN code the desktop
 *     surfaces (e.g. STAR-LYRA-1234, see TokenManager.generatePairingCode),
 *     calls /api/pairing/verify, persists the resulting session token in
 *     localStorage.
 *
 *  2. Live data — once authenticated:
 *       - fetch /api/run-watch/snapshot every 15s as a baseline + on
 *         reconnect,
 *       - subscribe to /api/run-watch/events (SSE) for the firehose,
 *       - poll /api/run-watch/frame-thumbnail when a FrameAccepted /
 *         ExposureFinished event arrives, plus every 10s as a fallback
 *         so the panel never goes stale.
 *
 *  3. Controls — POST to existing /api/sequencer/{pause,resume,skip,stop}
 *     so we don't duplicate any backend logic.
 */
'use strict';

// ---------------------------------------------------------------------------
// Auth + storage
// ---------------------------------------------------------------------------
const STORAGE_TOKEN_KEY = 'nightshade.runwatch.token';
const STORAGE_DEVICE_ID_KEY = 'nightshade.runwatch.deviceId';
const STORAGE_OPTS_KEY = 'nightshade.runwatch.opts';

function getToken() {
  try { return localStorage.getItem(STORAGE_TOKEN_KEY); } catch { return null; }
}
function setToken(t) {
  try {
    if (t) localStorage.setItem(STORAGE_TOKEN_KEY, t);
    else localStorage.removeItem(STORAGE_TOKEN_KEY);
  } catch { /* private mode — fall back to in-memory */ inMemoryToken = t || null; }
}
let inMemoryToken = null;
function effectiveToken() { return getToken() || inMemoryToken; }

function getOrCreateDeviceId() {
  let id;
  try { id = localStorage.getItem(STORAGE_DEVICE_ID_KEY); } catch { id = null; }
  if (id) return id;
  // crypto.randomUUID is widely supported on modern mobile browsers;
  // fall back to a Math.random-based id otherwise (good enough for a
  // device handle that's only used to label the paired-devices table).
  const fresh = (window.crypto && crypto.randomUUID)
    ? crypto.randomUUID()
    : 'web-' + Math.random().toString(36).slice(2, 10);
  try { localStorage.setItem(STORAGE_DEVICE_ID_KEY, fresh); } catch { /* ignore */ }
  return fresh;
}

function loadOpts() {
  try {
    const raw = localStorage.getItem(STORAGE_OPTS_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch { return {}; }
}
function saveOpts(opts) {
  try { localStorage.setItem(STORAGE_OPTS_KEY, JSON.stringify(opts)); } catch { /* ignore */ }
}

// ---------------------------------------------------------------------------
// Fetch helpers — all requests carry the bearer token automatically.
//
// Two cross-cutting concerns live here rather than in each caller:
//
//  * Rate limiting. The server budgets 60 reads/s per token
//    (`defaultTokenBucketConfigs`) and answers a denial with 429 +
//    `retryAfterSecs` + a `retry-after` header. This page shares that budget
//    with every other tab the operator has open, so a 429 is a normal thing to
//    meet, not a bug. Every request goes through one gate that honours the
//    server's own retry window; nothing here retries inside it, and the raw
//    429 body never reaches the screen.
//
//  * Link health. Whether the last exchange with the server succeeded is the
//    one fact the rest of the page cannot render honestly without, so it is
//    recorded on every call rather than at each call site.
// ---------------------------------------------------------------------------

/// Epoch ms before which no request may be sent, set from the server's own
/// `retryAfterSecs`. Zero means the budget is not exhausted.
let rateLimitedUntil = 0;

/// Typed refusals raised by [apiFetch]. Callers switch on `error.kind` rather
/// than on message text.
class ApiError extends Error {
  constructor(kind, message, detail) {
    super(message);
    this.kind = kind;
    this.detail = detail || {};
  }
}

function rateLimitRemainingSecs() {
  const ms = rateLimitedUntil - Date.now();
  return ms > 0 ? Math.ceil(ms / 1000) : 0;
}

/// Read the server's retry window off a 429. Prefers the JSON body's
/// `retryAfterSecs` (rate_limit_middleware `_denyRateLimited`), falls back to
/// the `retry-after` header, and finally to one second — the smallest window
/// the server ever asks for.
async function retryAfterSecsFrom(res) {
  let secs = null;
  try {
    const body = await res.clone().json();
    const raw = body && (body.retryAfterSecs ?? body.retryAfterSeconds);
    if (typeof raw === 'number' && isFinite(raw) && raw > 0) secs = raw;
  } catch { /* body is not the JSON shape we know — fall through */ }
  if (secs == null) {
    const header = Number(res.headers.get('retry-after'));
    if (isFinite(header) && header > 0) secs = header;
  }
  return secs == null ? 1 : Math.min(Math.ceil(secs), 300);
}

async function apiFetch(path, opts) {
  opts = opts || {};
  const waiting = rateLimitRemainingSecs();
  if (waiting > 0) {
    throw new ApiError(
      'rate_limited',
      'Server is rate-limiting this device',
      { retryAfterSecs: waiting },
    );
  }
  const headers = new Headers(opts.headers || {});
  const token = effectiveToken();
  if (token) headers.set('Authorization', 'Bearer ' + token);
  if (opts.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }
  let res;
  try {
    res = await fetch(path, Object.assign({}, opts, { headers }));
  } catch (e) {
    // A transport failure is the signal that the server is gone. It is the
    // only evidence this page ever gets that a run it is painting as
    // "running" may have stopped minutes ago.
    noteLinkFailure('unreachable', e && e.message ? e.message : String(e));
    throw new ApiError('unreachable', 'Cannot reach the server', {
      cause: e,
    });
  }
  if (res.status === 401 || res.status === 403) {
    // Tokens can be revoked desktop-side; force re-pair. The reason goes ON
    // THE SCREEN, not only into the thrown error — nothing catches
    // 'auth_required' to render it, which is how this landed as a silent
    // logout.
    setToken(null);
    showPairScreen(
      token
        ? 'This device\'s pairing is no longer accepted — the desktop ' +
          'rejected it, which happens when the pairing was revoked there or ' +
          'the profile it belonged to was replaced. Pair again with a fresh ' +
          'code from the desktop\'s Remote Access screen.'
        : null,
    );
    throw new ApiError('auth_required', 'Pairing is no longer accepted');
  }
  if (res.status === 429) {
    const secs = await retryAfterSecsFrom(res);
    rateLimitedUntil = Date.now() + secs * 1000;
    noteLinkFailure('rate_limited', 'retry in ' + secs + 's');
    throw new ApiError(
      'rate_limited',
      'Server is rate-limiting this device',
      { retryAfterSecs: secs },
    );
  }
  // Any answer at all — including a 4xx/5xx — proves the server is there.
  rateLimitedUntil = 0;
  return res;
}

async function apiJson(path, opts) {
  const res = await apiFetch(path, opts);
  if (!res.ok) {
    let body;
    try { body = await res.json(); } catch { body = await res.text(); }
    throw new ApiError('http_error', typeof body === 'string'
      ? `${path} ${res.status}: ${body}`
      : `${path} ${res.status}: ${body.error || JSON.stringify(body)}`,
      { status: res.status });
  }
  return res.json();
}

/// Response body of a control POST, or null when the server sent none. A
/// control button must report the server's own answer, and that answer is in
/// the body, not in the status code.
async function apiJsonOrNull(res) {
  try { return await res.json(); } catch { return null; }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------
function $(id) { return document.getElementById(id); }

function toast(message, kind) {
  kind = kind || 'info';
  const region = $('toast-region');
  if (!region) return;
  const el = document.createElement('div');
  el.className = 'toast toast-' + kind;
  el.textContent = message;
  region.appendChild(el);
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transition = 'opacity 0.2s';
    setTimeout(() => { try { region.removeChild(el); } catch {} }, 250);
  }, 3000);
}

function setConnectionState(state) {
  const dot = $('connection-dot');
  if (!dot) return;
  dot.classList.remove('conn-connected', 'conn-disconnected', 'conn-reconnecting');
  if (state === 'connected') {
    dot.classList.add('conn-connected');
    dot.title = 'Connected';
  } else if (state === 'reconnecting') {
    dot.classList.add('conn-reconnecting');
    dot.title = 'Reconnecting…';
  } else {
    dot.classList.add('conn-disconnected');
    dot.title = 'Disconnected';
  }
}

// ---------------------------------------------------------------------------
// Link health
//
// A phone left on the nightstand shows whatever the last successful snapshot
// said. Before this block that picture kept its green "running" badge for as
// long as the tab stayed open, however long ago the server had died — the only
// tell was an 8px dot's hover title, which a phone has no way to show. The
// state below is what lets the page say plainly that it has lost contact, and
// how stale what it is showing has become.
// ---------------------------------------------------------------------------

// Poll cadences. Declared here because the staleness threshold is derived
// from the snapshot interval and both are read by the watchdog below.
const SNAPSHOT_INTERVAL_MS = 15000;
const FRAME_FALLBACK_MS = 10000;

/// Epoch ms of the last snapshot the server actually answered. 0 = never.
let lastSnapshotAt = 0;
/// Epoch ms this session started polling, so "nothing yet" can be told apart
/// from "nothing for longer than a poll interval".
let sessionStartedAt = 0;
/// Non-null while the link is known bad: `{kind, detail}`.
let linkFailure = null;
/// The sequencer state the last good snapshot reported, kept so the banner can
/// name what is going stale without the badge continuing to assert it.
let lastKnownState = null;
let staleWatchdogTimer = null;

// One snapshot interval plus a poll's worth of slack. Past this the page has
// missed a scheduled exchange and must stop presenting its cache as live.
const SNAPSHOT_STALE_MS = SNAPSHOT_INTERVAL_MS + 5000;
const STALE_WATCHDOG_MS = 2000;

function noteLinkOk() {
  lastSnapshotAt = Date.now();
  linkFailure = null;
}

function noteLinkFailure(kind, detail) {
  linkFailure = { kind, detail: detail || '' };
}

/// True when this page cannot vouch for what it is showing: either the last
/// exchange failed outright, or no exchange has succeeded within a poll
/// interval.
function isLinkStale() {
  if (linkFailure && linkFailure.kind === 'unreachable') return true;
  // Nothing answered yet: the first exchange gets one poll interval to land
  // before "still loading" becomes "no contact". A failed first fetch does not
  // wait — it is already caught above.
  if (lastSnapshotAt === 0) {
    return sessionStartedAt > 0 && Date.now() - sessionStartedAt > SNAPSHOT_STALE_MS;
  }
  return Date.now() - lastSnapshotAt > SNAPSHOT_STALE_MS;
}

function formatAge(ms) {
  const s = Math.round(ms / 1000);
  if (s < 60) return s + 's';
  const m = Math.floor(s / 60);
  if (m < 60) return m + 'm ' + (s % 60) + 's';
  return Math.floor(m / 60) + 'h ' + (m % 60) + 'm';
}

/// Repaint the banner + badge + dot from the current link state. Called on
/// every snapshot outcome and on the watchdog tick, so the page can never sit
/// green past a missed poll.
function renderLinkState() {
  const banner = $('link-banner');
  const badge = $('state-badge');
  const stale = isLinkStale();
  const waiting = rateLimitRemainingSecs();

  if (!stale) {
    if (banner) {
      if (waiting > 0) {
        // The link is alive; the server is only asking us to slow down. Say
        // that instead of the raw 429 body.
        banner.classList.remove('hidden');
        banner.textContent =
          'Server is rate-limiting this device — next update in ' +
          waiting + 's.';
      } else {
        banner.classList.add('hidden');
        banner.textContent = '';
      }
    }
    return;
  }

  // Stale: the badge must stop asserting a state nobody has confirmed.
  if (badge) {
    badge.textContent = 'unknown';
    badge.className = 'badge badge-error';
  }
  setConnectionState('disconnected');

  const age = lastSnapshotAt === 0 ? null : Date.now() - lastSnapshotAt;
  const lead = linkFailure && linkFailure.kind === 'unreachable'
    ? 'Cannot reach the observatory server.'
    : 'No answer from the observatory server.';
  const since = age == null
    ? ' No update has arrived since this page opened.'
    : ' Last update ' + formatAge(age) + ' ago' +
      (lastKnownState ? ' (state was "' + lastKnownState + '")' : '') +
      '. The values below are from then and may be wrong.';
  if (banner) {
    banner.classList.remove('hidden');
    banner.textContent = lead + since;
  }
}

function startStaleWatchdog() {
  stopStaleWatchdog();
  staleWatchdogTimer = setInterval(renderLinkState, STALE_WATCHDOG_MS);
}

function stopStaleWatchdog() {
  if (staleWatchdogTimer) {
    clearInterval(staleWatchdogTimer);
    staleWatchdogTimer = null;
  }
}

/// Show the pair screen, saying WHY when this device has just lost a pairing
/// it had.
///
/// A device whose token the desktop revoked was dropped here silently: the
/// screen it landed on was byte-for-byte the one a browser that had never
/// paired gets (verified — the two screenshots hashed identically), with
/// `#pair-status` empty and the thrown 'Pairing is no longer accepted' reaching
/// nothing. From bed that reads as "the app forgot me", and the next move —
/// walk to the desktop for a fresh code — is the one thing it did not say.
///
/// [reason] is that sentence, and [tone] is `'error'` for something that
/// happened TO this device and `'info'` for something the operator did. Absent
/// (first run) the line is cleared rather than left holding the last one.
function showPairScreen(reason, tone) {
  $('pair-screen').classList.remove('hidden');
  $('main-screen').classList.add('hidden');
  const statusEl = $('pair-status');
  if (statusEl) {
    statusEl.textContent = reason || '';
    statusEl.className = reason
      ? 'pair-status ' + (tone || 'error')
      : 'pair-status';
  }
  closeSSE();
  stopPolling();
}

function showMainScreen() {
  $('pair-screen').classList.add('hidden');
  $('main-screen').classList.remove('hidden');
  bootSession();
}

// ---------------------------------------------------------------------------
// Pairing flow
// ---------------------------------------------------------------------------
// Map the server's machine-readable pairing failures onto something an
// operator standing at the telescope can act on. Without this the raw code
// ("invalid_pairing_code") was printed straight into the status line. Mirrors
// the dashboard's handlePairSubmit mapping.
function pairingErrorText(data, status) {
  const raw = String((data && (data.error || data.message)) || '');
  if (raw.includes('invalid_pairing_code')) {
    return 'Pairing code is not recognised. Check the code on the desktop.';
  }
  if (raw.includes('pairing_code_expired')) {
    return 'Pairing code expired. Request a new one on the desktop.';
  }
  if (raw.includes('pairing_code_already_used')) {
    return 'That code has already been claimed. Request a new one.';
  }
  if (status === 429 || raw.includes('temporarily locked')) {
    return 'Too many failed attempts. Wait a moment before trying again.';
  }
  return raw || 'Pairing failed.';
}

async function startPairing(code) {
  const trimmed = (code || '').trim();
  const statusEl = $('pair-status');
  statusEl.className = 'pair-status';
  // Codes are WORD-WORD-NNNN (TokenManager.generatePairingCode), never six
  // digits. Keep this in step with the dashboard's pair-modal guard.
  if (!/^[A-Za-z0-9-]{6,32}$/.test(trimmed)) {
    statusEl.textContent =
      'Enter the pairing code from the desktop (like STAR-LYRA-1234).';
    statusEl.classList.add('error');
    return;
  }

  statusEl.textContent = 'Pairing…';

  try {
    const body = JSON.stringify({
      code: trimmed,
      deviceId: getOrCreateDeviceId(),
      deviceName: deviceLabel(),
      deviceType: 'browser',
    });
    const res = await fetch('/api/pairing/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body,
    });
    const data = await res.json();
    if (!res.ok || !data.sessionToken) {
      statusEl.textContent = pairingErrorText(data, res.status);
      statusEl.classList.add('error');
      return;
    }
    setToken(data.sessionToken);
    statusEl.textContent = 'Paired successfully.';
    statusEl.classList.add('success');
    showMainScreen();
  } catch (e) {
    statusEl.textContent = 'Network error: ' + e.message;
    statusEl.classList.add('error');
  }
}

function deviceLabel() {
  // The desktop's paired-device row should show something the operator
  // recognises — phone/tablet/browser model is good enough.
  const ua = navigator.userAgent || 'web';
  // Try to extract a brand+OS hint without dragging in a full parser.
  let label = 'Web';
  if (/iphone/i.test(ua)) label = 'iPhone';
  else if (/ipad/i.test(ua)) label = 'iPad';
  else if (/android/i.test(ua)) label = 'Android phone';
  else if (/macintosh/i.test(ua)) label = 'Mac browser';
  else if (/windows/i.test(ua)) label = 'Windows browser';
  return label + ' · Run-Watch';
}

// ---------------------------------------------------------------------------
// Main session: snapshot polling + SSE + frame refresh
// ---------------------------------------------------------------------------
let snapshotTimer = null;
let frameTimer = null;
let sse = null;
let lastFrameBlobUrl = null;
let frameBusy = false;

function bootSession() {
  setConnectionState('reconnecting');
  lastSnapshotAt = 0;
  sessionStartedAt = Date.now();
  linkFailure = null;
  lastKnownState = null;
  fetchSnapshot();
  openSSE();
  startPolling();
  startStaleWatchdog();
  refreshFrame();
}

function startPolling() {
  stopPolling();
  snapshotTimer = setInterval(fetchSnapshot, SNAPSHOT_INTERVAL_MS);
  frameTimer = setInterval(refreshFrame, FRAME_FALLBACK_MS);
}

function stopPolling() {
  if (snapshotTimer) { clearInterval(snapshotTimer); snapshotTimer = null; }
  if (frameTimer) { clearInterval(frameTimer); frameTimer = null; }
  stopStaleWatchdog();
}

async function fetchSnapshot() {
  try {
    const data = await apiJson('/api/run-watch/snapshot');
    noteLinkOk();
    setConnectionState('connected');
    applySnapshot(data);
  } catch (e) {
    if (e.kind === 'auth_required') return;
    // 'unreachable' already recorded the failure inside apiFetch; a
    // rate-limited or HTTP-error answer still proves the server is alive, so
    // only the staleness clock decides those.
    if (e.kind !== 'unreachable' && e.kind !== 'rate_limited') {
      setConnectionState('reconnecting');
    }
  } finally {
    renderLinkState();
  }
}

/// The state the snapshot actually reports.
///
/// `progress.state` is the executor's own `SequenceExecutionState`, an enum
/// with no member for a cancelled run: once a run is stopped it reads `idle`
/// while `sequencer.state` — the field the same snapshot carries straight from
/// `/api/sequencer/status` — reads `cancelled`. Reading the executor block
/// unconditionally told the operator the rig was idle 8% into a night that had
/// just been cancelled. So: the executor block wins while it is describing a
/// live run, and the moment it falls back to `idle` the sequencer status —
/// which is the one that knows how the run ended — is what gets rendered.
function reportedSequencerState(progress, sequencer) {
  const executing = String((progress && progress.state) || '').toLowerCase();
  const reported = String((sequencer && sequencer.state) || '').toLowerCase();
  if (executing && executing !== 'idle') return executing;
  if (reported) return reported;
  // An executor that says idle with nothing to contradict it is idle. A
  // snapshot that names no state at all is not idle, it is unknown.
  return executing || 'unknown';
}

/// Show what the run says about itself, and hide the surface when it says
/// nothing.
///
/// `sequencer.message` is the status line `/api/sequencer/status` carries;
/// `progress.message` is the executor's own line for the node it is on. They
/// often agree, and a message already spelled out in the header is not repeated
/// underneath it, so the surface holds what the operator has not already read.
function renderSequencerMessages(sequencer, progress, headline) {
  const slot = $('seq-message');
  if (!slot) return;
  const seen = new Set();
  const lines = [];
  for (const raw of [sequencer.message, progress.message]) {
    const text = typeof raw === 'string' ? raw.trim() : '';
    if (!text || text === headline || seen.has(text)) continue;
    seen.add(text);
    lines.push(text);
  }
  slot.textContent = lines.join('\n');
  slot.classList.toggle('hidden', lines.length === 0);
}

function applySnapshot(data) {
  if (!data) return;

  // Sequencer state badge
  const sequencer = data.sequencer || {};
  const progress = sequencer.progress || {};
  const state = reportedSequencerState(progress, sequencer);
  const unknown = state === 'unknown';
  const badge = $('state-badge');
  badge.textContent = state;
  badge.className = 'badge';
  if (state === 'running') badge.classList.add('badge-running');
  else if (state === 'paused') badge.classList.add('badge-paused');
  else if (state === 'recovering') badge.classList.add('badge-recovering');
  else if (state === 'error' || state === 'failed') badge.classList.add('badge-error');
  else if (unknown) badge.classList.add('badge-error');
  else badge.classList.add('badge-idle');
  lastKnownState = state;

  // state 'unknown' means the server's read failed. Never fall back to
  // 'Idle' there — the run may well still be going. With nothing named and a
  // state that is not idle either (a cancelled run keeps no current node),
  // the state word itself is the only true thing left to show.
  const headline =
    progress.currentTarget || sequencer.currentNodeName ||
    (unknown ? (progress.message || 'Status unavailable')
             : state.charAt(0).toUpperCase() + state.slice(1));
  $('seq-name').textContent = headline;

  // What the executor is saying about the run. Both fields are rendered for
  // every state, not just `unknown`: they are where a failing meridian flip, a
  // trigger's retry countdown and the current exposure's own line arrive, and
  // the desktop dashboard has always shown them. Dropping them here meant a run
  // stalled on a flip read as "RUNNING 33%" on the phone while the wire carried
  // the reason in two fields.
  renderSequencerMessages(sequencer, progress, headline);

  // Active target. `coordinatesKnown: false` is the headless case — the native
  // executor holds the sequence, so the host can name the target but cannot
  // place it on the sky. Show the name it does have and label the rest.
  const target = data.activeTarget;
  if (target) {
    const placed = target.coordinatesKnown !== false;
    $('target-state').textContent = target.unavailable
      ? (target.message || 'Target unavailable')
      : (!placed
          ? (target.message || 'Coordinates unavailable')
          : (progress.currentFilter ? ('filter: ' + progress.currentFilter) : ''));
    $('target-name').textContent = target.name || '--';
    $('target-coords').textContent = formatRaDec(target.raHours, target.decDegrees);
    $('target-alt').textContent = formatDeg(target.altitudeDeg);
    $('target-az').textContent = formatDeg(target.azimuthDeg);
    $('target-time-set').textContent = formatDuration(target.timeToSetSecs);
    $('target-time-transit').textContent = formatDuration(target.timeToTransitSecs);
  } else {
    $('target-name').textContent = '--';
    $('target-coords').textContent = '--';
    $('target-alt').textContent = '--';
    $('target-az').textContent = '--';
    $('target-time-set').textContent = '--';
    $('target-time-transit').textContent = '--';
    $('target-state').textContent = '';
  }

  // Progress
  const pctKnown = progress.progressPercent != null;
  const pct = pctKnown ? Math.round(progress.progressPercent * 100) : 0;
  $('progress-pct').textContent = pctKnown ? pct + '%' : '--';
  $('progress-bar').style.width = pct + '%';
  const ariaBar = $('progress-bar-aria');
  if (ariaBar) {
    // A progressbar with no aria-valuenow is announced as indeterminate,
    // which is the truth when the server did not report a percentage.
    // aria-valuenow="0" would announce "0 percent" — a number nobody sent.
    if (pctKnown) ariaBar.setAttribute('aria-valuenow', String(pct));
    else ariaBar.removeAttribute('aria-valuenow');
    // The GRAPHIC has to say the same thing the text and the announcement do.
    // With `progressPercent: null` the readouts all read "--" while the bar
    // painted `width: 0%` — pixel-identical to a fresh boot that genuinely has
    // done nothing, verified side by side on the same page. The unknown track
    // is hatched so the two states cannot be confused at a glance.
    ariaBar.classList.toggle('unknown', !pctKnown);
  }
  const framesKnown =
    progress.completedExposures != null && progress.totalExposures != null;
  $('progress-frames').textContent = framesKnown
    ? progress.completedExposures + ' / ' + progress.totalExposures
    : '--';
  // The denominator is null whenever the host does not know the run's planned
  // integration (every native/headless start — see _knownIntegrationDenominator
  // in run_watch_handlers.dart). "24s / 0s" claimed a total the run had already
  // passed; "24s / --" says what is actually known.
  $('progress-integration').textContent =
    formatDurationSecs(progress.completedIntegrationSecs) + ' / ' +
    formatDurationSecs(progress.totalIntegrationSecs);
  $('progress-node').textContent = progress.currentNodeName || sequencer.currentNodeName || '--';
  $('progress-filter').textContent = progress.currentFilter || '--';

  // Equipment
  const list = $('equipment-list');
  list.innerHTML = '';
  const devices = data.devices || [];
  if (devices.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = 'No connected devices';
    list.appendChild(empty);
  } else {
    devices.forEach(d => {
      const row = document.createElement('div');
      row.className = 'equipment-row';
      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = d.name;
      const type = document.createElement('span');
      type.className = 'type';
      type.textContent = d.type;
      row.appendChild(name);
      row.appendChild(type);
      list.appendChild(row);
    });
  }

  // Guiding. PHD2 reports 0.0 for every RMS while disconnected, which is a
  // placeholder, not a measurement — a disconnected guider has no error to
  // report at all. Only a connected guider's numbers are shown.
  const guiding = data.guiding || {};
  const guideConnected = guiding.connected === true;
  $('guide-state').textContent = guideConnected
    ? (guiding.state || 'connected')
    : 'disconnected';
  $('guide-ra').textContent = guideConnected ? formatRms(guiding.rmsRa) : '--';
  $('guide-dec').textContent = guideConnected ? formatRms(guiding.rmsDec) : '--';
  $('guide-total').textContent = guideConnected ? formatRms(guiding.rmsTotal) : '--';
  $('guide-snr').textContent = guideConnected && guiding.snr != null
    ? guiding.snr.toFixed(1)
    : '--';

  // Weather. `dataSource: 'unavailable'` means no weather hardware, no safety
  // monitor and no API source — nothing has looked at the sky. A run of green
  // "clear"/"safe" out of that is the fail-honest rule's exact prohibition, so
  // the sensor question is answered before the verdict is drawn.
  const weather = data.weather || {};
  const wbadge = $('weather-badge');
  const weatherSourced =
    weather.dataSource != null && weather.dataSource !== 'unavailable';
  wbadge.className = 'badge';
  if (!weatherSourced) {
    wbadge.textContent = 'no sensor';
    wbadge.classList.add('badge-idle');
  } else {
    wbadge.textContent = weather.alertLevel || 'unknown';
    if (weather.safeToImage) wbadge.classList.add('badge-running');
    else if (weather.alertLevel === 'warning') wbadge.classList.add('badge-paused');
    else if (weather.alertLevel === 'unsafe' || weather.alertLevel === 'critical') wbadge.classList.add('badge-error');
    else wbadge.classList.add('badge-idle');
  }
  $('weather-message').textContent = weatherSourced
    ? (weather.message || '--')
    : (weather.message || 'No weather source configured.');

  // Recovery banner
  const banner = $('recovery-banner');
  if (data.recovery && typeof data.recovery === 'object') {
    banner.classList.remove('hidden');
    const reason = data.recovery.reason || data.recovery.trigger || 'Sequence recovery in progress';
    banner.textContent = 'Recovery: ' + reason;
  } else {
    banner.classList.add('hidden');
    banner.textContent = '';
  }

  // Recent events
  if (data.recentEvents && data.recentEvents.length) {
    const feed = $('event-feed');
    feed.innerHTML = '';
    data.recentEvents.forEach(e => feed.appendChild(renderEventLi(e)));
  }
}

function renderEventLi(evt) {
  const li = document.createElement('li');
  const severity = (evt.severity || 'info').toLowerCase();
  li.className = 'sev-' + severity;
  const time = document.createElement('span');
  time.className = 'event-time';
  time.textContent = formatTimeMs(evt.timestamp);
  const body = document.createElement('div');
  body.className = 'event-body';
  const title = document.createElement('div');
  title.className = 'event-title';
  title.textContent = eventTitleText(evt);
  const detail = document.createElement('div');
  detail.className = 'event-detail';
  detail.textContent = formatEventDetail(evt);
  body.appendChild(title);
  if (detail.textContent) body.appendChild(detail);
  li.appendChild(time);
  li.appendChild(body);
  return li;
}

/// Whether this row is the host's "no case for this variant" bucket.
///
/// The host has one such bucket per event family — `UnknownSequencerEvent`,
/// `UnknownImagingEvent`, `UnknownSafetyEvent` and the rest — and they are the
/// only rows whose data map is not a set of read fields. They are matched by
/// shape rather than by a list of names so a family added to the host later
/// arrives here already covered.
function isUnreadEventBucket(type) {
  return /^Unknown\w*Event$/.test(type);
}

/// The name a feed row carries.
///
/// An event the host has no mapping for arrives in an unread bucket carrying
/// the union variant it stands for; that variant is what the operator can act
/// on, so it is what the row is called. Without it the row was titled
/// "UnknownSequencerEvent" over a line of Dart source.
function eventTitleText(evt) {
  const type = evt.eventType || evt.eventName || 'event';
  if (isUnreadEventBucket(type) && evt.data && typeof evt.data.variant === 'string') {
    const variant = evt.data.variant.trim();
    if (variant) return variant;
  }
  return type.replace(/_/g, ' ');
}

function formatEventDetail(evt) {
  if (!evt.data || typeof evt.data !== 'object') return '';
  // An unmapped event carries one written sentence and a variant name that is
  // already this row's title. Render the sentence and nothing else: the
  // generic field walk below prints every string it finds, and a bucket whose
  // host has not been taught to name its variants still puts the stringified
  // event object in that map — which is how Dart source text reached the
  // operator's phone in the first place. A row with nothing written for a
  // person says only what it is named, which is the truth.
  if (isUnreadEventBucket(evt.eventType || evt.eventName || '')) {
    return typeof evt.data.message === 'string' ? evt.data.message : '';
  }
  // Surface the first 2 non-empty string-ish fields so the row stays
  // compact on a phone. Numeric fields render as `key: value`.
  const parts = [];
  for (const k of Object.keys(evt.data)) {
    if (parts.length >= 2) break;
    const v = evt.data[k];
    if (v == null) continue;
    if (typeof v === 'string') parts.push(v);
    else if (typeof v === 'number') parts.push(k + ': ' + formatShortNum(v));
  }
  return parts.join(' · ');
}

function formatShortNum(n) {
  if (n === Math.floor(n) && Math.abs(n) < 1000) return String(n);
  return n.toFixed(2);
}

function formatTimeMs(ms) {
  if (!ms) return '--';
  const d = new Date(ms);
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  const ss = String(d.getSeconds()).padStart(2, '0');
  return hh + ':' + mm + ':' + ss;
}

function formatRaDec(raHours, decDeg) {
  if (raHours == null || decDeg == null) return '--';
  const raH = Math.floor(raHours);
  const raMfull = (raHours - raH) * 60;
  const raM = Math.floor(raMfull);
  const raS = ((raMfull - raM) * 60).toFixed(1);
  const sign = decDeg >= 0 ? '+' : '-';
  const decAbs = Math.abs(decDeg);
  const decD = Math.floor(decAbs);
  const decMfull = (decAbs - decD) * 60;
  const decM = Math.floor(decMfull);
  const decS = ((decMfull - decM) * 60).toFixed(0);
  return `${raH}h ${raM}m ${raS}s · ${sign}${decD}° ${decM}′ ${decS}″`;
}

function formatDeg(deg) {
  if (deg == null) return '--';
  return deg.toFixed(1) + '°';
}

function formatRms(v) {
  if (v == null) return '--';
  return v.toFixed(2) + '″';
}

function formatDuration(secs) {
  if (secs == null) return '--';
  if (secs <= 0) return 'now';
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = Math.floor(secs % 60);
  if (h > 0) return h + 'h ' + m + 'm';
  if (m > 0) return m + 'm ' + s + 's';
  return s + 's';
}

function formatDurationSecs(secs) {
  // null means the server could not read the value, which is not zero.
  if (secs == null) return '--';
  return formatDuration(secs) === 'now' ? '0s' : formatDuration(secs);
}

// ---------------------------------------------------------------------------
// SSE — live event stream
// ---------------------------------------------------------------------------
function openSSE() {
  closeSSE();
  // EventSource doesn't accept custom headers natively. We pass the
  // bearer token via the access_token query param; the server's
  // pairing flow already issued it to localStorage.
  const token = effectiveToken();
  if (!token) return;
  const url = '/api/run-watch/events?access_token=' + encodeURIComponent(token);
  try {
    sse = new EventSource(url, { withCredentials: false });
  } catch (e) {
    console.warn('SSE init failed', e);
    return;
  }

  sse.onopen = () => setConnectionState('connected');
  sse.onerror = () => {
    // EventSource retries forever and fires onerror on each attempt. Calling
    // it "reconnecting" is only honest while the snapshot poll still believes
    // the link is alive; once the link is known stale the dot must agree with
    // the banner rather than keep suggesting a recovery is under way.
    setConnectionState(isLinkStale() ? 'disconnected' : 'reconnecting');
  };
  sse.onmessage = (evt) => handleSseMessage(evt);

  // Frame-triggering events — when one arrives, refresh the thumbnail
  // immediately rather than waiting for the 10s fallback.
  ['FrameAccepted', 'FrameRejected', 'ExposureFinished',
    'ExposureCompleted', 'ImageSaved'].forEach(name => {
    sse.addEventListener(name, () => refreshFrame());
  });

  // Sequencer state transitions — fetch a fresh snapshot so the
  // progress bar / current-target panel updates without waiting for
  // the 15s baseline poll.
  ['SequencePaused', 'SequenceResumed', 'SequenceStarted',
    'SequenceFinished', 'SequenceStopped', 'NodeStarted',
    'NodeCompleted', 'SchedulerDecision'].forEach(name => {
    sse.addEventListener(name, () => fetchSnapshot());
  });
}

function closeSSE() {
  if (sse) {
    try { sse.close(); } catch { /* ignore */ }
    sse = null;
  }
}

function handleSseMessage(evt) {
  let payload;
  try { payload = JSON.parse(evt.data); }
  catch { return; }
  // Append to event feed. Cap the visible list at 5 rows.
  const feed = $('event-feed');
  if (!feed) return;
  // Remove placeholder if present.
  const placeholder = feed.querySelector('.empty');
  if (placeholder) placeholder.remove();
  feed.insertBefore(renderEventLi(payload), feed.firstChild);
  while (feed.children.length > 5) feed.removeChild(feed.lastChild);

  // Critical events — surface as a toast (web Push API is opt-in via
  // settings sheet and lives in registerPushIfEnabled() below).
  if ((payload.severity || '').toLowerCase() === 'critical') {
    const title = (payload.eventType || payload.eventName)
      ? eventTitleText(payload)
      : 'Critical event';
    toast(title, 'error');
    // Also browser-level notification if permission granted.
    maybeShowNotification(title, formatEventDetail(payload));
  }
}

function maybeShowNotification(title, body) {
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'granted') return;
  try {
    if (navigator.serviceWorker && navigator.serviceWorker.controller) {
      // Prefer the service-worker route so notifications survive when
      // the tab is backgrounded — `Notification` constructor is
      // deprecated on mobile Safari for that reason.
      navigator.serviceWorker.getRegistration().then(reg => {
        if (reg) reg.showNotification(title, { body, icon: '/run-watch/icons/icon-192.svg' });
      });
    } else {
      new Notification(title, { body, icon: '/run-watch/icons/icon-192.svg' });
    }
  } catch (e) { console.warn('Notification failed', e); }
}

// ---------------------------------------------------------------------------
// Frame thumbnail
// ---------------------------------------------------------------------------
function setFrameLoading(loading) {
  const wrap = $('frame-wrap');
  const badge = $('frame-loading-badge');
  if (wrap) wrap.classList.toggle('is-loading', !!loading);
  if (badge) badge.hidden = !loading;
}

async function refreshFrame() {
  if (frameBusy) return;
  frameBusy = true;
  setFrameLoading(true);
  try {
    const res = await apiFetch('/api/run-watch/frame-thumbnail?maxWidth=1024&quality=75');
    if (!res.ok) {
      // 404 = no image yet; just leave the placeholder. Anything else
      // (5xx, etc.) is a transient — silent retry on next tick.
      return;
    }
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const img = $('frame-img');
    const placeholder = $('frame-placeholder');
    img.src = url;
    img.classList.remove('hidden');
    placeholder.classList.add('hidden');
    if (lastFrameBlobUrl) URL.revokeObjectURL(lastFrameBlobUrl);
    lastFrameBlobUrl = url;

    // Meta (timestamp + HFR) from custom response headers.
    const ts = res.headers.get('x-frame-timestamp');
    const hfr = res.headers.get('x-frame-hfr');
    const meta = [];
    if (ts) meta.push(formatTimeMs(Date.parse(ts) || Date.now()));
    if (hfr) meta.push('HFR ' + Number(hfr).toFixed(2));
    $('frame-meta').textContent = meta.join(' · ');
  } catch (e) {
    if (e.kind === 'auth_required') return;
    // A rate-limited or unreachable server is already stated by the link
    // banner; the placeholder simply remains.
    if (e.kind === 'rate_limited' || e.kind === 'unreachable') {
      renderLinkState();
    }
  } finally {
    setFrameLoading(false);
    frameBusy = false;
  }
}

// ---------------------------------------------------------------------------
// Playback controls
// ---------------------------------------------------------------------------
/// POST a control and report what the server actually answered.
///
/// A 200 is not consent. `POST /api/sequencer/stop` answers 200 with
/// `wasRunning: false` and "No sequence was running; nothing to stop." when
/// there is nothing to stop, and this surface used to reply "Stop sent" to
/// that — a green toast for a command the server declined. The body carries
/// the verdict; read it.
async function sequencerAction(path, label, body) {
  try {
    const opts = { method: 'POST' };
    if (body != null) {
      opts.headers = { 'Content-Type': 'application/json' };
      opts.body = JSON.stringify(body);
    }
    const res = await apiFetch(path, opts);
    const payload = await apiJsonOrNull(res);
    if (!res.ok) {
      const msg = (payload && (payload.message || payload.error)) || res.statusText;
      toast(`${label} failed: ${msg}`, 'error');
      return;
    }
    const refused = payload != null &&
      (payload.wasRunning === false || payload.accepted === false);
    if (refused) {
      toast(
        (payload.message || `${label} had no effect`),
        'warning',
      );
    } else {
      toast(`${label} accepted`, 'success');
    }
    fetchSnapshot();
  } catch (e) {
    if (e.kind === 'auth_required') return;
    if (e.kind === 'rate_limited') {
      toast(
        `${label} not sent — server is rate-limiting this device. ` +
        `Try again in ${e.detail.retryAfterSecs}s.`,
        'warning',
      );
      renderLinkState();
      return;
    }
    if (e.kind === 'unreachable') {
      toast(`${label} not sent — cannot reach the server`, 'error');
      renderLinkState();
      return;
    }
    toast(`${label} failed: ${e.message}`, 'error');
  }
}

// ---------------------------------------------------------------------------
// Settings sheet (wake lock, push, logout)
//
// Both toggles ride on APIs the browser only exposes to a SECURE context, and
// the address a phone actually uses to reach an observatory rig — the plain
// http:// LAN address of the desktop — is not one. Measured on that origin:
// `'wakeLock' in navigator` is false, the service worker never registers, and
// Notification.permission is pinned at "denied" before anything is asked. The
// page's answer to all of that used to be a checkbox that stayed ticked: the
// wake-lock branch had no `else`, and the push branch only acted on a
// permission of "default", so at "denied" it returned having done nothing.
// The feature worked in loopback testing and was dead in deployment, which is
// exactly why it survived.
//
// The support verdicts below are FEATURE TESTS — what this origin can actually
// do — never a guess from the user agent.
// ---------------------------------------------------------------------------

/// Whether this origin can hold a screen wake lock, and why not when it
/// cannot. The reason is a sentence for the operator, not a diagnostic.
function wakeLockSupport() {
  if ('wakeLock' in navigator) return { available: true, reason: null };
  if (!window.isSecureContext) {
    return {
      available: false,
      reason: 'Your browser only allows this over HTTPS. This page is served '
        + 'over plain HTTP, so the screen will sleep as usual.',
    };
  }
  return {
    available: false,
    reason: 'This browser has no screen wake-lock support.',
  };
}

/// Whether this origin can raise a notification, and why not when it cannot.
///
/// A blocked permission is reported separately from a missing API: on an
/// insecure origin the permission is already "denied" and cannot be asked for,
/// while on a secure one the operator can still change their mind.
function notificationSupport() {
  if (!('Notification' in window)) {
    return {
      available: false,
      reason: 'This browser has no notification support.',
    };
  }
  if (!window.isSecureContext) {
    return {
      available: false,
      reason: 'Your browser only allows notifications over HTTPS. This page is '
        + 'served over plain HTTP, so nothing can be delivered — watch this '
        + 'screen instead.',
    };
  }
  if (window.Notification.permission === 'denied') {
    return {
      available: false,
      reason: 'Notifications are blocked for this site in your browser '
        + 'settings.',
    };
  }
  return { available: true, reason: null };
}

/// Paint one toggle from its support verdict: an unavailable capability is
/// disabled, forced off, and told plainly why. Any stored opt-in for it is
/// cleared, so nothing on this device goes on claiming an ability it lacks.
function applyCapabilitySupport(inputId, rowId, noteId, support, opts, optKey) {
  const input = $(inputId);
  const note = $(noteId);
  const label = $(rowId);
  if (!input) return;
  if (support.available) {
    input.disabled = false;
    if (label) label.classList.remove('unavailable');
    if (note) { note.classList.add('hidden'); note.textContent = ''; }
    return;
  }
  input.disabled = true;
  input.checked = false;
  if (label) label.classList.add('unavailable');
  if (note) { note.textContent = support.reason; note.classList.remove('hidden'); }
  if (opts[optKey]) {
    opts[optKey] = false;
    saveOpts(opts);
  }
}

/// Bring the sheet's two toggles in line with what this origin can do. Called
/// at boot and every time the sheet opens, because a permission can be revoked
/// from browser settings between openings.
function refreshCapabilityToggles() {
  const opts = loadOpts();
  applyCapabilitySupport(
    'opt-wake-lock', 'opt-wake-lock-row', 'opt-wake-lock-note',
    wakeLockSupport(), opts, 'wakeLock');
  applyCapabilitySupport(
    'opt-push', 'opt-push-row', 'opt-push-note',
    notificationSupport(), opts, 'push');
}

let wakeLock = null;
async function applyWakeLockOption() {
  const opts = loadOpts();
  const support = wakeLockSupport();
  if (!support.available) {
    // Refuse out loud. Silence here is what let the toggle stay ticked over a
    // screen that went on sleeping.
    if (opts.wakeLock) {
      opts.wakeLock = false;
      saveOpts(opts);
      toast('Keep screen awake is unavailable — ' + support.reason, 'warning');
    }
    refreshCapabilityToggles();
    return;
  }
  if (opts.wakeLock) {
    try {
      wakeLock = await navigator.wakeLock.request('screen');
      wakeLock.addEventListener('release', () => { wakeLock = null; });
    } catch (e) {
      // The API is here and the request was still refused — a background tab,
      // a battery-saver policy, the operator's own denial. Report the
      // browser's own reason and untick what did not take.
      opts.wakeLock = false;
      saveOpts(opts);
      $('opt-wake-lock').checked = false;
      toast('Could not keep the screen awake: ' +
        (e && e.message ? e.message : String(e)), 'warning');
    }
  } else if (wakeLock) {
    try { await wakeLock.release(); } catch { /* ignore */ }
    wakeLock = null;
  }
}

async function applyPushOption() {
  const opts = loadOpts();
  if (!opts.push) return;
  const support = notificationSupport();
  if (!support.available) {
    opts.push = false;
    saveOpts(opts);
    toast('Notifications are unavailable — ' + support.reason, 'warning');
    refreshCapabilityToggles();
    return;
  }
  if (window.Notification.permission === 'default') {
    const perm = await window.Notification.requestPermission();
    if (perm !== 'granted') {
      opts.push = false;
      saveOpts(opts);
      $('opt-push').checked = false;
      toast('Notifications stay off — permission was not granted.', 'warning');
      refreshCapabilityToggles();
    }
  }
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------
window.addEventListener('DOMContentLoaded', () => {
  // Pairing screen wiring
  $('btn-pair').addEventListener('click', () => startPairing($('pair-code').value));
  $('pair-code').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') startPairing($('pair-code').value);
  });
  $('btn-manual-token').addEventListener('click', () => {
    const t = $('manual-token').value.trim();
    if (!t) return;
    setToken(t);
    showMainScreen();
  });

  // Playback wiring
  $('btn-pause').addEventListener('click', () =>
    sequencerAction('/api/sequencer/pause', 'Pause'));
  $('btn-resume').addEventListener('click', () =>
    sequencerAction('/api/sequencer/resume', 'Resume'));
  $('btn-skip').addEventListener('click', () =>
    sequencerAction('/api/sequencer/skip', 'Skip'));
  $('btn-stop').addEventListener('click', () => {
    if (confirm('Stop the running sequence?')) {
      sequencerAction('/api/sequencer/stop', 'Stop');
    }
  });
  const btnReset = $('btn-reset');
  if (btnReset) {
    btnReset.addEventListener('click', () => {
      if (confirm('Reset the sequencer state?')) {
        sequencerAction('/api/sequencer/reset', 'Reset');
      }
    });
  }
  const btnDither = $('btn-guide-dither');
  if (btnDither) {
    btnDither.addEventListener('click', () =>
      sequencerAction('/api/phd2/dither', 'Dither', { amount: 5.0 }));
  }
  const btnCpResume = $('btn-checkpoint-resume');
  if (btnCpResume) {
    btnCpResume.addEventListener('click', () =>
      sequencerAction('/api/sequencer/checkpoint/resume', 'Resume checkpoint'));
  }
  const btnCpDiscard = $('btn-checkpoint-discard');
  if (btnCpDiscard) {
    btnCpDiscard.addEventListener('click', () => {
      if (confirm('Discard the saved checkpoint?')) {
        sequencerAction('/api/sequencer/checkpoint/discard', 'Discard checkpoint');
      }
    });
  }

  // Settings sheet
  $('btn-settings').addEventListener('click', () => {
    const opts = loadOpts();
    $('opt-wake-lock').checked = !!opts.wakeLock;
    $('opt-push').checked = !!opts.push;
    // Re-tested on every opening, not cached at boot: a notification
    // permission can be granted or revoked from browser settings while this
    // page stays open.
    refreshCapabilityToggles();
    $('settings-modal').classList.remove('hidden');
  });
  $('btn-settings-close').addEventListener('click', () => {
    $('settings-modal').classList.add('hidden');
  });
  $('opt-wake-lock').addEventListener('change', (e) => {
    const opts = loadOpts();
    opts.wakeLock = e.target.checked;
    saveOpts(opts);
    applyWakeLockOption();
  });
  $('opt-push').addEventListener('change', (e) => {
    const opts = loadOpts();
    opts.push = e.target.checked;
    saveOpts(opts);
    applyPushOption();
  });
  $('btn-logout').addEventListener('click', () => {
    setToken(null);
    // Named too, so the same screen never appears without an account of how
    // this device got back to it.
    showPairScreen(
      'Signed out on this device. Pair again with a code from the desktop\'s '
      + 'Remote Access screen when you want it back.',
      'info',
    );
  });

  // Service-worker registration. Failures are non-fatal — the app
  // still works without the offline shell.
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/run-watch/sw.js', { scope: '/run-watch/' })
      .catch(e => console.warn('SW register failed', e));
  }

  // Settle what this origin can do before anything reads the stored opt-ins,
  // so a device that was paired over HTTPS and is now on the LAN address does
  // not carry a tick for a capability it has lost.
  refreshCapabilityToggles();

  // Decide which screen to show.
  if (effectiveToken()) {
    showMainScreen();
    applyWakeLockOption();
  } else {
    showPairScreen();
  }

  // Re-apply wake-lock when the tab comes back to the foreground —
  // browsers drop the lock when the page is hidden.
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && loadOpts().wakeLock) {
      applyWakeLockOption();
    }
  });
});
