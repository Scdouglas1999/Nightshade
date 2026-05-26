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
import 'headless_api/routes.dart';
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
  late final AuthHandlers _authHandlers;
  late final PairingHandlers _pairingHandlers;
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

  // Wave 7A — WebRTC datachannel fan-out for the same producer. Sessions
  // attach to [_liveViewStreamHub] via its public attachRaw entry point
  // so we do NOT duplicate the JPEG-encode pipeline; the WebRTC handler
  // is just a parallel transport for the existing frames.
  late final WebRtcLiveViewHandlers _webRtcLiveViewHandlers;

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
    _authHandlers = AuthHandlers(
      wsTicketManager: _wsTicketManager,
      authCookieManager: _authCookieManager,
      scopeForToken: _scopeForToken,
      logger: container.read(loggingServiceProvider),
    );
    _pairingHandlers = PairingHandlers(
      pairingAttempts: _pairingAttempts,
      ensurePairingService: _ensurePairingService,
      // Why a closure: PairingHandlers does not have visibility into
      // [_pairedSessionTokens], and we deliberately do not want to leak
      // that map past the server boundary. The closure mutates it
      // through a typed, intent-named entry point so the call site is
      // unambiguous.
      recordPairedSession: (token, scope) {
        _pairedSessionTokens[token] = scope;
      },
      rateLimitClientKey: _rateLimitClientKey,
      pairingPrintCodes: pairingPrintCodes,
      logger: container.read(loggingServiceProvider),
    );
    _systemHandlers = SystemHandlers(
      container: container,
      view: SystemServerView(
        // Wrap every server field in a closure so the handler always
        // reads the live value (the event-seq counter advances on
        // every broadcast, so a one-shot capture would be wrong by
        // the second request).
        fingerprint: () => _serverFingerprint,
        instanceId: () => _serverInstanceId,
        currentEventSeq: () => _eventSeq,
        eventReplayBufferSize: () => eventReplayBufferSize,
        eventReplayBufferOldestSeq: () => _eventReplayBuffer.oldestSeq,
        port: () => port,
        bindLocalOnly: () => bindLocalOnly,
        authRequired: () => _effectiveAuthTokensByValue.isNotEmpty,
        availableAuthScopes: _availableAuthScopes,
      ),
      staticFileHandlers: _staticFileHandlers,
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

    // Wave 7A — WebRTC live-view fan-out. Each session attaches to the
    // SAME hub via attachRaw with a custom sink that pushes binary
    // frames into an outbound RTCDataChannel. No re-encode, no second
    // producer loop.
    _webRtcLiveViewHandlers = WebRtcLiveViewHandlers(
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

    // Route table — per-domain declarative lists live under
    // `headless_api/routes/`. Each handler class has a sibling
    // `routes/<name>_routes.dart` exporting a top-level
    // `build<Name>Routes(handler)`. The order below MIRRORS the
    // legacy inline-`router.<verb>(...)` block exactly; shelf_router
    // matches by registration order so any reordering across domain
    // boundaries (e.g. moving `/api/sessions/*` (analytics) before
    // `/api/sessions/<sessionId>/images` (sessions)) would change
    // first-hit semantics. See `routes/headless_route.dart` for the
    // typed primitives.
    final allRoutes = <HeadlessRoute>[
      ...buildSystemRoutes(_systemHandlers),
      ...buildPairingRoutes(_pairingHandlers),
      ...buildAuthRoutes(_authHandlers),
      ...buildCollaborationRoutes(_collaborationHandlers),
      ...buildDeviceDiscoveryRoutes(_deviceDiscoveryHandlers),
      ...buildDeviceRoutes(_deviceHandlers),
      ...buildGuidingRoutes(_guidingHandlers),
      ...buildImagingRoutes(_imagingHandlers),
      ...buildSequencerRoutes(_sequencerHandlers),
      ...buildEquipmentRoutes(_equipmentHandlers),
      ...buildProfileRoutes(_profileHandlers),
      ...buildSessionRoutes(_sessionHandlers),
      ...buildTargetRoutes(_targetHandlers),
      ...buildSequenceManagementRoutes(_sequenceManagementHandlers),
      ...buildFlatWizardRoutes(_flatWizardHandlers),
      ...buildMosaicRoutes(_mosaicHandlers),
      ...buildAnalyticsRoutes(_analyticsHandlers),
      ...buildWeatherRoutes(_weatherHandlers),
      ...buildFileSystemRoutes(_fileSystemHandlers),
      ...buildScienceRoutes(_scienceHandlers),
      ...buildSuggestionRoutes(_suggestionHandlers),
      ...buildTransientRoutes(_transientHandlers),
      ...buildBackupRoutes(_backupHandlers),
      ...buildFramingRoutes(_framingHandlers),
      ...buildPlanetariumRoutes(_planetariumHandlers),
      ...buildDomeRoutes(_domeHandlers),
      ...buildSafetyMonitorRoutes(_safetyMonitorHandlers),
      ...buildAuxiliaryRoutes(_auxiliaryHandlers),
      ...buildSchedulerRoutes(_schedulerHandlers),
      ...buildFocusModelRoutes(_focusModelHandlers),
      ...buildJobRoutes(_jobHandlers),
      ...buildSessionOwnershipRoutes(_sessionOwnershipHandlers),
    ];

    // P1-11 — OTA update routes are only registered when the host has
    // wired an UpdateController via [setUpdateController]. Tests and
    // headless deployments that opt out of OTA leave the controller
    // unset, in which case these routes return 404 from the router
    // itself — matching the legacy behaviour exactly.
    final updateHandlers = _updateHandlers;
    if (updateHandlers != null) {
      allRoutes.addAll(buildUpdateRoutes(updateHandlers));
    }

    // Continue appending the remaining per-domain route lists. These
    // come AFTER the OTA block above so the relative declaration order
    // of OTA routes vs. log / calibration / catalog routes is preserved
    // exactly — shelf_router matches on registration order.
    allRoutes
      ..addAll(buildRunWatchRoutes(_runWatchHandlers))
      ..addAll(buildBroadcastRoutes(_broadcastHandlers))
      ..addAll(buildLogRoutes(_logHandlers))
      ..addAll(buildCalibrationRoutes(_calibrationHandlers))
      ..addAll(buildCatalogRoutes(_catalogHandlers))
      ..addAll(buildDbReadRoutes(_dbReadHandlers))
      ..addAll(buildPluginRoutes(_pluginHandlers))
      // Wave 7A — WebRTC live-view signalling. Must register before
      // the static-file catch-all so `/api/webrtc/live-view/*` is not
      // shadowed by the SPA fallback.
      ..addAll(buildWebRtcLiveViewRoutes(_webRtcLiveViewHandlers))
      ..addAll(buildStaticFileRoutes(_staticFileHandlers));

    // WebSocket-upgrade endpoints. Why these are NOT in
    // [buildWebSocketRoutes] as method-tear-offs:
    //
    // 1. `shelf_web_socket`'s `webSocketHandler` strips the original
    //    Request, so we capture it in an outer closure so the P1-1
    //    replay handler can read `?since=` and `?instance=` query
    //    parameters off the upgrade URL.
    // 2. P2-15: we also lift the auth identity (digest of the bearer
    //    token that authenticated the upgrade) off the request context
    //    that `_authMiddleware` stashed there. Passing it down means
    //    the collaboration `viewerId` is always the authenticated
    //    principal, regardless of what the client puts in the
    //    `collaboration.join` payload.
    //
    // [buildWebSocketRoutes] accepts the pre-built Handler closures so
    // the route table stays purely declarative; the closure body itself
    // has to live here because it accesses private server state.
    Handler eventsHandler() {
      return (Request request) {
        final query = request.url.queryParameters;
        final authIdentity = _authIdentityFrom(request);
        return webSocketHandler((socket, _) {
          _handleWebSocketWithQuery(socket, query, authIdentity);
        }).call(request);
      };
    }

    // P2-10 — push-based live-view streaming. Distinct from the main
    // event WS because (a) it carries binary JPEG frames, not JSON
    // events, and (b) the message protocol is a per-socket
    // subscribe/unsubscribe model rather than the always-on event
    // broadcast.
    Handler liveViewHandler() {
      return (Request request) {
        return webSocketHandler((socket, _) {
          _liveViewStreamHandlers.handleSocket(socket);
        }).call(request);
      };
    }

    allRoutes.addAll(buildWebSocketRoutes(
      eventsHandler: eventsHandler(),
      liveViewHandler: liveViewHandler(),
    ));

    // Single dispatch point — `registerRoutes` walks the list once and
    // calls the right `router.<verb>(...)` for each entry. See
    // `routes/headless_route.dart` for the typed-list design rationale.
    registerRoutes(router, allRoutes);

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
    // Wave 7A: tear down WebRTC sessions BEFORE the hub so any pending
    // datachannel send during the hub's final detach iteration does
    // not race with libwebrtc's close path.
    await _webRtcLiveViewHandlers.dispose();
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
  /// raw method but middleware may have lowercased it elsewhere — be
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
