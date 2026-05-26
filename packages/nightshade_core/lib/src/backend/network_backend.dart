// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:nightshade_core/src/models/settings/app_settings.dart'
    as models;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

// Import pure Dart types from backend_types for return types
import '../models/errors/nightshade_error.dart' as dart_error;
// [Wave 6D error parsing] — parse the headless server's structured error
// envelope ({code, message, details}) into a typed [ServerError] so the
// mobile companion can branch on the machine-readable `code` instead of
// substring-matching the message text.
import '../models/errors/server_error.dart';
import 'remote_display_jpeg.dart';

/// Backend connection state.
///
/// P2-13: the chip in the mobile UI conflated OS-level connectivity with
/// WebSocket session liveness. Splitting `connecting` (very first attempt)
/// from `reconnecting` (subsequent attempts after a previously-successful
/// connection) and adding a terminal `error` (gave up / hard failure) lets
/// the indicator render "Server unreachable" distinctly from "Reconnecting".
///
/// Why five values rather than three: `connecting` and `reconnecting` both
/// look like "in flight" to the user, but the messaging differs — a fresh
/// connect should not promise "still reconnecting" when there's nothing to
/// reconnect to yet. `error` is reserved for the case where the backend has
/// stopped attempting (e.g. an unrecoverable version mismatch); the legacy
/// `disconnected` state is reused for the post-disconnect idle window while
/// the exponential backoff timer is armed.
enum BackendConnectionState {
  /// Idle — not currently attempting a connection and not connected.
  /// Either disposed, or a backoff timer is armed before the next attempt.
  disconnected,

  /// First-time connect in progress (no prior successful attachment).
  /// Distinct from [reconnecting] so the UI says "Connecting" rather than
  /// "Reconnecting" on the initial handshake.
  connecting,

  /// WebSocket is open and the upgrade handshake completed successfully.
  connected,

  /// A prior connection dropped and the backend is retrying.
  reconnecting,

  /// Terminal failure mode (e.g. API version incompatibility). The backend
  /// stopped attempting; the user must reconfigure or relaunch. Emitting
  /// `error` is rare — most transient failures stay in [reconnecting] until
  /// the backoff window times out.
  error,
}

class RemoteDirectoryEntry {
  final String name;
  final String path;

  const RemoteDirectoryEntry({
    required this.name,
    required this.path,
  });

  factory RemoteDirectoryEntry.fromJson(Map<String, dynamic> json) {
    return RemoteDirectoryEntry(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class RemoteDirectoryListing {
  final String? currentPath;
  final String? parentPath;
  final List<RemoteDirectoryEntry> directories;

  const RemoteDirectoryListing({
    required this.currentPath,
    required this.parentPath,
    required this.directories,
  });

  factory RemoteDirectoryListing.fromJson(Map<String, dynamic> json) {
    final directories = (json['directories'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(RemoteDirectoryEntry.fromJson)
        .toList();
    return RemoteDirectoryListing(
      currentPath: json['currentPath'] as String?,
      parentPath: json['parentPath'] as String?,
      directories: directories,
    );
  }
}

/// Wire shape for `GET /api/filter-wheel/position` (P2-7).
///
/// Mirrors the JSON envelope emitted by `DeviceHandlers
/// .handleFilterWheelGetPosition`. `position` is null when the filter
/// wheel is disconnected or the driver has not yet reported a slot,
/// `name` is null when the driver returned a short slot-name array.
class RemoteFilterWheelPosition {
  final int? position;
  final String? name;
  final bool isMoving;

  const RemoteFilterWheelPosition({
    required this.position,
    required this.name,
    required this.isMoving,
  });

  factory RemoteFilterWheelPosition.fromJson(Map<String, dynamic> json) {
    return RemoteFilterWheelPosition(
      position: (json['position'] as num?)?.toInt(),
      name: json['name'] as String?,
      isMoving: json['isMoving'] as bool? ?? false,
    );
  }
}

class RemoteScienceBundle {
  final List<PhotometryMeasurementRow> photometry;
  final List<FramePhotometricCalibrationRow> calibrations;
  final List<TransparencySampleRow> transparency;
  final List<PsfFieldTileRow> psfTiles;
  final List<ScienceFrameQualityMetricsRow> frameQuality;
  final List<ScienceTileMetricRow> tileMetrics;
  final List<AstrometryResidualVectorRow> residuals;
  final List<MovingObjectCandidateRow> movingObjects;
  final List<LineRatioProductRow> lineRatios;

  const RemoteScienceBundle({
    required this.photometry,
    required this.calibrations,
    required this.transparency,
    required this.psfTiles,
    required this.frameQuality,
    required this.tileMetrics,
    required this.residuals,
    required this.movingObjects,
    required this.lineRatios,
  });
}

/// Network backend implementation that communicates with a headless server
///
/// This backend uses HTTP REST API and WebSocket for real-time events
/// and is used by the Mobile app to control a remote Desktop/Headless instance.
class NetworkBackend implements NightshadeBackend {
  static const _requestIdHeader = 'x-request-id';

  final String serverHost;
  final int serverPort;
  final int webSocketPort;
  final String? authToken;
  final Duration webSocketHeartbeatInterval;
  final Duration webSocketHeartbeatTimeout;

  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _webSocketHeartbeatTimer;
  final StreamController<NightshadeEvent> _eventController =
      StreamController<NightshadeEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _pushNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Persistent HTTP client for connection reuse.
  /// Using a single client avoids TCP connection churn and enables
  /// keep-alive connections for better performance.
  ///
  /// Why: dart:io `HttpClient` is retained for the binary streaming paths
  /// (image thumbnail/download, raw image bytes, FITS write) that rely on
  /// chunked response streaming. The JSON helper layer below uses
  /// `package:http` so it can be injected with a `MockClient` in tests.
  late final HttpClient _httpClient;

  /// `package:http` client used by the JSON HTTP helpers (`_get`, `_post`,
  /// `_put`, `_delete`, `_downloadBytes`, `_postRaw`, `_postRawBytes`, and
  /// `_checkServerCompatibility`). Injectable so tests can substitute a
  /// `MockClient` without spinning up a real HTTP server.
  final http.Client _http;

  /// Whether `_http` was constructed internally and therefore must be closed
  /// in `dispose`. When a caller injects a client (e.g. a test fake), the
  /// caller owns its lifecycle.
  final bool _ownsHttpClient;

  // Connection state management
  BackendConnectionState _connectionState = BackendConnectionState.disconnected;
  final StreamController<BackendConnectionState> _connectionStateController =
      StreamController<BackendConnectionState>.broadcast();
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  DateTime? _lastWebSocketMessageAt;
  bool _disposed = false;
  int _requestCounter = 0;
  static const int _maxReconnectDelay = 30; // Max 30 seconds

  /// P2-13: latches `true` the first time a connection attempt reaches the
  /// `connected` state. Used to distinguish the initial-handshake `connecting`
  /// transition from subsequent `reconnecting` attempts so the UI can render
  /// distinct messaging on each.
  bool _hasEverConnected = false;

  /// P2-2: identity payload sent on `collaboration.join` after the WS
  /// handshake completes. The server overrides the `viewerId` with the
  /// authenticated principal's digest (see P2-15) but we still send our
  /// derived value so the wire shape stays unchanged for hosts that
  /// pre-date the override and so the server can log impersonation
  /// attempts when our identity doesn't match. Display name appears in
  /// the viewer slot list on the desktop UI; defaults are derived in the
  /// mobile bootstrap and injected via [collaborationIdentity].
  String? _collaborationViewerId;
  String? _collaborationDeviceName;
  String? _collaborationDisplayName;

  // Ping/pong round-trip latency tracking. The WebSocket heartbeat already
  // exchanges {type:"ping"} / {type:"pong"} every `webSocketHeartbeatInterval`,
  // so this just records the send timestamp and computes the delta when the
  // matching pong arrives. We don't attach an id to pings (the server replies
  // to every ping with a single pong), so we just keep the most recent send
  // timestamp.
  DateTime? _pendingPingSentAt;
  Duration? _lastLatency;
  final StreamController<Duration> _latencyController =
      StreamController<Duration>.broadcast();

  // P1-1: client-side event sequencing + replay state.
  //
  // `_lastSeenEventSeq` is the monotonic seq of the most recent event we
  // accepted from the server. Null until the first event with a non-null
  // seq is observed (which is also the cursor we send back as `?since=`
  // on a reconnect to ask the server to replay anything we missed).
  //
  // `_serverInstanceId` is the UUID the server stamps on every outbound
  // event; a change in this value means the server restarted and our
  // cached seq cursor is now meaningless (the new server starts counting
  // from 0).
  //
  // `_previousServerInstanceId` snapshots the last instance we successfully
  // attached to so that, on the NEXT reconnect, we can compare against
  // whatever the new server advertises and reset the cursor if they
  // differ. This is the reactive path; the in-band check inside the WS
  // message handler covers the rarer "instance changes mid-stream" case.
  int? _lastSeenEventSeq;
  String? _serverInstanceId;
  String? _previousServerInstanceId;

  NetworkBackend({
    required this.serverHost,
    this.serverPort = 8080,
    this.webSocketPort = 8080, // WebSocket is on same port as HTTP
    this.authToken,
    this.webSocketHeartbeatInterval = const Duration(seconds: 15),
    this.webSocketHeartbeatTimeout = const Duration(seconds: 45),
    http.Client? httpClient,
    bool autoConnectWebSocket = true,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null {
    // Initialize persistent HTTP client with connection pooling
    _httpClient = HttpClient()
      ..idleTimeout = const Duration(seconds: 30)
      ..connectionTimeout = const Duration(seconds: 10);
    // Connect WebSocket immediately. Tests that only exercise the HTTP
    // request/response path can disable this to avoid background timers
    // and reconnect storms.
    if (autoConnectWebSocket) {
      connect();
    }
  }

  @override
  bool get dispatchPluginNodesLocally => false;

  /// Stream of connection state changes
  Stream<BackendConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Current connection state
  BackendConnectionState get connectionState => _connectionState;

  /// Stream of WebSocket ping/pong round-trip times. Emits a [Duration]
  /// every time the server's pong is received after we send a ping.
  /// Subscribers (e.g. the mobile NetworkStatusIndicator) use this to
  /// surface latency to the operator. Hidden when disconnected — when
  /// the heartbeat stops firing, no new values are emitted.
  Stream<Duration> get latencyStream => _latencyController.stream;

  /// The most recent ping/pong round-trip time, or null if none has been
  /// observed yet (initial connect, or post-disconnect).
  Duration? get lastLatency => _lastLatency;

  /// P1-1: monotonic sequence number of the last event we accepted from
  /// the server. Null before any seq-bearing event has been received (e.g.
  /// fresh connection, or talking to a pre-P1-1 server).
  ///
  /// Used together with [serverInstanceId] to build the `?since=N&instance=
  /// UUID` query string on a reconnect so the server can replay events we
  /// missed during the disconnect window.
  int? get lastSeenEventSeq => _lastSeenEventSeq;

  /// P1-1: UUID identifying the server instance we're currently attached
  /// to. Null until the first event (or `/api/info` response) discloses
  /// it. Changes when the server restarts; observing a change is the
  /// trigger to invalidate [lastSeenEventSeq].
  String? get serverInstanceId => _serverInstanceId;

  /// P2-2: identity broadcast on every `collaboration.join` frame sent
  /// after the WS handshake succeeds. Call this BEFORE [connect] (or
  /// before the auto-reconnect timer fires) so the very first join after
  /// the handshake carries the right values. Subsequent reconnects reuse
  /// whatever was last set here. The `viewerId` is derived from the
  /// authenticated token (typically `computeServerFingerprint(authToken)`
  /// — the same digest the server stamps on the socket context). When
  /// authentication is disabled and the caller has no token, pass any
  /// stable per-device identifier; the server will accept it because the
  /// "authenticated identity" override is null.
  ///
  /// `displayName` is what appears in the host UI's viewer slot list. The
  /// mobile companion sets it to `"PLATFORM · MODEL"` by default.
  void setCollaborationIdentity({
    required String viewerId,
    required String deviceName,
    required String displayName,
  }) {
    _collaborationViewerId = viewerId;
    _collaborationDeviceName = deviceName;
    _collaborationDisplayName = displayName;
  }

  /// Manually trigger an immediate WebSocket reconnection attempt.
  ///
  /// Cancels any pending exponential-backoff reconnect timer and calls
  /// [connect] right away. Used by the mobile UI's "Reconnect now" button
  /// so the operator doesn't have to wait the full backoff window before
  /// retrying a failed connection.
  ///
  /// The reconnect attempt counter is reset so the next failure starts
  /// fresh from a 1s backoff (rather than continuing the previous chain).
  Future<void> reconnectNow() async {
    if (_disposed) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    developer.log(
      '[NetworkBackend] Manual reconnect requested',
      name: 'NetworkBackend',
      level: 800,
    );
    await connect();
  }

  /// Update connection state and notify listeners
  void _updateConnectionState(BackendConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionStateController.add(newState);
      developer.log('[NetworkBackend] Connection state changed to: $newState',
          name: 'NetworkBackend', level: 800);
    }
  }

  /// Test connectivity to server
  Future<bool> testConnection() async {
    try {
      final compatibility = await _checkServerCompatibility();
      if (!compatibility.isCompatible) {
        developer.log('Connection rejected: ${compatibility.message}',
            name: 'NetworkBackend', level: 900);
        return false;
      }

      return true;
    } catch (e) {
      developer.log('Connection test failed: $e',
          name: 'NetworkBackend', level: 900, error: e);
      return false;
    }
  }

  Future<RemoteApiCompatibilityResult> _checkServerCompatibility() async {
    final uri = Uri.parse('http://$serverHost:$serverPort/api/info');
    final headers = <String, String>{
      RemoteApiCompatibility.apiVersionHeader:
          RemoteApiCompatibility.clientApiVersion.format(),
      _requestIdHeader: _nextRequestId('compat'),
    };
    final response = await _http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 3));
    if (response.statusCode != 200) {
      throw HttpException(
        'GET /api/info failed with HTTP ${response.statusCode}',
        uri: uri,
      );
    }

    final info = jsonDecode(response.body) as Map<String, dynamic>;
    // P1-1: surface the server instance UUID so the WS connect can decide
    // whether the seq cursor we cached on the previous attachment is still
    // valid against the server we're about to talk to. If the field is
    // missing the server pre-dates P1-1 and we just skip replay (live-only).
    final advertisedInstance = info['serverInstanceId'];
    if (advertisedInstance is String && advertisedInstance.isNotEmpty) {
      _reconcileInstanceFromInfo(advertisedInstance);
    }
    return RemoteApiCompatibility.check(info['version'] as String?);
  }

  /// P1-1: compare the instance UUID advertised by `/api/info` against the
  /// one we attached to on the previous connect. If they differ, the server
  /// was restarted between our connection attempts and our cached seq
  /// cursor refers to a counter that no longer exists. Reset it so the
  /// next WS connect omits `?since=` and starts fresh.
  ///
  /// On the FIRST `/api/info` call (no previous instance recorded) we just
  /// remember the value; on later calls we diff against the cached one.
  void _reconcileInstanceFromInfo(String advertisedInstance) {
    final previous = _previousServerInstanceId;
    if (previous != null && previous != advertisedInstance) {
      developer.log(
        '[NetworkBackend] Server instance changed (old=$previous, '
        'new=$advertisedInstance); cached event seq invalidated.',
        name: 'NetworkBackend',
        level: 900,
      );
      _lastSeenEventSeq = null;
      if (!_eventController.isClosed) {
        _eventController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          category: EventCategory.system,
          eventType: 'BackendReconnected',
          severity: EventSeverity.info,
          data: {
            'message': 'Server instance changed; cached state invalidated',
            'previousInstance': previous,
            'currentInstance': advertisedInstance,
          },
        ));
      }
    }
    _serverInstanceId = advertisedInstance;
    _previousServerInstanceId = advertisedInstance;
  }

  /// Initialize the WebSocket connection for real-time events
  Future<void> connect() async {
    _reconnectTimer?.cancel();
    if (_disposed) {
      return;
    }

    try {
      _stopWebSocketHeartbeat();
      // P2-13: distinguish "first-time connect" from "reconnecting after
      // a previously-healthy session" so the UI can render distinct
      // messaging. The latch flips on the first successful handshake
      // and stays true for the lifetime of this backend instance — a
      // dispose+recreate (via BackendNotifier swap) starts the cycle
      // over, which is the intended UX for "I changed servers".
      _updateConnectionState(_hasEverConnected
          ? BackendConnectionState.reconnecting
          : BackendConnectionState.connecting);

      final compatibility = await _checkServerCompatibility();
      if (!compatibility.isCompatible) {
        developer.log('Connection rejected: ${compatibility.message}',
            name: 'NetworkBackend', level: 900);
        // Version mismatch is a terminal condition — the caller must
        // upgrade or downgrade one side before retrying. Emit `error`
        // rather than `disconnected` so the UI surfaces this as an
        // unrecoverable failure (no spinning "reconnecting…" forever).
        _updateConnectionState(BackendConnectionState.error);
        return;
      }

      final queryParameters = <String, String>{};
      if (authToken != null && authToken!.isNotEmpty) {
        queryParameters['token'] = authToken!;
      }
      queryParameters['apiVersion'] =
          RemoteApiCompatibility.clientApiVersion.format();
      // P1-1: if we've previously attached to this server instance and have
      // a seq cursor to ask replay from, include both. The server-side
      // /events handler treats omitting either parameter as "fresh
      // subscribe, live-only" — which is also what we want on the very
      // first connect (no cursor yet) or after an instance change reset
      // the cursor to null.
      if (_lastSeenEventSeq != null && _serverInstanceId != null) {
        queryParameters['since'] = _lastSeenEventSeq!.toString();
        queryParameters['instance'] = _serverInstanceId!;
      }
      final wsUri = Uri(
        scheme: 'ws',
        host: serverHost,
        port: webSocketPort,
        path: '/events',
        queryParameters: queryParameters.isEmpty ? null : queryParameters,
      );
      _wsChannel = IOWebSocketChannel.connect(wsUri);
      _lastWebSocketMessageAt = DateTime.now();

      // Cancel any existing subscription before creating a new one
      await _wsSubscription?.cancel();
      _wsSubscription = _wsChannel!.stream.listen(
        (message) {
          try {
            _lastWebSocketMessageAt = DateTime.now();
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            final type = json['type'] as String?;

            if (type == 'pong') {
              // Compute round-trip latency from the last ping we sent.
              // The server replies to every ping with one pong (see
              // [_startWebSocketHeartbeat] and the matching server-side
              // handler), so the most recent _pendingPingSentAt is the
              // right reference point.
              final sentAt = _pendingPingSentAt;
              if (sentAt != null) {
                final latency = DateTime.now().difference(sentAt);
                _lastLatency = latency;
                _pendingPingSentAt = null;
                if (!_latencyController.isClosed) {
                  _latencyController.add(latency);
                }
              }
              return;
            }

            if (type == 'ping') {
              _wsChannel?.sink.add(jsonEncode({
                'type': 'pong',
                'timestamp': DateTime.now().toUtc().toIso8601String(),
              }));
              return;
            }

            if (type == 'collaboration_state') {
              return;
            }

            // Route push notifications to the dedicated stream
            if (type == 'push_notification') {
              _pushNotificationController.add(json);
              return;
            }

            // P1-1: server-driven advisory that the seq cursor we sent on
            // the upgrade request is no longer usable (instance changed,
            // or we asked for an event the ring buffer has already
            // evicted). The socket stays open — only the replay request
            // failed — so we drop our cached cursor, adopt whatever the
            // server's current instance is, and synthesize a
            // BackendReconnected event so downstream providers refetch
            // their cached state.
            if (type == 'resync_required') {
              final reason = json['reason'] as String? ?? 'unknown';
              final currentSeq = json['currentSeq'];
              final currentInstance = json['currentInstance'] as String?;
              developer.log(
                '[NetworkBackend] resync_required: reason=$reason '
                'currentSeq=$currentSeq currentInstance=$currentInstance',
                name: 'NetworkBackend',
                level: 900,
              );
              _lastSeenEventSeq = null;
              if (currentInstance != null && currentInstance.isNotEmpty) {
                _serverInstanceId = currentInstance;
                _previousServerInstanceId = currentInstance;
              }
              _eventController.add(NightshadeEvent(
                timestamp: DateTime.now().millisecondsSinceEpoch,
                category: EventCategory.system,
                eventType: 'BackendReconnected',
                severity: EventSeverity.info,
                data: {
                  'message': 'Server requested resync',
                  'reason': reason,
                  if (currentSeq != null) 'currentSeq': currentSeq,
                  if (currentInstance != null) 'currentInstance': currentInstance,
                },
              ));
              return;
            }

            final event = _eventFromJson(json);
            _trackEventSeq(event, isReplay: json['replay'] == true);
            _handleEventSideEffects(event);
            _eventController.add(event);

            // Route polar alignment events to the dedicated stream
            if (event.category == EventCategory.polarAlignment) {
              _polarAlignController.add(event.data);
            }
          } catch (e) {
            developer.log('Error parsing WebSocket message: $e',
                name: 'NetworkBackend', level: 900, error: e);
          }
        },
        onError: (error) {
          developer.log('WebSocket error: $error',
              name: 'NetworkBackend', level: 1000, error: error);
          _eventController.addError(error);
          _handleConnectionFailure();
        },
        onDone: () {
          developer.log('WebSocket connection closed',
              name: 'NetworkBackend', level: 900);
          _handleConnectionFailure();
        },
      );

      // Connection successful
      _updateConnectionState(BackendConnectionState.connected);
      _hasEverConnected = true;
      final wasReconnect = _reconnectAttempt > 0;
      _reconnectAttempt = 0; // Reset reconnect counter on success
      developer.log('[NetworkBackend] WebSocket connected successfully',
          name: 'NetworkBackend', level: 800);
      _startWebSocketHeartbeat();

      // P2-2: identify ourselves as a collaboration viewer immediately
      // after the handshake completes (auth is already validated by the
      // upgrade gate above). The server may override `viewerId` with the
      // authenticated principal's digest (P2-15) — we still send a value
      // so legacy hosts that lack the override keep working unchanged.
      _sendCollaborationJoin();

      // After a reconnect (not the initial connect), emit a synthetic event
      // so downstream providers know the connection is back and can refresh
      // their cached state. Events that occurred while disconnected are lost,
      // so UI components watching this stream should re-fetch latest state.
      if (wasReconnect) {
        _eventController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          category: EventCategory.system,
          eventType: 'BackendReconnected',
          severity: EventSeverity.info,
          data: const {'message': 'WebSocket reconnected'},
        ));
      }
    } catch (e) {
      developer.log('Failed to connect WebSocket: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      _handleConnectionFailure();
    }
  }

  /// Handle connection failures with exponential backoff
  void _handleConnectionFailure() {
    if (_disposed) {
      return;
    }
    _stopWebSocketHeartbeat();
    if (_connectionState == BackendConnectionState.disconnected &&
        _reconnectTimer != null) {
      return;
    }
    _updateConnectionState(BackendConnectionState.disconnected);

    // Calculate exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
    final delay = Duration(
      seconds: [
        1,
        2,
        4,
        8,
        16,
        _maxReconnectDelay
      ][_reconnectAttempt.clamp(0, 5)],
    );

    _reconnectAttempt++;
    developer.log(
        '[NetworkBackend] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt)',
        name: 'NetworkBackend',
        level: 800);

    _reconnectTimer = Timer(delay, () {
      if (_connectionState != BackendConnectionState.connected) {
        developer.log('[NetworkBackend] Attempting reconnection...',
            name: 'NetworkBackend', level: 800);
        connect();
      }
    });
  }

  void _startWebSocketHeartbeat() {
    _stopWebSocketHeartbeat();
    if (webSocketHeartbeatInterval <= Duration.zero) {
      return;
    }

    _webSocketHeartbeatTimer = Timer.periodic(webSocketHeartbeatInterval, (_) {
      final lastMessageAt = _lastWebSocketMessageAt;
      if (lastMessageAt != null &&
          DateTime.now().difference(lastMessageAt) >
              webSocketHeartbeatTimeout) {
        developer.log('[NetworkBackend] WebSocket heartbeat timed out',
            name: 'NetworkBackend', level: 900);
        _wsSubscription?.cancel();
        _wsSubscription = null;
        _wsChannel?.sink.close();
        _wsChannel = null;
        _handleConnectionFailure();
        return;
      }

      try {
        // Record the send timestamp BEFORE adding to the sink so that even
        // if the sink call yields, the pong-handler will see a consistent
        // value to subtract from. Overwriting any previous unmatched ping
        // is intentional: if we send a new ping while the prior pong is
        // still in flight, the older measurement is stale and the newer
        // one is what the operator cares about.
        _pendingPingSentAt = DateTime.now();
        _wsChannel?.sink.add(jsonEncode({
          'type': 'ping',
          'timestamp': _pendingPingSentAt!.toUtc().toIso8601String(),
        }));
      } catch (e) {
        // Don't leave a stale pending-ping timestamp behind on send failure;
        // a future successful ping would otherwise be computed against the
        // wrong sentAt and emit a wildly inflated latency.
        _pendingPingSentAt = null;
        developer.log('[NetworkBackend] Failed to send WebSocket heartbeat: $e',
            name: 'NetworkBackend', level: 900, error: e);
        _handleConnectionFailure();
      }
    });
  }

  void _stopWebSocketHeartbeat() {
    _webSocketHeartbeatTimer?.cancel();
    _webSocketHeartbeatTimer = null;
    // Drop the in-flight ping timestamp so a stale send doesn't get
    // matched against a pong from a later connection.
    _pendingPingSentAt = null;
    // Drop the cached latency so the UI doesn't display a stale value
    // while we're trying to reconnect. The next pong on a fresh
    // connection will repopulate it.
    _lastLatency = null;
  }

  /// Disconnect from the server.
  ///
  /// P2-2: emits a `collaboration.leave` frame BEFORE tearing down the
  /// socket so the server can release our viewer slot promptly rather
  /// than waiting for the WS-close handler to run. The leave is best-
  /// effort: if the sink is already dead (server crashed, network
  /// dropped) the send throws and we proceed with teardown — the
  /// server-side `onDone` handler is the backstop.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sendCollaborationLeave();
    _stopWebSocketHeartbeat();
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _wsChannel?.sink.close();
    _wsChannel = null;
    _updateConnectionState(BackendConnectionState.disconnected);
  }

