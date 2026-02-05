/// PHD2 Client - Real connection to PHD2 autoguiding software
///
/// PHD2 uses a JSON-RPC 2.0 protocol over TCP socket on port 4400.
/// Reference: https://github.com/OpenPHDGuiding/phd2/wiki/EventMonitoring
///
/// Features:
/// - Automatic reconnection with exponential backoff
/// - Heartbeat monitoring to detect stale connections
/// - Connection state tracking and reporting

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'utils/retry.dart';
import 'utils/circuit_breaker.dart';

import 'rolling_rms_calculator.dart';

/// PHD2 connection state
enum Phd2ConnectionState {
  /// Not connected
  disconnected,

  /// Attempting to connect
  connecting,

  /// Connected and healthy
  connected,

  /// Connected but not receiving data (stale connection)
  stale,

  /// Connection lost, attempting to reconnect
  reconnecting,

  /// Reconnection failed after all attempts
  failed,
}

/// PHD2 guiding state
enum Phd2State {
  stopped,
  selected,
  calibrating,
  guiding,
  looping,
  settling,
  paused,
  lostLock,
}

/// PHD2 settle progress
class Phd2SettleProgress {
  final bool done;
  final double distance;
  final double? settlePx;
  final double? time;
  final String? status;
  final String? error;

  Phd2SettleProgress({
    required this.done,
    required this.distance,
    this.settlePx,
    this.time,
    this.status,
    this.error,
  });

  factory Phd2SettleProgress.fromJson(Map<String, dynamic> json) {
    return Phd2SettleProgress(
      done: (json['Done'] as bool?) ?? false,
      distance: ((json['Distance'] as num?) ?? 0).toDouble(),
      settlePx: (json['SettlePx'] as num?)?.toDouble(),
      time: (json['Time'] as num?)?.toDouble(),
      status: json['Status'] as String?,
      error: json['Error'] as String?,
    );
  }
}

/// PHD2 guide stats
class Phd2GuideStats {
  final double rmsRa;
  final double rmsDec;
  final double rmsTotal;
  final double? peakRa;
  final double? peakDec;
  final double snr;
  final double starMass;
  final int frameCount;

  Phd2GuideStats({
    required this.rmsRa,
    required this.rmsDec,
    required this.rmsTotal,
    this.peakRa,
    this.peakDec,
    required this.snr,
    required this.starMass,
    required this.frameCount,
  });
}

/// PHD2 client for autoguiding control with resilient connection handling
class Phd2Client {
  static const int defaultPort = 4400;
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration heartbeatTimeout = Duration(seconds: 10);
  static const Duration staleConnectionThreshold = Duration(seconds: 60);

  final String host;
  final int port;

  Socket? _socket;
  StreamSubscription<List<int>>? _subscription;
  int _requestId = 0;

  final _pendingRequests = <int, Completer<dynamic>>{};
  final _eventController = StreamController<Phd2Event>.broadcast();
  final _connectionStateController =
      StreamController<Phd2ConnectionState>.broadcast();

  Phd2State _state = Phd2State.stopped;
  Phd2ConnectionState _connectionState = Phd2ConnectionState.disconnected;

  // Rolling RMS calculators for accurate statistics
  final _rmsRaCalculator = RollingRmsCalculator(windowSize: 100);
  final _rmsDecCalculator = RollingRmsCalculator(windowSize: 100);

  double _rmsRa = 0;
  double _rmsDec = 0;
  double _rmsTotal = 0;
  double _snr = 0;
  double _starMass = 0;
  String _statusMessage = '';
  bool _connected = false;

  // Connection resilience
  Timer? _heartbeatTimer;
  DateTime? _lastDataReceived;
  String? _lastHost;
  int? _lastPort;
  bool _shouldReconnect = true;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  final CircuitBreaker _circuitBreaker = CircuitBreaker(
    name: 'phd2',
    config: const CircuitBreakerConfig(
      failureThreshold: 5,
      successThreshold: 2,
      resetTimeout: Duration(seconds: 30),
    ),
  );

