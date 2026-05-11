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

  async focuserHalt(deviceId) {
    return this._post('/api/focuser/halt', { deviceId });
  }

  async autofocusStart(deviceId) {
    return this._post('/api/focuser/autofocus/start', { deviceId });
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
    return this._post('/api/filter-wheel/set-by-name', { deviceId, filterName });
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