  /// P2-2: send a `collaboration.join` frame on the open WebSocket.
  ///
  /// Called immediately after the upgrade handshake completes. Tolerates
  /// a missing identity (caller didn't call [setCollaborationIdentity]
  /// before [connect]) — when the viewerId is null we skip the send and
  /// log a warning, because a join with no id will be rejected by the
  /// server when auth is disabled (the server otherwise overrides it
  /// with the authenticated principal's digest, in which case the id we
  /// send doesn't matter).
  ///
  /// Send failures are logged but do not tear down the socket: the
  /// downstream event flow is independent of the collaboration slot, and
  /// a failed join just means the operator's viewer chip won't show this
  /// device — far less serious than killing the WS.
  void _sendCollaborationJoin() {
    final channel = _wsChannel;
    if (channel == null) return;
    final displayName = _collaborationDisplayName;
    final viewerId = _collaborationViewerId;
    final deviceName = _collaborationDeviceName;
    if (displayName == null || displayName.isEmpty) {
      developer.log(
        '[NetworkBackend] Skipping collaboration.join: no display name set '
        '(call setCollaborationIdentity before connect)',
        name: 'NetworkBackend',
        level: 900,
      );
      return;
    }
    try {
      // The server requires `name` (rejects an empty payload with an
      // error frame). We also send `viewerId` and `deviceName` — the
      // server overrides `viewerId` from the auth context when present
      // but still logs an impersonation warning if the value we send
      // disagrees. Sending the same value the auth path will derive is
      // therefore the correct behaviour even though the server's
      // override makes it functionally redundant.
      channel.sink.add(jsonEncode({
        'type': 'collaboration.join',
        if (viewerId != null && viewerId.isNotEmpty) 'viewerId': viewerId,
        if (deviceName != null && deviceName.isNotEmpty) 'deviceName': deviceName,
        'name': displayName,
      }));
    } catch (e) {
      developer.log(
        '[NetworkBackend] Failed to send collaboration.join: $e',
        name: 'NetworkBackend',
        level: 900,
        error: e,
      );
    }
  }

  /// P2-2: send a `collaboration.leave` frame, best-effort. Called from
  /// [disconnect] before the sink is closed.
  void _sendCollaborationLeave() {
    final channel = _wsChannel;
    if (channel == null) return;
    final viewerId = _collaborationViewerId;
    if (viewerId == null || viewerId.isEmpty) {
      return;
    }
    try {
      channel.sink.add(jsonEncode({
        'type': 'collaboration.leave',
        'viewerId': viewerId,
      }));
    } catch (e) {
      // Closing-time failure is expected on a dead socket; log at FINE.
      developer.log(
        '[NetworkBackend] collaboration.leave send failed (socket likely '
        'already closed): $e',
        name: 'NetworkBackend',
        level: 700,
      );
    }
  }

