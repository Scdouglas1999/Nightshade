// Run-Watch honesty contract.
//
// This surface is what an operator looks at from bed. Everything it shows is a
// cache of the last snapshot the server answered, so the questions that matter
// are: does it admit when that cache has gone stale, does it invent numbers the
// server never sent, and does it report the server's own refusals.
//
// The tests EXECUTE the page's render path against a DOM shim rather than
// grepping its source: what the operator sees is the contract.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const { makeDocument } = require('./dom_shim');

const RUN_WATCH = path.join(__dirname, '..', '..', 'web_run_watch');
const SOURCE = fs.readFileSync(path.join(RUN_WATCH, 'js', 'run-watch.js'), 'utf8');

const IDS = [
  'state-badge', 'seq-name', 'connection-dot', 'link-banner', 'recovery-banner',
  'target-state', 'target-name', 'target-coords', 'target-alt', 'target-az',
  'target-time-set', 'target-time-transit',
  'progress-pct', 'progress-bar', 'progress-bar-aria', 'progress-frames',
  'progress-integration', 'progress-node', 'progress-filter',
  'equipment-list', 'guide-state', 'guide-ra', 'guide-dec', 'guide-total',
  'guide-snr', 'weather-badge', 'weather-message', 'event-feed', 'toast-region',
];

/**
 * Load run-watch.js into a sandbox and hand back the internals under test.
 * The file is a plain script with no exports, so the accessors are appended
 * to its own scope.
 */
function loadRunWatch(overrides) {
  const doc = makeDocument(IDS);
  const timers = [];
  const sandbox = {
    window: { addEventListener() {}, crypto: undefined },
    document: doc,
    localStorage: {
      _m: new Map(),
      getItem(k) { return this._m.has(k) ? this._m.get(k) : null; },
      setItem(k, v) { this._m.set(k, String(v)); },
      removeItem(k) { this._m.delete(k); },
    },
    navigator: { userAgent: 'node-test' },
    fetchImpl: (overrides && overrides.fetch) || (() => {
      throw new Error('no fetch stub installed');
    }),
    EventSource: function () { this.close = () => {}; },
    setInterval: (fn, ms) => { timers.push({ fn, ms }); return timers.length; },
    clearInterval: () => {},
    setTimeout: () => 0,
    Headers: globalThis.Headers,
    console: { warn() {}, log() {} },
  };

  const suffix = `
;return {
  applySnapshot,
  renderLinkState,
  isLinkStale,
  noteLinkOk,
  noteLinkFailure,
  retryAfterSecsFrom,
  apiFetch,
  sequencerAction,
  formatDurationSecs,
  peek: () => ({ lastSnapshotAt, linkFailure, rateLimitedUntil, lastKnownState }),
  poke: (o) => {
    if (o.lastSnapshotAt !== undefined) lastSnapshotAt = o.lastSnapshotAt;
    if (o.sessionStartedAt !== undefined) sessionStartedAt = o.sessionStartedAt;
    if (o.linkFailure !== undefined) linkFailure = o.linkFailure;
    if (o.rateLimitedUntil !== undefined) rateLimitedUntil = o.rateLimitedUntil;
  },
};`;

  // eslint-disable-next-line no-new-func
  const factory = new Function(
    'window', 'document', 'localStorage', 'navigator', 'fetch', 'EventSource',
    'setInterval', 'clearInterval', 'setTimeout', 'Headers', 'console',
    SOURCE + suffix,
  );
  const api = factory(
    sandbox.window, sandbox.document, sandbox.localStorage, sandbox.navigator,
    sandbox.fetchImpl, sandbox.EventSource, sandbox.setInterval,
    sandbox.clearInterval, sandbox.setTimeout, sandbox.Headers, sandbox.console,
  );
  return { doc, api, timers };
}

