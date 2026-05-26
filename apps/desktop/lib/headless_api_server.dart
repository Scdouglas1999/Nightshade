// Auth tokens must be printed to stdout transiently (NOT logged to file —
// see the security rationale around _logWarning below). These two prints
// are the only legitimate stdout writes in this file.
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';
import 'package:nightshade_updater/nightshade_updater.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'headless_api/auth/auth_cookie.dart';
import 'headless_api/auth/cors_policy.dart';
import 'headless_api/auth/pairing_attempt_tracker.dart';
import 'headless_api/auth/pairing_service.dart';
import 'headless_api/auth/timing.dart';
import 'headless_api/auth/token_resolver.dart';
import 'headless_api/auth/ws_ticket_manager.dart';
import 'headless_api/auth_policy.dart';
import 'headless_api/command_correlator.dart';
import 'headless_api/event_replay_buffer.dart';
import 'headless_api/handlers.dart';
import 'headless_api/job_manager.dart';
import 'headless_api/request_context.dart' as ctx;
import 'headless_api/response_helpers.dart';
import 'headless_api/route_metadata.dart' as route_metadata;
import 'headless_api/session_ownership.dart';
import 'headless_api/validation.dart';

/// Headless API server using Shelf router with modular handlers
class HeadlessApiServer {
  // Re-exported from `headless_api/request_context.dart` so handler classes
  // and route modules outside this file can share the same context keys
  // without depending on `HeadlessApiServer` directly.
  static const _requestIdContextKey = ctx.requestIdContextKey;
  static const _requestIdHeader = ctx.requestIdHeader;

  /// P2-6 / P2-15: Shelf request-context key holding the SHA-256 digest of
  /// the authenticated bearer token. Set by [_authMiddleware] once a token
  /// resolves to a valid scope; consumed by the rate limiter and the
  /// WebSocket upgrade path. We never propagate the raw token through the
  /// request context — only the digest — so a misbehaving handler that
  /// dumps `request.context` for diagnostics cannot accidentally leak the
  /// secret to a log file.
  static const _authIdentityContextKey = ctx.authIdentityContextKey;

  /// P2-6: shelf request-context key holding the bound [route_metadata.
  /// TokenRouteClass] for this request. Memoised in the auth middleware so
  /// the rate-limit middleware doesn't have to re-classify the path.
  static const _authRouteClassContextKey = ctx.authRouteClassContextKey;

  final int port;
  final ProviderContainer container;
  final bool bindLocalOnly;
  final bool dispatchPluginNodes;

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

  /// P0-3: when true, every successful `POST /api/pairing/start` prints the
  /// raw pairing code to stdout (alongside the existing structured-log
  /// breadcrumb). Intended for headless operators on Pi/embedded hosts who
  /// otherwise have no way to see the code. Defaults to false because the
  /// GUI desktop bootstrap surfaces the code in its own UI.
  final bool pairingPrintCodes;

  /// P0-9: optional TLS context. When supplied, the server is bound with
  /// `shelf_io.serve(..., securityContext: tlsContext)` so the entire
  /// transport (HTTP + WebSocket upgrade) speaks HTTPS/WSS. Plain HTTP
  /// remains the default when null. The SHA-256 fingerprint surfaced via
  /// `/api/info` is rebased on the cert's SubjectPublicKeyInfo when this is
  /// set — see [_serverFingerprint].
  final SecurityContext? tlsContext;

  /// P0-9: when TLS is active, the SHA-256 hex digest of the certificate's
  /// SubjectPublicKeyInfo DER. Used to overwrite the token-derived
  /// fingerprint with a cert-pinned identity anchor. Plain HTTP mode leaves
  /// this null and falls back to the token-derived fingerprint.
  final String? tlsPublicKeyFingerprint;

  /// P1-1: capacity of the in-memory ring buffer that backs WS replay on
  /// reconnect. Default 5000 events ≈ 5 MB at 1 KB/event. Tuned per-deploy
  /// for memory-constrained hosts (Pi 4 / Pi 5).
  final int eventReplayBufferSize;

  HttpServer? _server;
  final List<WebSocketChannel> _sockets = [];
  final Map<WebSocketChannel, String> _socketViewerIds = {};

  /// P2-15: SHA-256 digest of the bearer token that authenticated each
  /// connected socket. Populated at upgrade time from the request context
  /// that `_authMiddleware` stashed. Used as the canonical `viewerId` for
  /// `collaboration.join` messages — any client-supplied value is ignored.
  /// Null entries are tolerated for sockets that connect when auth is
  /// disabled (no token configured); those still get a viewerId, but it
  /// falls back to whatever the client provides.
  final Map<WebSocketChannel, String?> _socketAuthIdentities = {};
  final Map<WebSocketChannel, DateTime> _socketLastSeenAt = {};
  Timer? _webSocketHeartbeatTimer;
  int _requestCounter = 0;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _collaborationSubscription;
  StreamSubscription? _catalogUpdateSubscription;
  // Push-notification forwarder. Why optional: headless mode has no on-device
  // notifications to forward (the operator is remote); GUI mode wires the
  // PushNotificationService stream here so paired phones receive sequence
  // failures, weather aborts, etc. as separate WebSocket messages distinct
  // from regular event broadcasts.
  StreamSubscription? _pushNotificationSubscription;
  final LiveCollaborationSessionManager _collaborationManager =
      LiveCollaborationSessionManager();
  final route_metadata.EndpointRateLimiter _rateLimiter =
      route_metadata.EndpointRateLimiter();

  /// P2-6: per-token / route-class bucket. Independent of the legacy
  /// endpoint window so a single token can hit dozens of different
  /// endpoints without exhausting one shared counter, while still being
  /// throttled if it floods one route class. Keys are derived from the
  /// auth-identity digest computed by [_authMiddleware]; unauthenticated
  /// requests bypass this limiter (they never reach it — auth rejects
  /// them first) so we can rely on a non-null token id at this point.
  final route_metadata.TokenBucketRateLimiter _tokenBucketLimiter =
      route_metadata.TokenBucketRateLimiter();

  /// The effective auth token (either provided or generated)
  late final String? _effectiveAuthToken;
  late final Map<String, HeadlessTokenScope> _effectiveAuthTokensByValue;
  late final TokenResolver _tokenResolver;
  late final CorsAllowList _corsAllowList;
  late final WsTicketManager _wsTicketManager;
  late final AuthCookieManager _authCookieManager;
  late final PairingAttemptTracker _pairingAttempts;
  PairingService? _pairingService;
  // Tokens minted by completed pairing flows and their scopes. Why separate
  // from the configured token table: pairing tokens live in PairingDatabase
  // (Drift) and must not mutate the immutable configured-token map.
  //
  // P0-2: this map is now hydrated from `PairedDevices` at [start()] so
  // server restarts no longer evict already-paired clients.
  // P0-10: entries are evicted synchronously by [_evictPairedSessionToken]
  // when the TokenManager surfaces a revoke / expiry event.
  final Map<String, HeadlessTokenScope> _pairedSessionTokens = {};

  /// P0-10: periodic sweep that walks `PairedDevices` and drops expired
  /// rows + evicts revoked entries from [_pairedSessionTokens]. Interval is
  /// configurable mainly for tests; production runs at 60s.
  Timer? _tokenSweepTimer;
  Duration get tokenSweepInterval => const Duration(seconds: 60);

  /// SHA-256 host fingerprint surfaced in `/api/info` and desktop QR codes.
  late final String _serverFingerprint;

  /// P1-1: random UUID generated once at server construction time. Mirrored
  /// onto every outbound event and returned by /api/info. Clients use a
  /// mismatch to detect a server restart and abandon their seq cursor.
  late final String _serverInstanceId;

  /// P1-1: monotonically increasing event sequence number, starts at 1
  /// for the first broadcast event of this server instance. Wraps would
  /// require ~9.2 quintillion events which is well past practical for
  /// the buffer's lifetime.
  int _eventSeq = 0;

  /// P1-1: ring buffer of recently broadcast events for WS replay on
  /// reconnect.
  late final EventReplayBuffer _eventReplayBuffer;

  /// P1-4: correlates command IDs from action handlers with later events.
  late final CommandCorrelator _commandCorrelator;

  /// Periodic sweep that evicts expired pending commands from the
  /// correlator. Cheap to run; the table is usually tiny.
  Timer? _commandCorrelatorSweepTimer;

  /// P1-2/P1-3: long-running operation manager. Autofocus, plate-solve,
  /// center-on-target, polar alignment, and similar multi-minute ops
  /// register as Jobs and return `{jobId}` immediately rather than
  /// holding the HTTP connection open.
  late final JobManager _jobManager;

  /// Periodic sweep that evicts terminated jobs older than the
  /// manager's retention window (default 24h). 5-minute cadence to keep
  /// the worst-case age bounded without busy-looping.
  Timer? _jobSweepTimer;

  /// P1-5: tracks which client currently owns the rig. Destructive
  /// endpoints (sequencer start, mount slew, dome open, ...) require
  /// the caller to be the operator or return 409 with a take-over hint.
  late final SessionOwnershipManager _sessionOwnership;

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
  late final DeviceDiscoveryHandlers _deviceDiscoveryHandlers;
  late final CollaborationHandlers _collaborationHandlers;
  late final StaticFileHandlers _staticFileHandlers;
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

  // Wave 6 — Run-Watch (phone/tablet monitoring).
  // The handler exposes /api/run-watch/{snapshot,frame-thumbnail,events}.
  // Backed by a fan-out broadcast stream over `backend.eventStream` so the
  // SSE handler can have any number of concurrent phone clients without
  // touching the tokio broadcast channel on the Rust side.
  late final RunWatchHandlers _runWatchHandlers;
  StreamController<NightshadeEvent>? _runWatchEventBroadcast;

  // Wave 7 Agent 2 — live-stacking broadcast endpoints.
  late final BroadcastHandlers _broadcastHandlers;

  // P2-10 — push-based live-view streaming over /ws/live-view. Backed by
  // a long-lived [LiveViewStreamHub] so subscriber state survives socket
  // churn and the JPEG-encode pipeline only runs while >=1 subscriber is
  // attached.
  late final LiveViewStreamHandlers _liveViewStreamHandlers;
  late final LiveViewStreamHub _liveViewStreamHub;

  // P1-2 / P1-3 — long-running job model handlers.
  late final JobHandlers _jobHandlers;

  // P1-5 — session ownership handlers.
  late final SessionOwnershipHandlers _sessionOwnershipHandlers;

  // P1-14 — remote log retrieval + tail SSE for mobile diagnostics.
  late final LogHandlers _logHandlers;

  // P1-10 — remote calibration library management (darks / flats /
  // defect maps). Constructed unconditionally; the routes are always wired
  // because every deployment has the Drift tables backing them.
  late final CalibrationHandlers _calibrationHandlers;

  // P1-12 — catalog management (download / upload / verify / uninstall /
  // reload). Constructed unconditionally; downloads run via the
  // JobManager so the HTTP connection isn't held open.
  late final CatalogHandlers _catalogHandlers;
  StreamSubscription<CatalogEvent>? _catalogEventSubscription;

  // P2-8 — read-only DB endpoints for tables the phone could not see
  // (sequence runs, notes journal, guide RMS history, polar alignment
  // history, dark library, flat history). Stateless beyond the DAOs it
  // reads off the container.
  late final DbReadHandlers _dbReadHandlers;

  // P2-11 — plugin management. Owns the plugin archive directory under
  // $appData/Nightshade/plugins and the SHA-256 verification path.
  late final PluginHandlers _pluginHandlers;

  // P1-11 — OTA update endpoints. Null when no UpdateController was
  // supplied (test fixtures that don't exercise the update surface);
  // routes are skipped in that case so a missing controller can't 500
  // the rest of the API.
  UpdateHandlers? _updateHandlers;
  StreamSubscription<UpdateEvent>? _updateEventSubscription;

  /// P1-19: LAN UDP broadcaster wired in main_headless.dart /
  /// desktop_app_bootstrap.dart. When supplied, every critical push that
  /// flows through [setPushNotificationStream] is also fanned out as a
  /// UDP datagram so backgrounded phones (Android WS-dropped, foreground-
  /// service iOS) receive the alert even when the WS is broken. Null when
  /// the server is bound loopback-only (no LAN to broadcast on).
  LanPushBroadcaster? _lanPushBroadcaster;

  /// P1-19: optional cellular delivery (FCM/APNs). The base
  /// implementations throw [UnimplementedError] until an operator wires
  /// the cloud-side configuration; see
  /// `docs/remote-control.md#critical-push-notifications-fcm-apns`.
  RemotePushDelivery? _remotePushDelivery;

