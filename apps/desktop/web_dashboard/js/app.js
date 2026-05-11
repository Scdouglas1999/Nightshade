/**
 * Nightshade Web Dashboard - Main Application
 *
 * Manages all dashboard panels: devices, camera, mount, sequencer, guiding, event log.
 * Connects to the headless API via REST polling and WebSocket events.
 */

(function () {
  'use strict';

  // =========================================================================
  // State
  // =========================================================================

  const state = {
    connectedDevices: [],
    allDevices: [],
    serverInfo: null,
    cameraDeviceId: '',
    mountDeviceId: '',
    focuserDeviceId: '',
    filterWheelDeviceId: '',
    lastImage: null,
    mountStatus: null,
    cameraStatus: null,
    sequencerStatus: null,
    guidingStatus: null,
    guideHistory: { ra: [], dec: [] },
    maxGuidePoints: 100,
    logEntries: [],
    maxLogEntries: 500,
    pollInterval: null,
    pingInterval: null,
    wsFallbackPollInterval: null,
    lastWsMessageAt: 0,
    panelLastUpdate: { devices: 0, mount: 0, camera: 0, sequencer: 0, guiding: 0 },
    staleCheckInterval: null,
    debugMode: false,
    pendingImageFetchTimer: null,
    pendingExposureExpectedBy: 0,
    activePhoneTab: 'panel-devices',
    dpadActiveButton: null,
    dpadActiveAxis: null,
    pressedKeys: new Set(),
    connectRetryCount: 0,
  };

  // Why a panel registry: §2.10 (stale indicators), §2.12 (per-panel enable),
  // and §2.13 (phone tab routing) all need a mapping from panel id to the
  // controlling device-type. Define it once.
  const PANEL_DEVICE_TYPES = {
    'panel-camera': 'camera',
    'panel-mount': 'mount',
  };

  // Phone tabs: which panels are accessible via the bottom tab bar on phones.
  const PHONE_PANELS = ['panel-devices', 'panel-mount', 'panel-camera',
                        'panel-sequencer', 'panel-log'];

  // §2.10 — if the WS has been silent for this long, fall back to REST polling.
  const WS_FALLBACK_THRESHOLD_MS = 10000;
  // Surface a stale-data badge on a panel after this much wall time since
  // its last successful update.
  const PANEL_STALE_THRESHOLD_MS = 10000;
  // §2.8 — image-fetch fallback if no exposure_complete event arrives.
  const IMAGE_FALLBACK_GRACE_MS = 30000;
  // §2.11 — cap on base64-decoded image size for display.
  const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

  // =========================================================================
  // Initialization
  // =========================================================================

  document.addEventListener('DOMContentLoaded', init);

  function init() {
    // Honour ?debug=1 in the URL to allow manual server URL entry. Why: §2.4
    // restricts the dashboard to its own origin; manual URL entry is a power-
    // user escape hatch and is hidden by default.
    state.debugMode = new URLSearchParams(window.location.search).get('debug') === '1';
    if (state.debugMode) {
      const urlInput = document.getElementById('server-url');
      urlInput.hidden = false;
      const label = document.getElementById('server-url-label');
      if (label) label.classList.remove('sr-only');
    }

    // Tokens never live in localStorage anymore (§2.5 long-form). The
    // "remember" path now goes through an HttpOnly `nightshade_session`
    // cookie that JS cannot read; the unchecked path keeps the bearer in
    // sessionStorage so it dies when the tab closes. The remember-checkbox
    // flag itself is benign metadata and stays in localStorage so the UI
    // state persists across reloads.
    const servedFromServer =
      window.location.protocol === 'http:' || window.location.protocol === 'https:';
    // §2.4 — initial server URL comes from window.location.origin only.
    // Debug mode allows overriding via localStorage; production cannot.
    let savedUrl = defaultServerUrl();
    if (state.debugMode) {
      const stored = normalizeServerUrl(localStorage.getItem('nightshade_url'));
      if (stored) savedUrl = stored;
    }
    const shouldAutoConnect = servedFromServer || (state.debugMode && !!savedUrl);
    const rememberToken = localStorage.getItem('nightshade_remember_token') === 'true';
    const savedToken = readStoredToken();
    const savedDeviceName = localStorage.getItem('nightshade_device_name') || defaultDeviceName();
    const savedDeviceId = localStorage.getItem('nightshade_device_id') || generateDeviceId();
    // One-shot scrub of any pre-§2.5-long-form token bytes that may still
    // sit in localStorage from an older install. We never write here
    // anymore; leaving the stale bytes would defeat the whole point.
    localStorage.removeItem('nightshade_token');

    document.getElementById('server-url').value = savedUrl;
    document.getElementById('auth-token').value = savedToken;
    document.getElementById('device-name').value = savedDeviceName;
    // Default OFF for remember-token (§2.5). The bearer is sessionStorage-only
    // unless the user opts in.
    document.getElementById('remember-token').checked = rememberToken;
    localStorage.setItem('nightshade_device_id', savedDeviceId);

    // Connect / pair buttons
    document.getElementById('btn-connect').addEventListener('click', () => handleConnect());
    document.getElementById('btn-pair').addEventListener('click', openPairModal);
    document.getElementById('btn-apply-token').addEventListener('click', () => handleConnect());
    document.getElementById('remember-token').addEventListener('change', handleRememberTokenChanged);

    // Pairing modal
    document.getElementById('btn-pair-cancel').addEventListener('click', closePairModal);
    document.getElementById('btn-pair-submit').addEventListener('click', handlePairSubmit);
    document.getElementById('pair-modal-code').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handlePairSubmit();
      if (e.key === 'Escape') closePairModal();
    });

    // Camera controls
    document.getElementById('btn-expose').addEventListener('click', handleExpose);
    document.getElementById('btn-abort-expose').addEventListener('click', handleAbortExpose);

    // Mount controls — press-and-hold d-pad (§2.7).
    setupDpad();
    document.getElementById('btn-mount-stop').addEventListener('click', handleMountStop);
    document.getElementById('btn-mount-park').addEventListener('click', handleMountPark);
    document.getElementById('btn-mount-unpark').addEventListener('click', handleMountUnpark);
    document.getElementById('btn-mount-tracking').addEventListener('click', handleMountToggleTracking);

    // Sequencer controls
    document.getElementById('btn-seq-start').addEventListener('click', handleSeqStart);
    document.getElementById('btn-seq-stop').addEventListener('click', handleSeqStop);
    document.getElementById('btn-seq-pause').addEventListener('click', handleSeqPause);
    document.getElementById('btn-seq-resume').addEventListener('click', handleSeqResume);

    // Guiding controls
    document.getElementById('btn-guide-start').addEventListener('click', handleGuideStart);
    document.getElementById('btn-guide-stop').addEventListener('click', handleGuideStop);

    // Log controls
    document.getElementById('btn-clear-log').addEventListener('click', clearLog);

    // Phone tabs (§2.13)
    for (const tab of document.querySelectorAll('.phone-tab')) {
      tab.addEventListener('click', () => activatePhoneTab(tab.dataset.target));
    }

    // Guide graph canvas
    setupGuideCanvas();
    setConnectionStatus('disconnected');

    // Phone layout — apply on load and on resize.
    applyResponsiveLayout();
    window.addEventListener('resize', applyResponsiveLayout);

    // Default: every action button disabled until we connect & enumerate
    // devices (§2.12).
    refreshPanelEnablement();

    // Auto-connect on load when served from the same origin (§2.4 + §2.16).
    if (shouldAutoConnect) {
      handleConnect();
    }
  }

  // =========================================================================
  // Connection
  // =========================================================================

  /**
   * Run the initial REST handshake with bounded exponential backoff (§2.16).
   * Three attempts at 250 ms, 1 s, 4 s. WebSocket has its own reconnect logic
   * and is not retried here.
   */
  async function handleConnect() {
    const url = normalizeServerUrl(document.getElementById('server-url').value);
    const token = document.getElementById('auth-token').value.trim();
    const rememberToken = document.getElementById('remember-token').checked;
    const deviceId = localStorage.getItem('nightshade_device_id') || generateDeviceId();

    if (!url) {
      showToast('Enter a valid http:// or https:// server URL', 'error');
      return;
    }

    document.getElementById('server-url').value = url;

    // Persist connection preferences; the bearer goes to sessionStorage
    // only — long-form persistence is the HttpOnly cookie path below.
    // Production mode (no debug flag) refuses to remember anything that
    // would override the same-origin URL (§2.4).
    if (state.debugMode) {
      localStorage.setItem('nightshade_url', url);
    } else {
      localStorage.removeItem('nightshade_url');
    }
    localStorage.setItem('nightshade_device_id', deviceId);
    writeStoredToken(token, rememberToken);

    api.configure(url, token, deviceId);
    api.setConnectionState(false);

    // §2.5 long-form: if a session cookie is still alive from a previous
    // visit, asking the server for the CSRF token is what tells JS "you
    // are already authenticated, no bearer needed." We do this BEFORE the
    // /api/status round-trip below so the same fetch can ride the cookie.
    // Only meaningful when no bearer was pasted (a fresh paste of a
    // token means the user explicitly wants the bearer path right now).
    if (!token) {
      try {
        const resumed = await api.tryResumeCookieSession();
        if (resumed) {
          addLogEntry('system', 'Resumed previous remembered session via HttpOnly cookie.');
        }
      } catch (_) {
        // tryResumeCookieSession swallows known no-session errors; any
        // unexpected exception is logged through the normal connect path
        // below when the first authenticated request fails.
      }
    }

    stopPolling();
    api.disconnectWebSocket();
    api.removeAllListeners();
    setConnectionStatus('connecting');

    // §2.16 — 3-attempt exponential backoff per audit. Pre-attempt sleeps:
    // 250 ms, 1 s, 4 s. The total delay budget is ~5 s, which matches the
    // user's mental model of "give it a moment" without making a healthy
    // server feel slow.
    const delays = [250, 1000, 4000];
    let lastError = null;
    for (let attempt = 0; attempt < delays.length; attempt++) {
      await sleep(delays[attempt]);
      state.connectRetryCount = attempt;
      updateConnectProgress(attempt + 1, delays.length);
      try {
        const info = await api.testConnection();
        state.serverInfo = info;

        if (info.authRequired) {
          document.getElementById('auth-bar').classList.remove('hidden');
        } else {
          document.getElementById('auth-bar').classList.add('hidden');
        }

        // A cookie session counts as authentication: tryResumeCookieSession
        // above may have populated api.hasSessionCookie even with no
        // typed-in bearer.
        if (info.authRequired && !token && !api.hasSessionCookie) {
          setConnectionStatus('disconnected');
          updateConnectProgress(0, 0);
          showToast(
            info.pairingSupported
              ? 'Click Pair to set up this browser, or paste a bearer token and click Apply.'
              : 'Server requires a bearer token. Paste one and click Apply.',
            'error',
          );
          return;
        }

        // The first authenticated request is the real connection gate.
        // /api/info is public and only confirms reachability.
        await api.getStatus();
        setConnectionStatus('connected');
        updateConnectProgress(0, 0);
        api.setConnectionState(true);

        // §2.5 long-form: if the user wants to be remembered AND we have a
        // bearer in hand AND we are not already on the cookie path, exchange
        // the bearer for an HttpOnly cookie so the next page load doesn't
        // need the bearer at all. Why after /api/status: we only commit to
        // a cookie once we've verified the bearer actually works against the
        // server's auth middleware.
        if (rememberToken && token && !api.hasSessionCookie) {
          try {
            await api.beginCookieSession();
            // Scrub the visible token input so a casual screen-share or
            // browser-back doesn't expose it after upgrade.
            document.getElementById('auth-token').value = '';
            sessionStorage.removeItem('nightshade_token');
            addLogEntry('system', 'Upgraded session to HttpOnly cookie (remember-me).');
          } catch (e) {
            // Surface the failure: silent fallback to the bearer path
            // would let the user think they were "remembered" when they
            // weren't — and CLAUDE.md prohibits silent fallbacks.
            addLogEntry('error', 'Cookie upgrade failed: ' + (e && e.message ? e.message : String(e)));
            showToast('Remember-me upgrade failed: ' + (e && e.message ? e.message : 'unknown'), 'error');
          }
        }

        addLogEntry('system', 'Connected to ' + info.name + ' v' + info.version);

        // Wire up event listeners *before* opening the socket so we never
        // miss the open/error/event signals fired during connect.
        setupEventListeners();
        // connectWebSocket is async (it requests a single-use ticket first).
        api.connectWebSocket().catch((err) => {
          addLogEntry('error', 'WebSocket connect failed: ' + err.message);
        });

        await fetchAllStatus();
        startPolling();
        return;
      } catch (e) {
        lastError = e;
        // Why log every attempt: opaque "Connection failed" with no retry trail
        // made transient flaps look like permanent failures.
        addLogEntry('error',
          'Connect attempt ' + (attempt + 1) + '/' + delays.length + ': ' + e.message);
      }
    }

    setConnectionStatus('disconnected');
    updateConnectProgress(0, 0);
    api.setConnectionState(false);
    showToast('Connection failed: ' + (lastError ? lastError.message : 'unknown'), 'error');
  }

  function updateConnectProgress(attempt, total) {
    const el = document.getElementById('connect-progress');
    if (!el) return;
    if (attempt > 0 && total > 0) {
      el.textContent = '(attempt ' + attempt + '/' + total + ')';
    } else {
      el.textContent = '';
    }
  }

  // =========================================================================
  // Pairing (§2.1)
  // =========================================================================

  function openPairModal() {
    const url = normalizeServerUrl(document.getElementById('server-url').value);
    if (!url) {
      showToast('Enter a valid server URL first', 'error');
      return;
    }
    document.getElementById('server-url').value = url;
    const modal = document.getElementById('pair-modal');
    modal.removeAttribute('hidden');
    modal.classList.add('visible');
    setPairModalStatus('Requesting a pairing code...', '');

    // Configure API for unauthenticated calls during the pairing handshake.
    const deviceId = localStorage.getItem('nightshade_device_id') || generateDeviceId();
    api.configure(url, '', deviceId);

    // Kick off pairing/start on open so the operator immediately sees a code
    // on the desktop console.
    api.pairingStart()
      .then((result) => {
        const exp = result && result.expiresInSeconds ? result.expiresInSeconds : 0;
        setPairModalStatus(
          'Code printed to the Nightshade desktop console. Expires in ~' +
          Math.max(1, Math.round(exp / 60)) + ' min.',
          'success',
        );
      })
      .catch((e) => {
        setPairModalStatus('Failed to start pairing: ' + e.message, 'error');
      });

    const codeInput = document.getElementById('pair-modal-code');
    codeInput.value = '';
    setTimeout(() => codeInput.focus(), 50);
  }

  function closePairModal() {
    const modal = document.getElementById('pair-modal');
    modal.classList.remove('visible');
    modal.setAttribute('hidden', '');
    setPairModalStatus('', '');
  }

  function setPairModalStatus(message, type) {
    const el = document.getElementById('pair-modal-status');
    if (!el) return;
    el.textContent = message;
    el.className = 'modal-status' + (type ? ' ' + type : '');
  }

  async function handlePairSubmit() {
    const url = normalizeServerUrl(document.getElementById('server-url').value);
    const code = document.getElementById('pair-modal-code').value.trim();
    const deviceName = document.getElementById('device-name').value.trim() || defaultDeviceName();
    const deviceId = localStorage.getItem('nightshade_device_id') || generateDeviceId();

    if (!url) {
      setPairModalStatus('Server URL is empty.', 'error');
      return;
    }
    if (!/^\d{6}$/.test(code)) {
      setPairModalStatus('Enter the 6-digit code shown on the desktop console.', 'error');
      return;
    }

    localStorage.setItem('nightshade_device_id', deviceId);
    localStorage.setItem('nightshade_device_name', deviceName);
    api.configure(url, '', deviceId);

    setPairModalStatus('Verifying...', '');
    try {
      const result = await api.pairWithCode(code, deviceName, deviceId);
      const token = result && result.token ? String(result.token) : '';
      if (!token) {
        throw new Error('Pairing completed without a token');
      }
      document.getElementById('auth-token').value = token;
      writeStoredToken(token, document.getElementById('remember-token').checked);
      setPairModalStatus('Paired. Connecting...', 'success');
      closePairModal();
      showToast('Pairing complete', 'success');
      await handleConnect();
    } catch (e) {
      // Server error codes per §2.1 brief — surface them as actionable text.
      let msg = e.message || 'Pairing failed';
      if (msg.includes('invalid_pairing_code')) {
        msg = 'Pairing code is not recognised. Check the code on the desktop console.';
      } else if (msg.includes('pairing_code_expired')) {
        msg = 'Pairing code expired. Click Pair again to request a new one.';
      } else if (msg.includes('pairing_code_already_used')) {
        msg = 'That code has already been claimed. Click Pair to start over.';
      } else if (msg.includes('429') || msg.includes('temporarily locked')) {
        msg = 'Too many failed attempts. Wait a moment before trying again.';
      }
      setPairModalStatus(msg, 'error');
      addLogEntry('error', 'Pairing failed: ' + e.message);
    }
  }

  function generateDeviceId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    // Why Math.random fallback is acceptable here: the device ID is a non-
    // secret correlation handle (used to match pairing requests with the
    // resulting token row), not a credential or signing key. Old browsers
    // without crypto.randomUUID still get a probabilistically unique value.
    return 'browser-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  }

  function readStoredToken() {
    // sessionStorage only (§2.5 long-form). The "remember" path no longer
    // stashes the bearer in JS-readable storage; it lives in an HttpOnly
    // cookie on the server side and is never legible to JS again.
    return sessionStorage.getItem('nightshade_token') || '';
  }

  function writeStoredToken(token, rememberToken) {
    // Remember the user's UI choice only. The actual "stay logged in
    // across tabs/restart" semantics now come from the HttpOnly cookie
    // set by POST /api/auth/cookie — see beginCookieSession() in api.js.
    localStorage.setItem('nightshade_remember_token', rememberToken ? 'true' : 'false');
    if (token) {
      sessionStorage.setItem('nightshade_token', token);
    } else {
      sessionStorage.removeItem('nightshade_token');
    }
    // Guard against any older code path that may have left a bearer in
    // localStorage. Clearing on every write makes the migration idempotent.
    localStorage.removeItem('nightshade_token');
  }

  function handleRememberTokenChanged() {
    const token = document.getElementById('auth-token').value.trim();
    const rememberToken = document.getElementById('remember-token').checked;
    writeStoredToken(token, rememberToken);
    // If the user just unticked Remember while a cookie session is live,
    // immediately revoke it so we don't keep an HttpOnly cookie around
    // that contradicts their stated preference. The fire-and-forget
    // promise is fine — failures only mean the cookie persists until its
    // natural expiry, which is no worse than the prior session.
    if (!rememberToken && api.hasSessionCookie) {
      api.endCookieSession().catch(() => {});
    }
  }

  function defaultDeviceName() {
    const host = window.location.hostname || 'browser';
    return 'Browser on ' + host;
  }

  function defaultServerUrl() {
    if (window.location.protocol === 'http:' || window.location.protocol === 'https:') {
      return window.location.origin;
    }
    return 'http://127.0.0.1:8080';
  }

  function normalizeServerUrl(value) {
    const raw = String(value || '').trim();
    if (!raw) return '';
    try {
      const url = new URL(raw);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return '';
      if (!url.hostname) return '';
      url.pathname = url.pathname.replace(/\/+$/, '');
      url.search = '';
      url.hash = '';
      return url.toString().replace(/\/$/, '');
    } catch (_) {
      return '';
    }
  }

  function setConnectionStatus(status) {
    const dot = document.getElementById('status-dot');
    const text = document.getElementById('status-text');
    dot.className = 'status-dot';
    if (status === 'connected') {
      dot.classList.add('connected');
      text.textContent = 'Connected';
    } else if (status === 'connecting') {
      dot.classList.add('connecting');
      text.textContent = 'Connecting...';
    } else {
      text.textContent = 'Disconnected';
    }
    refreshPanelEnablement();
  }

  /**
   * §2.12 — per-panel enable based on the connected-devices payload. Buttons
   * inside a panel are only clickable when (a) the dashboard is connected to
   * the server *and* (b) a device of the panel's type is connected.
   *
   * The clear-log button is exempt because it operates on local state.
   */
  function refreshPanelEnablement() {
    const connected = api.isConnected;
    for (const [panelId, deviceType] of Object.entries(PANEL_DEVICE_TYPES)) {
      const panel = document.getElementById(panelId);
      if (!panel) continue;
      const hasDevice = connected && state.connectedDevices.some(
        (d) => d.deviceType === deviceType,
      );
      setPanelEnabled(panel, deviceType, hasDevice);
    }

    // Sequencer/guiding/devices panels: enable iff connected. They don't
    // require a specific device of their own.
    for (const id of ['panel-sequencer', 'panel-guiding']) {
      const panel = document.getElementById(id);
      if (panel) setPanelEnabled(panel, null, connected);
    }

    // Top-level connect button is always usable.
    document.getElementById('btn-connect').disabled = false;
    document.getElementById('btn-clear-log').disabled = false;
    document.getElementById('btn-pair').disabled = false;
    document.getElementById('btn-apply-token').disabled = false;
  }

  function setPanelEnabled(panelEl, deviceType, enabled) {
    if (!panelEl) return;
    panelEl.setAttribute('aria-disabled', enabled ? 'false' : 'true');
    const tooltip = enabled ? '' : (deviceType
      ? humanDeviceType(deviceType) + ' not connected'
      : 'Connect to the server first');
    const buttons = panelEl.querySelectorAll('button');
    for (const btn of buttons) {
      // §2.7 — d-pad emergency Stop is always usable when connected even if
      // no mount is currently reported. Better a no-op than a runaway slew
      // that can't be cancelled.
      if (btn.id === 'btn-mount-stop') {
        btn.disabled = !api.isConnected;
        continue;
      }
      btn.disabled = !enabled;
      if (tooltip) btn.title = tooltip; else btn.removeAttribute('title');
    }
    const inputs = panelEl.querySelectorAll('input, select');
    for (const input of inputs) {
      input.disabled = !enabled;
    }
  }

  function humanDeviceType(t) {
    switch (t) {
      case 'camera': return 'Camera';
      case 'mount': return 'Mount';
      case 'focuser': return 'Focuser';
      case 'filterWheel': return 'Filter wheel';
      default: return t;
    }
  }

  function setupEventListeners() {
    api.on('ws:connected', () => {
      state.lastWsMessageAt = Date.now();
      addLogEntry('system', 'WebSocket connected');
    });

    api.on('ws:disconnected', () => {
      addLogEntry('system', 'WebSocket disconnected, reconnecting...');
    });

    api.on('event', (data) => {
      state.lastWsMessageAt = Date.now();
      handleServerEvent(data);
    });
  }

  // =========================================================================
  // Polling — WebSocket-driven by default, REST fallback only when stale.
  // §2.10: drop the unconditional 3 s poll loop.
  // =========================================================================

  function startPolling() {
    stopPolling();

    // Initial refresh so panels populate immediately on connect — WS events
    // arrive only when something changes.
    fetchAllStatus();

    state.pingInterval = setInterval(() => api.sendPing(), 30000);

    // Why a slow watchdog instead of a 3 s poll: WS pushes carry the panel
    // state. We only re-fetch when the socket has been silent for
    // WS_FALLBACK_THRESHOLD_MS — i.e., the socket is dead or the server
    // dropped events. The watchdog also drives the stale-data indicator.
    state.staleCheckInterval = setInterval(checkStaleness, 2000);
  }

  function stopPolling() {
    if (state.pollInterval) {
      clearInterval(state.pollInterval);
      state.pollInterval = null;
    }
    if (state.pingInterval) {
      clearInterval(state.pingInterval);
      state.pingInterval = null;
    }
    if (state.wsFallbackPollInterval) {
      clearInterval(state.wsFallbackPollInterval);
      state.wsFallbackPollInterval = null;
    }
    if (state.staleCheckInterval) {
      clearInterval(state.staleCheckInterval);
      state.staleCheckInterval = null;
    }
  }

  function checkStaleness() {
    const now = Date.now();
    const wsSilentMs = state.lastWsMessageAt > 0 ? now - state.lastWsMessageAt : Infinity;

    // Fallback polling: only when WS has been silent past the threshold.
    if (api.isConnected && wsSilentMs > WS_FALLBACK_THRESHOLD_MS) {
      if (!state.wsFallbackPollInterval) {
        addLogEntry('system',
          'WebSocket silent for ' + Math.round(wsSilentMs / 1000) +
          's — falling back to REST polling');
        state.wsFallbackPollInterval = setInterval(fetchAllStatus, 5000);
        // Immediate one-shot so the user doesn't wait 5s for the next tick.
        fetchAllStatus();
      }
    } else if (state.wsFallbackPollInterval) {
      // WS came back. Drop the polling loop.
      clearInterval(state.wsFallbackPollInterval);
      state.wsFallbackPollInterval = null;
      addLogEntry('system', 'WebSocket recovered — REST fallback disabled');
    }

    // Per-panel stale indicator: highlight any panel whose last data update
    // is older than the threshold.
    updateStaleIndicator('devices');
    updateStaleIndicator('mount');
    updateStaleIndicator('camera');
    updateStaleIndicator('sequencer');
    updateStaleIndicator('guiding');
  }

  function updateStaleIndicator(panelKey) {
    const el = document.getElementById('stale-' + panelKey);
    if (!el) return;
    const last = state.panelLastUpdate[panelKey];
    if (!last || !api.isConnected) {
      el.classList.remove('visible');
      el.textContent = '';
      return;
    }
    const ageMs = Date.now() - last;
    if (ageMs > PANEL_STALE_THRESHOLD_MS) {
      el.classList.add('visible');
      el.textContent = 'Stale: ' + Math.round(ageMs / 1000) + 's since last update';
    } else {
      el.classList.remove('visible');
      el.textContent = '';
    }
  }

  function markPanelFresh(panelKey) {
    state.panelLastUpdate[panelKey] = Date.now();
  }

  // =========================================================================
  // Data fetching
  // =========================================================================

  async function fetchAllStatus() {
    await Promise.all([
      fetchDevices(),
      fetchSequencerStatus(),
      fetchGuidingStatus(),
      fetchMountStatusIfConnected(),
      fetchCameraStatusIfConnected(),
    ]);
  }

  async function fetchDevices() {
    try {
      const result = await api.getConnectedDevices();
      state.connectedDevices = result.devices || [];

      // §2.4 hint: connected-devices may carry discoveryErrors. Surface them
      // once per call in the log to avoid silent driver failures.
      if (result.discoveryErrors && typeof result.discoveryErrors === 'object') {
        for (const [dt, err] of Object.entries(result.discoveryErrors)) {
          addLogEntry('error', 'Discovery error (' + dt + '): ' + err);
        }
      }

      renderDevicesPanel();
      markPanelFresh('devices');

      // Auto-select device IDs from connected devices.
      for (const dev of state.connectedDevices) {
        switch (dev.deviceType) {
          case 'camera': state.cameraDeviceId = dev.id; break;
          case 'mount': state.mountDeviceId = dev.id; break;
          case 'focuser': state.focuserDeviceId = dev.id; break;
          case 'filterWheel': state.filterWheelDeviceId = dev.id; break;
        }
      }
      refreshPanelEnablement();
    } catch (e) {
      // §2.10 — surface fetch errors via the panel stale indicator instead of
      // swallowing them silently. Stale check will pick this up by virtue of
      // panelLastUpdate.devices not being refreshed.
      addLogEntry('error', 'Devices fetch failed: ' + e.message);
    }
  }

  async function fetchSequencerStatus() {
    try {
      const status = await api.sequencerGetStatus();
      state.sequencerStatus = status;
      renderSequencerPanel();
      markPanelFresh('sequencer');
    } catch (e) {
      addLogEntry('error', 'Sequencer fetch failed: ' + e.message);
    }
  }

  async function fetchGuidingStatus() {
    try {
      const status = await api.phd2GetStatus();
      state.guidingStatus = status;
      renderGuidingPanel();
      markPanelFresh('guiding');
    } catch (e) {
      addLogEntry('error', 'Guiding fetch failed: ' + e.message);
    }
  }

  async function fetchMountStatusIfConnected() {
    if (!state.mountDeviceId) return;
    try {
      const status = await api.getMountStatus(state.mountDeviceId);
      state.mountStatus = status;
      renderMountPanel();
      markPanelFresh('mount');
    } catch (e) {
      addLogEntry('error', 'Mount status fetch failed: ' + e.message);
    }
  }

  async function fetchCameraStatusIfConnected() {
    if (!state.cameraDeviceId) return;
    try {
      const status = await api.getCameraStatus(state.cameraDeviceId);
      state.cameraStatus = status;
      renderCameraStatusInfo();
      markPanelFresh('camera');
    } catch (e) {
      addLogEntry('error', 'Camera status fetch failed: ' + e.message);
    }
  }

  // =========================================================================
  // Server events (WebSocket)
  // =========================================================================

  function handleServerEvent(data) {
    const category = data.category || data.event_category || 'system';
    const message = data.message || data.description || messageFromPayload(data);

    addLogEntry(category, message);

    // §2.10 — drive panel state from WS events first; only fall back to
    // REST when an event is too coarse to update the panel.
    if (category === 'camera' || category === 'imaging') {
      const eventType = data.eventType || data.event || '';
      // For temperature/cooling updates we still need a REST round-trip
      // because the WS event only carries the delta, not the full snapshot.
      if (eventType === 'TemperatureChanged' || eventType === 'ExposureProgress'
          || eventType === 'ExposureStarted' || eventType === 'ExposureStartedWithFrame') {
        fetchCameraStatusIfConnected();
      }
      // §2.8 — image fetch is *only* driven by completion events. The legacy
      // setTimeout((exposureTime+2)*1000) fallback has been removed.
      if (isExposureCompleteEvent(eventType)) {
        cancelPendingImageFetch();
        fetchLastImage();
      }
      markPanelFresh('camera');
    } else if (category === 'mount') {
      fetchMountStatusIfConnected();
    } else if (category === 'sequencer') {
      fetchSequencerStatus();
    } else if (category === 'guiding' || category === 'phd2') {
      const eventType = data.eventType || data.event || '';
      // §2.14 — canonical field names for guide-step coordinates are raPx
      // / decPx. The server emitter now publishes these alongside legacy
      // names; we accept either so we work across server versions during
      // the deployment transition.
      const payload = data.data || data;
      const guide = extractGuideStep(payload);
      if (guide) {
        addGuideDataPoint(guide.raPx, guide.decPx);
      }
      // Full status snapshots need a REST round-trip because the WS event
      // doesn't carry the rolling RMS or app state.
      if (eventType === 'GuidingStarted' || eventType === 'GuidingStopped'
          || eventType === 'Settled' || eventType === 'Settling'
          || eventType === 'AppState' || eventType === 'Connected'
          || eventType === 'Disconnected') {
        fetchGuidingStatus();
      }
      markPanelFresh('guiding');
    } else if (category === 'equipment') {
      // Equipment connect/disconnect changes the per-panel availability set.
      fetchDevices();
    }
  }

  function isExposureCompleteEvent(eventType) {
    if (!eventType) return false;
    return eventType === 'exposure_complete' || eventType === 'ExposureComplete'
        || eventType === 'image_ready' || eventType === 'ImageReady'
        || eventType === 'ExposureCompleted' || eventType === 'ExposureCompletedWithFrame';
  }

  function extractGuideStep(payload) {
    if (!payload || typeof payload !== 'object') return null;
    // Canonical (§2.14): raPx, decPx.
    if (payload.raPx !== undefined && payload.decPx !== undefined) {
      return { raPx: Number(payload.raPx), decPx: Number(payload.decPx) };
    }
    // Backend currently emits RADistanceRaw/DECDistanceRaw inside the event
    // `data` payload. Accept both so we work whether the backend has been
    // updated yet or not.
    if (payload.RADistanceRaw !== undefined && payload.DECDistanceRaw !== undefined) {
      return {
        raPx: Number(payload.RADistanceRaw),
        decPx: Number(payload.DECDistanceRaw),
      };
    }
    // Legacy camelCase that the dashboard *thought* it was receiving (§2.14
    // root cause). Keep accepting for backward compatibility.
    if (payload.raDistance !== undefined && payload.decDistance !== undefined) {
      return {
        raPx: Number(payload.raDistance),
        decPx: Number(payload.decDistance),
      };
    }
    return null;
  }

  function messageFromPayload(data) {
    const t = data.eventType || data.event || data.type;
    if (t) return String(t);
    return JSON.stringify(data);
  }

  // =========================================================================
  // Camera Controls
  // =========================================================================

  async function handleExpose() {
    if (!state.cameraDeviceId) {
      showToast('No camera connected', 'error');
      return;
    }

    const exposureTime = parseFloat(document.getElementById('exposure-time').value);
    const gain = parseInt(document.getElementById('camera-gain').value, 10);
    const binning = parseInt(document.getElementById('camera-binning').value, 10);

    if (isNaN(exposureTime) || exposureTime <= 0) {
      showToast('Invalid exposure time', 'error');
      return;
    }

    try {
      await api.cameraExpose(state.cameraDeviceId, exposureTime, {
        gain: isNaN(gain) ? undefined : gain,
        binX: binning || 1,
        binY: binning || 1,
      });
      addLogEntry('camera', 'Exposure started: ' + exposureTime + 's');
      showToast('Exposure started');

      // §2.8 — replace the unconditional setTimeout((exposureTime+2)*1000)
      // image fetch with an event-driven one. We arm a single fallback timer
      // for (exposureTime + IMAGE_FALLBACK_GRACE_MS) so a missing
      // exposure_complete event doesn't strand the operator with no preview.
      scheduleImageFetchFallback(exposureTime);
    } catch (e) {
      showToast('Expose failed: ' + e.message, 'error');
      addLogEntry('error', 'Expose failed: ' + e.message);
    }
  }

  function scheduleImageFetchFallback(exposureTime) {
    cancelPendingImageFetch();
    const waitMs = (exposureTime * 1000) + IMAGE_FALLBACK_GRACE_MS;
    state.pendingExposureExpectedBy = Date.now() + waitMs;
    state.pendingImageFetchTimer = setTimeout(() => {
      state.pendingImageFetchTimer = null;
      // One-shot fallback only — if the WS event arrives between scheduling
      // and now, handleServerEvent already cancelled the timer.
      addLogEntry('system',
        'No exposure_complete event after ' + Math.round(waitMs / 1000) +
        's; fetching last image as fallback');
      fetchLastImage();
    }, waitMs);
  }

  function cancelPendingImageFetch() {
    if (state.pendingImageFetchTimer) {
      clearTimeout(state.pendingImageFetchTimer);
      state.pendingImageFetchTimer = null;
    }
    state.pendingExposureExpectedBy = 0;
  }

  async function handleAbortExpose() {
    if (!state.cameraDeviceId) return;
    try {
      await api.cameraAbort(state.cameraDeviceId);
      cancelPendingImageFetch();
      addLogEntry('camera', 'Exposure aborted');
    } catch (e) {
      showToast('Abort failed: ' + e.message, 'error');
    }
  }

  async function fetchLastImage() {
    if (!state.cameraDeviceId) return;
    try {
      const result = await api.cameraGetLastImage(state.cameraDeviceId);
      if (result && result.image) {
        state.lastImage = result.image;
        await renderImagePreview();
      }
    } catch (e) {
      addLogEntry('error', 'Failed to fetch last image: ' + e.message);
    }
  }

  // =========================================================================
  // Mount Controls — press-and-hold d-pad (§2.7)
  // =========================================================================

  function setupDpad() {
    const dpad = document.getElementById('mount-dpad');
    if (!dpad) return;

    const buttons = dpad.querySelectorAll('button.dpad-btn');
    for (const btn of buttons) {
      btn.addEventListener('pointerdown', onDpadPointerDown);
      btn.addEventListener('pointerup', onDpadPointerStop);
      btn.addEventListener('pointerleave', onDpadPointerStop);
      btn.addEventListener('pointercancel', onDpadPointerStop);
      // Why prevent click: pointerdown already starts the slew. Letting the
      // browser fire a synthetic click on touch devices would re-issue a
      // mountMoveAxis(...rate) with no matching stop and re-create the §2.7
      // runaway-slew bug.
      btn.addEventListener('click', (e) => e.preventDefault());
      // Stop touch from scrolling the page when the user holds a button.
      btn.addEventListener('touchstart', (e) => e.preventDefault(), { passive: false });
    }

    // §2.15 — keyboard arrow keys move the axis while the d-pad container
    // has focus. We require explicit focus (tabindex on the container) to
    // avoid hijacking page-wide scrolling.
    dpad.addEventListener('keydown', onDpadKeyDown);
    dpad.addEventListener('keyup', onDpadKeyUp);
    dpad.addEventListener('focus', () => dpad.classList.add('dpad-keyboard-active'));
    dpad.addEventListener('blur', () => {
      dpad.classList.remove('dpad-keyboard-active');
      // Safety: releasing focus must release any held axis.
      stopAllDpadMotion();
      state.pressedKeys.clear();
    });
  }

  function onDpadPointerDown(e) {
    const btn = e.currentTarget;
    const axis = parseInt(btn.dataset.axis, 10);
    const direction = parseInt(btn.dataset.direction, 10);
    if (isNaN(axis) || isNaN(direction)) return;
    // Pointer capture ensures the matching pointerup fires on this element
    // even if the finger / cursor drifts off it.
    try { btn.setPointerCapture(e.pointerId); } catch (_) { /* not supported */ }
    state.dpadActiveButton = btn;
    state.dpadActiveAxis = axis;
    btn.classList.add('active');
    handleMountMoveStart(axis, direction);
  }

  function onDpadPointerStop(e) {
    const btn = e.currentTarget;
    btn.classList.remove('active');
    if (state.dpadActiveButton === btn) {
      const axis = state.dpadActiveAxis;
      state.dpadActiveButton = null;
      state.dpadActiveAxis = null;
      if (axis !== null && axis !== undefined) {
        handleMountMoveStop(axis);
      }
    }
  }

  function onDpadKeyDown(e) {
    const map = {
      'ArrowUp':    { axis: 1, direction:  1, btn: 'btn-mount-n' },
      'ArrowDown':  { axis: 1, direction: -1, btn: 'btn-mount-s' },
      'ArrowLeft':  { axis: 0, direction: -1, btn: 'btn-mount-w' },
      'ArrowRight': { axis: 0, direction:  1, btn: 'btn-mount-e' },
    };
    const m = map[e.key];
    if (!m) return;
    e.preventDefault();
    if (state.pressedKeys.has(e.key)) return; // ignore key-repeat
    state.pressedKeys.add(e.key);
    const btn = document.getElementById(m.btn);
    if (btn) btn.classList.add('active');
    handleMountMoveStart(m.axis, m.direction);
  }

  function onDpadKeyUp(e) {
    const map = {
      'ArrowUp':    { axis: 1, btn: 'btn-mount-n' },
      'ArrowDown':  { axis: 1, btn: 'btn-mount-s' },
      'ArrowLeft':  { axis: 0, btn: 'btn-mount-w' },
      'ArrowRight': { axis: 0, btn: 'btn-mount-e' },
    };
    const m = map[e.key];
    if (!m) return;
    e.preventDefault();
    state.pressedKeys.delete(e.key);
    const btn = document.getElementById(m.btn);
    if (btn) btn.classList.remove('active');
    handleMountMoveStop(m.axis);
  }

  function stopAllDpadMotion() {
    if (!state.mountDeviceId) return;
    api.mountMoveAxis(state.mountDeviceId, 0, 0).catch(() => {});
    api.mountMoveAxis(state.mountDeviceId, 1, 0).catch(() => {});
  }

  async function handleMountMoveStart(axis, direction) {
    if (!state.mountDeviceId) {
      showToast('No mount connected', 'error');
      return;
    }
    const speedSelect = document.getElementById('slew-speed');
    const rate = parseFloat(speedSelect.value) * direction;
    try {
      await api.mountMoveAxis(state.mountDeviceId, axis, rate);
    } catch (e) {
      showToast('Mount move failed: ' + e.message, 'error');
    }
  }

  async function handleMountMoveStop(axis) {
    if (!state.mountDeviceId) return;
    try {
      await api.mountMoveAxis(state.mountDeviceId, axis, 0);
    } catch (e) {
      showToast('Mount stop failed: ' + e.message, 'error');
    }
  }

  async function handleMountStop() {
    if (!state.mountDeviceId) return;
    try {
      // Stop both axes then issue a hard abort. Order matters: abort can
      // interrupt MoveAxis on drivers that queue the requests.
      await api.mountMoveAxis(state.mountDeviceId, 0, 0);
      await api.mountMoveAxis(state.mountDeviceId, 1, 0);
      await api.mountAbort(state.mountDeviceId);
      addLogEntry('mount', 'Mount stopped');
    } catch (e) {
      showToast('Mount stop failed: ' + e.message, 'error');
    }
  }

  async function handleMountPark() {
    if (!state.mountDeviceId) return;
    try {
      await api.mountPark(state.mountDeviceId);
      addLogEntry('mount', 'Parking mount');
      showToast('Parking mount');
    } catch (e) {
      showToast('Park failed: ' + e.message, 'error');
    }
  }

  async function handleMountUnpark() {
    if (!state.mountDeviceId) return;
    try {
      await api.mountUnpark(state.mountDeviceId);
      addLogEntry('mount', 'Unparking mount');
      showToast('Mount unparked');
    } catch (e) {
      showToast('Unpark failed: ' + e.message, 'error');
    }
  }

  async function handleMountToggleTracking() {
    if (!state.mountDeviceId) return;
    const isTracking = state.mountStatus && state.mountStatus.isTracking;
    try {
      await api.mountSetTracking(state.mountDeviceId, !isTracking);
      addLogEntry('mount', 'Tracking ' + (isTracking ? 'disabled' : 'enabled'));
    } catch (e) {
      showToast('Tracking toggle failed: ' + e.message, 'error');
    }
  }

  // =========================================================================
  // Sequencer Controls
  // =========================================================================

  async function handleSeqStart() {
    try {
      await api.sequencerStart();
      addLogEntry('sequencer', 'Sequence started');
      showToast('Sequence started');
    } catch (e) {
      showToast('Start failed: ' + e.message, 'error');
    }
  }

  async function handleSeqStop() {
    try {
      await api.sequencerStop();
      addLogEntry('sequencer', 'Sequence stopped');
    } catch (e) {
      showToast('Stop failed: ' + e.message, 'error');
    }
  }

  async function handleSeqPause() {
    try {
      await api.sequencerPause();
      addLogEntry('sequencer', 'Sequence paused');
    } catch (e) {
      showToast('Pause failed: ' + e.message, 'error');
    }
  }

  async function handleSeqResume() {
    try {
      await api.sequencerResume();
      addLogEntry('sequencer', 'Sequence resumed');
    } catch (e) {
      showToast('Resume failed: ' + e.message, 'error');
    }
  }

  // =========================================================================
  // Guiding Controls
  // =========================================================================

  async function handleGuideStart() {
    try {
      await api.phd2StartGuiding();
      addLogEntry('guiding', 'Guiding started');
      showToast('Guiding started');
    } catch (e) {
      showToast('Guide start failed: ' + e.message, 'error');
    }
  }

  async function handleGuideStop() {
    try {
      await api.phd2StopGuiding();
      addLogEntry('guiding', 'Guiding stopped');
    } catch (e) {
      showToast('Guide stop failed: ' + e.message, 'error');
    }
  }

  // =========================================================================
  // Rendering: Devices Panel
  // =========================================================================

  function renderDevicesPanel() {
    const container = document.getElementById('devices-list');
    if (!container) return;

    clearElement(container);
    if (state.connectedDevices.length === 0) {
      container.appendChild(createEmptyState('No devices connected'));
      return;
    }

    // Group by device type
    const groups = {};
    for (const dev of state.connectedDevices) {
      const type = dev.deviceType || 'unknown';
      if (!groups[type]) groups[type] = [];
      groups[type].push(dev);
    }

    const typeLabels = {
      camera: 'Cameras',
      mount: 'Mounts',
      focuser: 'Focusers',
      filterWheel: 'Filter Wheels',
      rotator: 'Rotators',
      guider: 'Guiders',
      dome: 'Domes',
      safetyMonitor: 'Safety Monitors',
      switch_: 'Switches',
      coverCalibrator: 'Cover Calibrators',
    };

    for (const [type, devices] of Object.entries(groups)) {
      const label = typeLabels[type] || type.charAt(0).toUpperCase() + type.slice(1);
      const groupEl = document.createElement('div');
      groupEl.className = 'device-group';
      const labelEl = document.createElement('div');
      labelEl.className = 'device-group-label';
      labelEl.textContent = label;
      groupEl.appendChild(labelEl);

      for (const dev of devices) {
        const itemEl = document.createElement('div');
        itemEl.className = 'device-item';
        const nameEl = document.createElement('span');
        nameEl.className = 'device-name';
        const statusIconEl = document.createElement('span');
        statusIconEl.className = 'device-status-icon connected';
        statusIconEl.setAttribute('aria-hidden', 'true');
        nameEl.appendChild(statusIconEl);
        nameEl.appendChild(document.createTextNode(' ' + (dev.name || dev.id || 'Unknown device')));

        const badgeEl = document.createElement('span');
        badgeEl.className = 'badge badge-running';
        badgeEl.textContent = dev.driverType || '';

        itemEl.appendChild(nameEl);
        itemEl.appendChild(badgeEl);
        groupEl.appendChild(itemEl);
      }
      container.appendChild(groupEl);
    }
  }

  // =========================================================================
  // Rendering: Camera Panel
  // =========================================================================

  async function renderImagePreview() {
    const container = document.getElementById('image-preview');
    const statsContainer = document.getElementById('image-stats');
    if (!container || !statsContainer) return;

    clearElement(container);
    clearElement(statsContainer);

    if (!state.lastImage) {
      container.appendChild(createImagePlaceholder('No image captured yet'));
      return;
    }

    const img = state.lastImage;

    // §2.11 — cap base64 image at 2 MiB and decode off the main thread with
    // createImageBitmap. Larger preview blobs would pin the main thread for
    // tens to hundreds of milliseconds on phones.
    const blob = decodeBase64ImageWithCap(img.displayData);
    if (!blob) {
      const placeholder = createImagePlaceholder(
        img.displayData && img.displayData.length
          ? 'Image too large for preview (max 2 MiB). Request a downsampled variant from the server.'
          : 'Image data not available',
      );
      container.appendChild(placeholder);
    } else {
      try {
        const bitmap = await createImageBitmap(blob);
        const canvas = document.createElement('canvas');
        canvas.width = bitmap.width;
        canvas.height = bitmap.height;
        canvas.style.maxWidth = '100%';
        canvas.style.maxHeight = '200px';
        canvas.style.objectFit = 'contain';
        canvas.setAttribute('aria-label', 'Last capture preview');
        const ctx = canvas.getContext('2d');
        ctx.drawImage(bitmap, 0, 0);
        bitmap.close();
        container.appendChild(canvas);
      } catch (e) {
        addLogEntry('error', 'Image decode failed: ' + e.message);
        container.appendChild(createImagePlaceholder('Failed to decode image'));
      }
    }

    // Render image stats
    if (img.stats) {
      const stats = [
        { label: 'HFR', value: img.stats.hfr != null ? img.stats.hfr.toFixed(2) : '--' },
        { label: 'Stars', value: img.stats.starCount != null ? img.stats.starCount : '--' },
        { label: 'Mean', value: img.stats.mean != null ? img.stats.mean.toFixed(0) : '--' },
        { label: 'Median', value: img.stats.median != null ? img.stats.median.toFixed(0) : '--' },
        { label: 'StdDev', value: img.stats.stdDev != null ? img.stats.stdDev.toFixed(0) : '--' },
        { label: 'Size', value: img.width + 'x' + img.height },
      ];
      for (const s of stats) {
        const itemEl = document.createElement('div');
        itemEl.className = 'image-stat';
        const labelEl = document.createElement('span');
        labelEl.className = 'image-stat-label';
        labelEl.textContent = s.label;
        const valueEl = document.createElement('span');
        valueEl.className = 'image-stat-value';
        valueEl.textContent = String(s.value);
        itemEl.appendChild(labelEl);
        itemEl.appendChild(valueEl);
        statsContainer.appendChild(itemEl);
      }
    }
  }

  /**
   * §2.11 — validate a base64 string, enforce 2 MiB cap, and decode to a Blob
   * so createImageBitmap can run off the main thread. Returns null when the
   * data is missing, malformed, or too large.
   */
  function decodeBase64ImageWithCap(b64) {
    if (!b64 || typeof b64 !== 'string') return null;
    // Each 4 chars of base64 decode to 3 bytes; this estimate is enough to
    // reject obviously-oversized inputs before we allocate.
    const approxBytes = Math.floor(b64.length * 3 / 4);
    if (approxBytes > MAX_IMAGE_BYTES) return null;
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(b64)) return null;
    try {
      const binary = atob(b64);
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
      }
      // PNG and JPEG both work as image/* — the browser sniffs the magic
      // bytes. Use image/png since the server documents this as PNG/JPEG.
      return new Blob([bytes], { type: 'image/png' });
    } catch (_) {
      return null;
    }
  }

  function renderCameraStatusInfo() {
    const el = document.getElementById('camera-status-info');
    if (!el) return;

    clearElement(el);
    if (!state.cameraStatus) {
      return;
    }

    const cs = state.cameraStatus;

    if (cs.cameraState !== undefined) {
      el.appendChild(createStatusRow('State', String(cs.cameraState)));
    }
    if (cs.ccdTemperature !== undefined) {
      const tempClass = cs.ccdTemperature <= -10 ? 'good' : cs.ccdTemperature <= 0 ? 'warn' : 'error';
      el.appendChild(createStatusRow('Temp', cs.ccdTemperature.toFixed(1) + ' C', tempClass));
    }
    if (cs.coolerPower !== undefined) {
      el.appendChild(createStatusRow('Cooler', cs.coolerPower.toFixed(0) + '%'));
    }
    if (cs.percentCompleted !== undefined && cs.percentCompleted > 0) {
      el.appendChild(createStatusRow('Exposure', cs.percentCompleted.toFixed(0) + '%', 'info'));
    }
  }

  // =========================================================================
  // Rendering: Mount Panel
  // =========================================================================

  function renderMountPanel() {
    if (!state.mountStatus) return;

    const ms = state.mountStatus;

    // RA/Dec display
    const raEl = document.getElementById('mount-ra');
    const decEl = document.getElementById('mount-dec');
    if (raEl && ms.rightAscension !== undefined) {
      raEl.textContent = formatRA(ms.rightAscension);
    }
    if (decEl && ms.declination !== undefined) {
      decEl.textContent = formatDec(ms.declination);
    }

    // Tracking status
    const trackBtn = document.getElementById('btn-mount-tracking');
    if (trackBtn && ms.isTracking !== undefined) {
      trackBtn.textContent = ms.isTracking ? 'Tracking ON' : 'Tracking OFF';
      trackBtn.className = ms.isTracking ? 'btn btn-sm btn-success' : 'btn btn-sm';
    }

    // Slewing indicator
    const slewEl = document.getElementById('mount-slewing');
    if (slewEl) {
      slewEl.classList.toggle('hidden-inline', !ms.isSlewing);
    }

    // Pier side — §2.9 centralised formatter.
    const pierEl = document.getElementById('mount-pier');
    if (pierEl && ms.sideOfPier !== undefined) {
      pierEl.textContent = formatPierSide(ms.sideOfPier);
    }

    // Alt/Az
    const altEl = document.getElementById('mount-alt');
    const azEl = document.getElementById('mount-az');
    if (altEl && ms.altitude !== undefined) altEl.textContent = ms.altitude.toFixed(1) + '°';
    if (azEl && ms.azimuth !== undefined) azEl.textContent = ms.azimuth.toFixed(1) + '°';
  }

  /**
   * §2.9 — map ASCOM PierSide integer to human label. Backend returns:
   *   1  → pierEast    (counterweight points west; tube points east)
   *   0  → pierWest    (counterweight points east; tube points west)
   *  -1  → pierUnknown
   * Some drivers (or already-resolved API responses) send the string label
   * directly; pass that through unchanged.
   */
  function formatPierSide(value) {
    if (typeof value === 'string' && value.length > 0) return value;
    const n = Number(value);
    if (n === 1) return 'East';
    if (n === 0) return 'West';
    if (n === -1) return 'Unknown';
    return '--';
  }

  // =========================================================================
  // Rendering: Sequencer Panel
  // =========================================================================

  function renderSequencerPanel() {
    const statusEl = document.getElementById('seq-status');
    const nodeEl = document.getElementById('seq-node');
    const messageEl = document.getElementById('seq-message');
    const progressBar = document.getElementById('seq-progress-bar');
    const progressBarContainer = document.getElementById('seq-progress-bar-container');
    const progressText = document.getElementById('seq-progress-text');

    if (!state.sequencerStatus) {
      if (statusEl) renderBadge(statusEl, 'idle', 'badge-idle');
      if (nodeEl) nodeEl.textContent = '--';
      if (messageEl) messageEl.textContent = '';
      if (progressBar) progressBar.style.width = '0%';
      if (progressBarContainer) progressBarContainer.setAttribute('aria-valuenow', '0');
      if (progressText) progressText.textContent = '';
      return;
    }

    const s = state.sequencerStatus;

    if (statusEl) {
      const badgeClass = getSequencerBadgeClass(s.state);
      renderBadge(statusEl, s.state || 'idle', badgeClass);
    }

    if (nodeEl) nodeEl.textContent = s.currentNodeName || '--';
    if (messageEl) messageEl.textContent = s.message || '';

    const progress = s.progress != null ? s.progress : 0;
    if (progressBar) {
      progressBar.style.width = progress + '%';
      if (progress >= 100) progressBar.classList.add('completed');
      else progressBar.classList.remove('completed');
    }
    if (progressBarContainer) {
      progressBarContainer.setAttribute('aria-valuenow', String(Math.round(progress)));
    }
    if (progressText) progressText.textContent = progress.toFixed(0) + '%';
  }

  function getSequencerBadgeClass(stateStr) {
    if (!stateStr) return 'badge-idle';
    const s = stateStr.toLowerCase();
    if (s === 'running' || s === 'executing') return 'badge-running';
    if (s === 'paused') return 'badge-paused';
    if (s === 'error' || s === 'failed') return 'badge-error';
    if (s === 'completed' || s === 'done') return 'badge-completed';
    return 'badge-idle';
  }

  // =========================================================================
  // Rendering: Guiding Panel
  // =========================================================================

  function renderGuidingPanel() {
    const statusEl = document.getElementById('guide-status');
    const raRmsEl = document.getElementById('guide-ra-rms');
    const decRmsEl = document.getElementById('guide-dec-rms');
    const totalRmsEl = document.getElementById('guide-total-rms');

    if (!state.guidingStatus) {
      if (statusEl) renderBadge(statusEl, 'disconnected', 'badge-idle');
      if (raRmsEl) raRmsEl.textContent = '--';
      if (decRmsEl) decRmsEl.textContent = '--';
      if (totalRmsEl) totalRmsEl.textContent = '--';
      return;
    }

    const g = state.guidingStatus;

    if (statusEl) {
      const guidingState = g.state || g.appState || 'unknown';
      const isGuiding = String(guidingState).toLowerCase().includes('guid');
      const badgeClass = isGuiding ? 'badge-running' : 'badge-idle';
      renderBadge(statusEl, guidingState, badgeClass);
    }

    // RMS values
    if (g.rmsRA !== undefined && raRmsEl) raRmsEl.textContent = g.rmsRA.toFixed(2) + '"';
    if (g.rmsDec !== undefined && decRmsEl) decRmsEl.textContent = g.rmsDec.toFixed(2) + '"';
    if (g.rmsTotal !== undefined && totalRmsEl) totalRmsEl.textContent = g.rmsTotal.toFixed(2) + '"';
  }

  function addGuideDataPoint(ra, dec) {
    state.guideHistory.ra.push(ra);
    state.guideHistory.dec.push(dec);

    if (state.guideHistory.ra.length > state.maxGuidePoints) {
      state.guideHistory.ra.shift();
      state.guideHistory.dec.shift();
    }

    drawGuideGraph();
  }

  // =========================================================================
  // Guide Graph (Canvas)
  // =========================================================================

  function setupGuideCanvas() {
    const canvas = document.getElementById('guide-canvas');
    if (!canvas) return;

    const resizeCanvas = () => {
      const container = canvas.parentElement;
      canvas.width = container.clientWidth;
      canvas.height = container.clientHeight;
      drawGuideGraph();
    };

    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();
  }

  function drawGuideGraph() {
    const canvas = document.getElementById('guide-canvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;

    ctx.fillStyle = '#0d1117';
    ctx.fillRect(0, 0, w, h);

    ctx.strokeStyle = '#21262d';
    ctx.lineWidth = 1;
    const midY = h / 2;

    ctx.beginPath();
    ctx.moveTo(0, midY);
    ctx.lineTo(w, midY);
    ctx.stroke();

    ctx.strokeStyle = '#161b22';
    for (const frac of [0.25, 0.75]) {
      ctx.beginPath();
      ctx.moveTo(0, h * frac);
      ctx.lineTo(w, h * frac);
      ctx.stroke();
    }

    const raData = state.guideHistory.ra;
    const decData = state.guideHistory.dec;
    if (raData.length < 2) return;

    let maxVal = 2; // minimum scale of 2 arcsec
    for (let i = 0; i < raData.length; i++) {
      maxVal = Math.max(maxVal, Math.abs(raData[i]), Math.abs(decData[i]));
    }
    maxVal *= 1.2;

    const xStep = w / (state.maxGuidePoints - 1);

    ctx.strokeStyle = '#58a6ff';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    for (let i = 0; i < raData.length; i++) {
      const x = i * xStep;
      const y = midY - (raData[i] / maxVal) * midY;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    ctx.strokeStyle = '#f85149';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    for (let i = 0; i < decData.length; i++) {
      const x = i * xStep;
      const y = midY - (decData[i] / maxVal) * midY;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    ctx.fillStyle = '#484f58';
    ctx.font = '10px sans-serif';
    ctx.fillText('+' + maxVal.toFixed(1) + '"', 4, 12);
    ctx.fillText('-' + maxVal.toFixed(1) + '"', 4, h - 4);
  }

  // =========================================================================
  // Log Panel
  // =========================================================================

  function addLogEntry(category, message) {
    const now = new Date();
    const ts = now.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });

    state.logEntries.push({ ts, category, message });
    if (state.logEntries.length > state.maxLogEntries) {
      state.logEntries.shift();
    }

    renderLogEntry(ts, category, message);
  }

  function renderLogEntry(ts, category, message) {
    const container = document.getElementById('log-container');
    if (!container) return;

    const emptyState = container.querySelector('.empty-state');
    if (emptyState) emptyState.remove();

    const entry = document.createElement('div');
    entry.className = 'log-entry';

    const catClass = getCategoryClass(category);
    const timestampEl = document.createElement('span');
    timestampEl.className = 'log-timestamp';
    timestampEl.textContent = ts;
    const categoryEl = document.createElement('span');
    categoryEl.className = 'log-category ' + catClass;
    categoryEl.textContent = category;
    const messageEl = document.createElement('span');
    messageEl.className = 'log-message';
    messageEl.textContent = message;
    entry.appendChild(timestampEl);
    entry.appendChild(categoryEl);
    entry.appendChild(messageEl);

    container.appendChild(entry);

    // Auto-scroll to bottom
    container.scrollTop = container.scrollHeight;
  }

  function getCategoryClass(cat) {
    if (!cat) return '';
    const c = cat.toLowerCase();
    if (c === 'camera' || c === 'imaging') return 'camera';
    if (c === 'mount') return 'mount';
    if (c === 'focuser') return 'focuser';
    if (c === 'guiding' || c === 'phd2') return 'guiding';
    if (c === 'sequencer') return 'sequencer';
    if (c === 'error') return 'error';
    return 'system';
  }

  function clearLog() {
    state.logEntries = [];
    const container = document.getElementById('log-container');
    if (container) {
      clearElement(container);
      container.appendChild(createEmptyState('Log cleared'));
    }
  }

  // =========================================================================
  // Phone Layout (§2.13)
  // =========================================================================

  function applyResponsiveLayout() {
    const phone = window.matchMedia('(max-width: 600px)').matches;
    document.body.classList.toggle('layout--phone', phone);
    if (phone) {
      activatePhoneTab(state.activePhoneTab);
    } else {
      // Make every panel visible again on tablet/desktop.
      for (const id of PHONE_PANELS) {
        const p = document.getElementById(id);
        if (p) p.classList.remove('phone-active');
      }
      // Guiding panel is reachable on phone via the Sequencer tab grouping
      // would hide it — leave it visible in the regular grid.
      const guiding = document.getElementById('panel-guiding');
      if (guiding) guiding.classList.remove('phone-active');
    }
  }

  function activatePhoneTab(panelId) {
    if (!PHONE_PANELS.includes(panelId)) return;
    state.activePhoneTab = panelId;
    for (const id of PHONE_PANELS) {
      const p = document.getElementById(id);
      if (p) p.classList.toggle('phone-active', id === panelId);
    }
    // Hide the guiding panel on phone (it's accessible via the desktop layout
    // when rotating). Keeping it out of the tab strip avoids overcrowding the
    // 5-slot bar.
    const guiding = document.getElementById('panel-guiding');
    if (guiding) guiding.classList.remove('phone-active');

    for (const tab of document.querySelectorAll('.phone-tab')) {
      tab.setAttribute('aria-selected', tab.dataset.target === panelId ? 'true' : 'false');
    }
  }

  // =========================================================================
  // Utilities
  // =========================================================================

  function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  function formatRA(raHours) {
    if (raHours == null || isNaN(raHours)) return '--h --m --s';
    const h = Math.floor(raHours);
    const m = Math.floor((raHours - h) * 60);
    const s = ((raHours - h) * 60 - m) * 60;
    return pad2(h) + 'h ' + pad2(m) + 'm ' + pad2(s.toFixed(1)) + 's';
  }

  function formatDec(decDeg) {
    if (decDeg == null || isNaN(decDeg)) return '--° --\' --"';
    const sign = decDeg >= 0 ? '+' : '-';
    const abs = Math.abs(decDeg);
    const d = Math.floor(abs);
    const m = Math.floor((abs - d) * 60);
    const s = ((abs - d) * 60 - m) * 60;
    return sign + pad2(d) + '° ' + pad2(m) + "' " + pad2(s.toFixed(0)) + '"';
  }

  function pad2(val) {
    const s = String(val);
    return s.length < 2 ? '0' + s : s;
  }

  // §2.18 — escapeHtml has been removed. Every rendering site uses textContent
  // / appendChild instead, which DOM-escapes automatically. Keeping a dead
  // helper around invites future contributors to reach for innerHTML.

  function clearElement(el) {
    while (el.firstChild) {
      el.removeChild(el.firstChild);
    }
  }

  function createEmptyState(message) {
    const el = document.createElement('div');
    el.className = 'empty-state';
    el.textContent = message;
    return el;
  }

  function createImagePlaceholder(message) {
    const el = document.createElement('div');
    el.className = 'image-preview-placeholder';
    el.textContent = message;
    return el;
  }

  function createStatusRow(label, value, valueClass) {
    const row = document.createElement('div');
    row.className = 'status-row';
    const labelEl = document.createElement('span');
    labelEl.className = 'status-label';
    labelEl.textContent = label;
    const valueEl = document.createElement('span');
    valueEl.className = valueClass ? 'status-value ' + valueClass : 'status-value';
    valueEl.textContent = value;
    row.appendChild(labelEl);
    row.appendChild(valueEl);
    return row;
  }

  function renderBadge(container, label, badgeClass) {
    clearElement(container);
    const badge = document.createElement('span');
    badge.className = 'badge ' + badgeClass;
    badge.textContent = label;
    container.appendChild(badge);
  }

  // =========================================================================
  // Toast Notifications
  // =========================================================================

  function showToast(message, type) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = 'toast' + (type ? ' ' + type : '');
    toast.setAttribute('role', type === 'error' ? 'alert' : 'status');
    toast.textContent = message;
    container.appendChild(toast);

    setTimeout(() => {
      toast.classList.add('fading-out');
      setTimeout(() => toast.remove(), 300);
    }, 4000);
  }

})();