/** A snapshot shaped like a live headless run of the D1 sim sequence. */
function runningSnapshot(extra) {
  return Object.assign({
    serverTime: new Date().toISOString(),
    sequencer: {
      state: 'running',
      currentNodeName: 'Exposure L',
      progress: {
        state: 'running',
        currentTarget: 'D1 Simulated Field',
        currentNodeName: 'Exposure L',
        currentFilter: 'L',
        totalExposures: 12,
        completedExposures: 1,
        completedIntegrationSecs: 2.0,
        totalIntegrationSecs: null,
        progressPercent: 1 / 12,
      },
    },
    activeTarget: {
      coordinatesKnown: false,
      message: 'Coordinates unavailable: the native executor holds this run',
      id: null,
      name: 'D1 Simulated Field',
      raHours: null,
      decDegrees: null,
      altitudeDeg: null,
      azimuthDeg: null,
      timeToSetSecs: null,
      timeToTransitSecs: null,
    },
    guiding: {
      state: 'Disconnected',
      connected: false,
      rmsRa: 0.0,
      rmsDec: 0.0,
      rmsTotal: 0.0,
      snr: 0.0,
    },
    weather: {
      safeToImage: true,
      alertLevel: 'clear',
      message: 'Weather safety is off — conditions are not being checked',
      dataSource: 'unavailable',
      lastEvaluation: null,
    },
    devices: [],
    recentEvents: [],
    recovery: null,
  }, extra || {});
}

// D4-02. A killed backend used to leave a green `badge-running` on screen
// indefinitely — measured at 35 s after SIGKILL, two poll intervals, with the
// frame counter frozen at "1 / 12" and no banner anywhere on the page.
test('a lost server flips the state badge and raises a banner', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(runningSnapshot());
  assert.equal(doc.getElementById('state-badge').textContent, 'running');
  assert.ok(doc.getElementById('state-badge').classList.contains('badge-running'));
  api.renderLinkState();
  assert.ok(doc.getElementById('link-banner').classList.contains('hidden'),
    'a healthy link raises no banner');

  // The server goes away: the next poll's fetch rejects.
  api.noteLinkFailure('unreachable', 'connect ECONNREFUSED');
  api.renderLinkState();

  const badge = doc.getElementById('state-badge');
  assert.equal(badge.textContent, 'unknown',
    'the badge must stop asserting "running" for a server that is gone');
  assert.ok(badge.classList.contains('badge-error'));
  assert.ok(!badge.classList.contains('badge-running'));

  const banner = doc.getElementById('link-banner');
  assert.ok(!banner.classList.contains('hidden'), 'the banner must be visible');
  assert.match(banner.textContent, /Cannot reach the observatory server/);
  assert.match(banner.textContent, /may be wrong/);

  const dot = doc.getElementById('connection-dot');
  assert.ok(dot.classList.contains('conn-disconnected'));
  assert.ok(!dot.classList.contains('conn-reconnecting'),
    'the dot must not keep implying a recovery is under way');

  // The SSE retry loop fires onerror on every attempt; it must not talk the
  // dot back into "reconnecting" behind the banner's back.
  const onerror = SOURCE.match(/sse\.onerror = \(\) => \{[\s\S]*?\n  \};/);
  assert.ok(onerror, 'the SSE error handler must exist');
  assert.match(onerror[0], /isLinkStale\(\) \? 'disconnected' : 'reconnecting'/);
});

// The silent case: the socket stays open but no snapshot completes. One poll
// interval plus slack is the deadline.
test('a missed poll interval counts as stale even with no error', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(runningSnapshot());
  assert.equal(api.isLinkStale(), false);

  // 21 s ago — past SNAPSHOT_INTERVAL_MS (15 s) + 5 s slack.
  api.poke({ lastSnapshotAt: Date.now() - 21000 });
  assert.equal(api.isLinkStale(), true);
  api.renderLinkState();
  assert.equal(doc.getElementById('state-badge').textContent, 'unknown');
  assert.match(doc.getElementById('link-banner').textContent,
    /No answer from the observatory server/);
  assert.match(doc.getElementById('link-banner').textContent,
    /state was "running"/);
});

// D4-06. `totalIntegrationSecs` is null whenever the host does not know the
// run's planned integration, which on a headless appliance is always. The old
// render turned that into "0s" and printed "24s / 0s".
test('an unknown integration denominator renders as unknown, not zero', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(runningSnapshot());
  assert.equal(doc.getElementById('progress-integration').textContent, '2s / --');
  assert.equal(doc.getElementById('progress-frames').textContent, '1 / 12');

  const snap = runningSnapshot();
  snap.sequencer.progress.totalIntegrationSecs = 24.0;
  api.applySnapshot(snap);
  assert.equal(doc.getElementById('progress-integration').textContent, '2s / 24s');
});

