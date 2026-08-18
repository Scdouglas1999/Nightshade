// Web-dashboard honesty contract.
//
// app.js is one closed IIFE with no exports, so — following the convention in
// app_initialization_contract_test.js — each render path under test is lifted
// out of the source and EXECUTED against a DOM shim with its collaborators
// injected. The assertions are about what lands in the document, not about how
// the source is spelled.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const { makeDocument } = require('./dom_shim');

const ROOT = path.join(__dirname, '..');
const APP = fs.readFileSync(path.join(ROOT, 'js', 'app.js'), 'utf8');
const API = fs.readFileSync(path.join(ROOT, 'js', 'api.js'), 'utf8');
const HTML = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');

/** Lift `function <name>(...) { … }` out of the IIFE by its 2-space indent. */
function fn(name) {
  const re = new RegExp(
    '(?:  |  async )function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}',
  );
  const m = APP.match(re);
  assert.ok(m, name + ' must exist in app.js');
  return m[0];
}

/**
 * Lift a top-level `const NAME = …;` declaration out of the IIFE. The value
 * may wrap over several lines — a derived threshold is spelled as the
 * arithmetic that produces it, and the test must read that arithmetic, not a
 * number retyped here.
 */
function konst(name) {
  const re = new RegExp('  const ' + name + ' =[\\s\\S]*?;');
  const m = APP.match(re);
  assert.ok(m, name + ' must exist in app.js');
  return m[0];
}

/** Lift a top-level `let NAME = …;` declaration out of the IIFE. */
function letDecl(name) {
  const re = new RegExp('  let ' + name + ' =[^;]*;');
  const m = APP.match(re);
  assert.ok(m, name + ' must exist in app.js');
  return m[0];
}

function build(params, sources, exportName) {
  // eslint-disable-next-line no-new-func
  return new Function(
    ...params,
    sources.join('\n') + '\n;return ' + exportName + ';',
  );
}

// ---------------------------------------------------------------------------
// D4-05 — guider RMS
// ---------------------------------------------------------------------------

function guidingPanel(guidingStatus) {
  const doc = makeDocument([
    'guide-status', 'guide-ra-rms', 'guide-dec-rms', 'guide-total-rms',
  ]);
  const badges = [];
  const render = build(
    ['document', 'state', 'renderBadge', 'updateGuidingButtons'],
    [fn('renderGuidingPanel')],
    'renderGuidingPanel',
  )(
    doc,
    { guidingStatus },
    (el, label, cls) => { badges.push({ label, cls }); el.textContent = label; },
    () => {},
  );
  render();
  return { doc, badges };
}

// GET /api/phd2/status answers `rmsRa`/`rmsDec`/`rmsTotal`, all 0.0 while
// disconnected. The panel read `rmsRA` — a key no response carries — so the RA
// row was permanently "--", while Dec and Total rendered the disconnected
// zeros as a flawless 0.00" guide.
test('a disconnected guider shows no RMS in any row', () => {
  const { doc } = guidingPanel({
    state: 'Disconnected', connected: false,
    rmsRa: 0.0, rmsDec: 0.0, rmsTotal: 0.0, snr: 0.0,
  });
  assert.equal(doc.getElementById('guide-ra-rms').textContent, '--');
  assert.equal(doc.getElementById('guide-dec-rms').textContent, '--');
  assert.equal(doc.getElementById('guide-total-rms').textContent, '--');
});

test('a connected guider shows all three RMS rows from the real keys', () => {
  const { doc } = guidingPanel({
    state: 'Guiding', connected: true,
    rmsRa: 0.41, rmsDec: 0.38, rmsTotal: 0.56, snr: 22.5,
  });
  assert.equal(doc.getElementById('guide-ra-rms').textContent, '0.41"');
  assert.equal(doc.getElementById('guide-dec-rms').textContent, '0.38"');
  assert.equal(doc.getElementById('guide-total-rms').textContent, '0.56"');
});

test('the RA row reads the key the server sends', () => {
  const source = fn('renderGuidingPanel');
  assert.match(source, /g\.rmsRa\b/);
  assert.doesNotMatch(source, /g\.rmsRA\b/,
    'rmsRA matches nothing in /api/phd2/status');
});

// ---------------------------------------------------------------------------
// D4-10 — safety verdict with no sensor
// ---------------------------------------------------------------------------

function weatherPanel(weather, safety) {
  const doc = makeDocument([
    'ops-weather-safe', 'ops-weather-alert-level', 'ops-weather-message',
    'ops-weather-temp', 'ops-weather-humidity', 'ops-weather-clouds',
    'ops-weather-wind', 'ops-weather-dew', 'ops-safety-badge',
    'ops-safety-monitor-count', 'ops-safety-monitor-list',
  ]);
  const render = build(
    ['document', 'state', 'clearElement'],
    [fn('renderOpsWeatherPanel'), fn('setOpsTelemetry')],
    'renderOpsWeatherPanel',
  )(doc, { ops: { weather, safety } }, (el) => { el.children = []; });
  render();
  return doc;
}

// A headless appliance with no weather hardware answers
// /api/weather/current with safeToImage:true, alertLevel:"clear",
// dataSource:"unavailable" and /api/safety/status with isSafe:true,
// monitorsConnected:0, failModeWarning:"No weather data sources available".
// Rendering the first two verbatim produced a green "yes / clear / safe" for a
// rig nothing was watching.
test('no weather source yields no affirmative safety verdict', () => {
  const doc = weatherPanel(
    {
      safeToImage: true, alertLevel: 'clear', dataSource: 'unavailable',
      message: 'Weather safety is off — conditions are not being checked',
    },
    {
      isSafe: true, monitorsConnected: 0, monitors: [],
      dataSource: 'unavailable',
      failModeWarning: 'No weather data sources available',
    },
  );
  const safe = doc.getElementById('ops-weather-safe');
  assert.equal(safe.textContent, 'no sensor');
  assert.ok(!safe.className.includes('good'));
  assert.equal(doc.getElementById('ops-weather-alert-level').textContent,
    'not measured');
  const badge = doc.getElementById('ops-safety-badge');
  assert.equal(badge.textContent, 'no source');
  assert.ok(!badge.className.includes('badge-running'),
    'an unmonitored sky must not read green');
});

