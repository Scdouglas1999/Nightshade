/**
 * Nightshade Headless API Client
 *
 * Wraps all REST and WebSocket endpoints exposed by the headless server.
 * Handles authentication, request retries, and event streaming.
 */
class NightshadeApi {
  constructor() {
    this._baseUrl = '';
    this._authToken = '';
    this._deviceId = '';
    this._apiVersion = '2.5.0';
    this._requestCounter = 0;
    this._ws = null;
    this._wsReconnectTimer = null;
    this._wsReconnectDelay = 1000;
    this._maxReconnectDelay = 30000;
    this._wsHeartbeatTimer = null;
    this._lastWsMessageAt = 0;
    this._wsHeartbeatTimeoutMs = 90000;
    this._requestTimeoutMs = 8000;
    this._connectionTimeoutMs = 4000;
    this._eventListeners = new Map();
    this._connected = false;
    this._wsConnected = false;
    // CSRF token bound to the HttpOnly session cookie (§2.5 long-form).
    // In-memory only — never persisted to storage. The cookie itself is
    // HttpOnly so JS can't read it; the CSRF token is what proves a
    // request originated from the SPA rather than from an attacker who
    // tricked the browser into sending the cookie ambient-style.
    this._csrfToken = '';
    // When true, fetches include the session cookie via
    // `credentials: 'include'` AND echo `X-Nightshade-CSRF` on writes.
    // Toggled on after a successful POST /api/auth/cookie OR when the
    // server confirms a pre-existing session via GET /api/auth/csrf.
    this._useSessionCookie = false;
  }

  /**
   * Configure the API base URL and auth token.
   * @param {string} baseUrl - e.g. "http://192.168.1.8:8080"
   * @param {string} authToken - Bearer token (empty string if auth disabled)
   * @param {string} deviceId - Paired device identifier for authenticated access
   */
  configure(baseUrl, authToken, deviceId) {
    this._baseUrl = baseUrl.replace(/\/+$/, '');
    this._authToken = authToken || '';
    this._deviceId = deviceId || '';
    this._connected = false;
    // Reconfiguring (e.g. user pasted a new token) invalidates any prior
    // cookie session — the caller will re-establish it via beginCookieSession.
    this._csrfToken = '';
    this._useSessionCookie = false;
  }

  get baseUrl() { return this._baseUrl; }
  get isConnected() { return this._connected; }
  get isWsConnected() { return this._wsConnected; }
  get hasSessionCookie() { return this._useSessionCookie; }

  // =========================================================================
  // HTTP helpers
  // =========================================================================

  _headers(extraHeaders, method) {
    const h = {
      'Content-Type': 'application/json',
      'X-Nightshade-API-Version': this._apiVersion,
      'X-Request-ID': this._nextRequestId(),
      ...extraHeaders,
    };
    // Cookie path: rely on the HttpOnly session cookie attached by the
    // browser; do NOT echo the bearer in the Authorization header (the
    // server's middleware accepts either, and avoiding the duplicate
    // ensures a single audit trail per session).
    //
    // Bearer path: continue to send Authorization as before. Mobile and
    // legacy clients keep working unchanged.
    if (!this._useSessionCookie && this._authToken) {
      h['Authorization'] = 'Bearer ' + this._authToken;
    }
    // Echo the CSRF token on every state-changing fetch when we're on the
    // cookie path. GET/HEAD do not need it (the server skips CSRF for
    // read-only methods because cross-site GET can't mutate state).
    if (this._useSessionCookie && this._csrfToken &&
        method && method !== 'GET' && method !== 'HEAD') {
      h['X-Nightshade-CSRF'] = this._csrfToken;
    }
    if (this._deviceId) {
      h['X-Nightshade-Device-Id'] = this._deviceId;
    }
    return h;
  }

  _nextRequestId() {
    this._requestCounter = (this._requestCounter + 1) % 1048575;
    return 'dash-' + Date.now().toString(36) + '-' + this._requestCounter.toString(36);
  }

  async _get(path) {
    return this._request('GET', path);
  }

  async _post(path, body) {
    return this._request('POST', path, body);
  }

  async _put(path, body) {
    return this._request('PUT', path, body);
  }

  async _delete(path) {
    return this._request('DELETE', path);
  }

  async _request(method, path, body, timeoutMs) {
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      timeoutMs || this._requestTimeoutMs,
    );

    let resp;
    try {
      resp = await fetch(this._baseUrl + path, {
        method,
        headers: this._headers(undefined, method),
        // Always attach cookies on same-origin requests. Why unconditional:
        // §2.5 long-form ships HttpOnly cookies for the "remember" path;
        // omitting credentials would prevent the cookie from round-
        // tripping even when present. Cross-origin allowance is gated by
        // Access-Control-Allow-Credentials server-side, so this stays
        // safe on disallowed origins.
        credentials: 'include',
        body: body != null
          ? JSON.stringify(body)
          : (method === 'POST' || method === 'PUT' ? '{}' : undefined),
        signal: controller.signal,
      });
    } catch (e) {
      if (e && e.name === 'AbortError') {
        throw new Error(method + ' ' + path + ' timed out');
      }
      throw e;
    } finally {
      clearTimeout(timeout);
    }