  Phd2Client({
    this.host = 'localhost',
    this.port = defaultPort,
  });

  /// Check if connected to PHD2
  bool get isConnected => _connected && _socket != null;

  /// Get current connection state
  Phd2ConnectionState get connectionState => _connectionState;

  /// Get current guiding state
  Phd2State get state => _state;

  /// Get RMS RA error
  double get rmsRa => _rmsRa;

  /// Get RMS Dec error
  double get rmsDec => _rmsDec;

  /// Get total RMS error
  double get rmsTotal => _rmsTotal;

  /// Get signal-to-noise ratio
  double get snr => _snr;

  /// Get star mass
  double get starMass => _starMass;

  /// Get status message
  String get statusMessage => _statusMessage;

  /// Get number of reconnection attempts
  int get reconnectAttempts => _reconnectAttempts;

  /// Check if connection is stale (no data received recently)
  bool get isStale {
    if (_lastDataReceived == null) return false;
    return DateTime.now().difference(_lastDataReceived!) >
        staleConnectionThreshold;
  }

  /// Stream of PHD2 events
  Stream<Phd2Event> get events => _eventController.stream;

  /// Stream of connection state changes
  Stream<Phd2ConnectionState> get connectionStateStream =>
      _connectionStateController.stream;

  /// Connect to PHD2
  Future<void> connect({String? host, int? port}) async {
    if (_socket != null) return;

    final targetHost = host ?? this.host;
    final targetPort = port ?? this.port;

    // Store connection parameters for reconnection
    _lastHost = targetHost;
    _lastPort = targetPort;

    _updateConnectionState(Phd2ConnectionState.connecting);

    try {
      await _circuitBreaker.execute(() async {
        _socket = await Socket.connect(targetHost, targetPort,
            timeout: const Duration(seconds: 5));
      });

      _connected = true;
      _reconnectAttempts = 0;
      _lastDataReceived = DateTime.now();
      _updateConnectionState(Phd2ConnectionState.connected);

      _subscription = _socket!.listen(
        (data) => _handleData(data),
        onError: (Object error) {
          debugPrint('[PHD2] socket error: $error');
          _handleConnectionLost();
        },
        onDone: () {
          debugPrint('[PHD2] connection closed');
          _handleConnectionLost();
        },
      );

      // Start heartbeat monitoring
      _startHeartbeat();

      // Send initial handshake/version check if needed
      // For now just get app state
      await _getAppState();

      _eventController.add(Phd2Event(
        event: 'Connected',
        data: {'host': targetHost, 'port': targetPort},
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      _connected = false;
      _updateConnectionState(Phd2ConnectionState.disconnected);
      rethrow;
    }
  }

  /// Enable or disable automatic reconnection
  void setAutoReconnect(bool enable) {
    _shouldReconnect = enable;
  }

  /// Disconnect from PHD2
  Future<void> disconnect() async {
    _shouldReconnect = false; // Prevent auto-reconnect on manual disconnect
    _handleDisconnect();
  }

  /// Update connection state and notify listeners
  void _updateConnectionState(Phd2ConnectionState newState) {
    if (_connectionState == newState) return;
    _connectionState = newState;
    _connectionStateController.add(newState);
  }

  /// Start heartbeat monitoring
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer =
        Timer.periodic(heartbeatInterval, (_) => _sendHeartbeat());
  }

  /// Stop heartbeat monitoring
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Send heartbeat ping to detect connection health
  Future<void> _sendHeartbeat() async {
    if (!_connected || _socket == null) {
      return;
    }

    // Check if connection is stale
    if (isStale) {
      debugPrint('[PHD2] connection is stale, triggering reconnect');
      _updateConnectionState(Phd2ConnectionState.stale);
      _handleConnectionLost();
      return;
    }

    try {
      // Send lightweight ping using get_app_state
      await _sendRequest('get_app_state').timeout(heartbeatTimeout,
          onTimeout: () {
        throw TimeoutException('Heartbeat timeout');
      });
    } on Exception catch (e) {
      debugPrint('[PHD2] heartbeat failed: $e');
      _handleConnectionLost();
    }
  }

  /// Handle connection lost - trigger reconnection if enabled
  void _handleConnectionLost() {
    if (!_connected) return; // Already handling disconnect

    _handleDisconnect();

    if (_shouldReconnect && !_isReconnecting) {
      debugPrint('[PHD2] connection lost, starting reconnection...');
      _updateConnectionState(Phd2ConnectionState.reconnecting);
      _reconnectWithBackoff();
    }
  }

  /// Reconnect with exponential backoff
  Future<void> _reconnectWithBackoff() async {
    if (_isReconnecting || _lastHost == null || _lastPort == null) {
      return;
    }

    _isReconnecting = true;

    try {
      await withRetry(
        () => connect(host: _lastHost, port: _lastPort),
        const RetryConfig(
          maxAttempts: 10,
          initialDelay: Duration(seconds: 2),
          maxDelay: Duration(seconds: 60),
          multiplier: 1.5,
        ),
        shouldRetry: isNetworkException,
        onRetry: (attempt, error, delay) {
          _reconnectAttempts = attempt;
          debugPrint('[PHD2] reconnect attempt $attempt failed: $error. '
              'Retrying in ${delay.inSeconds}s...');
        },
      );

      debugPrint(
          '[PHD2] reconnection successful after $_reconnectAttempts attempts');
      _eventController.add(Phd2Event(
        event: 'Reconnected',
        data: {'attempts': _reconnectAttempts},
        timestamp: DateTime.now(),
      ));
    } on RetryExhaustedException catch (e) {
      debugPrint('[PHD2] reconnection failed after all attempts: $e');
      _updateConnectionState(Phd2ConnectionState.failed);
      _eventController.add(Phd2Event(
        event: 'ReconnectionFailed',
        data: {'attempts': e.attempts, 'error': e.lastException.toString()},
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      debugPrint('[PHD2] reconnection error: $e');
      _updateConnectionState(Phd2ConnectionState.failed);
    } finally {
      _isReconnecting = false;
    }
  }

  void _handleDisconnect() {
    _connected = false;
    _stopHeartbeat();
    _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _state = Phd2State.stopped;
    _statusMessage = 'Disconnected';
    _updateConnectionState(Phd2ConnectionState.disconnected);

    // Fail any pending requests
    for (final completer in _pendingRequests.values) {
      completer.completeError(Exception('Disconnected from PHD2'));
    }
    _pendingRequests.clear();
  }

  void _handleData(List<int> data) {
    _lastDataReceived = DateTime.now();
    final buffer = StringBuffer();
    buffer.write(String.fromCharCodes(data));
    _processBuffer(buffer);
  }

  /// Process incoming data buffer for complete JSON messages
  void _processBuffer(StringBuffer buffer) {
    final content = buffer.toString();
    final lines = content.split('\r\n');

    buffer.clear();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      // If this is the last line and doesn't end with newline, keep it in buffer
      if (i == lines.length - 1 && !content.endsWith('\r\n')) {
        buffer.write(line);
        continue;
      }

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        _handleMessage(json);
      } catch (e) {
        debugPrint('[PHD2] Failed to parse message: $line');
      }
    }
  }

  /// Handle a PHD2 JSON message
  void _handleMessage(Map<String, dynamic> json) {
    // Check if this is a response to a request
    if (json.containsKey('id')) {
      final id = json['id'] as int;
      final completer = _pendingRequests.remove(id);
      if (completer != null) {
        if (json.containsKey('error')) {
          completer.completeError(Exception(json['error']['message']));
        } else {
          completer.complete(json['result']);
        }
      }
      return;
    }

    // This is an event
    final event = json['Event'] as String?;
    if (event == null) return;

    _handleEvent(event, json);
  }

  /// Handle a PHD2 event
  void _handleEvent(String event, Map<String, dynamic> json) {
    switch (event) {
      case 'Version':
        debugPrint('[PHD2] Version: ${json['PHDVersion']}');
        break;

      case 'AppState':
        _updateState(json['State'] as String?);
        break;

      case 'GuideStep':
        _handleGuideStep(json);
        break;

      case 'Settling':
        _statusMessage = 'Settling...';
        _state = Phd2State.settling;
        break;

      case 'SettleDone':
        final error = json['Error'] as String?;
        if (error != null) {
          _statusMessage = 'Settle failed: $error';
        } else {
          _statusMessage = 'Settled';
          _state = Phd2State.guiding;
        }
        break;

      case 'StarSelected':
        _statusMessage = 'Star selected';
        _state = Phd2State.selected;
        break;

      case 'StarLost':
        _statusMessage = 'Star lost!';
        _state = Phd2State.lostLock;
        break;

      case 'GuidingStarted':
        _statusMessage = 'Guiding started';
        _state = Phd2State.guiding;
        break;

      case 'GuidingStopped':
        _statusMessage = 'Guiding stopped';
        _state = Phd2State.stopped;
        // Clear rolling RMS calculators
        _rmsRaCalculator.clear();
        _rmsDecCalculator.clear();
        _rmsRa = 0;
        _rmsDec = 0;
        _rmsTotal = 0;
        break;

      case 'Paused':
        _statusMessage = 'Paused';
        _state = Phd2State.paused;
        break;

      case 'Resumed':
        _statusMessage = 'Guiding';
        _state = Phd2State.guiding;
        break;

      case 'CalibrationComplete':
        _statusMessage = 'Calibration complete';
        break;

      case 'LoopingExposures':
        _statusMessage = 'Looping exposures';
        _state = Phd2State.looping;
        break;
    }

    // Emit event
    _eventController.add(Phd2Event(
      event: event,
      data: json,
      timestamp: DateTime.now(),
    ));
  }

  void _handleGuideStep(Map<String, dynamic> json) {
    // Extract guide stats
    _snr = ((json['SNR'] as num?) ?? 0).toDouble();
    _starMass = ((json['StarMass'] as num?) ?? 0).toDouble();

    // Get raw distance values from PHD2
    final raDistance = ((json['RADistanceRaw'] as num?) ?? 0).toDouble();
    final decDistance = ((json['DECDistanceRaw'] as num?) ?? 0).toDouble();

    // Add values to rolling RMS calculators
    _rmsRaCalculator.add(raDistance);
    _rmsDecCalculator.add(decDistance);

    // Calculate proper RMS using rolling window
    // Formula: sqrt(mean(x²)) for each axis
    _rmsRa = _rmsRaCalculator.rms;
    _rmsDec = _rmsDecCalculator.rms;

    // Total RMS is pythagorean combination of RA and Dec RMS
    _rmsTotal = math.sqrt(_rmsRa * _rmsRa + _rmsDec * _rmsDec);

    // PHD2 also sends cumulative RMS in AvgDist - prefer our calculation
    // but fall back to PHD2's value if our window is small
    if (_rmsRaCalculator.count < 10) {
      final avgDist = json['AvgDist'] as num?;
      if (avgDist != null) {
        _rmsTotal = avgDist.toDouble();
      }
    }

    _statusMessage = 'Guiding: ${_rmsTotal.toStringAsFixed(2)}" RMS';
  }

  void _updateState(String? stateStr) {
    switch (stateStr) {
      case 'Stopped':
        _state = Phd2State.stopped;
        _statusMessage = 'Stopped';
        break;
      case 'Selected':
        _state = Phd2State.selected;
        _statusMessage = 'Star selected';
        break;
      case 'Calibrating':
        _state = Phd2State.calibrating;
        _statusMessage = 'Calibrating';
        break;
      case 'Guiding':
        _state = Phd2State.guiding;
        _statusMessage = 'Guiding';
        break;
      case 'LostLock':
        _state = Phd2State.lostLock;
        _statusMessage = 'Star lost!';
        break;
      case 'Paused':
        _state = Phd2State.paused;
        _statusMessage = 'Paused';
        break;
      case 'Looping':
        _state = Phd2State.looping;
        _statusMessage = 'Looping';
        break;
    }
  }

  /// Send a JSON-RPC request to PHD2
  Future<dynamic> _sendRequest(String method,
      [Map<String, dynamic>? params]) async {
    if (!_connected || _socket == null) {
      throw StateError('Not connected to PHD2');
    }

    final id = ++_requestId;
    final request = {
      'method': method,
      'id': id,
      if (params != null) 'params': params,
    };

    final completer = Completer<dynamic>();
    _pendingRequests[id] = completer;

    final json = jsonEncode(request) + '\r\n';
    _socket!.write(json);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('PHD2 request timed out: $method');
      },
    );
  }

  /// Get PHD2 app state
  Future<void> _getAppState() async {
    final result = await _sendRequest('get_app_state');
    _updateState(result as String?);
  }

  /// Start guiding
  Future<void> startGuiding({
    double settlePixels = 1.5,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
    bool recalibrate = false,
  }) async {
    final settle = {
      'pixels': settlePixels,
      'time': settleTime,
      'timeout': settleTimeout,
    };

    await _sendRequest('guide', {
      'settle': settle,
      'recalibrate': recalibrate,
    });
  }

  /// Stop guiding
  Future<void> stopGuiding() async {
    await _sendRequest('stop_capture');
  }

  /// Pause guiding
  Future<void> pauseGuiding() async {
    await _sendRequest('set_paused', {'paused': true});
  }

  /// Resume guiding
  Future<void> resumeGuiding() async {
    await _sendRequest('set_paused', {'paused': false});
  }

  /// Dither
  Future<void> dither({
    double amount = 5.0,
    bool raOnly = false,
    double settlePixels = 1.5,
    double settleTime = 10.0,
    double settleTimeout = 60.0,
  }) async {
    final settle = {
      'pixels': settlePixels,
      'time': settleTime,
      'timeout': settleTimeout,
    };

    await _sendRequest('dither', {
      'amount': amount,
      'raOnly': raOnly,
      'settle': settle,
    });
  }

  /// Loop exposures (start looping without guiding)
  Future<void> loop() async {
    await _sendRequest('loop');
  }

  /// Auto-select a guide star
  Future<void> autoSelectStar() async {
    await _sendRequest('find_star');
  }

  /// Get current pixel scale
  Future<double> getPixelScale() async {
    final result = await _sendRequest('get_pixel_scale');
    return (result as num).toDouble();
  }

  /// Get exposure time
  Future<double> getExposure() async {
    final result = await _sendRequest('get_exposure');
    return (result as num).toDouble() / 1000.0; // Convert ms to seconds
  }

  /// Set exposure time
  Future<void> setExposure(double seconds) async {
    await _sendRequest('set_exposure', {'exposure': (seconds * 1000).round()});
  }

  /// Get camera connection status
  Future<bool> isCameraConnected() async {
    try {
      final result = await _sendRequest('get_connected');
      return result as bool;
    } catch (_) {
      return false;
    }
  }

  /// Get calibration data
  /// Returns null if not calibrated, otherwise returns calibration parameters
  Future<Map<String, dynamic>?> getCalibrationData() async {
    try {
      // PHD2's get_calibration_data returns calibration info for both axes
      final result =
          await _sendRequest('get_calibration_data', {'which': 'both'});
      if (result == null) return null;
      return result as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _shouldReconnect = false; // Prevent reconnection during dispose
    _stopHeartbeat();
    _handleDisconnect();
    _eventController.close();
    _connectionStateController.close();
  }
}

/// PHD2 event
class Phd2Event {
  final String event;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  Phd2Event({
    required this.event,
    required this.data,
    required this.timestamp,
  });
}

/// Check if PHD2 is running (try to connect briefly)
Future<bool> checkPhd2Running(
    {String host = 'localhost', int port = 4400}) async {
  try {
    final socket =
        await Socket.connect(host, port, timeout: const Duration(seconds: 1));
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
