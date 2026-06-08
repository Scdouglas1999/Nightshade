// Auth tokens must be printed to stdout transiently (NOT logged to file â€”
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
import 'headless_api/push/database_push_token_store.dart';
import 'headless_api/routes.dart';
import 'headless_api/job_manager.dart';
import 'headless_api/request_context.dart' as ctx;
import 'headless_api/response_helpers.dart';
import 'headless_api/route_metadata.dart' as route_metadata;
import 'headless_api/session_ownership.dart';
import 'headless_api/validation.dart';

part 'headless_api_server/http_middleware.dart';
part 'headless_api_server/websocket_sessions.dart';
part 'headless_api_server/handler_initialization.dart';
part 'headless_api_server/server_lifecycle.dart';
part 'headless_api_server/event_forwarding.dart';

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
  /// request context â€” only the digest â€” so a misbehaving handler that
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
  /// app bypass CORS. See Â§2.27 in 2026-05-09-v250-audit-fixes.md.
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
  /// set â€” see [_serverFingerprint].
  final SecurityContext? tlsContext;

  /// P0-9: when TLS is active, the SHA-256 hex digest of the certificate's
  /// SubjectPublicKeyInfo DER. Used to overwrite the token-derived
  /// fingerprint with a cert-pinned identity anchor. Plain HTTP mode leaves
  /// this null and falls back to the token-derived fingerprint.
  final String? tlsPublicKeyFingerprint;

  /// P1-1: capacity of the in-memory ring buffer that backs WS replay on
  /// reconnect. Default 5000 events â‰ˆ 5 MB at 1 KB/event. Tuned per-deploy
  /// for memory-constrained hosts (Pi 4 / Pi 5).
  final int eventReplayBufferSize;

  HttpServer? _server;
  final List<WebSocketChannel> _sockets = [];
  final Map<WebSocketChannel, String> _socketViewerIds = {};

  /// P2-15: SHA-256 digest of the bearer token that authenticated each
  /// connected socket. Populated at upgrade time from the request context
  /// that `_authMiddleware` stashed. Used as the canonical `viewerId` for
  /// `collaboration.join` messages â€” any client-supplied value is ignored.
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
  /// requests bypass this limiter (they never reach it â€” auth rejects
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
  late final AuthHandlers _authHandlers;
  late final PairingHandlers _pairingHandlers;
  // Phase D — cellular-push token + preference endpoints. Shares the pairing
  // PairingService/DB via `_ensurePairingService` so push tokens live next to
  // the paired-device rows they belong to.
  late final PushHandlers _pushHandlers;
  late final SystemHandlers _systemHandlers;
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

  // Wave 6 â€” Run-Watch (phone/tablet monitoring).
  // The handler exposes /api/run-watch/{snapshot,frame-thumbnail,events}.
  // Backed by a fan-out broadcast stream over `backend.eventStream` so the
  // SSE handler can have any number of concurrent phone clients without
  // touching the tokio broadcast channel on the Rust side.
  late final RunWatchHandlers _runWatchHandlers;
  StreamController<NightshadeEvent>? _runWatchEventBroadcast;

  // Wave 7 Agent 2 â€” live-stacking broadcast endpoints.
  late final BroadcastHandlers _broadcastHandlers;

  // P2-10 â€” push-based live-view streaming over /ws/live-view. Backed by
  // a long-lived [LiveViewStreamHub] so subscriber state survives socket
  // churn and the JPEG-encode pipeline only runs while >=1 subscriber is
  // attached.
  late final LiveViewStreamHandlers _liveViewStreamHandlers;
  late final LiveViewStreamHub _liveViewStreamHub;

  // Wave 7A â€” WebRTC datachannel fan-out for the same producer. Sessions
  // attach to [_liveViewStreamHub] via its public attachRaw entry point
  // so we do NOT duplicate the JPEG-encode pipeline; the WebRTC handler
  // is just a parallel transport for the existing frames.
  late final WebRtcLiveViewHandlers _webRtcLiveViewHandlers;

  // P1-2 / P1-3 â€” long-running job model handlers.
  late final JobHandlers _jobHandlers;

  // P1-5 â€” session ownership handlers.
  late final SessionOwnershipHandlers _sessionOwnershipHandlers;

  // P1-14 â€” remote log retrieval + tail SSE for mobile diagnostics.
  late final LogHandlers _logHandlers;

  // P1-10 â€” remote calibration library management (darks / flats /
  // defect maps). Constructed unconditionally; the routes are always wired
  // because every deployment has the Drift tables backing them.
  late final CalibrationHandlers _calibrationHandlers;

  // P1-12 â€” catalog management (download / upload / verify / uninstall /
  // reload). Constructed unconditionally; downloads run via the
  // JobManager so the HTTP connection isn't held open.
  late final CatalogHandlers _catalogHandlers;
  StreamSubscription<CatalogEvent>? _catalogEventSubscription;

  // P2-8 â€” read-only DB endpoints for tables the phone could not see
  // (sequence runs, notes journal, guide RMS history, polar alignment
  // history, dark library, flat history). Stateless beyond the DAOs it
  // reads off the container.
  late final DbReadHandlers _dbReadHandlers;

  // P2-11 â€” plugin management. Owns the plugin archive directory under
  // $appData/Nightshade/plugins and the SHA-256 verification path.
  late final PluginHandlers _pluginHandlers;

  // P1-11 â€” OTA update endpoints. Null when no UpdateController was
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
      // is a security defect â€” anyone with read access to logs would have
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

    _initializeHandlers();
  }

  // ===========================================================================
  // Core Handlers (moved to handlers/system_handlers.dart)
  //
  // The four read-only system endpoints (/api/info, /api/status,
  // /api/self-test, /api/openapi.json), together with the canonical
  // `availableHeadlessEndpoints()` catalog and the storage/DB/connected-
  // device probes that back self-test, now live in [SystemHandlers].
  // The closure-based [SystemServerView] passed at construction time
  // keeps the snapshot live (every getter is called per request) so
  // the JSON envelope matches the inline implementation exactly.
  // ===========================================================================

  /// Sorted, deduplicated list of scope names present in the configured
  /// + paired token tables. Captured into [SystemServerView] so the
  /// extracted [SystemHandlers] can surface it on /api/info and
  /// /api/self-test without re-reading server state.
  List<String> _availableAuthScopes() {
    final scopes = _effectiveAuthTokensByValue.values
        .map(headlessTokenScopeName)
        .toSet()
        .toList();
    scopes.sort();
    return scopes;
  }

  // /api/collaboration/* and /api/session-handoff handlers were moved to
  // [CollaborationHandlers] (handlers/collaboration_handlers.dart). The
  // shared LiveCollaborationSessionManager is injected so the WS upgrade
  // path, the desktop GUI, and the HTTP surface still observe the same
  // in-memory state.

  // ===========================================================================
  // Pairing flow (Â§2.1) â€” first-run dashboard onboarding.
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

  // /api/pairing/{start,verify,active} handlers moved to
  // [PairingHandlers] (handlers/pairing_handlers.dart). The lifecycle
  // callbacks `ensurePairingService` / `recordPairedSession` /
  // `rateLimitClientKey` keep the server's private state behind a
  // typed surface.

  // /api/ws/ticket and /api/auth/{cookie,csrf,logout} handlers moved to
  // [AuthHandlers] (handlers/auth_handlers.dart). The shared
  // WsTicketManager, AuthCookieManager, and a TokenScopeResolver closure
  // (`_scopeForToken`) are injected via the constructor.

  /// Whether [method] mutates state and therefore requires CSRF when the
  /// caller is using a cookie. Why uppercase compare: shelf passes the
  /// raw method but middleware may have lowercased it elsewhere â€” be
  /// defensive. Stays inline because the auth middleware (which lives
  /// here) is the only consumer.
  static bool _methodNeedsCsrf(String method) {
    final upper = method.toUpperCase();
    return upper == 'POST' ||
        upper == 'PUT' ||
        upper == 'DELETE' ||
        upper == 'PATCH';
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

  // Legacy /api/sequences/{status,start,stop} routes now register the
  // sequencer-handler refs directly (see `_setupRoutes()`). Their
  // previous one-line indirection methods were redundant.

  // Dashboard + Run-Watch static-file serving was moved to
  // [StaticFileHandlers] (handlers/static_file_handlers.dart). The handlers
  // there own the SPA-directory resolution, the MIME-type table, the CSP
  // security headers, and the symlink-traversal guard. Inline `_handleInfo`
  // / `_handleSelfTest` now read the dashboard-available flag via
  // `_staticFileHandlers.dashboardAvailable` so the inline JSON shape is
  // unchanged.

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
  /// dependency for this single call site. RFC 4122 Â§4.4.
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

  Future<void> start() => _startServer();

  Future<void> stop() => _stopServer();

  void broadcastEvent(dynamic event) => _broadcastEventImpl(event);

  void setPushNotificationStream(
    Stream<Map<String, dynamic>> notificationStream,
  ) =>
      _setPushNotificationStream(notificationStream);

  void setLanPushBroadcaster(LanPushBroadcaster? broadcaster) =>
      _setLanPushBroadcaster(broadcaster);

  void setRemotePushDelivery(RemotePushDelivery? delivery) =>
      _setRemotePushDelivery(delivery);

  /// A [PushTokenStore] over this server's pairing DB — the recipient list the
  /// FCM/APNs/mock deliveries enumerate. Lazily constructs the
  /// [PairingService] (and thus opens the Drift DB) on first call, so only
  /// deployments that actually wire cellular push pay the DB-open cost.
  PushTokenStore get pushTokenStore =>
      DatabasePushTokenStore(_ensurePairingService().database);

  /// Phase D — wire the no-cloud [MockRemotePushDelivery] as the active remote
  /// delivery. Every critical push that reaches the cellular tap is then
  /// enumerated against the registered tokens (filtered by per-device prefs)
  /// and recorded into the mock's `delivered` list / logged as "would-send".
  ///
  /// This is the default Phase-D path: the operator gets a fully exercised
  /// fan-out (recipient lookup + preference gate) with zero Firebase/Apple
  /// accounts. Swap in the real FCM/APNs deliveries (sharing this same
  /// [pushTokenStore]) once credentials exist.
  MockRemotePushDelivery wireMockRemotePushDelivery({
    void Function(String message)? log,
  }) {
    final mock = MockRemotePushDelivery(store: pushTokenStore, log: log);
    _setRemotePushDelivery(mock);
    return mock;
  }

  /// Phase D — load [PushConfig] from [appSupportDir] (or the
  /// `NIGHTSHADE_PUSH_CONFIG` env override) and wire the resulting delivery:
  ///
  ///  * a real FCM and/or APNs delivery when the operator has dropped a valid
  ///    `push_config.json` pointing at the service-account JSON / `.p8` key
  ///    (the "real when configured" path), otherwise
  ///  * the no-cloud [MockRemotePushDelivery] (the "mock by default" path) so
  ///    the recipient lookup + per-device preference gate are exercised end to
  ///    end with zero Firebase/Apple accounts.
  ///
  /// All deliveries share [pushTokenStore], so each enumerates the same
  /// `device_push_tokens` rows filtered by `device_push_prefs`. Returns the
  /// wired delivery (or `null` only if config explicitly disables every
  /// channel AND the mock — i.e. `mock:false` with no cloud channel, leaving
  /// LAN + WS push untouched). Never throws: a malformed config degrades to
  /// the mock so the server always starts.
  Future<RemotePushDelivery?> wireRemotePushDelivery({
    required String appSupportDir,
    void Function(String message)? log,
  }) async {
    final store = pushTokenStore;
    PushConfig config;
    try {
      config = await PushConfig.load(appSupportDir: appSupportDir);
    } catch (_) {
      config = PushConfig.disabled;
    }
    // `buildRemotePushDelivery` returns the real FCM/APNs senders when a cloud
    // channel is configured, the mock when `config.mock` is set, else null.
    // With no cloud channel and no explicit `mock:false` opt-out we still want
    // the mock as the Phase-D default, so fall back to it here.
    final delivery = buildRemotePushDelivery(config, store) ??
        (config.hasCloudChannel
            ? null
            : MockRemotePushDelivery(store: store, log: log));
    if (delivery != null) {
      _setRemotePushDelivery(delivery);
    }
    return delivery;
  }

  void setUpdateController(UpdateController? controller) =>
      _setUpdateController(controller);

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