// D4-07. The card used to read `--` in every row during a live run whose
// target the same snapshot named.
test('a target with no coordinates still shows its name', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(runningSnapshot());
  assert.equal(doc.getElementById('target-name').textContent, 'D1 Simulated Field');
  assert.equal(doc.getElementById('target-coords').textContent, '--');
  assert.equal(doc.getElementById('target-alt').textContent, '--');
  assert.match(doc.getElementById('target-state').textContent,
    /Coordinates unavailable/);
});

// D4-08. aria-valuenow="0" announces "0 percent" — a figure the server never
// sent. An absent attribute announces an indeterminate bar, which is the truth.
test('an unknown progress percentage carries no aria-valuenow', () => {
  const { doc, api } = loadRunWatch();
  const snap = runningSnapshot();
  snap.sequencer.progress.progressPercent = null;
  api.applySnapshot(snap);
  const bar = doc.getElementById('progress-bar-aria');
  assert.equal(bar.getAttribute('aria-valuenow'), null);
  assert.equal(doc.getElementById('progress-pct').textContent, '--');

  api.applySnapshot(runningSnapshot());
  assert.equal(bar.getAttribute('aria-valuenow'), '8');
});

test('the shipped markup declares no aria-valuenow before any snapshot', () => {
  const html = fs.readFileSync(path.join(RUN_WATCH, 'index.html'), 'utf8');
  const bar = html.match(/<div class="bar"[^>]*id="progress-bar-aria"[^>]*>/);
  assert.ok(bar, 'the progressbar element must exist');
  assert.match(bar[0], /role="progressbar"/);
  assert.doesNotMatch(bar[0], /aria-valuenow/,
    'a bar that has heard nothing must not announce a value');
});

// D4-05, phone side. PHD2 answers 0.0 for every RMS while disconnected.
test('a disconnected guider reports no RMS at all', () => {
  const { doc, api } = loadRunWatch();
  api.applySnapshot(runningSnapshot());
  assert.equal(doc.getElementById('guide-state').textContent, 'disconnected');
  assert.equal(doc.getElementById('guide-ra').textContent, '--');
  assert.equal(doc.getElementById('guide-dec').textContent, '--');
  assert.equal(doc.getElementById('guide-total').textContent, '--');
  assert.equal(doc.getElementById('guide-snr').textContent, '--');

  const snap = runningSnapshot();
  snap.guiding = {
    state: 'Guiding', connected: true,
    rmsRa: 0.41, rmsDec: 0.38, rmsTotal: 0.56, snr: 22.5,
  };
  api.applySnapshot(snap);
  assert.equal(doc.getElementById('guide-ra').textContent, '0.41″');
  assert.equal(doc.getElementById('guide-total').textContent, '0.56″');
  assert.equal(doc.getElementById('guide-snr').textContent, '22.5');
});

// D4-10. `dataSource: 'unavailable'` means nothing has looked at the sky. The
// server still fills in safeToImage/alertLevel, and the badge used to render
// them as a green "clear".
test('no weather source never renders an affirmative verdict', () => {
  const { doc, api } = loadRunWatch();
  api.applySnapshot(runningSnapshot());
  const badge = doc.getElementById('weather-badge');
  assert.equal(badge.textContent, 'no sensor');
  assert.ok(!badge.classList.contains('badge-running'),
    'an unmeasured sky must not read green');
  assert.match(doc.getElementById('weather-message').textContent,
    /not being checked|No weather source configured/);

  const snap = runningSnapshot();
  snap.weather = {
    safeToImage: true, alertLevel: 'clear', message: 'Clear and dry',
    dataSource: 'hardware', lastEvaluation: null,
  };
  api.applySnapshot(snap);
  assert.equal(badge.textContent, 'clear');
  assert.ok(badge.classList.contains('badge-running'),
    'a real sensor reporting clear may read green');
});

