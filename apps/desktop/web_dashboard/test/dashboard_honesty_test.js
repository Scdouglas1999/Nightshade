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

/** Lift a top-level `const NAME = …;` line out of the IIFE. */
function konst(name) {
  const re = new RegExp('  const ' + name + ' = [^;]+;');
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

function linkState({ unreachable, lastContactAt, lastWsMessageAt,
  rateLimitRemainingSecs = 0, lastProbeAt = Date.now(), isConnected = true }) {
  const doc = makeDocument([
    'link-banner', 'status-text', 'status-dot', 'seq-status',
    'ops-seq-progress-text',
  ]);
  doc.getElementById('status-text').textContent = 'Connected';
  doc.getElementById('status-dot').className = 'status-dot connected';
  const calls = [];
  const render = build(
    ['document', 'api', 'state', 'lastReachabilityProbeAt',
      'setConnectionStatus', 'renderBadge'],
    [
      konst('SERVER_CONTACT_STALE_MS'),
      fn('lastServerContactAt'),
      fn('isServerContactStale'),
      fn('formatAgeSeconds'),
      fn('renderLinkState'),
    ],
    'renderLinkState',
  )(
    doc,
    { lastContactAt, isConnected, rateLimitRemainingSecs },
    { serverUnreachable: unreachable, lastWsMessageAt },
    lastProbeAt,
    (s) => { calls.push(s); },
    (el, label, cls) => { el.textContent = label; el.className = cls; },
  );
  render();
  return { doc, calls };
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

test('silence past the contact window is stale even without a failed probe', () => {
  const now = Date.now();
  const { doc } = linkState({
    unreachable: false,
    lastContactAt: now - 20000,
    lastWsMessageAt: now - 20000,
  });
  assert.equal(doc.getElementById('status-text').textContent, 'No contact');
  assert.match(doc.getElementById('link-banner').textContent,
    /No answer from the Nightshade server/);
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
  for (const name of ['renderSequencerPanel', 'renderOpsSequencerLoadPanel']) {
    const source = fn(name);
    assert.match(source, /removeAttribute\('aria-valuenow'\)/,
      name + ' must clear the value when status is unknown');
    assert.doesNotMatch(source, /setAttribute\('aria-valuenow', '0'\)/);
  }
});
