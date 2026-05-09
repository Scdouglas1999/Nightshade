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
  };

  // =========================================================================
  // Initialization
  // =========================================================================

  document.addEventListener('DOMContentLoaded', init);

  function init() {
    // Read saved settings. Tokens stay in sessionStorage unless the user
    // explicitly chooses to remember the token for this browser profile.
    const storedUrl = normalizeServerUrl(localStorage.getItem('nightshade_url'));
    const servedFromServer =
      window.location.protocol === 'http:' || window.location.protocol === 'https:';
    const savedUrl = storedUrl || defaultServerUrl();
    const shouldAutoConnect = !!storedUrl || servedFromServer;
    const rememberToken = localStorage.getItem('nightshade_remember_token') === 'true';
    const savedToken = readStoredToken(rememberToken);
    const savedDeviceName = localStorage.getItem('nightshade_device_name') || defaultDeviceName();
    const savedDeviceId = localStorage.getItem('nightshade_device_id') || generateDeviceId();

    document.getElementById('server-url').value = savedUrl;
    document.getElementById('auth-token').value = savedToken;
    document.getElementById('device-name').value = savedDeviceName;
    document.getElementById('remember-token').checked = rememberToken;
    localStorage.setItem('nightshade_device_id', savedDeviceId);

    // Connect button
    document.getElementById('btn-connect').addEventListener('click', handleConnect);
    document.getElementById('btn-pair').addEventListener('click', handlePair);
    document.getElementById('btn-apply-token').addEventListener('click', handleConnect);
    document.getElementById('remember-token').addEventListener('change', handleRememberTokenChanged);

    // Camera controls
    document.getElementById('btn-expose').addEventListener('click', handleExpose);
    document.getElementById('btn-abort-expose').addEventListener('click', handleAbortExpose);

    // Mount controls
    document.getElementById('btn-mount-n').addEventListener('click', () => handleMountMove(0, 1));
    document.getElementById('btn-mount-s').addEventListener('click', () => handleMountMove(0, -1));
    document.getElementById('btn-mount-e').addEventListener('click', () => handleMountMove(1, 1));
    document.getElementById('btn-mount-w').addEventListener('click', () => handleMountMove(1, -1));
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

    // Guide graph canvas
    setupGuideCanvas();
    setConnectionStatus('disconnected');

    // Auto-connect on load if we have a URL
    if (shouldAutoConnect) {
      handleConnect();
    }
  }

  // =========================================================================
  // Connection
  // =========================================================================

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

    // Persist connection preferences; token storage depends on Remember token.
    localStorage.setItem('nightshade_url', url);
    localStorage.setItem('nightshade_device_id', deviceId);
    writeStoredToken(token, rememberToken);

    // Configure API
    api.configure(url, token, deviceId);
    api.setConnectionState(false);

    stopPolling();
    api.disconnectWebSocket();
    api.removeAllListeners();
    setConnectionStatus('connecting');

    try {
      const info = await api.testConnection();
      state.serverInfo = info;

      if (info.authRequired) {
        document.getElementById('auth-bar').classList.remove('hidden');
      } else {
        document.getElementById('auth-bar').classList.add('hidden');
      }

      if (info.authRequired && !token) {
        setConnectionStatus('disconnected');
        showToast(
          'Server requires pairing or a valid token before remote control is allowed.',
          'error',
        );
        return;
      }

      // Treat the first protected request as the real connection gate.
      // /api/info is public and only tells us the server is reachable.
      await api.getStatus();
      setConnectionStatus('connected');
      api.setConnectionState(true);

      addLogEntry('system', 'Connected to ' + info.name + ' v' + info.version);

      // Start WebSocket
      setupEventListeners();
      api.connectWebSocket();

      // Initial data fetch
      await fetchAllStatus();

      // Start polling
      startPolling();

    } catch (e) {
      setConnectionStatus('disconnected');
      api.setConnectionState(false);
      showToast('Connection failed: ' + e.message, 'error');
      addLogEntry('error', 'Connection failed: ' + e.message);
    }
  }

  async function handlePair() {
    const url = normalizeServerUrl(document.getElementById('server-url').value);
    const pairingCode = document.getElementById('pairing-code').value.trim();
    const deviceName = document.getElementById('device-name').value.trim() || defaultDeviceName();
    const deviceId = localStorage.getItem('nightshade_device_id') || generateDeviceId();

    if (!url) {
      showToast('Enter a valid http:// or https:// server URL first', 'error');
      return;
    }

    document.getElementById('server-url').value = url;

    if (!pairingCode) {
      showToast('Enter the pairing code shown in Nightshade', 'error');
      return;
    }

    localStorage.setItem('nightshade_url', url);
    localStorage.setItem('nightshade_device_id', deviceId);
    localStorage.setItem('nightshade_device_name', deviceName);
    api.configure(url, '', deviceId);

    try {
      const result = await api.pairWithCode(pairingCode, deviceName, deviceId);
      const token = result.token || '';
      if (!token) {
        throw new Error('Pairing completed without a token');
      }

      document.getElementById('auth-token').value = token;
      writeStoredToken(token, document.getElementById('remember-token').checked);
      document.getElementById('pairing-code').value = '';
      showToast('Pairing complete. Connecting...', 'success');
      handleConnect();
    } catch (e) {
      showToast('Pairing failed: ' + e.message, 'error');
      addLogEntry('error', 'Pairing failed: ' + e.message);
    }
  }

  function generateDeviceId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    return 'browser-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
  }

  function readStoredToken(rememberToken) {
    if (rememberToken) {
      return localStorage.getItem('nightshade_token') || '';
    }
    return sessionStorage.getItem('nightshade_token') || '';
  }

  function writeStoredToken(token, rememberToken) {
    localStorage.setItem('nightshade_remember_token', rememberToken ? 'true' : 'false');
    if (rememberToken) {
      localStorage.setItem('nightshade_token', token);
      sessionStorage.removeItem('nightshade_token');
    } else {
      sessionStorage.setItem('nightshade_token', token);
      localStorage.removeItem('nightshade_token');
    }
  }

  function handleRememberTokenChanged() {
    const token = document.getElementById('auth-token').value.trim();
    const rememberToken = document.getElementById('remember-token').checked;
    writeStoredToken(token, rememberToken);
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
    setActionControlsEnabled(status === 'connected');
  }

  function setActionControlsEnabled(enabled) {
    const controls = document.querySelectorAll('.panel button:not(#btn-clear-log)');
    for (const control of controls) {
      control.disabled = !enabled;
    }
  }

  function setupEventListeners() {
    api.on('ws:connected', () => {
      addLogEntry('system', 'WebSocket connected');
    });

    api.on('ws:disconnected', () => {
      addLogEntry('system', 'WebSocket disconnected, reconnecting...');
    });

    api.on('event', (data) => {
      handleServerEvent(data);
    });
  }

  function startPolling() {
    stopPolling();
    // Poll every 3 seconds for status updates
    state.pollInterval = setInterval(fetchAllStatus, 3000);
    // Ping WebSocket every 30 seconds
    state.pingInterval = setInterval(() => api.sendPing(), 30000);
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
  }

  // =========================================================================
  // Data fetching
  // =========================================================================

  async function fetchAllStatus() {
    try {
      await Promise.all([
        fetchDevices(),
        fetchSequencerStatus(),
        fetchGuidingStatus(),
        fetchMountStatusIfConnected(),
        fetchCameraStatusIfConnected(),
      ]);
    } catch (e) {
      // Individual fetch errors are handled inside each function
    }
  }

  async function fetchDevices() {
    try {
      const result = await api.getConnectedDevices();
      state.connectedDevices = result.devices || [];
      renderDevicesPanel();

      // Auto-select device IDs from connected devices
      for (const dev of state.connectedDevices) {
        switch (dev.deviceType) {
          case 'camera': state.cameraDeviceId = dev.id; break;
          case 'mount': state.mountDeviceId = dev.id; break;
          case 'focuser': state.focuserDeviceId = dev.id; break;
          case 'filterWheel': state.filterWheelDeviceId = dev.id; break;
        }
      }
    } catch (e) {
      // Silently ignore - will retry next poll
    }
  }

  async function fetchSequencerStatus() {
    try {
      const status = await api.sequencerGetStatus();
      state.sequencerStatus = status;
      renderSequencerPanel();
    } catch (e) {
      // Silently ignore
    }
  }

  async function fetchGuidingStatus() {
    try {
      const status = await api.phd2GetStatus();
      state.guidingStatus = status;
      renderGuidingPanel();
    } catch (e) {
      // Silently ignore
    }
  }

  async function fetchMountStatusIfConnected() {
    if (!state.mountDeviceId) return;
    try {
      const status = await api.getMountStatus(state.mountDeviceId);
      state.mountStatus = status;
      renderMountPanel();
    } catch (e) {
      // Silently ignore
    }
  }

  async function fetchCameraStatusIfConnected() {
    if (!state.cameraDeviceId) return;
    try {
      const status = await api.getCameraStatus(state.cameraDeviceId);
      state.cameraStatus = status;
      renderCameraStatusInfo();
    } catch (e) {
      // Silently ignore
    }
  }

  // =========================================================================
  // Server events (WebSocket)
  // =========================================================================

  function handleServerEvent(data) {
    // Determine event category for logging
    const category = data.category || data.event_category || 'system';
    const message = data.message || data.description || JSON.stringify(data);

    addLogEntry(category, message);

    // Update specific panels based on event category
    if (category === 'camera' || category === 'imaging') {
      // Refresh camera status on camera events
      fetchCameraStatusIfConnected();
      // If an exposure completed, fetch the last image
      if (data.event === 'exposure_complete' || data.event === 'ExposureComplete'
          || data.event === 'image_ready' || data.event === 'ImageReady') {
        fetchLastImage();
      }
    } else if (category === 'mount') {
      fetchMountStatusIfConnected();
    } else if (category === 'sequencer') {
      fetchSequencerStatus();
    } else if (category === 'guiding' || category === 'phd2') {
      fetchGuidingStatus();
      // Extract guide data if present
      if (data.raDistance !== undefined && data.decDistance !== undefined) {
        addGuideDataPoint(data.raDistance, data.decDistance);
      }
    }
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

      // Schedule fetching the image after exposure completes
      setTimeout(() => fetchLastImage(), (exposureTime + 2) * 1000);
    } catch (e) {
      showToast('Expose failed: ' + e.message, 'error');
      addLogEntry('error', 'Expose failed: ' + e.message);
    }
  }

  async function handleAbortExpose() {
    if (!state.cameraDeviceId) return;
    try {
      await api.cameraAbort(state.cameraDeviceId);
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
        renderImagePreview();
      }
    } catch (e) {
      addLogEntry('error', 'Failed to fetch last image: ' + e.message);
    }
  }

  // =========================================================================
  // Mount Controls
  // =========================================================================

  async function handleMountMove(axis, direction) {
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

  async function handleMountStop() {
    if (!state.mountDeviceId) return;
    try {
      // Stop both axes
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

  function renderImagePreview() {
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

    // displayData is base64-encoded PNG/JPEG from the backend
    if (isSafeBase64ImageData(img.displayData)) {
      const preview = document.createElement('img');
      preview.src = 'data:image/png;base64,' + img.displayData;
      preview.alt = 'Last capture';
      container.appendChild(preview);
    } else {
      container.appendChild(createImagePlaceholder('Image data not available'));
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

    // Pier side
    const pierEl = document.getElementById('mount-pier');
    if (pierEl && ms.sideOfPier !== undefined) {
      pierEl.textContent = ms.sideOfPier;
    }

    // Alt/Az
    const altEl = document.getElementById('mount-alt');
    const azEl = document.getElementById('mount-az');
    if (altEl && ms.altitude !== undefined) altEl.textContent = ms.altitude.toFixed(1) + '\u00B0';
    if (azEl && ms.azimuth !== undefined) azEl.textContent = ms.azimuth.toFixed(1) + '\u00B0';
  }

  // =========================================================================
  // Rendering: Sequencer Panel
  // =========================================================================

  function renderSequencerPanel() {
    const statusEl = document.getElementById('seq-status');
    const nodeEl = document.getElementById('seq-node');
    const messageEl = document.getElementById('seq-message');
    const progressBar = document.getElementById('seq-progress-bar');
    const progressText = document.getElementById('seq-progress-text');

    if (!state.sequencerStatus) {
      if (statusEl) renderBadge(statusEl, 'idle', 'badge-idle');
      if (nodeEl) nodeEl.textContent = '--';
      if (messageEl) messageEl.textContent = '';
      if (progressBar) progressBar.style.width = '0%';
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
      const isGuiding = guidingState.toLowerCase().includes('guid');
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

    // Trim to max points
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

    // Set canvas size to match container
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

    // Clear
    ctx.fillStyle = '#0d1117';
    ctx.fillRect(0, 0, w, h);

    // Grid lines
    ctx.strokeStyle = '#21262d';
    ctx.lineWidth = 1;
    const midY = h / 2;

    // Horizontal center line
    ctx.beginPath();
    ctx.moveTo(0, midY);
    ctx.lineTo(w, midY);
    ctx.stroke();

    // Quarter lines
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

    // Auto-scale: find the max absolute value
    let maxVal = 2; // minimum scale of 2 arcsec
    for (let i = 0; i < raData.length; i++) {
      maxVal = Math.max(maxVal, Math.abs(raData[i]), Math.abs(decData[i]));
    }
    maxVal *= 1.2; // 20% padding

    const xStep = w / (state.maxGuidePoints - 1);

    // Draw RA line (blue)
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

    // Draw Dec line (red)
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

    // Scale label
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

    // Remove empty-state placeholder if present
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
  // Utilities
  // =========================================================================

  function formatRA(raHours) {
    if (raHours == null || isNaN(raHours)) return '--h --m --s';
    const h = Math.floor(raHours);
    const m = Math.floor((raHours - h) * 60);
    const s = ((raHours - h) * 60 - m) * 60;
    return pad2(h) + 'h ' + pad2(m) + 'm ' + pad2(s.toFixed(1)) + 's';
  }

  function formatDec(decDeg) {
    if (decDeg == null || isNaN(decDeg)) return '--\u00B0 --\' --"';
    const sign = decDeg >= 0 ? '+' : '-';
    const abs = Math.abs(decDeg);
    const d = Math.floor(abs);
    const m = Math.floor((abs - d) * 60);
    const s = ((abs - d) * 60 - m) * 60;
    return sign + pad2(d) + '\u00B0 ' + pad2(m) + "' " + pad2(s.toFixed(0)) + '"';
  }

  function pad2(val) {
    const s = String(val);
    return s.length < 2 ? '0' + s : s;
  }

  function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

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

  function isSafeBase64ImageData(value) {
    if (!value || typeof value !== 'string') return false;
    if (value.length > 24 * 1024 * 1024) return false;
    return /^[A-Za-z0-9+/]+={0,2}$/.test(value);
  }

  // =========================================================================
  // Toast Notifications
  // =========================================================================

  function showToast(message, type) {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = 'toast' + (type ? ' ' + type : '');
    toast.textContent = message;
    container.appendChild(toast);

    setTimeout(() => {
      toast.classList.add('fading-out');
      setTimeout(() => toast.remove(), 300);
    }, 4000);
  }

})();
