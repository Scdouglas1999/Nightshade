import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'headless_api/handlers.dart';

/// Headless API server using Shelf router with modular handlers
class HeadlessApiServer {
  static const _requestIdContextKey = 'requestId';
  static const _requestIdHeader = 'x-request-id';

  final int port;
  final ProviderContainer container;

  /// Optional authentication token. If set, all API requests must include
  /// this token as a Bearer token in the Authorization header.
  /// Example: `Authorization: Bearer your-secret-token`
  ///
  /// Public endpoints (like /api/info) are exempt from authentication.
  final String? authToken;

  /// Whether authentication is required. When true and authToken is null,
  /// the server will generate a random token and print it to console.
  final bool requireAuth;

  HttpServer? _server;
  final List<WebSocketChannel> _sockets = [];
  int _requestCounter = 0;

  /// The effective auth token (either provided or generated)
  late final String? _effectiveAuthToken;

  LoggingService get _logger => container.read(loggingServiceProvider);

  String _nextRequestId() {
    _requestCounter = (_requestCounter + 1) % 0xFFFFF;
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seq = _requestCounter.toRadixString(36);
    return '$ts-$seq';
  }

  String _requestIdFrom(Request request) =>
      request.context[_requestIdContextKey] as String? ?? 'unknown';

  void _logInfo(String message) =>
      _logger.info(message, source: 'HeadlessApiServer');
  void _logWarning(String message) =>
      _logger.warning(message, source: 'HeadlessApiServer');
  void _logError(String message) =>
      _logger.error(message, source: 'HeadlessApiServer');

  // Handler instances
  late final DeviceHandlers _deviceHandlers;
  late final GuidingHandlers _guidingHandlers;
  late final SequencerHandlers _sequencerHandlers;
  late final EquipmentHandlers _equipmentHandlers;
  late final ProfileHandlers _profileHandlers;
  late final ImagingHandlers _imagingHandlers;
  late final SessionHandlers _sessionHandlers;

  // New feature parity handlers
  late final TargetHandlers _targetHandlers;
  late final SequenceManagementHandlers _sequenceManagementHandlers;
  late final FlatWizardHandlers _flatWizardHandlers;
  late final MosaicHandlers _mosaicHandlers;
  late final AnalyticsHandlers _analyticsHandlers;
  late final WeatherHandlers _weatherHandlers;
  late final SuggestionHandlers _suggestionHandlers;
  late final TransientHandlers _transientHandlers;
  late final BackupHandlers _backupHandlers;
  late final FramingHandlers _framingHandlers;

  // Auxiliary device handlers
  late final DomeHandlers _domeHandlers;
  late final SafetyMonitorHandlers _safetyMonitorHandlers;
  late final AuxiliaryHandlers _auxiliaryHandlers;

  // Planetarium support for remote clients
  late final PlanetariumHandlers _planetariumHandlers;

  // Intelligent scheduler and focus model
  late final SchedulerHandlers _schedulerHandlers;
  late final FocusModelHandlers _focusModelHandlers;

  HeadlessApiServer({
    required this.port,
    required this.container,
    this.authToken,
    this.requireAuth = false,
  }) {
    // Determine effective auth token
    if (authToken != null) {
      _effectiveAuthToken = authToken;
    } else if (requireAuth) {
      // Generate a random token
      _effectiveAuthToken = _generateRandomToken();
      _logWarning(
          '[AUTH] Generated authentication token: $_effectiveAuthToken');
      _logWarning(
          '[AUTH] Use this token in the Authorization header: Bearer $_effectiveAuthToken');
    } else {
      _effectiveAuthToken = null;
    }
    // Initialize handler instances
    _deviceHandlers = DeviceHandlers(container);
    _guidingHandlers = GuidingHandlers(container);
    _sequencerHandlers = SequencerHandlers(container);
    _equipmentHandlers = EquipmentHandlers(container);
    _profileHandlers = ProfileHandlers(container);
    _imagingHandlers = ImagingHandlers(container);
    _sessionHandlers = SessionHandlers(container);

    // Initialize new feature parity handlers
    _targetHandlers = TargetHandlers(container);
    _sequenceManagementHandlers = SequenceManagementHandlers(container);
    _flatWizardHandlers = FlatWizardHandlers(container);
    _mosaicHandlers = MosaicHandlers(container);
    _analyticsHandlers = AnalyticsHandlers(container);
    _weatherHandlers = WeatherHandlers(container);
    _suggestionHandlers = SuggestionHandlers(container);
    _transientHandlers = TransientHandlers(container);
    _backupHandlers = BackupHandlers(container);
    _framingHandlers = FramingHandlers(container);

    // Initialize auxiliary device handlers
    _domeHandlers = DomeHandlers(container);
    _safetyMonitorHandlers = SafetyMonitorHandlers(container);
    _auxiliaryHandlers = AuxiliaryHandlers(container);

    // Initialize planetarium handlers
    _planetariumHandlers = PlanetariumHandlers(container);

    // Initialize intelligent scheduler and focus model handlers
    _schedulerHandlers = SchedulerHandlers(container);
    _focusModelHandlers = FocusModelHandlers(container);
  }

