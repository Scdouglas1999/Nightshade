import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/models/settings/app_settings.dart' as models;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Backend connection state
enum BackendConnectionState {
  connected,
  reconnecting,
  disconnected,
}

/// Network backend implementation that communicates with a headless server
///
/// This backend uses HTTP REST API and WebSocket for real-time events
/// and is used by the Mobile app to control a remote Desktop/Headless instance.
class NetworkBackend implements NightshadeBackend {
  final String serverHost;
  final int serverPort;
  final int webSocketPort;
  final String? authToken;

  WebSocketChannel? _wsChannel;
  final StreamController<NightshadeEvent> _eventController =
      StreamController<NightshadeEvent>.broadcast();

  // Connection state management
  BackendConnectionState _connectionState = BackendConnectionState.disconnected;
  final StreamController<BackendConnectionState> _connectionStateController =
      StreamController<BackendConnectionState>.broadcast();
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectDelay = 30; // Max 30 seconds

  NetworkBackend({
    required this.serverHost,
    this.serverPort = 8080,
    this.webSocketPort = 8080,  // WebSocket is on same port as HTTP
    this.authToken,
  }) {
    // Connect WebSocket immediately
    connect();
  }

  /// Stream of connection state changes
  Stream<BackendConnectionState> get connectionStateStream => _connectionStateController.stream;

  /// Current connection state
  BackendConnectionState get connectionState => _connectionState;

  /// Update connection state and notify listeners
  void _updateConnectionState(BackendConnectionState newState) {
    if (_connectionState != newState) {
      _connectionState = newState;
      _connectionStateController.add(newState);
      debugPrint('[NetworkBackend] Connection state changed to: $newState');
    }
  }

  /// Test connectivity to server
  Future<bool> testConnection() async {
    try {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/info');
      final client = HttpClient();
      
      try {
        final request = await client.getUrl(uri).timeout(const Duration(seconds: 3));
        final response = await request.close().timeout(const Duration(seconds: 3));
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('Connection test failed: $e');
      return false;
    }
  }

  /// Initialize the WebSocket connection for real-time events
  Future<void> connect() async {
    _reconnectTimer?.cancel();

    try {
      _updateConnectionState(BackendConnectionState.reconnecting);

      final wsUri = Uri.parse('ws://$serverHost:$webSocketPort/events');
      _wsChannel = IOWebSocketChannel.connect(wsUri);

      _wsChannel!.stream.listen(
        (message) {
          try {
            final json = jsonDecode(message as String) as Map<String, dynamic>;
            final event = _eventFromJson(json);
            _eventController.add(event);
          } catch (e) {
            debugPrint('Error parsing WebSocket message: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _eventController.addError(error);
          _handleConnectionFailure();
        },
        onDone: () {
          debugPrint('WebSocket connection closed');
          _handleConnectionFailure();
        },
      );

      // Connection successful
      _updateConnectionState(BackendConnectionState.connected);
      _reconnectAttempt = 0; // Reset reconnect counter on success
      debugPrint('[NetworkBackend] WebSocket connected successfully');
    } catch (e) {
      debugPrint('Failed to connect WebSocket: $e');
      _handleConnectionFailure();
    }
  }

  /// Handle connection failures with exponential backoff
  void _handleConnectionFailure() {
    _updateConnectionState(BackendConnectionState.disconnected);

    // Calculate exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
    final delay = Duration(
      seconds: [1, 2, 4, 8, 16, _maxReconnectDelay][_reconnectAttempt.clamp(0, 5)],
    );

    _reconnectAttempt++;
    debugPrint('[NetworkBackend] Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt)');

    _reconnectTimer = Timer(delay, () {
      if (_connectionState != BackendConnectionState.connected) {
        debugPrint('[NetworkBackend] Attempting reconnection...');
        connect();
      }
    });
  }

  /// Disconnect from the server
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _wsChannel?.sink.close();
    _wsChannel = null;
    _updateConnectionState(BackendConnectionState.disconnected);
  }

  /// Dispose resources
  void dispose() {
    _reconnectTimer?.cancel();
    _wsChannel?.sink.close();
    _eventController.close();
    _connectionStateController.close();
  }

  @override
  Stream<NightshadeEvent> get eventStream => _eventController.stream;

  // =========================================================================
  // HTTP Helper Methods
  // =========================================================================

  /// Add authentication headers to HTTP requests
  Map<String, String> _addAuthHeaders(Map<String, String> headers) {
    if (authToken != null) {
      headers['Authorization'] = 'Bearer $authToken';
    }
    return headers;
  }

  /// Determine if an HTTP exception is a transient failure that can be retried
  bool _isTransientFailure(dynamic error) {
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
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode >= 500;
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
          debugPrint('[NetworkBackend] Request failed after $maxAttempts attempts: $e');
          rethrow;
        }

        // Only retry transient failures
        if (!_isTransientFailure(e)) {
          debugPrint('[NetworkBackend] Non-transient failure, not retrying: $e');
          rethrow;
        }

        // Calculate backoff delay: 1s, 2s, 4s
        final delay = Duration(seconds: 1 << (attempt - 1));
        debugPrint('[NetworkBackend] Transient failure, retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts): $e');
        await Future.delayed(delay);
      }
    }