    const text = await resp.text();
    if (!resp.ok) {
      throw new Error(method + ' ' + path + ' failed (' + resp.status + '): ' + text);
    }
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch (_) {
      throw new Error(method + ' ' + path + ' returned invalid JSON');
    }
  }

  async _getWithTimeout(path, timeoutMs) {
    return this._request('GET', path, undefined, timeoutMs);
  }

  // =========================================================================
  // Core
  // =========================================================================

  async getInfo() { return this._get('/api/info'); }
  async getStatus() { return this._get('/api/status'); }

  // =========================================================================
  // Devices
  // =========================================================================

  async getDevices(deviceType) {
    const q = deviceType ? '?deviceType=' + encodeURIComponent(deviceType) : '';
    return this._get('/api/devices' + q);
  }

  async getConnectedDevices() {
    return this._get('/api/devices/connected');
  }

  async connectDevice(deviceId, deviceType) {
    return this._post('/api/devices/connect', { deviceId, deviceType });
  }

  async disconnectDevice(deviceId, deviceType) {
    return this._post('/api/devices/disconnect', { deviceId, deviceType });
  }

  // =========================================================================
  // Camera
  // =========================================================================

  async cameraExpose(deviceId, exposureTime, opts) {
    return this._post('/api/camera/expose', {
      deviceId,
      exposureTime,
      frameType: (opts && opts.frameType) || 'light',
      gain: opts && opts.gain,
      offset: opts && opts.offset,
      binX: (opts && opts.binX) || 1,
      binY: (opts && opts.binY) || 1,
      // Subframe x/y/width/height pass through whenever the dashboard panel
      // has explicit values entered — undefined falls back to full-frame on
      // the backend, which is the same default as the desktop UI.
      x: opts && opts.x,
      y: opts && opts.y,
      width: opts && opts.width,
      height: opts && opts.height,
    });
  }

  async cameraAbort(deviceId) {
    return this._post('/api/camera/abort', { deviceId });
  }

  async cameraGetLastImage(deviceId) {
    return this._get('/api/camera/last-image?deviceId=' + encodeURIComponent(deviceId));
  }

  async cameraSetCooling(deviceId, enabled, targetTemp) {
    return this._post('/api/camera/cooling', { deviceId, enabled, targetTemp });
  }

  async cameraSetGain(deviceId, gain) {
    return this._post('/api/camera/gain', { deviceId, gain });
  }

  async cameraSetOffset(deviceId, offset) {
    return this._post('/api/camera/offset', { deviceId, offset });
  }

  // The backend uses camelCase /api/camera/readoutMode (see device_handlers
  // and the route table in headless_api_server.dart). Match that exactly —
  // hyphenated variants 404 on the current server.
  async cameraSetReadoutMode(deviceId, modeIndex) {
    return this._post('/api/camera/readoutMode', { deviceId, modeIndex });
  }

  // Dedicated readout-mode list endpoint. Backed by the camera abstraction's
  // capabilities, but returns only the {readoutModes: [...]} subset so the
  // dropdown doesn't have to round-trip the full capabilities payload.
  async cameraGetReadoutModes(deviceId) {
    return this._get(
      '/api/camera/readout-modes?deviceId=' + encodeURIComponent(deviceId || ''),
    );
  }

  // Dedicated cooling-state endpoint. Source of truth is the camera status
  // model; this endpoint just projects the four cooling fields so the cooling
  // panel can poll at its own cadence without pulling the full status blob.
  async cameraGetCooling(deviceId) {
    return this._get(
      '/api/camera/cooling?deviceId=' + encodeURIComponent(deviceId || ''),
    );
  }

  // Binning and subframe are committed by cameraExpose's binX/binY/x/y/
  // width/height body fields. Why no separate /api/camera/binning or
  // /api/camera/subframe endpoint: ASCOM cameras only commit these at
  // StartExposure time, so a standalone setter would either no-op or
  // fight the next expose body. The dashboard sends them per-expose.
  // These no-op shims keep the audit §2.17 endpoint names alive in the
  // client surface so future code can call them uniformly.
  async cameraSetBinning(_deviceId, _binX, _binY) {
    return { status: 'queued', message: 'Binning applies on next Expose' };
  }

  async cameraSetSubframe(_deviceId, _x, _y, _width, _height) {
    return { status: 'queued', message: 'Subframe applies on next Expose' };
  }

  // Reset any pending subframe state — currently a no-op (subframe lives in
  // the input fields), kept so callers can express intent uniformly.
  clearPendingSubframe() { /* nothing to clear today */ }

  // =========================================================================
  // Equipment Status
  // =========================================================================

  async getCameraStatus(deviceId) {
    return this._get('/api/equipment/camera/status?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  async getMountStatus(deviceId) {
    return this._get('/api/equipment/mount/status?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  async getFocuserStatus(deviceId) {
    return this._get('/api/equipment/focuser/status?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  async getFilterWheelStatus(deviceId) {
    return this._get('/api/equipment/filter-wheel/status?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  async getRotatorStatus(deviceId) {
    return this._get('/api/equipment/rotator/status?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  // =========================================================================
  // Mount
  // =========================================================================

  async mountSlew(deviceId, ra, dec) {
    return this._post('/api/mount/slew', { deviceId, ra, dec });
  }

  async mountSync(deviceId, ra, dec) {
    return this._post('/api/mount/sync', { deviceId, ra, dec });
  }

  async mountPark(deviceId) {
    return this._post('/api/mount/park', { deviceId });
  }

  async mountUnpark(deviceId) {
    return this._post('/api/mount/unpark', { deviceId });
  }

  async mountSetTracking(deviceId, enabled) {
    return this._post('/api/mount/tracking', { deviceId, enabled });
  }

  async mountAbort(deviceId) {
    return this._post('/api/mount/abort', { deviceId });
  }

  async mountGetStatus(deviceId) {
    return this._get('/api/mount/status?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  async mountMoveAxis(deviceId, axis, rate) {
    return this._post('/api/mount/move-axis', { deviceId, axis, rate });
  }

  // =========================================================================
  // Focuser
  // =========================================================================

  async focuserMoveTo(deviceId, position) {
    return this._post('/api/focuser/move-to', { deviceId, position });
  }

  async focuserMoveRelative(deviceId, delta) {
    return this._post('/api/focuser/move-relative', { deviceId, delta });
  }

  async focuserHalt(deviceId) {
    return this._post('/api/focuser/halt', { deviceId });
  }

  // Returns FocuserStatus (position, moving, temperature). Why a wrapper:
  // the dashboard reads from /api/equipment/focuser/status and renders
  // position/temp from the same payload — keeping the call here matches the
  // mountGetStatus/cameraGetStatus pattern.
  async focuserGetStatus(deviceId) {
    return this._get(
      '/api/equipment/focuser/status?deviceId=' + encodeURIComponent(deviceId || ''),
    );
  }

  // Autofocus requires a camera + exposure parameters; the dashboard sends
  // sensible defaults from the connected camera's last gain and a 3s sub.
  // Step sizes mirror the desktop AutofocusDialog defaults.
  async autofocusStart(deviceId, cameraId, opts) {
    return this._post('/api/focuser/autofocus/start', {
      deviceId,
      cameraId,
      exposureTime: (opts && opts.exposureTime) || 3.0,
      stepSize: (opts && opts.stepSize) || 50,
      stepsOut: (opts && opts.stepsOut) || 5,
      method: (opts && opts.method) || 'VCurve',
      binning: (opts && opts.binning) || 2,
    });
  }

  async autofocusCancel(deviceId) {
    return this._post('/api/focuser/autofocus/cancel', { deviceId });
  }

  // =========================================================================
  // Filter Wheel
  // =========================================================================

  async filterWheelSetPosition(deviceId, position) {
    return this._post('/api/filter-wheel/position', { deviceId, position });
  }

  async filterWheelGetNames(deviceId) {
    return this._get('/api/filter-wheel/names?deviceId=' + encodeURIComponent(deviceId || ''));
  }

  async filterWheelSetByName(deviceId, filterName) {
    // The backend payload key is `name` (see handleFilterWheelSetByName); the
    // dashboard previously sent `filterName`, which the validator rejected
    // with "field 'name' required".
    return this._post('/api/filter-wheel/set-by-name', { deviceId, name: filterName });
  }

  // Combined "list of positions with names + offsets" for the click-to-rotate
  // panel. Filter offsets come from /api/focus-model/filter-offsets (the
  // single source of truth shared with the autofocus model). Why two GETs:
  // there is no combined endpoint and we want offsets to survive even when
  // a wheel reports placeholder names like "Filter 1" .. "Filter 8".
  async filterWheelGetPositions(deviceId) {
    const [namesResp, status, offsetsResp] = await Promise.all([
      this.filterWheelGetNames(deviceId),
      this._get('/api/equipment/filter-wheel/status?deviceId=' +
        encodeURIComponent(deviceId || '')),
      // Why catch: the focus model offsets endpoint requires an active
      // profile; on a fresh install it can 404. Treat that as "no offsets"
      // rather than failing the whole panel render.
      this._get('/api/focus-model/filter-offsets').catch(() => ({})),
    ]);
    const names = (namesResp && namesResp.names) || [];
    const offsets = (offsetsResp && (offsetsResp.offsets || offsetsResp)) || {};
    const positions = names.map((name, idx) => ({
      position: idx,
      name: name || ('Slot ' + idx),
      // offsets is keyed by filter name in the focus model service
      offset: offsets && offsets[name] != null ? Number(offsets[name]) : null,
    }));
    return {
      positions,
      currentPosition: status && status.position != null ? Number(status.position) : -1,
      filterCount: positions.length,
    };
  }

  // =========================================================================
  // Rotator
  // =========================================================================

  async rotatorMoveTo(deviceId, angle) {
    return this._post('/api/rotator/move-to', { deviceId, angle });
  }

  async rotatorMoveRelative(deviceId, delta) {
    return this._post('/api/rotator/move-relative', { deviceId, delta });
  }

  async rotatorHalt(deviceId) {
    return this._post('/api/rotator/halt', { deviceId });
  }

  async rotatorGetAngle(deviceId) {
    return this._get(
      '/api/rotator/status?deviceId=' + encodeURIComponent(deviceId || ''),
    );
  }

  async rotatorGetStatus(deviceId) {
    return this._get(
      '/api/equipment/rotator/status?deviceId=' + encodeURIComponent(deviceId || ''),
    );
  }

  // POST /api/rotator/sync — Sync rotator's reported sky angle to the
  // supplied position-angle without moving the hardware. Canonical field is
  // `positionAngle` (matches plate-solve terminology); the handler also
  // accepts `angle` as an alias for older clients.
  async rotatorSync(deviceId, positionAngle) {
    return this._post('/api/rotator/sync', { deviceId, positionAngle });
  }

  // =========================================================================
  // Targets (autocomplete)
  // =========================================================================

  async targetsSearch(query) {
    return this._get('/api/targets/search?query=' + encodeURIComponent(query || ''));
  }

  // Mount Slew helpers — names match the audit §2.17 brief. mountSlewToRaDec
  // and mountAbortSlew are aliases over the existing mountSlew / mountAbort
  // to keep app.js handlers readable.
  async mountSlewToRaDec(deviceId, raHours, decDeg) {
    return this.mountSlew(deviceId, raHours, decDeg);
  }

  async mountAbortSlew(deviceId) {
    return this.mountAbort(deviceId);
  }

  // =========================================================================
  // PHD2 Guiding
  // =========================================================================

  async phd2Connect(host, port) {
    return this._post('/api/phd2/connect', { host: host || 'localhost', port: port || 4400 });
  }

  async phd2Disconnect() {
    return this._post('/api/phd2/disconnect', {});
  }

  async phd2StartGuiding(settlePixels, settleTime, settleTimeout) {
    return this._post('/api/phd2/start-guiding', {
      settlePixels: settlePixels || 1.0,
      settleTime: settleTime || 10.0,
      settleTimeout: settleTimeout || 60.0,
    });
  }

  async phd2StopGuiding() {
    return this._post('/api/phd2/stop-guiding', {});
  }

  async phd2GetStatus() {
    return this._get('/api/phd2/status');
  }

  async phd2Dither(amount) {
    return this._post('/api/phd2/dither', { amount: amount || 5.0 });
  }

  async phd2SetPaused(paused) {
    return this._post('/api/phd2/pause', { paused });
  }

  // =========================================================================
  // Sequencer
  // =========================================================================

  async sequencerGetStatus() {
    return this._get('/api/sequencer/status');
  }

  async sequencerStart() {
    return this._post('/api/sequencer/start', {});
  }

  async sequencerStop() {
    return this._post('/api/sequencer/stop', {});
  }

  async sequencerPause() {
    return this._post('/api/sequencer/pause', {});
  }

  async sequencerResume() {
    return this._post('/api/sequencer/resume', {});
  }

  async sequencerSkip() {
    return this._post('/api/sequencer/skip', {});
  }

  async sequencerReset() {
    return this._post('/api/sequencer/reset', {});
  }

  async sequencerLoad(sequenceData) {
    return this._post('/api/sequencer/load', sequenceData);
  }

  // =========================================================================
  // Profiles
  // =========================================================================

  async getProfiles() { return this._get('/api/profiles'); }
  async getActiveProfile() { return this._get('/api/profiles/active'); }

  // =========================================================================
  // Settings
  // =========================================================================

  async getSettings() { return this._get('/api/settings'); }
  async getLocation() { return this._get('/api/settings/location'); }

  // =========================================================================
  // Weather
  // =========================================================================

  async getWeatherSafeImaging() { return this._get('/api/weather/safe-imaging'); }

  // TODO[W5-BACKEND-EXTEND]: there is no /api/weather/current endpoint that
  // returns live telemetry (temperature, humidity, dewpoint, wind, cloud
  // cover) from a connected ObservingConditions / hardware weather device.
  // The current weather routes only expose radar/forecast/alerts/safe-imaging.
  // Until a dedicated handler is added, the dashboard's weather panel fans
  // out across the alerts + safe-imaging endpoints so the operator still has
  // some signal; we explicitly do NOT fabricate the missing fields.
  async weatherGetCurrent() {
    const [safeImaging, alertsResp] = await Promise.all([
      this._get('/api/weather/safe-imaging'),
      this._get('/api/weather/alerts'),
    ]);
    const alerts = (alertsResp && Array.isArray(alertsResp.alerts))
      ? alertsResp.alerts : [];
    return {
      safeToImage: !!(safeImaging && safeImaging.safeToImage),
      alertLevel: (safeImaging && safeImaging.alertLevel) || 'none',
      message: (safeImaging && safeImaging.message) || '',
      // Surface the most recent alert (the server emits at most one current
      // alert today) so the panel can show its details without re-querying.
      currentAlert: alerts.length > 0 ? alerts[0] : null,
      // These fields are placeholders to match the §2.17 brief shape. They
      // are explicitly null so the UI renders '--' rather than 0 — the
      // panel must NOT pretend it knows the telemetry.
      temperature: null,
      humidity: null,
      cloudCover: null,
      windSpeed: null,
      dewPoint: null,
    };
  }

  // =========================================================================
  // Safety (§2.17 — ops panels)
  // =========================================================================

  // Aggregate safety status across all connected safety monitors.
  // Returns { isSafe, monitorsConnected, monitors[], failModeWarning, ... }
  async safetyGetStatus() {
    return this._get('/api/safety/status');
  }

  // =========================================================================
  // Sequences — listing + load by id (§2.17 — ops panels)
  // =========================================================================

  // List sequences saved in the database. Excludes templates (handled by a
  // separate endpoint). Each entry: { id, name, description, rootNodeId,
  // isTemplate, createdAt, updatedAt }.
  async sequencerList() {
    return this._get('/api/sequence-management/list');
  }

  // TODO[W5-BACKEND-EXTEND]: no /api/sequencer/load-by-id endpoint exists.
  // /api/sequencer/load requires a serialized sequence JSON string. To
  // "load" a saved sequence by id from the dashboard we currently fetch the
  // sequence + nodes via /api/sequence-management and post a synthesised
  // payload below. A dedicated server-side endpoint would let the dashboard
  // submit only the sequence id (matching the desktop UI's behaviour).
  async sequencerLoadById(sequenceId) {
    const [seqResp, nodesResp] = await Promise.all([
      this._get('/api/sequence-management/' + encodeURIComponent(sequenceId)),
      this._get(
        '/api/sequence-management/' + encodeURIComponent(sequenceId) + '/nodes',
      ),
    ]);
    const sequence = seqResp && seqResp.sequence;
    const nodes = (nodesResp && nodesResp.nodes) || [];
    if (!sequence) {
      throw new Error('Sequence ' + sequenceId + ' not found');
    }
    // The backend expects a `json` field — pass the full sequence body so the
    // Rust sequencer can rehydrate it. The desktop client builds the same
    // payload, so any future schema change applies uniformly.
    const payload = JSON.stringify({ sequence, nodes });
    return this._post('/api/sequencer/load', { json: payload });
  }

  // Convenience for the ops sequencer panel: load + immediately start.
  async sequencerLoadAndStart(sequenceId) {
    await this.sequencerLoadById(sequenceId);
    return this.sequencerStart();
  }

  // Abort = stop. Why an alias: the §2.17 brief uses "Abort"; the server uses
  // "stop". Keeping both names makes the dashboard code match the brief
  // verbatim without a confusing rename.
  async sequencerAbort() {
    return this.sequencerStop();
  }

  // =========================================================================
  // Checkpoint resume (§2.17 — ops panels)
  // =========================================================================

  // TODO[W5-BACKEND-EXTEND]: the current sequencer only supports a single
  // active checkpoint, not a list. /api/sequencer/checkpoint/has +
  // /api/sequencer/checkpoint/info return that single entry. The §2.17 brief
  // describes a "picker" so we normalise the response to an array of length
  // 0 or 1; if/when multi-checkpoint support lands the wire format will need
  // to change, and the UI already iterates over an array.
  async sequencerListCheckpoints() {
    const hasResp = await this._get('/api/sequencer/checkpoint/has');
    if (!hasResp || !hasResp.hasCheckpoint) {
      return { checkpoints: [] };
    }
    const infoResp = await this._get('/api/sequencer/checkpoint/info');
    const info = infoResp && infoResp.info;
    if (!info) {
      return { checkpoints: [] };
    }
    return { checkpoints: [info] };
  }

  async sequencerResumeCheckpoint() {
    return this._post('/api/sequencer/checkpoint/resume', {});
  }

  async sequencerDiscardCheckpoint() {
    return this._post('/api/sequencer/checkpoint/discard', {});
  }

  // =========================================================================
  // Dome (§2.17 — ops panels)
  // =========================================================================

  async domeOpen(deviceId) {
    return this._post('/api/dome/open', { deviceId });
  }

  async domeClose(deviceId) {
    return this._post('/api/dome/close', { deviceId });
  }

  async domeSlew(deviceId, azimuth) {
    return this._post('/api/dome/slew', { deviceId, azimuth });
  }

  async domePark(deviceId) {
    return this._post('/api/dome/park', { deviceId });
  }

  async domeGetStatus(deviceId) {
    return this._get(
      '/api/dome/status?deviceId=' + encodeURIComponent(deviceId || ''),
    );
  }

  // TODO[W5-BACKEND-EXTEND]: handleDomeSync currently returns 501. The audit
  // calls for a "sync-to-mount toggle"; once the bridge exposes
  // apiDomeSetSlaved(), the handler can flip dome slaving and the UI control
  // here will start working. We still POST so the failure surfaces clearly to
  // the operator instead of being silently hidden.
  async domeSyncToMount(deviceId, enabled) {
    return this._post('/api/dome/sync', { deviceId, enabled });
  }

  // =========================================================================
  // Profiles (§2.17 — ops panels)
  // =========================================================================

  async profilesGetList() {
    return this._get('/api/profiles');
  }

  async profilesGetActive() {
    return this._get('/api/profiles/active');
  }

  async profilesActivate(profileId) {
    return this._post(
      '/api/profiles/' + encodeURIComponent(profileId) + '/load',
      {},
    );
  }

  // TODO[W5-BACKEND-EXTEND]: no /api/profiles/reload endpoint exists. The
  // desktop UI re-reads the active profile to pick up out-of-band edits;
  // here we re-activate the active profile id, which has equivalent effect
  // (it forces device caches + filter offsets to repopulate from disk).
  async profilesReload() {
    const active = await this.profilesGetActive();
    const profile = active && active.profile;
    if (!profile || !profile.id) {
      throw new Error('No active profile to reload');
    }
    return this.profilesActivate(profile.id);
  }

  // =========================================================================
  // Analytics — session summary (§2.17 — ops panels)
  // =========================================================================

  // TODO[W5-BACKEND-EXTEND]: there is no /api/analytics/session-summary
  // endpoint. The closest is /api/sessions/active (which returns the row
  // with totalExposures / totalIntegrationSecs / avgHfr) and the science
  // bundle (which carries the transparency sample series we use for the
  // sparkline). Compose them so the dashboard panel has both the headline
  // stats and the transparency trend without waiting on a new server route.
  async analyticsGetSessionSummary() {
    const active = await this._get('/api/sessions/active');
    const session = active && active.session;
    if (!session) {
      return {
        session: null,
        transparency: [],
      };
    }
    let transparency = [];
    try {
      const bundle = await this._get(
        '/api/science/session/' + encodeURIComponent(session.id) + '/bundle',
      );
      transparency = (bundle && bundle.transparency) || [];
    } catch (e) {
      // Why swallow: science telemetry is optional — many sessions are
      // imaging-only and have no transparency samples recorded. A 404 or
      // empty bundle is not an error condition for the analytics panel.
      transparency = [];
    }
    return { session, transparency };
  }
  // =========================================================================
  // Plate Solve (§2.17 W5-WEB-WIZARDS)
  // =========================================================================

  // /api/plate-solve takes a file system path. The web dashboard finds the
  // path by querying /api/images/recent?limit=1 for the most recently
  // captured image (the desktop's AutoSaveService writes it to disk before
  // the row lands in the images table) and feeds the resulting filePath in.
  async plateSolve(imagePath, hint) {
    return this._post('/api/plate-solve', {
      imagePath,
      ra: hint && hint.ra,
      dec: hint && hint.dec,
      fov: hint && hint.fov,
    });
  }

  // Most-recent captured image — used so the plate-solve panel can solve
  // "the current frame" without the operator typing a filesystem path.
  async imagesGetRecent(limit) {
    return this._get('/api/images/recent?limit=' + encodeURIComponent(limit || 1));
  }

  // Save the camera's last in-memory capture to disk as FITS so the plate
  // solver can read it. The server already exposes this endpoint for the
  // desktop's auto-save fallback; the web client reuses it for "plate-solve
  // current frame" when no DB-tracked image exists yet.
  async imagingSaveFitsFromCapture(deviceId, filePath, headerData) {
    return this._post('/api/imaging/save-fits-from-capture', {
      deviceId,
      filePath,
      headerData: headerData || {},
    });
  }

  // =========================================================================
  // Polar Alignment (§2.17 W5-WEB-WIZARDS)
  // =========================================================================

  // The desktop backend uses snake_case for the polar alignment payload (see
  // SessionHandlers.handleStartPolarAlignment). Keep the wire shape identical
  // here rather than auto-camelCasing — the validator on the server side
  // rejects unknown fields.
  async polarAlignmentStart(opts) {
    const o = opts || {};
    return this._post('/api/polar-alignment/start', {
      exposure_time: o.exposureTime != null ? o.exposureTime : 3.0,
      step_size: o.stepSize != null ? o.stepSize : 5.0,
      binning: o.binning != null ? o.binning : 2,
      is_north: o.isNorth != null ? o.isNorth : true,
      manual_rotation: o.manualRotation != null ? o.manualRotation : false,
      rotate_east: o.rotateEast != null ? o.rotateEast : true,
      gain: o.gain,
      offset: o.offset,
      solve_timeout: o.solveTimeout,
      start_from_current: o.startFromCurrent,
    });
  }

  async polarAlignmentStop() {
    return this._post('/api/polar-alignment/stop', {});
  }

  // TODO[W5-BACKEND-EXTEND]: there is no dedicated all-sky polar alignment
  // start endpoint on the headless server yet. W5-ALL-SKY-PA landed the
  // desktop-side notifier (PolarAlignmentStateNotifier.startAllSkyAlignment)
  // but the REST surface only exposes the TPPA path through
  // /api/polar-alignment/start. The dashboard surfaces both modes in its UI
  // and routes both to /api/polar-alignment/start until the backend gains a
  // dedicated /api/polar-alignment/start-all-sky route; until then both
  // modes drive the same TPPA flow on the server.
  async polarAlignmentStartAllSky(opts) {
    return this.polarAlignmentStart(opts);
  }

  // =========================================================================
  // Flat Wizard (§2.17 W5-WEB-WIZARDS)
  // =========================================================================

  // Multi-filter ADU calibration. Returns an array of FlatResult JSON objects
  // — one per filter — each carrying the converged exposure for the chosen
  // ADU target. Streams progress via `imaging` / `sequencer` WebSocket events
  // while running (the backend's FlatWizardService emits them through the
  // shared event bus).
  async flatWizardCalibrateMulti(deviceId, filters, opts) {
    const o = opts || {};
    return this._request('POST', '/api/flat-wizard/calibrate-multi', {
      deviceId,
      filters,
      targetAdu: o.targetAdu != null ? o.targetAdu : 30000,
      tolerance: o.tolerance != null ? o.tolerance : 10.0,
      minExposure: o.minExposure != null ? o.minExposure : 0.001,
      maxExposure: o.maxExposure != null ? o.maxExposure : 30.0,
      maxIterations: o.maxIterations != null ? o.maxIterations : 10,
      binX: o.binX != null ? o.binX : 1,
      binY: o.binY != null ? o.binY : 1,
    // ADU calibration can run many iterations per filter; the default 8s
    // _requestTimeoutMs would abort before any real wheel can settle.
    }, /* timeoutMs */ 300000);
  }

  // Quick single-filter calibration — useful as the simplest panel-flat path.
  async flatWizardQuickCalibrate(deviceId, filter, opts) {
    const o = opts || {};
    return this._request('POST', '/api/flat-wizard/quick-calibrate', {
      deviceId,
      filter,
      targetAdu: o.targetAdu != null ? o.targetAdu : 30000,
      tolerancePercent: o.tolerancePercent != null ? o.tolerancePercent : 10.0,
      binX: o.binX != null ? o.binX : 1,
      binY: o.binY != null ? o.binY : 1,
    }, 120000);
  }

  // Turn a set of calibrations into a full flat-frame sequence the operator
  // can hand to the sequencer.
  async flatWizardGenerateSequence(calibrations, opts) {
    const o = opts || {};
    return this._post('/api/flat-wizard/generate-sequence', {
      calibrations,
      framesPerFilter: o.framesPerFilter != null ? o.framesPerFilter : 20,
      sequenceName: o.sequenceName || 'Flat Frame Sequence',
      description: o.description,
      binX: o.binX != null ? o.binX : 1,
      binY: o.binY != null ? o.binY : 1,
      gain: o.gain,
      offset: o.offset,
      onlySuccessful: o.onlySuccessful != null ? o.onlySuccessful : true,
    });
  }

  // =========================================================================
  // Mosaic Planner (§2.17 W5-WEB-WIZARDS)
  // =========================================================================

  // Compute the panel centers for a mosaic — useful for the preview step
  // before committing to a sequence.
  async mosaicGeneratePanels(config) {
    return this._post('/api/mosaic/generate-panels', { config });
  }

  // Time estimate for the mosaic. Surfaced in the wizard preview step so
  // operators see "this will take 4h12m" before pressing Build.
  async mosaicEstimateTime(config, exposure, overheadPerPanelSecs) {
    const body = { config, exposure };
    if (overheadPerPanelSecs != null) {
      body.overheadPerPanelSecs = overheadPerPanelSecs;
    }
    return this._post('/api/mosaic/estimate-time', body);
  }

  async mosaicValidate(config) {
    return this._post('/api/mosaic/validate', { config });
  }

  // Generate the full mosaic sequence (panel slews + per-panel exposures).
  // The dashboard's mosaic wizard hands the result off to the sequencer load
  // endpoint so the operator can press Start immediately.
  async mosaicGenerateSequence(opts) {
    const o = opts || {};
    return this._post('/api/mosaic/generate-sequence', {
      mosaicName: o.mosaicName || 'Mosaic',
      config: o.config,
      exposure: o.exposure,
      options: o.options || {},
    });
  }

  // =========================================================================
  // Framing Assistant (§2.17 W5-WEB-WIZARDS)
  // =========================================================================

  // Slew without solve-and-correct — the cheap "go close to" path.
  async framingSlewToTarget(ra, dec) {
    return this._post('/api/framing/slew-to-target', { ra, dec });
  }

  // Iterative plate-solve-and-correct centering. The server uses the
  // configured plate-solver settings to drive the mount onto the target.
  async framingCenterOnTarget(ra, dec, opts) {
    const o = opts || {};
    return this._request('POST', '/api/framing/center-on-target', {
      ra,
      dec,
      maxIterations: o.maxIterations != null ? o.maxIterations : 5,
      toleranceArcsec: o.toleranceArcsec != null ? o.toleranceArcsec : 30.0,
      exposureTime: o.exposureTime != null ? o.exposureTime : 3.0,
      binning: o.binning != null ? o.binning : 2,
      gain: o.gain != null ? o.gain : 100,
      syncMount: o.syncMount != null ? o.syncMount : false,
    // Centering can iterate up to maxIterations plate-solves; allow a long
    // window so a 5-iteration run with 3s exposures + a slow solver completes.
    }, 600000);
  }

  // Rotate to a chosen sky PA — used by the framing wizard's rotation step
  // when a rotator is connected.
  async framingRotateTo(angle) {
    return this._post('/api/framing/rotate-to', { angle });
  }

  // Mount sync to the framing-chosen coordinates (i.e. "the scope is HERE
  // now"). Optional — the wizard offers it as a sanity step after centering.
  async framingSyncMount(ra, dec) {
    return this._post('/api/framing/sync', { ra, dec });
  }

  // =========================================================================
  // Planetarium / FOV (§2.17 W5-WEB-WIZARDS)
  // =========================================================================

  // Returns the effective FOV (width/height in degrees) for the active
  // profile + camera. The framing wizard renders the FOV box on a sky chart
  // and the mosaic wizard auto-fills panelWidth/panelHeight from this.
  async getFovConfig() {
    return this._get('/api/planetarium/fov-config');
  }

  // =========================================================================
  // Targets (CRUD subset — used by the framing wizard to persist framing)
  // =========================================================================

  // Update an existing target (the framing wizard PUTs ra/dec/positionAngle
  // onto a previously-saved target row).
  async targetsUpdate(targetId, payload) {
    return this._put('/api/targets/' + encodeURIComponent(targetId), payload);
  }

  // Create a new target row. Used as the fallback path when the framing
  // wizard saves an ad-hoc framing for coordinates the operator typed in
  // without first selecting a target from the catalog.
  async targetsCreate(payload) {
    return this._post('/api/targets', payload);
  }


  /**
   * Start a pairing session. The server prints a 6-digit code to its console;
   * the operator then types it into the dashboard's pairing modal.
   * @returns {Promise<{expiresAt:string, expiresInSeconds:number}>}
   */
  async pairingStart() {
    return this._post('/api/pairing/start', {});
  }

  /**
   * Complete pairing by submitting the 6-digit code shown on the desktop
   * console. On success the server returns a bearer token and scope.
   * The server expects field name `code` (not `pairingCode`).
   * @param {string} code 6-digit pairing code
   * @param {string} deviceName Human-readable browser identity
   * @param {string} deviceId Stable identifier for this browser profile
   */
  async pairWithCode(code, deviceName, deviceId) {
    return this._post('/api/pairing/verify', {
      code,
      deviceName,
      deviceId,
      deviceType: 'browser',
    });
  }

  /**
   * Request a single-use 60-second WebSocket auth ticket. Used so the bearer
   * token never has to appear as a query parameter on the /events upgrade
   * (which would leak it into HTTP/proxy logs). Requires an authenticated
   * session — the server's auth middleware verifies the bearer first.
   * @returns {Promise<{ticket:string, expiresInSeconds:number}>}
   */
  async issueWebSocketTicket() {
    return this._post('/api/ws/ticket', {});
  }

  /**
   * Exchange the current bearer token for an HttpOnly session cookie + CSRF
   * token (§2.5 long-form). The server sets `Set-Cookie` with HttpOnly,
   * Secure, SameSite=Strict; the cookie value never enters JS. The returned
   * CSRF token is stashed in memory and echoed via `X-Nightshade-CSRF` on
   * every subsequent write.
   *
   * After this call the API client switches to the cookie path: the bearer
   * is no longer sent in the Authorization header, and the in-memory bearer
   * is cleared so a stray console.log cannot exfiltrate it.
   */
  async beginCookieSession() {
    if (!this._authToken) {
      throw new Error('No bearer token to upgrade — pair first.');
    }
    // Why we still send Authorization on THIS call: the server requires the
    // raw bearer to mint a cookie (no cookie-to-cookie escalation). After
    // it returns we flip _useSessionCookie on so future requests omit it.
    const result = await this._request('POST', '/api/auth/cookie', {});
    const csrf = result && result.csrfToken ? String(result.csrfToken) : '';
    if (!csrf) {
      throw new Error('Server did not return a CSRF token.');
    }
    this._csrfToken = csrf;
    this._useSessionCookie = true;
    // Drop the in-memory bearer so an XSS leak cannot scrape window.api
    // for the raw token. The HttpOnly cookie still carries it server-
    // side; we never need it back in JS.
    this._authToken = '';
    return { csrfToken: csrf, expiresInSeconds: result.expiresInSeconds };
  }

  /**
   * Fetch the CSRF token for an existing session cookie. Called on page
   * load when the dashboard suspects a cookie is present (since cookies are
   * HttpOnly the only way to know is to ask the server). Returns null when
   * the server reports no active session (e.g. cookie expired).
   */
  async tryResumeCookieSession() {
    try {
      const result = await this._request('GET', '/api/auth/csrf');
      const csrf = result && result.csrfToken ? String(result.csrfToken) : '';
      if (!csrf) {
        return null;
      }
      this._csrfToken = csrf;
      this._useSessionCookie = true;
      this._authToken = '';
      return { csrfToken: csrf, expiresInSeconds: result.expiresInSeconds };
    } catch (e) {
      // 401 from /api/auth/csrf simply means "no active session" — return
      // null so the caller falls back to the bearer/pairing path instead
      // of treating it as a hard error.
      return null;
    }
  }

  /**
   * Revoke the HttpOnly session cookie (logout). The browser clears the
   * cookie via the response Set-Cookie; the server drops the bound bearer
   * token so a copied cookie value cannot be reused.
   */
  async endCookieSession() {
    if (!this._useSessionCookie) {
      return;
    }
    try {
      await this._request('POST', '/api/auth/logout', {});
    } catch (_) {
      // Best-effort: even if the network round-trip fails we still want to
      // forget the CSRF token client-side so the SPA stops sending it.
    }
    this._csrfToken = '';
    this._useSessionCookie = false;
  }

  // =========================================================================
  // WebSocket Events
  // =========================================================================

  /**
   * Connect to the event WebSocket.
   * Events are dispatched to listeners registered via on().
   *
   * Why request a ticket first: ?token=<bearer> still works (legacy) but
   * leaks the bearer into HTTP/proxy access logs. A single-use 60-second
   * ticket is preferred; ?token is the fallback when the ticket endpoint is
   * unavailable or when no token is configured.
   */
  async connectWebSocket() {
    if (this._ws && (this._ws.readyState === WebSocket.OPEN || this._ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    let ticket = '';
    if (this._authToken) {
      try {
        const result = await this.issueWebSocketTicket();
        ticket = result && result.ticket ? String(result.ticket) : '';
      } catch (e) {
        // Why swallow: older servers did not expose /api/ws/ticket. Fall back
        // to ?token=, which the server explicitly continues to accept.
        ticket = '';
      }
    }

    let wsUrl = this._baseUrl.replace(/^http/, 'ws') + '/events';
    const query = [];
    if (ticket) {
      query.push('ticket=' + encodeURIComponent(ticket));
    } else if (this._authToken) {
      query.push('token=' + encodeURIComponent(this._authToken));
    }
    if (this._deviceId) {
      query.push('deviceId=' + encodeURIComponent(this._deviceId));
    }
    query.push('apiVersion=' + encodeURIComponent(this._apiVersion));
    if (query.length > 0) {
      wsUrl += (wsUrl.includes('?') ? '&' : '?') + query.join('&');
    }
    this._ws = new WebSocket(wsUrl);

    this._ws.onopen = () => {
      this._wsConnected = true;
      this._wsReconnectDelay = 1000;
      this._lastWsMessageAt = Date.now();
      this._startWebSocketHeartbeatMonitor();
      this._emit('ws:connected', {});
    };

    this._ws.onclose = () => {
      this._wsConnected = false;
      this._stopWebSocketHeartbeatMonitor();
      this._emit('ws:disconnected', {});
      this._scheduleReconnect();
    };

    this._ws.onerror = (err) => {
      this._wsConnected = false;
      this._emit('ws:error', { error: err });
    };

    this._ws.onmessage = (msg) => {
      try {
        const data = JSON.parse(msg.data);
        this._lastWsMessageAt = Date.now();

        if (data.type === 'ping') {
          this._ws.send(JSON.stringify({
            type: 'pong',
            timestamp: new Date().toISOString(),
          }));
          return;
        }

        if (data.type === 'pong') {
          return;
        }

        this._emit('event', data);

        // Also emit by category if present
        if (data.category) {
          this._emit('event:' + data.category, data);
        }
      } catch (e) {
        // Non-JSON message, emit as raw
        this._emit('event:raw', { raw: msg.data });
      }
    };
  }

  disconnectWebSocket() {
    if (this._wsReconnectTimer) {
      clearTimeout(this._wsReconnectTimer);
      this._wsReconnectTimer = null;
    }
    this._stopWebSocketHeartbeatMonitor();
    if (this._ws) {
      this._ws.close();
      this._ws = null;
    }
    this._wsConnected = false;
  }

  _scheduleReconnect() {
    if (this._wsReconnectTimer) return;
    this._wsReconnectTimer = setTimeout(() => {
      this._wsReconnectTimer = null;
      // Why fire-and-forget: connectWebSocket is async because it requests an
      // auth ticket first. Failures here are surfaced via ws:error events.
      this.connectWebSocket().catch((err) => {
        this._emit('ws:error', { error: err });
      });
    }, this._wsReconnectDelay);
    // Exponential backoff
    this._wsReconnectDelay = Math.min(this._wsReconnectDelay * 1.5, this._maxReconnectDelay);
  }

  /** Send a ping to keep the WebSocket alive */
  sendPing() {
    if (this._ws && this._ws.readyState === WebSocket.OPEN) {
      this._ws.send(JSON.stringify({
        type: 'ping',
        timestamp: new Date().toISOString(),
      }));
    }
  }

  _startWebSocketHeartbeatMonitor() {
    this._stopWebSocketHeartbeatMonitor();
    this._wsHeartbeatTimer = setInterval(() => {
      if (!this._ws || this._ws.readyState !== WebSocket.OPEN) return;
      if (Date.now() - this._lastWsMessageAt <= this._wsHeartbeatTimeoutMs) {
        return;
      }

      this._emit('ws:error', { error: new Error('WebSocket heartbeat timed out') });
      this._ws.close();
    }, 15000);
  }

  _stopWebSocketHeartbeatMonitor() {
    if (this._wsHeartbeatTimer) {
      clearInterval(this._wsHeartbeatTimer);
      this._wsHeartbeatTimer = null;
    }
  }

  // =========================================================================
  // Event Emitter
  // =========================================================================

  /**
   * Listen for events.
   * @param {string} eventName - e.g. 'event', 'event:camera', 'ws:connected'
   * @param {Function} callback
   */
  on(eventName, callback) {
    if (!this._eventListeners.has(eventName)) {
      this._eventListeners.set(eventName, []);
    }
    this._eventListeners.get(eventName).push(callback);
  }

  off(eventName, callback) {
    const listeners = this._eventListeners.get(eventName);
    if (listeners) {
      const idx = listeners.indexOf(callback);
      if (idx >= 0) listeners.splice(idx, 1);
    }
  }

  /**
   * Remove all registered event listeners.
   * Call this before re-registering listeners on reconnect to prevent duplicates.
   */
  removeAllListeners() {
    this._eventListeners.clear();
  }

  _emit(eventName, data) {
    const listeners = this._eventListeners.get(eventName);
    if (listeners) {
      for (const cb of listeners) {
        try { cb(data); } catch (e) { console.error('Event listener error:', e); }
      }
    }
  }

  // =========================================================================
  // Connection test
  // =========================================================================

  /**
   * Test connectivity by hitting /api/info (public, no auth required).
   * Returns the info response or throws on failure.
   */
  async testConnection() {
    const info = await this._getWithTimeout('/api/info', this._connectionTimeoutMs);
    return info;
  }

  setConnectionState(isConnected) {
    this._connected = Boolean(isConnected);
  }
}

// Singleton instance
const api = new NightshadeApi();