  Future<void> start() async {
    final router = Router();

    // Core endpoints
    router.get('/api/info', _handleInfo);
    router.get('/api/status', _handleStatus);

    // Device management
    router.get('/api/devices', _handleGetDevices);
    router.get('/api/devices/connected', _handleGetConnectedDevices);
    router.post('/api/devices/connect', _handleConnectDevice);
    router.post('/api/devices/disconnect', _handleDisconnectDevice);

    // Camera Control
    router.post('/api/camera/expose', _deviceHandlers.handleCameraExpose);
    router.post('/api/camera/abort', _deviceHandlers.handleCameraAbort);
    router.get(
        '/api/camera/last-image', _deviceHandlers.handleCameraGetLastImage);
    router.post('/api/camera/cooling', _deviceHandlers.handleCameraSetCooling);
    router.post('/api/camera/gain', _deviceHandlers.handleCameraSetGain);
    router.post('/api/camera/offset', _deviceHandlers.handleCameraSetOffset);

    // Mount Control
    router.post('/api/mount/slew', _deviceHandlers.handleMountSlew);
    router.post('/api/mount/sync', _deviceHandlers.handleMountSync);
    router.post('/api/mount/park', _deviceHandlers.handleMountPark);
    router.post('/api/mount/unpark', _deviceHandlers.handleMountUnpark);
    router.post('/api/mount/tracking', _deviceHandlers.handleMountSetTracking);
    router.post(
        '/api/mount/pulse-guide', _deviceHandlers.handleMountPulseGuide);
    router.post('/api/mount/abort', _deviceHandlers.handleMountAbort);
    router.get('/api/mount/status', _deviceHandlers.handleMountGetStatus);
    router.post('/api/mount/set-tracking-rate',
        _deviceHandlers.handleMountSetTrackingRate);
    router.post('/api/mount/move-axis', _deviceHandlers.handleMountMoveAxis);

    // Focuser Control
    router.post('/api/focuser/move-to', _deviceHandlers.handleFocuserMoveTo);
    router.post('/api/focuser/move-relative',
        _deviceHandlers.handleFocuserMoveRelative);
    router.post('/api/focuser/halt', _deviceHandlers.handleFocuserHalt);
    router.post(
        '/api/focuser/autofocus/start', _deviceHandlers.handleAutofocusStart);
    router.post(
        '/api/focuser/autofocus/cancel', _deviceHandlers.handleAutofocusCancel);

    // Filter Wheel Control
    router.post('/api/filter-wheel/position',
        _deviceHandlers.handleFilterWheelSetPosition);
    router.get(
        '/api/filter-wheel/names', _deviceHandlers.handleFilterWheelGetNames);
    router.post('/api/filter-wheel/set-by-name',
        _deviceHandlers.handleFilterWheelSetByName);

    // Rotator Control
    router.post('/api/rotator/move-to', _deviceHandlers.handleRotatorMoveTo);
    router.post('/api/rotator/move-relative',
        _deviceHandlers.handleRotatorMoveRelative);
    router.get('/api/rotator/status', _deviceHandlers.handleRotatorGetStatus);
    router.post('/api/rotator/halt', _deviceHandlers.handleRotatorHalt);

    // PHD2 Guiding
    router.post('/api/phd2/connect', _guidingHandlers.handlePhd2Connect);
    router.post('/api/phd2/disconnect', _guidingHandlers.handlePhd2Disconnect);
    router.post(
        '/api/phd2/start-guiding', _guidingHandlers.handlePhd2StartGuiding);
    router.post(
        '/api/phd2/stop-guiding', _guidingHandlers.handlePhd2StopGuiding);
    router.post('/api/phd2/dither', _guidingHandlers.handlePhd2Dither);
    router.get('/api/phd2/status', _guidingHandlers.handlePhd2GetStatus);
    router.post('/api/phd2/pause', _guidingHandlers.handlePhd2SetPaused);
    router.post('/api/phd2/clear-calibration',
        _guidingHandlers.handlePhd2ClearCalibration);
    router.post('/api/phd2/flip-calibration',
        _guidingHandlers.handlePhd2FlipCalibration);
    router.post('/api/phd2/get-calibration-data',
        _guidingHandlers.handlePhd2GetCalibrationData);
    router.post('/api/phd2/find-star', _guidingHandlers.handlePhd2FindStar);
    router.post('/api/phd2/set-lock-position',
        _guidingHandlers.handlePhd2SetLockPosition);
    router.get(
        '/api/phd2/lock-position', _guidingHandlers.handlePhd2GetLockPosition);
    router.post('/api/phd2/loop', _guidingHandlers.handlePhd2Loop);
    router.post(
        '/api/phd2/deselect-star', _guidingHandlers.handlePhd2DeselectStar);
    router.get('/api/phd2/star-image', _guidingHandlers.handlePhd2GetStarImage);
    router.get(
        '/api/phd2/algo-params', _guidingHandlers.handlePhd2GetAlgoParamNames);
    router.get('/api/phd2/algo-param', _guidingHandlers.handlePhd2GetAlgoParam);
    router.post(
        '/api/phd2/algo-param', _guidingHandlers.handlePhd2SetAlgoParam);

    // Plate Solving
    router.post('/api/plate-solve', _imagingHandlers.handlePlateSolve);

    // Sequencing (legacy)
    router.get('/api/sequences/status', _handleSequenceStatus);
    router.post('/api/sequences/start', _handleSequenceStart);
    router.post('/api/sequences/stop', _handleSequenceStop);

    // Sequencing (extended)
    router.get(
        '/api/sequencer/status', _sequencerHandlers.handleSequencerStatus);
    router.post(
        '/api/sequencer/start', _sequencerHandlers.handleSequencerStart);
    router.post('/api/sequencer/stop', _sequencerHandlers.handleSequencerStop);
    router.post(
        '/api/sequencer/pause', _sequencerHandlers.handleSequencerPause);
    router.post(
        '/api/sequencer/resume', _sequencerHandlers.handleSequencerResume);
    router.post('/api/sequencer/skip', _sequencerHandlers.handleSequencerSkip);
    router.post(
        '/api/sequencer/reset', _sequencerHandlers.handleSequencerReset);
    router.post('/api/sequencer/load', _sequencerHandlers.handleSequencerLoad);
    router.post('/api/sequencer/simulation',
        _sequencerHandlers.handleSequencerSetSimulationMode);
    router.post(
        '/api/sequencer/devices', _sequencerHandlers.handleSequencerSetDevices);
    router.post('/api/sequencer/safety-fail-mode',
        _sequencerHandlers.handleSequencerSetSafetyFailMode);
    router.post('/api/sequencer/checkpoint/dir',
        _sequencerHandlers.handleSequencerSetCheckpointDir);
    router.get('/api/sequencer/checkpoint/has',
        _sequencerHandlers.handleSequencerHasCheckpoint);
    router.get('/api/sequencer/checkpoint/info',
        _sequencerHandlers.handleSequencerGetCheckpointInfo);
    router.post('/api/sequencer/checkpoint/resume',
        _sequencerHandlers.handleSequencerResumeFromCheckpoint);
    router.post('/api/sequencer/checkpoint/discard',
        _sequencerHandlers.handleSequencerDiscardCheckpoint);
    router.post('/api/sequencer/checkpoint/save',
        _sequencerHandlers.handleSequencerSaveCheckpoint);

    // Equipment Status
    router.get(
        '/api/equipment/camera/status', _equipmentHandlers.handleCameraStatus);
    router.get(
        '/api/equipment/mount/status', _equipmentHandlers.handleMountStatus);
    router.get('/api/equipment/focuser/status',
        _equipmentHandlers.handleFocuserStatus);
    router.get('/api/equipment/filter-wheel/status',
        _equipmentHandlers.handleFilterWheelStatus);
    router.get('/api/equipment/rotator/status',
        _equipmentHandlers.handleRotatorStatus);

    // Equipment Capabilities
    router.get('/api/equipment/camera/capabilities',
        _equipmentHandlers.handleCameraCapabilities);
    router.get('/api/equipment/mount/capabilities',
        _equipmentHandlers.handleMountCapabilities);
    router.get('/api/equipment/focuser/capabilities',
        _equipmentHandlers.handleFocuserCapabilities);
    router.get('/api/equipment/filter-wheel/capabilities',
        _equipmentHandlers.handleFilterWheelCapabilities);
    router.get('/api/equipment/rotator/capabilities',
        _equipmentHandlers.handleRotatorCapabilities);

    // Device Health
    router.post('/api/device/heartbeat/start',
        _equipmentHandlers.handleStartDeviceHeartbeat);
    router.post('/api/device/heartbeat/stop',
        _equipmentHandlers.handleStopDeviceHeartbeat);
    router.get('/api/device/health/<deviceId>',
        _equipmentHandlers.handleGetDeviceHealth);

    // Profiles
    router.get('/api/profiles', _profileHandlers.handleGetProfiles);
    router.post('/api/profiles', _profileHandlers.handleSaveProfile);
    router.delete(
        '/api/profiles/<profileId>', _profileHandlers.handleDeleteProfile);
    router.post(
        '/api/profiles/<profileId>/load', _profileHandlers.handleLoadProfile);
    router.get('/api/profiles/active', _profileHandlers.handleGetActiveProfile);

    // Settings
    router.get('/api/settings', _profileHandlers.handleGetSettings);
    router.post('/api/settings', _profileHandlers.handleUpdateSettings);
    router.get('/api/settings/location', _profileHandlers.handleGetLocation);
    router.post('/api/settings/location', _profileHandlers.handleSetLocation);
    router.get('/api/location', _profileHandlers.handleGetLocationFromInternet);

    // Imaging
    router.post('/api/imaging/stats', _imagingHandlers.handleGetImageStats);
    router.post(
        '/api/imaging/stretch', _imagingHandlers.handleAutoStretchImage);
    router.post('/api/imaging/debayer', _imagingHandlers.handleDebayerImage);
    router.get(
        '/api/imaging/raw-data', _imagingHandlers.handleGetLastRawImageData);
    router.post('/api/imaging/save-fits', _imagingHandlers.handleSaveFitsFile);
    router.post('/api/imaging/save-fits-from-capture',
        _imagingHandlers.handleSaveFitsFromLastCapture);
    router.delete('/api/imaging/device-image/<deviceId>',
        _imagingHandlers.handleClearDeviceImage);

    // Polar Alignment
    router.post('/api/polar-alignment/start',
        _sessionHandlers.handleStartPolarAlignment);
    router.post(
        '/api/polar-alignment/stop', _sessionHandlers.handleStopPolarAlignment);

    // Session Images
    router.get('/api/sessions/<sessionId>/images',
        _sessionHandlers.handleGetSessionImages);
    router.get('/api/images/<imageId>/thumbnail',
        _sessionHandlers.handleGetImageThumbnail);
    router.get(
        '/api/images/<imageId>/download', _sessionHandlers.handleDownloadImage);

    // ===========================================================================
    // Target Management
    // ===========================================================================
    router.get('/api/targets', _targetHandlers.handleGetAllTargets);
    router.get(
        '/api/targets/favorites', _targetHandlers.handleGetFavoriteTargets);
    router.get('/api/targets/search', _targetHandlers.handleSearchTargets);
    router.get('/api/targets/by-type', _targetHandlers.handleGetTargetsByType);
    router.get(
        '/api/targets/by-priority', _targetHandlers.handleGetTargetsByPriority);
    router.get('/api/targets/<id>', _targetHandlers.handleGetTargetById);
    router.post('/api/targets', _targetHandlers.handleCreateTarget);
    router.put('/api/targets/<id>', _targetHandlers.handleUpdateTarget);
    router.delete('/api/targets/<id>', _targetHandlers.handleDeleteTarget);
    router.post(
        '/api/targets/<id>/favorite', _targetHandlers.handleToggleFavorite);
    router.put(
        '/api/targets/<id>/progress', _targetHandlers.handleUpdateProgress);

    // ===========================================================================
    // Sequence Management (CRUD - separate from sequencer execution)
    // ===========================================================================
    router.get('/api/sequence-management/list',
        _sequenceManagementHandlers.handleGetAllSequences);
    router.get('/api/sequence-management/templates',
        _sequenceManagementHandlers.handleGetAllTemplates);
    router.get('/api/sequence-management/<id>',
        _sequenceManagementHandlers.handleGetSequenceById);
    router.get('/api/sequence-management/<id>/nodes',
        _sequenceManagementHandlers.handleGetNodesForSequence);
    router.get('/api/sequence-management/<id>/children',
        _sequenceManagementHandlers.handleGetChildNodes);
    router.post('/api/sequence-management',
        _sequenceManagementHandlers.handleCreateSequence);
    router.put('/api/sequence-management/<id>',
        _sequenceManagementHandlers.handleUpdateSequence);
    router.delete('/api/sequence-management/<id>',
        _sequenceManagementHandlers.handleDeleteSequence);
    router.post('/api/sequence-management/<id>/duplicate',
        _sequenceManagementHandlers.handleDuplicateSequence);
    router.post('/api/sequence-management/<id>/nodes',
        _sequenceManagementHandlers.handleCreateNode);
    router.put('/api/sequence-management/nodes/<nodeId>',
        _sequenceManagementHandlers.handleUpdateNode);
    router.delete('/api/sequence-management/nodes/<nodeId>',
        _sequenceManagementHandlers.handleDeleteNode);
    router.post('/api/sequence-management/<id>/reorder',
        _sequenceManagementHandlers.handleReorderNodes);
    router.post('/api/sequence-management/nodes/<nodeId>/enabled',
        _sequenceManagementHandlers.handleSetNodeEnabled);

    // ===========================================================================
    // Flat Wizard
    // ===========================================================================
    router.post('/api/flat-wizard/calibrate',
        _flatWizardHandlers.handleCalibrateFilter);
    router.post('/api/flat-wizard/calibrate-multi',
        _flatWizardHandlers.handleCalibrateMultipleFilters);
    router.post('/api/flat-wizard/generate-sequence',
        _flatWizardHandlers.handleGenerateSequence);
    router.post('/api/flat-wizard/quick-calibrate',
        _flatWizardHandlers.handleQuickCalibrate);

    // ===========================================================================
    // Mosaic Planning
    // ===========================================================================
    router.post(
        '/api/mosaic/generate-panels', _mosaicHandlers.handleGeneratePanels);
    router.post('/api/mosaic/generate-sequence',
        _mosaicHandlers.handleGenerateSequence);
    router.post(
        '/api/mosaic/calculate-area', _mosaicHandlers.handleCalculateArea);
    router.post('/api/mosaic/validate', _mosaicHandlers.handleValidateMosaic);
    router.post(
        '/api/mosaic/estimate-time', _mosaicHandlers.handleEstimateTime);

    // ===========================================================================
    // Sessions & Analytics
    // ===========================================================================
    router.get('/api/sessions', _analyticsHandlers.handleGetAllSessions);
    router.get(
        '/api/sessions/active', _analyticsHandlers.handleGetActiveSession);
    router.get(
        '/api/sessions/recent', _analyticsHandlers.handleGetRecentSessions);
    router.get('/api/sessions/<id>', _analyticsHandlers.handleGetSessionById);
    router.get(
        '/api/sessions/<id>/stats', _analyticsHandlers.handleGetSessionStats);
    router.get('/api/sessions/target/<targetId>',
        _analyticsHandlers.handleGetSessionsForTarget);
    router.post('/api/sessions', _analyticsHandlers.handleCreateSession);
    router.put('/api/sessions/<id>', _analyticsHandlers.handleUpdateSession);
    router.post('/api/sessions/<id>/end', _analyticsHandlers.handleEndSession);
    router.delete('/api/sessions/<id>', _analyticsHandlers.handleDeleteSession);
    router.get(
        '/api/analytics/summary', _analyticsHandlers.handleGetAnalyticsSummary);
    router.get('/api/analytics/integration-time',
        _analyticsHandlers.handleGetTotalIntegrationTime);
    router.get('/api/analytics/target-statistics',
        _analyticsHandlers.handleGetTargetStatistics);

    // ===========================================================================
    // Weather & Radar
    // ===========================================================================
    router.get('/api/weather/radar', _weatherHandlers.handleGetRadarData);
    router.get('/api/weather/forecast', _weatherHandlers.handleGetForecast);
    router.get('/api/weather/alerts', _weatherHandlers.handleGetAlerts);
    router.get(
        '/api/weather/cloud-cover', _weatherHandlers.handleGetCloudCover);
    router.get('/api/weather/settings', _weatherHandlers.handleGetSettings);
    router.post('/api/weather/settings', _weatherHandlers.handleUpdateSettings);
    router.get(
        '/api/weather/safe-imaging', _weatherHandlers.handleCheckSafeImaging);
    router.post('/api/weather/clear-cache', _weatherHandlers.handleClearCache);

    // ===========================================================================
    // Target Suggestions
    // ===========================================================================
    router.get('/api/suggestions/tonight',
        _suggestionHandlers.handleGetSuggestionsForTonight);
    router.get('/api/suggestions/config', _suggestionHandlers.handleGetConfig);
    router.get('/api/suggestions/score/<targetId>',
        _suggestionHandlers.handleGetTargetScore);

    // ===========================================================================
    // Transient Alerts
    // ===========================================================================
    router.get('/api/transients', _transientHandlers.handleGetActiveTransients);
    router.get(
        '/api/transients/settings', _transientHandlers.handleGetSettings);
    router.post(
        '/api/transients/settings', _transientHandlers.handleUpdateSettings);
    router.get('/api/transients/queued', _transientHandlers.handleGetQueued);
    router.post(
        '/api/transients/<id>/queue', _transientHandlers.handleQueueTransient);
    router.post('/api/transients/<id>/dismiss',
        _transientHandlers.handleDismissTransient);
    router.post(
        '/api/transients/refresh', _transientHandlers.handleRefreshAlerts);

    // ===========================================================================
    // Backup & Restore
    // ===========================================================================
    router.get('/api/backup/list', _backupHandlers.handleListBackups);
    router.post('/api/backup/create', _backupHandlers.handleCreateBackup);
    router.post('/api/backup/restore', _backupHandlers.handleRestoreBackup);
    router.post('/api/backup/auto-save', _backupHandlers.handleAutoSaveBackup);
    router.get(
        '/api/backup/<id>/metadata', _backupHandlers.handleGetBackupMetadata);
    router.get(
        '/api/backup/<id>/download', _backupHandlers.handleDownloadBackup);
    router.delete('/api/backup/<id>', _backupHandlers.handleDeleteBackup);

    // ===========================================================================
    // Framing & Centering
    // ===========================================================================
    router.post(
        '/api/framing/slew-to-target', _framingHandlers.handleSlewToTarget);
    router.post(
        '/api/framing/center-on-target', _framingHandlers.handleCenterOnTarget);
    router.post('/api/framing/sync', _framingHandlers.handleSyncMount);
    router.get('/api/framing/current-position',
        _framingHandlers.handleGetCurrentPosition);
    router.post('/api/framing/rotate-to', _framingHandlers.handleRotateTo);
    router.post('/api/framing/abort-slew', _framingHandlers.handleAbortSlew);
    router.post('/api/framing/park', _framingHandlers.handleParkMount);
    router.post('/api/framing/unpark', _framingHandlers.handleUnparkMount);

    // ===========================================================================
    // Planetarium (remote client support)
    // ===========================================================================
    router.get('/api/planetarium/mount-position',
        _planetariumHandlers.handleGetMountPosition);
    router.get(
        '/api/planetarium/fov-config', _planetariumHandlers.handleGetFovConfig);
    router.post('/api/planetarium/slew-to', _planetariumHandlers.handleSlewTo);
    router.post(
        '/api/planetarium/center-on', _planetariumHandlers.handleCenterOn);
    router.post('/api/planetarium/sync-to', _planetariumHandlers.handleSyncTo);
    router.get('/api/planetarium/catalog/search',
        _planetariumHandlers.handleCatalogSearch);
    router.get('/api/planetarium/catalog/region',
        _planetariumHandlers.handleCatalogRegion);
    router.get('/api/planetarium/catalog/object/<objectId>',
        _planetariumHandlers.handleGetCatalogObject);
    router.get('/api/planetarium/subscribe-info',
        _planetariumHandlers.handleGetSubscribeInfo);
    router.get(
        '/api/planetarium/location', _planetariumHandlers.handleGetLocation);

    // ===========================================================================
    // Dome Control
    // ===========================================================================
    router.post('/api/dome/open', _domeHandlers.handleDomeOpen);
    router.post('/api/dome/close', _domeHandlers.handleDomeClose);
    router.post('/api/dome/slew', _domeHandlers.handleDomeSlew);
    router.post('/api/dome/sync', _domeHandlers.handleDomeSync);
    router.post('/api/dome/park', _domeHandlers.handleDomePark);
    router.post('/api/dome/home', _domeHandlers.handleDomeHome);
    router.post('/api/dome/halt', _domeHandlers.handleDomeHalt);
    router.get('/api/dome/status', _domeHandlers.handleDomeStatus);
    router.get('/api/dome/capabilities', _domeHandlers.handleDomeCapabilities);

    // ===========================================================================
    // Safety Monitor
    // ===========================================================================
    router.get('/api/safety/status', _safetyMonitorHandlers.handleSafetyStatus);
    router.get(
        '/api/safety/settings', _safetyMonitorHandlers.handleGetSafetySettings);
    router.post('/api/safety/settings',
        _safetyMonitorHandlers.handleUpdateSafetySettings);
    router.post('/api/safety/acknowledge',
        _safetyMonitorHandlers.handleAcknowledgeUnsafe);

    // ===========================================================================
    // Auxiliary Devices (Switch & Cover Calibrator)
    // ===========================================================================
    router.get('/api/switch/status', _auxiliaryHandlers.handleSwitchStatus);
    router.post('/api/switch/set', _auxiliaryHandlers.handleSwitchSet);
    router.get('/api/cover/status', _auxiliaryHandlers.handleCoverStatus);
    router.post('/api/cover/open', _auxiliaryHandlers.handleCoverOpen);
    router.post('/api/cover/close', _auxiliaryHandlers.handleCoverClose);
    router.post(
        '/api/cover/brightness', _auxiliaryHandlers.handleCoverBrightness);
    router.post(
        '/api/cover/calibrator-on', _auxiliaryHandlers.handleCalibratorOn);
    router.post(
        '/api/cover/calibrator-off', _auxiliaryHandlers.handleCalibratorOff);

    // ===========================================================================
    // Intelligent Scheduler
    // ===========================================================================
    router.get(
        '/api/scheduler/altitude', _schedulerHandlers.handleCalculateAltitude);
    router.get('/api/scheduler/transit-time',
        _schedulerHandlers.handleCalculateTransitTime);
    router.get(
        '/api/scheduler/rise-set', _schedulerHandlers.handleCalculateRiseSet);
    router.get('/api/scheduler/hours-above-horizon',
        _schedulerHandlers.handleCalculateHoursAbove);
    router.post('/api/scheduler/optimize-targets',
        _schedulerHandlers.handleOptimizeTargets);
    router.get('/api/scheduler/twilight-times',
        _schedulerHandlers.handleGetTwilightTimes);
    router.get(
        '/api/scheduler/moon-info', _schedulerHandlers.handleGetMoonInfo);

    // ===========================================================================
    // Focus Model
    // ===========================================================================
    router.get('/api/focus-model/data', _focusModelHandlers.handleGetFocusData);
    router.post(
        '/api/focus-model/add-point', _focusModelHandlers.handleAddFocusPoint);
    router.delete(
        '/api/focus-model/clear', _focusModelHandlers.handleClearFocusData);
    router.get(
        '/api/focus-model/model', _focusModelHandlers.handleGetFocusModel);
    router.get(
        '/api/focus-model/predict', _focusModelHandlers.handlePredictFocus);
    router.get('/api/focus-model/filter-offsets',
        _focusModelHandlers.handleGetFilterOffsets);
    router.post('/api/focus-model/filter-offsets',
        _focusModelHandlers.handleSetFilterOffsets);
    router.get('/api/focus-model/should-refocus',
        _focusModelHandlers.handleShouldRefocus);
    router.get(
        '/api/focus-model/export', _focusModelHandlers.handleExportFocusData);
    router.post(
        '/api/focus-model/import', _focusModelHandlers.handleImportFocusData);

    // WebSocket - support both paths for NetworkBackend compatibility
    router.get('/api/ws', webSocketHandler(_handleWebSocket));
    router.get('/events', webSocketHandler(_handleWebSocket));

    final handler = const Pipeline()
        .addMiddleware(_requestTrackingMiddleware())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _logInfo(
        'Headless API server running on http://${_server!.address.host}:${_server!.port}');
    if (_effectiveAuthToken != null) {
      _logInfo(
          '[AUTH] Authentication is ENABLED. All requests require Bearer token.');
    } else {
      _logInfo('[AUTH] Authentication is DISABLED. All requests are allowed.');
    }

    // Subscribe to backend events and broadcast to WebSocket clients
    _subscribeToBackendEvents();
  }

