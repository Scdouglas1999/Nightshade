import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_webrtc/nightshade_webrtc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'headless_api/auth/cors_policy.dart';
import 'headless_api/auth/pairing_attempt_tracker.dart';
import 'headless_api/auth/pairing_service.dart';
import 'headless_api/auth/token_resolver.dart';
import 'headless_api/auth/ws_ticket_manager.dart';
import 'headless_api/auth_policy.dart';
import 'headless_api/handlers.dart';
import 'headless_api/response_helpers.dart';
import 'headless_api/route_metadata.dart' as route_metadata;
import 'headless_api/validation.dart';

/// Headless API server using Shelf router with modular handlers
class HeadlessApiServer {
  static const _requestIdContextKey = 'requestId';
  static const _requestIdHeader = 'x-request-id';

  final int port;
  final ProviderContainer container;
  final bool bindLocalOnly;

  /// Optional authentication token. If set, all API requests must include
  /// this token as a Bearer token in the Authorization header.
  /// Example: `Authorization: Bearer your-secret-token`
  ///
  /// Public endpoints (like /api/info) are exempt from authentication.
  final String? authToken;

  /// Whether authentication is required. When true and authToken is null,
  /// the server will generate a random token and print it to console.
  final bool requireAuth;

  /// Additional scoped tokens. The legacy [authToken] remains an admin token.
  final Map<String, HeadlessTokenScope> scopedAuthTokens;
  final Duration webSocketHeartbeatInterval;
  final Duration webSocketHeartbeatTimeout;

  /// Extra browser/origin values allowed to issue cross-origin requests
  /// (beyond same-origin to the bound host:port). Pass as e.g.
  /// `['http://192.168.1.50:3000']`. Why explicit list: the previous policy
  /// reflected any origin matching host:port, which let any local-loopback
  /// app bypass CORS. See §2.27 in 2026-05-09-v250-audit-fixes.md.
  final List<String> corsAllowedOrigins;

  HttpServer? _server;
  final List<WebSocketChannel> _sockets = [];
  final Map<WebSocketChannel, String> _socketViewerIds = {};
  final Map<WebSocketChannel, DateTime> _socketLastSeenAt = {};
  Timer? _webSocketHeartbeatTimer;
  int _requestCounter = 0;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _collaborationSubscription;
  final LiveCollaborationSessionManager _collaborationManager =
      LiveCollaborationSessionManager();
  final route_metadata.EndpointRateLimiter _rateLimiter =
      route_metadata.EndpointRateLimiter();

  /// The effective auth token (either provided or generated)
  late final String? _effectiveAuthToken;
  late final Map<String, HeadlessTokenScope> _effectiveAuthTokensByValue;
  late final TokenResolver _tokenResolver;
  late final CorsAllowList _corsAllowList;
  late final WsTicketManager _wsTicketManager;
  late final PairingAttemptTracker _pairingAttempts;
  PairingService? _pairingService;
  // Tokens minted by completed pairing flows that grant admin scope. Why
  // separate from the configured token table: pairing tokens are persisted
  // in the PairingDatabase (Drift), and we want to honour them without
  // mutating the immutable map of configured tokens.
  final Map<String, HeadlessTokenScope> _pairedSessionTokens = {};

  LoggingService get _logger => container.read(loggingServiceProvider);

  String _nextRequestId() {
    _requestCounter = (_requestCounter + 1) % 0xFFFFF;
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seq = _requestCounter.toRadixString(36);
    return '$ts-$seq';
  }

  String _requestIdFrom(Request request) =>
      request.context[_requestIdContextKey] as String? ?? 'unknown';