    // Should never reach here, but throw last exception just in case
    throw lastException!;
  }

  Future<Map<String, dynamic>> _get(String endpoint, [Map<String, dynamic>? queryParams]) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint')
          .replace(queryParameters: queryParams?.map((k, v) => MapEntry(k, v.toString())) ?? {});
      final client = HttpClient();

      try {
        final request = await client.getUrl(uri);

        // Add authentication headers
        final headers = _addAuthHeaders({});
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        final response = await request.close();

        // Check for transient status codes
        if (_isTransientStatusCode(response.statusCode)) {
          throw Exception('HTTP ${response.statusCode}: Transient failure for GET $endpoint');
        }

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}: Failed to GET $endpoint');
        }

        final responseBody = await response.transform(utf8.decoder).join();
        return jsonDecode(responseBody) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    });
  }

  Future<Map<String, dynamic>> _post(String endpoint, [Map<String, dynamic>? body]) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');
      final client = HttpClient();

      try {
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;

        // Add authentication headers
        final headers = _addAuthHeaders({});
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        if (body != null) {
          request.write(jsonEncode(body));
        }

        final response = await request.close();

        // Check for transient status codes
        if (_isTransientStatusCode(response.statusCode)) {
          throw Exception('HTTP ${response.statusCode}: Transient failure for POST $endpoint');
        }

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}: Failed to POST $endpoint');
        }

        final responseBody = await response.transform(utf8.decoder).join();
        return jsonDecode(responseBody) as Map<String, dynamic>;
      } finally {
        client.close();
      }
    });
  }

  Future<void> _delete(String endpoint) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/$endpoint');
      final client = HttpClient();

      try {
        final request = await client.deleteUrl(uri);

        // Add authentication headers
        final headers = _addAuthHeaders({});
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        final response = await request.close();

        // Check for transient status codes
        if (_isTransientStatusCode(response.statusCode)) {
          throw Exception('HTTP ${response.statusCode}: Transient failure for DELETE $endpoint');
        }

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}: Failed to DELETE $endpoint');
        }
      } finally {
        client.close();
      }
    });
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
      debugPrint('[NetworkBackend] Using cached device list (${_cachedDevices!.length} devices)');
    } else if (_ongoingDiscovery != null) {
      // Another discovery is in progress, wait for it
      debugPrint('[NetworkBackend] Waiting for ongoing discovery...');
      _cachedDevices = await _ongoingDiscovery!;
    } else {
      // Start new discovery
      debugPrint('[NetworkBackend] Starting new device discovery...');
      _ongoingDiscovery = _fetchDevicesFromServer();
      try {
        _cachedDevices = await _ongoingDiscovery!;
        _cacheTimestamp = DateTime.now();
        debugPrint('[NetworkBackend] Cached ${_cachedDevices!.length} devices');
      } finally {
        _ongoingDiscovery = null;
      }
    }
    
    final deviceList = _cachedDevices ?? [];
    
    // Filter by requested type and convert
    final filtered = deviceList
        .where((d) {
          final typeStr = (d['type'] as String).toLowerCase();
          final requestedTypeStr = deviceType.name.toLowerCase();
          // Handle filterwheel vs filterWheel naming
          if (requestedTypeStr == 'filterwheel') {
            return typeStr == 'filterwheel' || typeStr == 'filterwheel';
          }
          return typeStr == requestedTypeStr;
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
    
    debugPrint('[NetworkBackend] Returning ${filtered.length} ${deviceType.name} devices');
    return filtered;
  }

  Future<List<Map<String, dynamic>>> _fetchDevicesFromServer() async {
    final response = await _get('devices');
    return (response['devices'] as List? ?? response['available'] as List? ?? [])
        .cast<Map<String, dynamic>>();
  }

  /// Invalidate device cache (called when "Scan Network" is clicked)
  void invalidateDeviceCache() {
    debugPrint('[NetworkBackend] Cache invalidated');
    _cachedDevices = null;
    _cacheTimestamp = null;
  }

  @override
  Future<List<DeviceInfo>> discoverIndiAtAddress(String host, int port) async {
    final response = await _get('devices/discover-indi', {
      'host': host,
      'port': port.toString(),
    });

    final devices = response as List<dynamic>? ?? [];
    return devices.map((d) => DeviceInfo(
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
    )).toList();
  }

  @override
  Future<List<DeviceInfo>> discoverAlpacaAtAddress(String host, int port) async {
    final response = await _get('devices/discover-alpaca', {
      'host': host,
      'port': port.toString(),
    });

    final devices = response as List<dynamic>? ?? [];
    return devices.map((d) => DeviceInfo(
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
    )).toList();
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
    
    return deviceList.map((d) => DeviceInfo(
      id: d['id'] as String,
      name: d['name'] as String,
      deviceType: _parseDeviceType(d['type'] as String),
      driverType: _parseDriverType(d['driverType'] as String),
      description: d['description'] as String? ?? '',
      driverVersion: d['driverVersion'] as String? ?? '',
    )).toList();
  }

  // =========================================================================
  // Camera Control
  // =========================================================================

  @override
  Future<void> cameraStartExposure({
    required String deviceId,
    required double exposureTime,
    required FrameType frameType,
    required int gain,
    required int offset,
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
      'gain': gain,
      'offset': offset,
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
  Future<CapturedImageResult?> cameraGetLastImage(String deviceId) async {
    final response = await _get('camera/last-image?deviceId=$deviceId');
    if (response['image'] == null) return null;

    final img = response['image'] as Map<String, dynamic>;
    return CapturedImageResult(
      width: img['width'] as int,
      height: img['height'] as int,
      displayData: List<int>.from(img['displayData'] as List),
      histogram: List<int>.from(img['histogram'] as List),
      stats: ImageStatsResult(
        min: (img['stats']['min'] as num).toDouble(),
        max: (img['stats']['max'] as num).toDouble(),
        mean: (img['stats']['mean'] as num).toDouble(),
        median: (img['stats']['median'] as num).toDouble(),
        stdDev: (img['stats']['stdDev'] as num).toDouble(),
        hfr: img['stats']['hfr'] as double?,
        starCount: img['stats']['starCount'] as int,
      ),
      exposureTime: (img['exposureTime'] as num).toDouble(),
      timestamp: img['timestamp'] as String,
      isColor: img['isColor'] as bool? ?? false,  // Default to grayscale for backward compatibility
    );
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

  // =========================================================================
  // Mount Control
  // =========================================================================

  @override
  Future<void> mountSlewToCoordinates(String deviceId, double ra, double dec) async {
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
  Future<bridge_api.AutofocusResultApi> autofocusStart({
    required String deviceId,
    required String cameraId,
    required double exposureTime,
    required int stepSize,
    required int stepsOut,
    String method = 'VCurve',
    int binning = 1,
  }) async {
    final response = await _post('focuser/autofocus/start', {
      'deviceId': deviceId,
      'cameraId': cameraId,
      'exposureTime': exposureTime,
      'stepSize': stepSize,
      'stepsOut': stepsOut,
      'method': method,
      'binning': binning,
    });

    // Parse focus data points from response
    final focusDataList = (response['focusData'] as List<dynamic>?)
        ?.map((item) => bridge_api.FocusDataPoint(
              position: (item['position'] as num).toInt(),
              hfr: (item['hfr'] as num).toDouble(),
              starCount: (item['starCount'] as num?)?.toInt() ?? 0,
            ))
        .toList() ?? [];

    return bridge_api.AutofocusResultApi(
      bestPosition: (response['bestPosition'] as num).toInt(),
      bestHfr: (response['bestHfr'] as num).toDouble(),
      focusData: focusDataList,
      method: response['method'] as String? ?? method,
      temperature: (response['temperature'] as num?)?.toDouble(),
      timestamp: (response['timestamp'] as num).toInt(),
      curveFitQuality: (response['curveFitQuality'] as num?)?.toDouble() ?? 0.0,
      backlashApplied: response['backlashApplied'] as bool? ?? false,
    );
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
    // TODO: Implement network API for star image
    throw UnimplementedError('PHD2 star image not yet available over network');
  }

  @override
  Future<List<String>> phd2GetAlgoParamNames({required String axis}) async {
    // TODO: Implement network API
    throw UnimplementedError('PHD2 brain params not yet available over network');
  }

  @override
  Future<double> phd2GetAlgoParam({
    required String axis,
    required String name,
  }) async {
    // TODO: Implement network API
    throw UnimplementedError('PHD2 brain params not yet available over network');
  }

  @override
  Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    // TODO: Implement network API
    throw UnimplementedError('PHD2 brain params not yet available over network');
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
  }) async {
    await _post('sequencer/devices', {
      'cameraId': cameraId,
      'mountId': mountId,
      'focuserId': focuserId,
      'filterwheelId': filterwheelId,
      'rotatorId': rotatorId,
      'filterNames': filterNames,
    });
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
  Future<dynamic> getCameraStatus(String deviceId) async {
    final response = await _get('equipment/camera/status?deviceId=$deviceId');
    return response;  // Return raw JSON, will be converted by caller
  }

  @override
  Future<dynamic> getMountStatus(String deviceId) async {
    final response = await _get('equipment/mount/status?deviceId=$deviceId');
    return response;  // Return raw JSON, will be converted by caller
  }

  @override
  Future<dynamic> getFocuserStatus(String deviceId) async {
    final response = await _get('equipment/focuser/status?deviceId=$deviceId');
    return response;  // Return raw JSON, will be converted by caller
  }

  @override
  Future<dynamic> getFilterWheelStatus(String deviceId) async {
    final response = await _get('equipment/filter-wheel/status?deviceId=$deviceId');
    return response;  // Return raw JSON, will be converted by caller
  }

  // =========================================================================
  // Type Conversion Helpers
  // =========================================================================

  DeviceType _parseDeviceType(String str) {
    switch (str.toLowerCase()) {
      case 'camera': return DeviceType.camera;
      case 'mount': return DeviceType.mount;
      case 'focuser': return DeviceType.focuser;
      case 'filterwheel': return DeviceType.filterWheel;
      case 'guider': return DeviceType.guider;
      case 'dome': return DeviceType.dome;
      case 'rotator': return DeviceType.rotator;
      case 'weather': return DeviceType.weather;
      case 'safetymonitor': return DeviceType.safetyMonitor;
      default: throw Exception('Unknown device type: $str');
    }
  }

  DriverType _parseDriverType(String str) {
    switch (str.toLowerCase()) {
      case 'ascom': return DriverType.ascom;
      case 'alpaca': return DriverType.alpaca;
      case 'indi': return DriverType.indi;
      case 'simulator': return DriverType.simulator;
      default: throw Exception('Unknown driver type: $str');
    }
  }

  EventSeverity _parseSeverity(String str) {
    switch (str.toLowerCase()) {
      case 'info': return EventSeverity.info;
      case 'warning': return EventSeverity.warning;
      case 'error': return EventSeverity.error;
      case 'critical': return EventSeverity.critical;
      default: return EventSeverity.info;
    }
  }

  EventCategory _parseCategory(String str) {
    switch (str.toLowerCase()) {
      case 'equipment': return EventCategory.equipment;
      case 'imaging': return EventCategory.imaging;
      case 'guiding': return EventCategory.guiding;
      case 'sequencer': return EventCategory.sequencer;
      case 'safety': return EventCategory.safety;
      case 'system': return EventCategory.system;
      case 'polaralignment': return EventCategory.polarAlignment;
      default: return EventCategory.system;
    }
  }

  NightshadeEvent _eventFromJson(Map<String, dynamic> json) {
    return NightshadeEvent(
      timestamp: json['timestamp'] as int,
      severity: _parseSeverity(json['severity'] as String),
      category: _parseCategory(json['category'] as String),
      eventType: json['eventType'] as String,
      data: json['data'] as Map<String, dynamic>,
    );
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
    return EquipmentProfile.fromJson(response['profile'] as Map<String, dynamic>);
  }

  // =========================================================================
  // Settings & Location
  // =========================================================================

  @override
  Future<models.AppSettings> getSettings() async {
    final json = await _get('settings');
    return models.AppSettings.fromJson(json['settings'] as Map<String, dynamic>);
  }

  @override
  Future<void> updateSettings(models.AppSettings settings) async {
    await _post('settings', {'settings': settings.toJson()});
  }

  @override
  Future<models.ObserverLocation?> getLocation() async {
    final json = await _get('settings/location');
    if (json['location'] == null) return null;
    return models.ObserverLocation.fromJson(json['location'] as Map<String, dynamic>);
  }

  @override
  Future<void> setLocation(models.ObserverLocation? location) async {
    await _post('settings/location', {'location': location?.toJson()});
  }

  // =========================================================================
  // Image Processing
  // =========================================================================

  @override
  Future<ImageStats> getImageStats(int width, int height, Uint16List data) async {
    final response = await _post('imaging/stats', {
      'width': width,
      'height': height,
      'data': data.toList(),
    });
    return ImageStats.fromJson(response['stats'] as Map<String, dynamic>);
  }

  @override
  Future<Uint8List> autoStretchImage(int width, int height, Uint16List data) async {
    final response = await _post('imaging/stretch', {
      'width': width,
      'height': height,
      'data': data.toList(),
    });
    return Uint8List.fromList((response['data'] as List).cast<int>());
  }

  @override
  Future<Uint8List> debayerImage(
    int width,
    int height,
    Uint16List data,
    String pattern,
    String algorithm,
  ) async {
    final response = await _post('imaging/debayer', {
      'width': width,
      'height': height,
      'data': data.toList(),
      'pattern': pattern,
      'algorithm': algorithm,
    });
    return Uint8List.fromList((response['data'] as List).cast<int>());
  }

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  final _polarAlignController = StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents => _polarAlignController.stream;

  @override
  Future<void> startPolarAlignment({
    required double exposureTime,
    required double stepSize,
    required int binning,
    required bool isNorth,
    required bool manualRotation,
    required bool rotateEast,
  }) async {
    await _post('polar-alignment/start', {
      'exposure_time': exposureTime,
      'step_size': stepSize,
      'binning': binning,
      'is_north': isNorth,
      'manual_rotation': manualRotation,
      'rotate_east': rotateEast,
    });
  }

  @override
  Future<void> stopPolarAlignment() async {
    await _post('polar-alignment/stop', {});
  }

  // =========================================================================
  // Image Download (for Mobile)
  // =========================================================================

  @override
  Future<List<CapturedImage>> getSessionImages(int sessionId) async {
    final response = await _get('sessions/$sessionId/images');
    final imagesList = (response['images'] as List?) ?? [];
    
    return imagesList.map((img) {
      return CapturedImage(
        id: img['image_id'].toString(),
        filePath: img['file_path'] as String,
        capturedAt: DateTime.fromMillisecondsSinceEpoch((img['captured_at'] as int) * 1000),
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

  @override
  Future<Uint8List> getImageThumbnail(int imageId) async {
    final uri = Uri.parse('http://$serverHost:$serverPort/api/images/$imageId/thumbnail');
    final client = HttpClient();
    
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: Failed to get thumbnail');
      }
      
      final bytes = await consolidateHttpClientResponseBytes(response);
      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> downloadImage(int imageId, String localPath, {void Function(double)? onProgress}) async {
    final uri = Uri.parse('http://$serverHost:$serverPort/api/images/$imageId/download');
    final client = HttpClient();
    
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: Failed to download image');
      }
      
      // Get content length for progress tracking
      final contentLength = response.contentLength;
      
      // Stream to file
      final file = File(localPath);
      await file.parent.create(recursive: true);
      
      final sink = file.openWrite();
      int bytesReceived = 0;
      
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          bytesReceived += chunk.length;
          
          if (onProgress != null && contentLength > 0) {
            onProgress(bytesReceived / contentLength);
          }
        }
      } finally {
        await sink.close();
      }
      
      debugPrint('[NetworkBackend] Downloaded image $imageId to $localPath ($bytesReceived bytes)');
    } finally {
      client.close();
    }
  }

  FrameType _parseFrameType(String str) {
    switch (str.toLowerCase()) {
      case 'light': return FrameType.light;
      case 'dark': return FrameType.dark;
      case 'flat': return FrameType.flat;
      case 'bias': return FrameType.bias;
      case 'darkflat': return FrameType.darkFlat;
      default: return FrameType.light;
    }
  }

  ImageFileFormat _parseImageFormat(String str) {
    switch (str.toLowerCase()) {
      case 'fits': return ImageFileFormat.fits;
      case 'xisf': return ImageFileFormat.xisf;
      case 'tiff': return ImageFileFormat.tiff;
      case 'png': return ImageFileFormat.png;
      case 'jpeg':
      case 'jpg': return ImageFileFormat.jpeg;
      default: return ImageFileFormat.fits;
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
  Future<List<int>> getLastRawImageData() async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/imaging/raw-data');
      final client = HttpClient();

      try {
        final request = await client.getUrl(uri);

        // Add authentication headers
        final headers = _addAuthHeaders({});
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        final response = await request.close();

        // Check for transient status codes
        if (_isTransientStatusCode(response.statusCode)) {
          throw Exception('HTTP ${response.statusCode}: Transient failure for GET imaging/raw-data');
        }

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}: Failed to GET imaging/raw-data');
        }

        // Read binary data
        final bytes = await consolidateHttpClientResponseBytes(response);
        return bytes;
      } finally {
        client.close();
      }
    });
  }

  @override
  Future<void> saveFitsFile({
    required String filePath,
    required int width,
    required int height,
    required List<int> data,
    required bridge_api.FitsWriteHeader headerData,
  }) async {
    return _retryableRequest(() async {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/imaging/save-fits');
      final client = HttpClient();

      try {
        final request = await client.postUrl(uri);
        request.headers.contentType = ContentType.json;

        // Add authentication headers
        final headers = _addAuthHeaders({});
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });

        // Serialize FITS header to JSON
        final headerJson = {
          'objectName': headerData.objectName,
          'exposureTime': headerData.exposureTime,
          'captureTimestamp': headerData.captureTimestamp,
          'frameType': headerData.frameType,
          'filter': headerData.filter,
          'gain': headerData.gain,
          'offset': headerData.offset,
          'ccdTemp': headerData.ccdTemp,
          'ra': headerData.ra,
          'dec': headerData.dec,
          'altitude': headerData.altitude,
          'telescope': headerData.telescope,
          'instrument': headerData.instrument,
          'observer': headerData.observer,
          'binX': headerData.binX,
          'binY': headerData.binY,
          'focalLength': headerData.focalLength,
          'aperture': headerData.aperture,
          'pixelSizeX': headerData.pixelSizeX,
          'pixelSizeY': headerData.pixelSizeY,
          'siteLatitude': headerData.siteLatitude,
          'siteLongitude': headerData.siteLongitude,
          'siteElevation': headerData.siteElevation,
        };

        // Build request body
        final body = {
          'filePath': filePath,
          'width': width,
          'height': height,
          'data': data,
          'headerData': headerJson,
        };

        request.write(jsonEncode(body));

        final response = await request.close();

        // Check for transient status codes
        if (_isTransientStatusCode(response.statusCode)) {
          throw Exception('HTTP ${response.statusCode}: Transient failure for POST imaging/save-fits');
        }

        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}: Failed to POST imaging/save-fits');
        }

        // Consume response body to complete the request
        await response.transform(utf8.decoder).join();
      } finally {
        client.close();
      }
    });
  }
}

/// Helper function to consolidate HTTP response bytes
Future<List<int>> consolidateHttpClientResponseBytes(HttpClientResponse response) {
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