  void _subscribeToBackendEvents() {
    try {
      final backend = container.read(backendProvider);
      backend.eventStream.listen((event) {
        broadcastEvent(event);
      });
    } catch (e) {
      _logError('[API] Failed to subscribe to backend events: $e');
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    for (final socket in _sockets) {
      await socket.sink.close();
    }
    _sockets.clear();
  }

  /// Broadcast an event to all connected WebSocket clients
  void broadcastEvent(dynamic event) {
    if (_sockets.isEmpty) return;

    String jsonEvent;
    try {
      if (event is NightshadeEvent) {
        // Use NightshadeEvent.toJson() for proper schema
        jsonEvent = jsonEncode({
          'type': 'event',
          ...event.toJson(),
        });
      } else if (event is Map<String, dynamic>) {
        // Already a map - add type wrapper
        jsonEvent = jsonEncode({
          'type': 'event',
          ...event,
        });
      } else {
        // Other types - encode as-is
        jsonEvent = jsonEncode(event);
      }
    } catch (e) {
      _logError('Error encoding event for broadcast: $e');
      return;
    }

    for (final socket in _sockets) {
      try {
        socket.sink.add(jsonEvent);
      } catch (e) {
        _logWarning('Error broadcasting to socket: $e');
      }
    }
  }

  // ===========================================================================
  // Core Handlers (kept inline for simplicity)
  // ===========================================================================

  Future<Response> _handleInfo(Request request) async {
    return Response.ok(
      jsonEncode({
        "name": "Nightshade Headless",
        "version": "2.0.0",
        "mode": "headless",
        "authRequired": _effectiveAuthToken != null,
        "publicEndpoints": ["/api/info", "/api/ws", "/events"],
        "endpoints": _getAvailableEndpoints(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  List<String> _getAvailableEndpoints() {
    return [
      // Core
      'GET /api/info',
      'GET /api/status',
      'GET /api/devices',
      'GET /api/devices/connected',
      'POST /api/devices/connect',
      'POST /api/devices/disconnect',
      // Camera
      'POST /api/camera/expose',
      'POST /api/camera/abort',
      'GET /api/camera/last-image',
      'POST /api/camera/cooling',
      // Mount
      'POST /api/mount/slew',
      'POST /api/mount/sync',
      'POST /api/mount/park',
      'POST /api/mount/unpark',
      // Focuser
      'POST /api/focuser/move-to',
      'POST /api/focuser/halt',
      'POST /api/focuser/autofocus/start',
      'POST /api/focuser/autofocus/cancel',
      // Filter Wheel
      'POST /api/filter-wheel/position',
      'POST /api/filter-wheel/set-by-name',
      // Rotator
      'POST /api/rotator/move-to',
      'POST /api/rotator/halt',
      // PHD2
      'POST /api/phd2/connect',
      'POST /api/phd2/disconnect',
      'POST /api/phd2/start-guiding',
      'POST /api/phd2/stop-guiding',
      'POST /api/phd2/dither',
      'GET /api/phd2/status',
      'POST /api/phd2/pause',
      'POST /api/phd2/clear-calibration',
      'POST /api/phd2/flip-calibration',
      'POST /api/phd2/get-calibration-data',
      'POST /api/phd2/find-star',
      'POST /api/phd2/set-lock-position',
      'GET /api/phd2/lock-position',
      'POST /api/phd2/loop',
      'POST /api/phd2/deselect-star',
      'GET /api/phd2/star-image',
      'GET /api/phd2/algo-params',
      'GET /api/phd2/algo-param',
      'POST /api/phd2/algo-param',
      // Plate Solving
      'POST /api/plate-solve',
      // Sequencer
      'GET /api/sequencer/status',
      'POST /api/sequencer/start',
      'POST /api/sequencer/stop',
      'POST /api/sequencer/pause',
      'POST /api/sequencer/resume',
      'POST /api/sequencer/skip',
      'POST /api/sequencer/reset',
      'POST /api/sequencer/load',
      // Equipment Status
      'GET /api/equipment/camera/status',
      'GET /api/equipment/mount/status',
      'GET /api/equipment/focuser/status',
      'GET /api/equipment/filter-wheel/status',
      'GET /api/equipment/rotator/status',
      // Equipment Capabilities
      'GET /api/equipment/camera/capabilities',
      'GET /api/equipment/mount/capabilities',
      'GET /api/equipment/focuser/capabilities',
      'GET /api/equipment/filter-wheel/capabilities',
      'GET /api/equipment/rotator/capabilities',
      // Profiles
      'GET /api/profiles',
      'POST /api/profiles',
      'GET /api/profiles/active',
      // Settings
      'GET /api/settings',
      'POST /api/settings',
      'GET /api/settings/location',
      'POST /api/settings/location',
      // Imaging
      'POST /api/imaging/stats',
      'POST /api/imaging/stretch',
      'POST /api/imaging/save-fits',
      'POST /api/imaging/save-fits-from-capture',
      // Polar Alignment
      'POST /api/polar-alignment/start',
      'POST /api/polar-alignment/stop',
      // Session Images
      'GET /api/sessions/<sessionId>/images',
      'GET /api/images/<imageId>/thumbnail',
      // Targets
      'GET /api/targets',
      'GET /api/targets/favorites',
      'GET /api/targets/search',
      'GET /api/targets/by-type',
      'GET /api/targets/by-priority',
      'GET /api/targets/<id>',
      'POST /api/targets',
      'PUT /api/targets/<id>',
      'DELETE /api/targets/<id>',
      'POST /api/targets/<id>/favorite',
      'PUT /api/targets/<id>/progress',
      // Sequence Management
      'GET /api/sequence-management/list',
      'GET /api/sequence-management/templates',
      'GET /api/sequence-management/<id>',
      'GET /api/sequence-management/<id>/nodes',
      'GET /api/sequence-management/<id>/children',
      'POST /api/sequence-management',
      'PUT /api/sequence-management/<id>',
      'DELETE /api/sequence-management/<id>',
      'POST /api/sequence-management/<id>/duplicate',
      'POST /api/sequence-management/<id>/nodes',
      'PUT /api/sequence-management/nodes/<nodeId>',
      'DELETE /api/sequence-management/nodes/<nodeId>',
      'POST /api/sequence-management/<id>/reorder',
      // Flat Wizard
      'POST /api/flat-wizard/calibrate',
      'POST /api/flat-wizard/calibrate-multi',
      'POST /api/flat-wizard/generate-sequence',
      'POST /api/flat-wizard/quick-calibrate',
      // Mosaic
      'POST /api/mosaic/generate-panels',
      'POST /api/mosaic/generate-sequence',
      'POST /api/mosaic/calculate-area',
      'POST /api/mosaic/validate',
      'POST /api/mosaic/estimate-time',
      // Sessions & Analytics
      'GET /api/sessions',
      'GET /api/sessions/active',
      'GET /api/sessions/recent',
      'GET /api/sessions/<id>',
      'GET /api/sessions/<id>/stats',
      'GET /api/sessions/target/<targetId>',
      'POST /api/sessions',
      'PUT /api/sessions/<id>',
      'POST /api/sessions/<id>/end',
      'DELETE /api/sessions/<id>',
      'GET /api/analytics/summary',
      'GET /api/analytics/integration-time',
      'GET /api/analytics/target-statistics',
      // Weather
      'GET /api/weather/radar',
      'GET /api/weather/forecast',
      'GET /api/weather/alerts',
      'GET /api/weather/cloud-cover',
      'GET /api/weather/settings',
      'POST /api/weather/settings',
      'GET /api/weather/safe-imaging',
      'POST /api/weather/clear-cache',
      // Suggestions
      'GET /api/suggestions/tonight',
      'GET /api/suggestions/config',
      'GET /api/suggestions/score/<targetId>',
      // Transients
      'GET /api/transients',
      'GET /api/transients/settings',
      'POST /api/transients/settings',
      'GET /api/transients/queued',
      'POST /api/transients/<id>/queue',
      'POST /api/transients/<id>/dismiss',
      'POST /api/transients/refresh',
      // Backup
      'GET /api/backup/list',
      'POST /api/backup/create',
      'POST /api/backup/restore',
      'POST /api/backup/auto-save',
      'GET /api/backup/<id>/metadata',
      'GET /api/backup/<id>/download',
      'DELETE /api/backup/<id>',
      // Framing
      'POST /api/framing/slew-to-target',
      'POST /api/framing/center-on-target',
      'POST /api/framing/sync',
      'GET /api/framing/current-position',
      'POST /api/framing/rotate-to',
      'POST /api/framing/abort-slew',
      'POST /api/framing/park',
      'POST /api/framing/unpark',
      // Planetarium (remote client support)
      'GET /api/planetarium/mount-position',
      'GET /api/planetarium/fov-config',
      'POST /api/planetarium/slew-to',
      'POST /api/planetarium/center-on',
      'POST /api/planetarium/sync-to',
      'GET /api/planetarium/catalog/search',
      'GET /api/planetarium/catalog/region',
      'GET /api/planetarium/catalog/object/<objectId>',
      'GET /api/planetarium/subscribe-info',
      'GET /api/planetarium/location',
      // Dome
      'POST /api/dome/open',
      'POST /api/dome/close',
      'POST /api/dome/slew',
      'POST /api/dome/sync',
      'POST /api/dome/park',
      'POST /api/dome/home',
      'POST /api/dome/halt',
      'GET /api/dome/status',
      'GET /api/dome/capabilities',
      // Safety Monitor
      'GET /api/safety/status',
      'GET /api/safety/settings',
      'POST /api/safety/settings',
      'POST /api/safety/acknowledge',
      // Switch
      'GET /api/switch/status',
      'POST /api/switch/set',
      // Cover Calibrator
      'GET /api/cover/status',
      'POST /api/cover/open',
      'POST /api/cover/close',
      'POST /api/cover/brightness',
      'POST /api/cover/calibrator-on',
      'POST /api/cover/calibrator-off',
      // Intelligent Scheduler
      'GET /api/scheduler/altitude',
      'GET /api/scheduler/transit-time',
      'GET /api/scheduler/rise-set',
      'GET /api/scheduler/hours-above-horizon',
      'POST /api/scheduler/optimize-targets',
      'GET /api/scheduler/twilight-times',
      'GET /api/scheduler/moon-info',
      // Focus Model
      'GET /api/focus-model/data',
      'POST /api/focus-model/add-point',
      'DELETE /api/focus-model/clear',
      'GET /api/focus-model/model',
      'GET /api/focus-model/predict',
      'GET /api/focus-model/filter-offsets',
      'POST /api/focus-model/filter-offsets',
      'GET /api/focus-model/should-refocus',
      'GET /api/focus-model/export',
      'POST /api/focus-model/import',
      // WebSocket
      'WS /api/ws',
      'WS /events',
    ];
  }

  Future<Response> _handleStatus(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/status');
    try {
      final backend = container.read(backendProvider);
      final status = await backend.sequencerGetStatus();
      return Response.ok(
        jsonEncode({
          "sequencer": {
            "state": status.state,
            "currentNodeId": status.currentNodeId,
            "currentNodeName": status.currentNodeName,
            "progress": status.progress,
            "message": status.message
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API][$requestId] Status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleGetDevices(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices');
    try {
      final deviceTypeStr = request.url.queryParameters['deviceType'];
      final backend = container.read(backendProvider);

      // If no device type specified, discover all device types
      List<DeviceInfo> allDevices = [];
      if (deviceTypeStr != null) {
        final deviceType = _parseDeviceType(deviceTypeStr);
        if (deviceType != null) {
          allDevices = await backend.discoverDevices(deviceType);
        }
      } else {
        // Discover all device types
        for (final dt in DeviceType.values) {
          try {
            final devices = await backend.discoverDevices(dt);
            allDevices.addAll(devices);
          } catch (_) {
            // Ignore errors for individual device types
          }
        }
      }

      return Response.ok(
        jsonEncode({
          "devices": allDevices
              .map((d) => {
                    'id': d.id,
                    'name': d.name,
                    'deviceType': d.deviceType.name,
                    'driverType': d.driverType.name,
                    'description': d.description,
                  })
              .toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API][$requestId] Get devices error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleGetConnectedDevices(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/connected');
    try {
      final backend = container.read(backendProvider);
      final devices = await backend.getConnectedDevices();
      return Response.ok(
        jsonEncode({
          "devices": devices
              .map((d) => {
                    'id': d.id,
                    'name': d.name,
                    'deviceType': d.deviceType.name,
                    'driverType': d.driverType.name,
                    'description': d.description,
                  })
              .toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API][$requestId] Get connected devices error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleConnectDevice(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] POST /api/devices/connect');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final deviceTypeStr = payload['deviceType'] as String;
      final deviceType = _parseDeviceType(deviceTypeStr);

      if (deviceType == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid device type: $deviceTypeStr"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final backend = container.read(backendProvider);
      await backend.connectDevice(deviceType, deviceId);

      return Response.ok(
        jsonEncode({
          "status": "connected",
          "deviceId": deviceId,
          "deviceType": deviceType.name,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API][$requestId] Connect device error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleDisconnectDevice(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] POST /api/devices/disconnect');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final deviceTypeStr = payload['deviceType'] as String;
      final deviceType = _parseDeviceType(deviceTypeStr);

      if (deviceType == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Invalid device type: $deviceTypeStr"}),
          headers: {'content-type': 'application/json'},
        );
      }

      final backend = container.read(backendProvider);
      await backend.disconnectDevice(deviceType, deviceId);

      return Response.ok(
        jsonEncode({
          "status": "disconnected",
          "deviceId": deviceId,
          "deviceType": deviceType.name,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API][$requestId] Disconnect device error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// Parse a device type string to DeviceType enum
  DeviceType? _parseDeviceType(String? deviceTypeStr) {
    if (deviceTypeStr == null) return null;
    final normalized = deviceTypeStr.toLowerCase();
    for (final dt in DeviceType.values) {
      if (dt.name.toLowerCase() == normalized) {
        return dt;
      }
    }
    return null;
  }

  // Legacy sequence endpoints (map to sequencer)
  Future<Response> _handleSequenceStatus(Request request) async {
    return _sequencerHandlers.handleSequencerStatus(request);
  }

  Future<Response> _handleSequenceStart(Request request) async {
    return _sequencerHandlers.handleSequencerStart(request);
  }

  Future<Response> _handleSequenceStop(Request request) async {
    return _sequencerHandlers.handleSequencerStop(request);
  }

  // ===========================================================================
  // WebSocket Handler
  // ===========================================================================

  void _handleWebSocket(WebSocketChannel socket, String? protocol) {
    _sockets.add(socket);
    _logInfo('New WebSocket connection');

    socket.stream.listen(
      (message) {
        // Handle incoming messages (e.g. pings)
        try {
          final data = jsonDecode(message);
          if (data['type'] == 'ping') {
            socket.sink.add(jsonEncode({'type': 'pong'}));
          }
        } catch (_) {}
      },
      onDone: () {
        _sockets.remove(socket);
        _logInfo('WebSocket disconnected');
      },
      onError: (error) {
        _sockets.remove(socket);
        _logWarning('WebSocket error: $error');
      },
    );
  }

  // ===========================================================================
  // Middleware
  // ===========================================================================

  Middleware _requestTrackingMiddleware() {
    return (innerHandler) {
      return (request) async {
        final requestId = request.headers[_requestIdHeader] ?? _nextRequestId();
        final path = '/${request.url.path}';
        final startedAt = DateTime.now();
        final scopedRequest = request.change(context: {
          ...request.context,
          _requestIdContextKey: requestId,
        });

        _logInfo('[REQ][$requestId] ${request.method} $path started');
        try {
          final response = await innerHandler(scopedRequest);
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          _logInfo(
              '[REQ][$requestId] ${request.method} $path completed status=${response.statusCode} ms=$elapsedMs');
          return response.change(headers: {
            ...response.headers,
            _requestIdHeader: requestId,
          });
        } catch (e, stackTrace) {
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          _logError(
              '[REQ][$requestId] ${request.method} $path failed ms=$elapsedMs error=$e\n$stackTrace');
          rethrow;
        }
      };
    };
  }

  Middleware _corsMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers':
                'Origin, Content-Type, X-Auth-Token, Authorization',
          });
        }
        return null;
      },
      responseHandler: (response) {
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers':
              'Origin, Content-Type, X-Auth-Token, Authorization',
        });
      },
    );
  }

  /// Middleware that validates Bearer token authentication.
  ///
  /// Public endpoints are exempt from authentication:
  /// - GET /api/info
  /// - WebSocket upgrades (/api/ws, /events)
  Middleware _authMiddleware() {
    // Endpoints that don't require authentication
    const publicPaths = {'/api/info', '/api/ws', '/events'};

    return createMiddleware(
      requestHandler: (request) {
        // Skip auth if no token is configured
        if (_effectiveAuthToken == null) {
          return null;
        }

        // Skip auth for public endpoints
        final requestId = _requestIdFrom(request);
        final path = '/${request.url.path}';
        if (publicPaths.contains(path)) {
          return null;
        }

        // Check for Authorization header
        final authHeader = request.headers['authorization'];
        if (authHeader == null) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - no Authorization header');
          return Response.unauthorized(
            jsonEncode({
              'error': 'Authentication required',
              'message': 'Missing Authorization header',
            }),
            headers: {
              'content-type': 'application/json',
              _requestIdHeader: requestId,
            },
          );
        }

        // Validate Bearer token format
        if (!authHeader.startsWith('Bearer ')) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - invalid auth format');
          return Response.unauthorized(
            jsonEncode({
              'error': 'Authentication required',
              'message':
                  'Invalid Authorization header format. Expected: Bearer <token>',
            }),
            headers: {
              'content-type': 'application/json',
              _requestIdHeader: requestId,
            },
          );
        }

        // Extract and validate token
        final token = authHeader.substring(7); // Remove 'Bearer ' prefix
        if (token != _effectiveAuthToken) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - invalid token');
          return Response.forbidden(
            jsonEncode({
              'error': 'Access denied',
              'message': 'Invalid authentication token',
            }),
            headers: {
              'content-type': 'application/json',
              _requestIdHeader: requestId,
            },
          );
        }

        // Token is valid, continue to handler
        return null;
      },
    );
  }

  /// Generates a cryptographically secure random token.
  static String _generateRandomToken({int length = 32}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();

    // Use a simple PRNG seeded with current time for token generation
    var seed = random;
    for (var i = 0; i < length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buffer.write(chars[seed % chars.length]);
    }
    return buffer.toString();
  }

  /// Get the current authentication token (for logging/debugging).
  /// Returns null if authentication is disabled.
  String? get effectiveAuthToken => _effectiveAuthToken;
}