  HeadlessApiServer({
    required this.port,
    required this.container,
    this.bindLocalOnly = true,
    this.dispatchPluginNodes = true,
    this.authToken,
    this.requireAuth = false,
    this.scopedAuthTokens = const {},
    this.webSocketHeartbeatInterval = const Duration(seconds: 30),
    this.webSocketHeartbeatTimeout = const Duration(seconds: 90),
    this.corsAllowedOrigins = const [],
    this.pairingPrintCodes = false,
    this.tlsContext,
    this.tlsPublicKeyFingerprint,
    this.eventReplayBufferSize = 5000,
    PairingService? pairingService,
    CommandCorrelator? commandCorrelator,
    String? serverInstanceId,
    LanPushBroadcaster? lanPushBroadcaster,
    RemotePushDelivery? remotePushDelivery,
  }) {
    _lanPushBroadcaster = lanPushBroadcaster;
    _remotePushDelivery = remotePushDelivery;
    _pairingService = pairingService;
    // P1-1: fix the server-instance UUID at construction time so unit
    // tests that exercise the /api/info endpoint can observe it
    // synchronously without waiting for start().
    _serverInstanceId = serverInstanceId ?? _generateUuidV4();
    _eventReplayBuffer = EventReplayBuffer(capacity: eventReplayBufferSize);
    // P1-4: caller may inject a deterministic correlator for tests; the
    // default uses Random.secure + DateTime.now.
    _commandCorrelator = commandCorrelator ?? CommandCorrelator();
    final tokensByValue = <String, HeadlessTokenScope>{};

    // Determine effective auth token
    if (authToken != null) {
      _effectiveAuthToken = authToken;
      tokensByValue[authToken!] = HeadlessTokenScope.admin;
    } else if (requireAuth) {
      // Generate a random token
      _effectiveAuthToken = _generateRandomToken();
      tokensByValue[_effectiveAuthToken!] = HeadlessTokenScope.admin;
      // Why: the auto-generated token must be visible to the operator once
      // so they can configure a client, but persisting it in the log file
      // is a security defect — anyone with read access to logs would have
      // permanent admin auth. Print full to stdout (transient), redact in
      // the structured log.
      print('[AUTH] Generated authentication token: $_effectiveAuthToken');
      print(
          '[AUTH] Use this token in the Authorization header: Bearer $_effectiveAuthToken');
      _logWarning(
          '[AUTH] Auto-generated token (first run): ${_redactBearer(_effectiveAuthToken!)}');
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

    // P0-9: when TLS is active, the cert's SubjectPublicKeyInfo SHA-256 is
    // the right identity anchor for client-side cert pinning. The
    // token-derived fingerprint (computed from the admin bearer token, see
    // [computeServerFingerprint]) is retained as the plain-HTTP fallback so
    // existing QR-flow clients keep working unchanged. Format:
    //  - TLS mode:  raw hex digest of SubjectPublicKeyInfo DER (64 chars).
    //  - HTTP mode: sha256("nightshade-remote-v1:" + adminToken).
    final tlsPin = tlsPublicKeyFingerprint?.trim();
    if (tlsPin != null && tlsPin.isNotEmpty) {
      _serverFingerprint = tlsPin;
    } else {
      final identityMaterial = () {
        final primary = _effectiveAuthToken?.trim();
        if (primary != null && primary.isNotEmpty) {
          return primary;
        }
        if (tokensByValue.isNotEmpty) {
          return tokensByValue.keys.first;
        }
        return _generateRandomToken();
      }();
      _serverFingerprint = computeServerFingerprint(identityMaterial);
    }

    // Why: the resolver iterates the entire token map every lookup with
    // constant-time comparison. The map captured here is the union of the
    // configured static tokens; paired-session tokens are checked alongside
    // via [_pairedSessionTokens] (also constant-time) when present.
    _tokenResolver = TokenResolver(tokensByValue: _effectiveAuthTokensByValue);
    _corsAllowList = CorsAllowList.fromConfig(
      additionalOrigins: corsAllowedOrigins,
    );
    _wsTicketManager = WsTicketManager();
    _authCookieManager = AuthCookieManager();
    _pairingAttempts = PairingAttemptTracker();

    // P1-2 / P1-3 — job manager. Constructed BEFORE the device/imaging/
    // framing/session handlers so they can be wired to it. broadcastEvent
    // is a method on this class so we can pass the bound reference even
    // though the server hasn't bound a socket yet — the event stream
    // becomes active in start().
    _jobManager = JobManager(
      emitEvent: broadcastEvent,
    );

    // P1-5 — session ownership manager. The digest function reuses the
    // existing `computeServerFingerprint` helper so token-digest values
    // share the same domain-separated SHA-256 prefix as everywhere else
    // we hash a credential.
    _sessionOwnership = SessionOwnershipManager(
      emitEvent: broadcastEvent,
      digestToken: computeServerFingerprint,
    );

    // Initialize handler instances. Long-running ops (autofocus, plate-
    // solve, center-on-target, polar-alignment) receive the JobManager
    // so their handlers return `{jobId, status: queued}` immediately and
    // run the work in the background. Other handlers don't need it.
    _deviceHandlers = DeviceHandlers(
      container,
      jobManager: _jobManager,
    );
    _deviceDiscoveryHandlers = DeviceDiscoveryHandlers(container);
    _collaborationHandlers = CollaborationHandlers(
      manager: _collaborationManager,
      logger: container.read(loggingServiceProvider),
    );
    _staticFileHandlers = StaticFileHandlers(
      logger: container.read(loggingServiceProvider),
    );
    _guidingHandlers = GuidingHandlers(container);
    _sequencerHandlers = SequencerHandlers(container);
    _equipmentHandlers = EquipmentHandlers(container);
    // [Wave 6B settings sync] inject `broadcastEvent` so handleUpdateSettings
    // can fan settings.changed events out to every connected WS client.
    _profileHandlers = ProfileHandlers(container, emitEvent: broadcastEvent);
    _imagingHandlers = ImagingHandlers(
      container,
      jobManager: _jobManager,
    );
    _sessionHandlers = SessionHandlers(
      container,
      jobManager: _jobManager,
    );

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
    _framingHandlers = FramingHandlers(
      container,
      jobManager: _jobManager,
    );
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

    // Wave 6 — broadcast controller that fans out NightshadeEvents from
    // the backend stream to every connected SSE subscriber. Created here
    // (rather than in `start()`) so it can be passed to the handler ctor
    // and survive a stop()/start() pair without rebuilding the handler.
    _runWatchEventBroadcast = StreamController<NightshadeEvent>.broadcast();
    _runWatchHandlers = RunWatchHandlers(
      container: container,
      eventBroadcast: _runWatchEventBroadcast!.stream,
    );

    // Wave 7 Agent 2 — broadcast endpoint handler (live-stacking
    // viewer for EAA / outreach). Lives independently of the run-watch
    // surface because the broadcast is public-by-default whereas
    // run-watch is paired-only.
    _broadcastHandlers = BroadcastHandlers(container: container);

    // P2-10 — Hub owns the producer loop + subscriber registry across
    // socket churn so we never lose the "is anyone listening?" signal
    // between client reconnects. The handler is a thin wrapper that
    // exposes the WS upgrade callback to the router.
    _liveViewStreamHub = LiveViewStreamHub(container: container);
    _liveViewStreamHandlers = LiveViewStreamHandlers(
      container: container,
      hub: _liveViewStreamHub,
    );

    // P1-14 — remote log retrieval/tail for mobile operators on
    // headless deployments (Pi/embedded). The handler is stateless
    // beyond what's in the LoggingService it reads from the container.
    _logHandlers = LogHandlers(container);

    // P1-10 — remote calibration library management. Stateless beyond the
    // DAOs it reads from the container; no upstream service to dispose.
    _calibrationHandlers = CalibrationHandlers(container);

    // P1-12 — catalog management. The handler dispatches long-running
    // downloads through the JobManager so the action POST returns
    // {jobId} immediately. Catalog lifecycle events are bridged onto
    // the WS event stream in start() below.
    _catalogHandlers = CatalogHandlers(
      jobManager: _jobManager,
      logger: container.read(loggingServiceProvider),
    );

    // P2-8 — db read endpoints. Reads from existing DAOs; no service
    // dependency, so construction is trivial.
    _dbReadHandlers = DbReadHandlers(container);

    // P2-11 — plugin management endpoints. The service is fetched from
    // the container so test fixtures can override
    // `pluginManagementServiceProvider` to point at a temp directory.
    _pluginHandlers = PluginHandlers(container);

    // P1-2 / P1-3 — REST surface for the JobManager that was constructed
    // earlier (before the device handlers so they could be wired).
    _jobHandlers = JobHandlers(jobManager: _jobManager);

    // P1-5 — REST surface for the SessionOwnershipManager.
    _sessionOwnershipHandlers = SessionOwnershipHandlers(
      manager: _sessionOwnership,
      tokenResolver: _extractBearerToken,
    );
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
    // P0-3: admin-only view of currently-valid pairing sessions. Behind the
    // auth middleware (the path is NOT in `publicPaths`) and gated to admin
    // scope via `_adminOnlyPaths`. Lets headless operators on a paired admin
    // client retrieve the active code without watching stdout.
    router.get('/api/pairing/active', _handlePairingActiveList);

    // WebSocket auth ticket (§2.28). Issues a one-shot ticket so browsers
    // don't have to leak the bearer token via WS query parameters.
    router.post('/api/ws/ticket', _handleWsTicketIssue);

    // HttpOnly cookie + CSRF token for the dashboard "remember me" path
    // (§2.5 long-form). The dashboard exchanges a freshly-paired bearer
    // token for a cookie that JS cannot read, plus a CSRF token it must
    // echo on every write. Logout invalidates both.
    router.post('/api/auth/cookie', _handleAuthCookieIssue);
    router.get('/api/auth/csrf', _handleAuthCsrfFetch);
    router.post('/api/auth/logout', _handleAuthLogout);
    router.get('/api/collaboration/state',
        _collaborationHandlers.handleCollaborationState);
    router.post('/api/collaboration/viewers/join',
        _collaborationHandlers.handleCollaborationJoin);
    router.post('/api/collaboration/viewers/leave',
        _collaborationHandlers.handleCollaborationLeave);
    router.post('/api/collaboration/preview',
        _collaborationHandlers.handleCollaborationPreview);
    router.post('/api/collaboration/chat',
        _collaborationHandlers.handleCollaborationChat);
    router.post('/api/collaboration/annotations',
        _collaborationHandlers.handleCollaborationAnnotation);
    router.get('/api/session-handoff',
        _collaborationHandlers.handleGetSessionHandoff);
    router.post('/api/session-handoff',
        _collaborationHandlers.handleSetSessionHandoff);
    router.delete('/api/session-handoff',
        _collaborationHandlers.handleClearSessionHandoff);

    // Device management
    router.get('/api/devices', _deviceDiscoveryHandlers.handleGetDevices);
    router.get('/api/devices/discover-indi',
        _deviceDiscoveryHandlers.handleDiscoverIndiAtAddress);
    router.get('/api/devices/discover-alpaca',
        _deviceDiscoveryHandlers.handleDiscoverAlpacaAtAddress);
    router.get('/api/devices/connected',
        _deviceDiscoveryHandlers.handleGetConnectedDevices);
    router.post('/api/devices/connect', _deviceHandlers.handleConnectDevice);
    router.post(
        '/api/devices/disconnect', _deviceHandlers.handleDisconnectDevice);

    // Camera Control
    router.post('/api/camera/expose', _deviceHandlers.handleCameraExpose);
    router.post('/api/camera/abort', _deviceHandlers.handleCameraAbort);
    router.get(
        '/api/camera/last-image', _deviceHandlers.handleCameraGetLastImage);
    router.get('/api/camera/last-image/jpeg',
        _deviceHandlers.handleCameraGetLastImageJpeg);
    router.get('/api/camera/live-view/frame',
        _deviceHandlers.handleCameraLiveViewFrame);
    router.post('/api/camera/cooling', _deviceHandlers.handleCameraSetCooling);
    router.get('/api/camera/cooling', _deviceHandlers.handleCameraGetCooling);
    router.get('/api/camera/readout-modes',
        _deviceHandlers.handleCameraGetReadoutModes);
    router.post(
        '/api/camera/readoutMode', _deviceHandlers.handleCameraSetReadoutMode);
    router.post('/api/camera/gain', _deviceHandlers.handleCameraSetGain);
    router.post('/api/camera/offset', _deviceHandlers.handleCameraSetOffset);
    router.get('/api/camera/recommended-settings',
        _deviceHandlers.handleCameraGetRecommendedSettings);

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
    // P2-7 — GET sibling of POST /api/filter-wheel/position so mobile
    // can render the current slot, name, and "is moving" flag.
    router.get('/api/filter-wheel/position',
        _deviceHandlers.handleFilterWheelGetPosition);
    router.get(
        '/api/filter-wheel/names', _deviceHandlers.handleFilterWheelGetNames);
    router.post(
        '/api/filter-wheel/names', _deviceHandlers.handleFilterWheelSetNames);
    router.post('/api/filter-wheel/set-by-name',
        _deviceHandlers.handleFilterWheelSetByName);

    // Rotator Control
    router.post('/api/rotator/move-to', _deviceHandlers.handleRotatorMoveTo);
    router.post('/api/rotator/move-relative',
        _deviceHandlers.handleRotatorMoveRelative);
    router.get('/api/rotator/status', _deviceHandlers.handleRotatorGetStatus);
    router.post('/api/rotator/halt', _deviceHandlers.handleRotatorHalt);
    router.post('/api/rotator/sync', _deviceHandlers.handleRotatorSync);

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
    router.post('/api/sequencer/skip-to-node',
        _sequencerHandlers.handleSequencerSkipToNode);
    router.post('/api/sequencer/plugin-node-finished',
        _sequencerHandlers.handleSequencerPluginNodeFinished);
    router.post(
        '/api/sequencer/reset', _sequencerHandlers.handleSequencerReset);
    router.post('/api/sequencer/load', _sequencerHandlers.handleSequencerLoad);
    router.post('/api/sequencer/simulation',
        _sequencerHandlers.handleSequencerSetSimulationMode);
    router.post(
        '/api/sequencer/devices', _sequencerHandlers.handleSequencerSetDevices);
    router.post('/api/sequencer/safety-fail-mode',
        _sequencerHandlers.handleSequencerSetSafetyFailMode);
    router.post('/api/sequencer/safety-check-interval',
        _sequencerHandlers.handleSequencerSetSafetyCheckInterval);
    router.post('/api/sequencer/save-path',
        _sequencerHandlers.handleSequencerSetSavePath);
    router.post('/api/sequencer/active-sequence-run-id',
        _sequencerHandlers.handleSequencerSetActiveSequenceRunId);
    router.post('/api/sequencer/decision-logging-enabled',
        _sequencerHandlers.handleSequencerSetDecisionLoggingEnabled);
    router.post('/api/sequencer/update-dither-config',
        _sequencerHandlers.handleSequencerUpdateDitherConfig);
    router.post('/api/sequencer/update-location',
        _sequencerHandlers.handleSequencerUpdateLocation);
    router.post('/api/sequencer/update-filter-offsets',
        _sequencerHandlers.handleSequencerUpdateFilterOffsets);
    router.post('/api/sequencer/update-pending-integration-carry-over',
        _sequencerHandlers.handleSequencerUpdatePendingIntegrationCarryOver);
    router.post('/api/sequencer/update-autofocus-interval',
        _sequencerHandlers.handleSequencerUpdateAutofocusInterval);
    router.post('/api/sequencer/update-default-quality-check',
        _sequencerHandlers.handleSequencerUpdateDefaultQualityCheck);
    router.post('/api/sequencer/update-reject-folder-path',
        _sequencerHandlers.handleSequencerUpdateRejectFolderPath);
    router.post('/api/sequencer/update-observer-profile',
        _sequencerHandlers.handleSequencerUpdateObserverProfile);
    router.post('/api/sequencer/update-sky-brightness',
        _sequencerHandlers.handleSequencerUpdateSkyBrightness);
    router.post('/api/sequencer/update-default-adaptive-exposure',
        _sequencerHandlers.handleSequencerUpdateDefaultAdaptiveExposure);
    router.post('/api/sequencer/clear-default-adaptive-exposure',
        _sequencerHandlers.handleSequencerClearDefaultAdaptiveExposure);
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

    // Wave 4 Recovery Mode — remote-control endpoints used by the mobile
    // companion / web dashboard. Wire shape matches NetworkBackend's
    // recovery POSTs/GETs (see packages/nightshade_core/.../network_backend.dart).
    router.post('/api/sequencer/recovery/try-now',
        _sequencerHandlers.handleSequencerRecoveryTryNow);
    router.post('/api/sequencer/recovery/abort',
        _sequencerHandlers.handleSequencerRecoveryAbort);
    router.post('/api/sequencer/recovery/update-config',
        _sequencerHandlers.handleSequencerUpdateRecoveryConfig);
    router.get('/api/sequencer/recovery/current',
        _sequencerHandlers.handleSequencerGetCurrentRecovery);
    router.get('/api/sequencer/recovery/history',
        _sequencerHandlers.handleSequencerGetRecoveryHistory);

    // Wave 5 Agent 4 — cloud-motion forwarding from a remote controller.
    router.post('/api/sequencer/update-cloud-motion',
        _sequencerHandlers.handleSequencerUpdateCloudMotion);
    router.get('/api/sequencer/cloud-motion',
        _sequencerHandlers.handleSequencerGetCloudMotion);
    router.post('/api/sequencer/update-conditions-score',
        _sequencerHandlers.handleSequencerUpdateConditionsScore);
    router.get('/api/sequencer/adaptive-swap',
        _sequencerHandlers.handleSequencerGetAdaptiveSwap);

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
    router.post('/api/imaging/calibrate-file',
        _imagingHandlers.handleCalibrateImageFile);
    router.delete('/api/imaging/device-image/<deviceId>',
        _imagingHandlers.handleClearDeviceImage);

    // Polar Alignment
    router.post('/api/polar-alignment/start',
        _sessionHandlers.handleStartPolarAlignment);
    router.post('/api/polar-alignment/all-sky/start',
        _sessionHandlers.handleStartAllSkyPolarAlignment);
    router.post(
        '/api/polar-alignment/stop', _sessionHandlers.handleStopPolarAlignment);

    // Session Images
    router.get('/api/sessions/<sessionId>/images',
        _sessionHandlers.handleGetSessionImages);
    router.get('/api/images', _sessionHandlers.handleGetAllImages);
    // Legacy alias for mobile clients that pre-date /api/images. Why kept:
    // §2.2 of the audit consolidates the two servers into HeadlessApiServer;
    // dropping the legacy path would break pinned mobile builds in the field.
    router.get('/api/images/recent', _sessionHandlers.handleGetRecentImages);
    router.get(
        '/api/images/standalone', _sessionHandlers.handleGetStandaloneImages);
    // P1-13: registered BEFORE the `<imageId>` patterns so the literal
    // `backfill-thumbnails` segment isn't matched as a path param.
    router.post('/api/images/backfill-thumbnails',
        _sessionHandlers.handleBackfillThumbnails);
    router.post('/api/images', _sessionHandlers.handleCreateImage);
    router.get('/api/images/<imageId>', _sessionHandlers.handleGetImageById);
    router.put('/api/images/<imageId>', _sessionHandlers.handleUpdateImage);
    router.get('/api/images/<imageId>/thumbnail',
        _sessionHandlers.handleGetImageThumbnail);
    router.post('/api/images/<imageId>/regenerate-thumbnail',
        _sessionHandlers.handleRegenerateImageThumbnail);
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
    router.get('/api/sequence-management/list-full',
        _sequenceManagementHandlers.handleListFullSequences);
    router.get('/api/sequence-management/templates-full',
        _sequenceManagementHandlers.handleListFullTemplates);
    router.post('/api/sequence-management/save-full',
        _sequenceManagementHandlers.handleSaveFullSequence);
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
    router.get('/api/mosaic/recommended-exposure',
        _mosaicHandlers.handleRecommendExposure);

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
    router.get('/api/weather/current', _weatherHandlers.handleGetCurrent);
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
    router.post('/api/framing/set-target', _framingHandlers.handleSetTarget);
    router.post('/api/framing/save', _framingHandlers.handleSaveFraming);

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

    // ===========================================================================
    // P1-2 / P1-3 — Long-running operation jobs
    // ===========================================================================
    router.get('/api/jobs', _jobHandlers.handleListJobs);
    router.get('/api/jobs/<jobId>',
        (Request req, String jobId) => _jobHandlers.handleGetJob(req, jobId));
    router.post(
        '/api/jobs/<jobId>/cancel',
        (Request req, String jobId) =>
            _jobHandlers.handleCancelJob(req, jobId));
    router.delete('/api/jobs/<jobId>',
        (Request req, String jobId) => _jobHandlers.handlePurgeJob(req, jobId));

    // ===========================================================================
    // P1-5 — Session ownership
    // ===========================================================================
    router.get('/api/session/owner', _sessionOwnershipHandlers.handleGetOwner);
    router.get(
        '/api/session/status', _sessionOwnershipHandlers.handleGetStatus);
    router.post('/api/session/claim', _sessionOwnershipHandlers.handleClaim);
    router.post(
        '/api/session/take-over', _sessionOwnershipHandlers.handleTakeOver);
    router.post(
        '/api/session/release', _sessionOwnershipHandlers.handleRelease);

    // ===========================================================================
    // P1-11 — System / OTA update endpoints. Only registered when an
    // UpdateController was wired via [setUpdateController]; tests and
    // headless deployments that opt out of OTA leave the controller
    // unset, in which case the routes return 404 from the router itself.
    // ===========================================================================
    final updateHandlers = _updateHandlers;
    if (updateHandlers != null) {
      router.get('/api/system/version', updateHandlers.handleGetVersion);
      router.post(
          '/api/system/update/check', updateHandlers.handleCheckForUpdate);
      router.get(
          '/api/system/update/status', updateHandlers.handleGetStatus);
      router.post(
          '/api/system/update/download', updateHandlers.handleDownload);
      router.post('/api/system/update/apply', updateHandlers.handleApply);
      router.post('/api/system/update/abort', updateHandlers.handleAbort);
      router.post(
          '/api/system/update/rollback', updateHandlers.handleRollback);
      router.get(
          '/api/system/update/staged', updateHandlers.handleGetStaged);
      router.delete(
          '/api/system/update/staged', updateHandlers.handleDiscardStaged);
    }

    // WebSocket - support both paths for NetworkBackend compatibility.
    // Why per-route wrappers: shelf_web_socket's `webSocketHandler` strips
    // the original Request, so we capture it in an outer closure so the
    // P1-1 replay handler can read `?since=` and `?instance=` query
    // parameters off the upgrade URL.
    //
    // P2-15: we also lift the auth identity (digest of the bearer token
    // that authenticated the upgrade) off the request context that
    // `_authMiddleware` stashed there. Passing it down means the
    // collaboration `viewerId` is always the authenticated principal,
    // regardless of what the client puts in the `collaboration.join`
    // payload.
    Handler wsHandler() {
      return (Request request) {
        final query = request.url.queryParameters;
        final authIdentity = _authIdentityFrom(request);
        return webSocketHandler((socket, _) {
          _handleWebSocketWithQuery(socket, query, authIdentity);
        }).call(request);
      };
    }

    router.get('/api/ws', wsHandler());
    router.get('/events', wsHandler());

    // P2-10 — push-based live-view streaming. Distinct from the main
    // event WS because (a) it carries binary JPEG frames, not JSON
    // events, and (b) the message protocol is a per-socket
    // subscribe/unsubscribe model rather than the always-on event
    // broadcast.
    router.get('/ws/live-view', (Request request) {
      return webSocketHandler((socket, _) {
        _liveViewStreamHandlers.handleSocket(socket);
      }).call(request);
    });

    // Wave 6 — Run-Watch monitoring endpoints (phone/tablet web app).
    // The SSE endpoint is registered explicitly as a GET handler so the
    // shelf router does not buffer the long-lived response.
    router.get('/api/run-watch/snapshot', _runWatchHandlers.handleSnapshot);
    router.get('/api/run-watch/frame-thumbnail',
        _runWatchHandlers.handleFrameThumbnail);
    router.get('/api/run-watch/events',
        (Request req) => _runWatchHandlers.handleEventStream(req));

    // Wave 7 Agent 2 — live-stacking broadcast (EAA / outreach).
    // The /broadcast HTML page is intentionally served from the same
    // server so a single LAN URL covers the whole audience.
    router.get('/api/broadcast/info', _broadcastHandlers.handleInfo);
    router.get('/api/broadcast/live-stack', _broadcastHandlers.handleLiveStack);
    router.get('/api/broadcast/sse',
        (Request req) => _broadcastHandlers.handleSse(req));
    router.get('/broadcast',
        (Request req) => _broadcastHandlers.handleBroadcastPage(req));

    // P1-14 — remote log endpoints. Mobile operators on headless
    // deployments (Pi / embedded) use these to diagnose without SSH.
    // The SSE tail handler is registered explicitly as a GET so the
    // shelf router does not buffer the long-lived response.
    router.get('/api/logs', _logHandlers.handleListFiles);
    router.get('/api/logs/recent', _logHandlers.handleRecent);
    router.get('/api/logs/files/<filename>/download',
        (Request req, String filename) =>
            _logHandlers.handleDownloadFile(req, filename));
    router.get('/api/logs/tail',
        (Request req) => _logHandlers.handleTail(req));
    router.post('/api/logs/clear', _logHandlers.handleClear);
    router.post('/api/logs/test-entry', _logHandlers.handleTestEntry);

    // ===========================================================================
    // P1-10 — Remote calibration library management (darks, flats,
    // defect maps). Previously the only way to manage these tables on a
    // headless Pi was SSH; now they have a full REST surface.
    // ===========================================================================
    router.get('/api/calibration/darks', _calibrationHandlers.handleListDarks);
    router.post(
        '/api/calibration/darks', _calibrationHandlers.handleRegisterDark);
    router.post('/api/calibration/darks/upload',
        _calibrationHandlers.handleUploadDark);
    router.post('/api/calibration/darks/find-match',
        _calibrationHandlers.handleFindMatchingDark);
    router.post('/api/calibration/darks/backfill-sizes',
        _calibrationHandlers.handleVerifyDarkSizes);
    router.get(
        '/api/calibration/darks/<id>',
        (Request req, String id) =>
            _calibrationHandlers.handleGetDark(req, id));
    router.get(
        '/api/calibration/darks/<id>/download',
        (Request req, String id) =>
            _calibrationHandlers.handleDownloadDark(req, id));
    router.delete(
        '/api/calibration/darks/<id>',
        (Request req, String id) =>
            _calibrationHandlers.handleDeleteDark(req, id));

    router.get('/api/calibration/flats', _calibrationHandlers.handleListFlats);
    router.post(
        '/api/calibration/flats', _calibrationHandlers.handleRecordFlat);
    router.get('/api/calibration/flats/recommendation',
        _calibrationHandlers.handleFlatRecommendation);
    router.get(
        '/api/calibration/flats/<id>',
        (Request req, String id) =>
            _calibrationHandlers.handleGetFlat(req, id));
    router.delete(
        '/api/calibration/flats/<id>',
        (Request req, String id) =>
            _calibrationHandlers.handleDeleteFlat(req, id));

    router.get('/api/calibration/defect-maps',
        _calibrationHandlers.handleListDefectMaps);
    router.post('/api/calibration/defect-maps',
        _calibrationHandlers.handleRegisterDefectMap);
    router.get(
        '/api/calibration/defect-maps/<id>',
        (Request req, String id) =>
            _calibrationHandlers.handleGetDefectMap(req, id));
    router.delete(
        '/api/calibration/defect-maps/<id>',
        (Request req, String id) =>
            _calibrationHandlers.handleDeleteDefectMap(req, id));
    router.post(
        '/api/calibration/defect-maps/<id>/regenerate',
        (Request req, String id) =>
            _calibrationHandlers.handleRegenerateDefectMap(req, id));

    // ===========================================================================
    // P1-12 — Catalog management. Without these endpoints a freshly
    // imaged Pi has no way to populate its star/DSO catalogs without
    // SSH; plate solving fails until someone runs the desktop GUI.
    // ===========================================================================
    router.get('/api/catalog/status', _catalogHandlers.handleStatus);
    router.get('/api/catalog/available', _catalogHandlers.handleAvailable);
    router.post('/api/catalog/download', _catalogHandlers.handleDownload);
    router.post('/api/catalog/upload', _catalogHandlers.handleUpload);
    router.post('/api/catalog/verify', _catalogHandlers.handleVerify);
    router.post('/api/catalog/reload', _catalogHandlers.handleReload);
    router.delete(
        '/api/catalog/<name>',
        (Request req, String name) =>
            _catalogHandlers.handleDelete(req, name));

    // ===========================================================================
    // P2-8 — Read-only DB endpoints for tables the phone couldn't see
    // (sequence runs, notes journal, guide-RMS history, polar alignment
    // history, dark library, flat history). All paginated, all under
    // /api with the same `{items,total}` envelope shape.
    // ===========================================================================
    router.get('/api/sequence-runs', _dbReadHandlers.handleListSequenceRuns);
    router.get('/api/notes-journal', _dbReadHandlers.handleListNotesJournal);
    router.get('/api/guide-rms-history',
        _dbReadHandlers.handleListGuideRmsHistory);
    router.get('/api/polar-alignment-history',
        _dbReadHandlers.handleListPolarAlignmentHistory);
    router.get('/api/db/dark-library', _dbReadHandlers.handleListDarkLibrary);
    router.get('/api/db/flat-history', _dbReadHandlers.handleListFlatHistory);

    // ===========================================================================
    // P2-11 — Plugin management. Upload uses the raw body for the
    // archive bytes; the `filename` and optional `sha256` come in as
    // query parameters (same shape as /api/catalog/upload).
    // ===========================================================================
    router.get('/api/plugins', _pluginHandlers.handleListPlugins);
    router.post('/api/plugins/upload', _pluginHandlers.handleUploadPlugin);
    router.post(
        '/api/plugins/<pluginId>/enable',
        (Request req, String pluginId) =>
            _pluginHandlers.handleEnablePlugin(req, pluginId));
    router.post(
        '/api/plugins/<pluginId>/disable',
        (Request req, String pluginId) =>
            _pluginHandlers.handleDisablePlugin(req, pluginId));
    router.delete(
        '/api/plugins/<pluginId>',
        (Request req, String pluginId) =>
            _pluginHandlers.handleUninstallPlugin(req, pluginId));

    // Web Dashboard - static file serving
    router.get('/dashboard', _staticFileHandlers.handleDashboardIndex);
    router.get('/dashboard/', _staticFileHandlers.handleDashboardIndex);
    router.get('/dashboard/<path|.*>', _staticFileHandlers.handleDashboardFile);

    // Wave 6 — Run-Watch SPA static files. Mirrors the /dashboard
    // resolver but searches `web_run_watch/` next to the executable
    // and in the source tree.
    router.get('/run-watch', _staticFileHandlers.handleRunWatchIndex);
    router.get('/run-watch/', _staticFileHandlers.handleRunWatchIndex);
    router.get('/run-watch/<path|.*>', _staticFileHandlers.handleRunWatchFile);

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
          shouldBypass: (request) {
            final path = '/${request.url.path}';
            // P2-10: also bypass /ws/live-view so shelf does not try to
            // wrap the WS upgrade response into a JSON error envelope.
            return path == '/api/ws' ||
                path == '/events' ||
                path == '/ws/live-view';
          },
        ))
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_requestSizeLimitMiddleware())
        .addMiddleware(_apiVersionMiddleware())
        .addMiddleware(_authMiddleware())
        .addMiddleware(_rateLimitMiddleware())
        .addMiddleware(_highRiskAuditMiddleware())
        // P1-5: ownership gate runs AFTER auth so we only check ownership
        // for requests that already presented a valid token. Placed
        // before the router so the 409 short-circuits the handler.
        .addMiddleware(_sessionOwnershipMiddleware())
        .addHandler(router.call);

    final bindAddress =
        bindLocalOnly ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4;
    // P0-9: when a TLS SecurityContext is supplied, bind HTTPS instead of
    // HTTP. shelf_io.serve transparently upgrades the WebSocket layer to
    // WSS for us because the underlying HttpServer is secure.
    _server = await shelf_io.serve(
      handler,
      bindAddress,
      port,
      securityContext: tlsContext,
    );
    final scheme = tlsContext != null ? 'https' : 'http';
    _logInfo(
        'Headless API server running on $scheme://${_server!.address.host}:${_server!.port}');
    if (tlsContext != null) {
      _logInfo(
          '[TLS] Transport encryption is ENABLED. Bearer tokens and pairing codes are protected on the wire.');
    }
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

    // P0-2 + P0-10: hydrate `_pairedSessionTokens` from the Drift DB and
    // register a revocation listener so revokeDevice() / token expiry / the
    // periodic sweep all evict the in-memory entry synchronously without a
    // server restart. Must run AFTER bind so a hydration error doesn't trap
    // operator-facing connect-URL printing in main_headless.dart.
    await _hydratePairedSessionTokens();
    _installRevocationListener();
    _scheduleTokenSweep();

    // P1-4: periodically evict expired pending commands so a hung driver
    // (or a sequence aborted before a completion event fires) doesn't keep
    // the correlator table growing forever.
    _commandCorrelatorSweepTimer?.cancel();
    _commandCorrelatorSweepTimer =
        Timer.periodic(const Duration(minutes: 5), (_) {
      try {
        _commandCorrelator.evictExpired();
      } catch (e) {
        _logWarning('CommandCorrelator sweep failed: $e');
      }
    });

    // P1-2 / P1-3: purge terminated jobs older than the manager's
    // retention window. 5-minute cadence keeps the worst-case age at
    // `retention + 5min` which is well within the documented 24h budget.
    _jobSweepTimer?.cancel();
    _jobSweepTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      try {
        _jobManager.evictExpired();
      } catch (e) {
        _logWarning('JobManager sweep failed: $e');
      }
    });

    // Subscribe to backend events and broadcast to WebSocket clients
    _subscribeToBackendEvents();
    _subscribeToSequenceCatalogUpdates();
    _subscribeToHostMutationEvents();
    _subscribeToCatalogManagerEvents();
    _collaborationSubscription =
        _collaborationManager.stream.listen(_broadcastCollaborationState);

    // P1-19: start the LAN UDP push broadcaster (when wired). We start it
    // only when the server is non-loopback — loopback-only deployments
    // have no LAN to fan out on, so the bind would just waste sockets.
    final broadcaster = _lanPushBroadcaster;
    if (broadcaster != null && !bindLocalOnly && !broadcaster.isStarted) {
      try {
        await broadcaster.start();
        _logInfo(
          '[push] LAN push broadcaster started '
          '(port=${broadcaster.port}, interfaces=${broadcaster.activeSinkCount})',
        );
      } catch (e, st) {
        // Bind failure is not fatal — UDP push is a supplement to the WS
        // fan-out. Surface a warning so the operator knows phones won't
        // wake on critical alerts when the WS is broken.
        _logWarning(
          '[push] LAN push broadcaster failed to start: $e\n$st — '
          'critical alerts will only reach phones via the WebSocket.',
        );
      }
    } else if (broadcaster != null && bindLocalOnly) {
      _logInfo(
        '[push] LAN push broadcaster supplied but server is loopback-only; '
        'broadcaster will not start.',
      );
    }
  }

  /// Load all active, unexpired pairing tokens from Drift into the in-memory
  /// `_pairedSessionTokens` map. Without this, every server restart evicts
  /// every HTTP-paired client (audit F-3 in 01-connection-auth.md). The
  /// hydrated scope is heuristic: the DB doesn't currently store the granted
  /// scope per device, so we default to `control` — the same default the
  /// verify path uses when `requestedScope` is unset. Operators who pair as
  /// admin must re-pair if they want admin again after the next restart;
  /// this matches the verify-path default and is documented in the
  /// release notes.
  Future<void> _hydratePairedSessionTokens() async {
    // Skip hydration when no PairingService is available. The service is
    // either injected via the constructor (tests / GUI in-memory pairing
    // DB) or lazily constructed via [_ensurePairingService] on first use.
    // Constructing it eagerly inside `start()` would force every test that
    // does NOT exercise pairing to open the on-disk Drift DB, which in
    // turn needs path_provider — which is unavailable in widget-test
    // bindings. The verify endpoint still lazy-creates the service on
    // first paired call.
    final service = _pairingService;
    if (service == null) {
      _logInfo(
        '[AUTH] Skipping paired-session hydration: no PairingService '
        'configured yet (will be created on first pairing request).',
      );
      return;
    }
    try {
      final rows = await service.tokenManager.getActiveUnexpiredPairedDevices();
      var restored = 0;
      for (final row in rows) {
        // Default to `control` scope — see method-doc rationale above.
        _pairedSessionTokens[row.sessionToken] = HeadlessTokenScope.control;
        restored++;
      }
      _logInfo(
        '[AUTH] Restored $restored paired session token(s) from disk',
        fields: {'restored': restored},
      );
    } catch (e, st) {
      // We do NOT silently fall back to an empty map: the audit flagged
      // silent-restart-loses-clients as the actual production-breaking
      // failure mode. If hydration crashes we want the operator to know
      // their phones may need to re-pair, so log it loudly.
      _logError(
        '[AUTH] Failed to hydrate paired session tokens from disk: $e\n$st',
      );
    }
  }

  /// Register the [TokenManager] revocation listener so revocations from
  /// any code path (`TokenManager.revokeDevice`, the periodic sweep, the
  /// expiry path in `verifySessionToken`) propagate to the in-memory map.
  ///
  /// Skipped when no PairingService has been injected; the lazy-construct
  /// path inside [_handlePairingVerify] re-registers the listener via
  /// [_ensurePairingService] once a service exists. See
  /// [_hydratePairedSessionTokens] for the symmetric reasoning.
  void _installRevocationListener() {
    final service = _pairingService;
    if (service == null) return;
    service.tokenManager.setRevocationListener(_evictPairedSessionToken);
  }

  /// Remove a paired-session token from the in-memory map. Idempotent: if
  /// the token is unknown (already evicted, or never present) the call is a
  /// no-op so concurrent sweep + verify paths cannot fight.
  void _evictPairedSessionToken(String sessionToken) {
    final scope = _pairedSessionTokens.remove(sessionToken);
    if (scope != null) {
      _logInfo(
        '[AUTH] Evicted paired session token (${_redactBearer(sessionToken)}) '
        'from in-memory map (scope=${headlessTokenScopeName(scope)})',
      );
    }
  }

  /// Periodic sweep that calls into `TokenManager.purgeExpiredAndRevokedSessions`.
  /// Why 60 s: revocation propagation is bounded by this interval. The
  /// `_evictPairedSessionToken` callback runs synchronously on direct revoke
  /// paths, but the sweep also catches tokens that hit `expires_at` between
  /// requests (no client ever attempted to use them, so the verify path
  /// never fired the listener).
  void _scheduleTokenSweep() {
    _tokenSweepTimer?.cancel();
    _tokenSweepTimer = Timer.periodic(tokenSweepInterval, (_) async {
      final service = _pairingService;
      if (service == null) return;
      try {
        final result =
            await service.tokenManager.purgeExpiredAndRevokedSessions();
        if (!result.isEmpty) {
          _logInfo(
            '[AUTH] Token sweep purged ${result.expiredTokens.length} expired '
            'and ${result.revokedTokens.length} revoked session token(s)',
          );
        }
      } catch (e, st) {
        _logWarning(
          '[AUTH] Token sweep failed: $e\n$st',
        );
      }
    });
  }

  void _subscribeToSequenceCatalogUpdates() {
    _catalogUpdateSubscription?.cancel();
    _catalogUpdateSubscription = container
        .read(sequenceCatalogUpdateBusProvider)
        .stream
        .listen((update) {
      broadcastEvent(update.toNightshadeEvent());
    });
  }

  void _subscribeToHostMutationEvents() {
    final hub = container.read(hostMutationEventHubProvider);
    hub.wsBroadcast = (event) {
      broadcastEvent(event);
      final ctrl = _runWatchEventBroadcast;
      if (ctrl != null && !ctrl.isClosed) {
        try {
          ctrl.add(event);
        } catch (e) {
          _logWarning('[run-watch] host-mutation SSE fan-out failed: $e');
        }
      }
    };
  }

  void _unsubscribeFromHostMutationEvents() {
    container.read(hostMutationEventHubProvider).wsBroadcast = null;
  }

  /// P1-12: bridge [CatalogManager.events] onto the WS event stream so
  /// clients see structured catalog lifecycle messages
  /// (`CatalogDownloadStarted`, `CatalogDownloadProgress`,
  /// `CatalogVerified`, ...) in the `catalog` category. The fan-out
  /// happens inside the manager's stream listener so this works even
  /// when the catalog op was initiated from the local GUI rather than
  /// the REST API.
  void _subscribeToCatalogManagerEvents() {
    _catalogEventSubscription?.cancel();
    _catalogEventSubscription = CatalogManager.instance.events.listen(
      (event) {
        final severity = switch (event.eventType) {
          'CatalogDownloadFailed' => EventSeverity.error,
          'CatalogVerified' => (event.data['ok'] == true)
              ? EventSeverity.info
              : EventSeverity.warning,
          _ => EventSeverity.info,
        };
        broadcastEvent(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: severity,
          category: EventCategory.catalog,
          eventType: event.eventType,
          data: Map<String, dynamic>.from(event.data),
        ));
      },
      onError: (Object e, _) {
        _logWarning('[catalog] event stream error: $e');
      },
    );
  }

  void _subscribeToBackendEvents() {
    try {
      final backend = container.read(backendProvider);
      _eventSubscription = backend.eventStream.listen((event) {
        broadcastEvent(event);
        // Wave 6: re-broadcast onto the SSE fan-out controller. Two
        // separate sinks (WS clients + SSE clients) read from the same
        // upstream so a phone subscribing via SSE sees the same events
        // as the desktop dashboard's WebSocket.
        final ctrl = _runWatchEventBroadcast;
        if (ctrl != null && !ctrl.isClosed) {
          try {
            ctrl.add(event);
          } catch (e) {
            // A failure inside the SSE fan-out must never crash the
            // upstream event subscription that the WS path depends on.
            _logWarning('[run-watch] SSE fan-out add failed: $e');
          }
        }
        _dispatchPluginNodeIfRequested(event);
      });
    } catch (e) {
      _logError('[API] Failed to subscribe to backend events: $e');
    }
  }

  void _dispatchPluginNodeIfRequested(NightshadeEvent event) {
    if (!dispatchPluginNodes ||
        event.category != EventCategory.sequencer ||
        event.eventType != 'PluginNodeRequested') {
      return;
    }

    final backend = container.read(backendProvider);
    if (!backend.dispatchPluginNodesLocally) {
      _logInfo(
        '[plugin-node] Remote backend event ignored; host-side dispatcher '
        'owns plugin node execution',
      );
      return;
    }

    final nodeId = event.data['node_id'] as String? ?? '';
    final pluginId = event.data['plugin_id'] as String? ?? '';
    final nodeTypeId = event.data['node_type_id'] as String? ?? '';
    final configJson = event.data['config_json'] as String? ?? '';
    final displayName = event.data['display_name'] as String?;
    final rawTimeout = event.data['timeout_secs'];
    final timeoutSecs = rawTimeout is num ? rawTimeout.toInt() : 600;

    if (nodeId.isEmpty) {
      _logWarning(
        '[plugin-node] PluginNodeRequested event missing node_id '
        '(plugin=$pluginId, node_type=$nodeTypeId)',
      );
      return;
    }

    final coordinator = container.read(pluginNodeDispatchCoordinatorProvider);
    if (!coordinator.claim(nodeId)) {
      _logInfo(
        '[plugin-node] PluginNodeRequested ignored; another local listener '
        'claimed node_id=$nodeId',
      );
      return;
    }

    final dispatcher = container.read(pluginNodeDispatcherProvider);
    unawaited(() async {
      late PluginNodeDispatchResult result;
      try {
        result = await dispatcher(
          PluginNodeDispatchRequest(
            nodeId: nodeId,
            pluginId: pluginId,
            nodeTypeId: nodeTypeId,
            configJson: configJson,
            displayName: displayName,
            timeoutSecs: timeoutSecs,
          ),
        );
      } catch (e, st) {
        _logError(
          '[plugin-node] Dispatcher threw for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
        );
        result = PluginNodeDispatchResult(
          success: false,
          message: 'dispatcher threw: $e',
        );
      }

      try {
        await backend.sequencerPluginNodeFinished(
          nodeId: nodeId,
          success: result.success,
          message: result.message,
          structuredDetailJson: result.structuredDetailJson,
        );
      } catch (e, st) {
        _logError(
          '[plugin-node] Failed to deliver verdict for $pluginId/$nodeTypeId '
          '(node_id=$nodeId): $e\n$st',
        );
      } finally {
        coordinator.release(nodeId);
      }
    }());
  }

  Future<void> stop() async {
    _unsubscribeFromHostMutationEvents();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    await _catalogUpdateSubscription?.cancel();
    _catalogUpdateSubscription = null;
    // P1-12: drop the bridge from CatalogManager.events to the WS
    // broadcaster so the manager's controller can finish flushing on
    // disposal without us still listening.
    await _catalogEventSubscription?.cancel();
    _catalogEventSubscription = null;
    await _collaborationSubscription?.cancel();
    _collaborationSubscription = null;
    await _pushNotificationSubscription?.cancel();
    _pushNotificationSubscription = null;
    // P1-19: tear down the LAN UDP broadcaster + remote delivery hooks.
    // Ownership note: the broadcaster's lifecycle is shared with the
    // server it was passed to. Calling stop() here is the right thing
    // because we constructed/owned its sockets via [start]; the caller
    // that supplied it expects this teardown when the server stops.
    final lanBroadcaster = _lanPushBroadcaster;
    _lanPushBroadcaster = null;
    if (lanBroadcaster != null) {
      await lanBroadcaster.stop();
    }
    final remote = _remotePushDelivery;
    _remotePushDelivery = null;
    if (remote != null) {
      await remote.dispose();
    }
    _webSocketHeartbeatTimer?.cancel();
    _webSocketHeartbeatTimer = null;
    // P0-10: stop the periodic token sweep before tearing down the DB, and
    // clear the revocation listener so it does not retain a reference to
    // `this` past disposal.
    _tokenSweepTimer?.cancel();
    _tokenSweepTimer = null;
    // P1-4: stop the correlator eviction sweep.
    _commandCorrelatorSweepTimer?.cancel();
    _commandCorrelatorSweepTimer = null;
    _commandCorrelator.clear();
    _eventReplayBuffer.clear();
    // P1-2 / P1-3: stop job sweep + drain the manager. Any in-flight
    // work observes the cancellation flag and exits its next poll.
    _jobSweepTimer?.cancel();
    _jobSweepTimer = null;
    await _jobManager.dispose();
    // P1-5: tear down ownership state and broadcast controller.
    await _sessionOwnership.dispose();
    final pairingForListener = _pairingService;
    if (pairingForListener != null) {
      pairingForListener.tokenManager.setRevocationListener(null);
    }
    // Wave 6: closing the broadcast controller signals all attached
    // SSE clients to disconnect cleanly. The handler's onCancel cleans
    // up its own per-client timer + subscription.
    final ctrl = _runWatchEventBroadcast;
    _runWatchEventBroadcast = null;
    if (ctrl != null && !ctrl.isClosed) {
      await ctrl.close();
    }
    // P2-10: tear down the live-view hub before the HTTP server so any
    // in-flight producer tick observes the disposal flag and stops
    // touching the backend.
    await _liveViewStreamHub.dispose();
    await _server?.close(force: true);
    _server = null;
    for (final socket in List.of(_sockets)) {
      await socket.sink.close();
    }
    _socketViewerIds.clear();
    _socketAuthIdentities.clear();
    _socketLastSeenAt.clear();
    _sockets.clear();
    _collaborationManager.dispose();
    // Why close the pairing DB: PairingService owns a Drift connection.
    // Leaving it open across server restarts leaks file handles in tests.
    final pairing = _pairingService;
    if (pairing != null) {
      await pairing.close();
      _pairingService = null;
    }
  }

  /// Broadcast an event to all connected WebSocket clients.
  ///
  /// P1-1: every NightshadeEvent is stamped with a monotonic `seq` and the
  /// server-instance UUID, then appended to the replay ring buffer BEFORE
  /// fan-out to sockets. Map-typed events (legacy callers passing raw
  /// JSON) are coerced through NightshadeEvent.fromWireJson so SSE,
  /// snapshot consumers, and future replay subscribers see a consistent
  /// shape.
  ///
  /// P1-4: NightshadeEvents whose `eventType` is in the command-completion
  /// table get their originating `correlatingCommandId` stamped from the
  /// correlator on a best-effort basis.
  ///
  /// The replay buffer append is done BEFORE the early-return on empty
  /// sockets: SSE clients and the snapshot endpoint can still pick up
  /// the buffered events even if no WS clients are connected.
  void broadcastEvent(dynamic event) {
    final stamped = _stampEventForBroadcast(event);
    if (stamped == null) {
      // Non-event payload (e.g. raw map without the canonical fields).
      // Don't sequence it but still emit so legacy callers continue to
      // work. These payloads bypass the replay buffer by design.
      _emitRawEvent(event);
      return;
    }
    _eventReplayBuffer.append(stamped);
    _emitStampedEvent(stamped);
  }

  /// Stamp a NightshadeEvent (or coerce a Map into one) with the next
  /// sequence number, the server-instance id, and any matching commandId.
  ///
  /// Returns null when [raw] is neither a NightshadeEvent nor an
  /// event-shaped Map that we can reconstruct. The caller falls back to a
  /// non-sequenced raw emit in that case.
  NightshadeEvent? _stampEventForBroadcast(dynamic raw) {
    NightshadeEvent? base;
    if (raw is NightshadeEvent) {
      base = raw;
    } else if (raw is Map<String, dynamic>) {
      try {
        base = NightshadeEvent.fromWireJson(raw);
      } on FormatException {
        return null;
      }
    } else {
      return null;
    }

    _eventSeq += 1;
    final operation = operationForCompletionEvent(base.eventType);
    final deviceId = base.data['deviceId'] is String
        ? base.data['deviceId'] as String
        : null;
    String? correlatingCommandId = base.correlatingCommandId;
    if (correlatingCommandId == null && operation != null) {
      correlatingCommandId = _commandCorrelator.stampEvent(
        operation: operation,
        deviceId: deviceId,
      );
    }
    return base.copyWith(
      seq: _eventSeq,
      serverInstanceId: _serverInstanceId,
      correlatingCommandId: correlatingCommandId,
    );
  }

  /// Serialise a stamped event and push to every connected socket.
  void _emitStampedEvent(NightshadeEvent stamped) {
    if (_sockets.isEmpty) return;
    final jsonEvent = _encodeStampedEventForWire(stamped);
    if (jsonEvent == null) return;
    for (final socket in List.of(_sockets)) {
      try {
        socket.sink.add(jsonEvent);
      } catch (e) {
        _logWarning('Error broadcasting to socket: $e');
      }
    }
  }

  /// Encode a stamped event into the WebSocket wire envelope. Returns
  /// null if encoding failed (logged inside).
  String? _encodeStampedEventForWire(NightshadeEvent stamped,
      {bool replay = false}) {
    try {
      final json = stamped.toJson();
      if (stamped.category == EventCategory.guiding &&
          stamped.eventType == 'GuideStep') {
        final data = json['data'];
        if (data is Map<String, dynamic>) {
          final raRaw = data['RADistanceRaw'];
          final decRaw = data['DECDistanceRaw'];
          if (raRaw is num && !data.containsKey('raPx')) {
            data['raPx'] = raRaw.toDouble();
          }
          if (decRaw is num && !data.containsKey('decPx')) {
            data['decPx'] = decRaw.toDouble();
          }
        }
      }
      return jsonEncode({
        'type': 'event',
        if (replay) 'replay': true,
        ...json,
      });
    } catch (e) {
      _logError('Error encoding event for broadcast: $e');
      return null;
    }
  }

  /// Fallback emit path for non-event payloads. Bypasses the ring buffer
  /// and sequence stamping.
  void _emitRawEvent(dynamic event) {
    if (_sockets.isEmpty) return;
    String jsonEvent;
    try {
      if (event is Map<String, dynamic>) {
        jsonEvent = jsonEncode({'type': 'event', ...event});
      } else {
        jsonEvent = jsonEncode(event);
      }
    } catch (e) {
      _logError('Error encoding non-event payload for broadcast: $e');
      return;
    }
    for (final socket in List.of(_sockets)) {
      try {
        socket.sink.add(jsonEvent);
      } catch (e) {
        _logWarning('Error broadcasting non-event payload: $e');
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

  /// Forward push notifications from a [PushNotificationService] stream to all
  /// connected WebSocket clients. Notifications are sent verbatim (the service
  /// emits the `type: 'push_notification'` envelope) so the mobile client can
  /// distinguish them from `type: 'event'` broadcasts and surface them as
  /// system notifications instead of UI updates.
  ///
  /// Why on the server rather than the service: the WebSocket fan-out lives
  /// here. Re-subscribing replaces any previous subscription so the GUI can
  /// safely call this every time the backend changes.
  ///
  /// P1-19: in addition to the WS fan-out, each notification is also handed
  /// to the LAN UDP broadcaster (when configured) so phones whose WebSocket
  /// has dropped still wake on critical alerts. The broadcaster filters by
  /// severity (critical-only by default) and supplies its own HMAC-signed
  /// wire frame; see lan_push_broadcaster.dart for the protocol spec.
  void setPushNotificationStream(
      Stream<Map<String, dynamic>> notificationStream) {
    _pushNotificationSubscription?.cancel();
    _pushNotificationSubscription = notificationStream.listen(
      (notification) {
        // Always do the WS fan-out — even if no sockets are attached, we
        // still kick the LAN broadcaster + remote delivery so a phone that
        // can't keep its WS open still gets the alert.
        if (_sockets.isNotEmpty) {
          final String encoded;
          try {
            encoded = jsonEncode(notification);
          } catch (e) {
            _logWarning('Error encoding push notification: $e');
            return;
          }
          for (final socket in List.of(_sockets)) {
            try {
              socket.sink.add(encoded);
            } catch (e) {
              _logWarning('Error broadcasting push notification: $e');
            }
          }
        }

        // P1-19: LAN UDP broadcaster + remote (FCM/APNs) delivery hooks.
        // Building the wire frame is cheap; if neither sink is wired we
        // skip the encode entirely.
        final broadcaster = _lanPushBroadcaster;
        final remote = _remotePushDelivery;
        if (broadcaster == null && remote == null) {
          return;
        }
        final frame = _buildPushFrameFromNotification(notification);
        if (frame == null) {
          return;
        }
        if (broadcaster != null && broadcaster.isStarted) {
          // Fire-and-forget — sendCriticalPush is non-blocking on the
          // happy path. Errors inside the broadcaster surface via its own
          // logger, so we don't need a try/catch here.
          unawaited(broadcaster.sendCriticalPush(frame));
        }
        if (remote != null) {
          unawaited(_deliverRemotePush(remote, frame));
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _logError('Push notification stream error: $error');
      },
    );
  }

  /// Coerce a `push_notification` JSON envelope into a wire-format
  /// [PushNotificationFrame]. Returns null when the envelope is missing
  /// required fields — those are logged so a malformed producer is
  /// visible rather than silently dropped.
  PushNotificationFrame? _buildPushFrameFromNotification(
    Map<String, dynamic> notification,
  ) {
    final title = notification['title'];
    final body = notification['body'];
    final priority = notification['priority'];
    final eventType = notification['eventType'];
    final category = notification['category'];
    final timestamp = notification['timestamp'];
    if (title is! String || body is! String) {
      _logWarning(
        'Push notification missing title/body — skipping LAN fan-out',
        fields: {'envelope_keys': notification.keys.toList()},
      );
      return null;
    }
    // Map the existing PushNotificationPriority labels (low/normal/high/
    // critical) onto the wire-protocol severity labels. Anything other
    // than critical/warning collapses to `info`. The broadcaster's
    // severity filter (critical-only by default) takes care of dropping
    // the lower tiers without further work here.
    final severity = switch (priority) {
      'critical' => 'critical',
      'high' => 'warning',
      _ => 'info',
    };
    final eventDeviceMap = <String, Object?>{};
    if (eventType is String) eventDeviceMap['eventType'] = eventType;
    if (category is String) eventDeviceMap['category'] = category;
    final ts = timestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    return PushNotificationFrame(
      id: _generateUuidV4(),
      severity: severity,
      title: title,
      body: body,
      data: eventDeviceMap,
      timestamp: ts,
      serverFingerprint: _serverFingerprint,
    );
  }

  Future<void> _deliverRemotePush(
    RemotePushDelivery remote,
    PushNotificationFrame frame,
  ) async {
    try {
      await remote.deliver(frame);
    } on UnimplementedError catch (e) {
      // Expected when the FCM/APNs scaffold is in place but no operator
      // has wired the cloud-side credentials. Log once-per-frame at
      // debug-level severity so the missing setup is visible without
      // spamming the operator's error log.
      _logInfo('Remote push delivery not configured: $e');
    } catch (e, st) {
      _logWarning('Remote push delivery failed: $e\n$st');
    }
  }

  /// P1-19: replace the LAN push broadcaster post-construction (used by
  /// `desktop_app_bootstrap.dart` so the broadcaster's lifecycle is tied
  /// to the GUI's settings toggle rather than the server's constructor).
  /// Pass null to disable.
  void setLanPushBroadcaster(LanPushBroadcaster? broadcaster) {
    _lanPushBroadcaster = broadcaster;
  }

  /// P1-19: register a remote (FCM/APNs) delivery hook. By default both
  /// scaffolds throw [UnimplementedError]; the headless server logs
  /// those as informational so the operator can see "remote push not
  /// configured" without taking down the LAN broadcaster.
  void setRemotePushDelivery(RemotePushDelivery? delivery) {
    _remotePushDelivery = delivery;
  }

  /// P1-11: bind an [UpdateController] to the server. The controller's
  /// `events` stream is subscribed and every variant translated into a
  /// `NightshadeEvent` with `category: EventCategory.system`. Routes
  /// under `/api/system/version` + `/api/system/update/*` are installed
  /// on the next [start()] call.
  ///
  /// Pass null to detach (e.g. on shutdown so the WS broadcast stream
  /// does not keep delivering events after the underlying service has
  /// been disposed).
  void setUpdateController(UpdateController? controller) {
    _updateEventSubscription?.cancel();
    _updateEventSubscription = null;
    if (controller == null) {
      _updateHandlers = null;
      return;
    }
    _updateHandlers = UpdateHandlers(
      controller: controller,
      jobManager: _jobManager,
    );
    _updateEventSubscription = controller.events.listen(
      (event) {
        final severity = event is UpdateFailedEvent ||
                event is UpdateVerificationFailedEvent
            ? EventSeverity.error
            : EventSeverity.info;
        broadcastEvent(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: severity,
          category: EventCategory.system,
          eventType: event.type,
          data: event.data,
        ));
      },
      onError: (Object error, StackTrace stackTrace) {
        _logError('UpdateController event stream error: $error');
      },
    );
  }

  // ===========================================================================
  // Core Handlers (kept inline for simplicity)
  // ===========================================================================

  Future<Response> _handleInfo(Request request) async {
    final platformCapabilities =
        PlatformCapabilityMatrix.forPlatform(Platform.operatingSystem);
    final versionInfo = container.read(appVersionProvider);
    final dashboardAvailable = _staticFileHandlers.dashboardAvailable;

    return jsonOk(
      {
        'name': 'Nightshade Headless',
        'version': versionInfo.version,
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
        'pairingSupported': true,
        'fingerprint': _serverFingerprint,
        // P1-1: surface the sequencing + replay state so a reconnecting
        // client can decide between `?since=` replay and a full
        // `/api/run-watch/snapshot` rehydrate without guessing.
        'serverInstanceId': _serverInstanceId,
        'currentEventSeq': _eventSeq,
        'eventReplayBufferSize': eventReplayBufferSize,
        'eventReplayBufferOldestSeq': _eventReplayBuffer.oldestSeq,
        'apiOnlyMode': true,
        'webUIAvailable': dashboardAvailable,
        'publicEndpoints': [
          '/api/info',
          '/api/pairing/start',
          '/api/pairing/verify',
          '/dashboard',
          // Wave 6: the run-watch SPA bundle is auth-exempt so the
          // phone can load it before pairing. The /api/run-watch/*
          // endpoints themselves still require a Bearer token.
          '/run-watch',
        ],
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
      'POST /api/pairing/start',
      'POST /api/pairing/verify',
      // P0-3: admin-only diagnostic listing currently-valid pairing
      // codes so a headless operator on a paired admin client can
      // retrieve the code without watching stdout.
      'GET /api/pairing/active',
      'POST /api/ws/ticket',
      'POST /api/auth/cookie',
      'GET /api/auth/csrf',
      'POST /api/auth/logout',
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
      'GET /api/camera/last-image/jpeg',
      'GET /api/camera/live-view/frame',
      // P2-10 — push-based live-view streaming. Listed alongside the pull
      // endpoint so OpenAPI consumers see both options.
      'WS /ws/live-view',
      'POST /api/camera/cooling',
      'GET /api/camera/cooling',
      'GET /api/camera/readout-modes',
      'POST /api/camera/readoutMode',
      'POST /api/camera/gain',
      'POST /api/camera/offset',
      'GET /api/camera/recommended-settings',
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
      'GET /api/filter-wheel/position',
      'GET /api/filter-wheel/names',
      'POST /api/filter-wheel/names',
      'POST /api/filter-wheel/set-by-name',
      // Rotator
      'POST /api/rotator/move-to',
      'POST /api/rotator/move-relative',
      'GET /api/rotator/status',
      'POST /api/rotator/halt',
      'POST /api/rotator/sync',
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
      // Broadcast
      'GET /api/broadcast/info',
      'GET /api/broadcast/live-stack',
      'GET /api/broadcast/sse',
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
      'POST /api/sequencer/skip-to-node',
      'POST /api/sequencer/plugin-node-finished',
      'POST /api/sequencer/reset',
      'POST /api/sequencer/load',
      'POST /api/sequencer/simulation',
      'POST /api/sequencer/devices',
      'POST /api/sequencer/safety-fail-mode',
      'POST /api/sequencer/safety-check-interval',
      'POST /api/sequencer/save-path',
      'POST /api/sequencer/active-sequence-run-id',
      'POST /api/sequencer/decision-logging-enabled',
      'POST /api/sequencer/update-dither-config',
      'POST /api/sequencer/update-location',
      'POST /api/sequencer/update-filter-offsets',
      'POST /api/sequencer/update-pending-integration-carry-over',
      'POST /api/sequencer/update-autofocus-interval',
      'POST /api/sequencer/update-default-quality-check',
      'POST /api/sequencer/update-reject-folder-path',
      'POST /api/sequencer/update-observer-profile',
      'POST /api/sequencer/update-sky-brightness',
      'POST /api/sequencer/update-default-adaptive-exposure',
      'POST /api/sequencer/clear-default-adaptive-exposure',
      'POST /api/sequencer/checkpoint/dir',
      'GET /api/sequencer/checkpoint/has',
      'GET /api/sequencer/checkpoint/info',
      'POST /api/sequencer/checkpoint/resume',
      'POST /api/sequencer/checkpoint/discard',
      'POST /api/sequencer/checkpoint/save',
      'POST /api/sequencer/recovery/try-now',
      'POST /api/sequencer/recovery/abort',
      'POST /api/sequencer/recovery/update-config',
      'GET /api/sequencer/recovery/current',
      'GET /api/sequencer/recovery/history',
      'POST /api/sequencer/update-cloud-motion',
      'GET /api/sequencer/cloud-motion',
      'POST /api/sequencer/update-conditions-score',
      'GET /api/sequencer/adaptive-swap',
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
      'POST /api/imaging/calibrate-file',
      'DELETE /api/imaging/device-image/<deviceId>',
      // Polar Alignment
      'POST /api/polar-alignment/start',
      'POST /api/polar-alignment/all-sky/start',
      'POST /api/polar-alignment/stop',
      // Session Images
      'GET /api/sessions/<sessionId>/images',
      'GET /api/images',
      'GET /api/images/recent',
      'GET /api/images/standalone',
      'POST /api/images',
      'GET /api/images/<imageId>',
      'PUT /api/images/<imageId>',
      'GET /api/images/<imageId>/thumbnail',
      // P1-13: thumbnail cache management.
      'POST /api/images/backfill-thumbnails',
      'POST /api/images/<imageId>/regenerate-thumbnail',
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
      'GET /api/sequence-management/list-full',
      'GET /api/sequence-management/templates-full',
      'POST /api/sequence-management/save-full',
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
      'GET /api/mosaic/recommended-exposure',
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
      'GET /api/weather/current',
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
      'POST /api/framing/set-target',
      'POST /api/framing/save',
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
      // P1-2 / P1-3 — Long-running operation jobs
      'GET /api/jobs',
      'GET /api/jobs/<jobId>',
      'POST /api/jobs/<jobId>/cancel',
      'DELETE /api/jobs/<jobId>',
      // P1-5 — Session ownership
      'GET /api/session/owner',
      'GET /api/session/status',
      'POST /api/session/claim',
      'POST /api/session/take-over',
      'POST /api/session/release',
      // P1-11 — System / OTA update endpoints
      'GET /api/system/version',
      'POST /api/system/update/check',
      'GET /api/system/update/status',
      'POST /api/system/update/download',
      'POST /api/system/update/apply',
      'POST /api/system/update/abort',
      'POST /api/system/update/rollback',
      'GET /api/system/update/staged',
      'DELETE /api/system/update/staged',
      // WebSocket
      'WS /api/ws',
      'WS /events',
      // Wave 6 — Run-Watch (phone/tablet monitoring SPA)
      'GET /api/run-watch/snapshot',
      'GET /api/run-watch/frame-thumbnail',
      'GET /api/run-watch/events',
      // P1-14 — Remote log retrieval / tail
      'GET /api/logs',
      'GET /api/logs/recent',
      'GET /api/logs/files/<filename>/download',
      'GET /api/logs/tail',
      'POST /api/logs/clear',
      'POST /api/logs/test-entry',
      // P1-10 — Remote calibration library management
      'GET /api/calibration/darks',
      'POST /api/calibration/darks',
      'POST /api/calibration/darks/upload',
      'POST /api/calibration/darks/find-match',
      'POST /api/calibration/darks/backfill-sizes',
      'GET /api/calibration/darks/<id>',
      'GET /api/calibration/darks/<id>/download',
      'DELETE /api/calibration/darks/<id>',
      'GET /api/calibration/flats',
      'POST /api/calibration/flats',
      'GET /api/calibration/flats/recommendation',
      'GET /api/calibration/flats/<id>',
      'DELETE /api/calibration/flats/<id>',
      'GET /api/calibration/defect-maps',
      'POST /api/calibration/defect-maps',
      'GET /api/calibration/defect-maps/<id>',
      'DELETE /api/calibration/defect-maps/<id>',
      'POST /api/calibration/defect-maps/<id>/regenerate',
      // P1-12 — Catalog management (download / upload / verify / etc.)
      'GET /api/catalog/status',
      'GET /api/catalog/available',
      'POST /api/catalog/download',
      'POST /api/catalog/upload',
      'POST /api/catalog/verify',
      'POST /api/catalog/reload',
      'DELETE /api/catalog/<name>',

      // P2-8 — Read-only DB endpoints (paginated)
      'GET /api/sequence-runs',
      'GET /api/notes-journal',
      'GET /api/guide-rms-history',
      'GET /api/polar-alignment-history',
      'GET /api/db/dark-library',
      'GET /api/db/flat-history',

      // P2-11 — Plugin management
      'GET /api/plugins',
      'POST /api/plugins/upload',
      'POST /api/plugins/<pluginId>/enable',
      'POST /api/plugins/<pluginId>/disable',
      'DELETE /api/plugins/<pluginId>',
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
          'dashboardAvailable': _staticFileHandlers.dashboardAvailable,
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

  // /api/collaboration/* and /api/session-handoff handlers were moved to
  // [CollaborationHandlers] (handlers/collaboration_handlers.dart). The
  // shared LiveCollaborationSessionManager is injected so the WS upgrade
  // path, the desktop GUI, and the HTTP surface still observe the same
  // in-memory state.

  // ===========================================================================
  // Pairing flow (§2.1) — first-run dashboard onboarding.
  //
  // The desktop console prints the 6-digit code; the dashboard user retypes it
  // into the Pair sheet. Verifying the code mints a long-lived bearer token
  // that the dashboard then uses for all authenticated calls. The code itself
  // is never returned in the HTTP response body so a network observer (or a
  // logging proxy) cannot harvest it without console access.
  // ===========================================================================

  /// Returns the [PairingService], lazily constructing one on first use.
  /// Why lazy: the constructor cannot await a [PairingDatabase] open, but the
  /// service must outlive a single request. We create it on demand and reuse
  /// the same instance for the rest of the server lifetime.
  PairingService _ensurePairingService() {
    final existing = _pairingService;
    if (existing != null) return existing;
    final created = PairingService();
    _pairingService = created;
    // P0-10: ensure the revocation listener is wired even when the service
    // was lazy-constructed (i.e. the headless operator never explicitly
    // injected one but a verify call just created it). The startup
    // [_installRevocationListener] no-ops when no service exists; this is
    // the symmetric hook for the late-binding case.
    created.tokenManager.setRevocationListener(_evictPairedSessionToken);
    return created;
  }

  Future<Response> _handlePairingStart(Request request) async {
    final requestId = _requestIdFrom(request);
    final clientKey = _rateLimitClientKey(request);

    final lockedFor = _pairingAttempts.retryAfter(clientKey);
    if (lockedFor != null) {
      _logWarning(
        '[PAIR][$requestId] start rate-limited from $clientKey '
        'retry=${lockedFor.inSeconds}s',
      );
      return jsonRateLimited(
        {
          'error': 'Pairing attempts temporarily locked',
          'retryAfterSeconds':
              lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds,
          'requestId': requestId,
        },
        headers: {
          _requestIdHeader: requestId,
          'retry-after':
              (lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds).toString(),
        },
      );
    }

    final service = _ensurePairingService();
    final result = await service.startPairing();

    // The code itself goes only to the operator's stdout/log so an off-host
    // attacker cannot harvest it from HTTP traces. The dashboard polls for
    // success on /api/pairing/verify with the user-typed code.
    _logInfo(
      '[PAIR][$requestId] Pairing started; enter this code on the companion '
      'within ${service.codeLifetime.inMinutes} minutes: ${result.code}',
    );

    // P0-3: when the headless operator passed --pairing-print-codes (or set
    // NIGHTSHADE_PAIRING_PRINT_CODES=true), echo the code to stdout. Without
    // this, a Pi-headless first-run has no way to retrieve the code — the
    // HTTP response intentionally omits it and the structured log file is
    // not always tailed. Operators must opt in to this print so accidental
    // log capture in a CI/recording context does not leak the code.
    if (pairingPrintCodes) {
      print(
        '[PAIRING] code=${result.code} '
        'expires=${result.expiresAt.toUtc().toIso8601String()}',
      );
    }
    return jsonOk(
      {
        'expiresAt': result.expiresAt.toUtc().toIso8601String(),
        'expiresInSeconds':
            result.expiresAt.difference(DateTime.now()).inSeconds,
      },
      headers: {_requestIdHeader: requestId},
    );
  }

  /// P0-3: admin-only view of currently-valid pairing sessions. The full
  /// code is included ONLY when the caller's token has admin scope —
  /// returning it on a control-scope token would let any paired client read
  /// freshly-minted codes that the operator might be sharing out-of-band.
  /// Returns: `{ sessions: [{code?, expiresAt, expiresInSeconds, deviceId?}] }`.
  ///
  /// Code redaction: when called without admin scope this endpoint is
  /// rejected by the auth middleware (it lives behind the
  /// `_adminOnlyPaths` table). The handler itself does not need a
  /// secondary scope check.
  Future<Response> _handlePairingActiveList(Request request) async {
    final requestId = _requestIdFrom(request);
    try {
      final service = _ensurePairingService();
      // Query the underlying Drift DB directly — TokenManager has no need to
      // expose unused pairing sessions because the only consumer is this
      // admin-facing diagnostic. Walking the DB rather than caching in
      // memory keeps the source of truth in one place.
      final allSessions = await service.database
          .select(service.database.pairingSessions)
          .get();
      final now = DateTime.now();
      final sessions = <Map<String, Object?>>[];
      for (final row in allSessions) {
        if (row.isUsed) continue;
        if (!row.expiresAt.isAfter(now)) continue;
        sessions.add({
          'code': row.pairingCode,
          'expiresAt': row.expiresAt.toUtc().toIso8601String(),
          'expiresInSeconds': row.expiresAt.difference(now).inSeconds,
        });
      }
      return jsonOk(
        {'sessions': sessions},
        headers: {_requestIdHeader: requestId},
      );
    } catch (e) {
      _logError('[PAIR][$requestId] Failed to list active sessions: $e');
      return jsonInternalServerError(
        {'error': 'Failed to list active pairing sessions: $e'},
        headers: {_requestIdHeader: requestId},
      );
    }
  }

  Future<Response> _handlePairingVerify(Request request) async {
    final requestId = _requestIdFrom(request);
    final clientKey = _rateLimitClientKey(request);

    final lockedFor = _pairingAttempts.retryAfter(clientKey);
    if (lockedFor != null) {
      _logWarning(
        '[PAIR][$requestId] verify rate-limited from $clientKey '
        'retry=${lockedFor.inSeconds}s',
      );
      return jsonRateLimited(
        {
          'error': 'Pairing attempts temporarily locked',
          'retryAfterSeconds':
              lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds,
          'requestId': requestId,
        },
        headers: {
          _requestIdHeader: requestId,
          'retry-after':
              (lockedFor.inSeconds < 1 ? 1 : lockedFor.inSeconds).toString(),
        },
      );
    }

    final payload = await readJsonObject(request);
    final code = requireString(payload, 'code', maxLength: 32);
    // deviceId/deviceName/deviceType identify the dashboard instance for the
    // PairingDatabase. Defaults are conservative so a minimal browser client
    // can pair without sending hardware fingerprints.
    final deviceId = optionalString(payload, 'deviceId', maxLength: 128) ??
        'dashboard:${clientKey.replaceAll(':', '_')}';
    final deviceName =
        optionalString(payload, 'deviceName', maxLength: 128) ?? 'Dashboard';
    final deviceType =
        optionalString(payload, 'deviceType', maxLength: 32) ?? 'browser';
    final requestedScopeRaw =
        optionalString(payload, 'requestedScope', maxLength: 16) ?? 'control';
    final requestedScope = parseHeadlessTokenScope(requestedScopeRaw);

    final service = _ensurePairingService();
    final result = await service.verifyPairing(
      code: code,
      deviceId: deviceId,
      deviceName: deviceName,
      deviceType: deviceType,
    );

    switch (result.outcome) {
      case PairingVerifyOutcome.success:
        final token = result.sessionToken!;
        // Default to control (imaging + devices). Admin is opt-in only via
        // requestedScope=admin so a scanned QR or LAN pairing cannot silently
        // gain backup/filesystem privileges.
        final grantedScope = requestedScope == HeadlessTokenScope.admin
            ? HeadlessTokenScope.admin
            : HeadlessTokenScope.control;
        _pairedSessionTokens[token] = grantedScope;
        _pairingAttempts.clear(clientKey);
        _logInfo(
          '[PAIR][$requestId] Pairing succeeded for device=$deviceId '
          'scope=${headlessTokenScopeName(grantedScope)}',
        );
        return jsonOk(
          {
            'token': token,
            'tokenScope': headlessTokenScopeName(grantedScope),
            'expiresAt': result.expiresAt!.toUtc().toIso8601String(),
          },
          headers: {_requestIdHeader: requestId},
        );
      case PairingVerifyOutcome.invalidCode:
        _pairingAttempts.recordFailure(clientKey);
        _logWarning(
          '[PAIR][$requestId] Invalid pairing code from $clientKey',
        );
        return jsonUnauthorized(
          {
            'error': 'invalid_pairing_code',
            'message': 'The pairing code is not recognised.',
            'requestId': requestId,
          },
          headers: {_requestIdHeader: requestId},
        );
      case PairingVerifyOutcome.codeExpired:
        _pairingAttempts.recordFailure(clientKey);
        _logWarning(
          '[PAIR][$requestId] Expired pairing code from $clientKey',
        );
        return jsonUnauthorized(
          {
            'error': 'pairing_code_expired',
            'message':
                'The pairing code has expired. Request a new one from the desktop console.',
            'requestId': requestId,
          },
          headers: {_requestIdHeader: requestId},
        );
      case PairingVerifyOutcome.codeAlreadyUsed:
        _pairingAttempts.recordFailure(clientKey);
        _logWarning(
          '[PAIR][$requestId] Reused pairing code from $clientKey',
        );
        return jsonUnauthorized(
          {
            'error': 'pairing_code_already_used',
            'message':
                'The pairing code has already been claimed. Request a new one.',
            'requestId': requestId,
          },
          headers: {_requestIdHeader: requestId},
        );
    }
  }

  // ===========================================================================
  // WebSocket auth ticket (§2.28) — single-use ticket so browsers do not have
  // to leak the bearer token via WS query parameters into HTTP/proxy logs.
  // ===========================================================================
  Future<Response> _handleWsTicketIssue(Request request) async {
    final requestId = _requestIdFrom(request);
    // Auth middleware has already verified the bearer token before we get
    // here (the route is not public). We just mint a one-shot ticket the
    // caller can present on the WS upgrade.
    //
    // P2-15: bind the ticket to the auth identity that minted it so the
    // upgrade handler can identify the connection without trusting the
    // client-supplied viewerId. The middleware stashes the digest on
    // the request context; we pass it straight to the ticket manager.
    final identity = _authIdentityFrom(request);
    final ticket = _wsTicketManager.issue(identity: identity);
    return jsonOk(
      {
        'ticket': ticket,
        'expiresInSeconds': _wsTicketManager.ticketLifetime.inSeconds,
      },
      headers: {_requestIdHeader: requestId},
    );
  }

  /// Issue an HttpOnly session cookie + CSRF token for the dashboard
  /// "remember me" path (§2.5 long-form). The caller must already be
  /// authenticated via the Authorization header — we explicitly require the
  /// bearer (not the cookie) so the caller proves possession of the raw
  /// token before we let the browser commit to JS-invisible storage.
  ///
  /// Response shape: `{ "csrfToken": "...", "expiresInSeconds": N }`.
  /// The cookie value is NEVER returned in the body — only in `Set-Cookie` —
  /// so a logging proxy or JS that scrapes responses cannot read it.
  Future<Response> _handleAuthCookieIssue(Request request) async {
    final requestId = _requestIdFrom(request);
    final authHeader = request.headers['authorization'];
    // Why re-check the header here even though auth middleware already
    // accepted the request: the middleware may have accepted a cookie path.
    // For *upgrading* to a cookie, only the raw bearer is acceptable —
    // otherwise a stolen cookie could mint a fresh cookie for itself.
    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      _logWarning(
        '[AUTH][$requestId] Cookie issue rejected: bearer token required (no cookie escalation).',
      );
      return jsonUnauthorized(
        {
          'error': 'bearer_required',
          'message':
              'POST /api/auth/cookie requires an Authorization: Bearer <token> header.',
        },
        headers: {_requestIdHeader: requestId},
      );
    }
    final bearer = authHeader.substring(7);
    final scope = _scopeForToken(bearer);
    if (scope == null) {
      // Should not reach here because middleware would have rejected, but
      // defend in depth so a future middleware reorder cannot mint cookies
      // for unrecognised tokens.
      _logWarning(
        '[AUTH][$requestId] Cookie issue rejected: bearer token did not resolve to a scope.',
      );
      return jsonForbidden(
        {
          'error': 'invalid_token',
          'message': 'The bearer token is not recognised.',
        },
        headers: {_requestIdHeader: requestId},
      );
    }
    final issue = _authCookieManager.mint(bearer);
    final secure = !_isPlainLoopbackRequest(request);
    final setCookie = AuthCookieManager.buildSetCookieHeader(
      cookieToken: issue.cookieToken,
      maxAge: issue.maxAge,
      secure: secure,
    );
    return jsonOk(
      {
        'csrfToken': issue.csrfToken,
        'expiresInSeconds': issue.maxAge.inSeconds,
      },
      headers: {
        _requestIdHeader: requestId,
        'set-cookie': setCookie,
      },
    );
  }

  /// Fetch the CSRF token bound to the caller's session cookie. The
  /// dashboard calls this on page load when it detects a session cookie has
  /// been sent (since the cookie itself is HttpOnly the SPA cannot read it
  /// directly, but the browser will attach it to this request and we look
  /// it up on the server side).
  Future<Response> _handleAuthCsrfFetch(Request request) async {
    final requestId = _requestIdFrom(request);
    final cookieHeader = request.headers['cookie'];
    final sessionCookie = AuthCookieManager.extractCookie(cookieHeader);
    final csrf = _authCookieManager.fetchCsrf(sessionCookie);
    if (csrf == null) {
      return jsonUnauthorized(
        {
          'error': 'no_session',
          'message':
              'No active session cookie. Pair this browser, then POST /api/auth/cookie.',
        },
        headers: {_requestIdHeader: requestId},
      );
    }
    return jsonOk(
      {
        'csrfToken': csrf,
        'expiresInSeconds': AuthCookieManager.csrfLifetime.inSeconds,
      },
      headers: {_requestIdHeader: requestId},
    );
  }

  /// Revoke the caller's session cookie (logout). Clears the cookie on the
  /// browser AND drops the server-side session so a copied cookie value
  /// cannot be reused after logout.
  Future<Response> _handleAuthLogout(Request request) async {
    final requestId = _requestIdFrom(request);
    final cookieHeader = request.headers['cookie'];
    final sessionCookie = AuthCookieManager.extractCookie(cookieHeader);
    _authCookieManager.revoke(sessionCookie);
    final secure = !_isPlainLoopbackRequest(request);
    return jsonOk(
      {'loggedOut': true},
      headers: {
        _requestIdHeader: requestId,
        'set-cookie': AuthCookieManager.buildClearCookieHeader(secure: secure),
      },
    );
  }

  /// Whether [method] mutates state and therefore requires CSRF when the
  /// caller is using a cookie. Why uppercase compare: shelf passes the
  /// raw method but middleware may have lowercased it elsewhere — be
  /// defensive.
  static bool _methodNeedsCsrf(String method) {
    final upper = method.toUpperCase();
    return upper == 'POST' ||
        upper == 'PUT' ||
        upper == 'DELETE' ||
        upper == 'PATCH';
  }

  /// Whether this request landed on a plain-HTTP loopback bind. The cookie
  /// MUST carry `Secure` over the public LAN — but a browser refuses to set
  /// a `Secure` cookie on a plain `http://127.0.0.1` test rig, so we relax
  /// the attribute when (and only when) the request was served over HTTP to
  /// loopback. Any non-loopback or HTTPS request still gets `Secure`.
  bool _isPlainLoopbackRequest(Request request) {
    if (request.requestedUri.scheme == 'https') {
      return false;
    }
    final host = request.requestedUri.host;
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  // /api/devices/*, /api/devices/discover-indi, /api/devices/discover-alpaca,
  // and /api/devices/connected were moved to
  // [DeviceDiscoveryHandlers] (handlers/device_discovery_handlers.dart) so the
  // headless server class is not the home of read-only discovery logic.
  //
  // /api/devices/connect and /api/devices/disconnect were moved to
  // [DeviceHandlers.handleConnectDevice] / [DeviceHandlers.handleDisconnectDevice]
  // under audit DEV-P0-2. The previous in-line implementations bypassed
  // `DeviceService.connect<Type>`, skipping the per-device-type connect
  // flow (StateNotifier updates, temperature polling, cool-on-connect,
  // recommended-gain auto-apply, filter-name sync, heartbeat monitoring).

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

  /// Upgrade wrapper that captures the query parameters off the original
  /// request before shelf_web_socket strips them. The replay logic lives
  /// here so it runs BEFORE the socket is added to [_sockets] and starts
  /// receiving live events (otherwise replay vs live would interleave).
  void _handleWebSocketWithQuery(
    WebSocketChannel socket,
    Map<String, String> query,
    String? authIdentity,
  ) {
    _socketAuthIdentities[socket] = authIdentity;
    // P1-1: replay on reconnect. Accept `?since=<int>&instance=<uuid>`. If
    // both are valid AND the instance matches AND the seq is within the
    // ring buffer's covered range, replay the missed events BEFORE
    // attaching the live broadcast stream. Otherwise send a
    // `resync_required` advisory so the client can decide how to recover.
    final sinceStr = query['since'];
    final instance = query['instance'];
    if (sinceStr != null && sinceStr.isNotEmpty) {
      final since = int.tryParse(sinceStr);
      if (since == null) {
        // Malformed since= — treat as a fresh subscribe to avoid leaking
        // information about the seq cursor; log a warning.
        _logWarning(
          'WS upgrade with malformed ?since=$sinceStr; '
          'falling back to live-only subscription',
        );
      } else if (instance != null && instance != _serverInstanceId) {
        _sendResyncRequired(socket, reason: 'instance_changed');
      } else {
        final replay = _eventReplayBuffer.eventsSince(since);
        if (replay == null) {
          _sendResyncRequired(socket, reason: 'missed_too_many');
        } else {
          for (final ev in replay) {
            final encoded = _encodeStampedEventForWire(ev, replay: true);
            if (encoded == null) continue;
            try {
              socket.sink.add(encoded);
            } catch (e) {
              _logWarning('Error replaying event to socket: $e');
              break;
            }
          }
        }
      }
    }

    _handleWebSocket(socket, null);
  }

  /// Send the `resync_required` advisory frame and let the client decide
  /// (call snapshot, drop cached state, etc.). The socket is NOT closed;
  /// the live stream continues so the client can keep receiving fresh
  /// events while it rehydrates.
  void _sendResyncRequired(
    WebSocketChannel socket, {
    required String reason,
  }) {
    try {
      socket.sink.add(jsonEncode({
        'type': 'resync_required',
        'reason': reason,
        'currentSeq': _eventSeq,
        'currentInstance': _serverInstanceId,
        if (_eventReplayBuffer.oldestSeq != null)
          'oldestRetainedSeq': _eventReplayBuffer.oldestSeq,
      }));
    } catch (e) {
      _logWarning('Error sending resync_required to socket: $e');
    }
  }

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
        } on Object catch (e) {
          // Why: malformed inbound socket frame must not tear down the socket
          // listener — the remote client may recover on the next frame. We
          // log the parse error so a flood of malformed frames is visible in
          // diagnostics; we deliberately do NOT close the socket here because
          // that's `onError`'s job.
          _logWarning('WebSocket inbound frame parse failed: $e');
        }
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
    _socketAuthIdentities.remove(socket);
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
    // P2-15: the authoritative viewer identity for THIS socket is the
    // digest of the bearer token that authenticated the upgrade. When
    // the socket has no auth identity (auth disabled, or a legacy
    // pre-ticket connection), we fall back to the client-supplied
    // viewerId to keep the existing wire shape working — that is the
    // explicit "auth disabled" path and the operator opted in.
    final authIdentity = _socketAuthIdentities[socket];
    switch (type) {
      case 'collaboration.join':
        final clientViewerId = data['viewerId'] as String?;
        final name = data['name'] as String?;
        if (name == null || name.isEmpty) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message': 'collaboration.join requires a name',
          }));
          return;
        }
        // Resolve the actual viewer id. The auth identity wins
        // whenever it is available; any mismatching client value is
        // logged at WARNING (potential impersonation attempt) but does
        // NOT fail the join — the server simply substitutes the real
        // identity so legitimate clients that pre-date this gate keep
        // working unchanged.
        final effectiveViewerId = authIdentity ?? clientViewerId;
        if (effectiveViewerId == null || effectiveViewerId.isEmpty) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message':
                'collaboration.join requires viewerId when auth is disabled',
          }));
          return;
        }
        if (authIdentity != null &&
            clientViewerId != null &&
            clientViewerId.isNotEmpty &&
            clientViewerId != authIdentity) {
          _logWarning(
            '[COLLAB] Socket attempted to claim viewerId=$clientViewerId '
            'but authenticated as ${_redactBearer(authIdentity)}; '
            'substituting authenticated identity.',
            fields: {
              'attemptedViewerId': clientViewerId,
              'authenticatedViewerId': authIdentity,
              'event': 'collaboration_join_impersonation_attempt',
            },
          );
        }
        _socketViewerIds[socket] = effectiveViewerId;
        _collaborationManager.upsertViewer(effectiveViewerId, name);
        return;
      case 'collaboration.leave':
        // P2-15: the client cannot remove a viewer slot it does not
        // own. We always use the socket's authoritative identity (or
        // the id this socket previously bound to) regardless of what
        // the payload says.
        final viewerId = _socketViewerIds.remove(socket) ??
            authIdentity ??
            (data['viewerId'] as String?);
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
        final clientViewerId = data['viewerId'] as String?;
        final viewerName = data['viewerName'] as String?;
        final message = data['message'] as String?;
        if (viewerName == null || message == null) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message':
                'collaboration.chat requires viewerName and message',
          }));
          return;
        }
        // P2-15: same impersonation rule as collaboration.join — the
        // authenticated identity, not the client-supplied id, signs the
        // chat row so a client cannot put words in someone else's mouth.
        final viewerId = authIdentity ?? clientViewerId;
        if (viewerId == null) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message': 'collaboration.chat requires viewerId when auth is disabled',
          }));
          return;
        }
        if (authIdentity != null &&
            clientViewerId != null &&
            clientViewerId.isNotEmpty &&
            clientViewerId != authIdentity) {
          _logWarning(
            '[COLLAB] Chat impersonation attempt from socket '
            '(claimed=$clientViewerId actual=${_redactBearer(authIdentity)}); '
            'substituting authenticated identity.',
          );
        }
        _collaborationManager.addChat(
          viewerId: viewerId,
          viewerName: viewerName,
          message: message,
        );
        return;
      case 'collaboration.annotation':
        final annotationId = data['annotationId'] as String?;
        final clientViewerId = data['viewerId'] as String?;
        final kind = data['kind'] as String?;
        final payload = data['payload'];
        if (annotationId == null ||
            kind == null ||
            payload is! Map<String, dynamic>) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message':
                'collaboration.annotation requires annotationId, kind, and payload',
          }));
          return;
        }
        final viewerId = authIdentity ?? clientViewerId;
        if (viewerId == null) {
          socket.sink.add(jsonEncode({
            'type': 'error',
            'message':
                'collaboration.annotation requires viewerId when auth is disabled',
          }));
          return;
        }
        if (authIdentity != null &&
            clientViewerId != null &&
            clientViewerId.isNotEmpty &&
            clientViewerId != authIdentity) {
          _logWarning(
            '[COLLAB] Annotation impersonation attempt from socket '
            '(claimed=$clientViewerId actual=${_redactBearer(authIdentity)}); '
            'substituting authenticated identity.',
          );
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

  // Dashboard + Run-Watch static-file serving was moved to
  // [StaticFileHandlers] (handlers/static_file_handlers.dart). The handlers
  // there own the SPA-directory resolution, the MIME-type table, the CSP
  // security headers, and the symlink-traversal guard. Inline `_handleInfo`
  // / `_handleSelfTest` now read the dashboard-available flag via
  // `_staticFileHandlers.dashboardAvailable` so the inline JSON shape is
  // unchanged.

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
          if (path == '/api/ws' || path == '/events') {
            return response;
          }
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
        final path = '/${request.url.path}';
        if (path == '/api/ws' || path == '/events') {
          return response;
        }
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
        if (isWebSocket) {
          return response;
        }
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
        // P2-6: per-token / route-class bucket runs first. It supersedes
        // the endpoint window for authenticated requests because (a) it
        // is keyed by the principal rather than by the public IP (NAT-
        // safe), and (b) its route classes carve a per-token budget that
        // the endpoint window cannot express. The endpoint window stays
        // as a defence-in-depth backstop in case the route-class bucket
        // is somehow bypassed (unauthenticated path that still reaches
        // the rate limiter).
        final identity = _authIdentityFrom(request);
        final routeClass = _authRouteClassFrom(request);
        if (identity != null && routeClass != null) {
          final tokenDecision = _tokenBucketLimiter.tryConsume(
            tokenId: identity,
            routeClass: routeClass,
          );
          if (!tokenDecision.allowed) {
            return _denyRateLimited(
              request: request,
              path: path,
              decision: tokenDecision,
              bucketLabel:
                  route_metadata.tokenRouteClassName(routeClass),
              identity: identity,
            );
          }
        }

        // Defence-in-depth: legacy sliding-window check keyed on IP/
        // path. Triggers for unauthenticated requests (which the auth
        // gate above already mostly rejected) and stays useful for
        // catching pathological per-endpoint bursts even after the
        // token bucket allowed the request.
        final decision = _rateLimiter.check(
          clientKey: _rateLimitClientKey(request),
          method: request.method,
          path: path,
        );
        if (decision.allowed) {
          return null;
        }

        return _denyRateLimited(
          request: request,
          path: path,
          decision: decision,
          bucketLabel: 'endpoint',
          identity: identity,
        );
      },
    );
  }

  /// Build the 429 response shared between the per-token and the legacy
  /// endpoint buckets. Body shape matches the task spec
  /// (`{code: 'rate_limited', message, retryAfterSecs}`) while still
  /// including the legacy `error` / `maxRequests` / `retryAfterSeconds`
  /// keys so existing dashboards (which key off `error`) keep working.
  Response _denyRateLimited({
    required Request request,
    required String path,
    required route_metadata.RateLimitDecision decision,
    required String bucketLabel,
    String? identity,
  }) {
    final requestId = _requestIdFrom(request);
    // Redacted form of the principal for log lines: the digest is itself
    // safe to log (it's not a credential) but it's noisy. We surface
    // only the first eight hex chars in human-readable logs while
    // retaining the full digest in the structured fields so log search
    // can correlate across requests.
    final principalLog = identity == null
        ? 'anonymous'
        : identity.substring(0, identity.length < 8 ? identity.length : 8);
    final principalForBody =
        identity == null ? 'anonymous' : 'token-$principalLog';
    final message =
        'Token $principalForBody exceeded $bucketLabel bucket';
    _logWarning(
      '[RATE][$requestId] ${request.method} $path limited '
      'bucket=$bucketLabel principal=$principalLog '
      'max=${decision.maxRequests} retry=${decision.retryAfterSeconds}s',
      fields: {
        'requestId': requestId,
        'method': request.method,
        'path': path,
        'bucket': bucketLabel,
        'principal': identity,
        'maxRequests': decision.maxRequests,
        'retryAfterSeconds': decision.retryAfterSeconds,
      },
    );
    return jsonRateLimited(
      {
        'code': 'rate_limited',
        'error': 'Rate limit exceeded',
        'message': message,
        'bucket': bucketLabel,
        'maxRequests': decision.maxRequests,
        'retryAfterSecs': decision.retryAfterSeconds,
        'retryAfterSeconds': decision.retryAfterSeconds,
        'requestId': requestId,
      },
      headers: {
        'retry-after': decision.retryAfterSeconds.toString(),
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
      // Why include the CSRF header: cookie-bearing fetches from the
      // dashboard SPA echo the server-issued CSRF token via
      // `X-Nightshade-CSRF`; without it in the allow-list the browser
      // would block the request before our middleware ever ran (§2.5
      // long-form).
      'Access-Control-Allow-Headers':
          'Origin, Content-Type, X-Auth-Token, Authorization, '
              'X-Nightshade-API-Version, X-Request-ID, X-Nightshade-CSRF',
      // Why expose Set-Cookie on the wire but not allow-credentials: the
      // cookie is HttpOnly so the browser stores it without JS seeing it;
      // `credentials: 'include'` on the SPA fetch is what makes the cookie
      // round-trip, and that requires the next header.
      'Access-Control-Allow-Credentials': 'true',
      'Vary': 'Origin',
    };
  }

  String? _resolveAllowedOrigin(Request request, String? origin) {
    // Why delegate: previous behaviour reflected any origin that matched the
    // bound host:port, which let any local-loopback browser app bypass CORS
    // on a different port (§2.27). [CorsAllowList] applies the explicit
    // configured allow-list and an even stricter rule for high-risk control
    // paths; the same-origin escape hatch is preserved so the bundled
    // dashboard continues to work without configuration.
    return _corsAllowList.resolve(
      requestOrigin: origin,
      requestUri: request.requestedUri,
      path: '/${request.url.path}',
    );
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
    // Endpoints that don't require authentication. Pairing endpoints are
    // public because the dashboard has no bearer token until the user
    // completes the first pairing flow; the 6-digit code shown on the
    // desktop console is the out-of-band trust factor (§2.1).
    const publicPaths = {
      '/api/info',
      '/api/pairing/start',
      '/api/pairing/verify',
      // Wave 7 Agent 2: live-stacking broadcast endpoints. The audience
      // at an outreach event has not paired the device; the
      // LiveStackingNode's own `auth_token` field is the access gate
      // (constant-time compared inside BroadcastService.authorize).
      // Adding these paths here bypasses the dashboard's pairing-token
      // middleware so a phone-in-the-audience can fetch them with no
      // bearer token; the broadcast handler does its own auth check.
      '/api/broadcast/info',
      '/api/broadcast/live-stack',
      '/api/broadcast/sse',
      '/broadcast',
    };

    // WebSocket paths that support query-param auth (legacy ?token=) or the
    // single-use ?ticket= flow added in §2.28.
    //
    // P2-10: /ws/live-view participates in the same query-param auth flow
    // because browser/WS clients can't always set custom headers on the
    // upgrade request — the phone passes the bearer token via ?token= and
    // we honour it here.
    const webSocketPaths = {'/api/ws', '/events', '/ws/live-view'};

    return (innerHandler) {
      return (request) {
        // Skip auth if no token is configured
        if (_effectiveAuthTokensByValue.isEmpty &&
            _pairedSessionTokens.isEmpty) {
          return innerHandler(request);
        }

        // Skip auth for public endpoints and dashboard static files
        final requestId = _requestIdFrom(request);
        final path = '/${request.url.path}';
        // /run-watch ships the phone SPA which must load before the user
        // has any token at all. Once the SPA fetches /api/run-watch/* it
        // attaches the bearer token like every other client, so only the
        // bundle itself is auth-exempt.
        if (publicPaths.contains(path) ||
            path.startsWith('/dashboard') ||
            path == '/run-watch' ||
            path.startsWith('/run-watch/')) {
          return innerHandler(request);
        }

        // For WebSocket paths, accept either the legacy ?token=<bearer> (with
        // a deprecation warning) or the §2.28 one-shot ?ticket= which is
        // consumed and invalidated here so it cannot be reused.
        if (webSocketPaths.contains(path)) {
          final queryTicket = request.url.queryParameters['ticket'];
          if (queryTicket != null && queryTicket.isNotEmpty) {
            // P2-15: ws_ticket_manager.consume now returns the digest of
            // the token that was used to mint the ticket, NOT the raw
            // token. That digest IS the authenticated identity for the
            // upcoming WS — stash it on the context so the upgrade
            // handler can bind it to the socket as the canonical viewer
            // id.
            final ticketIdentity = _wsTicketManager.consume(queryTicket);
            if (ticketIdentity != null) {
              return innerHandler(_attachAuthIdentity(
                request,
                identity: ticketIdentity,
                routeClass: route_metadata.tokenRouteClassFor(
                  method: request.method,
                  path: path,
                ),
              ));
            }
            // Bad/expired ticket — do NOT fall through to legacy token to
            // avoid masking a stolen-ticket replay attempt with a successful
            // bearer-token outcome. Reject explicitly.
            _logWarning(
              '[AUTH][$requestId] Rejected WS upgrade to $path - invalid or expired ticket',
            );
            return jsonUnauthorized(
              {
                'error': 'Authentication required',
                'message': 'Invalid or expired WebSocket ticket',
              },
              headers: {_requestIdHeader: requestId},
            );
          }

          final queryToken = request.url.queryParameters['token'];
          if (queryToken != null && queryToken.isNotEmpty) {
            final queryScope = _scopeForToken(queryToken);
            if (queryScope != null &&
                HeadlessAuthPolicy.allows(
                  actual: queryScope,
                  method: 'WS',
                  path: path,
                )) {
              _logWarning(
                '[AUTH][$requestId] WS upgrade to $path used legacy ?token=. '
                'Switch to POST /api/ws/ticket + ?ticket= (audit §2.28).',
              );
              return innerHandler(_attachAuthIdentity(
                request,
                identity: computeServerFingerprint(queryToken),
                routeClass: route_metadata.tokenRouteClassFor(
                  method: request.method,
                  path: path,
                ),
              ));
            }
          }
          // Fall through to check Authorization header below.
        }

        // Resolve credentials. Acceptable forms:
        //  1. `Authorization: Bearer <token>` header (mobile clients, API
        //     consumers, the dashboard's pre-cookie path).
        //  2. The §2.5 long-form `nightshade_session` HttpOnly cookie set by
        //     `POST /api/auth/cookie` after a successful pairing. Cookie
        //     requests additionally require a matching CSRF token on every
        //     state-changing method.
        //  3. `?access_token=<bearer>` query parameter, but ONLY for the
        //     Wave 6 SSE endpoint. Why: browser EventSource cannot set
        //     custom headers and the SSE handler is GET-only / read-only,
        //     so a one-shot URL token is the only viable auth carrier
        //     for the phone client. This is gated to /api/run-watch/events
        //     so general endpoints still require the header form.
        //
        // We resolve the cookie BEFORE the Authorization header so a single
        // dashboard tab that has both (e.g. mid-migration) still gets the
        // CSRF check applied. If both are present the Authorization header
        // takes precedence (it is the active session the browser opted into
        // for this request).
        final authHeader = request.headers['authorization'];
        final cookieHeader = request.headers['cookie'];
        final sessionCookie = AuthCookieManager.extractCookie(cookieHeader);
        String? token;
        bool tokenFromCookie = false;
        // Wave 6 — accept ?access_token= on the SSE endpoint only.
        // P1-14 extends this to the /api/logs/tail SSE endpoint for the
        // same reason: browser EventSource cannot set custom headers,
        // so a one-shot query-param bearer is the only viable carrier
        // for the phone client. Both endpoints are GET-only and
        // read-only so a leaked URL token (e.g. via a screenshot) has
        // bounded blast radius.
        if (path == '/api/run-watch/events' || path == '/api/logs/tail') {
          final qToken = request.url.queryParameters['access_token'];
          if (qToken != null && qToken.isNotEmpty) {
            token = qToken;
          }
        }
        if (token == null && authHeader != null) {
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
          token = authHeader.substring(7); // Remove 'Bearer ' prefix
        }
        if (token == null && sessionCookie != null) {
          final cookieBearer = _authCookieManager.resolveBearer(sessionCookie);
          if (cookieBearer != null) {
            token = cookieBearer;
            tokenFromCookie = true;
          }
        }

        if (token == null) {
          _logWarning(
              '[AUTH][$requestId] Rejected request to $path - no Authorization header or session cookie');
          return jsonUnauthorized(
            {
              'error': 'Authentication required',
              'message': 'Missing Authorization header or session cookie',
            },
            headers: {
              _requestIdHeader: requestId,
            },
          );
        }

        // CSRF gate for cookie-authenticated requests. Why only when the
        // token came from the cookie: bearer-header requests are not
        // ambient-credentialed by the browser, so a cross-origin attacker
        // cannot get the header attached automatically. Cookie requests,
        // however, are sent on every same-site fetch — the CSRF token
        // (in-memory in JS, mirrored to a request header) is what proves
        // the request actually originated from the dashboard SPA.
        //
        // GET/HEAD/OPTIONS are excluded because CSRF protects state
        // changes; read-only responses do not need it (and pre-flighting
        // every GET would break image/event endpoints).
        if (tokenFromCookie && _methodNeedsCsrf(request.method)) {
          final presented =
              request.headers[AuthCookieManager.csrfHeader.toLowerCase()];
          if (!_authCookieManager.validateCsrf(
            cookieToken: sessionCookie,
            presented: presented,
          )) {
            _logWarning(
              '[AUTH][$requestId] Rejected cookie request to $path - missing or invalid CSRF token',
            );
            return jsonForbidden(
              {
                'error': 'csrf_required',
                'message':
                    'A valid ${AuthCookieManager.csrfHeader} header is required for this method.',
              },
              headers: {_requestIdHeader: requestId},
            );
          }
        }

        final clientKey = _rateLimitClientKey(request);
        // Why pre-check: the constant-time loop is O(N*L) over the token
        // table; an attacker spamming bad tokens could make it a CPU-burn
        // vector (§2.22). The resolver tracks per-client failure counts and
        // we shed load with 429 once the bucket fills.
        if (_tokenResolver.isRateLimited(clientKey)) {
          _logWarning(
            '[AUTH][$requestId] Rate-limited token comparisons from $clientKey on $path',
          );
          return jsonRateLimited(
            {
              'error': 'Rate limit exceeded',
              'message': 'Too many authentication failures',
              'requestId': requestId,
            },
            headers: {
              _requestIdHeader: requestId,
              'retry-after': '60',
            },
          );
        }
        final tokenScope = _scopeForToken(token);
        if (tokenScope == null) {
          _tokenResolver.recordFailure(clientKey);
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
        // Token recognised — clear stale failures so a successful login
        // resets the counter for that client.
        _tokenResolver.clearFailures(clientKey);

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

        // Token is valid, continue to handler. Stash the digest of the
        // resolved token + the request's route class so the rate-limit
        // middleware (and any handler that wants to log the principal
        // without a re-resolution) can read it back. We MUST NOT pass
        // the raw token through the context — see [_authIdentityContextKey].
        return innerHandler(_attachAuthIdentity(
          request,
          identity: computeServerFingerprint(token),
          routeClass: route_metadata.tokenRouteClassFor(
            method: request.method,
            path: path,
          ),
        ));
      };
    };
  }

  /// P2-6 / P2-15: stash the authenticated principal's digest + the
  /// classified route class on the shelf request context so downstream
  /// middleware (rate limit) and the WS upgrade handler can bind to them.
  ///
  /// The raw bearer is NEVER placed on the context — only its SHA-256
  /// digest via `computeServerFingerprint`, which is the same value the
  /// session-ownership manager uses to identify owners and what every
  /// other code path digests to.
  Request _attachAuthIdentity(
    Request request, {
    required String identity,
    required route_metadata.TokenRouteClass routeClass,
  }) {
    return request.change(context: {
      _authIdentityContextKey: identity,
      _authRouteClassContextKey: routeClass,
    });
  }

  /// Read the authenticated principal digest off the request context.
  /// Returns null when the auth middleware didn't run (e.g. test fixtures
  /// with no token configured), in which case the rate limiter falls back
  /// to the IP-based key.
  String? _authIdentityFrom(Request request) {
    final value = request.context[_authIdentityContextKey];
    return value is String ? value : null;
  }

  route_metadata.TokenRouteClass? _authRouteClassFrom(Request request) {
    final value = request.context[_authRouteClassContextKey];
    return value is route_metadata.TokenRouteClass ? value : null;
  }

  /// P1-5: extract the raw bearer token (or cookie-backed session token)
  /// from [request]. The auth middleware has already validated whatever
  /// we resolve here; we re-extract because the validated value is not
  /// currently propagated into the request context.
  ///
  /// Returns null when no token is present — callers must treat that as
  /// an unauthenticated request even though the auth middleware should
  /// have rejected it first.
  String? _extractBearerToken(Request request) {
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      return authHeader.substring(7);
    }
    final cookieHeader = request.headers['cookie'];
    final sessionCookie = AuthCookieManager.extractCookie(cookieHeader);
    if (sessionCookie != null) {
      final cookieBearer = _authCookieManager.resolveBearer(sessionCookie);
      if (cookieBearer != null) {
        return cookieBearer;
      }
    }
    return null;
  }

  /// P1-5: gate destructive POSTs on the operator slot. Read-only and
  /// status endpoints fall through unchanged. The middleware also
  /// refreshes the owner's heartbeat on every authenticated mutating
  /// request so a phone polling the rig stays the owner without an
  /// explicit WS frame.
  Middleware _sessionOwnershipMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        final path = '/${request.url.path}';
        if (!isOwnershipRequired(method: request.method, path: path)) {
          return null;
        }
        // Reaching this branch means: (a) an authenticated request, (b)
        // a mutating verb, (c) a path on the destructive allow-list. If
        // there is no owner yet, the slot is unclaimed and every
        // control-scope client falls back to the legacy "first-come,
        // first-served" semantics — we do NOT block when nobody has
        // claimed the rig, because the dashboard's initial pairing flow
        // (which has not yet POSTed /api/session/claim) must still be
        // able to drive the gear.
        final owner = _sessionOwnership.current;
        if (owner == null) {
          return null;
        }
        final token = _extractBearerToken(request);
        if (token == null) {
          // Auth middleware should have caught this; defensive.
          return jsonForbidden({
            'error': 'auth_required',
            'message':
                'Session-ownership-gated endpoints require a bearer token.',
          });
        }
        if (!_sessionOwnership.isOwner(token)) {
          return jsonConflict({
            'error': 'not_session_owner',
            'message':
                'Another client is the operator. POST /api/session/take-over '
                    'with a reason to displace them.',
            'currentOwner': owner.toJson(),
            'retryWithTakeOver': true,
          });
        }
        // Heartbeat refresh so an actively-driving client never auto-
        // releases under the 5-minute idle timeout.
        _sessionOwnership.touchHeartbeat(token);
        return null;
      },
    );
  }

  HeadlessTokenScope? _scopeForToken(String? token) {
    if (token == null || token.isEmpty) {
      return null;
    }
    // Why constant-time + full-iteration: a naive Map[token] short-circuits on
    // hash mismatch, leaking per-character timing of the bearer token to a
    // network attacker (§2.22). The resolver iterates the entire map and uses
    // XOR-based comparison so timing is independent of which entry matches.
    final scope = _tokenResolver.resolve(token);
    if (scope != null) {
      return scope;
    }
    // Paired-session tokens live outside the immutable static map (Drift-
    // backed). Mirror the same constant-time iteration here so the choice
    // between "static config token" and "paired token" is not observable.
    HeadlessTokenScope? pairedMatch;
    for (final entry in _pairedSessionTokens.entries) {
      if (constantTimeCompareStrings(entry.key, token)) {
        pairedMatch = entry.value;
      }
    }
    return pairedMatch;
  }

  /// Generates a cryptographically secure random token.
  static String _generateRandomToken({int length = 32}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(length, (_) => chars[random.nextInt(chars.length)])
        .join();
  }

  /// P1-1: inline UUID v4 generator used for the server-instance id. We
  /// deliberately avoid `package:uuid` so the server has no extra
  /// dependency for this single call site. RFC 4122 §4.4.
  static String _generateUuidV4() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int n) => n.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-'
        '${h.substring(20)}';
  }

  /// Redact a bearer/auth token for structured-log output. Shows the first
  /// 4 + last 4 chars and masks the middle, so log readers can correlate
  /// a token across log lines without exposing the secret in plaintext.
  /// Delegates to [ctx.redactBearer] so the same redaction rule applies
  /// across the server, every extracted handler class, and the audit
  /// surfaces.
  static String _redactBearer(String token) => ctx.redactBearer(token);

  /// Get the current authentication token (for logging/debugging).
  /// Returns null if authentication is disabled.
  String? get effectiveAuthToken => _effectiveAuthToken;

  /// The bound HTTP port. Useful when the server was started with port 0.
  int get actualPort => _server?.port ?? port;

  /// The same SHA-256 hex digest the server surfaces from `GET /api/info`.
  ///
  /// Either the TLS SubjectPublicKeyInfo digest when TLS is active or the
  /// `computeServerFingerprint`-derived token digest otherwise. Exposed so
  /// the mDNS advertiser (P1-6) can publish the value as a TXT record,
  /// keeping the QR `fingerprint`, the `/api/info` `fingerprint`, and the
  /// mDNS `fingerprint` aligned.
  String get serverFingerprint => _serverFingerprint;

  /// `true` when the server is bound with a TLS context. The mDNS `scheme`
  /// TXT record (P1-6) reads this so the advertised transport matches reality.
  bool get isTlsActive => tlsContext != null;

  /// P1-1: random UUID identifying this server instance. Returned by
  /// /api/info and stamped on every outbound event.
  String get serverInstanceId => _serverInstanceId;

  /// P1-1: current monotonic event sequence counter. 0 before any event
  /// has been broadcast.
  int get currentEventSeq => _eventSeq;

  /// P1-1: oldest event seq retained in the replay buffer, or null when
  /// no events have been emitted yet.
  int? get eventReplayBufferOldestSeq => _eventReplayBuffer.oldestSeq;

  /// P1-4: command correlator owned by this server. Handlers call
  /// [CommandCorrelator.beginCommand] before kicking off an action so the
  /// response can include the commandId and later events get tagged.
  CommandCorrelator get commandCorrelator => _commandCorrelator;

  /// P1-2 / P1-3: in-memory job manager. Exposed so the GUI / tests can
  /// drive it directly without going through HTTP, and so handlers in
  /// other modules can register long-running operations through the
  /// same manager.
  JobManager get jobManager => _jobManager;

  /// P1-5: operator-slot manager. Exposed so the GUI can subscribe to
  /// ownership-change events for the desktop status-bar badge, and so
  /// tests can introspect the slot without going through HTTP.
  SessionOwnershipManager get sessionOwnership => _sessionOwnership;

  /// Expose the internal collaboration manager so GUI hosts can track
  /// viewer-count changes (drives the desktop status-bar viewer badge).
  /// Why expose rather than emit yet another callback: the manager already
  /// publishes a `LiveCollaborationState` stream consumers can subscribe to,
  /// and exposing it avoids duplicating that wiring for one more listener.
  LiveCollaborationSessionManager get collaborationManager =>
      _collaborationManager;
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