  /// Dispose resources
  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _stopWebSocketHeartbeat();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _httpClient.close(force: true);
    if (_ownsHttpClient) {
      _http.close();
    }
    _eventController.close();
    _connectionStateController.close();
    _polarAlignController.close();
    _pushNotificationController.close();
    _latencyController.close();
  }

  @override
  Stream<NightshadeEvent> get eventStream => _eventController.stream;

  void _handleEventSideEffects(NightshadeEvent event) {
    if (event.category == EventCategory.equipment &&
        event.eventType == 'PropertyChanged' &&
        event.data['property'] == 'device_change') {
      developer.log(
        '[NetworkBackend] Device-change event invalidating discovery cache',
        name: 'NetworkBackend',
        level: 800,
      );
      invalidateDeviceCache();
    }
  }

  /// P1-1: update the cached seq cursor + server instance after parsing an
  /// event. Detects three conditions:
  ///
  /// 1. A gap (received seq > expected seq + 1) — log a warning so the
  ///    operator and tests can see that events were lost. The cursor still
  ///    advances to the received seq so we don't wedge waiting for the
  ///    missing ones.
  ///
  /// 2. An instance-id change (server restarted mid-WS, which is rare
  ///    because the WS dies when the server dies) — log, reset the
  ///    cursor, emit BackendReconnected so providers refetch.
  ///
  /// 3. The first time we see a serverInstanceId — adopt it as our
  ///    attachment cursor.
  void _trackEventSeq(NightshadeEvent event, {required bool isReplay}) {
    if (isReplay) {
      developer.log(
        '[NetworkBackend] Replayed event seq=${event.seq} '
        'type=${event.eventType}',
        name: 'NetworkBackend',
        level: 700,
      );
    }

    final eventSeq = event.seq;
    final eventInstance = event.serverInstanceId;

    if (eventInstance != null && eventInstance.isNotEmpty) {
      final cached = _serverInstanceId;
      if (cached != null && cached != eventInstance) {
        developer.log(
          '[NetworkBackend] Server instance changed mid-stream '
          '(old=$cached, new=$eventInstance); resetting seq cursor.',
          name: 'NetworkBackend',
          level: 900,
        );
        _lastSeenEventSeq = null;
        _serverInstanceId = eventInstance;
        _previousServerInstanceId = eventInstance;
        _eventController.add(NightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          category: EventCategory.system,
          eventType: 'BackendReconnected',
          severity: EventSeverity.info,
          data: {
            'message': 'Server instance changed mid-stream',
            'previousInstance': cached,
            'currentInstance': eventInstance,
          },
        ));
      } else if (cached == null) {
        _serverInstanceId = eventInstance;
        _previousServerInstanceId = eventInstance;
      }
    }

    if (eventSeq != null) {
      final previous = _lastSeenEventSeq;
      if (previous != null && eventSeq > previous + 1) {
        final lost = eventSeq - previous - 1;
        developer.log(
          '[NetworkBackend] Event seq gap: expected ${previous + 1}, '
          'got $eventSeq (lost $lost events)',
          name: 'NetworkBackend',
          level: 900,
        );
      }
      _lastSeenEventSeq = eventSeq;
    }
  }

  /// Stream of push notifications received from the desktop server.
  ///
  /// Each map contains 'title', 'body', 'priority', 'eventType', 'category',
  /// and 'timestamp' fields as sent by PushNotificationService.
  Stream<Map<String, dynamic>> get pushNotificationStream =>
      _pushNotificationController.stream;

  // =========================================================================
  // HTTP Helper Methods
  // =========================================================================

  String _nextRequestId(String endpoint) {
    _requestCounter = (_requestCounter + 1) % 0xFFFFF;
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final seq = _requestCounter.toRadixString(36);
    final safeEndpoint = endpoint
        .replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '')
        .toLowerCase();
    return 'nb-$ts-$seq-${safeEndpoint.isEmpty ? 'request' : safeEndpoint}';
  }

  /// Add authentication, compatibility, and trace headers to HTTP requests.
  Map<String, String> _addAuthHeaders(
    Map<String, String> headers, {
    required String endpoint,
  }) {
    headers[RemoteApiCompatibility.apiVersionHeader] =
        RemoteApiCompatibility.clientApiVersion.format();
    headers[_requestIdHeader] = _nextRequestId(endpoint);
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  /// Determine if an HTTP exception is a transient failure that can be retried
  bool _isTransientFailure(dynamic error) {
    // Check for structured NightshadeError
    if (error is dart_error.NightshadeError) {
      return error.isRecoverable;
    }
    // [Wave 6D error parsing] — the headless envelope's httpStatus tells
    // us whether the request should be retried. Mirror the same status
    // ranges as [_isTransientStatusCode] so retry behaviour is
    // consistent whether the failure was decoded into a [ServerError] or
    // a fallback [NightshadeError].
    if (error is ServerError) {
      final status = error.httpStatus;
      if (status != null) {
        return _isTransientStatusCode(status);
      }
      return false;
    }
    if (error is SocketException) {
      // Network errors are transient
      return true;
    }
    if (error is TimeoutException) {
      // Timeouts are transient
      return true;
    }
    if (error is HttpException) {
      // Connection reset, broken pipe, etc.
      return true;
    }
    if (error is Exception) {
      final errorStr = error.toString().toLowerCase();
      // Check for common transient error messages
      if (errorStr.contains('connection') ||
          errorStr.contains('timeout') ||
          errorStr.contains('reset') ||
          errorStr.contains('refused') ||
          errorStr.contains('network')) {
        return true;
      }
    }
    return false;
  }

  /// Check if an HTTP status code indicates a transient failure
  bool _isTransientStatusCode(int statusCode) {
    // 408 Request Timeout, 429 Too Many Requests, 500 Internal Server Error,
    // 502 Bad Gateway, 503 Service Unavailable, 504 Gateway Timeout
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  /// Parse an error response from the server.
  ///
  /// Attempts to parse structured error JSON from the response body.
  /// Falls back to creating an error from the status code and endpoint.
  ///
  /// Return type is [Exception] rather than the narrower
  /// [dart_error.NightshadeError] because the headless server's new
  /// envelope ({code, message, details}) is surfaced as a typed
  /// [ServerError] — see the [Wave 6D error parsing] branch below.
  /// Existing callers `throw` the result so the widened type doesn't
  /// change their behaviour; the retry helper's
  /// `_isTransientFailure` accepts any Object via duck-typing.
  Exception _parseErrorResponse(
    int statusCode,
    String responseBody,
    String method,
    String endpoint,
  ) {
    // Try to parse as structured error JSON
    try {
      final json = jsonDecode(responseBody);
      if (json is Map<String, dynamic>) {
        // [Wave 6D error parsing] — the headless server emits a
        // {code, message, details} envelope on every 4xx/5xx; prefer
        // that shape over the legacy and category formats. The check
        // is positional (both keys, both non-empty strings) so we
        // don't accidentally swallow the richer NightshadeError
        // envelope, which always carries `category`.
        if (!json.containsKey('category')) {
          final serverError =
              ServerError.tryFromJson(json, httpStatus: statusCode);
          if (serverError != null) {
            return serverError;
          }
        }

        // Check for full structured error format
        if (json.containsKey('category') && json.containsKey('message')) {
          return dart_error.NightshadeError.fromJson(json);
        }

        // Check for legacy error format: {error: 'message', message: 'details'}
        if (json.containsKey('error') || json.containsKey('message')) {
          final errorMsg = json['error'] as String? ??
              json['message'] as String? ??
              'Unknown error';
          final detailMsg =
              json['message'] as String? ?? json['details'] as String? ?? '';
          final fullMessage = detailMsg.isNotEmpty && detailMsg != errorMsg
              ? '$errorMsg: $detailMsg'
              : errorMsg;

          return dart_error.NightshadeError.fromString(fullMessage);
        }
      }
    } catch (e, stackTrace) {
      // Why: the server may return a non-JSON body (HTML error page, plain
      // text from a misbehaving proxy, empty body). The structured-error
      // path is best-effort; the HTTP-status fallback below always produces
      // a useful NightshadeError. Logging at FINE keeps the dev console
      // signal-only when servers regularly return non-JSON 5xx pages.
      // Justification: trace-level (500) — diagnostic-only for the
      // best-effort JSON decode path; HTTP-status fallback below is the
      // real error surface.
      developer.log(
        '[NetworkBackend] _parseErrorResponse JSON decode failed '
        '(status=$statusCode endpoint=$endpoint): $e',
        name: 'NetworkBackend',
        level: 500,
        error: e,
        stackTrace: stackTrace,
      );
    }

    // Fallback: create error from HTTP status
    final isTransient = _isTransientStatusCode(statusCode);
    return dart_error.NightshadeError(
      category: statusCode == 404
          ? dart_error.BackendErrorCategory.connection
          : statusCode == 400
              ? dart_error.BackendErrorCategory.validation
              : statusCode == 408 || statusCode == 504
                  ? dart_error.BackendErrorCategory.timeout
                  : dart_error.BackendErrorCategory.system,
      message: 'HTTP $statusCode: $method $endpoint failed',
      isRecoverable: isTransient,
      isTimeout: statusCode == 408 || statusCode == 504,
    );
  }

  /// Retry a request with exponential backoff
  /// Max 3 attempts for transient failures only
  Future<T> _retryableRequest<T>(
    Future<T> Function() request, {
    int maxAttempts = 3,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    int attempt = 0;
    Exception? lastException;

    while (attempt < maxAttempts) {
      try {
        return await request().timeout(timeout);
      } catch (e) {
        lastException = e as Exception;
        attempt++;

        // Check if this is the last attempt
        if (attempt >= maxAttempts) {
          developer.log(
              '[NetworkBackend] Request failed after $maxAttempts attempts: $e',
              name: 'NetworkBackend',
              level: 1000,
              error: e);
          rethrow;
        }

        // Only retry transient failures
        if (!_isTransientFailure(e)) {
          developer.log(
              '[NetworkBackend] Non-transient failure, not retrying: $e',
              name: 'NetworkBackend',
              level: 1000,
              error: e);
          rethrow;
        }

        // Calculate backoff delay: 1s, 2s, 4s
        final delay = Duration(seconds: 1 << (attempt - 1));
        developer.log(
            '[NetworkBackend] Transient failure, retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts): $e',
            name: 'NetworkBackend',
            level: 900,
            error: e);
        await Future.delayed(delay);
      }
    }

    // Should never reach here, but throw last exception just in case
    throw lastException!;
  }

  Future<Map<String, dynamic>> _get(String endpoint,
      [Map<String, dynamic>? queryParams]) async {
    return _retryableRequest(() async {
      final baseUri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');
      final uri = queryParams == null
          ? baseUri
          : baseUri.replace(queryParameters: {
              ...baseUri.queryParameters,
              ...queryParams.map((k, v) => MapEntry(k, v.toString())),
            });

      final headers = _addAuthHeaders({}, endpoint: endpoint);
      final response = await _http.get(uri, headers: headers);

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'GET', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<Map<String, dynamic>> _post(String endpoint,
      [Map<String, dynamic>? body, Map<String, String>? extraHeaders]) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');

      final headers = _addAuthHeaders({}, endpoint: endpoint);
      headers[HttpHeaders.contentTypeHeader] = 'application/json';
      // [Wave 6B settings sync] callers can stamp identification headers
      // (e.g. X-Nightshade-Command-Id) onto the request so server-emitted
      // events can be correlated back to the originating client and that
      // client can drop its own echo.
      if (extraHeaders != null && extraHeaders.isNotEmpty) {
        headers.addAll(extraHeaders);
      }

      final response = await _http.post(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'POST', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<void> _delete(String endpoint) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');

      final headers = _addAuthHeaders({}, endpoint: endpoint);
      final response = await _http.delete(uri, headers: headers);

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'DELETE', endpoint);
      }
    });
  }

  Future<Map<String, dynamic>> _put(String endpoint,
      [Map<String, dynamic>? body]) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');

      final headers = _addAuthHeaders({}, endpoint: endpoint);
      headers[HttpHeaders.contentTypeHeader] = 'application/json';

      final response = await _http.put(
        uri,
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'PUT', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<Uint8List> _downloadBytes(
    String endpoint, [
    Map<String, dynamic>? queryParams,
  ]) async {
    final downloaded = await _downloadBytesWithHeaders(endpoint, queryParams);
    return downloaded.bytes;
  }

  Future<({Uint8List bytes, Map<String, String> headers})>
      _downloadBytesWithHeaders(
    String endpoint, [
    Map<String, dynamic>? queryParams,
  ]) async {
    return _retryableRequest(() async {
      final baseUri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');
      final uri = queryParams == null
          ? baseUri
          : baseUri.replace(queryParameters: {
              ...baseUri.queryParameters,
              ...queryParams.map((k, v) => MapEntry(k, v.toString())),
            });
      final headers = _addAuthHeaders({}, endpoint: endpoint);

      final response = await _http.get(uri, headers: headers);
      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'GET', endpoint);
      }
      return (
        bytes: response.bodyBytes,
        headers: Map<String, String>.from(response.headers),
      );
    });
  }

  Never _throwHostOnlyRemoteProcessing(String operation) {
    throw dart_error.NightshadeError(
      category: dart_error.BackendErrorCategory.validation,
      message:
          '$operation is host-only over the remote API. Use a host-authoritative '
          'endpoint (for example GET /api/camera/last-image/jpeg or '
          'POST /api/imaging/save-fits-from-capture).',
    );
  }

  Future<Map<String, dynamic>> _postRaw(
    String endpoint,
    Map<String, dynamic> queryParams,
    Uint8List bytes, {
    String contentType = 'application/octet-stream',
  }) async {
    return _retryableRequest(() async {
      final uri =
          Uri.parse('http://$serverHost:$serverPort/api/$endpoint').replace(
        queryParameters:
            queryParams.map((key, value) => MapEntry(key, value.toString())),
      );

      final headers = _addAuthHeaders({}, endpoint: endpoint);
      headers[HttpHeaders.contentTypeHeader] = contentType;

      final response = await _http.post(uri, headers: headers, body: bytes);

      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'POST', endpoint);
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  Future<Uint8List> _postRawBytes(
    String endpoint,
    Map<String, dynamic> body,
  ) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');

      final headers = _addAuthHeaders({}, endpoint: endpoint);
      headers[HttpHeaders.contentTypeHeader] = 'application/json';

      final response = await _http.post(
        uri,
        headers: headers,
        body: jsonEncode(body),
      );
      if (response.statusCode != 200) {
        throw _parseErrorResponse(
            response.statusCode, response.body, 'POST', endpoint);
      }
      return response.bodyBytes;
    });
  }

  List<T> _rowsFromJson<T>(
    Object? source,
    T Function(Map<String, dynamic>) decoder,
  ) {
    final rows = source as List? ?? const [];
    return rows
        .whereType<Map>()
        .map((row) => decoder(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  // =========================================================================
  // Device Discovery & Connection
  // =========================================================================

  // Cache for device discovery to prevent redundant API calls
  List<Map<String, dynamic>>? _cachedDevices;
  DateTime? _cacheTimestamp;
  static const _cacheDuration = Duration(seconds: 30);
  Future<List<Map<String, dynamic>>>? _ongoingDiscovery;

  @override
  Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType) async {
    // Check if we have a valid cache
    if (_cachedDevices != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration) {
      developer.log(
          '[NetworkBackend] Using cached device list (${_cachedDevices!.length} devices)',
          name: 'NetworkBackend',
          level: 800);
    } else if (_ongoingDiscovery != null) {
      // Another discovery is in progress, wait for it
      developer.log('[NetworkBackend] Waiting for ongoing discovery...',
          name: 'NetworkBackend', level: 800);
      _cachedDevices = await _ongoingDiscovery!;
    } else {
      // Start new discovery
      developer.log('[NetworkBackend] Starting new device discovery...',
          name: 'NetworkBackend', level: 800);
      _ongoingDiscovery = _fetchDevicesFromServer();
      try {
        _cachedDevices = await _ongoingDiscovery!;
        _cacheTimestamp = DateTime.now();
        developer.log(
            '[NetworkBackend] Cached ${_cachedDevices!.length} devices',
            name: 'NetworkBackend',
            level: 800);
      } finally {
        _ongoingDiscovery = null;
      }
    }

    final deviceList = _cachedDevices ?? [];

    // Filter by requested type and convert
    final filtered = deviceList
        .where((d) {
          final typeValue = d['deviceType'] ?? d['type'];
          if (typeValue is! String) {
            return false;
          }
          return _normalizeDeviceType(typeValue) ==
              _normalizeDeviceType(deviceType.name);
        })
        .map((d) => DeviceInfo(
              id: d['id'] as String,
              name: d['name'] as String,
              deviceType: deviceType,
              driverType: _parseDriverType(d['driverType'] as String),
              description: d['description'] as String? ?? '',
              driverVersion: d['driverVersion'] as String? ?? '',
            ))
        .toList();

    developer.log(
        '[NetworkBackend] Returning ${filtered.length} ${deviceType.name} devices',
        name: 'NetworkBackend',
        level: 800);
    return filtered;
  }

  String _normalizeDeviceType(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<List<Map<String, dynamic>>> _fetchDevicesFromServer() async {
    final response = await _get('devices');
    return (response['devices'] as List? ??
            response['available'] as List? ??
            [])
        .cast<Map<String, dynamic>>();
  }

  /// Invalidate device cache (called when "Scan Network" is clicked)
  void invalidateDeviceCache() {
    developer.log('[NetworkBackend] Cache invalidated',
        name: 'NetworkBackend', level: 800);
    _cachedDevices = null;
    _cacheTimestamp = null;
  }

  @override
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port) async {
    final response = await _get('devices/discover-indi', {
      'host': host,
      'port': port.toString(),
    });

    final devices = (response['devices'] as List?) ?? const [];
    return devices
        .map((d) => DeviceInfo(
              id: d['id'] as String? ?? '',
              name: d['name'] as String? ?? '',
              deviceType: DeviceType.values.firstWhere(
                (t) => t.name == (d['deviceType'] as String?),
                orElse: () => DeviceType.camera,
              ),
              driverType: DriverType.values.firstWhere(
                (t) => t.name == (d['driverType'] as String?),
                orElse: () => DriverType.indi,
              ),
              description: d['description'] as String? ?? '',
              driverVersion: d['driverVersion'] as String? ?? '',
            ))
        .toList();
  }

  @override
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(
      String host, int port) async {
    final response = await _get('devices/discover-alpaca', {
      'host': host,
      'port': port.toString(),
    });

    final devices = (response['devices'] as List?) ?? const [];
    return devices
        .map((d) => DeviceInfo(
              id: d['id'] as String? ?? '',
              name: d['name'] as String? ?? '',
              deviceType: DeviceType.values.firstWhere(
                (t) => t.name == (d['deviceType'] as String?),
                orElse: () => DeviceType.camera,
              ),
              driverType: DriverType.values.firstWhere(
                (t) => t.name == (d['driverType'] as String?),
                orElse: () => DriverType.alpaca,
              ),
              description: d['description'] as String? ?? '',
              driverVersion: d['driverVersion'] as String? ?? '',
            ))
        .toList();
  }

  @override
  Future<void> connectDevice(DeviceType deviceType, String deviceId) async {
    await _post('devices/connect', {
      'deviceType': deviceType.name,
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> disconnectDevice(DeviceType deviceType, String deviceId) async {
    await _post('devices/disconnect', {
      'deviceType': deviceType.name,
      'deviceId': deviceId,
    });
  }

  @override
  Future<List<DeviceInfo>> getConnectedDevices() async {
    final response = await _get('devices/connected');
    final deviceList = response['devices'] as List;

    return deviceList
        .cast<Map<String, dynamic>>()
        .map(DeviceInfo.fromJson)
        .toList();
  }

  // =========================================================================
  // Camera Control
  // =========================================================================

  @override
  Future<void> cameraStartExposure({
    required String deviceId,
    required double exposureTime,
    required FrameType frameType,
    int? gain,
    int? offset,
    int binX = 1,
    int binY = 1,
    int? x,
    int? y,
    int? width,
    int? height,
  }) async {
    await _post('camera/expose', {
      'deviceId': deviceId,
      'exposureTime': exposureTime,
      'frameType': frameType.name,
      if (gain != null) 'gain': gain,
      if (offset != null) 'offset': offset,
      'binX': binX,
      'binY': binY,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    });
  }

  @override
  Future<void> cameraAbortExposure(String deviceId) async {
    await _post('camera/abort', {'deviceId': deviceId});
  }

  @override
  Future<Uint8List> cameraLiveViewFrame(String deviceId) async {
    try {
      return await _downloadBytes(
        'camera/live-view/frame',
        {'deviceId': deviceId},
      );
    } on ServerError catch (e) {
      // [Wave 6D error parsing] — prefer the machine-readable `code` over
      // the substring-match on `message`. The server emits
      // `live_view_unavailable` when the driver doesn't support live
      // view, and the underlying 503 is surfaced via httpStatus.
      if (e.code == 'live_view_unavailable' ||
          e.code == 'not_supported' ||
          e.httpStatus == 503) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.validation,
          message: e.message,
        );
      }
      rethrow;
    } on dart_error.NightshadeError catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('503') ||
          msg.contains('live_view_unavailable') ||
          msg.contains('not supported')) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.validation,
          message: e.message,
        );
      }
      rethrow;
    }
  }

  @override
  Future<CapturedImageResult?> cameraGetLastImage(String deviceId) async {
    try {
      final downloaded = await _downloadBytesWithHeaders(
        'camera/last-image/jpeg',
        {'deviceId': deviceId},
      );
      final metaHeader = _headerValue(downloaded.headers, 'x-image-meta');
      if (metaHeader == null || metaHeader.isEmpty) {
        throw dart_error.NightshadeError(
          category: dart_error.BackendErrorCategory.validation,
          message:
              'GET /api/camera/last-image/jpeg missing x-image-meta header',
        );
      }
      return capturedImageFromRemoteJpegWire(
        jpegBytes: downloaded.bytes,
        metaHeaderBase64: metaHeader,
      );
    } on ServerError catch (e) {
      // [Wave 6D error parsing] — treat 404 or the explicit `no_image`
      // envelope code as "no image cached yet" and return null instead
      // of bubbling an exception. Anything else is a real failure.
      if (e.httpStatus == 404 || e.code == 'no_image') {
        return null;
      }
      rethrow;
    } on dart_error.NightshadeError catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('404') || msg.contains('no_image')) {
        return null;
      }
      rethrow;
    }
  }

  String? _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  @override
  Future<void> cameraSetCooling({
    required String deviceId,
    required bool enabled,
    double? targetTemp,
  }) async {
    await _post('camera/cooling', {
      'deviceId': deviceId,
      'enabled': enabled,
      if (targetTemp != null) 'targetTemp': targetTemp,
    });
  }

  @override
  Future<void> cameraSetReadoutMode(String deviceId, int modeIndex) async {
    await _post('camera/readoutMode', {
      'deviceId': deviceId,
      'modeIndex': modeIndex,
    });
  }

  @override
  Future<void> cameraSetGain(String deviceId, int gain) async {
    await _post('camera/gain', {
      'deviceId': deviceId,
      'gain': gain,
    });
  }

  @override
  Future<void> cameraSetOffset(String deviceId, int offset) async {
    await _post('camera/offset', {
      'deviceId': deviceId,
      'offset': offset,
    });
  }

  @override
  Future<CameraRecommendedSettings> cameraGetRecommendedSettings(
      String deviceId) async {
    // Network backend: the remote host owns the SDK. Query it via the
    // headless API, parsing the same struct shape Rust returns.
    //
    // Fallback policy — "errors are a feature":
    //   * HTTP 404 / `not_implemented` code → older host that predates this
    //     route. Return an empty recommendation; the user can still set
    //     values manually from the profile editor. This is logged.
    //   * Anything else (timeout, malformed JSON, 5xx, transport failure)
    //     rethrows so the UI shows a real error rather than silently
    //     pretending the device has no recommendation.
    try {
      final response = await _get('camera/recommended-settings', {
        'deviceId': deviceId,
      });
      return CameraRecommendedSettings(
        unityGain: (response['unityGain'] as num?)?.toInt(),
        hcgGain: (response['hcgGain'] as num?)?.toInt(),
        defaultOffset: (response['defaultOffset'] as num?)?.toInt(),
        notes: (response['notes'] as String?) ?? '',
      );
    } on ServerError catch (e) {
      if (e.httpStatus == 404 || e.code == 'not_implemented') {
        developer.log(
          'cameraGetRecommendedSettings not implemented on remote '
          '(${e.code}, HTTP ${e.httpStatus}); returning empty recommendation',
          name: 'NetworkBackend',
          level: 900, // WARNING
        );
        return const CameraRecommendedSettings(notes: '');
      }
      rethrow;
    } on dart_error.NightshadeError catch (e) {
      // `_parseErrorResponse` falls back to a `NightshadeError` with
      // `BackendErrorCategory.connection` for HTTP 404 when the body
      // isn't a recognized error envelope. Treat that specific shape as
      // "route missing" too — any other category propagates.
      if (e.category == dart_error.BackendErrorCategory.connection &&
          e.message.contains('HTTP 404')) {
        developer.log(
          'cameraGetRecommendedSettings route 404 on remote '
          '(${e.message}); returning empty recommendation',
          name: 'NetworkBackend',
          level: 900, // WARNING
        );
        return const CameraRecommendedSettings(notes: '');
      }
      rethrow;
    }
  }

  // =========================================================================
  // Mount Control
  // =========================================================================

  @override
  Future<void> mountSlewToCoordinates(
      String deviceId, double ra, double dec) async {
    await _post('mount/slew', {
      'deviceId': deviceId,
      'ra': ra,
      'dec': dec,
    });
  }

  @override
  Future<void> mountSync(String deviceId, double ra, double dec) async {
    await _post('mount/sync', {
      'deviceId': deviceId,
      'ra': ra,
      'dec': dec,
    });
  }

  @override
  Future<void> mountPark(String deviceId) async {
    await _post('mount/park', {'deviceId': deviceId});
  }

  @override
  Future<void> mountUnpark(String deviceId) async {
    await _post('mount/unpark', {'deviceId': deviceId});
  }

  @override
  Future<void> mountSetTracking(String deviceId, bool enabled) async {
    await _post('mount/tracking', {
      'deviceId': deviceId,
      'enabled': enabled,
    });
  }

  @override
  Future<void> mountPulseGuide({
    required String deviceId,
    required String direction,
    required int durationMs,
  }) async {
    await _post('mount/pulse-guide', {
      'deviceId': deviceId,
      'direction': direction,
      'durationMs': durationMs,
    });
  }

  @override
  Future<void> mountAbort(String deviceId) async {
    await _post('mount/abort', {'deviceId': deviceId});
  }

  @override
  Future<dynamic> mountGetStatus(String deviceId) async {
    return await _get('mount/status', {'deviceId': deviceId});
  }

  @override
  Future<void> mountSetTrackingRate(String deviceId, int rate) async {
    await _post('mount/set-tracking-rate', {
      'deviceId': deviceId,
      'rate': rate,
    });
  }

  @override
  Future<void> mountMoveAxis(String deviceId, int axis, double rate) async {
    await _post('mount/move-axis', {
      'deviceId': deviceId,
      'axis': axis,
      'rate': rate,
    });
  }

  @override
  Future<void> mountSlewAltAz(
      String deviceId, double altitude, double azimuth) async {
    await _post('mount/slew-alt-az', {
      'deviceId': deviceId,
      'altitude': altitude,
      'azimuth': azimuth,
    });
  }

  @override
  Future<void> mountFindHome(String deviceId) async {
    await _post('mount/find-home', {'deviceId': deviceId});
  }

  // =========================================================================
  // Focuser Control
  // =========================================================================

  @override
  Future<void> focuserMoveTo(String deviceId, int position) async {
    await _post('focuser/move-to', {
      'deviceId': deviceId,
      'position': position,
    });
  }

  @override
  Future<void> focuserMoveRelative(String deviceId, int delta) async {
    await _post('focuser/move-relative', {
      'deviceId': deviceId,
      'delta': delta,
    });
  }

  @override
  Future<void> focuserHalt(String deviceId) async {
    await _post('focuser/halt', {'deviceId': deviceId});
  }

  @override
  Future<AutofocusResult> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
    String curveFitting = 'Hyperbolic',
    int numberOfAttempts = 1,
    int exposuresPerPoint = 1,
    double rSquaredThreshold = 0.7,
    double outerCropRatio = 1.0,
    double innerCropRatio = 0.0,
    int useBrightestNStars = 0,
    int focuserSettleTimeMs = 500,
    String backlashCompMethod = 'Overshoot',
    int backlashIn = 350,
    int backlashOut = 0,
  }) async {
    final response = await _post('focuser/autofocus/start', {
      'deviceId': deviceId,
      'cameraId': cameraId,
      'exposureTime': exposureTime,
      'stepSize': stepSize,
      'stepsOut': stepsOut,
      'method': method,
      'binning': binning,
      'curveFitting': curveFitting,
      'numberOfAttempts': numberOfAttempts,
      'exposuresPerPoint': exposuresPerPoint,
      'rSquaredThreshold': rSquaredThreshold,
      'outerCropRatio': outerCropRatio,
      'innerCropRatio': innerCropRatio,
      'useBrightestNStars': useBrightestNStars,
      'focuserSettleTimeMs': focuserSettleTimeMs,
      'backlashCompMethod': backlashCompMethod,
      'backlashIn': backlashIn,
      'backlashOut': backlashOut,
    });

    // Parse using pure Dart types from JSON
    return AutofocusResult.fromJson(response);
  }

  @override
  Future<void> autofocusCancel() async {
    await _post('focuser/autofocus/cancel');
  }

  // =========================================================================
  // Filter Wheel Control
  // =========================================================================

  @override
  Future<void> filterWheelSetPosition(String deviceId, int position) async {
    await _post('filter-wheel/position', {
      'deviceId': deviceId,
      'position': position,
    });
  }

  @override
  Future<List<String>> filterWheelGetNames(String deviceId) async {
    final response = await _get('filter-wheel/names', {'deviceId': deviceId});
    return (response['names'] as List).cast<String>();
  }

  @override
  Future<void> filterWheelSetByName(String deviceId, String name) async {
    await _post('filter-wheel/set-by-name', {
      'deviceId': deviceId,
      'name': name,
    });
  }

  /// P2-7 — fetch the current filter-wheel slot, slot name, and
  /// in-motion flag from the headless server. Not on
  /// [NightshadeBackend] because the local FfiBackend already exposes
  /// the same data via `filterWheelStateProvider`; the network surface
  /// is the only one that needs an explicit GET.
  Future<RemoteFilterWheelPosition> getFilterWheelPosition() async {
    final response = await _get('filter-wheel/position');
    return RemoteFilterWheelPosition.fromJson(response);
  }

  // =========================================================================
  // Rotator Control
  // =========================================================================

  @override
  Future<void> rotatorMoveTo(String deviceId, double angle) async {
    await _post('rotator/move-to', {
      'deviceId': deviceId,
      'angle': angle,
    });
  }

  @override
  Future<void> rotatorMoveRelative(String deviceId, double delta) async {
    await _post('rotator/move-relative', {
      'deviceId': deviceId,
      'delta': delta,
    });
  }

  @override
  Future<double> rotatorGetAngle(String deviceId) async {
    final response = await _get('rotator/status', {'deviceId': deviceId});
    return (response['position'] as num).toDouble();
  }

  @override
  Future<void> rotatorHalt(String deviceId) async {
    await _post('rotator/halt', {
      'deviceId': deviceId,
    });
  }

  @override
  Future<void> rotatorSyncToPa(String deviceId, double pa) async {
    await _post('rotator/sync', {
      'deviceId': deviceId,
      'positionAngle': pa,
    });
  }

  // =========================================================================
  // PHD2 Guiding
  // =========================================================================

  @override
  Future<void> phd2Connect({String host = 'localhost', int port = 4400}) async {
    await _post('phd2/connect', {
      'host': host,
      'port': port,
    });
  }

  @override
  Future<void> phd2Disconnect() async {
    await _post('phd2/disconnect');
  }

  @override
  Future<void> phd2StartGuiding({
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await _post('phd2/start-guiding', {
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
  }

  @override
  Future<void> phd2StopGuiding() async {
    await _post('phd2/stop-guiding');
  }

  @override
  Future<void> phd2Dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await _post('phd2/dither', {
      'amount': amount,
      'raOnly': raOnly,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
  }

  @override
  Future<Phd2Status> phd2GetStatus() async {
    final response = await _get('phd2/status');
    return Phd2Status(
      state: response['state'] ?? 'Unknown',
      connected: response['connected'] ?? false,
      rmsRa: (response['rmsRa'] as num?)?.toDouble() ?? 0.0,
      rmsDec: (response['rmsDec'] as num?)?.toDouble() ?? 0.0,
      rmsTotal: (response['rmsTotal'] as num?)?.toDouble() ?? 0.0,
      snr: (response['snr'] as num?)?.toDouble() ?? 0.0,
      starMass: (response['starMass'] as num?)?.toDouble() ?? 0.0,
      avgDistance: (response['avgDistance'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  Future<Phd2StarImage> phd2GetStarImage({int size = 50}) async {
    final response = await _get('phd2/star-image', {'size': size});
    // Decode pixels from base64
    final pixelsBase64 = response['pixels'] as String;
    final pixels = base64Decode(pixelsBase64);
    return Phd2StarImage(
      frame: response['frame'] as int,
      width: response['width'] as int,
      height: response['height'] as int,
      starX: (response['starX'] as num).toDouble(),
      starY: (response['starY'] as num).toDouble(),
      pixels: Uint8List.fromList(pixels),
    );
  }

  @override
  Future<List<String>> phd2GetAlgoParamNames({required String axis}) async {
    final response = await _get('phd2/algo-params', {'axis': axis});
    final params = response['params'] as List<dynamic>;
    return params.map((e) => e as String).toList();
  }

  @override
  Future<double> phd2GetAlgoParam({
    required String axis,
    required String name,
  }) async {
    final response =
        await _get('phd2/algo-param', {'axis': axis, 'name': name});
    return (response['value'] as num).toDouble();
  }

  @override
  Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    await _post(
        'phd2/algo-param', {'axis': axis, 'name': name, 'value': value});
  }

  @override
  Future<void> phd2SetPaused(bool paused) async {
    await _post('phd2/pause', {'paused': paused});
  }

  @override
  Future<void> phd2ClearCalibration({String which = 'both'}) async {
    await _post('phd2/clear-calibration', {'which': which});
  }

  @override
  Future<void> phd2FlipCalibration() async {
    await _post('phd2/flip-calibration', {});
  }

  @override
  Future<Phd2CalibrationData> phd2GetCalibrationData() async {
    final response = await _post('phd2/get-calibration-data', {});
    final isCalibrated = response['isCalibrated'] as bool;
    return Phd2CalibrationData(
      isCalibrated: isCalibrated,
      rotationAngle: (response['raAngle'] as num?)?.toDouble(),
      raRate: (response['raRate'] as num?)?.toDouble(),
      decRate: (response['decRate'] as num?)?.toDouble(),
      calibratedAt: isCalibrated ? DateTime.now() : null,
    );
  }

  @override
  Future<(double, double)> phd2FindStar() async {
    final response = await _post('phd2/find-star', {});
    return (
      (response['x'] as num).toDouble(),
      (response['y'] as num).toDouble(),
    );
  }

  @override
  Future<void> phd2SetLockPosition({
    required double x,
    required double y,
    bool exact = false,
  }) async {
    await _post('phd2/set-lock-position', {'x': x, 'y': y, 'exact': exact});
  }

  @override
  Future<(double, double)> phd2GetLockPosition() async {
    final response = await _get('phd2/lock-position');
    return (
      (response['x'] as num).toDouble(),
      (response['y'] as num).toDouble(),
    );
  }

  @override
  Future<void> phd2Loop() async {
    await _post('phd2/loop', {});
  }

  @override
  Future<void> phd2DeselectStar() async {
    await _post('phd2/deselect-star', {});
  }

  // =========================================================================
  // Generic Guiding (driver-agnostic abstraction)
  // =========================================================================

  @override
  Future<void> guiderStartGuiding({
    required String deviceId,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await _post('guider/start-guiding', {
      'deviceId': deviceId,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
  }

  @override
  Future<void> guiderStopGuiding({required String deviceId}) async {
    await _post('guider/stop-guiding', {'deviceId': deviceId});
  }

  @override
  Future<void> guiderDither({
    required String deviceId,
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.0,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    await _post('guider/dither', {
      'deviceId': deviceId,
      'amount': amount,
      'raOnly': raOnly,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
    });
  }

  @override
  Future<void> guiderLoop({required String deviceId}) async {
    await _post('guider/loop', {'deviceId': deviceId});
  }

  @override
  Future<(double, double)> guiderFindStar({required String deviceId}) async {
    final response = await _post('guider/find-star', {'deviceId': deviceId});
    return (
      (response['x'] as num).toDouble(),
      (response['y'] as num).toDouble(),
    );
  }

  @override
  Future<void> guiderSetLockPosition({
    required String deviceId,
    required double x,
    required double y,
    bool exact = false,
  }) async {
    await _post('guider/set-lock-position', {
      'deviceId': deviceId,
      'x': x,
      'y': y,
      'exact': exact,
    });
  }

  @override
  Future<(double, double)> guiderGetLockPosition(
      {required String deviceId}) async {
    final response = await _get(
        'guider/lock-position?deviceId=${Uri.encodeQueryComponent(deviceId)}');
    return (
      (response['x'] as num).toDouble(),
      (response['y'] as num).toDouble(),
    );
  }

  @override
  Future<void> guiderDeselectStar({required String deviceId}) async {
    await _post('guider/deselect-star', {'deviceId': deviceId});
  }

  @override
  Future<Phd2StarImage> guiderGetStarImage({
    required String deviceId,
    int size = 50,
  }) async {
    final response = await _get(
      'guider/star-image?deviceId=${Uri.encodeQueryComponent(deviceId)}&size=$size',
    );
    return Phd2StarImage(
      frame: response['frame'] as int,
      width: response['width'] as int,
      height: response['height'] as int,
      starX: (response['starX'] as num).toDouble(),
      starY: (response['starY'] as num).toDouble(),
      pixels: base64Decode(response['pixels'] as String),
    );
  }

  @override
  Future<BuiltinGuiderConfig> builtinGuiderGetConfig() async {
    final response = await _get('builtin-guider/config');
    return BuiltinGuiderConfig.fromJson(response);
  }

  @override
  Future<void> builtinGuiderSetConfig(BuiltinGuiderConfig config) async {
    await _post('builtin-guider/config', config.toJson());
  }

  // =========================================================================
  // Plate Solving
  // =========================================================================

  @override
  Future<PlateSolveResult> plateSolve({
    required String imagePath,
    double? ra,
    double? dec,
    double? fovDegrees,
  }) async {
    final response = await _post('plate-solve', {
      'imagePath': imagePath,
      if (ra != null) 'ra': ra,
      if (dec != null) 'dec': dec,
      if (fovDegrees != null) 'fov': fovDegrees,
    });

    return PlateSolveResult(
      success: response['success'] as bool,
      ra: (response['ra'] as num).toDouble(),
      dec: (response['dec'] as num).toDouble(),
      pixelScale: (response['pixelScale'] as num).toDouble(),
      rotation: (response['rotation'] as num).toDouble(),
      fieldWidth: (response['fieldWidth'] as num).toDouble(),
      fieldHeight: (response['fieldHeight'] as num).toDouble(),
      solveTimeSecs: (response['solveTimeSecs'] as num).toDouble(),
      error: response['error'] as String?,
    );
  }

  // =========================================================================
  // Sequencer Control
  // =========================================================================

  @override
  Future<void> sequencerStart() async {
    await _post('sequencer/start');
  }

  @override
  Future<void> sequencerStop() async {
    await _post('sequencer/stop');
  }

  @override
  Future<void> sequencerPause() async {
    await _post('sequencer/pause');
  }

  @override
  Future<void> sequencerResume() async {
    await _post('sequencer/resume');
  }

  @override
  Future<void> sequencerSkip() async {
    await _post('sequencer/skip');
  }

  @override
  Future<void> sequencerSkipToNode(String nodeId) async {
    // Wave 1.5 Pack A: forwarded to the remote host's sequencer.skip-to-node
    // endpoint. Server side maps to api_sequencer_skip_to_node.
    await _post('sequencer/skip-to-node', {'nodeId': nodeId});
  }

  @override
  Future<void> sequencerPluginNodeFinished({
    required String nodeId,
    required bool success,
    String? message,
    String? structuredDetailJson,
  }) async {
    // Wave 6 Pack P: forwarded to the remote host's plugin-node-finished
    // endpoint. Server side maps to `api_sequencer_plugin_node_finished`.
    // The remote backend will likely need to dispatch the plugin on the
    // host side too — Pack P does not yet wire the remote dispatch path
    // (that lands with the Wave 7 remote-protocol pack); for now this
    // is a faithful forwarder so the wire format is stable from day 1.
    await _post('sequencer/plugin-node-finished', {
      'nodeId': nodeId,
      'success': success,
      if (message != null) 'message': message,
      if (structuredDetailJson != null)
        'structuredDetailJson': structuredDetailJson,
    });
  }

  @override
  Future<void> sequencerReset() async {
    await _post('sequencer/reset');
  }

  @override
  Future<void> sequencerLoadJson(String json) async {
    await _post('sequencer/load', {'json': json});
  }

  @override
  Future<void> sequencerSetSimulationMode(bool enabled) async {
    await _post('sequencer/simulation', {'enabled': enabled});
  }

  @override
  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    await _post('sequencer/devices', {
      'cameraId': cameraId,
      'mountId': mountId,
      'focuserId': focuserId,
      'filterwheelId': filterwheelId,
      'rotatorId': rotatorId,
      'filterNames': filterNames,
      'filterFocusOffsets': filterFocusOffsets,
    });
  }

  @override
  Future<void> sequencerSetSafetyFailMode(String mode) async {
    await _post('sequencer/safety-fail-mode', {'mode': mode});
  }

  @override
  Future<void> sequencerSetSafetyCheckIntervalSeconds(int seconds) async {
    await _post('sequencer/safety-check-interval', {'seconds': seconds});
  }

  @override
  Future<void> sequencerSetSavePath(String? path) async {
    await _post('sequencer/save-path', {'path': path});
  }

  @override
  Future<void> sequencerSetActiveSequenceRunId(int? sequenceRunId) async {
    // Wave 8 Replay Debug — POST through the standard sequencer
    // sub-API; the network backend just forwards primitives.
    await _post(
      'sequencer/active-sequence-run-id',
      {'sequence_run_id': sequenceRunId},
    );
  }

  @override
  Future<void> sequencerSetDecisionLoggingEnabled(bool enabled) async {
    // Wave 8 Replay Debug — runtime toggle.
    await _post(
      'sequencer/decision-logging-enabled',
      {'enabled': enabled},
    );
  }

  @override
  Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  }) async {
    await _post('sequencer/update-dither-config', {
      'pixels': pixels,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
      'raOnly': raOnly,
    });
  }

  @override
  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    await _post('sequencer/update-location', {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  @override
  Future<void> sequencerUpdateFilterOffsets(Map<String, int> offsets) async {
    await _post('sequencer/update-filter-offsets', {'offsets': offsets});
  }

  @override
  Future<void> sequencerUpdatePendingIntegrationCarryOver(
    Map<String, Map<String, double>> carryOver,
  ) async {
    // Wave 7.5 — remote staging mirrors the FFI path. The headless API
    // owns the deserialisation; an unrecognised endpoint on an older
    // headless build is surfaced (CLAUDE.md "errors are a feature").
    await _post('sequencer/update-pending-integration-carry-over', {
      'carry_over': carryOver,
    });
  }

  @override
  Future<void> sequencerUpdateAutofocusInterval(int everyNFrames) async {
    // Wave 1.5 Pack A: forwarded to the remote host's runtime-config update
    // endpoint. Server side maps to api_sequencer_update_autofocus_interval.
    await _post(
        'sequencer/update-autofocus-interval', {'everyNFrames': everyNFrames});
  }

  @override
  Future<void> sequencerUpdateDefaultQualityCheck({
    double? hfrThreshold,
    double? hfrBaselinePercent,
    double? eccentricityThreshold,
    int? starCountMin,
    required int maxConsecutiveRejects,
    required bool enabled,
  }) async {
    // Pack G — forwarded to the remote host. Server side maps to
    // api_sequencer_update_default_quality_check.
    await _post('sequencer/update-default-quality-check', {
      'hfrThreshold': hfrThreshold,
      'hfrBaselinePercent': hfrBaselinePercent,
      'eccentricityThreshold': eccentricityThreshold,
      'starCountMin': starCountMin,
      'maxConsecutiveRejects': maxConsecutiveRejects,
      'enabled': enabled,
    });
  }

  @override
  Future<void> sequencerUpdateRejectFolderPath(String? path) async {
    // Pack G — forwarded to the remote host. Server side maps to
    // api_sequencer_update_reject_folder_path.
    await _post('sequencer/update-reject-folder-path', {'path': path});
  }

  @override
  Future<void> sequencerUpdateObserverProfile({
    String? observerName,
    double? siteElevationM,
    String? cameraMake,
    String? cameraModel,
    String? telescopeName,
    double? telescopeFocalLengthMm,
    double? telescopeApertureMm,
  }) async {
    // Pack G — forwarded to the remote host. Server side maps to
    // api_sequencer_update_observer_profile.
    await _post('sequencer/update-observer-profile', {
      'observerName': observerName,
      'siteElevationM': siteElevationM,
      'cameraMake': cameraMake,
      'cameraModel': cameraModel,
      'telescopeName': telescopeName,
      'telescopeFocalLengthMm': telescopeFocalLengthMm,
      'telescopeApertureMm': telescopeApertureMm,
    });
  }

  @override
  Future<void> sequencerUpdateCloudMotion({
    double? currentCoverPercent,
    double? predictedArrivalMinutes,
    double? predictedOpeningMinutes,
    double? predictedOpeningDurationSecs,
    double? predictedClearSkyAlt,
    double? predictedClearSkyAz,
  }) async {
    // Wave 5 Agent 4 — forwarded to the remote host so the remote rig's
    // executor sees the same analyzer reading the local controller has.
    await _post('sequencer/update-cloud-motion', {
      'currentCoverPercent': currentCoverPercent,
      'predictedArrivalMinutes': predictedArrivalMinutes,
      'predictedOpeningMinutes': predictedOpeningMinutes,
      'predictedOpeningDurationSecs': predictedOpeningDurationSecs,
      'predictedClearSkyAlt': predictedClearSkyAlt,
      'predictedClearSkyAz': predictedClearSkyAz,
    });
  }

  @override
  Future<String?> sequencerGetCloudMotionJson() async {
    // Wave 5 Agent 4 — fetched lazily by the dashboard tick. The remote
    // endpoint mirrors the local FRB call.
    try {
      final response = await _get('sequencer/cloud-motion');
      final json = response['cloud_motion'];
      return json is String ? json : null;
    } catch (_) {
      // The remote endpoint may not be implemented in older headless
      // servers; treat a 404 / parse error as "no data" rather than
      // failing the dashboard tick.
      return null;
    }
  }

  @override
  Future<void> sequencerUpdateConditionsScore(ConditionsScore? score) async {
    await _post('sequencer/update-conditions-score', {
      'score': score?.toJson(),
    });
  }

  @override
  Future<AdaptiveSwapSnapshot?> sequencerGetAdaptiveSwapSnapshot() async {
    final response = await _get('sequencer/adaptive-swap');
    final value = response['adaptive_swap'];
    if (value == null) return null;
    if (value is String) return AdaptiveSwapDriver.decodeSnapshotJson(value);
    if (value is Map<String, dynamic>) {
      return AdaptiveSwapSnapshot.fromJson(value);
    }
    if (value is Map) {
      return AdaptiveSwapSnapshot.fromJson(Map<String, dynamic>.from(value));
    }
    throw StateError(
      'Malformed adaptive_swap response: expected object, string, or null; '
      'got ${value.runtimeType}',
    );
  }

  @override
  Future<void> sequencerUpdateSkyBrightness({required double? mag}) async {
    // Wave 5 Agent 2 — forwarded to the remote host so the remote rig's
    // executor sees the same SkyBrightnessTracker reading the local
    // controller has. Older headless servers may not implement the
    // endpoint; we don't swallow errors here (the user explicitly
    // pushed and would want to know).
    await _post('sequencer/update-sky-brightness', {'mag': mag});
  }

  @override
  Future<void> sequencerUpdateDefaultAdaptiveExposure({
    required bool enabled,
    required double targetSnr,
    required double referenceSkyBrightnessMag,
    required double minExposureSecs,
    required double maxExposureSecs,
    required Map<String, bool> perFilterEnabled,
    required Map<String, double> perFilterMinSecs,
    required Map<String, double> perFilterMaxSecs,
  }) async {
    await _post('sequencer/update-default-adaptive-exposure', {
      'enabled': enabled,
      'targetSnr': targetSnr,
      'referenceSkyBrightnessMag': referenceSkyBrightnessMag,
      'minExposureSecs': minExposureSecs,
      'maxExposureSecs': maxExposureSecs,
      'perFilterEnabled': perFilterEnabled,
      'perFilterMinSecs': perFilterMinSecs,
      'perFilterMaxSecs': perFilterMaxSecs,
    });
  }

  @override
  Future<void> sequencerClearDefaultAdaptiveExposure() async {
    await _post('sequencer/clear-default-adaptive-exposure', const {});
  }

  // =========================================================================
  // Wave 4 Recovery Mode
  // =========================================================================

  @override
  Future<void> recoveryTryNow() async {
    await _post('sequencer/recovery/try-now', const {});
  }

  @override
  Future<void> recoveryAbort() async {
    await _post('sequencer/recovery/abort', const {});
  }

  @override
  Future<void> updateRecoveryConfig({
    required double retryIntervalSecs,
    required double maxDurationSecs,
    required bool stopTrackingDuringRecovery,
    required bool abortOnMeridian,
    required bool audibleAlertWhenEntered,
  }) async {
    await _post('sequencer/recovery/update-config', {
      'retryIntervalSecs': retryIntervalSecs,
      'maxDurationSecs': maxDurationSecs,
      'stopTrackingDuringRecovery': stopTrackingDuringRecovery,
      'abortOnMeridian': abortOnMeridian,
      'audibleAlertWhenEntered': audibleAlertWhenEntered,
    });
  }

  @override
  Future<String?> getCurrentRecoveryJson() async {
    final response = await _get('sequencer/recovery/current');
    // The server returns `{"context": null}` for an idle executor or
    // `{"context": "<json>"}` while recovering.
    final ctx = response['context'];
    if (ctx == null) return null;
    return ctx as String;
  }

  @override
  Future<String> getRecoveryHistoryJson() async {
    final response = await _get('sequencer/recovery/history');
    return (response['history'] as String?) ?? '[]';
  }

  @override
  Future<SequencerStatus> sequencerGetStatus() async {
    final response = await _get('sequencer/status');
    return SequencerStatus(
      state: response['state'] as String? ?? 'Idle',
      currentNodeId: response['currentNodeId'] as String?,
      currentNodeName: response['currentNodeName'] as String?,
      progress: (response['progress'] as num?)?.toDouble() ?? 0.0,
      message: response['message'] as String?,
    );
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  @override
  Future<void> sequencerSetCheckpointDir(String path) async {
    await _post('sequencer/checkpoint/dir', {'path': path});
  }

  @override
  Future<bool> hasCheckpoint() async {
    final response = await _get('sequencer/checkpoint/has');
    return response['hasCheckpoint'] as bool? ?? false;
  }

  @override
  Future<CheckpointInfo?> getCheckpointInfo() async {
    final response = await _get('sequencer/checkpoint/info');
    if (response['info'] == null) return null;
    return CheckpointInfo.fromJson(response['info'] as Map<String, dynamic>);
  }

  @override
  Future<void> resumeFromCheckpoint() async {
    await _post('sequencer/checkpoint/resume', {});
  }

  @override
  Future<void> discardCheckpoint() async {
    await _post('sequencer/checkpoint/discard', {});
  }

  @override
  Future<void> saveCheckpoint() async {
    await _post('sequencer/checkpoint/save', {});
  }

  @override
  Future<LocationSettings> getLocationFromInternet() async {
    final response = await _get('location');
    return LocationSettings(
      latitude: (response['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (response['longitude'] as num?)?.toDouble() ?? 0.0,
      elevation: (response['elevation'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // =========================================================================
  // Equipment Status
  // =========================================================================

  @override
  Future<CameraStatus> getCameraStatus(String deviceId) async {
    final response =
        await _get('equipment/camera/status', {'deviceId': deviceId});
    return CameraStatus.fromJson(response);
  }

  @override
  Future<MountStatus> getMountStatus(String deviceId) async {
    final response =
        await _get('equipment/mount/status', {'deviceId': deviceId});
    return MountStatus.fromJson(response);
  }

  @override
  Future<FocuserStatus> getFocuserStatus(String deviceId) async {
    final response =
        await _get('equipment/focuser/status', {'deviceId': deviceId});
    return FocuserStatus.fromJson(response);
  }

  @override
  Future<FilterWheelStatus> getFilterWheelStatus(String deviceId) async {
    final response =
        await _get('equipment/filter-wheel/status', {'deviceId': deviceId});
    return FilterWheelStatus.fromJson(response);
  }

  @override
  Future<RotatorStatus> getRotatorStatus(String deviceId) async {
    final response =
        await _get('equipment/rotator/status', {'deviceId': deviceId});
    return RotatorStatus.fromJson(response);
  }

  // =========================================================================
  // Device Capabilities
  // =========================================================================

  @override
  Future<CameraCapabilities?> getCameraCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/camera/capabilities', {'deviceId': deviceId});
      return CameraCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get camera capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<MountCapabilities?> getMountCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/mount/capabilities', {'deviceId': deviceId});
      return MountCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get mount capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<FocuserCapabilities?> getFocuserCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/focuser/capabilities', {'deviceId': deviceId});
      return FocuserCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get focuser capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<FilterWheelCapabilities?> getFilterWheelCapabilities(
      String deviceId) async {
    try {
      final response = await _get(
          'equipment/filter-wheel/capabilities', {'deviceId': deviceId});
      return FilterWheelCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get filter wheel capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<RotatorCapabilities?> getRotatorCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/rotator/capabilities', {'deviceId': deviceId});
      return RotatorCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get rotator capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  // NOTE: The old _parseXxxCapabilities helpers have been removed.
  // Pure Dart types now have fromJson() factory constructors.

  // Legacy helper for rotator - kept for reference but no longer used
  RotatorCapabilities _parseRotatorCapabilities(Map<String, dynamic> json) {
    return RotatorCapabilities(
      canReverse: json['canReverse'] ?? false,
      reverse: json['reverse'] ?? false,
      stepSize: json['stepSize']?.toDouble(),
      isMoving: json['isMoving'] ?? false,
      mechanicalPosition: json['mechanicalPosition']?.toDouble(),
      position: json['position']?.toDouble(),
      canMoveAbsolute: json['canMoveAbsolute'] ?? false,
      canHalt: json['canHalt'] ?? false,
      canSync: json['canSync'] ?? false,
    );
  }

  // =========================================================================
  // Type Conversion Helpers
  // =========================================================================

  DeviceType _parseDeviceType(String str) {
    switch (str.toLowerCase()) {
      case 'camera':
        return DeviceType.camera;
      case 'mount':
        return DeviceType.mount;
      case 'focuser':
        return DeviceType.focuser;
      case 'filterwheel':
        return DeviceType.filterWheel;
      case 'guider':
        return DeviceType.guider;
      case 'dome':
        return DeviceType.dome;
      case 'rotator':
        return DeviceType.rotator;
      case 'weather':
        return DeviceType.weather;
      case 'safetymonitor':
        return DeviceType.safetyMonitor;
      default:
        throw Exception('Unknown device type: $str');
    }
  }

  DriverType _parseDriverType(String str) {
    switch (str.toLowerCase()) {
      case 'ascom':
        return DriverType.ascom;
      case 'alpaca':
        return DriverType.alpaca;
      case 'indi':
        return DriverType.indi;
      case 'native':
        return DriverType.native;
      case 'simulator':
        return DriverType.simulator;
      default:
        throw Exception('Unknown driver type: $str');
    }
  }

  EventSeverity _parseSeverity(String str) {
    switch (str.toLowerCase()) {
      case 'info':
        return EventSeverity.info;
      case 'warning':
        return EventSeverity.warning;
      case 'error':
        return EventSeverity.error;
      case 'critical':
        return EventSeverity.critical;
      default:
        return EventSeverity.info;
    }
  }

  EventCategory _parseCategory(String str) {
    switch (str.toLowerCase()) {
      case 'equipment':
        return EventCategory.equipment;
      case 'imaging':
        return EventCategory.imaging;
      case 'guiding':
        return EventCategory.guiding;
      case 'sequencer':
        return EventCategory.sequencer;
      case 'safety':
        return EventCategory.safety;
      case 'system':
        return EventCategory.system;
      case 'polaralignment':
        return EventCategory.polarAlignment;
      default:
        return EventCategory.system;
    }
  }

  NightshadeEvent _eventFromJson(Map<String, dynamic> json) {
    return NightshadeEvent.fromWireJson(json);
  }

  // =========================================================================
  // Equipment Profiles
  // =========================================================================

  @override
  Future<List<EquipmentProfile>> getProfiles() async {
    final response = await _get('profiles');
    return (response['profiles'] as List)
        .map((p) => EquipmentProfile.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveProfile(EquipmentProfile profile) async {
    await _post('profiles', {'profile': profile.toJson()});
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    await _delete('profiles/$profileId');
  }

  @override
  Future<void> loadProfile(String profileId) async {
    await _post('profiles/$profileId/load');
  }

  @override
  Future<EquipmentProfile?> getActiveProfile() async {
    final response = await _get('profiles/active');
    if (response['profile'] == null) return null;
    return EquipmentProfile.fromJson(
        response['profile'] as Map<String, dynamic>);
  }

  // =========================================================================
  // Settings & Location
  // =========================================================================

  @override
  Future<models.AppSettings> getSettings() async {
    final json = await _get('settings');
    final settingsJson = json['settings'];
    if (settingsJson is! Map<String, dynamic>) {
      throw StateError(
        'GET /api/settings returned no settings object (HTTP 200)',
      );
    }
    return models.AppSettings.fromJson(settingsJson);
  }

  @override
  Future<void> updateSettings(models.AppSettings settings) async {
    // [Wave 6B settings sync] forward through the dedicated overload so
    // origin-filtering callers can stamp a command id without changing
    // the public interface of NightshadeBackend.
    return updateSettingsWithCommandId(settings, commandId: null);
  }

  /// [Wave 6B settings sync] Variant of [updateSettings] that stamps the
  /// outgoing POST with an `X-Nightshade-Command-Id` header so the
  /// `settings.changed` events that come back over the WS carry the
  /// `correlatingCommandId` and the calling client can ignore its own
  /// echo. Callers track the same id locally; un-paired clients can
  /// continue to call [updateSettings] and accept the echo as a no-op
  /// (the diff against in-memory state will already be empty).
  Future<void> updateSettingsWithCommandId(
    models.AppSettings settings, {
    required String? commandId,
  }) async {
    final extraHeaders = commandId == null
        ? null
        : <String, String>{'X-Nightshade-Command-Id': commandId};
    await _post('settings', {'settings': settings.toJson()}, extraHeaders);
  }

  @override
  Future<models.ObserverLocation?> getLocation() async {
    final json = await _get('settings/location');
    if (json['location'] == null) return null;
    return models.ObserverLocation.fromJson(
        json['location'] as Map<String, dynamic>);
  }

  @override
  Future<void> setLocation(models.ObserverLocation? location) async {
    await _post('settings/location', {'location': location?.toJson()});
  }

  // =========================================================================
  // Image Processing
  // =========================================================================

  @override
  Future<ImageStats> getImageStats(
      int width, int height, Uint16List data) async {
    _throwHostOnlyRemoteProcessing('POST /api/imaging/stats');
  }

  @override
  Future<Uint8List> autoStretchImage(
      int width, int height, Uint16List data) async {
    _throwHostOnlyRemoteProcessing('POST /api/imaging/stretch');
  }

  @override
  Future<List<StarCrop>> getStarCropsFromLastImage(String deviceId,
      {int maxCrops = 5}) async {
    final response = await _get('imaging/star-crops', {
      'deviceId': deviceId,
      'maxCrops': maxCrops,
    });
    final crops = response['crops'] as List<dynamic>;
    return crops
        .map((crop) => StarCrop.fromJson(crop as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Uint8List> debayerImage(
    int width,
    int height,
    Uint16List data,
    String pattern,
    String algorithm,
  ) async {
    _throwHostOnlyRemoteProcessing('POST /api/imaging/debayer');
  }

  @override
  Future<void> calibrateImageFile({
    required String lightPath,
    String? darkPath,
    String? flatPath,
    String? biasPath,
    required String outputPath,
  }) async {
    await _post('imaging/calibrate-file', {
      'lightPath': lightPath,
      if (darkPath != null) 'darkPath': darkPath,
      if (flatPath != null) 'flatPath': flatPath,
      if (biasPath != null) 'biasPath': biasPath,
      'outputPath': outputPath,
    });
  }

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  final _polarAlignController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents =>
      _polarAlignController.stream;

  @override
  Future<void> startPolarAlignment({
    required double exposureTime,
    required double stepSize,
    required int binning,
    required bool isNorth,
    required bool manualRotation,
    required bool rotateEast,
    int? gain,
    int? offset,
    double? solveTimeout,
    bool? startFromCurrent,
    double? autoCompleteThreshold,
  }) async {
    await _post('polar-alignment/start', {
      'exposure_time': exposureTime,
      'step_size': stepSize,
      'binning': binning,
      'is_north': isNorth,
      'manual_rotation': manualRotation,
      'rotate_east': rotateEast,
      if (gain != null) 'gain': gain,
      if (offset != null) 'offset': offset,
      if (solveTimeout != null) 'solve_timeout': solveTimeout,
      if (startFromCurrent != null) 'start_from_current': startFromCurrent,
      if (autoCompleteThreshold != null)
        'auto_complete_threshold': autoCompleteThreshold,
    });
  }

  @override
  Future<void> stopPolarAlignment() async {
    await _post('polar-alignment/stop', {});
  }

  @override
  Future<void> startAllSkyPolarAlignment({
    required double exposureTime,
    required double solveTimeout,
    required int binning,
    required bool isNorth,
    required double acceptanceThresholdArcsec,
    required double iterationCadenceSecs,
    int? gain,
    int? offset,
  }) async {
    await _post('polar-alignment/all-sky/start', {
      'exposure_time': exposureTime,
      'solve_timeout': solveTimeout,
      'binning': binning,
      'is_north': isNorth,
      'acceptance_threshold_arcsec': acceptanceThresholdArcsec,
      'iteration_cadence_secs': iterationCadenceSecs,
      if (gain != null) 'gain': gain,
      if (offset != null) 'offset': offset,
    });
  }

  // =========================================================================
  // Image Download (for Mobile)
  // =========================================================================

  @override
  Future<List<CapturedImage>> getSessionImages(int sessionId) async {
    final imagesList = await getSessionImageRows(sessionId);

    return imagesList.map((img) {
      return CapturedImage(
        id: img['image_id'].toString(),
        filePath: img['file_path'] as String,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
            (img['captured_at'] as int) * 1000),
        settings: ExposureSettings(
          exposureTime: (img['exposure_duration'] as num).toDouble(),
          gain: img['gain'] as int? ?? 0,
          offset: img['offset'] as int? ?? 0,
          binningX: img['bin_x'] as int? ?? 1,
          binningY: img['bin_y'] as int? ?? 1,
          filter: img['filter'] as String?,
          frameType: _parseFrameType(img['frame_type'] as String),
        ),
        stats: img['hfr'] != null
            ? ImageStats(
                hfr: (img['hfr'] as num?)?.toDouble(),
                starCount: img['star_count'] as int?,
              )
            : null,
        targetName: null, // Not included in basic metadata
        format: _parseImageFormat(img['file_format'] as String),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getSessionImageRows(int sessionId) async {
    final response = await _get('sessions/$sessionId/images');
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getAllImageRows() async {
    final response = await _get('images');
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getStandaloneImageRows() async {
    final response = await _get('images/standalone');
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  @override
  Future<Uint8List> getImageThumbnail(int imageId) async {
    final uri = Uri.parse(
        'http://$serverHost:$serverPort/api/images/$imageId/thumbnail');

    final request = await _httpClient.getUrl(uri);
    final response = await request.close();

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to get thumbnail');
    }

    final bytes = await consolidateHttpClientResponseBytes(response);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> downloadImage(int imageId, String localPath,
      {void Function(double)? onProgress}) async {
    final uri = Uri.parse(
        'http://$serverHost:$serverPort/api/images/$imageId/download');

    // P0-5 — opportunistic resume. If a partial file already exists at
    // [localPath] from a prior aborted attempt, send `Range: bytes=N-`
    // to ask the server to continue. A server that supports Range
    // (post-P0-5 Nightshade) replies with 206 + `content-range`; an
    // older/naive server ignores the header and returns 200 with the
    // entire body — we detect that and start over from byte 0.
    final file = File(localPath);
    await file.parent.create(recursive: true);

    int resumeOffset = 0;
    if (await file.exists()) {
      try {
        resumeOffset = await file.length();
      } on FileSystemException catch (e) {
        // Existing file is unreadable — surface it instead of pretending
        // to start from zero. CLAUDE.md: errors are a feature.
        throw Exception('Failed to stat partial download at $localPath: $e');
      }
    }

    final request = await _httpClient.getUrl(uri);
    if (resumeOffset > 0) {
      request.headers.set('range', 'bytes=$resumeOffset-');
    }
    final response = await request.close();

    // Server can answer:
    //   * 206 Partial Content — honoured the Range, append to the file.
    //   * 200 OK + content-range absent — full body, truncate the file
    //     and write from scratch.
    //   * 416 — our resume offset is past EOF on the server (e.g. the
    //     file was replaced). Truncate and retry without Range.
    //   * anything else — propagate.
    final statusCode = response.statusCode;
    final contentRange = response.headers.value('content-range');
    final bool isPartial = statusCode == 206 && contentRange != null;

    if (statusCode == 416 && resumeOffset > 0) {
      // The server says our partial is invalid (file changed / shrunk).
      // Drop the partial and retry from scratch with a fresh request.
      developer.log(
        '[NetworkBackend] Server returned 416 for resume offset '
        '$resumeOffset; discarding partial and retrying from byte 0',
        name: 'NetworkBackend',
        level: 900,
      );
      await response.drain<void>();
      await file.delete();
      // Recursive single-shot retry (resumeOffset will be 0 next call
      // because the file was deleted). This is bounded — a 416 on the
      // retry would mean the server has nothing at all to serve, which
      // we let propagate.
      return downloadImage(imageId, localPath, onProgress: onProgress);
    }

    if (statusCode != 200 && statusCode != 206) {
      await response.drain<void>();
      throw Exception('HTTP $statusCode: Failed to download image');
    }

    // Get total length for progress tracking. For 206 the response
    // content-length is the *slice* length, but we want total bytes
    // for the progress fraction; pull the total from `content-range:
    // bytes START-END/TOTAL`.
    int totalLength = response.contentLength;
    if (isPartial) {
      final slash = contentRange.lastIndexOf('/');
      if (slash > 0 && slash < contentRange.length - 1) {
        final totalStr = contentRange.substring(slash + 1);
        if (totalStr != '*') {
          totalLength = int.tryParse(totalStr) ?? totalLength;
        }
      }
    }

    // Open the sink in the correct mode: append for 206, write
    // (truncate) for 200. If we asked for a range but got 200, the
    // server doesn't support Range — discard whatever was already on
    // disk and start over.
    final IOSink sink;
    int bytesReceived;
    if (isPartial) {
      sink = file.openWrite(mode: FileMode.append);
      bytesReceived = resumeOffset;
    } else {
      sink = file.openWrite();
      bytesReceived = 0;
    }

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        bytesReceived += chunk.length;

        if (onProgress != null && totalLength > 0) {
          onProgress(bytesReceived / totalLength);
        }
      }
    } finally {
      await sink.close();
    }

    developer.log(
        '[NetworkBackend] Downloaded image $imageId to $localPath '
        '($bytesReceived bytes${isPartial ? ', resumed from $resumeOffset' : ''})',
        name: 'NetworkBackend',
        level: 800);
  }

  FrameType _parseFrameType(String str) {
    switch (str.toLowerCase()) {
      case 'light':
        return FrameType.light;
      case 'dark':
        return FrameType.dark;
      case 'flat':
        return FrameType.flat;
      case 'bias':
        return FrameType.bias;
      case 'darkflat':
        return FrameType.darkFlat;
      default:
        return FrameType.light;
    }
  }

  ImageFileFormat _parseImageFormat(String str) {
    switch (str.toLowerCase()) {
      case 'fits':
        return ImageFileFormat.fits;
      case 'xisf':
        return ImageFileFormat.xisf;
      case 'tiff':
        return ImageFileFormat.tiff;
      case 'png':
        return ImageFileFormat.png;
      case 'jpeg':
      case 'jpg':
        return ImageFileFormat.jpeg;
      default:
        return ImageFileFormat.fits;
    }
  }

  // =========================================================================
  // Device Health Monitoring
  // =========================================================================

  @override
  Future<void> startDeviceHeartbeat({
    required DeviceType deviceType,
    required String deviceId,
    required int intervalMs,
  }) async {
    await _post('device/heartbeat/start', {
      'device_type': deviceType.name,
      'device_id': deviceId,
      'interval_ms': intervalMs,
    });
  }

  @override
  Future<void> stopDeviceHeartbeat(String deviceId) async {
    await _post('device/heartbeat/stop', {
      'device_id': deviceId,
    });
  }

  @override
  Future<(int, bool)> getDeviceHealth(String deviceId) async {
    final response = await _get('device/health/$deviceId');
    final lastComm = response['last_successful_comm'] as int;
    final isHealthy = response['is_healthy'] as bool;
    return (lastComm, isHealthy);
  }

  // =========================================================================
  // Raw Image Data
  // =========================================================================

  @override
  Future<List<int>> getLastRawImageData(String deviceId) async {
    return _retryableRequest(() async {
      final uri = Uri.parse(
          'http://$serverHost:$serverPort/api/imaging/raw-data?deviceId=${Uri.encodeComponent(deviceId)}');

      final request = await _httpClient.getUrl(uri);

      // Add authentication headers
      final headers = _addAuthHeaders({}, endpoint: 'imaging/raw-data');
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();

      // Check for transient status codes
      if (_isTransientStatusCode(response.statusCode)) {
        throw Exception(
            'HTTP ${response.statusCode}: Transient failure for GET imaging/raw-data');
      }

      if (response.statusCode != 200) {
        throw Exception(
            'HTTP ${response.statusCode}: Failed to GET imaging/raw-data');
      }

      // Read binary data
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes;
    });
  }

  @override
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required FitsWriteHeader headerData,
  }) async {
    _throwHostOnlyRemoteProcessing('POST /api/imaging/save-fits');
  }

  @override
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  }) async {
    // Use the optimized endpoint that saves from server-side stored image
    // No raw pixel data needs to be transferred
    return _retryableRequest(() async {
      final uri = Uri.parse(
          'http://$serverHost:$serverPort/api/imaging/save-fits-from-capture');

      final request = await _httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;

      // Add authentication headers
      final headers = _addAuthHeaders(
        {},
        endpoint: 'imaging/save-fits-from-capture',
      );
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      // Build request body - file path, device ID, and header (no pixel data)
      // Use pure Dart type's toJson() for header serialization
      final body = {
        'deviceId': deviceId,
        'filePath': filePath,
        'headerData': headerData.toJson(),
      };

      request.write(jsonEncode(body));

      final response = await request.close();

      // Check for transient status codes
      if (_isTransientStatusCode(response.statusCode)) {
        throw Exception(
            'HTTP ${response.statusCode}: Transient failure for POST imaging/save-fits-from-capture');
      }

      if (response.statusCode != 200) {
        throw Exception(
            'HTTP ${response.statusCode}: Failed to POST imaging/save-fits-from-capture');
      }

      // Consume response body to complete the request
      await response.transform(utf8.decoder).join();
    });
  }

  @override
  Future<void> clearDeviceImage(String deviceId) async {
    await _delete('imaging/device-image/${Uri.encodeComponent(deviceId)}');
  }

  // =========================================================================
  // Target Management
  // =========================================================================

  /// Get all targets from the headless server
  /// Returns JSON maps that can be used to construct CelestialTarget objects
  Future<List<Map<String, dynamic>>> getAllTargets() async {
    final response = await _get('targets');
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Get a specific target by ID
  Future<Map<String, dynamic>?> getTargetById(int id) async {
    try {
      final response = await _get('targets/$id');
      return response['target'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log('Failed to get target $id: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  /// Search targets by query string
  Future<List<Map<String, dynamic>>> searchTargets(String query) async {
    final response = await _get('targets/search', {'query': query});
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Create a new target
  Future<int> createTarget(Map<String, dynamic> target) async {
    final response = await _post('targets', target);
    return response['id'] as int;
  }

  /// Update an existing target
  Future<void> updateTarget(int id, Map<String, dynamic> target) async {
    await _put('targets/$id', target);
  }

  /// Delete a target
  Future<void> deleteTarget(int id) async {
    await _delete('targets/$id');
  }

  /// Toggle favorite status for a target
  Future<void> toggleTargetFavorite(int id) async {
    await _post('targets/$id/favorite');
  }

  /// Update target progress
  Future<void> updateTargetProgress(int id,
      {int? capturedSubs, double? totalIntegrationSecs}) async {
    await _put('targets/$id/progress', {
      if (capturedSubs != null) 'capturedSubs': capturedSubs,
      if (totalIntegrationSecs != null)
        'totalIntegrationSecs': totalIntegrationSecs,
    });
  }

  /// Get favorite targets
  Future<List<Map<String, dynamic>>> getFavoriteTargets() async {
    final response = await _get('targets/favorites');
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Get targets by object type
  Future<List<Map<String, dynamic>>> getTargetsByType(String objectType) async {
    final response = await _get('targets/by-type', {'type': objectType});
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  /// Get targets by priority
  Future<List<Map<String, dynamic>>> getTargetsByPriority(int priority) async {
    final response =
        await _get('targets/by-priority', {'priority': priority.toString()});
    final targetsList = response['targets'] as List? ?? [];
    return targetsList.cast<Map<String, dynamic>>();
  }

  // =========================================================================
  // Sequence Management (CRUD - separate from sequencer execution)
  // =========================================================================

  /// Get all sequences
  Future<List<Map<String, dynamic>>> getSequenceList() async {
    final response = await _get('sequence-management/list');
    final sequencesList = response['sequences'] as List? ?? [];
    return sequencesList.cast<Map<String, dynamic>>();
  }

  /// Get all sequence templates
  Future<List<Map<String, dynamic>>> getSequenceTemplates() async {
    final response = await _get('sequence-management/templates');
    final templatesList = response['templates'] as List? ?? [];
    return templatesList.cast<Map<String, dynamic>>();
  }

  /// Get a specific sequence by ID
  Future<Map<String, dynamic>?> getSequenceDetails(int id) async {
    try {
      final response = await _get('sequence-management/$id');
      return response['sequence'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log('Failed to get sequence $id: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  /// Get nodes for a sequence
  Future<List<Map<String, dynamic>>> getSequenceNodes(int sequenceId) async {
    final response = await _get('sequence-management/$sequenceId/nodes');
    final nodesList = response['nodes'] as List? ?? [];
    return nodesList.cast<Map<String, dynamic>>();
  }

  /// Create a new sequence
  Future<int> createSequence(Map<String, dynamic> sequence) async {
    final response = await _post('sequence-management', sequence);
    return response['id'] as int;
  }

  /// Update an existing sequence
  Future<void> updateSequence(int id, Map<String, dynamic> sequence) async {
    await _put('sequence-management/$id', sequence);
  }

  /// Delete a sequence
  Future<void> deleteSequence(int id) async {
    await _delete('sequence-management/$id');
  }

  /// Duplicate a sequence
  Future<int> duplicateSequence(int sourceId, String newName) async {
    final response = await _post(
        'sequence-management/$sourceId/duplicate', {'newName': newName});
    return response['id'] as int;
  }

  /// Save a full sequence document to the host database.
  Future<int> saveFullSequence(
    Map<String, dynamic> sequence, {
    bool isTemplate = false,
    int? databaseId,
  }) async {
    final response = await _post('sequence-management/save-full', {
      'sequence': sequence,
      'isTemplate': isTemplate,
      if (databaseId != null) 'databaseId': databaseId,
    });
    return response['id'] as int;
  }

  /// Load all sequences with full node trees from the host.
  Future<List<Map<String, dynamic>>> listFullSequences() async {
    final response = await _get('sequence-management/list-full');
    final sequencesList = response['sequences'] as List? ?? [];
    return sequencesList.cast<Map<String, dynamic>>();
  }

  /// Load all templates with full node trees from the host.
  Future<List<Map<String, dynamic>>> listFullTemplates() async {
    final response = await _get('sequence-management/templates-full');
    final templatesList = response['templates'] as List? ?? [];
    return templatesList.cast<Map<String, dynamic>>();
  }

  /// Create a new sequence node
  Future<void> createSequenceNode(
      int sequenceId, Map<String, dynamic> node) async {
    await _post('sequence-management/$sequenceId/nodes', node);
  }

  /// Update a sequence node
  Future<void> updateSequenceNode(
      String nodeId, Map<String, dynamic> node) async {
    await _put('sequence-management/nodes/$nodeId', node);
  }

  /// Delete a sequence node
  Future<void> deleteSequenceNode(String nodeId) async {
    await _delete('sequence-management/nodes/$nodeId');
  }

  /// Reorder sequence nodes
  Future<void> reorderSequenceNodes(
      int sequenceId, List<String> nodeIds) async {
    await _post(
        'sequence-management/$sequenceId/reorder', {'nodeIds': nodeIds});
  }

  // =========================================================================
  // Flat Wizard
  // =========================================================================

  /// Calibrate a single filter for flat frames
  Future<Map<String, dynamic>> flatWizardCalibrateFilter({
    required String deviceId,
    required String filter,
    required int targetAdu,
    required int tolerance,
    double minExposure = 0.001,
    double maxExposure = 30.0,
    int? gain,
    int binning = 1,
  }) async {
    final response = await _post('flat-wizard/calibrate', {
      'deviceId': deviceId,
      'filter': filter,
      'targetAdu': targetAdu,
      'tolerance': tolerance,
      'minExposure': minExposure,
      'maxExposure': maxExposure,
      if (gain != null) 'gain': gain,
      'binning': binning,
    });
    return response;
  }

  /// Calibrate multiple filters for flat frames
  Future<Map<String, dynamic>> flatWizardCalibrateMultiple({
    required String deviceId,
    required List<String> filters,
    required int targetAdu,
    required int tolerance,
    double minExposure = 0.001,
    double maxExposure = 30.0,
    int? gain,
    int binning = 1,
  }) async {
    final response = await _post('flat-wizard/calibrate-multi', {
      'deviceId': deviceId,
      'filters': filters,
      'targetAdu': targetAdu,
      'tolerance': tolerance,
      'minExposure': minExposure,
      'maxExposure': maxExposure,
      if (gain != null) 'gain': gain,
      'binning': binning,
    });
    return response;
  }

  /// Generate a flat frame sequence from calibration results
  Future<Map<String, dynamic>> flatWizardGenerateSequence({
    required List<Map<String, dynamic>> calibrations,
    required int framesPerFilter,
    String sequenceName = 'Flat Frames',
    bool dither = false,
  }) async {
    final response = await _post('flat-wizard/generate-sequence', {
      'calibrations': calibrations,
      'framesPerFilter': framesPerFilter,
      'sequenceName': sequenceName,
      'dither': dither,
    });
    return response;
  }

  // =========================================================================
  // Mosaic Planning
  // =========================================================================

  /// Generate mosaic panels
  Future<Map<String, dynamic>> mosaicGeneratePanels(
      Map<String, dynamic> config) async {
    final response = await _post('mosaic/generate-panels', config);
    return response;
  }

  /// Generate a mosaic sequence
  Future<Map<String, dynamic>> mosaicGenerateSequence({
    required Map<String, dynamic> config,
    required Map<String, dynamic> exposureSettings,
    required Map<String, dynamic> options,
  }) async {
    final response = await _post('mosaic/generate-sequence', {
      'config': config,
      'exposureSettings': exposureSettings,
      'options': options,
    });
    return response;
  }

  /// Calculate mosaic area
  Future<Map<String, dynamic>> mosaicCalculateArea(
      Map<String, dynamic> config) async {
    final response = await _post('mosaic/calculate-area', config);
    return response;
  }

  /// Validate mosaic configuration
  Future<Map<String, dynamic>> mosaicValidate(
      Map<String, dynamic> config) async {
    final response = await _post('mosaic/validate', config);
    return response;
  }

  // =========================================================================
  // Sessions & Analytics
  // =========================================================================

  /// Get all imaging sessions
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final response = await _get('sessions');
    final sessionsList = response['sessions'] as List? ?? [];
    return sessionsList.cast<Map<String, dynamic>>();
  }

  /// Get active session
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      final response = await _get('sessions/active');
      return response['session'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log('Failed to get active session: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  /// Get session by ID
  Future<Map<String, dynamic>?> getSessionById(int id) async {
    try {
      final response = await _get('sessions/$id');
      return response['session'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log('Failed to get session $id: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  /// Create a new session
  Future<int> createSession(Map<String, dynamic> session) async {
    final response = await _post('sessions', session);
    return response['id'] as int;
  }

  /// Update session fields (stats, notes, status).
  Future<void> updateSession(int id, Map<String, dynamic> body) async {
    await _put('sessions/$id', body);
  }

  /// End a session with the given status.
  Future<void> endSession(int id, {String status = 'completed'}) async {
    await _post('sessions/$id/end', {'status': status});
  }

  /// Sessions for a target.
  Future<List<Map<String, dynamic>>> getSessionsForTarget(int targetId) async {
    final response = await _get('sessions/target/$targetId');
    final sessions = response['sessions'] as List? ?? [];
    return sessions.cast<Map<String, dynamic>>();
  }

  /// Create a captured-image metadata row on the host.
  Future<int> createCapturedImage(Map<String, dynamic> image) async {
    final response = await _post('images', image);
    return response['id'] as int;
  }

  /// Patch captured-image metadata on the host.
  Future<void> updateCapturedImage(int id, Map<String, dynamic> patch) async {
    await _put('images/$id', patch);
  }

  /// Fetch one captured-image row by id.
  Future<Map<String, dynamic>?> getCapturedImageById(int id) async {
    try {
      final response = await _get('images/$id');
      return response['image'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log('Failed to get image $id: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  /// Images for a target.
  Future<List<Map<String, dynamic>>> getImagesForTarget(int targetId) async {
    final response = await _get('images', {'targetId': targetId.toString()});
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  /// Thumbnail-strip rows for a producing exposure node.
  Future<List<Map<String, dynamic>>> getImagesByProducingNode(
    String producingNodeId, {
    String? producingRunId,
    int? limit,
  }) async {
    final params = <String, String>{
      'producingNodeId': producingNodeId,
      if (producingRunId != null) 'producingRunId': producingRunId,
      if (limit != null) 'limit': limit.toString(),
    };
    final response = await _get('images', params);
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  /// Get session statistics
  Future<Map<String, dynamic>> getSessionStats(int sessionId) async {
    final response = await _get('sessions/$sessionId/stats');
    return response['stats'] as Map<String, dynamic>? ?? {};
  }

  Future<Uint8List> downloadSessionExport(int sessionId, String format) async {
    return _downloadBytes('sessions/$sessionId/export/$format');
  }

  Future<List<PsfFieldTileRow>> getSessionPsfTiles(int sessionId) async {
    final response = await _get('sessions/$sessionId/psf-tiles');
    final tiles = response['psfTiles'] as List? ?? [];
    return tiles
        .cast<Map<String, dynamic>>()
        .map(_psfFieldTileFromJson)
        .toList();
  }

  Future<List<AstrometryResidualVectorRow>> getSessionResidualVectors(
    int sessionId,
  ) async {
    final response = await _get('sessions/$sessionId/residuals');
    final residuals = response['residuals'] as List? ?? [];
    return residuals
        .cast<Map<String, dynamic>>()
        .map(_residualVectorFromJson)
        .toList();
  }

  /// Get analytics summary
  Future<Map<String, dynamic>> getAnalyticsSummary(
      {DateTime? startDate, DateTime? endDate}) async {
    final params = <String, dynamic>{};
    if (startDate != null)
      params['startDate'] = startDate.millisecondsSinceEpoch.toString();
    if (endDate != null)
      params['endDate'] = endDate.millisecondsSinceEpoch.toString();
    final response =
        await _get('analytics/summary', params.isEmpty ? null : params);
    return response;
  }

  /// Get total integration time
  Future<Map<String, dynamic>> getTotalIntegrationTime(
      {DateTime? startDate, DateTime? endDate}) async {
    final params = <String, dynamic>{};
    if (startDate != null)
      params['startDate'] = startDate.millisecondsSinceEpoch.toString();
    if (endDate != null)
      params['endDate'] = endDate.millisecondsSinceEpoch.toString();
    final response = await _get(
        'analytics/integration-time', params.isEmpty ? null : params);
    return response;
  }

  // =========================================================================
  // Weather & Radar
  // =========================================================================

  /// Get weather radar data
  Future<Map<String, dynamic>> getWeatherRadar(double lat, double lon,
      {bool forceRefresh = false}) async {
    final response = await _get('weather/radar', {
      'lat': lat.toString(),
      'lon': lon.toString(),
      if (forceRefresh) 'refresh': 'true',
    });
    return response;
  }

  /// Get weather alerts
  Future<List<Map<String, dynamic>>> getWeatherAlerts() async {
    final response = await _get('weather/alerts');
    final alertsList = response['alerts'] as List? ?? [];
    return alertsList.cast<Map<String, dynamic>>();
  }

  /// Check safe imaging conditions
  Future<Map<String, dynamic>> checkSafeImaging() async {
    final response = await _get('weather/safe-imaging');
    return response;
  }

  /// Get weather settings
  Future<Map<String, dynamic>> getWeatherSettings() async {
    final response = await _get('weather/settings');
    return response['settings'] as Map<String, dynamic>? ?? {};
  }

  /// Update weather settings
  Future<void> updateWeatherSettings(Map<String, dynamic> settings) async {
    await _post('weather/settings', settings);
  }

  /// Clear weather cache
  Future<void> clearWeatherCache() async {
    await _post('weather/clear-cache');
  }

  // =========================================================================
  // Target Suggestions
  // =========================================================================

  /// Get target suggestions for tonight
  Future<Map<String, dynamic>> getSuggestionsForTonight({
    double? minAltitude,
    double? minScore,
    int? maxResults,
    String? sortMode,
    bool? prioritizeIncomplete,
    List<String>? objectTypes,
  }) async {
    final params = <String, dynamic>{};
    if (minAltitude != null) params['minAltitude'] = minAltitude.toString();
    if (minScore != null) params['minScore'] = minScore.toString();
    if (maxResults != null) params['maxResults'] = maxResults.toString();
    if (sortMode != null) params['sortMode'] = sortMode;
    if (prioritizeIncomplete != null)
      params['prioritizeIncomplete'] = prioritizeIncomplete.toString();
    if (objectTypes != null && objectTypes.isNotEmpty)
      params['objectTypes'] = objectTypes.join(',');
    final response =
        await _get('suggestions/tonight', params.isEmpty ? null : params);
    return response;
  }

  /// Get target score
  Future<Map<String, dynamic>> getTargetScore(int targetId) async {
    final response = await _get('suggestions/score/$targetId');
    return response;
  }

  // =========================================================================
  // Transient Alerts
  // =========================================================================

  /// Get active transient alerts
  Future<Map<String, dynamic>> getActiveTransients() async {
    final response = await _get('transients');
    return response;
  }

  /// Get transient settings
  Future<Map<String, dynamic>> getTransientSettings() async {
    final response = await _get('transients/settings');
    return response['settings'] as Map<String, dynamic>? ?? {};
  }

  /// Update transient settings
  Future<void> updateTransientSettings(Map<String, dynamic> settings) async {
    await _post('transients/settings', settings);
  }

  /// Queue a transient for observation
  Future<void> queueTransient(String transientId) async {
    await _post('transients/$transientId/queue');
  }

  /// Dismiss a transient
  Future<void> dismissTransient(String transientId) async {
    await _post('transients/$transientId/dismiss');
  }

  /// Refresh transient alerts
  Future<void> refreshTransientAlerts() async {
    await _post('transients/refresh');
  }

  /// Get queued transients
  Future<Map<String, dynamic>> getQueuedTransients() async {
    final response = await _get('transients/queued');
    return response;
  }

  // =========================================================================
  // Backup & Restore
  // =========================================================================

  /// List available backups
  Future<List<Map<String, dynamic>>> listBackups() async {
    final response = await _get('backup/list');
    final backupsList = response['backups'] as List? ?? [];
    return backupsList.cast<Map<String, dynamic>>();
  }

  /// Create a new backup
  Future<Map<String, dynamic>> createBackup(
      {String? customPath, bool autoSave = false}) async {
    final response = await _post('backup/create', {
      if (customPath != null) 'customPath': customPath,
      'autoSave': autoSave,
    });
    return response;
  }

  /// Restore from a backup
  Future<Map<String, dynamic>> restoreBackup(String filePath,
      {bool replaceExisting = false}) async {
    final response = await _post('backup/restore', {
      'filePath': filePath,
      'replaceExisting': replaceExisting,
    });
    return response;
  }

  /// Delete a backup
  Future<void> deleteBackup(String backupId) async {
    await _delete('backup/$backupId');
  }

  /// Get backup metadata
  Future<Map<String, dynamic>> getBackupMetadata(String backupId) async {
    final response = await _get('backup/$backupId/metadata');
    return response;
  }

  /// Download backup file bytes
  Future<Uint8List> downloadBackup(String backupId) async {
    return _downloadBytes('backup/$backupId/download');
  }

  Future<Map<String, dynamic>> uploadBackupAndRestore(
    Uint8List bytes,
    String fileName, {
    bool replaceExisting = false,
  }) async {
    return _postRaw(
      'backup/upload-restore',
      {
        'fileName': fileName,
        'replaceExisting': replaceExisting,
      },
      bytes,
      contentType: 'application/octet-stream',
    );
  }

  Future<RemoteScienceBundle> getScienceSessionBundle(int sessionId) async {
    final response = await _get('science/session/$sessionId/bundle');
    return RemoteScienceBundle(
      photometry: _rowsFromJson<PhotometryMeasurementRow>(
        response['photometry'],
        PhotometryMeasurementRow.fromJson,
      ),
      calibrations: _rowsFromJson<FramePhotometricCalibrationRow>(
        response['calibrations'],
        FramePhotometricCalibrationRow.fromJson,
      ),
      transparency: _rowsFromJson<TransparencySampleRow>(
        response['transparency'],
        TransparencySampleRow.fromJson,
      ),
      psfTiles: _rowsFromJson<PsfFieldTileRow>(
        response['psfTiles'],
        PsfFieldTileRow.fromJson,
      ),
      frameQuality: _rowsFromJson<ScienceFrameQualityMetricsRow>(
        response['frameQuality'],
        ScienceFrameQualityMetricsRow.fromJson,
      ),
      tileMetrics: _rowsFromJson<ScienceTileMetricRow>(
        response['tileMetrics'],
        ScienceTileMetricRow.fromJson,
      ),
      residuals: _rowsFromJson<AstrometryResidualVectorRow>(
        response['residuals'],
        AstrometryResidualVectorRow.fromJson,
      ),
      movingObjects: _rowsFromJson<MovingObjectCandidateRow>(
        response['movingObjects'],
        MovingObjectCandidateRow.fromJson,
      ),
      lineRatios: _rowsFromJson<LineRatioProductRow>(
        response['lineRatios'],
        LineRatioProductRow.fromJson,
      ),
    );
  }

  Future<RemoteScienceBundle> getSessionlessScienceBundle() async {
    final response = await _get('science/sessionless/recent');
    return RemoteScienceBundle(
      photometry: _rowsFromJson<PhotometryMeasurementRow>(
        response['photometry'],
        PhotometryMeasurementRow.fromJson,
      ),
      calibrations: _rowsFromJson<FramePhotometricCalibrationRow>(
        response['calibrations'],
        FramePhotometricCalibrationRow.fromJson,
      ),
      transparency: _rowsFromJson<TransparencySampleRow>(
        response['transparency'],
        TransparencySampleRow.fromJson,
      ),
      psfTiles: _rowsFromJson<PsfFieldTileRow>(
        response['psfTiles'],
        PsfFieldTileRow.fromJson,
      ),
      frameQuality: _rowsFromJson<ScienceFrameQualityMetricsRow>(
        response['frameQuality'],
        ScienceFrameQualityMetricsRow.fromJson,
      ),
      tileMetrics: _rowsFromJson<ScienceTileMetricRow>(
        response['tileMetrics'],
        ScienceTileMetricRow.fromJson,
      ),
      residuals: _rowsFromJson<AstrometryResidualVectorRow>(
        response['residuals'],
        AstrometryResidualVectorRow.fromJson,
      ),
      movingObjects: _rowsFromJson<MovingObjectCandidateRow>(
        response['movingObjects'],
        MovingObjectCandidateRow.fromJson,
      ),
      lineRatios: _rowsFromJson<LineRatioProductRow>(
        response['lineRatios'],
        LineRatioProductRow.fromJson,
      ),
    );
  }

  Future<List<PhotometricTransformRow>> getPhotometricTransforms({
    int? profileId,
  }) async {
    final response = await _get(
      'science/transforms',
      profileId == null ? null : {'profileId': profileId.toString()},
    );
    return _rowsFromJson<PhotometricTransformRow>(
      response['transforms'],
      PhotometricTransformRow.fromJson,
    );
  }

  Future<List<CatalogStarMatch>> matchPhotometricCalibrationStars(
    int imageId,
  ) async {
    final response = await _post(
      'science/calibration/image/$imageId/match-stars',
      const {},
    );
    return _rowsFromJson<CatalogStarMatch>(
      response['starMatches'],
      CatalogStarMatch.fromJson,
    );
  }

  Future<PhotometricTransformCoefficients?> computePhotometricTransform({
    required List<CatalogStarMatch> starMatches,
    required String filterName,
    int? equipmentProfileId,
  }) async {
    final response = await _post(
      'science/calibration/compute-transform',
      {
        'starMatches': starMatches.map((match) => match.toJson()).toList(),
        'filterName': filterName,
        if (equipmentProfileId != null)
          'equipmentProfileId': equipmentProfileId,
      },
    );
    final coefficients = response['coefficients'];
    if (coefficients is Map<String, dynamic>) {
      return PhotometricTransformCoefficients.fromJson(coefficients);
    }
    if (coefficients is Map) {
      return PhotometricTransformCoefficients.fromJson(
        coefficients.cast<String, dynamic>(),
      );
    }
    return null;
  }

  Future<int> savePhotometricTransform(
    PhotometricTransformCoefficients coefficients,
  ) async {
    final response = await _post(
      'science/calibration/save-transform',
      {'coefficients': coefficients.toJson()},
    );
    return (response['id'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> generateSessionLineRatios(int sessionId) async {
    return _post('science/session/$sessionId/generate-line-ratios', {});
  }

  Future<Map<String, String>> getScienceSettings() async {
    final response = await _get('science/settings');
    return (response['settings'] as Map? ?? const {})
        .cast<String, dynamic>()
        .map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> updateScienceSettings(Map<String, String> settings) async {
    await _post('science/settings', {'settings': settings});
  }

  Future<ScienceSessionConfig?> getScienceSessionConfig(int sessionId) async {
    final response = await _get('science/session/$sessionId/config');
    final config = response['config'];
    if (config is Map<String, dynamic>) {
      return ScienceSessionConfig.fromJson(config);
    }
    if (config is Map) {
      return ScienceSessionConfig.fromJson(config.cast<String, dynamic>());
    }
    return null;
  }

  Future<void> updateScienceSessionConfig(
    int sessionId,
    ScienceSessionConfig config,
  ) async {
    await _post('science/session/$sessionId/config', {
      'config': config.toJson(),
    });
  }

  Future<Uint8List> exportSessionAavso(
    int sessionId, {
    required String targetStarName,
    String? filterBand,
    String? chartId,
  }) async {
    return _postRawBytes(
      'science/session/$sessionId/export/aavso',
      {
        'targetStarName': targetStarName,
        if (filterBand != null && filterBand.isNotEmpty)
          'filterBand': filterBand,
        if (chartId != null && chartId.isNotEmpty) 'chartId': chartId,
      },
    );
  }

  Future<Uint8List> generateObservationReport(int sessionId) async {
    return _downloadBytes('science/session/$sessionId/report/pdf');
  }

  // =========================================================================
  // Remote Filesystem
  // =========================================================================

  Future<RemoteDirectoryListing> browseRemoteDirectories({String? path}) async {
    final response = await _get(
      'files/browse',
      path == null || path.isEmpty ? null : {'path': path},
    );
    return RemoteDirectoryListing.fromJson(response);
  }

  Future<Map<String, dynamic>> validateRemoteDirectory(
    String path, {
    bool mustExist = false,
    bool mustBeWritable = false,
  }) async {
    return _post('files/validate', {
      'path': path,
      'mustExist': mustExist,
      'mustBeWritable': mustBeWritable,
    });
  }

  // =========================================================================
  // Framing & Centering
  // =========================================================================

  /// Slew to target coordinates
  Future<void> slewToTarget(double ra, double dec) async {
    await _post('framing/slew-to-target', {
      'ra': ra,
      'dec': dec,
    });
  }

  /// Center on target with plate solving
  Future<Map<String, dynamic>> centerOnTarget({
    required double ra,
    required double dec,
    int? maxIterations,
    double? toleranceArcsec,
    double? exposureTime,
    int? binning,
    int? gain,
    bool? syncMount,
  }) async {
    final response = await _post('framing/center-on-target', {
      'ra': ra,
      'dec': dec,
      if (maxIterations != null) 'maxIterations': maxIterations,
      if (toleranceArcsec != null) 'toleranceArcsec': toleranceArcsec,
      if (exposureTime != null) 'exposureTime': exposureTime,
      if (binning != null) 'binning': binning,
      if (gain != null) 'gain': gain,
      if (syncMount != null) 'syncMount': syncMount,
    });
    return response;
  }

  /// Sync mount to coordinates
  Future<void> syncMountToCoordinates(double ra, double dec) async {
    await _post('framing/sync', {
      'ra': ra,
      'dec': dec,
    });
  }

  /// Get current mount position
  Future<Map<String, dynamic>> getCurrentPosition() async {
    final response = await _get('framing/current-position');
    return response;
  }

  /// Rotate to angle
  Future<void> rotateTo(double angle) async {
    await _post('framing/rotate-to', {'angle': angle});
  }

  /// Abort current slew
  Future<void> abortSlew() async {
    await _post('framing/abort-slew');
  }

  /// Park the mount
  Future<void> parkMountFraming() async {
    await _post('framing/park');
  }

  /// Unpark the mount
  Future<void> unparkMountFraming() async {
    await _post('framing/unpark');
  }

  /// Push a framing target to the imaging host (Plan Tonight handoff).
  Future<void> framingSetTarget({
    required double ra,
    required double dec,
    required String name,
  }) async {
    await _post('framing/set-target', {
      'ra': ra,
      'dec': dec,
      'name': name,
    });
  }

  // ===========================================================================
  // Dome Control
  // ===========================================================================

  /// Open dome shutter
  Future<void> domeOpen() async {
    await _post('dome/open');
  }

  /// Close dome shutter
  Future<void> domeClose() async {
    await _post('dome/close');
  }

  /// Slew dome to azimuth
  Future<void> domeSlew(double azimuth) async {
    await _post('dome/slew', {'azimuth': azimuth});
  }

  /// Enable/disable dome-mount sync
  Future<void> domeSync(bool enable) async {
    await _post('dome/sync', {'enable': enable});
  }

  /// Park dome
  Future<void> domePark() async {
    await _post('dome/park');
  }

  /// Move dome to home position
  Future<void> domeHome() async {
    await _post('dome/home');
  }

  /// Halt dome movement
  Future<void> domeHalt() async {
    await _post('dome/halt');
  }

  /// Get dome status
  Future<Map<String, dynamic>> getDomeStatus() async {
    return await _get('dome/status');
  }

  /// Get dome capabilities
  Future<Map<String, dynamic>> getDomeCapabilities() async {
    return await _get('dome/capabilities');
  }

  // ===========================================================================
  // Safety Monitor
  // ===========================================================================

  /// Get safety status
  Future<Map<String, dynamic>> getSafetyStatus({String? deviceId}) async {
    return await _get(
      'safety/status',
      deviceId != null ? {'deviceId': deviceId} : null,
    );
  }

  /// Get safety settings
  Future<Map<String, dynamic>> getSafetySettings() async {
    return await _get('safety/settings');
  }

  /// Update safety settings
  Future<void> updateSafetySettings(Map<String, dynamic> settings) async {
    await _post('safety/settings', settings);
  }

  /// Acknowledge unsafe condition
  Future<void> acknowledgeSafetyCondition({
    required String reason,
    int? durationMinutes,
  }) async {
    await _post('safety/acknowledge', {
      'reason': reason,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
    });
  }

  // ===========================================================================
  // Switch Control
  // ===========================================================================

  /// Get all switch states
  Future<Map<String, dynamic>> getSwitchStatus() async {
    return await _get('switch/status');
  }

  /// Set a switch value
  Future<void> setSwitch({
    required int switchId,
    required dynamic value,
  }) async {
    await _post('switch/set', {
      'switchId': switchId,
      'value': value,
    });
  }

  // ===========================================================================
  // Cover Calibrator
  // ===========================================================================

  /// Get cover calibrator status
  Future<Map<String, dynamic>> getCoverStatus() async {
    return await _get('cover/status');
  }

  /// Open cover
  Future<void> coverOpen() async {
    await _post('cover/open');
  }

  /// Close cover
  Future<void> coverClose() async {
    await _post('cover/close');
  }

  /// Set calibrator brightness
  Future<void> setCoverBrightness(int brightness) async {
    await _post('cover/brightness', {'brightness': brightness});
  }

  /// Turn calibrator on
  Future<void> calibratorOn({int? brightness}) async {
    await _post('cover/calibrator-on', {
      if (brightness != null) 'brightness': brightness,
    });
  }

  /// Turn calibrator off
  Future<void> calibratorOff() async {
    await _post('cover/calibrator-off');
  }

  // ===========================================================================
  // Scheduler (Astronomical Calculations)
  // ===========================================================================

  /// Calculate altitude of object at given time
  Future<Map<String, dynamic>> getAltitude({
    required double ra,
    required double dec,
    DateTime? time,
  }) async {
    return await _get('scheduler/altitude', {
      'ra': ra,
      'dec': dec,
      if (time != null) 'time': time.toIso8601String(),
    });
  }

  /// Get transit time for object
  Future<Map<String, dynamic>> getTransitTime({
    required double ra,
    required double dec,
  }) async {
    return await _get('scheduler/transit-time', {'ra': ra, 'dec': dec});
  }

  /// Get rise and set times for object
  Future<Map<String, dynamic>> getRiseSetTimes({
    required double ra,
    required double dec,
    double? minAltitude,
  }) async {
    return await _get('scheduler/rise-set', {
      'ra': ra,
      'dec': dec,
      if (minAltitude != null) 'minAltitude': minAltitude,
    });
  }

  /// Get hours object is above altitude
  Future<Map<String, dynamic>> getHoursAboveHorizon({
    required double ra,
    required double dec,
    double minAltitude = 30.0,
  }) async {
    return await _get('scheduler/hours-above-horizon', {
      'ra': ra,
      'dec': dec,
      'minAltitude': minAltitude,
    });
  }

  /// Optimize target order for imaging
  Future<Map<String, dynamic>> optimizeTargets({
    required List<int> targetIds,
    String strategy = 'transit',
    double minAltitude = 30.0,
  }) async {
    return await _post('scheduler/optimize-targets', {
      'targetIds': targetIds,
      'strategy': strategy,
      'minAltitude': minAltitude,
    });
  }

  /// Get twilight times for tonight
  Future<Map<String, dynamic>> getTwilightTimes({DateTime? date}) async {
    return await _get(
      'scheduler/twilight-times',
      date != null ? {'date': date.toIso8601String()} : null,
    );
  }

  /// Get moon information
  Future<Map<String, dynamic>> getMoonInfo({DateTime? date}) async {
    return await _get(
      'scheduler/moon-info',
      date != null ? {'date': date.toIso8601String()} : null,
    );
  }

  // ===========================================================================
  // Focus Model
  // ===========================================================================

  /// Get all focus data points
  Future<Map<String, dynamic>> getFocusModelData() async {
    return await _get('focus-model/data');
  }

  /// Add a focus data point
  Future<void> addFocusDataPoint({
    required double temperature,
    required int position,
    double? hfr,
    String? filter,
  }) async {
    await _post('focus-model/add-point', {
      'temperature': temperature,
      'position': position,
      if (hfr != null) 'hfr': hfr,
      if (filter != null) 'filter': filter,
    });
  }

  /// Clear all focus data points
  Future<void> clearFocusModelData() async {
    await _delete('focus-model/clear');
  }

  /// Get current focus model
  Future<Map<String, dynamic>> getFocusModel() async {
    return await _get('focus-model/model');
  }

  /// Predict focus position for temperature
  Future<Map<String, dynamic>> predictFocusPosition({
    required double temperature,
    String? filter,
  }) async {
    return await _get('focus-model/predict', {
      'temperature': temperature,
      if (filter != null) 'filter': filter,
    });
  }

  /// Get per-filter focus offsets
  Future<Map<String, dynamic>> getFilterFocusOffsets() async {
    return await _get('focus-model/filter-offsets');
  }

  /// Set per-filter focus offsets
  Future<void> setFilterFocusOffsets({
    required String referenceFilter,
    required Map<String, int> offsets,
  }) async {
    await _post('focus-model/filter-offsets', {
      'referenceFilter': referenceFilter,
      'offsets': offsets,
    });
  }

  /// Check if refocus needed based on temperature drift
  Future<Map<String, dynamic>> shouldRefocus({
    required double currentTemp,
    required double lastFocusTemp,
    int? maxDriftSteps,
  }) async {
    return await _get('focus-model/should-refocus', {
      'currentTemp': currentTemp,
      'lastFocusTemp': lastFocusTemp,
      if (maxDriftSteps != null) 'maxDriftSteps': maxDriftSteps,
    });
  }

  /// Export focus data as JSON
  Future<Map<String, dynamic>> exportFocusModel() async {
    return await _get('focus-model/export');
  }

  /// Import focus data from JSON
  Future<void> importFocusModel(Map<String, dynamic> data) async {
    await _post('focus-model/import', data);
  }

  // ===========================================================================
  // PHD2 Additional Endpoints
  // ===========================================================================

  /// Get PHD2 star image
  Future<Map<String, dynamic>> getPhd2StarImage({int size = 50}) async {
    return await _get('phd2/star-image', {'size': size});
  }

  /// Get PHD2 algorithm parameter names
  Future<List<String>> getPhd2AlgoParamNames(String axis) async {
    final response = await _get('phd2/algo-params', {'axis': axis});
    return (response['parameters'] as List).cast<String>();
  }

  /// Get PHD2 algorithm parameter value
  Future<double> getPhd2AlgoParam({
    required String axis,
    required String name,
  }) async {
    final response =
        await _get('phd2/algo-param', {'axis': axis, 'name': name});
    return (response['value'] as num).toDouble();
  }

  /// Set PHD2 algorithm parameter
  Future<void> setPhd2AlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    await _post('phd2/algo-param', {
      'axis': axis,
      'name': name,
      'value': value,
    });
  }

  // ===========================================================================
  // Planetarium Support
  // ===========================================================================

  /// Get current mount position for planetarium FOV overlay
  Future<Map<String, dynamic>> getPlanetariumMountPosition() async {
    return await _get('planetarium/mount-position');
  }

  /// Get FOV configuration for planetarium
  Future<Map<String, dynamic>> getPlanetariumFovConfig() async {
    return await _get('planetarium/fov-config');
  }

  /// Slew to coordinates from planetarium
  Future<void> planetariumSlewTo({
    required double ra,
    required double dec,
  }) async {
    await _post('planetarium/slew-to', {'ra': ra, 'dec': dec});
  }

  /// Center on coordinates from planetarium with plate solving
  Future<Map<String, dynamic>> planetariumCenterOn({
    required double ra,
    required double dec,
    int? maxIterations,
    double? toleranceArcsec,
  }) async {
    return await _post('planetarium/center-on', {
      'ra': ra,
      'dec': dec,
      if (maxIterations != null) 'maxIterations': maxIterations,
      if (toleranceArcsec != null) 'toleranceArcsec': toleranceArcsec,
    });
  }

  /// Sync mount to coordinates from planetarium
  Future<void> planetariumSyncTo({
    required double ra,
    required double dec,
  }) async {
    await _post('planetarium/sync-to', {'ra': ra, 'dec': dec});
  }

  /// Search catalog for objects
  Future<Map<String, dynamic>> planetariumCatalogSearch(String query) async {
    return await _get('planetarium/catalog/search', {'query': query});
  }

  /// Get objects in a region
  Future<Map<String, dynamic>> planetariumCatalogRegion({
    required double ra,
    required double dec,
    required double radius,
    double? minMagnitude,
    double? maxMagnitude,
    int? limit,
  }) async {
    return await _get('planetarium/catalog/region', {
      'ra': ra,
      'dec': dec,
      'radius': radius,
      if (minMagnitude != null) 'minMagnitude': minMagnitude,
      if (maxMagnitude != null) 'maxMagnitude': maxMagnitude,
      if (limit != null) 'limit': limit,
    });
  }

  /// Get detailed object info
  Future<Map<String, dynamic>> planetariumGetObject(String objectId) async {
    return await _get(
        'planetarium/catalog/object/${Uri.encodeComponent(objectId)}');
  }

  /// Get WebSocket subscription info for real-time updates
  Future<Map<String, dynamic>> getPlanetariumSubscribeInfo() async {
    return await _get('planetarium/subscribe-info');
  }

  /// Get observer location for planetarium calculations
  Future<Map<String, dynamic>> getPlanetariumLocation() async {
    return await _get('planetarium/location');
  }

  PsfFieldTileRow _psfFieldTileFromJson(Map<String, dynamic> json) {
    return PsfFieldTileRow(
      id: json['id'] as int,
      capturedImageId: json['capturedImageId'] as int?,
      sessionId: json['sessionId'] as int?,
      tileRow: json['tileRow'] as int? ?? 0,
      tileCol: json['tileCol'] as int? ?? 0,
      starCount: json['starCount'] as int? ?? 0,
      medianFwhm: (json['medianFwhm'] as num?)?.toDouble() ?? 0.0,
      medianHfr: (json['medianHfr'] as num?)?.toDouble() ?? 0.0,
      medianEccentricity:
          (json['medianEccentricity'] as num?)?.toDouble() ?? 0.0,
      roundness: (json['roundness'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
    );
  }

  AstrometryResidualVectorRow _residualVectorFromJson(
    Map<String, dynamic> json,
  ) {
    return AstrometryResidualVectorRow(
      id: json['id'] as int,
      capturedImageId: json['capturedImageId'] as int?,
      sessionId: json['sessionId'] as int?,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      dxArcsec: (json['dxArcsec'] as num?)?.toDouble() ?? 0.0,
      dyArcsec: (json['dyArcsec'] as num?)?.toDouble() ?? 0.0,
      magnitudeArcsec: (json['magnitudeArcsec'] as num?)?.toDouble() ?? 0.0,
      recommendationCode: json['recommendationCode'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
    );
  }

  // ===========================================================================
  // P1-2 / P1-3 — Long-running operation job client API
  // ===========================================================================

  /// Snapshot of a server-side job. Mirrors the wire shape of
  /// `apps/desktop/lib/headless_api/job_manager.dart#Job.toJson`. We
  /// deliberately keep the model loose (no enum for state) so a server
  /// that adds a new state value does not crash an older client; the
  /// caller branches on the string.
  Future<RemoteJob> getJob(String jobId) async {
    final response = await _get('jobs/$jobId');
    return RemoteJob.fromJson(response);
  }

  /// Cancel a long-running job. Throws when the server replies 409 (the
  /// job is already terminal) — the caller may want to log it but not
  /// abort their workflow.
  Future<RemoteJob> cancelJob(String jobId) async {
    final response = await _post('jobs/$jobId/cancel');
    return RemoteJob.fromJson(response);
  }

  /// List jobs (filtered).
  Future<List<RemoteJob>> listJobs({String? state, String? operation}) async {
    final response = await _get('jobs', {
      if (state != null) 'state': state,
      if (operation != null) 'operation': operation,
    });
    final raw = response['jobs'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(RemoteJob.fromJson)
        .toList(growable: false);
  }

  /// Stream WS-broadcast snapshots for a single [jobId]. The stream
  /// terminates when the job reaches a terminal state or when the
  /// underlying event subscription closes (server restart, network
  /// drop). Callers that want to keep observing across reconnects must
  /// re-subscribe after `connectionStateStream` emits `connected`.
  Stream<RemoteJob> watchJob(String jobId) {
    return eventStream
        .where((e) =>
            e.category == EventCategory.job && e.data['jobId'] == jobId)
        .map((e) => RemoteJob.fromEventData(e.data));
  }

  /// Await the terminal state of [jobId]. Returns the final snapshot
  /// (succeeded / failed / cancelled). Polls the snapshot endpoint when
  /// the WS stream is unavailable so we don't deadlock if the operator
  /// is on a flaky link.
  ///
  /// [timeout] caps the wait. The audit's spec recommends:
  ///   * 30 minutes for autofocus
  ///   * 5 minutes for plate solve
  ///   * 10 minutes for center-on-target
  ///   * 5 minutes for mosaic plan
  ///   * 10 minutes for polar alignment
  Future<RemoteJob> awaitJobCompletion(
    String jobId, {
    Duration timeout = const Duration(minutes: 10),
    Duration pollInterval = const Duration(seconds: 5),
  }) async {
    final initial = await getJob(jobId);
    if (_isTerminalRemoteJobState(initial.state)) {
      return initial;
    }
    final completer = Completer<RemoteJob>();
    StreamSubscription<RemoteJob>? sub;
    Timer? pollTimer;
    Timer? timeoutTimer;
    void finish(RemoteJob job) {
      if (completer.isCompleted) return;
      sub?.cancel();
      pollTimer?.cancel();
      timeoutTimer?.cancel();
      completer.complete(job);
    }

    sub = watchJob(jobId).listen((snapshot) {
      if (_isTerminalRemoteJobState(snapshot.state)) {
        finish(snapshot);
      }
    });

    // Concurrent poll to catch terminations the WS stream might miss
    // (e.g. when we reconnect after the JobCompleted frame).
    pollTimer = Timer.periodic(pollInterval, (_) async {
      try {
        final snap = await getJob(jobId);
        if (_isTerminalRemoteJobState(snap.state)) {
          finish(snap);
        }
      } catch (_) {
        // Silent retry — the next poll tick will try again. The timeout
        // protects against indefinite hangs.
      }
    });

    timeoutTimer = Timer(timeout, () {
      if (completer.isCompleted) return;
      sub?.cancel();
      pollTimer?.cancel();
      completer.completeError(
        TimeoutException(
            'Job $jobId did not reach a terminal state within $timeout'),
      );
    });

    return completer.future;
  }

  static bool _isTerminalRemoteJobState(String state) {
    return state == 'succeeded' || state == 'failed' || state == 'cancelled';
  }

  // ===========================================================================
  // P1-5 — Session ownership client API
  // ===========================================================================

  /// POST /api/session/claim — returns true on success, false when the
  /// slot is already taken.
  Future<bool> claimSession({String? clientName, String? clientId}) async {
    final uri = Uri.parse(
        'http://$serverHost:$serverPort/api/session/claim');
    final headers = _addAuthHeaders({}, endpoint: 'session/claim');
    headers[HttpHeaders.contentTypeHeader] = 'application/json';
    final response = await _http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        if (clientName != null) 'clientName': clientName,
        if (clientId != null) 'clientId': clientId,
      }),
    );
    if (response.statusCode == 200) {
      return true;
    }
    if (response.statusCode == 409) {
      return false; // Slot taken — caller may decide to take-over.
    }
    throw _parseErrorResponse(
        response.statusCode, response.body, 'POST', 'session/claim');
  }

  /// POST /api/session/take-over — always succeeds (any control-scope
  /// client can preempt). The previous owner observes the displacement
  /// via the WS event stream.
  Future<void> takeOverSession({
    required String reason,
    String? clientName,
    String? clientId,
  }) async {
    await _post('session/take-over', {
      'reason': reason,
      if (clientName != null) 'clientName': clientName,
      if (clientId != null) 'clientId': clientId,
    });
  }

  /// POST /api/session/release — voluntary release by the owner. 403 if
  /// called by a non-owner.
  Future<void> releaseSession() async {
    await _post('session/release');
  }

  /// GET /api/session/status — combined snapshot + caller-relative view.
  Future<RemoteSessionStatus> getSessionStatus() async {
    final response = await _get('session/status');
    return RemoteSessionStatus.fromJson(response);
  }

  // =========================================================================
  // P1-11 — Remote OTA update management.
  //
  // Mirrors the headless server's `/api/system/version` and
  // `/api/system/update/*` surface. Long-running operations (check,
  // download, apply, rollback) return a [RemoteJob] handle; the caller
  // polls via [getJob]/[awaitJobCompletion] or subscribes to the WS
  // event stream filtered by `category == EventCategory.system`.
  // =========================================================================

  /// GET /api/system/version — current build info.
  Future<RemoteVersionInfo> getSystemVersion() async {
    final response = await _get('system/version');
    return RemoteVersionInfo.fromJson(response);
  }

  /// POST /api/system/update/check — dispatch a check job.
  Future<RemoteJob> checkForUpdate({String? channel}) async {
    final response = await _post('system/update/check', {
      if (channel != null && channel.isNotEmpty) 'channel': channel,
    });
    return RemoteJob.fromJson(response);
  }

  /// GET /api/system/update/status — current update phase snapshot.
  Future<RemoteUpdateStatus> getUpdateStatus() async {
    final response = await _get('system/update/status');
    return RemoteUpdateStatus.fromJson(response);
  }

  /// POST /api/system/update/download — start downloading the staged
  /// update. Returns a job handle for progress tracking.
  Future<RemoteJob> downloadUpdate() async {
    final response = await _post('system/update/download');
    return RemoteJob.fromJson(response);
  }

  /// POST /api/system/update/apply — apply the staged update. The server
  /// process may exit during the apply (the host is replaced by the
  /// updater binary), so clients should reconnect after the WS drops.
  Future<RemoteJob> applyUpdate() async {
    final response = await _post('system/update/apply');
    return RemoteJob.fromJson(response);
  }

  /// POST /api/system/update/abort — abort any in-flight check or
  /// download. The response carries the list of jobIds that were
  /// cancelled.
  Future<RemoteJob> abortUpdate() async {
    final response = await _post('system/update/abort');
    // The abort endpoint returns `{aborted: bool, cancelledJobs: [...]}`
    // rather than a single Job snapshot. Synthesise a RemoteJob from
    // the first cancelled job id (or a synthetic one when there were
    // none) so the caller sees a consistent return type.
    final cancelled = response['cancelledJobs'];
    final firstJobId = cancelled is List && cancelled.isNotEmpty
        ? cancelled.first.toString()
        : 'aborted';
    return RemoteJob(
      jobId: firstJobId,
      operation: 'system.update.abort',
      state: 'cancelled',
    );
  }

  /// GET /api/system/update/staged — info about the staged update, or
  /// null when nothing is staged.
  Future<RemoteStagedUpdate?> getStagedUpdate() async {
    final response = await _get('system/update/staged');
    final raw = response['staged'];
    if (raw == null) return null;
    if (raw is! Map) return null;
    return RemoteStagedUpdate.fromJson(
      Map<String, dynamic>.from(raw),
    );
  }

  /// DELETE /api/system/update/staged — discard the staged update.
  Future<void> discardStagedUpdate() async {
    await _delete('system/update/staged');
  }

  // =========================================================================
  // P1-10 — Remote calibration library management.
  // =========================================================================

  /// GET /api/calibration/darks — filtered listing.
  Future<List<RemoteDarkLibraryEntry>> listDarks({
    double? exposureSeconds,
    int? gain,
    double? temperatureCelsius,
    int? limit,
  }) async {
    final params = <String, dynamic>{};
    if (exposureSeconds != null) params['exposureSeconds'] = exposureSeconds;
    if (gain != null) params['gain'] = gain;
    if (temperatureCelsius != null) {
      params['temperatureC'] = temperatureCelsius;
    }
    if (limit != null) params['limit'] = limit;
    final response =
        await _get('calibration/darks', params.isEmpty ? null : params);
    return _rowsFromJson(response['darks'], RemoteDarkLibraryEntry.fromJson);
  }

  /// GET /api/calibration/darks/{id}.
  Future<RemoteDarkLibraryEntry> getDark(int id) async {
    final response = await _get('calibration/darks/$id');
    final row = response['dark'];
    if (row is! Map) {
      throw StateError('Malformed darks/{id} response: missing `dark` field');
    }
    return RemoteDarkLibraryEntry.fromJson(row.cast<String, dynamic>());
  }

  /// POST /api/calibration/darks — register an already-on-disk file.
  Future<RemoteDarkLibraryEntry> registerDark({
    required String filePath,
    required double exposureDuration,
    double? sensorTempC,
    int gain = 0,
    int offset = 0,
    int binX = 1,
    int binY = 1,
    String frameType = 'dark',
    int? width,
    int? height,
    int? frameCount,
    String? masterPath,
  }) async {
    final body = <String, dynamic>{
      'filePath': filePath,
      'exposureDuration': exposureDuration,
      if (sensorTempC != null) 'sensorTempC': sensorTempC,
      'gain': gain,
      'offset': offset,
      'binX': binX,
      'binY': binY,
      'frameType': frameType,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (frameCount != null) 'frameCount': frameCount,
      if (masterPath != null) 'masterPath': masterPath,
    };
    final response = await _post('calibration/darks', body);
    return RemoteDarkLibraryEntry.fromJson(
        (response['dark'] as Map).cast<String, dynamic>());
  }

  /// POST /api/calibration/darks/upload — upload a FITS file with metadata.
  ///
  /// The server stores the file under `$DATA_DIR/calibration/darks/` and
  /// inserts a row referencing it. We send the FITS as the raw body and
  /// the metadata as a JSON-encoded `meta` query parameter.
  Future<RemoteDarkLibraryEntry> uploadDark({
    required File darkFile,
    required DarkUploadMetadata metadata,
    String? fileName,
  }) async {
    final bytes = await darkFile.readAsBytes();
    final name = fileName ?? p.basename(darkFile.path);
    final meta = jsonEncode(metadata.toJson());
    final response = await _postRaw(
      'calibration/darks/upload',
      {'meta': meta, 'fileName': name},
      bytes,
      contentType: 'application/octet-stream',
    );
    return RemoteDarkLibraryEntry.fromJson(
        (response['dark'] as Map).cast<String, dynamic>());
  }

  /// POST /api/calibration/darks/find-match.
  Future<RemoteDarkLibraryEntry?> findMatchingDark({
    required double exposureDuration,
    int gain = 0,
    int offset = 0,
    int binX = 1,
    int binY = 1,
    double? sensorTempC,
    String frameType = 'dark',
    Map<String, dynamic>? tolerances,
  }) async {
    final body = <String, dynamic>{
      'exposureDuration': exposureDuration,
      'gain': gain,
      'offset': offset,
      'binX': binX,
      'binY': binY,
      if (sensorTempC != null) 'sensorTempC': sensorTempC,
      'frameType': frameType,
      if (tolerances != null) 'tolerances': tolerances,
    };
    try {
      final response = await _post('calibration/darks/find-match', body);
      return RemoteDarkLibraryEntry.fromJson(
          (response['dark'] as Map).cast<String, dynamic>());
    } on ServerError catch (e) {
      // [Wave 6D error parsing] — handler returns 404 + the structured
      // envelope {code: 'no_matching_dark'} when no dark satisfies the
      // requested parameters. Treating it as the legitimate "no match"
      // outcome (null) instead of an exception.
      if (e.code == 'no_matching_dark' ||
          (e.httpStatus == 404 && e.code.contains('no_matching'))) {
        return null;
      }
      rethrow;
    } on dart_error.NightshadeError catch (e) {
      // The handler returns 404 with `error: no_matching_dark` when no
      // dark matches the requested capture parameters. `_parseErrorResponse`
      // collapses the 404 into the `connection` category and stuffs the
      // server-side `error` field into the message, so we sniff for the
      // sentinel string to map the legitimate non-error outcome to null.
      if (e.category == dart_error.BackendErrorCategory.connection &&
          e.message.contains('no_matching_dark')) {
        return null;
      }
      rethrow;
    }
  }

  /// DELETE /api/calibration/darks/{id}?deleteFile=<bool>.
  Future<void> deleteDark(int id, {bool deleteFile = false}) async {
    if (deleteFile) {
      await _delete('calibration/darks/$id?deleteFile=true');
    } else {
      await _delete('calibration/darks/$id');
    }
  }

  /// POST /api/calibration/darks/backfill-sizes.
  ///
  /// Returns the raw counts map; callers usually only need to display the
  /// totals, so we don't bother wrapping in a typed model.
  Future<Map<String, int>> verifyDarkSizes() async {
    final response = await _post('calibration/darks/backfill-sizes');
    return {
      for (final entry in response.entries)
        if (entry.value is num) entry.key: (entry.value as num).toInt(),
    };
  }

  /// GET /api/calibration/flats — filtered listing.
  Future<List<RemoteFlatHistoryEntry>> listFlats({
    String? filter,
    int? equipmentProfileId,
    int? gain,
    DateTime? since,
    int? limit,
  }) async {
    final params = <String, dynamic>{};
    if (filter != null) params['filter'] = filter;
    if (equipmentProfileId != null) {
      params['equipmentProfileId'] = equipmentProfileId;
    }
    if (gain != null) params['gain'] = gain;
    if (since != null) params['since'] = since.toUtc().toIso8601String();
    if (limit != null) params['limit'] = limit;
    final response =
        await _get('calibration/flats', params.isEmpty ? null : params);
    return _rowsFromJson(response['flats'], RemoteFlatHistoryEntry.fromJson);
  }

  /// GET /api/calibration/flats/{id}.
  Future<RemoteFlatHistoryEntry> getFlat(int id) async {
    final response = await _get('calibration/flats/$id');
    return RemoteFlatHistoryEntry.fromJson(
        (response['flat'] as Map).cast<String, dynamic>());
  }

  /// POST /api/calibration/flats — record a flat-history entry.
  Future<RemoteFlatHistoryEntry> recordFlat({
    required String filter,
    required double exposureDuration,
    required int adu,
    double histogramTarget = 50.0,
    int gain = 0,
    int binning = 1,
    int? panelBrightness,
    double? skyAduRate,
    String? twilightPhase,
    int? equipmentProfileId,
  }) async {
    final body = <String, dynamic>{
      'filter': filter,
      'exposureDuration': exposureDuration,
      'adu': adu,
      'histogramTarget': histogramTarget,
      'gain': gain,
      'binning': binning,
      if (panelBrightness != null) 'panelBrightness': panelBrightness,
      if (skyAduRate != null) 'skyAduRate': skyAduRate,
      if (twilightPhase != null) 'twilightPhase': twilightPhase,
      if (equipmentProfileId != null) 'equipmentProfileId': equipmentProfileId,
    };
    final response = await _post('calibration/flats', body);
    return RemoteFlatHistoryEntry.fromJson(
        (response['flat'] as Map).cast<String, dynamic>());
  }

  /// DELETE /api/calibration/flats/{id}.
  Future<void> deleteFlat(int id) async {
    await _delete('calibration/flats/$id');
  }

  /// GET /api/calibration/flats/recommendation. Returns null when no
  /// matching history row is found.
  Future<RemoteFlatRecommendation?> getFlatRecommendation({
    required String filter,
    int? equipmentProfileId,
    int? gain,
  }) async {
    final params = <String, dynamic>{'filter': filter};
    if (equipmentProfileId != null) {
      params['equipmentProfileId'] = equipmentProfileId;
    }
    if (gain != null) params['gain'] = gain;
    final response = await _get('calibration/flats/recommendation', params);
    final recommended = response['recommended'];
    if (recommended == null || recommended is! Map) return null;
    final basedOn = recommended['basedOn'] as Map?;
    return RemoteFlatRecommendation(
      exposureDuration:
          (recommended['exposureDuration'] as num?)?.toDouble() ?? 0.0,
      basedOnFlatId: (basedOn?['flatId'] as num?)?.toInt() ?? 0,
      ageDays: (basedOn?['ageDays'] as num?)?.toInt() ?? 0,
      confidence: basedOn?['confidence'] as String? ?? 'low',
    );
  }

  /// GET /api/calibration/defect-maps — filtered list (no BLOB).
  Future<List<RemoteDefectMap>> listDefectMaps({
    String? cameraId,
    int? width,
    int? height,
    int? temperatureBucketDecicelsius,
  }) async {
    final params = <String, dynamic>{};
    if (cameraId != null) params['cameraId'] = cameraId;
    if (width != null) params['width'] = width;
    if (height != null) params['height'] = height;
    if (temperatureBucketDecicelsius != null) {
      params['temperatureBucketDecicelsius'] = temperatureBucketDecicelsius;
    }
    final response = await _get(
      'calibration/defect-maps',
      params.isEmpty ? null : params,
    );
    return _rowsFromJson(response['defectMaps'], RemoteDefectMap.fromJson);
  }

  /// GET /api/calibration/defect-maps/{id}?format=binary — fetch the
  /// packed bitmap as raw bytes.
  Future<Uint8List> getDefectMapBitmap(int id) async {
    return _downloadBytes('calibration/defect-maps/$id', {'format': 'binary'});
  }

  /// POST /api/calibration/defect-maps — register a defect map by metadata
  /// + base64 bitmap.
  Future<RemoteDefectMap> registerDefectMap({
    required String cameraId,
    required int width,
    required int height,
    required int temperatureBucketDecicelsius,
    required Uint8List bitmap,
    required int defectCount,
    String? sourceFilePath,
  }) async {
    final body = <String, dynamic>{
      'cameraId': cameraId,
      'width': width,
      'height': height,
      'temperatureBucketDecicelsius': temperatureBucketDecicelsius,
      'bitmap': base64Encode(bitmap),
      'defectCount': defectCount,
      if (sourceFilePath != null) 'sourceFilePath': sourceFilePath,
    };
    final response = await _post('calibration/defect-maps', body);
    return RemoteDefectMap.fromJson(
        (response['defectMap'] as Map).cast<String, dynamic>());
  }

  /// DELETE /api/calibration/defect-maps/{id}?deleteFile=<bool>.
  Future<void> deleteDefectMap(int id, {bool deleteFile = false}) async {
    if (deleteFile) {
      await _delete('calibration/defect-maps/$id?deleteFile=true');
    } else {
      await _delete('calibration/defect-maps/$id');
    }
  }

  /// POST /api/calibration/defect-maps/{id}/regenerate.
  Future<Map<String, dynamic>> regenerateDefectMap(int id) async {
    return _post('calibration/defect-maps/$id/regenerate');
  }

  // =========================================================================
  // P1-12 — Remote catalog management.
  // =========================================================================

  /// GET /api/catalog/status. Returns the on-disk state of every known
  /// catalog on the *server*. The mobile/desktop remote client surfaces
  /// this in the catalog management UI so a freshly-imaged server can be
  /// detected ("plate-solve will fail until you download a star catalog").
  Future<RemoteCatalogStatusResponse> getCatalogStatus() async {
    final response = await _get('catalog/status');
    return RemoteCatalogStatusResponse.fromJson(response);
  }

  /// GET /api/catalog/available. Returns the manifest of catalogs the
  /// server knows how to download. Cached server-side for 1 hour.
  Future<List<RemoteAvailableCatalog>> listAvailableCatalogs() async {
    final response = await _get('catalog/available');
    final raw = response['available'];
    if (raw is! List) {
      throw StateError('Malformed /catalog/available response: missing list');
    }
    return raw
        .whereType<Map>()
        .map((m) => RemoteAvailableCatalog.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// POST /api/catalog/download. Returns the job handle; the actual
  /// download runs in the background and progress is broadcast as
  /// `catalog`-category events on the WS stream.
  Future<RemoteJob> downloadCatalog(String name) async {
    final response = await _post('catalog/download', {'name': name});
    return RemoteJob.fromJson(response);
  }

  /// POST /api/catalog/upload. Sends the file body with `name` + `sha256`
  /// as query parameters. The server verifies the SHA-256 before
  /// installing.
  Future<RemoteCatalogInstallResult> uploadCatalog(
    File archive, {
    required String name,
    required String sha256,
  }) async {
    final bytes = await archive.readAsBytes();
    final response = await _postRaw(
      'catalog/upload',
      {'name': name, 'sha256': sha256},
      bytes,
      contentType: 'application/octet-stream',
    );
    final installed = response['installed'];
    if (installed is! Map) {
      throw StateError(
          'Malformed /catalog/upload response: missing `installed` field');
    }
    return RemoteCatalogInstallResult.fromJson(
        installed.cast<String, dynamic>());
  }

  /// POST /api/catalog/verify. Recomputes SHA-256 over every (or one)
  /// installed catalog and returns the per-name verification result.
  Future<Map<String, RemoteCatalogVerifyResult>> verifyCatalog({
    String? name,
  }) async {
    final response =
        await _post('catalog/verify', name == null ? null : {'name': name});
    final verified = response['verified'];
    if (verified is! Map) {
      throw StateError(
          'Malformed /catalog/verify response: missing `verified` field');
    }
    return verified.map((key, value) {
      if (value is! Map) {
        throw StateError(
            'Malformed verify result for `$key`: expected object');
      }
      return MapEntry(
        key.toString(),
        RemoteCatalogVerifyResult.fromJson(value.cast<String, dynamic>()),
      );
    });
  }

  /// DELETE /api/catalog/{name}.
  Future<void> uninstallCatalog(String name) async {
    await _delete('catalog/$name');
  }

  /// POST /api/catalog/reload. Drops the server's cached catalog loaders
  /// so subsequent searches re-parse the on-disk files.
  Future<void> reloadCatalogs() async {
    await _post('catalog/reload');
  }

  // =========================================================================
  // P2-8 — read-only DB endpoints. Each returns a paginated `{items, total}`
  // envelope. Methods live on NetworkBackend (not the NightshadeBackend
  // interface) because the local FfiBackend already exposes these via Drift
  // DAOs; the network path is the only one that needs an explicit GET.
  // =========================================================================

  /// GET /api/sequence-runs?sequenceId=&limit=&offset=
  Future<RemotePage<RemoteSequenceRun>> fetchSequenceRuns({
    int? sequenceId,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('sequence-runs', {
      if (sequenceId != null) 'sequenceId': sequenceId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteSequenceRun.fromJson);
  }

  /// GET /api/notes-journal?equipmentProfileId=&limit=&offset=
  Future<RemotePage<RemoteNotesJournalEntry>> fetchNotesJournal({
    int? equipmentProfileId,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('notes-journal', {
      if (equipmentProfileId != null)
        'equipmentProfileId': equipmentProfileId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteNotesJournalEntry.fromJson);
  }

  /// GET /api/guide-rms-history?sinceMs=&untilMs=&limit=&offset=
  Future<RemotePage<RemoteGuideRmsHistoryEntry>> fetchGuideRmsHistory({
    int? sinceMs,
    int? untilMs,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('guide-rms-history', {
      if (sinceMs != null) 'sinceMs': sinceMs.toString(),
      if (untilMs != null) 'untilMs': untilMs.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteGuideRmsHistoryEntry.fromJson);
  }

  /// GET /api/polar-alignment-history?equipmentProfileId=&limit=&offset=
  Future<RemotePage<RemotePolarAlignmentHistoryEntry>>
      fetchPolarAlignmentHistory({
    int? equipmentProfileId,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('polar-alignment-history', {
      if (equipmentProfileId != null)
        'equipmentProfileId': equipmentProfileId.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(
      response,
      RemotePolarAlignmentHistoryEntry.fromJson,
    );
  }

  /// GET /api/db/dark-library?gainMin=&gainMax=&temperatureC=&exposureSecs=&limit=&offset=
  ///
  /// Returns the raw `dark_library` Drift rows. The pre-existing
  /// `listDarks()` method (P1-10) projects the same table through the
  /// `RemoteDarkLibraryEntry` wire model used by the calibration UI, but
  /// elides several columns (master frame path, master count) that the
  /// P2-8 read surface intentionally exposes. Hence the separate
  /// [RemoteDbDarkLibraryRow] wire type — different consumers, different
  /// shapes, no risk of one breaking the other.
  Future<RemotePage<RemoteDbDarkLibraryRow>> fetchDarkLibrary({
    int? gainMin,
    int? gainMax,
    double? temperatureC,
    double? exposureSecs,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('db/dark-library', {
      if (gainMin != null) 'gainMin': gainMin.toString(),
      if (gainMax != null) 'gainMax': gainMax.toString(),
      if (temperatureC != null) 'temperatureC': temperatureC.toString(),
      if (exposureSecs != null) 'exposureSecs': exposureSecs.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteDbDarkLibraryRow.fromJson);
  }

  /// GET /api/db/flat-history?filterName=&panelKey=&limit=&offset=
  ///
  /// Distinct from the calibration UI's `listFlats()` for the same reason
  /// the dark-library variant is — see the comment on [fetchDarkLibrary].
  Future<RemotePage<RemoteDbFlatHistoryRow>> fetchFlatHistory({
    String? filterName,
    int? panelKey,
    int limit = 200,
    int offset = 0,
  }) async {
    final response = await _get('db/flat-history', {
      if (filterName != null && filterName.isNotEmpty)
        'filterName': filterName,
      if (panelKey != null) 'panelKey': panelKey.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    return RemotePage.fromJson(response, RemoteDbFlatHistoryRow.fromJson);
  }

  // =========================================================================
  // P2-11 — plugin management. Methods live on NetworkBackend because the
  // FfiBackend manages plugins directly via PluginHost; the network path
  // is the only one that needs HTTP wiring.
  // =========================================================================

  /// GET /api/plugins
  Future<List<RemotePluginManifest>> listPlugins() async {
    final response = await _get('plugins');
    final raw = response['items'];
    if (raw is! List) {
      throw StateError('Malformed /plugins response: missing items list');
    }
    return raw
        .whereType<Map>()
        .map((m) => RemotePluginManifest.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// POST /api/plugins/upload — sends the plugin bytes with `filename` as
  /// a query parameter. Server computes SHA-256, persists the file under
  /// the app-data plugin directory, and returns the new manifest.
  Future<RemotePluginManifest> uploadPlugin(
    List<int> bytes, {
    required String filename,
  }) async {
    final response = await _postRaw(
      'plugins/upload',
      {'filename': filename},
      Uint8List.fromList(bytes),
      contentType: 'application/octet-stream',
    );
    final manifest = response['manifest'];
    if (manifest is! Map) {
      throw StateError(
          'Malformed /plugins/upload response: missing manifest field');
    }
    return RemotePluginManifest.fromJson(manifest.cast<String, dynamic>());
  }

  /// POST /api/plugins/{id}/enable
  Future<RemotePluginManifest> enablePlugin(String pluginId) async {
    final response = await _post('plugins/$pluginId/enable');
    final manifest = response['manifest'];
    if (manifest is! Map) {
      throw StateError(
          'Malformed /plugins/enable response: missing manifest field');
    }
    return RemotePluginManifest.fromJson(manifest.cast<String, dynamic>());
  }

  /// POST /api/plugins/{id}/disable
  Future<RemotePluginManifest> disablePlugin(String pluginId) async {
    final response = await _post('plugins/$pluginId/disable');
    final manifest = response['manifest'];
    if (manifest is! Map) {
      throw StateError(
          'Malformed /plugins/disable response: missing manifest field');
    }
    return RemotePluginManifest.fromJson(manifest.cast<String, dynamic>());
  }

  /// DELETE /api/plugins/{id}
  Future<void> uninstallPlugin(String pluginId) async {
    await _delete('plugins/$pluginId');
  }

  // [Wave 6E log tail] — client surface for the headless server's
  // remote-log endpoints. Lets the mobile log tab show ENTRIES emitted on
  // the host (not just NightshadeEvents) when the backend is networked.
  //
  // Wire shapes mirror `apps/desktop/lib/headless_api/handlers/log_handlers.dart`:
  //   GET  /api/logs/recent       — JSON { entries: [...], count, totalBuffered }
  //   GET  /api/logs/tail         — SSE  `id: <iso>\nevent: log\ndata: <json>\n\n`
  //   POST /api/logs/clear        — JSON { /* server-defined; we discard */ }
  //
  // We deliberately keep these methods OUT of [NightshadeBackend]'s
  // abstract surface because the local FFI backend has no equivalent
  // remote-log concept (it consumes the LoggingService directly). UI
  // callers do an `is NetworkBackend` check before invoking these.

  /// Fetch the last `limit` entries from the server's in-memory ring
  /// buffer, optionally filtered by severity and source substring.
  /// Throws on transport errors (let the UI display the failure rather
  /// than silently degrading; CLAUDE.md "errors are a feature").
  Future<List<LogEntry>> fetchRecentServerLogs({
    int limit = 200,
    String? severityMin,
    String? categoryFilter,
  }) async {
    final query = <String, dynamic>{
      'limit': limit.toString(),
    };
    if (severityMin != null && severityMin.isNotEmpty) {
      query['minSeverity'] = severityMin;
    }
    // The server doesn't yet expose a categoryFilter; we forward it as a
    // `source` substring filter when supplied so the existing handler
    // honours it. Documented here so a future server-side categoryFilter
    // can replace the source mapping without changing the call site.
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      query['source'] = categoryFilter;
    }
    final body = await _get('logs/recent', query);
    final entriesRaw = body['entries'];
    if (entriesRaw is! List) {
      // Malformed payload — surface loudly. A silent empty list would
      // make a broken server look like a quiet one.
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.system,
        message:
            'GET /api/logs/recent: missing or non-list `entries` field in '
            'response body',
      );
    }
    final out = <LogEntry>[];
    for (final raw in entriesRaw) {
      if (raw is! Map) continue;
      try {
        out.add(LogEntry.fromJson(
          raw.map((k, v) => MapEntry(k.toString(), v as Object?)),
        ));
      } on FormatException catch (e) {
        // One bad entry must not torpedo the whole list. We log and
        // skip; the UI gets the remaining entries.
        developer.log(
          '[NetworkBackend] fetchRecentServerLogs: dropped malformed entry: $e',
          name: 'NetworkBackend',
          level: 900,
        );
      }
    }
    return out;
  }

  /// POST /api/logs/clear — delete all non-current log files on the
  /// server. Returns when the server acknowledges; the response body is
  /// the per-file status map which the desktop log viewer surfaces but
  /// the mobile log tab does not currently need.
  Future<void> clearServerLogs() async {
    await _post('logs/clear');
  }

  /// Open a tail subscription against `GET /api/logs/tail` (SSE). The
  /// returned stream emits one [LogEntry] per server-side log event. The
  /// stream auto-reconnects with exponential backoff on transport errors
  /// (up to a 30 s ceiling) and closes only when the consumer cancels
  /// its subscription.
  ///
  /// Why a custom HttpClient instead of [http.Client]: package:http
  /// buffers the entire response body before returning, which is the
  /// opposite of what an SSE stream needs. dart:io's HttpClient hands
  /// back a streaming response we can chunk-decode in real time.
  Stream<LogEntry> tailServerLogs({String? severityMin}) {
    final controller = StreamController<LogEntry>();
    HttpClient? client;
    HttpClientResponse? response;
    StreamSubscription<String>? sub;
    var closed = false;
    var reconnectAttempts = 0;
    Timer? reconnectTimer;
    String? lastEventId;
    late Future<void> Function() connect;

    void scheduleReconnect() {
      if (closed) return;
      sub?.cancel();
      sub = null;
      try {
        response = null;
        client?.close(force: true);
      } catch (_) {
        // close() can throw on already-disposed clients; ignore.
      }
      client = null;
      reconnectAttempts += 1;
      // Cap exponential backoff at 30 s so a long server outage doesn't
      // push the next attempt out by minutes.
      final delaySeconds = (1 << (reconnectAttempts - 1)).clamp(1, 30);
      reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
        if (!closed) unawaited(connect());
      });
    }

    connect = () async {
      if (closed) return;
      reconnectTimer?.cancel();
      reconnectTimer = null;
      final query = <String, String>{};
      if (severityMin != null && severityMin.isNotEmpty) {
        query['severity'] = severityMin;
      }
      final uri = Uri(
        scheme: 'http',
        host: serverHost,
        port: serverPort,
        path: '/api/logs/tail',
        queryParameters: query.isEmpty ? null : query,
      );
      try {
        client = HttpClient();
        final req = await client!.getUrl(uri);
        req.headers.set('accept', 'text/event-stream');
        req.headers.set('cache-control', 'no-cache');
        // Mirror _addAuthHeaders manually because the dart:io HttpClient
        // doesn't share the package:http header pipeline.
        req.headers.set(
          RemoteApiCompatibility.apiVersionHeader,
          RemoteApiCompatibility.clientApiVersion.format(),
        );
        req.headers.set(_requestIdHeader, _nextRequestId('logs/tail'));
        if (authToken != null && authToken!.isNotEmpty) {
          req.headers.set('Authorization', 'Bearer $authToken');
        }
        if (lastEventId != null) {
          req.headers.set('last-event-id', lastEventId!);
        }
        response = await req.close();
        if (response!.statusCode != 200) {
          throw dart_error.NightshadeError(
            category: dart_error.BackendErrorCategory.connection,
            message:
                'GET /api/logs/tail returned HTTP ${response!.statusCode}',
          );
        }
        reconnectAttempts = 0;
        final buffer = StringBuffer();
        sub = response!
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (closed) return;
            if (line.isEmpty) {
              _processSseFrame(buffer.toString(), controller, (id) {
                lastEventId = id;
              });
              buffer.clear();
              return;
            }
            // Comments (`: keep-alive`) are ignored by the SSE spec.
            if (line.startsWith(':')) return;
            buffer.writeln(line);
          },
          onError: (Object e, _) {
            if (closed) return;
            developer.log(
              '[NetworkBackend] /api/logs/tail stream error: $e',
              name: 'NetworkBackend',
              level: 900,
            );
            scheduleReconnect();
          },
          onDone: () {
            if (closed) return;
            developer.log(
              '[NetworkBackend] /api/logs/tail stream closed by server',
              name: 'NetworkBackend',
              level: 700,
            );
            scheduleReconnect();
          },
          cancelOnError: true,
        );
      } catch (e) {
        if (closed) return;
        developer.log(
          '[NetworkBackend] /api/logs/tail connect failed: $e',
          name: 'NetworkBackend',
          level: 900,
        );
        scheduleReconnect();
      }
    };

    controller.onListen = () => unawaited(connect());
    controller.onCancel = () async {
      closed = true;
      reconnectTimer?.cancel();
      reconnectTimer = null;
      await sub?.cancel();
      sub = null;
      try {
        client?.close(force: true);
      } catch (_) {
        // ignore — already disposed
      }
      client = null;
    };

    return controller.stream;
  }

  /// Parse one accumulated SSE frame (text lines from the same `id`/
  /// `event`/`data` block) and surface a [LogEntry] if it contains a
  /// `data:` payload with a valid log entry. Updates `onId` with the
  /// frame's `id:` value so reconnects can pass `Last-Event-ID`.
  void _processSseFrame(
    String raw,
    StreamController<LogEntry> controller,
    void Function(String id) onId,
  ) {
    if (raw.isEmpty) return;
    String? event;
    String? id;
    final data = StringBuffer();
    for (final line in raw.split('\n')) {
      if (line.isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final field = line.substring(0, colon);
      var value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
          break;
        case 'id':
          id = value;
          break;
        case 'data':
          if (data.isNotEmpty) data.write('\n');
          data.write(value);
          break;
        case 'retry':
          // We honour the server's reconnect retry hint by NOT overriding
          // our exponential backoff with it — the server's 5 s suggestion
          // is fine as a floor but our backoff already starts at 1 s and
          // climbs from there, which is safer under sustained failure.
          break;
      }
    }
    if (id != null) onId(id);
    // The server emits `event: replay-done` as a marker (no log entry);
    // skip it without surfacing.
    if (event == 'replay-done') return;
    final dataStr = data.toString();
    if (dataStr.isEmpty) return;
    try {
      final decoded = jsonDecode(dataStr);
      if (decoded is! Map) return;
      final entry = LogEntry.fromJson(
        decoded.map((k, v) => MapEntry(k.toString(), v as Object?)),
      );
      if (!controller.isClosed) controller.add(entry);
    } on FormatException catch (e) {
      developer.log(
        '[NetworkBackend] /api/logs/tail: dropped malformed entry: $e',
        name: 'NetworkBackend',
        level: 900,
      );
    } catch (e) {
      developer.log(
        '[NetworkBackend] /api/logs/tail: decode error: $e',
        name: 'NetworkBackend',
        level: 900,
      );
    }
  }

  // [Wave 6E live-view stream] — client surface for the P2-10 push-based
  // live-view WebSocket at `/ws/live-view`. Server protocol is documented
  // alongside the handler in
  // `apps/desktop/lib/headless_api/handlers/live_view_stream_handlers.dart`.
  //
  // The returned stream emits one [LiveViewFrame] per server push. The
  // socket is opened lazily on the first subscriber and torn down (with
  // a polite `unsubscribe` message + sink.close) when the subscription
  // is cancelled. Re-subscribing returns a NEW stream backed by a new
  // socket; we do not share a single socket across subscriptions because
  // each viewer may want different `maxDim`/`maxFps`/`region`.
  Stream<LiveViewFrame> subscribeLiveView({
    required String deviceId,
    int maxDim = 1024,
    double maxFps = 2.0,
    int jpegQuality = 70,
    LiveViewRegion? region,
  }) {
    if (deviceId.isEmpty) {
      // Eagerly reject so the UI sees a synchronous failure rather than
      // an empty stream.
      return Stream<LiveViewFrame>.error(
        ArgumentError.value(deviceId, 'deviceId', 'must not be empty'),
      );
    }
    final controller = StreamController<LiveViewFrame>();
    WebSocketChannel? channel;
    StreamSubscription<dynamic>? wsSub;
    Map<String, Object?>? pendingMeta;
    var closed = false;

    Future<void> openSocket() async {
      final query = <String, String>{};
      if (authToken != null && authToken!.isNotEmpty) {
        query['token'] = authToken!;
      }
      final uri = Uri(
        scheme: 'ws',
        host: serverHost,
        port: webSocketPort,
        path: '/ws/live-view',
        queryParameters: query.isEmpty ? null : query,
      );
      try {
        channel = IOWebSocketChannel.connect(uri);
        // Send the initial subscribe immediately. The server replies
        // with `{type: ready, ...}` then starts pushing frames.
        channel!.sink.add(jsonEncode({
          'type': 'subscribe',
          'deviceId': deviceId,
          'maxDim': maxDim,
          'maxFps': maxFps,
          'jpegQuality': jpegQuality,
          if (region != null) 'region': region.toJson(),
        }));
        wsSub = channel!.stream.listen(
          (raw) {
            if (closed || controller.isClosed) return;
            if (raw is String) {
              try {
                final decoded = jsonDecode(raw);
                if (decoded is! Map) return;
                final type = decoded['type'];
                if (type == 'frame_meta') {
                  pendingMeta = decoded
                      .map((k, v) => MapEntry(k.toString(), v as Object?));
                } else if (type == 'error') {
                  // Surface non-fatal server-reported errors as stream
                  // errors but don't close the stream — the server will
                  // try again on the next tick.
                  controller.addError(
                    dart_error.NightshadeError(
                      category: dart_error.BackendErrorCategory.system,
                      message: (decoded['message'] as String?) ??
                          'live-view error: ${decoded['code']}',
                    ),
                  );
                } else if (type == 'stopped') {
                  // Server closed the stream voluntarily. Close from our
                  // side so the consumer's await for() exits cleanly.
                  if (!controller.isClosed) controller.close();
                }
                // ready/pong: nothing to surface to the consumer.
              } catch (e) {
                developer.log(
                  '[NetworkBackend] /ws/live-view JSON decode failed: $e',
                  name: 'NetworkBackend',
                  level: 900,
                );
              }
            } else if (raw is List<int>) {
              final meta = pendingMeta;
              pendingMeta = null;
              if (meta == null) {
                // Stray binary frame with no preceding meta — log + drop.
                developer.log(
                  '[NetworkBackend] /ws/live-view: received binary frame '
                  'with no preceding meta envelope; dropping',
                  name: 'NetworkBackend',
                  level: 900,
                );
                return;
              }
              try {
                final frame = LiveViewFrame.fromMetadata(
                  meta,
                  raw is Uint8List ? raw : Uint8List.fromList(raw),
                );
                controller.add(frame);
              } on FormatException catch (e) {
                controller.addError(e);
              }
            }
          },
          onError: (Object e, _) {
            if (closed || controller.isClosed) return;
            controller.addError(e);
            controller.close();
          },
          onDone: () {
            if (closed || controller.isClosed) return;
            controller.close();
          },
        );
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }

    controller.onListen = () => unawaited(openSocket());
    controller.onCancel = () async {
      closed = true;
      try {
        channel?.sink.add(jsonEncode({'type': 'unsubscribe'}));
      } catch (_) {
        // sink may already be closed; ignore
      }
      await wsSub?.cancel();
      wsSub = null;
      try {
        await channel?.sink.close();
      } catch (_) {
        // ignore — already closing
      }
      channel = null;
    };
    return controller.stream;
  }
}

/// Client-side mirror of the headless server's Job model. Tolerates
/// missing/extra fields so a server that gains additional metadata does
/// not break older clients.
class RemoteJob {
  final String jobId;
  final String operation;
  final String? deviceId;
  final String? commandId;
  final String state;
  final double? progress;
  final String? progressMessage;
  final Map<String, dynamic>? result;
  final Map<String, dynamic>? error;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RemoteJob({
    required this.jobId,
    required this.operation,
    required this.state,
    this.deviceId,
    this.commandId,
    this.progress,
    this.progressMessage,
    this.result,
    this.error,
    this.createdAt,
    this.updatedAt,
  });

  bool get isTerminal =>
      state == 'succeeded' || state == 'failed' || state == 'cancelled';

  factory RemoteJob.fromJson(Map<String, dynamic> json) {
    return RemoteJob(
      jobId: json['jobId'] as String? ?? '',
      operation: json['operation'] as String? ?? '',
      deviceId: json['deviceId'] as String?,
      commandId: json['commandId'] as String?,
      state: json['state'] as String? ?? 'unknown',
      progress: (json['progress'] as num?)?.toDouble(),
      progressMessage: json['progressMessage'] as String?,
      result: json['result'] is Map
          ? Map<String, dynamic>.from(json['result'] as Map)
          : null,
      error: json['error'] is Map
          ? Map<String, dynamic>.from(json['error'] as Map)
          : null,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  /// Construct from the `data` map of a job-category NightshadeEvent.
  /// The wire shape there is a subset of [fromJson] (no createdAt /
  /// updatedAt — the event itself carries the timestamp).
  factory RemoteJob.fromEventData(Map<String, dynamic> data) {
    return RemoteJob(
      jobId: data['jobId'] as String? ?? '',
      operation: data['operation'] as String? ?? '',
      deviceId: data['deviceId'] as String?,
      commandId: data['commandId'] as String?,
      state: data['state'] as String? ?? 'unknown',
      progress: (data['progress'] as num?)?.toDouble(),
      progressMessage: data['message'] as String?,
      result: data['result'] is Map
          ? Map<String, dynamic>.from(data['result'] as Map)
          : null,
      error: data['error'] is Map
          ? Map<String, dynamic>.from(data['error'] as Map)
          : null,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }
}

/// Client-side mirror of `GET /api/system/version`. Carries the
/// running build info plus the last-check / last-applied bookkeeping
/// timestamps. All optional fields tolerate missing keys so a future
/// server that drops one (e.g. when the controller cannot persist the
/// state markers) does not break older clients.
class RemoteVersionInfo {
  final String currentVersion;
  final int buildNumber;
  final String channel;
  final String platform;
  final String? dataDir;
  final String? updateServerUrl;
  final DateTime? lastUpdateCheck;
  final DateTime? lastUpdateApplied;

  const RemoteVersionInfo({
    required this.currentVersion,
    required this.buildNumber,
    required this.channel,
    required this.platform,
    this.dataDir,
    this.updateServerUrl,
    this.lastUpdateCheck,
    this.lastUpdateApplied,
  });

  factory RemoteVersionInfo.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? raw) {
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    return RemoteVersionInfo(
      currentVersion: json['currentVersion'] as String? ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      channel: json['channel'] as String? ?? 'stable',
      platform: json['platform'] as String? ?? '',
      dataDir: json['dataDir'] as String?,
      updateServerUrl: json['updateServerUrl'] as String?,
      lastUpdateCheck: parse(json['lastUpdateCheck']),
      lastUpdateApplied: parse(json['lastUpdateApplied']),
    );
  }
}

/// Client-side mirror of `GET /api/system/update/status`. State is
/// kept loose (string, not enum) so a server that adds a new
/// lifecycle phase does not crash older clients — the caller
/// branches on the wire name.
class RemoteUpdateStatus {
  final String state;
  final String? stagedVersion;
  final DateTime? stagedAt;
  final double? progressPct;
  final String? message;
  final String? lastError;

  const RemoteUpdateStatus({
    required this.state,
    this.stagedVersion,
    this.stagedAt,
    this.progressPct,
    this.message,
    this.lastError,
  });

  bool get hasStagedUpdate => stagedVersion != null;
  bool get isInFlight =>
      state == 'checking' ||
      state == 'downloading' ||
      state == 'verifying' ||
      state == 'installing';

  factory RemoteUpdateStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parse(Object? raw) {
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    return RemoteUpdateStatus(
      state: json['state'] as String? ?? 'idle',
      stagedVersion: json['stagedVersion'] as String?,
      stagedAt: parse(json['stagedAt']),
      progressPct: (json['progressPct'] as num?)?.toDouble(),
      message: json['message'] as String?,
      lastError: json['lastError'] as String?,
    );
  }
}

/// Client-side mirror of `GET /api/system/update/staged`. Returned by
/// [NetworkBackend.getStagedUpdate] when a staged update exists.
class RemoteStagedUpdate {
  final String stagedVersion;
  final int stagedBuildNumber;
  final DateTime? stagedAt;
  final String? manifestHash;
  final int fileCount;
  final int totalBytes;
  final String? sourceUrl;
  final Map<String, String> expectedHashes;

  const RemoteStagedUpdate({
    required this.stagedVersion,
    required this.stagedBuildNumber,
    required this.fileCount,
    required this.totalBytes,
    required this.expectedHashes,
    this.stagedAt,
    this.manifestHash,
    this.sourceUrl,
  });

  factory RemoteStagedUpdate.fromJson(Map<String, dynamic> json) {
    final hashesRaw = json['expectedHashes'];
    final hashes = <String, String>{};
    if (hashesRaw is Map) {
      hashesRaw.forEach((k, v) {
        if (k is String && v is String) {
          hashes[k] = v;
        }
      });
    }
    DateTime? parse(Object? raw) {
      if (raw is! String) return null;
      return DateTime.tryParse(raw);
    }

    return RemoteStagedUpdate(
      stagedVersion: json['stagedVersion'] as String? ?? '',
      stagedBuildNumber: (json['stagedBuildNumber'] as num?)?.toInt() ?? 0,
      stagedAt: parse(json['stagedAt']),
      manifestHash: json['manifestHash'] as String?,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? hashes.length,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      sourceUrl: json['sourceUrl'] as String?,
      expectedHashes: hashes,
    );
  }
}

/// Client-side mirror of the headless server's session-status response.
class RemoteSessionStatus {
  final Map<String, dynamic>? owner;
  final bool isYouTheOwner;
  final String mode; // 'operator' | 'viewer' | 'unowned'
  final int heartbeatTimeoutSeconds;

  const RemoteSessionStatus({
    required this.owner,
    required this.isYouTheOwner,
    required this.mode,
    required this.heartbeatTimeoutSeconds,
  });

  factory RemoteSessionStatus.fromJson(Map<String, dynamic> json) {
    return RemoteSessionStatus(
      owner: json['owner'] is Map
          ? Map<String, dynamic>.from(json['owner'] as Map)
          : null,
      isYouTheOwner: json['isYouTheOwner'] as bool? ?? false,
      mode: json['mode'] as String? ?? 'unowned',
      heartbeatTimeoutSeconds:
          (json['heartbeatTimeoutSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

// =============================================================================
// P1-12 — Client-side mirrors of the headless server's /api/catalog/... shapes.
// =============================================================================

/// Per-catalog install state surfaced by `GET /api/catalog/status`.
class RemoteCatalogStatus {
  final String name;
  final String? version;
  final int sizeBytes;
  final int fileCount;
  final DateTime? installedAt;
  final DateTime? lastVerified;
  final String? expectedHash;
  final String? actualHash;
  final int? objectCount;

  /// One of `installed`, `partial`, `corrupted`, `missing`.
  final String status;
  final List<String> errors;

  const RemoteCatalogStatus({
    required this.name,
    required this.status,
    this.version,
    this.sizeBytes = 0,
    this.fileCount = 0,
    this.installedAt,
    this.lastVerified,
    this.expectedHash,
    this.actualHash,
    this.objectCount,
    this.errors = const [],
  });

  bool get isInstalled => status == 'installed';

  factory RemoteCatalogStatus.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return RemoteCatalogStatus(
      name: json['name'] as String? ?? '',
      version: json['version'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      installedAt: _parseDateField(json['installedAt']),
      lastVerified: _parseDateField(json['lastVerified']),
      expectedHash: json['expectedHash'] as String?,
      actualHash: json['actualHash'] as String?,
      objectCount: (json['objectCount'] as num?)?.toInt(),
      status: json['status'] as String? ?? 'missing',
      errors: rawErrors is List
          ? rawErrors.map((e) => e.toString()).toList(growable: false)
          : const [],
    );
  }
}

/// Wire response for `GET /api/catalog/status`.
class RemoteCatalogStatusResponse {
  final List<RemoteCatalogStatus> catalogs;
  final int totalBytes;
  final String dataDir;
  final int? availableSpaceBytes;

  const RemoteCatalogStatusResponse({
    required this.catalogs,
    required this.totalBytes,
    required this.dataDir,
    this.availableSpaceBytes,
  });

  factory RemoteCatalogStatusResponse.fromJson(Map<String, dynamic> json) {
    final rawCatalogs = json['catalogs'];
    final catalogs = <RemoteCatalogStatus>[];
    if (rawCatalogs is List) {
      for (final entry in rawCatalogs) {
        if (entry is Map) {
          catalogs.add(
              RemoteCatalogStatus.fromJson(entry.cast<String, dynamic>()));
        }
      }
    }
    return RemoteCatalogStatusResponse(
      catalogs: catalogs,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      dataDir: json['dataDir'] as String? ?? '',
      availableSpaceBytes: (json['availableSpaceBytes'] as num?)?.toInt(),
    );
  }
}

/// One entry in the `GET /api/catalog/available` response.
class RemoteAvailableCatalog {
  final String name;
  final String displayName;
  final String version;
  final String description;
  final String? downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final bool requiredForPlateSolve;

  const RemoteAvailableCatalog({
    required this.name,
    required this.displayName,
    required this.version,
    required this.description,
    this.downloadUrl,
    required this.sizeBytes,
    this.sha256,
    this.requiredForPlateSolve = false,
  });

  factory RemoteAvailableCatalog.fromJson(Map<String, dynamic> json) {
    return RemoteAvailableCatalog(
      name: json['name'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String? ?? '',
      downloadUrl: json['downloadUrl'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String?,
      requiredForPlateSolve:
          json['requiredForPlateSolve'] as bool? ?? false,
    );
  }
}

/// Result of `POST /api/catalog/upload`.
class RemoteCatalogInstallResult {
  final String name;
  final String sha256;
  final int sizeBytes;
  final int objectCount;
  final String version;
  final DateTime? installedAt;

  const RemoteCatalogInstallResult({
    required this.name,
    required this.sha256,
    required this.sizeBytes,
    required this.objectCount,
    required this.version,
    this.installedAt,
  });

  factory RemoteCatalogInstallResult.fromJson(Map<String, dynamic> json) {
    return RemoteCatalogInstallResult(
      name: json['name'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      objectCount: (json['objectCount'] as num?)?.toInt() ?? 0,
      version: json['version'] as String? ?? '',
      installedAt: _parseDateField(json['installedAt']),
    );
  }
}

/// Per-catalog result of `POST /api/catalog/verify`.
class RemoteCatalogVerifyResult {
  final bool ok;
  final String? expectedHash;
  final String? actualHash;
  final List<String> errors;

  const RemoteCatalogVerifyResult({
    required this.ok,
    this.expectedHash,
    this.actualHash,
    this.errors = const [],
  });

  factory RemoteCatalogVerifyResult.fromJson(Map<String, dynamic> json) {
    final rawErrors = json['errors'];
    return RemoteCatalogVerifyResult(
      ok: json['ok'] as bool? ?? false,
      expectedHash: json['expectedHash'] as String?,
      actualHash: json['actualHash'] as String?,
      errors: rawErrors is List
          ? rawErrors.map((e) => e.toString()).toList(growable: false)
          : const [],
    );
  }
}

DateTime? _parseDateField(Object? raw) {
  if (raw is! String) return null;
  return DateTime.tryParse(raw);
}

// =========================================================================
// P2-8 — wire types for the read-only DB endpoints. All endpoints use the
// same `{items, total}` envelope, captured by [RemotePage<T>] so callers
// see one consistent paginated shape regardless of underlying table.
// =========================================================================

/// Generic envelope for paginated `GET` endpoints. `items` is the page
/// content; `total` is the unpaginated row count matching the filter.
class RemotePage<T> {
  final List<T> items;
  final int total;

  const RemotePage({required this.items, required this.total});

  factory RemotePage.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw StateError('Malformed paginated response: missing items list');
    }
    final items = rawItems
        .whereType<Map>()
        .map((m) => itemFromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
    return RemotePage(
      items: items,
      total: (json['total'] as num?)?.toInt() ?? items.length,
    );
  }
}

/// Wire row for `/api/sequence-runs`.
class RemoteSequenceRun {
  final int id;
  final int? sequenceId;
  final String? sequenceName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final String? statsJson;

  const RemoteSequenceRun({
    required this.id,
    required this.startedAt,
    required this.status,
    this.sequenceId,
    this.sequenceName,
    this.endedAt,
    this.statsJson,
  });

  factory RemoteSequenceRun.fromJson(Map<String, dynamic> json) {
    return RemoteSequenceRun(
      id: (json['id'] as num).toInt(),
      sequenceId: (json['sequenceId'] as num?)?.toInt(),
      sequenceName: json['sequenceName'] as String?,
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: _parseDateField(json['endedAt']),
      status: json['status'] as String? ?? 'unknown',
      statsJson: json['statsJson'] as String?,
    );
  }
}

/// Wire row for `/api/notes-journal`.
class RemoteNotesJournalEntry {
  final int id;
  final DateTime timestamp;
  final String objectName;
  final String? objectType;
  final String? catalogId;
  final double ra;
  final double dec;
  final double? altitude;
  final double? azimuth;
  final String? notes;
  final int? rating;
  final int? equipmentProfileId;
  final String? seeingConditions;
  final String? transparency;
  final String? locationName;
  final double? latitude;
  final double? longitude;

  const RemoteNotesJournalEntry({
    required this.id,
    required this.timestamp,
    required this.objectName,
    required this.ra,
    required this.dec,
    this.objectType,
    this.catalogId,
    this.altitude,
    this.azimuth,
    this.notes,
    this.rating,
    this.equipmentProfileId,
    this.seeingConditions,
    this.transparency,
    this.locationName,
    this.latitude,
    this.longitude,
  });

  factory RemoteNotesJournalEntry.fromJson(Map<String, dynamic> json) {
    return RemoteNotesJournalEntry(
      id: (json['id'] as num).toInt(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      objectName: json['objectName'] as String? ?? '',
      objectType: json['objectType'] as String?,
      catalogId: json['catalogId'] as String?,
      ra: (json['ra'] as num?)?.toDouble() ?? 0.0,
      dec: (json['dec'] as num?)?.toDouble() ?? 0.0,
      altitude: (json['altitude'] as num?)?.toDouble(),
      azimuth: (json['azimuth'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      rating: (json['rating'] as num?)?.toInt(),
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      seeingConditions: json['seeingConditions'] as String?,
      transparency: json['transparency'] as String?,
      locationName: json['locationName'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }
}

/// Wire row for `/api/guide-rms-history`.
class RemoteGuideRmsHistoryEntry {
  final int id;
  final int? sessionId;
  final String? mountId;
  final int? targetId;
  final double totalRmsArcsec;
  final int sampleCount;
  final double? exposureSeconds;
  final DateTime recordedAt;

  const RemoteGuideRmsHistoryEntry({
    required this.id,
    required this.totalRmsArcsec,
    required this.sampleCount,
    required this.recordedAt,
    this.sessionId,
    this.mountId,
    this.targetId,
    this.exposureSeconds,
  });

  factory RemoteGuideRmsHistoryEntry.fromJson(Map<String, dynamic> json) {
    return RemoteGuideRmsHistoryEntry(
      id: (json['id'] as num).toInt(),
      sessionId: (json['sessionId'] as num?)?.toInt(),
      mountId: json['mountId'] as String?,
      targetId: (json['targetId'] as num?)?.toInt(),
      totalRmsArcsec: (json['totalRmsArcsec'] as num?)?.toDouble() ?? 0.0,
      sampleCount: (json['sampleCount'] as num?)?.toInt() ?? 0,
      exposureSeconds: (json['exposureSeconds'] as num?)?.toDouble(),
      recordedAt: DateTime.parse(json['recordedAt'] as String),
    );
  }
}

/// Wire row for `/api/polar-alignment-history`.
class RemotePolarAlignmentHistoryEntry {
  final int id;
  final int? equipmentProfileId;
  final double? initialAzimuthError;
  final double? initialAltitudeError;
  final double? initialTotalError;
  final double? finalAzimuthError;
  final double? finalAltitudeError;
  final double? finalTotalError;
  final DateTime startedAt;
  final DateTime completedAt;
  final bool autoCompleted;
  final bool isNorth;
  final String? configJson;

  const RemotePolarAlignmentHistoryEntry({
    required this.id,
    required this.startedAt,
    required this.completedAt,
    required this.autoCompleted,
    required this.isNorth,
    this.equipmentProfileId,
    this.initialAzimuthError,
    this.initialAltitudeError,
    this.initialTotalError,
    this.finalAzimuthError,
    this.finalAltitudeError,
    this.finalTotalError,
    this.configJson,
  });

  factory RemotePolarAlignmentHistoryEntry.fromJson(
      Map<String, dynamic> json) {
    return RemotePolarAlignmentHistoryEntry(
      id: (json['id'] as num).toInt(),
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      initialAzimuthError:
          (json['initialAzimuthError'] as num?)?.toDouble(),
      initialAltitudeError:
          (json['initialAltitudeError'] as num?)?.toDouble(),
      initialTotalError: (json['initialTotalError'] as num?)?.toDouble(),
      finalAzimuthError: (json['finalAzimuthError'] as num?)?.toDouble(),
      finalAltitudeError: (json['finalAltitudeError'] as num?)?.toDouble(),
      finalTotalError: (json['finalTotalError'] as num?)?.toDouble(),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: DateTime.parse(json['completedAt'] as String),
      autoCompleted: json['autoCompleted'] as bool? ?? false,
      isNorth: json['isNorth'] as bool? ?? true,
      configJson: json['configJson'] as String?,
    );
  }
}

/// Wire row for `/api/db/dark-library` (P2-8). Distinct from
/// [RemoteDarkLibraryEntry] in `models/calibration/`: that one is the
/// calibration UI's projection (P1-10) which elides several columns the
/// raw read surface keeps (master frame path, master count).
class RemoteDbDarkLibraryRow {
  final int id;
  final String filePath;
  final String frameType;
  final double exposureTime;
  final int gain;
  final int offset;
  final int binX;
  final int binY;
  final double? temperature;
  final int width;
  final int height;
  final String? masterDarkPath;
  final int masterFrameCount;
  final DateTime createdAt;

  const RemoteDbDarkLibraryRow({
    required this.id,
    required this.filePath,
    required this.frameType,
    required this.exposureTime,
    required this.gain,
    required this.offset,
    required this.binX,
    required this.binY,
    required this.width,
    required this.height,
    required this.masterFrameCount,
    required this.createdAt,
    this.temperature,
    this.masterDarkPath,
  });

  factory RemoteDbDarkLibraryRow.fromJson(Map<String, dynamic> json) {
    return RemoteDbDarkLibraryRow(
      id: (json['id'] as num).toInt(),
      filePath: json['filePath'] as String? ?? '',
      frameType: json['frameType'] as String? ?? 'dark',
      exposureTime: (json['exposureTime'] as num?)?.toDouble() ?? 0.0,
      gain: (json['gain'] as num?)?.toInt() ?? 0,
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      binX: (json['binX'] as num?)?.toInt() ?? 1,
      binY: (json['binY'] as num?)?.toInt() ?? 1,
      temperature: (json['temperature'] as num?)?.toDouble(),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      masterDarkPath: json['masterDarkPath'] as String?,
      masterFrameCount: (json['masterFrameCount'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Wire row for `/api/db/flat-history` (P2-8). See [RemoteDbDarkLibraryRow]
/// for the rationale for keeping this distinct from
/// [RemoteFlatHistoryEntry].
class RemoteDbFlatHistoryRow {
  final int id;
  final String filterName;
  final double exposureTime;
  final double histogramTarget;
  final double actualAdu;
  final int? equipmentProfileId;
  final int? panelBrightness;
  final double? skyAduRate;
  final String? twilightPhase;
  final int gain;
  final int binning;
  final DateTime timestamp;

  const RemoteDbFlatHistoryRow({
    required this.id,
    required this.filterName,
    required this.exposureTime,
    required this.histogramTarget,
    required this.actualAdu,
    required this.gain,
    required this.binning,
    required this.timestamp,
    this.equipmentProfileId,
    this.panelBrightness,
    this.skyAduRate,
    this.twilightPhase,
  });

  factory RemoteDbFlatHistoryRow.fromJson(Map<String, dynamic> json) {
    return RemoteDbFlatHistoryRow(
      id: (json['id'] as num).toInt(),
      filterName: json['filterName'] as String? ?? '',
      exposureTime: (json['exposureTime'] as num?)?.toDouble() ?? 0.0,
      histogramTarget: (json['histogramTarget'] as num?)?.toDouble() ?? 0.0,
      actualAdu: (json['actualAdu'] as num?)?.toDouble() ?? 0.0,
      equipmentProfileId: (json['equipmentProfileId'] as num?)?.toInt(),
      panelBrightness: (json['panelBrightness'] as num?)?.toInt(),
      skyAduRate: (json['skyAduRate'] as num?)?.toDouble(),
      twilightPhase: json['twilightPhase'] as String?,
      gain: (json['gain'] as num?)?.toInt() ?? 0,
      binning: (json['binning'] as num?)?.toInt() ?? 1,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// =========================================================================
// P2-11 — wire types for the plugin management endpoints.
// =========================================================================

/// Wire row for `/api/plugins`, returned individually by upload/enable/
/// disable. Mirrors the on-disk plugin manifest that the
/// PluginManagementService maintains under app-data.
class RemotePluginManifest {
  final String id;
  final String name;
  final String version;
  final String? description;
  final String? author;
  final bool enabled;
  final bool signed;
  final bool signatureValid;
  final String? sha256;
  final int? sizeBytes;
  final DateTime? installedAt;
  final String? installedFilename;
  final String? loadError;

  const RemotePluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.enabled,
    required this.signed,
    required this.signatureValid,
    this.description,
    this.author,
    this.sha256,
    this.sizeBytes,
    this.installedAt,
    this.installedFilename,
    this.loadError,
  });

  factory RemotePluginManifest.fromJson(Map<String, dynamic> json) {
    return RemotePluginManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String?,
      author: json['author'] as String?,
      enabled: json['enabled'] as bool? ?? false,
      signed: json['signed'] as bool? ?? false,
      signatureValid: json['signatureValid'] as bool? ?? false,
      sha256: json['sha256'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      installedAt: _parseDateField(json['installedAt']),
      installedFilename: json['installedFilename'] as String?,
      loadError: json['loadError'] as String?,
    );
  }
}

/// Helper function to consolidate HTTP response bytes
Future<List<int>> consolidateHttpClientResponseBytes(
    HttpClientResponse response) {
  final completer = Completer<List<int>>();
  final chunks = <List<int>>[];

  response.listen(
    (chunk) => chunks.add(chunk),
    onDone: () => completer.complete(chunks.expand((x) => x).toList()),
    onError: completer.completeError,
    cancelOnError: true,
  );

  return completer.future;
}