// D4-09. `POST /api/sequencer/stop` answers 200 with wasRunning:false and
// "No sequence was running; nothing to stop." when there is nothing to stop.
test('a control reports the server refusal instead of a success toast', async () => {
  const answers = {
    body: {
      commandId: 'x', status: 'stopped', preserveCheckpoint: true,
      wasRunning: false,
      message: 'No sequence was running; nothing to stop.',
    },
  };
  const { doc, api } = loadRunWatch({
    fetch: async () => ({
      ok: true, status: 200, statusText: 'OK',
      headers: new Headers(),
      json: async () => answers.body,
    }),
  });
  await api.sequencerAction('/api/sequencer/stop', 'Stop');
  const toasts = doc.getElementById('toast-region').children.map((c) => ({
    text: c.textContent, cls: c.className,
  }));
  assert.equal(toasts.length, 1);
  assert.equal(toasts[0].text, 'No sequence was running; nothing to stop.');
  assert.ok(toasts[0].cls.includes('toast-warning'),
    'a refusal must not be styled as a success');

  answers.body = { commandId: 'y', status: 'stopped', wasRunning: true };
  await api.sequencerAction('/api/sequencer/stop', 'Stop');
  const after = doc.getElementById('toast-region').children;
  assert.equal(after[after.length - 1].textContent, 'Stop accepted');
});

// D4-03. The limiter's JSON body must never be what the operator reads, and
// the page must honour the server's own retry window rather than re-firing.
test('a 429 is honoured as a retry window, not printed', async () => {
  const body = {
    code: 'rate_limited', error: 'Rate limit exceeded',
    message: 'Token token-6e609b0e exceeded read bucket',
    bucket: 'read', maxRequests: 60, retryAfterSecs: 3, retryAfterSeconds: 3,
    requestId: 'abc',
  };
  let calls = 0;
  const { doc, api } = loadRunWatch({
    fetch: async () => {
      calls += 1;
      return {
        ok: false, status: 429, statusText: 'Too Many Requests',
        headers: new Headers({ 'retry-after': '3' }),
        clone() { return this; },
        json: async () => body,
        text: async () => JSON.stringify(body),
      };
    },
  });

  await assert.rejects(
    () => api.apiFetch('/api/run-watch/snapshot'),
    (e) => e.kind === 'rate_limited' && e.detail.retryAfterSecs === 3,
  );
  assert.equal(calls, 1);

  // Inside the window the gate refuses locally: no second request is sent.
  await assert.rejects(
    () => api.apiFetch('/api/run-watch/snapshot'),
    (e) => e.kind === 'rate_limited',
  );
  assert.equal(calls, 1, 'the page must not re-fire inside the retry window');

  api.noteLinkOk();
  api.renderLinkState();
  const banner = doc.getElementById('link-banner');
  assert.ok(!banner.classList.contains('hidden'));
  assert.match(banner.textContent, /rate-limiting this device/);
  assert.doesNotMatch(banner.textContent, /rate_limited|maxRequests|requestId/,
    'the limiter body must never reach the screen');
});

// A page that has just opened is loading, not out of contact — but only for
// one poll interval, and only while nothing has actually failed.
test('a page still waiting for its first snapshot is not yet stale', () => {
  const { doc, api } = loadRunWatch();
  api.poke({ lastSnapshotAt: 0, sessionStartedAt: Date.now(), linkFailure: null });
  assert.equal(api.isLinkStale(), false);
  api.renderLinkState();
  assert.ok(doc.getElementById('link-banner').classList.contains('hidden'));

  api.poke({ sessionStartedAt: Date.now() - 21000 });
  assert.equal(api.isLinkStale(), true);
  api.renderLinkState();
  assert.match(doc.getElementById('link-banner').textContent,
    /No update has arrived since this page opened/);
});

test('a first fetch that fails outright is stale immediately', () => {
  const { api } = loadRunWatch();
  api.poke({ lastSnapshotAt: 0, sessionStartedAt: Date.now() });
  api.noteLinkFailure('unreachable', 'connect ECONNREFUSED');
  assert.equal(api.isLinkStale(), true,
    'a refused connection needs no grace period');
});