test('a real sensor still renders its verdict', () => {
  const doc = weatherPanel(
    {
      safeToImage: true, alertLevel: 'clear', dataSource: 'hardware',
      message: 'Clear and dry', temperature: 4.5, humidity: 61,
    },
    { isSafe: true, monitorsConnected: 1, monitors: [], dataSource: 'hardware' },
  );
  assert.equal(doc.getElementById('ops-weather-safe').textContent, 'yes');
  assert.ok(doc.getElementById('ops-weather-safe').className.includes('good'));
  assert.equal(doc.getElementById('ops-weather-alert-level').textContent, 'clear');
  assert.equal(doc.getElementById('ops-safety-badge').textContent, 'safe');
  assert.equal(doc.getElementById('ops-weather-temp').textContent, '4.5 °C');
});

test('a real sensor reporting unsafe still reads unsafe', () => {
  const doc = weatherPanel(
    { safeToImage: false, alertLevel: 'unsafe', dataSource: 'hardware', message: 'Rain' },
    { isSafe: false, monitorsConnected: 1, monitors: [], dataSource: 'hardware' },
  );
  assert.equal(doc.getElementById('ops-weather-safe').textContent, 'no');
  assert.equal(doc.getElementById('ops-safety-badge').textContent, 'unsafe');
});

// ---------------------------------------------------------------------------
// D4-04 — settings panel reads only keys the API emits
// ---------------------------------------------------------------------------

// Verified against a live headless host: GET /api/settings emits 146 keys, of
// which `observatoryName`, `defaultSavePath` and `plateSolveSolver` are none;
// GET /api/settings/location answers {latitude, longitude, elevation} with no
// `elevationMeters`. All four rows therefore read "--" on a configured host.
test('the settings panel reads the keys the API actually emits', async () => {
  const doc = makeDocument([
    'settings-observer-name', 'settings-save-path', 'settings-plate-solver',
    'settings-latitude', 'settings-longitude', 'settings-elevation',
  ]);
  const refresh = build(
    ['document', 'api', 'addLogEntry'],
    [fn('refreshSettingsPanel')],
    'refreshSettingsPanel',
  )(
    doc,
    {
      isConnected: true,
      getSettings: async () => ({
        settings: {
          observerName: 'S. Douglas',
          imageOutputPath: '/srv/lights',
          plateSolver: 'ASTAP',
        },
      }),
      getLocation: async () => ({
        location: { latitude: 40.1, longitude: -105.2, elevation: 1650.0 },
      }),
    },
    () => { throw new Error('the happy path must not log an error'); },
  );
  await refresh();

  assert.equal(doc.getElementById('settings-observer-name').textContent, 'S. Douglas');
  assert.equal(doc.getElementById('settings-save-path').textContent, '/srv/lights');
  assert.equal(doc.getElementById('settings-plate-solver').textContent, 'ASTAP');
  assert.equal(doc.getElementById('settings-latitude').textContent, '40.1000°');
  assert.equal(doc.getElementById('settings-elevation').textContent, '1650 m');
});

test('the settings panel names no key the server does not send', () => {
  // Comments name the dead keys on purpose; only executable lines are checked.
  const code = fn('refreshSettingsPanel')
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  for (const dead of ['observatoryName', 'defaultSavePath', 'plateSolveSolver',
    'elevationMeters']) {
    assert.doesNotMatch(code, new RegExp('\\b' + dead + '\\b'),
      dead + ' appears in no server response');
  }
  assert.match(HTML, /id="settings-observer-name"/);
  assert.doesNotMatch(HTML, /id="settings-observatory-name"/);
});

// ---------------------------------------------------------------------------
// D4-01 — a dead backend must flip the header, not stay green
// ---------------------------------------------------------------------------

/**
 * Stand the page's whole data clock up — the tick, the header subscriber, the
 * Run-panel subscriber and the per-panel stale lines — and hand back one
 * `render()` that drives all of them from one sample, exactly as the running
 * page does. Testing the header alone is what let the Run panel keep a second,
 * disagreeing clock.
 */
function linkState({ unreachable, lastContactAt, lastWsMessageAt,
  rateLimitRemainingSecs = 0, lastProbeAt = Date.now(), isConnected = true,
  panelLastUpdate = {}, panelLastFailure = {} }) {
  const doc = makeDocument([
    'link-banner', 'status-text', 'status-dot', 'seq-status', 'seq-node',
    'seq-message',
    'ops-seq-progress-text', 'seq-progress-text', 'seq-progress-bar',
    'seq-progress-bar-container', 'ops-seq-progress-bar',
    'ops-seq-progress-bar-container', 'ops-seq-eta', 'ops-seq-current-node',
    'ops-seq-current-target',
    'stale-devices', 'stale-mount', 'stale-camera', 'stale-sequencer',
    'stale-guiding', 'stale-focuser', 'stale-filter-wheel', 'stale-rotator',
    'stale-sequences', 'stale-analytics',
  ]);
  doc.getElementById('status-text').textContent = 'Connected';
  doc.getElementById('status-dot').className = 'status-dot connected';
  const calls = [];
  const repaints = [];
  const zeroed = {
    devices: 0, mount: 0, camera: 0, sequencer: 0, guiding: 0,
    focuser: 0, 'filter-wheel': 0, rotator: 0, sequences: 0, analytics: 0,
  };
  // Mutable, so a test can move the clock and repaint through the SAME
  // closure — the flag the recovery edge turns off lives in there.
  const api = { lastContactAt, isConnected, rateLimitRemainingSecs };
  const state = {
    serverUnreachable: unreachable,
    lastWsMessageAt,
    panelLastUpdate: Object.assign({}, zeroed, panelLastUpdate),
    panelLastFailure: Object.assign({}, zeroed, panelLastFailure),
  };
  const render = build(
    ['document', 'api', 'state', 'lastReachabilityProbeAt',
      'setConnectionStatus', 'renderBadge', 'renderSequencerPanel'],
    [
      konst('REACHABILITY_PROBE_MS'),
      konst('SERVER_HEARTBEAT_MS'),
      konst('MISSED_HEARTBEATS_BEFORE_STALE'),
      konst('SERVER_CONTACT_STALE_MS'),
      konst('PANEL_KEYS'),
      letDecl('runUnknownAsserted'),
      fn('lastServerContactAt'),
      fn('isServerContactStale'),
      fn('isPanelDataStale'),
      fn('formatAgeSeconds'),
      // The real helper, not a stub: what the stale branch does to the
      // progress readouts is the thing under test.
      fn('markProgressUnknown'),
      fn('renderLinkState'),
      fn('runDataIsStale'),
      fn('paintRunUnknown'),
      fn('renderRunDataState'),
      fn('renderStaleIndicator'),
      // The tick itself, and the wiring init() performs — both real, so a
      // subscriber the page forgets to register fails here too.
      'const dataClockSubscribers = [];',
      fn('subscribeToDataClock'),
      fn('repaintDataState'),
      `subscribeToDataClock(renderLinkState);
       subscribeToDataClock(renderRunDataState);
       for (const panelKey of PANEL_KEYS) {
         subscribeToDataClock((view) => renderStaleIndicator(panelKey, view));
       }`,
    ],
    'repaintDataState',
  )(
    doc,
    api,
    state,
    lastProbeAt,
    (s) => {
      calls.push(s);
      if (s === 'connected') {
        doc.getElementById('status-text').textContent = 'Connected';
      }
    },
    (el, label, cls) => { el.textContent = label; el.className = cls; },
    () => { repaints.push('sequencer'); },
  );
  render();
  return { doc, calls, repaints, render, api, state };
}