  void _logInfo(String message, {Map<String, Object?>? fields}) =>
      _logger.info(message, source: 'HeadlessApiServer', fields: fields);
  void _logWarning(String message, {Map<String, Object?>? fields}) =>
      _logger.warning(message, source: 'HeadlessApiServer', fields: fields);
  void _logError(String message, {Map<String, Object?>? fields}) =>
      _logger.error(message, source: 'HeadlessApiServer', fields: fields);

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
  late final FileSystemHandlers _fileSystemHandlers;
  late final ScienceHandlers _scienceHandlers;

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
    this.bindLocalOnly = true,
    this.authToken,
    this.requireAuth = false,
    this.scopedAuthTokens = const {},
    this.webSocketHeartbeatInterval = const Duration(seconds: 30),
    this.webSocketHeartbeatTimeout = const Duration(seconds: 90),
    this.corsAllowedOrigins = const [],
    PairingService? pairingService,
  }) {
    _pairingService = pairingService;
    final tokensByValue = <String, HeadlessTokenScope>{};

    // Determine effective auth token
    if (authToken != null) {
      _effectiveAuthToken = authToken;
      tokensByValue[authToken!] = HeadlessTokenScope.admin;
    } else if (requireAuth) {
      // Generate a random token
      _effectiveAuthToken = _generateRandomToken();
      tokensByValue[_effectiveAuthToken!] = HeadlessTokenScope.admin;
      _logWarning(
          '[AUTH] Generated authentication token: $_effectiveAuthToken');
      _logWarning(
          '[AUTH] Use this token in the Authorization header: Bearer $_effectiveAuthToken');
    } else {
      _effectiveAuthToken = null;
    }

    for (final entry in scopedAuthTokens.entries) {
      final token = entry.key.trim();
      if (token.isNotEmpty) {
        tokensByValue[token] = entry.value;
      }
    }
    _effectiveAuthTokensByValue = Map.unmodifiable(tokensByValue);
    // Why: the resolver iterates the entire token map every lookup with
    // constant-time comparison. The map captured here is the union of the
    // configured static tokens; paired-session tokens are checked alongside
    // via [_pairedSessionTokens] (also constant-time) when present.
    _tokenResolver = TokenResolver(tokensByValue: _effectiveAuthTokensByValue);
    _corsAllowList = CorsAllowList.fromConfig(
      additionalOrigins: corsAllowedOrigins,
    );
    _wsTicketManager = WsTicketManager();
    _pairingAttempts = PairingAttemptTracker();

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
    _fileSystemHandlers = FileSystemHandlers(container);
    _scienceHandlers = ScienceHandlers(container);

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
    router.get('/api/self-test', _handleSelfTest);
    router.get('/api/openapi.json', _handleOpenApiSpec);

    // Pairing flow (web dashboard first-run UX). See §2.1 in
    // 2026-05-09-v250-audit-fixes.md.
    router.post('/api/pairing/start', _handlePairingStart);
    router.post('/api/pairing/verify', _handlePairingVerify);

    // WebSocket auth ticket (§2.28). Issues a one-shot ticket so browsers
    // don't have to leak the bearer token via WS query parameters.
    router.post('/api/ws/ticket', _handleWsTicketIssue);
    router.get('/api/collaboration/state', _handleCollaborationState);
    router.post('/api/collaboration/viewers/join', _handleCollaborationJoin);
    router.post('/api/collaboration/viewers/leave', _handleCollaborationLeave);
    router.post('/api/collaboration/preview', _handleCollaborationPreview);
    router.post('/api/collaboration/chat', _handleCollaborationChat);
    router.post(
        '/api/collaboration/annotations', _handleCollaborationAnnotation);
    router.get('/api/session-handoff', _handleGetSessionHandoff);
    router.post('/api/session-handoff', _handleSetSessionHandoff);
    router.delete('/api/session-handoff', _handleClearSessionHandoff);

    // Device management
    router.get('/api/devices', _handleGetDevices);
    router.get('/api/devices/discover-indi', _handleDiscoverIndiAtAddress);
    router.get('/api/devices/discover-alpaca', _handleDiscoverAlpacaAtAddress);
    router.get('/api/devices/connected', _handleGetConnectedDevices);
    router.post('/api/devices/connect', _handleConnectDevice);
    router.post('/api/devices/disconnect', _handleDisconnectDevice);

    // Camera Control
    router.post('/api/camera/expose', _deviceHandlers.handleCameraExpose);
    router.post('/api/camera/abort', _deviceHandlers.handleCameraAbort);
    router.get(
        '/api/camera/last-image', _deviceHandlers.handleCameraGetLastImage);
    router.post('/api/camera/cooling', _deviceHandlers.handleCameraSetCooling);
    router.post(
        '/api/camera/readoutMode', _deviceHandlers.handleCameraSetReadoutMode);
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
    router.post('/api/mount/slew-alt-az', _deviceHandlers.handleMountSlewAltAz);
    router.post('/api/mount/find-home', _deviceHandlers.handleMountFindHome);

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

    // Generic guider control
    router.post(
        '/api/guider/start-guiding', _guidingHandlers.handleGuiderStartGuiding);
    router.post(
        '/api/guider/stop-guiding', _guidingHandlers.handleGuiderStopGuiding);
    router.post('/api/guider/dither', _guidingHandlers.handleGuiderDither);
    router.post('/api/guider/loop', _guidingHandlers.handleGuiderLoop);
    router.post('/api/guider/find-star', _guidingHandlers.handleGuiderFindStar);
    router.post('/api/guider/set-lock-position',
        _guidingHandlers.handleGuiderSetLockPosition);
    router.get('/api/guider/lock-position',
        _guidingHandlers.handleGuiderGetLockPosition);
    router.post(
        '/api/guider/deselect-star', _guidingHandlers.handleGuiderDeselectStar);
    router.get(
        '/api/guider/star-image', _guidingHandlers.handleGuiderGetStarImage);
    router.get('/api/builtin-guider/config',
        _guidingHandlers.handleBuiltinGuiderGetConfig);
    router.post('/api/builtin-guider/config',
        _guidingHandlers.handleBuiltinGuiderSetConfig);

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
    router.post('/api/sequencer/save-path',
        _sequencerHandlers.handleSequencerSetSavePath);
    router.post('/api/sequencer/update-dither-config',
        _sequencerHandlers.handleSequencerUpdateDitherConfig);
    router.post('/api/sequencer/update-location',
        _sequencerHandlers.handleSequencerUpdateLocation);
    router.post('/api/sequencer/update-filter-offsets',
        _sequencerHandlers.handleSequencerUpdateFilterOffsets);
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
    router.get('/api/imaging/star-crops', _imagingHandlers.handleGetStarCrops);
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
    router.get('/api/images', _sessionHandlers.handleGetAllImages);
    router.get(
        '/api/images/standalone', _sessionHandlers.handleGetStandaloneImages);
    router.get('/api/images/<imageId>/thumbnail',
        _sessionHandlers.handleGetImageThumbnail);
    router.get(
        '/api/images/<imageId>/download', _sessionHandlers.handleDownloadImage);
    router.get('/api/sessions/<sessionId>/export/json',
        _sessionHandlers.handleExportSessionJson);
    router.get('/api/sessions/<sessionId>/export/csv',
        _sessionHandlers.handleExportSessionCsv);
    router.get('/api/sessions/<sessionId>/export/html',
        _sessionHandlers.handleExportSessionHtml);
    router.get('/api/sessions/<sessionId>/export/<format>',
        _sessionHandlers.handleExportSession);

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
    router.get('/api/sessions/<id>/psf-tiles',
        _analyticsHandlers.handleGetSessionPsfTiles);
    router.get('/api/sessions/<id>/residuals',
        _analyticsHandlers.handleGetSessionResiduals);
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
    // Remote Filesystem
    // ===========================================================================
    router.get(
        '/api/files/browse', _fileSystemHandlers.handleBrowseDirectories);
    router.post(
        '/api/files/validate', _fileSystemHandlers.handleValidateDirectory);

    // Science parity
    router.get('/api/science/session/<sessionId>/bundle',
        _scienceHandlers.handleGetSessionBundle);
    router.get('/api/science/sessionless/recent',
        _scienceHandlers.handleGetSessionlessBundle);
    router.get(
        '/api/science/settings', _scienceHandlers.handleGetScienceSettings);
    router.post(
        '/api/science/settings', _scienceHandlers.handleUpdateScienceSettings);
    router.get('/api/science/session/<sessionId>/config',
        _scienceHandlers.handleGetSessionConfig);
    router.post('/api/science/session/<sessionId>/config',
        _scienceHandlers.handleUpdateSessionConfig);
    router.get('/api/science/transforms',
        _scienceHandlers.handleGetPhotometricTransforms);
    router.post('/api/science/calibration/image/<imageId>/match-stars',
        _scienceHandlers.handleMatchPhotometricCalibrationStars);
    router.post('/api/science/calibration/compute-transform',
        _scienceHandlers.handleComputePhotometricTransform);
    router.post('/api/science/calibration/save-transform',
        _scienceHandlers.handleSavePhotometricTransform);
    router.post('/api/science/session/<sessionId>/generate-line-ratios',
        _scienceHandlers.handleGenerateLineRatios);
    router.post('/api/science/session/<sessionId>/export/aavso',
        _scienceHandlers.handleExportAavso);
    router.get('/api/science/session/<sessionId>/report/pdf',
        _scienceHandlers.handleGenerateObservationReport);

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
    router.post('/api/backup/upload-restore',
        _backupHandlers.handleUploadRestoreBackup);
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

    // Web Dashboard - static file serving
    router.get('/dashboard', _handleDashboardIndex);
    router.get('/dashboard/', _handleDashboardIndex);
    router.get('/dashboard/<path|.*>', _handleDashboardFile);

    final handler = Pipeline()
        .addMiddleware(_requestTrackingMiddleware())
        // Why placement: error translation must wrap downstream so
        // BadRequestError thrown anywhere lower becomes a structured 400.
        // It must be _outside_ auth/CORS so 4xx auth responses keep their
        // intended status (errorTranslationMiddleware only intercepts
        // exceptions, not non-2xx responses).
        .addMiddleware(errorTranslationMiddleware(
          logError: _logError,
          requestIdFor: _requestIdFrom,
        ))
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_requestSizeLimitMiddleware())
        .addMiddleware(_apiVersionMiddleware())
        .addMiddleware(_authMiddleware())
        .addMiddleware(_rateLimitMiddleware())
        .addMiddleware(_highRiskAuditMiddleware())
        .addHandler(router.call);

    final bindAddress =
        bindLocalOnly ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4;
    _server = await shelf_io.serve(handler, bindAddress, port);
    _logInfo(
        'Headless API server running on http://${_server!.address.host}:${_server!.port}');
    if (_effectiveAuthTokensByValue.isNotEmpty) {
      _logInfo(
          '[AUTH] Authentication is ENABLED. All requests require Bearer token.');
    } else {
      _logInfo('[AUTH] Authentication is DISABLED. All requests are allowed.');
      if (!bindLocalOnly) {
        _logWarning(
            '[AUTH] Unauthenticated LAN access is enabled. This is unsafe for normal rig control.');
      }
    }

    // Subscribe to backend events and broadcast to WebSocket clients
    _subscribeToBackendEvents();
    _collaborationSubscription =
        _collaborationManager.stream.listen(_broadcastCollaborationState);
  }

  void _subscribeToBackendEvents() {
    try {
      final backend = container.read(backendProvider);
      _eventSubscription = backend.eventStream.listen((event) {
        broadcastEvent(event);
      });
    } catch (e) {
      _logError('[API] Failed to subscribe to backend events: $e');
    }
  }

  Future<void> stop() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    _webSocketHeartbeatTimer?.cancel();
    _webSocketHeartbeatTimer = null;
    await _server?.close(force: true);
    _server = null;
    for (final socket in List.of(_sockets)) {
      await socket.sink.close();
    }
    _socketViewerIds.clear();
    _socketLastSeenAt.clear();
    _sockets.clear();
    _collaborationManager.dispose();
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

    for (final socket in List.of(_sockets)) {
      try {
        socket.sink.add(jsonEvent);
      } catch (e) {
        _logWarning('Error broadcasting to socket: $e');
      }
    }
  }

  void _broadcastCollaborationState(LiveCollaborationState state) {
    if (_sockets.isEmpty) return;
    final payload = jsonEncode({
      'type': 'collaboration_state',
      'state': state.toJson(),
    });
    for (final socket in List.of(_sockets)) {
      try {
        socket.sink.add(payload);
      } catch (e) {
        _logWarning('Error broadcasting collaboration state: $e');
      }
    }
  }

  // ===========================================================================
  // Core Handlers (kept inline for simplicity)
  // ===========================================================================

  Future<Response> _handleInfo(Request request) async {
    final platformCapabilities =
        PlatformCapabilityMatrix.forPlatform(Platform.operatingSystem);

    return jsonOk(
      {
        'name': 'Nightshade Headless',
        'version': '2.5.0',
        'apiVersion': RemoteApiCompatibility.serverApiVersion.format(),
        'minimumSupportedApiVersion':
            RemoteApiCompatibility.minimumSupportedVersion.format(),
        'apiVersionHeader': RemoteApiCompatibility.apiVersionHeader,
        'mode': 'headless',
        'platform': platformCapabilities.platform,
        'platformCapabilities': platformCapabilities.toJson(),
        'authRequired': _effectiveAuthTokensByValue.isNotEmpty,
        'authenticationMode':
            _effectiveAuthTokensByValue.isNotEmpty ? 'token' : 'none',
        'authScopes': _availableAuthScopes(),
        'pairingSupported': false,
        'apiOnlyMode': true,
        'webUIAvailable': false,
        'publicEndpoints': ['/api/info', '/dashboard'],
        'endpoints': _getAvailableEndpoints(),
      },
      headers: _apiCompatibilityHeaders(),
    );
  }

  List<String> _availableAuthScopes() {
    final scopes = _effectiveAuthTokensByValue.values
        .map(headlessTokenScopeName)
        .toSet()
        .toList();
    scopes.sort();
    return scopes;
  }

  List<String> _getAvailableEndpoints() {
    return [
      // Core
      'GET /api/info',
      'GET /api/status',
      'GET /api/self-test',
      'GET /api/openapi.json',
      'GET /api/collaboration/state',
      'POST /api/collaboration/viewers/join',
      'POST /api/collaboration/viewers/leave',
      'POST /api/collaboration/preview',
      'POST /api/collaboration/chat',
      'POST /api/collaboration/annotations',
      'GET /api/session-handoff',
      'POST /api/session-handoff',
      'DELETE /api/session-handoff',
      'GET /api/devices',
      'GET /api/devices/discover-indi',
      'GET /api/devices/discover-alpaca',
      'GET /api/devices/connected',
      'POST /api/devices/connect',
      'POST /api/devices/disconnect',
      // Camera
      'POST /api/camera/expose',
      'POST /api/camera/abort',
      'GET /api/camera/last-image',
      'POST /api/camera/cooling',
      'POST /api/camera/readoutMode',
      'POST /api/camera/gain',
      'POST /api/camera/offset',
      // Mount
      'POST /api/mount/slew',
      'POST /api/mount/sync',
      'POST /api/mount/park',
      'POST /api/mount/unpark',
      'POST /api/mount/tracking',
      'POST /api/mount/pulse-guide',
      'POST /api/mount/abort',
      'GET /api/mount/status',
      'POST /api/mount/set-tracking-rate',
      'POST /api/mount/move-axis',
      'POST /api/mount/slew-alt-az',
      'POST /api/mount/find-home',
      // Focuser
      'POST /api/focuser/move-to',
      'POST /api/focuser/move-relative',
      'POST /api/focuser/halt',
      'POST /api/focuser/autofocus/start',
      'POST /api/focuser/autofocus/cancel',
      // Filter Wheel
      'POST /api/filter-wheel/position',
      'GET /api/filter-wheel/names',
      'POST /api/filter-wheel/set-by-name',
      // Rotator
      'POST /api/rotator/move-to',
      'POST /api/rotator/move-relative',
      'GET /api/rotator/status',
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
      // Generic Guider
      'POST /api/guider/start-guiding',
      'POST /api/guider/stop-guiding',
      'POST /api/guider/dither',
      'POST /api/guider/loop',
      'POST /api/guider/find-star',
      'POST /api/guider/set-lock-position',
      'GET /api/guider/lock-position',
      'POST /api/guider/deselect-star',
      'GET /api/guider/star-image',
      'GET /api/builtin-guider/config',
      'POST /api/builtin-guider/config',
      // Plate Solving
      'POST /api/plate-solve',
      // Legacy Sequencer
      'GET /api/sequences/status',
      'POST /api/sequences/start',
      'POST /api/sequences/stop',
      // Sequencer
      'GET /api/sequencer/status',
      'POST /api/sequencer/start',
      'POST /api/sequencer/stop',
      'POST /api/sequencer/pause',
      'POST /api/sequencer/resume',
      'POST /api/sequencer/skip',
      'POST /api/sequencer/reset',
      'POST /api/sequencer/load',
      'POST /api/sequencer/simulation',
      'POST /api/sequencer/devices',
      'POST /api/sequencer/safety-fail-mode',
      'POST /api/sequencer/save-path',
      'POST /api/sequencer/update-dither-config',
      'POST /api/sequencer/update-location',
      'POST /api/sequencer/update-filter-offsets',
      'POST /api/sequencer/checkpoint/dir',
      'GET /api/sequencer/checkpoint/has',
      'GET /api/sequencer/checkpoint/info',
      'POST /api/sequencer/checkpoint/resume',
      'POST /api/sequencer/checkpoint/discard',
      'POST /api/sequencer/checkpoint/save',
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
      // Device Health
      'POST /api/device/heartbeat/start',
      'POST /api/device/heartbeat/stop',
      'GET /api/device/health/<deviceId>',
      // Profiles
      'GET /api/profiles',
      'POST /api/profiles',
      'DELETE /api/profiles/<profileId>',
      'POST /api/profiles/<profileId>/load',
      'GET /api/profiles/active',
      // Settings
      'GET /api/settings',
      'POST /api/settings',
      'GET /api/settings/location',
      'POST /api/settings/location',
      'GET /api/location',
      // Imaging
      'POST /api/imaging/stats',
      'POST /api/imaging/stretch',
      'GET /api/imaging/star-crops',
      'POST /api/imaging/debayer',
      'GET /api/imaging/raw-data',
      'POST /api/imaging/save-fits',
      'POST /api/imaging/save-fits-from-capture',
      'DELETE /api/imaging/device-image/<deviceId>',
      // Polar Alignment
      'POST /api/polar-alignment/start',
      'POST /api/polar-alignment/stop',
      // Session Images
      'GET /api/sessions/<sessionId>/images',
      'GET /api/images',
      'GET /api/images/standalone',
      'GET /api/images/<imageId>/thumbnail',
      'GET /api/images/<imageId>/download',
      'GET /api/sessions/<sessionId>/export/json',
      'GET /api/sessions/<sessionId>/export/csv',
      'GET /api/sessions/<sessionId>/export/html',
      'GET /api/sessions/<sessionId>/export/<format>',
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
      'POST /api/sequence-management/nodes/<nodeId>/enabled',
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
      'GET /api/sessions/<id>/psf-tiles',
      'GET /api/sessions/<id>/residuals',
      'GET /api/sessions/target/<targetId>',
      'POST /api/sessions',
      'PUT /api/sessions/<id>',
      'POST /api/sessions/<id>/end',
      'DELETE /api/sessions/<id>',
      'GET /api/files/browse',
      'POST /api/files/validate',
      // Science
      'GET /api/science/session/<sessionId>/bundle',
      'GET /api/science/sessionless/recent',
      'GET /api/science/settings',
      'POST /api/science/settings',
      'GET /api/science/session/<sessionId>/config',
      'POST /api/science/session/<sessionId>/config',
      'GET /api/science/transforms',
      'POST /api/science/calibration/image/<imageId>/match-stars',
      'POST /api/science/calibration/compute-transform',
      'POST /api/science/calibration/save-transform',
      'POST /api/science/session/<sessionId>/generate-line-ratios',
      'POST /api/science/session/<sessionId>/export/aavso',
      'GET /api/science/session/<sessionId>/report/pdf',
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
      'POST /api/backup/upload-restore',
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
      return jsonOk({
        "sequencer": {
          "state": status.state,
          "currentNodeId": status.currentNodeId,
          "currentNodeName": status.currentNodeName,
          "progress": status.progress,
          "message": status.message
        },
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Status error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
    }
  }

  Future<Response> _handleSelfTest(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/self-test');
    try {
      final platformCapabilities =
          PlatformCapabilityMatrix.forPlatform(Platform.operatingSystem);
      final backend = container.read(backendProvider);
      final storageChecks = await _runStorageSelfTests();
      final databaseCheck = _runDatabaseSelfTest();
      final connectedDeviceProbe = await _probeConnectedDevices(backend);
      final endpointCount = _getAvailableEndpoints().length;

      final checks = [
        ...storageChecks.map((check) => check['status']),
        databaseCheck['status'],
        connectedDeviceProbe['status'],
      ];
      final hasFailures = checks.contains('error');

      return jsonOk({
        'status': hasFailures ? 'degraded' : 'ok',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'platform': {
          'operatingSystem': platformCapabilities.platform,
          'operatingSystemVersion': Platform.operatingSystemVersion,
          'executable': Platform.resolvedExecutable,
        },
        'server': {
          'port': port,
          'bindMode': bindLocalOnly ? 'loopback' : 'lan',
          'authMode': _effectiveAuthTokensByValue.isNotEmpty ? 'token' : 'none',
          'authRequired': _effectiveAuthTokensByValue.isNotEmpty,
          'authScopes': _availableAuthScopes(),
          'dashboardAvailable': _findDashboardDir() != null,
        },
        'backend': {
          'type': backend.runtimeType.toString(),
          'connectedDevices': connectedDeviceProbe,
        },
        'deviceDrivers': platformCapabilities.toJson(),
        'storagePaths': storageChecks,
        'database': databaseCheck,
        'api': {
          'endpointCount': endpointCount,
          'selfTestEndpoint': 'GET /api/self-test',
        },
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Self-test error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  Future<Response> _handleOpenApiSpec(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/openapi.json');
    try {
      return jsonOk(_buildOpenApiSpec());
    } catch (e, stackTrace) {
      _logError('[API][$requestId] OpenAPI generation error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  Map<String, dynamic> _buildOpenApiSpec() {
    return route_metadata.buildOpenApiSpec(
      routes: _getAvailableEndpoints(),
      port: port,
    );
  }

  Map<String, dynamic> _runDatabaseSelfTest() {
    try {
      container.read(databaseProvider);
      return {
        'name': 'driftDatabase',
        'status': 'ok',
        'message': 'Database provider is initialized.',
      };
    } catch (e) {
      return {
        'name': 'driftDatabase',
        'status': 'error',
        'message': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _probeConnectedDevices(
    NightshadeBackend backend,
  ) async {
    try {
      final devices = await backend.getConnectedDevices().timeout(
            const Duration(seconds: 2),
          );
      return {
        'status': 'ok',
        'count': devices.length,
        'devices': devices.map((device) => device.toJson()).toList(),
      };
    } catch (e) {
      return {
        'status': 'warning',
        'count': null,
        'devices': <Map<String, dynamic>>[],
        'message': 'Connected-device probe unavailable: $e',
      };
    }
  }

  Future<List<Map<String, dynamic>>> _runStorageSelfTests() async {
    final checks = <Map<String, dynamic>>[];

    Future<void> addDirectoryCheck(
      String name,
      Future<Directory> Function() resolver,
    ) async {
      try {
        final directory = await resolver();
        checks.add(await _checkWritableDirectory(name, directory));
      } catch (e) {
        checks.add({
          'name': name,
          'status': 'error',
          'path': null,
          'exists': false,
          'writable': false,
          'message': e.toString(),
        });
      }
    }

    await addDirectoryCheck(
      'applicationDocuments',
      getApplicationDocumentsDirectory,
    );
    await addDirectoryCheck(
      'applicationSupport',
      getApplicationSupportDirectory,
    );
    await addDirectoryCheck(
      'systemTemp',
      () async => Directory.systemTemp,
    );

    return checks;
  }

  Future<Map<String, dynamic>> _checkWritableDirectory(
    String name,
    Directory directory,
  ) async {
    final exists = await directory.exists();
    if (!exists) {
      return {
        'name': name,
        'status': 'error',
        'path': directory.path,
        'exists': false,
        'writable': false,
        'message': 'Directory does not exist.',
      };
    }

    final probeFile = File(
      p.join(
        directory.path,
        '.nightshade-self-test-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await probeFile.writeAsString('ok');
      await probeFile.delete();
      return {
        'name': name,
        'status': 'ok',
        'path': directory.path,
        'exists': true,
        'writable': true,
      };
    } catch (e) {
      try {
        if (await probeFile.exists()) {
          await probeFile.delete();
        }
      } catch (_) {
        // Best-effort cleanup only.
      }
      return {
        'name': name,
        'status': 'error',
        'path': directory.path,
        'exists': true,
        'writable': false,
        'message': e.toString(),
      };
    }
  }

  Future<Response> _handleCollaborationState(Request request) async {
    return jsonOk(_collaborationManager.state.toJson());
  }

  Future<Response> _handleCollaborationJoin(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final viewerId = payload['viewerId'] as String?;
      final name = payload['name'] as String?;
      if (viewerId == null ||
          viewerId.isEmpty ||
          name == null ||
          name.isEmpty) {
        return jsonBadRequest({'error': 'Missing viewerId or name'});
      }
      _collaborationManager.upsertViewer(viewerId, name);
      return jsonOk(_collaborationManager.state.toJson());
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> _handleCollaborationLeave(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final viewerId = payload['viewerId'] as String?;
      if (viewerId == null || viewerId.isEmpty) {
        return jsonBadRequest({'error': 'Missing viewerId'});
      }
      _collaborationManager.removeViewer(viewerId);
      return jsonOk(_collaborationManager.state.toJson());
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> _handleCollaborationPreview(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final preview = payload['preview'];
      if (preview != null && preview is! Map<String, dynamic>) {
        return jsonBadRequest({'error': 'preview must be an object'});
      }
      _collaborationManager.updatePreview(preview as Map<String, dynamic>?);
      return jsonOk(_collaborationManager.state.toJson());
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> _handleCollaborationChat(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final viewerId = payload['viewerId'] as String?;
      final viewerName = payload['viewerName'] as String?;
      final message = payload['message'] as String?;
      if (viewerId == null || viewerName == null || message == null) {
        return jsonBadRequest(
            {'error': 'viewerId, viewerName, and message are required'});
      }
      _collaborationManager.addChat(
        viewerId: viewerId,
        viewerName: viewerName,
        message: message,
      );
      return jsonOk(_collaborationManager.state.toJson());
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> _handleCollaborationAnnotation(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final annotationId = payload['annotationId'] as String?;
      final viewerId = payload['viewerId'] as String?;
      final kind = payload['kind'] as String?;
      final annotationPayload = payload['payload'];
      if (annotationId == null ||
          viewerId == null ||
          kind == null ||
          annotationPayload is! Map<String, dynamic>) {
        return jsonBadRequest({
          'error': 'annotationId, viewerId, kind, and payload are required'
        });
      }
      _collaborationManager.addAnnotation(
        annotationId: annotationId,
        viewerId: viewerId,
        kind: kind,
        payload: annotationPayload,
      );
      return jsonOk(_collaborationManager.state.toJson());
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> _handleGetSessionHandoff(Request request) async {
    return jsonOk(
        {'sessionHandoff': _collaborationManager.state.sessionHandoff});
  }

  Future<Response> _handleSetSessionHandoff(Request request) async {
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final handoff = payload['handoff'];
      if (handoff != null && handoff is! Map<String, dynamic>) {
        return jsonBadRequest({'error': 'handoff must be an object'});
      }
      _collaborationManager.setSessionHandoff(handoff as Map<String, dynamic>?);
      return jsonOk(
          {'sessionHandoff': _collaborationManager.state.sessionHandoff});
    } catch (e) {
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> _handleClearSessionHandoff(Request request) async {
    _collaborationManager.setSessionHandoff(null);
    return jsonOk({'sessionHandoff': null});
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

      return jsonOk({
        "devices": allDevices
            .map((d) => {
                  'id': d.id,
                  'name': d.name,
                  'deviceType': d.deviceType.name,
                  'driverType': d.driverType.name,
                  'description': d.description,
                })
            .toList(),
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Get devices error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
    }
  }

  Future<Response> _handleDiscoverIndiAtAddress(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/discover-indi');
    try {
      final host = request.url.queryParameters['host'];
      final port = int.tryParse(request.url.queryParameters['port'] ?? '');
      if (host == null || host.isEmpty || port == null) {
        return jsonBadRequest({'error': 'host and port are required'});
      }

      final backend = container.read(backendProvider);
      final devices = await backend.discoverIndiAtAddress(host, port);
      return jsonOk({'devices': devices.map((d) => d.toJson()).toList()});
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] INDI address discovery error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  Future<Response> _handleDiscoverAlpacaAtAddress(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/discover-alpaca');
    try {
      final host = request.url.queryParameters['host'];
      final port = int.tryParse(request.url.queryParameters['port'] ?? '');
      if (host == null || host.isEmpty || port == null) {
        return jsonBadRequest({'error': 'host and port are required'});
      }

      final backend = container.read(backendProvider);
      final devices = await backend.discoverAlpacaAtAddress(host, port);
      return jsonOk({'devices': devices.map((d) => d.toJson()).toList()});
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] Alpaca address discovery error: $e\n$stackTrace');
      return jsonInternalServerError({'error': 'Internal server error'});
    }
  }

  Future<Response> _handleGetConnectedDevices(Request request) async {
    final requestId = _requestIdFrom(request);
    _logInfo('[API][$requestId] GET /api/devices/connected');
    try {
      final backend = container.read(backendProvider);
      final devices = await backend.getConnectedDevices();
      return jsonOk({
        "devices": devices
            .map((d) => {
                  'id': d.id,
                  'name': d.name,
                  'deviceType': d.deviceType.name,
                  'driverType': d.driverType.name,
                  'description': d.description,
                })
            .toList(),
      });
    } catch (e, stackTrace) {
      _logError(
          '[API][$requestId] Get connected devices error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
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
        return jsonBadRequest({"error": "Invalid device type: $deviceTypeStr"});
      }

      final backend = container.read(backendProvider);
      await backend.connectDevice(deviceType, deviceId);

      return jsonOk({
        "status": "connected",
        "deviceId": deviceId,
        "deviceType": deviceType.name,
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Connect device error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
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
        return jsonBadRequest({"error": "Invalid device type: $deviceTypeStr"});
      }

      final backend = container.read(backendProvider);
      await backend.disconnectDevice(deviceType, deviceId);

      return jsonOk({
        "status": "disconnected",
        "deviceId": deviceId,
        "deviceType": deviceType.name,
      });
    } catch (e, stackTrace) {
      _logError('[API][$requestId] Disconnect device error: $e\n$stackTrace');
      return jsonInternalServerError({"error": "Internal server error"});
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
    _socketLastSeenAt[socket] = DateTime.now();
    _ensureWebSocketHeartbeatTimer();
    _logInfo('New WebSocket connection');
    socket.sink.add(jsonEncode({
      'type': 'collaboration_state',
      'state': _collaborationManager.state.toJson(),
    }));

    socket.stream.listen(
      (message) {
        // Handle incoming messages (e.g. pings)
        try {
          _socketLastSeenAt[socket] = DateTime.now();
          final data = jsonDecode(message) as Map<String, dynamic>;
          if (data['type'] == 'ping') {
            socket.sink.add(jsonEncode({
              'type': 'pong',
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            }));
          } else if (data['type'] == 'pong') {
            return;
          } else {
            _handleCollaborationSocketMessage(
              socket,
              data,
            );
          }
        } catch (_) {}
      },
      onDone: () {
        _removeWebSocket(socket);
        _logInfo('WebSocket disconnected');
      },
      onError: (error) {
        _removeWebSocket(socket);
        _logWarning('WebSocket error: $error');
      },
    );
  }

  void _removeWebSocket(WebSocketChannel socket) {
    final viewerId = _socketViewerIds.remove(socket);
    if (viewerId != null) {
      _collaborationManager.removeViewer(viewerId);
    }
    _socketLastSeenAt.remove(socket);
    _sockets.remove(socket);
    if (_sockets.isEmpty) {
      _webSocketHeartbeatTimer?.cancel();
      _webSocketHeartbeatTimer = null;
    }
  }

  void _ensureWebSocketHeartbeatTimer() {
    if (webSocketHeartbeatInterval <= Duration.zero ||
        _webSocketHeartbeatTimer != null) {
      return;
    }

    _webSocketHeartbeatTimer = Timer.periodic(webSocketHeartbeatInterval, (_) {
      final now = DateTime.now();
      for (final socket in List.of(_sockets)) {
        final lastSeenAt = _socketLastSeenAt[socket];
        if (lastSeenAt != null &&
            now.difference(lastSeenAt) > webSocketHeartbeatTimeout) {
          _logWarning('Closing stale WebSocket after heartbeat timeout');
          _removeWebSocket(socket);
          unawaited(socket.sink.close());
          continue;
        }

        try {
          socket.sink.add(jsonEncode({
            'type': 'ping',
            'timestamp': now.toUtc().toIso8601String(),
          }));
        } catch (e) {
          _logWarning('WebSocket heartbeat failed: $e');
          _removeWebSocket(socket);
        }
      }
    });
  }

  void _handleCollaborationSocketMessage(
    WebSocketChannel socket,
    Map<String, dynamic> data,
  ) {
    final type = data['type'] as String?;
    switch (type) {
      case 'collaboration.join':
        final viewerId = data['viewerId'] as String?;
        final name = data['name'] as String?;
        if (viewerId == null || name == null) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message': 'collaboration.join requires viewerId and name',
          }));
          return;
        }
        _socketViewerIds[socket] = viewerId;
        _collaborationManager.upsertViewer(viewerId, name);
        return;
      case 'collaboration.leave':
        final viewerId =
            data['viewerId'] as String? ?? _socketViewerIds.remove(socket);
        if (viewerId != null) {
          _collaborationManager.removeViewer(viewerId);
        }
        return;
      case 'collaboration.preview':
        final preview = data['preview'];
        if (preview != null && preview is! Map<String, dynamic>) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message': 'collaboration.preview requires preview to be an object',
          }));
          return;
        }
        _collaborationManager.updatePreview(preview as Map<String, dynamic>?);
        return;
      case 'collaboration.chat':
        final viewerId = data['viewerId'] as String?;
        final viewerName = data['viewerName'] as String?;
        final message = data['message'] as String?;
        if (viewerId == null || viewerName == null || message == null) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message':
                'collaboration.chat requires viewerId, viewerName, and message',
          }));
          return;
        }
        _collaborationManager.addChat(
          viewerId: viewerId,
          viewerName: viewerName,
          message: message,
        );
        return;
      case 'collaboration.annotation':
        final annotationId = data['annotationId'] as String?;
        final viewerId = data['viewerId'] as String?;
        final kind = data['kind'] as String?;
        final payload = data['payload'];
        if (annotationId == null ||
            viewerId == null ||
            kind == null ||
            payload is! Map<String, dynamic>) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message':
                'collaboration.annotation requires annotationId, viewerId, kind, and payload',
          }));
          return;
        }
        _collaborationManager.addAnnotation(
          annotationId: annotationId,
          viewerId: viewerId,
          kind: kind,
          payload: payload,
        );
        return;
      case 'session_handoff.set':
        final handoff = data['handoff'];
        if (handoff != null && handoff is! Map<String, dynamic>) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message': 'session_handoff.set requires handoff to be an object',
          }));
          return;
        }
        _collaborationManager
            .setSessionHandoff(handoff as Map<String, dynamic>?);
        return;
      case 'session_handoff.clear':
        _collaborationManager.setSessionHandoff(null);
        return;
    }
  }

  // ===========================================================================
  // Web Dashboard Static File Serving
  // ===========================================================================

  /// Resolves the web_dashboard directory location.
  /// Checks multiple paths: next to the executable (release), and in the source
  /// tree (development).
  Directory? _findDashboardDir() {
    // 1. Next to the executable (release builds)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final releasePath =
        p.join(exeDir, 'data', 'flutter_assets', 'web_dashboard');
    final releaseDir = Directory(releasePath);
    if (releaseDir.existsSync()) return releaseDir;

    // 2. In the same directory as the executable
    final sameDirPath = p.join(exeDir, 'web_dashboard');
    final sameDir = Directory(sameDirPath);
    if (sameDir.existsSync()) return sameDir;

    // 3. Source tree location (development - walk up from exe to find apps/desktop)
    // The exe in debug mode is in build/windows/x64/runner/Debug/ or similar
    var current = exeDir;
    for (var i = 0; i < 10; i++) {
      final candidate = p.join(current, 'web_dashboard');
      if (Directory(candidate).existsSync()) return Directory(candidate);
      final parent = p.dirname(current);
      if (parent == current) break;
      current = parent;
    }

    // 4. Try relative to current working directory
    final cwdPath = p.join(Directory.current.path, 'web_dashboard');
    final cwdDir = Directory(cwdPath);
    if (cwdDir.existsSync()) return cwdDir;

    return null;
  }

  static const _mimeTypes = <String, String>{
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.json': 'application/json; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
  };

  String _getMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return _mimeTypes[ext] ?? 'application/octet-stream';
  }

  Future<Response> _handleDashboardIndex(Request request) async {
    return _serveDashboardFile('index.html');
  }

  Future<Response> _handleDashboardFile(Request request, String path) async {
    // Sanitize path: prevent directory traversal
    final normalized = p.normalize(path).replaceAll('\\', '/');
    if (normalized.contains('..') || normalized.startsWith('/')) {
      return jsonForbidden({'error': 'Invalid path'});
    }
    return _serveDashboardFile(normalized);
  }

  Future<Response> _serveDashboardFile(String relativePath) async {
    final dashboardDir = _findDashboardDir();
    if (dashboardDir == null) {
      _logWarning('[Dashboard] web_dashboard directory not found');
      return jsonNotFound(
        {
          'error': 'Dashboard not found',
          'message': 'The web_dashboard directory could not be located. '
              'Ensure it is deployed alongside the application.',
        },
      );
    }

    final filePath = p.join(dashboardDir.path, relativePath);
    final file = File(filePath);

    if (!await file.exists()) {
      return jsonNotFound({'error': 'File not found: $relativePath'});
    }

    // Ensure the resolved path is still inside the dashboard directory
    final resolvedPath = await file.resolveSymbolicLinks();
    final resolvedDashDir = await dashboardDir.resolveSymbolicLinks();
    final dashDirWithSep = resolvedDashDir.endsWith(Platform.pathSeparator)
        ? resolvedDashDir
        : resolvedDashDir + Platform.pathSeparator;
    if (!resolvedPath.startsWith(dashDirWithSep) &&
        resolvedPath != resolvedDashDir) {
      return jsonForbidden({'error': 'Access denied'});
    }

    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        'content-type': _getMimeType(filePath),
        'cache-control': 'no-cache',
        ..._dashboardSecurityHeaders,
      },
    );
  }

  static const _dashboardSecurityHeaders = {
    'content-security-policy': "default-src 'self'; script-src 'self'; "
        "style-src 'self'; img-src 'self' data: blob:; connect-src 'self' "
        "http://*:* https://*:* ws://*:* wss://*:*; object-src 'none'; "
        "base-uri 'none'; frame-ancestors 'none'",
    'x-frame-options': 'DENY',
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  };

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

        _logInfo(
          '[REQ][$requestId] ${request.method} $path started',
          fields: {
            'requestId': requestId,
            'method': request.method,
            'path': path,
            'phase': 'started',
          },
        );
        try {
          final response = await innerHandler(scopedRequest);
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          _logInfo(
            '[REQ][$requestId] ${request.method} $path completed status=${response.statusCode} ms=$elapsedMs',
            fields: {
              'requestId': requestId,
              'method': request.method,
              'path': path,
              'phase': 'completed',
              'statusCode': response.statusCode,
              'elapsedMs': elapsedMs,
            },
          );
          return response.change(headers: {
            ...response.headers,
            _requestIdHeader: requestId,
          });
        } catch (e, stackTrace) {
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          _logError(
            '[REQ][$requestId] ${request.method} $path failed ms=$elapsedMs error=$e\n$stackTrace',
            fields: {
              'requestId': requestId,
              'method': request.method,
              'path': path,
              'phase': 'failed',
              'elapsedMs': elapsedMs,
              'error': e.toString(),
            },
          );
          rethrow;
        }
      };
    };
  }

  Middleware _corsMiddleware() {
    return (innerHandler) {
      return (request) async {
        final corsHeaders = _buildCorsHeaders(request);
        if (request.method == 'OPTIONS') {
          if (request.headers.containsKey('origin') && corsHeaders.isEmpty) {
            return jsonForbidden(
              {
                'error': 'origin_not_allowed',
                'message': 'Cross-origin requests are not allowed.',
              },
              headers: {'vary': 'Origin'},
            );
          }
          return Response.ok('', headers: corsHeaders);
        }

        final response = await innerHandler(request);
        if (corsHeaders.isEmpty) {
          return response;
        }
        return response.change(headers: {
          ...response.headers,
          ...corsHeaders,
        });
      };
    };
  }

  Middleware _requestSizeLimitMiddleware() {
    return (innerHandler) {
      return (request) async {
        final path = '/${request.url.path}';
        final validation = route_metadata.validateContentLength(
          method: request.method,
          path: path,
          contentLengthHeader: request.headers[HttpHeaders.contentLengthHeader],
        );
        if (validation != null) {
          return jsonResponse(
            validation['body'],
            statusCode: validation['statusCode'] as int,
          );
        }

        if (!route_metadata.methodCanHaveBody(request.method)) {
          return innerHandler(request);
        }

        final declaredContentLength =
            request.headers[HttpHeaders.contentLengthHeader];
        if (declaredContentLength != null && declaredContentLength.isNotEmpty) {
          return innerHandler(request);
        }

        final limit = route_metadata.requestBodyLimitForPath(path);
        final body = await _readRequestBodyWithinLimit(request, limit);
        if (!body.accepted) {
          final requestId = _requestIdFrom(request);
          _logWarning(
            '[REQ][$requestId] ${request.method} $path body too large '
            'received=${body.receivedBytes} max=$limit',
            fields: {
              'requestId': requestId,
              'method': request.method,
              'path': path,
              'receivedBytes': body.receivedBytes,
              'maxBytes': limit,
            },
          );
          return jsonTooLarge({
            'error': 'Request body too large',
            'maxBytes': limit,
            'receivedBytes': body.receivedBytes,
            'requestId': requestId,
          });
        }

        return innerHandler(request.change(body: body.bytes));
      };
    };
  }

  Future<_RequestBodyLimitResult> _readRequestBodyWithinLimit(
    Request request,
    int maxBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var receivedBytes = 0;
    var exceededLimit = false;
    await for (final chunk in request.read()) {
      receivedBytes += chunk.length;
      if (receivedBytes > maxBytes) {
        exceededLimit = true;
        continue;
      }
      if (!exceededLimit) {
        bytes.add(chunk);
      }
    }
    if (exceededLimit) {
      return _RequestBodyLimitResult.rejected(receivedBytes);
    }
    return _RequestBodyLimitResult.accepted(
      bytes.takeBytes(),
      receivedBytes,
    );
  }

  Middleware _apiVersionMiddleware() {
    return (innerHandler) {
      return (request) async {
        final path = '/${request.url.path}';
        final isWebSocket = path == '/api/ws' || path == '/events';
        final clientVersion = request
                .headers[RemoteApiCompatibility.apiVersionHeader] ??
            (isWebSocket ? request.url.queryParameters['apiVersion'] : null);
        if ((path.startsWith('/api/') || isWebSocket) &&
            clientVersion != null &&
            clientVersion.trim().isNotEmpty) {
          final compatibility =
              RemoteApiCompatibility.checkClient(clientVersion);
          if (!compatibility.isCompatible) {
            final requestId = _requestIdFrom(request);
            _logWarning(
              '[API][$requestId] Rejected incompatible client API version '
              '$clientVersion for $path: ${compatibility.code}',
            );
            return jsonUpgradeRequired(
              {
                'error': compatibility.code,
                'message': compatibility.message,
                'clientApiVersion':
                    compatibility.clientVersion ?? clientVersion,
                'serverApiVersion':
                    RemoteApiCompatibility.serverApiVersion.format(),
                'minimumSupportedApiVersion':
                    RemoteApiCompatibility.minimumSupportedVersion.format(),
                'requestId': requestId,
              },
              headers: {
                _requestIdHeader: requestId,
                ..._apiCompatibilityHeaders(),
              },
            );
          }
        }

        final response = await innerHandler(request);
        return response.change(headers: {
          ...response.headers,
          ..._apiCompatibilityHeaders(),
        });
      };
    };
  }

  Map<String, String> _apiCompatibilityHeaders() {
    return {
      RemoteApiCompatibility.apiVersionHeader:
          RemoteApiCompatibility.serverApiVersion.format(),
      'x-nightshade-minimum-api-version':
          RemoteApiCompatibility.minimumSupportedVersion.format(),
    };
  }

  Middleware _rateLimitMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        final path = '/${request.url.path}';
        final decision = _rateLimiter.check(
          clientKey: _rateLimitClientKey(request),
          method: request.method,
          path: path,
        );
        if (decision.allowed) {
          return null;
        }

        final requestId = _requestIdFrom(request);
        _logWarning(
          '[RATE][$requestId] ${request.method} $path limited '
          'max=${decision.maxRequests} retry=${decision.retryAfterSeconds}s',
          fields: {
            'requestId': requestId,
            'method': request.method,
            'path': path,
            'maxRequests': decision.maxRequests,
            'retryAfterSeconds': decision.retryAfterSeconds,
          },
        );
        return jsonRateLimited(
          {
            'error': 'Rate limit exceeded',
            'maxRequests': decision.maxRequests,
            'retryAfterSeconds': decision.retryAfterSeconds,
            'requestId': requestId,
          },
          headers: {
            'retry-after': decision.retryAfterSeconds.toString(),
          },
        );
      },
    );
  }

  Middleware _highRiskAuditMiddleware() {
    return (innerHandler) {
      return (request) async {
        final path = '/${request.url.path}';
        final auditAction = route_metadata.highRiskAuditActionFor(
          method: request.method,
          path: path,
        );
        if (auditAction == null) {
          return innerHandler(request);
        }

        final requestId = _requestIdFrom(request);
        final clientKey = _rateLimitClientKey(request);
        _logger.info(
          '[AUDIT][$requestId] $auditAction requested '
          'method=${request.method} path=$path client=$clientKey',
          source: 'HeadlessApiAudit',
          fields: {
            'requestId': requestId,
            'auditAction': auditAction,
            'method': request.method,
            'path': path,
            'client': clientKey,
            'phase': 'requested',
          },
        );

        final response = await innerHandler(request);
        _logger.info(
          '[AUDIT][$requestId] $auditAction completed '
          'status=${response.statusCode}',
          source: 'HeadlessApiAudit',
          fields: {
            'requestId': requestId,
            'auditAction': auditAction,
            'method': request.method,
            'path': path,
            'client': clientKey,
            'phase': 'completed',
            'statusCode': response.statusCode,
          },
        );
        return response;
      };
    };
  }

  String _rateLimitClientKey(Request request) {
    final forwardedFor = request.headers['x-forwarded-for'];
    if (forwardedFor != null && forwardedFor.trim().isNotEmpty) {
      return forwardedFor.split(',').first.trim();
    }

    final forwardedHost = request.headers['x-real-ip'];
    if (forwardedHost != null && forwardedHost.trim().isNotEmpty) {
      return forwardedHost.trim();
    }

    return request.requestedUri.host;
  }

  Map<String, String> _buildCorsHeaders(Request request) {
    final origin = request.headers['origin'];
    final allowedOrigin = _resolveAllowedOrigin(request, origin);
    if (allowedOrigin == null) {
      return const {};
    }
    return {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers':
          'Origin, Content-Type, X-Auth-Token, Authorization, '
              'X-Nightshade-API-Version, X-Request-ID',
      'Vary': 'Origin',
    };
  }

  String? _resolveAllowedOrigin(Request request, String? origin) {
    if (origin == null || origin.isEmpty) {
      return null;
    }

    final originUri = Uri.tryParse(origin);
    if (originUri == null) {
      return null;
    }

    final requestedUri = request.requestedUri;
    if (originUri.scheme != requestedUri.scheme ||
        originUri.host.toLowerCase() != requestedUri.host.toLowerCase() ||
        originUri.port != requestedUri.port) {
      return null;
    }

    return origin;
  }

  /// Middleware that validates Bearer token authentication.
  ///
  /// Public endpoints are exempt from authentication:
  /// - GET /api/info
  ///
  /// WebSocket endpoints (/api/ws, /events) require authentication when enabled.
  /// They accept the token via Authorization header or `token` query parameter
  /// (since browsers cannot set custom headers on WebSocket upgrades).
  Middleware _authMiddleware() {
    // Endpoints that don't require authentication
    const publicPaths = {'/api/info'};

    // WebSocket paths that support query-param auth
    const webSocketPaths = {'/api/ws', '/events'};

    return createMiddleware(
      requestHandler: (request) {
        // Skip auth if no token is configured
        if (_effectiveAuthTokensByValue.isEmpty) {
          return null;
        }

        // Skip auth for public endpoints and dashboard static files
        final requestId = _requestIdFrom(request);
        final path = '/${request.url.path}';
        if (publicPaths.contains(path) || path.startsWith('/dashboard')) {
          return null;
        }

        // For WebSocket paths, also accept token as query parameter
        if (webSocketPaths.contains(path)) {
          final queryToken = request.url.queryParameters['token'];
          final queryScope = _scopeForToken(queryToken);
          if (queryScope != null &&
              HeadlessAuthPolicy.allows(
                actual: queryScope,
                method: 'WS',
                path: path,
              )) {
            return null; // Valid token via query param
          }
          // Fall through to check Authorization header below
        }

        // Check for Authorization header
        final authHeader = request.headers['authorization'];
        if (authHeader == null) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - no Authorization header');
          return jsonUnauthorized(
            {
              'error': 'Authentication required',
              'message': 'Missing Authorization header',
            },
            headers: {
              _requestIdHeader: requestId,
            },
          );
        }

        // Validate Bearer token format
        if (!authHeader.startsWith('Bearer ')) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - invalid auth format');
          return jsonUnauthorized(
            {
              'error': 'Authentication required',
              'message':
                  'Invalid Authorization header format. Expected: Bearer <token>',
            },
            headers: {
              _requestIdHeader: requestId,
            },
          );
        }

        // Extract and validate token
        final token = authHeader.substring(7); // Remove 'Bearer ' prefix
        final tokenScope = _scopeForToken(token);
        if (tokenScope == null) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - invalid token');
          return jsonForbidden(
            {
              'error': 'Access denied',
              'message': 'Invalid authentication token',
            },
            headers: {
              _requestIdHeader: requestId,
            },
          );
        }

        if (!HeadlessAuthPolicy.allows(
          actual: tokenScope,
          method: request.method,
          path: path,
        )) {
          final requiredScope = HeadlessAuthPolicy.requiredScopeFor(
            method: request.method,
            path: path,
          );
          _logWarning(
            '[AUTH][$requestId] Rejected request to $path - '
            'scope=${headlessTokenScopeName(tokenScope)} '
            'required=${headlessTokenScopeName(requiredScope)}',
          );
          return jsonForbidden(
            {
              'error': 'Access denied',
              'message': 'Token scope is not permitted for this endpoint',
              'requiredScope': headlessTokenScopeName(requiredScope),
              'tokenScope': headlessTokenScopeName(tokenScope),
            },
            headers: {
              _requestIdHeader: requestId,
            },
          );
        }

        // Token is valid, continue to handler
        return null;
      },
    );
  }

  HeadlessTokenScope? _scopeForToken(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    return _effectiveAuthTokensByValue[token];
  }

  /// Generates a cryptographically secure random token.
  static String _generateRandomToken({int length = 32}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// Get the current authentication token (for logging/debugging).
  /// Returns null if authentication is disabled.
  String? get effectiveAuthToken => _effectiveAuthToken;

  /// The bound HTTP port. Useful when the server was started with port 0.
  int get actualPort => _server?.port ?? port;
}

class _RequestBodyLimitResult {
  final bool accepted;
  final Uint8List bytes;
  final int receivedBytes;

  const _RequestBodyLimitResult._({
    required this.accepted,
    required this.bytes,
    required this.receivedBytes,
  });

  factory _RequestBodyLimitResult.accepted(
    Uint8List bytes,
    int receivedBytes,
  ) {
    return _RequestBodyLimitResult._(
      accepted: true,
      bytes: bytes,
      receivedBytes: receivedBytes,
    );
  }

  factory _RequestBodyLimitResult.rejected(int receivedBytes) {
    return _RequestBodyLimitResult._(
      accepted: false,
      bytes: Uint8List(0),
      receivedBytes: receivedBytes,
    );
  }
}