test('retryAfterSecsFrom prefers the body, then the header, then one second',
  async () => {
    const { api } = loadRunWatch();
    const res = (json, header) => ({
      clone() {
        return { json: async () => { if (json == null) throw new Error('no body'); return json; } };
      },
      headers: new Headers(header ? { 'retry-after': String(header) } : {}),
    });
    assert.equal(await api.retryAfterSecsFrom(res({ retryAfterSecs: 7 }, 2)), 7);
    assert.equal(await api.retryAfterSecsFrom(res({ retryAfterSeconds: 4 })), 4);
    assert.equal(await api.retryAfterSecsFrom(res(null, 9)), 9);
    assert.equal(await api.retryAfterSecsFrom(res(null)), 1);
    // A hostile window cannot park the page for hours.
    assert.equal(await api.retryAfterSecsFrom(res({ retryAfterSecs: 100000 })), 300);
  });

// ---------------------------------------------------------------------------
// D4W-3 — a cancelled night is not an idle rig
// ---------------------------------------------------------------------------

/**
 * What GET /api/run-watch/snapshot actually answers six seconds after
 * POST /api/sequencer/stop, measured against the release bundle: the sequencer
 * status says `cancelled` while the executor's own progress block has already
 * fallen back to `idle` — `SequenceExecutionState` has no cancelled member.
 */
function cancelledSnapshot(progressExtra) {
  return runningSnapshot({
    sequencer: {
      state: 'cancelled',
      currentNodeName: null,
      progress: Object.assign({
        state: 'idle',
        currentTarget: 'D1 Simulated Field',
        currentNodeName: null,
        totalExposures: 12,
        completedExposures: 1,
        progressPercent: 0.083,
      }, progressExtra || {}),
    },
  });
}

test('a cancelled run is not reported as an idle rig', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(cancelledSnapshot());
  assert.equal(doc.getElementById('state-badge').textContent, 'cancelled',
    'the badge must read the field the snapshot actually carries');
  assert.equal(doc.getElementById('seq-name').textContent, 'D1 Simulated Field');
});

test('a cancelled run with nothing left to name still says cancelled', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(cancelledSnapshot({ currentTarget: null }));
  assert.equal(doc.getElementById('state-badge').textContent, 'cancelled');
  assert.equal(doc.getElementById('seq-name').textContent, 'Cancelled',
    'an unnamed cancelled run must not read "Idle"');
});

test('a live run still reports the executor state, not the wire state', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  // The executor is mid-run and the sequencer status lags a state behind: the
  // block describing the live run wins.
  api.applySnapshot(runningSnapshot({
    sequencer: {
      state: 'idle',
      currentNodeName: 'Exposure L',
      progress: { state: 'running', currentTarget: 'D1 Simulated Field' },
    },
  }));
  assert.equal(doc.getElementById('state-badge').textContent, 'running');
});

test('a genuinely idle rig still reads idle', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(runningSnapshot({
    sequencer: { state: 'idle', currentNodeName: null, progress: { state: 'idle' } },
  }));
  assert.equal(doc.getElementById('state-badge').textContent, 'idle');
  assert.equal(doc.getElementById('seq-name').textContent, 'Idle');
});

test('a snapshot that names no state at all is unknown, never idle', () => {
  const { doc, api } = loadRunWatch();
  api.noteLinkOk();
  api.applySnapshot(runningSnapshot({ sequencer: { progress: {} } }));
  assert.equal(doc.getElementById('state-badge').textContent, 'unknown');
  assert.ok(doc.getElementById('state-badge').className.includes('badge-error'));
});

// ---------------------------------------------------------------------------
// D4W-5 — before the first snapshot, the page is connecting
// ---------------------------------------------------------------------------

test('the shipped markup asserts no rig state before the first snapshot', () => {
  const html = fs.readFileSync(path.join(RUN_WATCH, 'index.html'), 'utf8');
  const badge = html.match(/<span id="state-badge"[^>]*>([^<]*)</);
  assert.ok(badge, 'the state badge must exist in the markup');
  assert.equal(badge[1].trim(), 'connecting',
    'a page that has heard nothing must not claim the rig is idle');
  const name = html.match(/<span id="seq-name"[^>]*>([^<]*)</);
  assert.ok(name, 'the sequence-name slot must exist in the markup');
  assert.match(name[1].trim(), /^Connecting/);
});