// Measured before the fix: 65 s after SIGKILL the header still read a green
// "Connected", the sequencer badge still read "running", and the weather panel
// still read "safe". `api.isConnected` is set once at connect and never
// cleared, so nothing in the page ever contradicted it.
test('an unreachable server flips the header and raises a banner', () => {
  const now = Date.now();
  const { doc } = linkState({
    unreachable: true,
    lastContactAt: now - 30000,
    lastWsMessageAt: now - 30000,
    lastProbeAt: now - 1000,
  });
  assert.equal(doc.getElementById('status-text').textContent, 'No contact');
  assert.ok(doc.getElementById('status-dot').className.includes('error'));
  const banner = doc.getElementById('link-banner');
  assert.ok(!banner.classList.contains('hidden'));
  assert.match(banner.textContent, /Cannot reach the Nightshade server/);
  assert.match(banner.textContent, /may be wrong/);
  assert.equal(doc.getElementById('seq-status').textContent, 'unknown',
    'the sequencer badge must stop claiming a state');
});

// D4W-02. The badge was fixed and the figure was not. Measured against the
// running bundle: SIGKILL at wire progress 0.250 left the badge "unknown" and
// the banner up while "25%" stayed on screen, the bar stayed 94.75px wide and
// the container kept announcing aria-valuenow="25" — for the whole 47 s the
// probe watched. The sibling ops readout was correctly "--" the entire time,
// so the page contradicted itself as well as the world.
test('a lost link stops asserting a progress figure', () => {
  const now = Date.now();
  const seed = (doc) => {
    doc.getElementById('seq-progress-text').textContent = '25%';
    doc.getElementById('seq-progress-bar').style.width = '25%';
    doc.getElementById('seq-progress-bar-container')
      .setAttribute('aria-valuenow', '25');
    doc.getElementById('ops-seq-progress-text').textContent = '25%';
    doc.getElementById('ops-seq-progress-bar').style.width = '25%';
    doc.getElementById('ops-seq-progress-bar-container')
      .setAttribute('aria-valuenow', '25');
    doc.getElementById('ops-seq-eta').textContent = '12m';
  };
  // Render once healthy so the seeded values are what a live run left behind,
  // then lose the server through the same closure.
  const h = linkState({
    unreachable: false,
    lastContactAt: now - 500,
    lastWsMessageAt: now - 500,
  });
  seed(h.doc);
  h.state.serverUnreachable = true;
  h.api.lastContactAt = now - 47000;
  h.state.lastWsMessageAt = now - 47000;
  h.render();

  const doc = h.doc;
  assert.equal(doc.getElementById('seq-status').textContent, 'unknown');
  for (const id of ['seq-progress-text', 'ops-seq-progress-text']) {
    assert.equal(doc.getElementById(id).textContent, '--',
      id + ' must stop naming a percentage');
  }
  for (const id of ['seq-progress-bar', 'ops-seq-progress-bar']) {
    assert.equal(doc.getElementById(id).style.width, '0%');
    assert.ok(doc.getElementById(id).classList.contains('unknown'),
      id + ' must not draw as a run that has done nothing');
  }
  for (const id of ['seq-progress-bar-container',
    'ops-seq-progress-bar-container']) {
    assert.equal(doc.getElementById(id).getAttribute('aria-valuenow'), null,
      id + ' must stop announcing a figure');
    assert.ok(doc.getElementById(id).classList.contains('unknown'));
  }
  // The ETA is extrapolated from that percentage; it cannot outlive it.
  assert.equal(doc.getElementById('ops-seq-eta').textContent, '--');
});

test('an unknown bar is visually distinct from a genuine zero', () => {
  // The two states share `width: 0%`, so the distinction has to be carried by
  // something else, and something else has to actually paint it.
  const css = fs.readFileSync(
    path.join(ROOT, 'css', 'dashboard.css'), 'utf8');
  assert.match(css, /\.progress-bar-container\.unknown\s*\{[\s\S]*?background-image/,
    'the unknown track must have its own rendering');
});

test('silence past the contact window is stale even without a failed probe', () => {
  const now = Date.now();
  // Two whole heartbeats missed and then some: nothing has answered for well
  // over a minute on a link the socket still believes is up.
  const { doc } = linkState({
    unreachable: false,
    lastContactAt: now - 70000,
    lastWsMessageAt: now - 70000,
  });
  assert.equal(doc.getElementById('status-text').textContent, 'No contact');
  assert.match(doc.getElementById('link-banner').textContent,
    /No answer from the Nightshade server/);
});

// D4W-1. An idle server pushes no events, so the 30 s ping/pong is the only
// thing that stamps contact and the gap between beats routinely reaches a full
// interval. Measured against the 12 s window this code used to carry: over a
// 200 s soak of a healthy, idle server the header spent 26 of 40 samples on
// "No contact" while every request in flight was being answered.
test('a healthy idle server between heartbeats is never declared lost', () => {
  const now = Date.now();
  for (const gap of [12001, 20000, 29500, 35000]) {
    const { doc } = linkState({
      unreachable: false,
      lastContactAt: now - gap,
      lastWsMessageAt: now - gap,
    });
    assert.equal(doc.getElementById('status-text').textContent, 'Connected',
      gap + ' ms since the last beat is quiet, not lost');
    assert.ok(doc.getElementById('link-banner').classList.contains('hidden'),
      'no banner at ' + gap + ' ms');
    assert.equal(doc.getElementById('seq-status').textContent, '',
      'the badge is left to the sequencer renderer at ' + gap + ' ms');
  }
});

// D4W-2. Staleness is a state of the link, not a mark burned into the badge:
// the badge that went "unknown" on a missed exchange stayed "unknown" for the
// rest of the session — through every later healthy poll — because only the
// header was ever restored.
test('contact returning hands the badge back to the real renderer', () => {
  const now = Date.now();
  const { doc, calls, repaints, render, api, state } = linkState({
    unreachable: true,
    lastContactAt: now - 70000,
    lastWsMessageAt: now - 70000,
    lastProbeAt: now - 1000,
  });
  assert.equal(doc.getElementById('seq-status').textContent, 'unknown');
  assert.deepEqual(repaints, [], 'nothing to restore while still stale');

  // The server answers again.
  api.lastContactAt = Date.now();
  state.lastWsMessageAt = Date.now();
  state.serverUnreachable = false;
  render();

  assert.deepEqual(repaints, ['sequencer'],
    'the sequencer panel repaints from the data, not from the overlay');
  assert.ok(calls.includes('connected'));
  assert.ok(doc.getElementById('link-banner').classList.contains('hidden'));

  // A second healthy tick must not keep repainting: the edge fired once.
  render();
  assert.deepEqual(repaints, ['sequencer']);
});

test('a healthy link leaves the header alone and hides the banner', () => {
  const now = Date.now();
  const { doc } = linkState({
    unreachable: false,
    lastContactAt: now - 500,
    lastWsMessageAt: now - 500,
  });
  assert.equal(doc.getElementById('status-text').textContent, 'Connected');
  assert.ok(doc.getElementById('link-banner').classList.contains('hidden'));
});

test('a rate-limited but live server says so without going stale', () => {
  const now = Date.now();
  const { doc } = linkState({
    unreachable: false,
    lastContactAt: now - 500,
    lastWsMessageAt: now - 500,
    rateLimitRemainingSecs: 3,
  });
  assert.equal(doc.getElementById('status-text').textContent, 'Connected');
  const banner = doc.getElementById('link-banner');
  assert.ok(!banner.classList.contains('hidden'));
  assert.match(banner.textContent, /rate-limiting this session/);
  assert.match(banner.textContent, /3s/);
});

// ---------------------------------------------------------------------------
// D4-03 — 429 handling
// ---------------------------------------------------------------------------

function loadApi(fetchStub) {
  const context = vm.createContext({
    fetch: fetchStub,
    Headers: globalThis.Headers,
    AbortController: globalThis.AbortController,
    setTimeout: globalThis.setTimeout,
    clearTimeout: globalThis.clearTimeout,
    Date: globalThis.Date,
    isFinite: globalThis.isFinite,
    Number: globalThis.Number,
    JSON: globalThis.JSON,
    console,
  });
  vm.runInContext(API + '\n;globalThis.__api = new NightshadeApi();', context);
  return context.__api;
}

const RATE_LIMIT_BODY = JSON.stringify({
  code: 'rate_limited', error: 'Rate limit exceeded',
  message: 'Token token-6e609b0e exceeded read bucket',
  bucket: 'read', maxRequests: 60, retryAfterSecs: 3, retryAfterSeconds: 3,
  requestId: 'dash-abc',
});

// Reproduced against a live host: a burst put the limiter's JSON body straight
// into the operator's log panel — "Settings fetch failed: GET /api/settings
// failed (429): {"code":"rate_limited",…}" — and nothing honoured
// retryAfterSecs, so the next tick fired into the same empty bucket.
test('a 429 becomes a typed retry window, never a rendered body', async () => {
  let calls = 0;
  const api = loadApi(async () => {
    calls += 1;
    return {
      ok: false, status: 429,
      headers: new Headers({ 'retry-after': '3' }),
      text: async () => RATE_LIMIT_BODY,
    };
  });

  await assert.rejects(
    () => api.getSettings(),
    (e) => e.kind === 'rate_limited' && e.retryAfterSecs === 3 &&
      !/rate_limited|maxRequests|requestId/.test(e.message),
  );
  assert.equal(calls, 1);
  assert.equal(api.rateLimitRemainingSecs, 3);

  // Inside the window no request leaves the page.
  await assert.rejects(() => api.getSettings(), (e) => e.kind === 'rate_limited');
  assert.equal(calls, 1, 'the client must not re-fire inside the retry window');
});

test('a transport failure is typed unreachable and stamps no contact', async () => {
  const api = loadApi(async () => { throw new TypeError('Failed to fetch'); });
  await assert.rejects(() => api.getInfo(), (e) => e.kind === 'unreachable');
  assert.equal(api.lastContactAt, 0,
    'a fetch that never completed is not proof the server exists');
});

test('any answered request counts as contact, even a 500', async () => {
  const api = loadApi(async () => ({
    ok: false, status: 500, headers: new Headers(), text: async () => 'boom',
  }));
  await assert.rejects(() => api.getInfo(), (e) => e.kind === 'http_error');
  assert.ok(api.lastContactAt > 0);
});

test('describeApiError never leaks a rate-limit body into the log', () => {
  const describe = build(['x'], [fn('describeApiError')], 'describeApiError')(null);
  const limited = describe(
    { kind: 'rate_limited', retryAfterSecs: 3, message: RATE_LIMIT_BODY },
    'Settings fetch',
  );
  assert.match(limited, /rate-limiting this session/);
  assert.doesNotMatch(limited, /rate_limited|maxRequests|requestId/);
  assert.match(
    describe({ kind: 'unreachable', message: 'x' }, 'Devices fetch'),
    /no answer from the server/,
  );
  assert.match(
    describe({ kind: 'http_error', message: 'GET /api/x failed (404): gone' }, 'X'),
    /404/,
    'a real HTTP error keeps its detail',
  );
});

// ---------------------------------------------------------------------------
// D4-08 — aria-valuenow
// ---------------------------------------------------------------------------

test('no progress bar declares aria-valuenow before it has a value', () => {
  const bars = HTML.match(/<div class="progress-bar-container"[^>]*>/g) || [];
  assert.ok(bars.length >= 2, 'both sequencer progress bars must exist');
  for (const bar of bars) {
    assert.doesNotMatch(bar, /aria-valuenow/,
      'markup must not announce a percentage nothing has reported');
  }
  // Both panels reach the clearing through the one helper now, so the helper is
  // where the rule lives — and the callers must be the ones using it.
  assert.match(fn('markProgressUnknown'), /removeAttribute\('aria-valuenow'\)/,
    'the unknown render must clear the announced value');
  for (const name of ['renderSequencerPanel', 'renderOpsSequencerLoadPanel',
    'paintRunUnknown']) {
    const source = fn(name);
    assert.match(source, /markProgressUnknown\(/,
      name + ' must clear the value when the figure is unknown');
    assert.doesNotMatch(source, /setAttribute\('aria-valuenow', '0'\)/);
  }
});

// ---------------------------------------------------------------------------
// D4W-5 — before the first answer, the page is connecting, not reporting
// ---------------------------------------------------------------------------

test('the sequencer badge asserts nothing before the first status', () => {
  const doc = makeDocument([
    'seq-status', 'seq-node', 'seq-message', 'seq-progress-bar',
    'seq-progress-bar-container', 'seq-progress-text',
  ]);
  const render = build(
    ['document', 'state', 'renderBadge', 'updateSequencerButtons',
      'getSequencerBadgeClass', 'sequencerProgressPercent',
      'renderOpsSequencerLoadPanel', 'runDataIsStale', 'paintRunUnknown'],
    [fn('markProgressUnknown'), fn('markProgressKnown'),
      fn('renderSequencerPanel')],
    'renderSequencerPanel',
  )(
    doc,
    { sequencerStatus: null },
    (el, label, cls) => { el.textContent = label; el.className = cls; },
    () => {},
    () => 'badge-idle',
    () => 0,
    () => {},
    // A healthy link with a fresh sequencer route: this test is about the
    // page before its FIRST answer, not about a stale one.
    () => false,
    () => { throw new Error('the unknown overlay must not fire on a fresh link'); },
  );
  render();
  assert.equal(doc.getElementById('seq-status').textContent, 'connecting',
    'a rig this page has never heard from is not "idle"');
  assert.equal(doc.getElementById('seq-progress-text').textContent, '');
  assert.equal(
    doc.getElementById('seq-progress-bar-container')
      .getAttribute('aria-valuenow'),
    null,
  );
  assert.ok(doc.getElementById('seq-progress-bar').classList
    .contains('unknown'),
  'a bar that has heard nothing must not draw as a real zero');

  // The shipped markup is what the operator sees for the first few hundred ms,
  // before any JS has run — it must make the same claim, which is none.
  const badge = HTML.match(/<span id="seq-status">[\s\S]*?<\/span>\s*<\/span>/);
  assert.ok(badge, 'the sequencer status badge must exist in the markup');
  assert.match(badge[0], />connecting</);
});

// ---------------------------------------------------------------------------
// D4W-01 — the server log tail
// ---------------------------------------------------------------------------

/// An EventSource good enough to prove which listener kind a client used.
class FakeEventSource {
  constructor(url) {
    this.url = url;
    this.listeners = new Map();
    this.onmessage = null;
    this.onerror = null;
    this.onopen = null;
    FakeEventSource.last = this;
  }
  addEventListener(name, fn) {
    if (!this.listeners.has(name)) this.listeners.set(name, []);
    this.listeners.get(name).push(fn);
  }
  close() { this.closed = true; }

  /// Deliver a frame the way the server writes it: `event: <name>` + data.
  /// A named frame does NOT reach `onmessage` — that is the whole defect.
  emit(name, data) {
    const event = { data: JSON.stringify(data) };
    for (const fn of this.listeners.get(name) || []) fn(event);
    if (name === 'message' && this.onmessage) this.onmessage(event);
  }
}

function apiWithEventSource() {
  const context = vm.createContext({
    fetch: async () => { throw new Error('no fetch in this test'); },
    Headers: globalThis.Headers,
    AbortController: globalThis.AbortController,
    setTimeout: globalThis.setTimeout,
    clearTimeout: globalThis.clearTimeout,
    Date: globalThis.Date,
    isFinite: globalThis.isFinite,
    Number: globalThis.Number,
    JSON: globalThis.JSON,
    EventSource: FakeEventSource,
    encodeURIComponent: globalThis.encodeURIComponent,
    console,
  });
  vm.runInContext(API + '\n;globalThis.__api = new NightshadeApi();', context);
  const api = context.__api;
  // The bearer rides in the query string: EventSource has no header API.
  api._authToken = 'tok-1';
  return api;
}

// Measured against the running bundle: the panel sat on "Waiting for log
// entries…" behind a badge reading "live" while a second EventSource attached
// to the IDENTICAL url counted 174 frames on `addEventListener('log', …)` and
// 0 on `onmessage`, over the same 12 s. `log_handlers.dart` names every frame
// (`event: log`), and EventSource.onmessage fires only for unnamed ones.
test('the log tail listens for the frames the server actually names', () => {
  const api = apiWithEventSource();
  const seen = [];
  let replayDone = 0;
  api.subscribeLogTail('info', (e) => seen.push(e), null, () => { replayDone++; });
  const source = FakeEventSource.last;

  source.emit('log', {
    timestamp: '2026-08-17T13:36:11.111819Z',
    severity: 'warning',
    source: 'HeadlessMain',
    message: 'SECURITY: TLS IS OFF',
  });
  source.emit('replay-done', {});

  assert.equal(seen.length, 1, 'a named "log" frame is an entry');
  assert.equal(seen[0].source, 'HeadlessMain');
  assert.equal(replayDone, 1, 'the end of the replay is the server\'s own event');
  assert.equal(source.onmessage, null,
    'nothing may hang off onmessage: this endpoint sends no unnamed frames');
});

// The tail reads `severity` — an allow-LIST of exact level names. `minSeverity`
// is /api/logs/recent's parameter and is ignored here, so the panel's selector
// filtered nothing at all: a debug firehose arrived on a stream asked for
// "info". Verified on the wire — `minSeverity=info` returned 2 debug entries in
// the same window where `severity=info,warning,error,critical` returned none.
test('the log tail asks for the severities with the parameter that filters', () => {
  const api = apiWithEventSource();
  api.subscribeLogTail('warning', () => {}, null);
  const url = FakeEventSource.last.url;
  assert.match(url, /severity=warning%2Cerror%2Ccritical/);
  assert.doesNotMatch(url, /minSeverity/,
    'minSeverity is silently ignored by /api/logs/tail');

  // The names are the server's own LogLevel values; "trace" and "warn" parse
  // as nothing on the other side.
  // Spread back into this realm: the vm sandbox's Array is a different class.
  const ctor = api.constructor;
  assert.deepEqual([...ctor.logLevels],
    ['debug', 'info', 'warning', 'error', 'critical']);
  assert.deepEqual([...ctor.logSeveritiesAtOrAbove('trace')], [],
    'an unknown name filters nothing rather than narrowing silently');
});

test('the severity selector offers only levels the server knows', () => {
  const select = HTML.match(
    /<select id="logs-min-severity"[\s\S]*?<\/select>/);
  assert.ok(select, 'the severity selector must exist');
  const values = [...select[0].matchAll(/value="([^"]+)"/g)].map((m) => m[1]);
  assert.deepEqual(values, ['debug', 'info', 'warning', 'error', 'critical']);
});

test('a log row reads the keys a log frame carries', () => {
  const doc = makeDocument(['logs-container']);
  const append = build(
    ['document', 'logTail'],
    [fn('appendLogRow')],
    'appendLogRow',
  )(doc, { maxEntries: 500 });
  append({
    timestamp: '2026-08-17T13:36:11.111819Z',
    severity: 'warning',
    source: 'DeliveryRetrySweeper',
    message: 'Started the Darkroom delivery retry sweep (every 900s).',
  });
  const row = doc.getElementById('logs-container').children[0];
  const text = row.children.map((c) => c.textContent);
  assert.ok(text.includes('WARNING'), 'the severity comes from `severity`');
  assert.ok(text.includes('DeliveryRetrySweeper'),
    'the source column comes from `source` — `target` is a key no frame has');
  assert.ok(row.className.includes('log-warning'));

  // The keys that were being read and are not in `LogEntry.toJson`.
  const code = fn('appendLogRow')
    .split('\n')
    .filter((line) => !line.trim().startsWith('//'))
    .join('\n');
  for (const dead of ['payload.level', 'payload.target', 'payload.module',
    'payload.category', 'payload.msg', 'payload.timestampMs']) {
    assert.ok(!code.includes(dead), dead + ' appears in no log frame');
  }
});

// ---------------------------------------------------------------------------
// D4-01 (wave 6) — one failing route must not leave the Run panel painting a
// frozen run as live
//
// Measured against the running bundle with /api/sequencer/status substituted
// for a plain HTTP 500 and EVERY other request reaching the real daemon: 66
// refused refreshes over 45 s, every 5 s sample identical —
//   hdr='Connected' seq='running' node='Exposure L' pct='3%'
//   msg='Exposure: Frame 2/20 (5.0s) (10%)' staleBadge=hidden
// while the wire read state=running progress=0.1375 'Frame 11/20'. The page
// asserted 3% for a rig at 13.75%, under a green header, with the per-panel
// stale badge suppressed by its `wsHealthy` gate because the event socket was
// perfectly healthy the whole time.
// ---------------------------------------------------------------------------

/** The page mid-run: everything fresh, the sequencer route just refused. */
function runPanelWithFailingRoute(agoMs) {
  const now = Date.now();
  const fresh = now - 1000;
  const h = linkState({
    unreachable: false,
    lastContactAt: now - 200,
    lastWsMessageAt: now - 200,
    panelLastUpdate: {
      devices: fresh, mount: fresh, camera: fresh, sequencer: now - agoMs,
      guiding: fresh, focuser: fresh, 'filter-wheel': fresh, rotator: fresh,
    },
  });
  // A live run is on screen when the route starts failing.
  h.doc.getElementById('seq-status').textContent = 'running';
  h.doc.getElementById('seq-node').textContent = 'Exposure L';
  h.doc.getElementById('seq-message').textContent =
    'Exposure: Frame 2/20 (5.0s) (10%)';
  h.doc.getElementById('seq-progress-text').textContent = '3%';
  h.doc.getElementById('seq-progress-bar').style.width = '3%';
  h.doc.getElementById('seq-progress-bar-container')
    .setAttribute('aria-valuenow', '3');
  h.doc.getElementById('ops-seq-eta').textContent = '31m';
  return h;
}

test('a failing sequencer route stops the Run panel asserting a live run', () => {
  const h = runPanelWithFailingRoute(45000);
  // The link is fine: the server is answering everything else, and the header
  // must go on saying so.
  assert.equal(h.doc.getElementById('status-text').textContent, 'Connected');
  assert.ok(h.doc.getElementById('link-banner').classList.contains('hidden'));
  assert.equal(h.doc.getElementById('seq-status').textContent, 'running',
    'a healthy route is not stale merely because 45 s have passed');

  // Now the route refuses. Nothing else about the page changes.
  h.state.panelLastFailure.sequencer = Date.now();
  h.render();

  assert.equal(h.doc.getElementById('seq-status').textContent, 'unknown',
    'the badge must stop claiming a state its own source refused to confirm');
  assert.equal(h.doc.getElementById('seq-progress-text').textContent, '--');
  assert.equal(
    h.doc.getElementById('seq-progress-bar-container')
      .getAttribute('aria-valuenow'), null);
  assert.equal(h.doc.getElementById('seq-node').textContent, '--');
  assert.equal(h.doc.getElementById('seq-message').textContent, '');
  assert.equal(h.doc.getElementById('ops-seq-eta').textContent, '--');
});

test('a failing route says on the panel how old its data is', () => {
  const h = runPanelWithFailingRoute(45000);
  h.state.panelLastFailure.sequencer = Date.now();
  h.render();

  const badge = h.doc.getElementById('stale-sequencer');
  assert.ok(badge.classList.contains('visible'),
    'a healthy event socket must not suppress the panel that is failing');
  assert.match(badge.textContent, /Stale: 45s since last update/);
  // Only the panel that failed. The rest of the rig is being reported fine.
  for (const key of ['devices', 'mount', 'camera', 'guiding', 'focuser',
    'filter-wheel', 'rotator']) {
    assert.equal(h.doc.getElementById('stale-' + key).textContent, '',
      key + ' is answering and must not be marked stale');
  }
});

test('a quiet but healthy night marks nothing stale', () => {
  // The whole reason the suppressing gate existed: an idle server pushes no
  // events, so a panel's last refresh can be minutes old with nothing wrong.
  const now = Date.now();
  const h = linkState({
    unreachable: false,
    lastContactAt: now - 2000,
    lastWsMessageAt: now - 2000,
    panelLastUpdate: {
      devices: now - 600000, mount: now - 600000, camera: now - 600000,
      sequencer: now - 600000, guiding: now - 600000, focuser: now - 600000,
      'filter-wheel': now - 600000, rotator: now - 600000,
    },
  });
  for (const key of ['devices', 'mount', 'camera', 'sequencer', 'guiding',
    'focuser', 'filter-wheel', 'rotator']) {
    assert.equal(h.doc.getElementById('stale-' + key).textContent, '',
      key + ' has nothing new to report, which is not the same as stale');
  }
  assert.equal(h.doc.getElementById('seq-status').textContent, '',
    'the Run panel is left to its own renderer on a healthy night');
});

test('a route that answers again hands the Run panel back to its renderer', () => {
  const h = runPanelWithFailingRoute(45000);
  h.state.panelLastFailure.sequencer = Date.now();
  h.render();
  assert.equal(h.doc.getElementById('seq-status').textContent, 'unknown');
  assert.deepEqual(h.repaints, [], 'nothing to restore while still stale');

  // The next refresh succeeds.
  h.state.panelLastUpdate.sequencer = Date.now();
  h.render();
  assert.deepEqual(h.repaints, ['sequencer'],
    'the panel repaints from the data, not from the overlay');
  assert.equal(h.doc.getElementById('stale-sequencer').textContent, '');

  // A second healthy tick must not keep repainting: the edge fired once.
  h.render();
  assert.deepEqual(h.repaints, ['sequencer']);
});

test('the header and the panels age their data on one clock', () => {
  // The header's verdict is a page-wide fact: when contact is gone, every
  // panel is stale too, without each one needing its own failure recorded.
  const now = Date.now();
  const h = linkState({
    unreachable: true,
    lastContactAt: now - 70000,
    lastWsMessageAt: now - 70000,
    lastProbeAt: now - 1000,
    panelLastUpdate: {
      devices: now - 70000, mount: now - 70000, camera: now - 70000,
      sequencer: now - 70000, guiding: now - 70000, focuser: now - 70000,
      'filter-wheel': now - 70000, rotator: now - 70000,
      sequences: now - 70000, analytics: now - 70000,
    },
  });
  assert.equal(h.doc.getElementById('status-text').textContent, 'No contact');
  for (const key of ['devices', 'mount', 'camera', 'sequencer', 'guiding',
    'focuser', 'filter-wheel', 'rotator', 'sequences', 'analytics']) {
    assert.match(h.doc.getElementById('stale-' + key).textContent,
      /Stale: 1m 10s since last update/,
      key + ' must age from the same verdict the header reached');
  }
});

// D4-4. Measured across a SIGTERM with the dashboard open on a live run: at
// +8 s / +18 s / +38 s / +68 s the banner read "Every value below is from then
// and may be wrong", the Run panel had gone to unknown/--/--, and seven
// sibling panels carried a "Stale: …" line — while the Sequences panel went on
// naming "M long night" as the Current target and the Analytics panel went on
// reporting 15 frames, neither of them marked at all. They were simply not on
// the clock: PANEL_KEYS never named them and the markup had no line for them
// to write into.
test('the Sequences and Analytics panels age like their siblings', () => {
  const now = Date.now();
  const h = linkState({
    unreachable: true,
    lastContactAt: now - 68000,
    lastWsMessageAt: now - 68000,
    lastProbeAt: now - 1000,
    panelLastUpdate: { sequences: now - 68000, analytics: now - 68000 },
  });
  for (const key of ['sequences', 'analytics']) {
    assert.match(h.doc.getElementById('stale-' + key).textContent,
      /Stale: 1m 8s since last update/,
      key + ' must say its data is as old as the header says it is');
  }
  // And the line has somewhere to land in the shipped markup.
  for (const id of ['stale-sequences', 'stale-analytics']) {
    assert.match(HTML, new RegExp('id="' + id + '"'),
      id + ' must exist in index.html or the wiring writes into nothing');
  }
});

// D4-4, second half. paintRunUnknown clears every other claim the two panels
// make about a run whose source has stopped answering — the badge, both
// progress bars, the ETA, the node, the message — and left the target alone,
// so "Current target: M long night" outlived all of them by 68 s.
test('a retired run leaves no target named either', () => {
  const now = Date.now();
  const h = linkState({
    unreachable: true,
    lastContactAt: now - 68000,
    lastWsMessageAt: now - 68000,
    lastProbeAt: now - 1000,
  });
  const target = h.doc.getElementById('ops-seq-current-target');
  target.textContent = 'M long night';
  h.render();
  assert.equal(target.textContent, '--',
    'the target is a claim about the run, and it dies with the run');
});

// Observed on screen during the fix's own re-reproduction: the Run panel had
// gone honest (UNKNOWN / -- / --) while the Sequences panel two columns away
// still read "Current node: Autofocus (HFR Degradation) / Progress 5%". Both
// quote the same cached status, and the ops panel is repainted by sibling
// fetches — the analytics summary, a slew, the first paint — that go on
// succeeding while the sequencer route refuses.
test('the ops mirror cannot repaint a run the clock has already retired', () => {
  const doc = makeDocument([
    'seq-status', 'seq-node', 'seq-message', 'seq-progress-text',
    'seq-progress-bar', 'seq-progress-bar-container',
    'ops-seq-current-target', 'ops-seq-current-node', 'ops-seq-progress-text',
    'ops-seq-progress-bar', 'ops-seq-progress-bar-container', 'ops-seq-eta',
  ]);
  const now = Date.now();
  const state = {
    // A live run, cached from the last answer that landed.
    sequencerStatus: {
      state: 'running',
      currentNodeName: 'Autofocus (HFR Degradation)',
      progress: 0.05,
      message: 'Autofocus: step 0/9 (37%)',
    },
    serverUnreachable: false,
    lastWsMessageAt: now - 200,
    // ...and a sequencer route that refused after it.
    panelLastUpdate: { sequencer: now - 45000 },
    panelLastFailure: { sequencer: now - 1000 },
    ops: { sessionSummary: null, sequenceStartedAt: now - 60000 },
  };
  const render = build(
    ['document', 'api', 'state', 'lastReachabilityProbeAt', 'renderBadge',
      'sequencerProgressPercent', 'formatDurationSeconds'],
    [
      konst('REACHABILITY_PROBE_MS'),
      konst('SERVER_HEARTBEAT_MS'),
      konst('MISSED_HEARTBEATS_BEFORE_STALE'),
      konst('SERVER_CONTACT_STALE_MS'),
      fn('lastServerContactAt'),
      fn('isServerContactStale'),
      fn('isPanelDataStale'),
      fn('runDataIsStale'),
      fn('markProgressUnknown'),
      fn('markProgressKnown'),
      fn('paintRunUnknown'),
      fn('renderOpsSequencerLoadPanel'),
    ],
    'renderOpsSequencerLoadPanel',
  )(
    doc,
    { lastContactAt: now - 200, isConnected: true, rateLimitRemainingSecs: 0 },
    state,
    now - 1000,
    (el, label, cls) => { el.textContent = label; el.className = cls; },
    (raw) => raw * 100,
    () => '3m',
  );
  render();

  assert.equal(doc.getElementById('ops-seq-current-node').textContent, '--',
    'the ops mirror must not name a node its source refused to confirm');
  assert.equal(doc.getElementById('ops-seq-progress-text').textContent, '--');
  assert.equal(doc.getElementById('ops-seq-eta').textContent, '--');
  assert.equal(
    doc.getElementById('ops-seq-progress-bar-container')
      .getAttribute('aria-valuenow'), null);
  // And it silences the Run panel with it, so the two can never disagree.
  assert.equal(doc.getElementById('seq-status').textContent, 'unknown');
  assert.equal(doc.getElementById('seq-node').textContent, '--');
});

// ---------------------------------------------------------------------------
// D4-3 — "Current target" names the target
// ---------------------------------------------------------------------------

/** Drive renderOpsSequencerLoadPanel with a healthy clock and one status. */
function opsLoadPanel(sequencerStatus, opsExtra) {
  const doc = makeDocument([
    'seq-status', 'seq-node', 'seq-message', 'seq-progress-text',
    'seq-progress-bar', 'seq-progress-bar-container',
    'ops-seq-current-target', 'ops-seq-current-node', 'ops-seq-progress-text',
    'ops-seq-progress-bar', 'ops-seq-progress-bar-container', 'ops-seq-eta',
  ]);
  const now = Date.now();
  const state = {
    sequencerStatus,
    serverUnreachable: false,
    lastWsMessageAt: now - 200,
    panelLastUpdate: { sequencer: now - 200 },
    panelLastFailure: {},
    ops: Object.assign({ sessionSummary: null, sequenceStartedAt: now - 60000 },
      opsExtra || {}),
  };
  const render = build(
    ['document', 'api', 'state', 'lastReachabilityProbeAt', 'renderBadge',
      'sequencerProgressPercent', 'formatDurationSeconds'],
    [
      konst('REACHABILITY_PROBE_MS'),
      konst('SERVER_HEARTBEAT_MS'),
      konst('MISSED_HEARTBEATS_BEFORE_STALE'),
      konst('SERVER_CONTACT_STALE_MS'),
      fn('lastServerContactAt'),
      fn('isServerContactStale'),
      fn('isPanelDataStale'),
      fn('runDataIsStale'),
      fn('markProgressUnknown'),
      fn('markProgressKnown'),
      fn('paintRunUnknown'),
      fn('renderOpsSequencerLoadPanel'),
    ],
    'renderOpsSequencerLoadPanel',
  )(
    doc,
    { lastContactAt: now - 200, isConnected: true, rateLimitRemainingSecs: 0 },
    state,
    now - 1000,
    (el, label, cls) => { el.textContent = label; el.className = cls; },
    (raw) => raw * 100,
    () => '3m',
  );
  render();
  return doc;
}

// Measured live against the release bundle: on a headless run whose
// TargetHeader names "D4 Web Target" inside a sequence called "D4 web live",
// the panel read "D4 web live" for every sample of the run — the imaging
// SESSION's name, which a headless start takes from the sequence. Once the run
// ended and /api/sessions/active answered {"session":null} the fallback named
// the Loop ROOT node and the field read "D4 root"; during an interval
// autofocus it read "Autofocus (HFR Degradation)".
test('Current target names the target, never the sequence or the node', () => {
  const doc = opsLoadPanel({
    state: 'running',
    currentNodeName: 'Exposure L',
    currentTarget: 'D4 Web Target',
    progress: 0.13,
    message: 'Exposure: Frame 5/40',
  }, { sessionSummary: { session: { id: 7, name: 'D4 web live' } } });
  assert.equal(doc.getElementById('ops-seq-current-target').textContent,
    'D4 Web Target');
  assert.equal(doc.getElementById('ops-seq-current-node').textContent,
    'Exposure L', 'the node keeps its own row');
});

test('a run that has named no target says so rather than guessing', () => {
  const doc = opsLoadPanel({
    state: 'running',
    currentNodeName: 'D4 root',
    currentTarget: null,
    progress: 0.13,
    message: null,
  }, { sessionSummary: { session: { id: 7, name: 'D4 web live' } } });
  assert.equal(doc.getElementById('ops-seq-current-target').textContent, '--',
    'an unknown target is "--", not the nearest string on the page');
});
