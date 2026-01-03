import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// API handler function types
typedef DevicesHandler = Future<Map<String, dynamic>> Function();
typedef DeviceConnectHandler = Future<void> Function(String deviceType, String deviceId);
typedef DeviceDisconnectHandler = Future<void> Function(String deviceType, String deviceId);
typedef ConnectedDevicesHandler = Future<List<Map<String, dynamic>>> Function();
typedef SequenceStatusHandler = Future<Map<String, dynamic>> Function();
typedef SequenceStartHandler = Future<Map<String, dynamic>> Function(String? body);
typedef SequenceStopHandler = Future<Map<String, dynamic>> Function();
typedef ImagesHandler = Future<List<Map<String, dynamic>>> Function({int? limit});
typedef Phd2ConnectHandler = Future<void> Function({String? host, int? port});
typedef Phd2DisconnectHandler = Future<void> Function();

// Camera handlers
typedef CameraExposeHandler = Future<void> Function(Map<String, dynamic> params);
typedef CameraAbortHandler = Future<void> Function(String deviceId);
typedef CameraGetLastImageHandler = Future<Map<String, dynamic>?> Function(String deviceId);
typedef CameraSetCoolingHandler = Future<void> Function(String deviceId, bool enabled, double? targetTemp);
typedef CameraSetGainHandler = Future<void> Function(String deviceId, int gain);
typedef CameraSetOffsetHandler = Future<void> Function(String deviceId, int offset);

// Mount handlers
typedef MountSlewHandler = Future<void> Function(String deviceId, double ra, double dec);
typedef MountSyncHandler = Future<void> Function(String deviceId, double ra, double dec);
typedef MountParkHandler = Future<void> Function(String deviceId);
typedef MountUnparkHandler = Future<void> Function(String deviceId);
typedef MountSetTrackingHandler = Future<void> Function(String deviceId, bool enabled);
typedef MountPulseGuideHandler = Future<void> Function(String deviceId, String direction, int durationMs);
typedef MountAbortHandler = Future<void> Function(String deviceId);
typedef MountGetStatusHandler = Future<Map<String, dynamic>> Function(String deviceId);

// Focuser handlers
typedef FocuserMoveToHandler = Future<void> Function(String deviceId, int position);
typedef FocuserMoveRelativeHandler = Future<void> Function(String deviceId, int delta);
typedef FocuserHaltHandler = Future<void> Function(String deviceId);
typedef AutofocusStartHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> params);
typedef AutofocusCancelHandler = Future<void> Function();

// Filter wheel handlers
typedef FilterWheelSetPositionHandler = Future<void> Function(String deviceId, int position);
typedef FilterWheelGetNamesHandler = Future<List<String>> Function(String deviceId);
typedef FilterWheelSetByNameHandler = Future<void> Function(String deviceId, String name);

// Rotator handlers
typedef RotatorMoveToHandler = Future<void> Function(String deviceId, double angle);
typedef RotatorMoveRelativeHandler = Future<void> Function(String deviceId, double delta);
typedef RotatorGetStatusHandler = Future<Map<String, dynamic>> Function(String deviceId);
typedef RotatorHaltHandler = Future<void> Function(String deviceId);

// Equipment status handlers
typedef EquipmentStatusHandler = Future<Map<String, dynamic>> Function(String deviceId);

// PHD2 extended handlers
typedef Phd2GetStatusHandler = Future<Map<String, dynamic>> Function();
typedef Phd2StartGuidingHandler = Future<void> Function(Map<String, dynamic> params);
typedef Phd2StopGuidingHandler = Future<void> Function();
typedef Phd2DitherHandler = Future<void> Function(Map<String, dynamic> params);

// Settings handlers
typedef GetSettingsHandler = Future<Map<String, dynamic>> Function();
typedef UpdateSettingsHandler = Future<void> Function(Map<String, dynamic> settings);
typedef GetLocationHandler = Future<Map<String, dynamic>?> Function();
typedef SetLocationHandler = Future<void> Function(Map<String, dynamic>? location);

// Sequencer extended handlers
typedef SequencerPauseHandler = Future<void> Function();
typedef SequencerResumeHandler = Future<void> Function();
typedef SequencerLoadHandler = Future<void> Function(String json);
typedef SequencerSetSimulationHandler = Future<void> Function(bool enabled);

// Plate solve handler
typedef PlateSolveHandler = Future<Map<String, dynamic>> Function(Map<String, dynamic> params);

// Polar alignment handlers
typedef PolarAlignmentStartHandler = Future<void> Function(Map<String, dynamic> params);
typedef PolarAlignmentStopHandler = Future<void> Function();

// Profile handlers
typedef GetProfilesHandler = Future<List<Map<String, dynamic>>> Function();
typedef SaveProfileHandler = Future<void> Function(Map<String, dynamic> profile);
typedef DeleteProfileHandler = Future<void> Function(String profileId);
typedef LoadProfileHandler = Future<void> Function(String profileId);
typedef GetActiveProfileHandler = Future<Map<String, dynamic>?> Function();

/// Simple HTTP server for serving API endpoints
/// This allows the desktop app to be controlled by mobile devices via REST API
class NightshadeWebServer {
  HttpServer? _server;
  final int port;
  final String? webRoot;
  bool _isRunning = false;
  bool _apiOnlyMode = false;
  int? _actualPort;
  
  // API handlers - can be set to wire up to actual functionality
  DevicesHandler? _devicesHandler;
  DeviceConnectHandler? _deviceConnectHandler;
  DeviceDisconnectHandler? _deviceDisconnectHandler;
  ConnectedDevicesHandler? _connectedDevicesHandler;
  SequenceStatusHandler? _sequenceStatusHandler;
  SequenceStartHandler? _sequenceStartHandler;
  SequenceStopHandler? _sequenceStopHandler;
  ImagesHandler? _imagesHandler;
  Phd2ConnectHandler? _phd2ConnectHandler;
  Phd2DisconnectHandler? _phd2DisconnectHandler;

  // Camera handlers
  CameraExposeHandler? _cameraExposeHandler;
  CameraAbortHandler? _cameraAbortHandler;
  CameraGetLastImageHandler? _cameraGetLastImageHandler;
  CameraSetCoolingHandler? _cameraSetCoolingHandler;
  CameraSetGainHandler? _cameraSetGainHandler;
  CameraSetOffsetHandler? _cameraSetOffsetHandler;

  // Mount handlers
  MountSlewHandler? _mountSlewHandler;
  MountSyncHandler? _mountSyncHandler;
  MountParkHandler? _mountParkHandler;
  MountUnparkHandler? _mountUnparkHandler;
  MountSetTrackingHandler? _mountSetTrackingHandler;
  MountPulseGuideHandler? _mountPulseGuideHandler;
  MountAbortHandler? _mountAbortHandler;
  MountGetStatusHandler? _mountGetStatusHandler;

  // Focuser handlers
  FocuserMoveToHandler? _focuserMoveToHandler;
  FocuserMoveRelativeHandler? _focuserMoveRelativeHandler;
  FocuserHaltHandler? _focuserHaltHandler;
  AutofocusStartHandler? _autofocusStartHandler;
  AutofocusCancelHandler? _autofocusCancelHandler;

  // Filter wheel handlers
  FilterWheelSetPositionHandler? _filterWheelSetPositionHandler;
  FilterWheelGetNamesHandler? _filterWheelGetNamesHandler;
  FilterWheelSetByNameHandler? _filterWheelSetByNameHandler;

  // Rotator handlers
  RotatorMoveToHandler? _rotatorMoveToHandler;
  RotatorMoveRelativeHandler? _rotatorMoveRelativeHandler;
  RotatorGetStatusHandler? _rotatorGetStatusHandler;
  RotatorHaltHandler? _rotatorHaltHandler;

  // Equipment status handlers
  EquipmentStatusHandler? _cameraStatusHandler;
  EquipmentStatusHandler? _mountStatusHandler;
  EquipmentStatusHandler? _focuserStatusHandler;
  EquipmentStatusHandler? _filterWheelStatusHandler;

  // PHD2 extended handlers
  Phd2GetStatusHandler? _phd2GetStatusHandler;
  Phd2StartGuidingHandler? _phd2StartGuidingHandler;
  Phd2StopGuidingHandler? _phd2StopGuidingHandler;
  Phd2DitherHandler? _phd2DitherHandler;

  // Settings handlers
  GetSettingsHandler? _getSettingsHandler;
  UpdateSettingsHandler? _updateSettingsHandler;
  GetLocationHandler? _getLocationHandler;
  SetLocationHandler? _setLocationHandler;

  // Sequencer extended handlers
  SequencerPauseHandler? _sequencerPauseHandler;
  SequencerResumeHandler? _sequencerResumeHandler;
  SequencerLoadHandler? _sequencerLoadHandler;
  SequencerSetSimulationHandler? _sequencerSetSimulationHandler;

  // Plate solve handler
  PlateSolveHandler? _plateSolveHandler;

  // Polar alignment handlers
  PolarAlignmentStartHandler? _polarAlignmentStartHandler;
  PolarAlignmentStopHandler? _polarAlignmentStopHandler;

  // Profile handlers
  GetProfilesHandler? _getProfilesHandler;
  SaveProfileHandler? _saveProfileHandler;
  DeleteProfileHandler? _deleteProfileHandler;
  LoadProfileHandler? _loadProfileHandler;
  GetActiveProfileHandler? _getActiveProfileHandler;

  NightshadeWebServer({
    this.port = 8080,
    this.webRoot,
    DevicesHandler? devicesHandler,
    DeviceConnectHandler? deviceConnectHandler,
    DeviceDisconnectHandler? deviceDisconnectHandler,
    ConnectedDevicesHandler? connectedDevicesHandler,
    SequenceStatusHandler? sequenceStatusHandler,
    SequenceStartHandler? sequenceStartHandler,
    SequenceStopHandler? sequenceStopHandler,
    ImagesHandler? imagesHandler,
    Phd2ConnectHandler? phd2ConnectHandler,
    Phd2DisconnectHandler? phd2DisconnectHandler,
  }) : _devicesHandler = devicesHandler,
       _deviceConnectHandler = deviceConnectHandler,
       _deviceDisconnectHandler = deviceDisconnectHandler,
       _connectedDevicesHandler = connectedDevicesHandler,
       _sequenceStatusHandler = sequenceStatusHandler,
       _sequenceStartHandler = sequenceStartHandler,
       _sequenceStopHandler = sequenceStopHandler,
       _imagesHandler = imagesHandler,
       _phd2ConnectHandler = phd2ConnectHandler,
       _phd2DisconnectHandler = phd2DisconnectHandler {
    // If webRoot is null or doesn't exist, use API-only mode
    if (webRoot == null) {
      _apiOnlyMode = true;
    } else {
      final webRootDir = Directory(webRoot!);
      _apiOnlyMode = !webRootDir.existsSync();
    }
    
    // Log handler registration
    print('[WebServer] Initialized with:');
    print('[WebServer]   devicesHandler: ${devicesHandler != null ? "REGISTERED" : "NULL"}');
    print('[WebServer]   sequenceStatusHandler: ${sequenceStatusHandler != null ? "REGISTERED" : "NULL"}');
    print('[WebServer]   API-only mode: $_apiOnlyMode');
  }

  /// Check if server is running
  bool get isRunning => _isRunning;

  /// Check if server is in API-only mode
  bool get isApiOnlyMode => _apiOnlyMode;

  /// Get the actual port the server is listening on
  int get actualPort => _actualPort ?? port;

  // =========================================================================
  // Handler setters - use these to wire up handlers after construction
  // =========================================================================

  // Camera handlers
  set cameraExposeHandler(CameraExposeHandler? h) => _cameraExposeHandler = h;
  set cameraAbortHandler(CameraAbortHandler? h) => _cameraAbortHandler = h;
  set cameraGetLastImageHandler(CameraGetLastImageHandler? h) => _cameraGetLastImageHandler = h;
  set cameraSetCoolingHandler(CameraSetCoolingHandler? h) => _cameraSetCoolingHandler = h;
  set cameraSetGainHandler(CameraSetGainHandler? h) => _cameraSetGainHandler = h;
  set cameraSetOffsetHandler(CameraSetOffsetHandler? h) => _cameraSetOffsetHandler = h;

  // Mount handlers
  set mountSlewHandler(MountSlewHandler? h) => _mountSlewHandler = h;
  set mountSyncHandler(MountSyncHandler? h) => _mountSyncHandler = h;
  set mountParkHandler(MountParkHandler? h) => _mountParkHandler = h;
  set mountUnparkHandler(MountUnparkHandler? h) => _mountUnparkHandler = h;
  set mountSetTrackingHandler(MountSetTrackingHandler? h) => _mountSetTrackingHandler = h;
  set mountPulseGuideHandler(MountPulseGuideHandler? h) => _mountPulseGuideHandler = h;
  set mountAbortHandler(MountAbortHandler? h) => _mountAbortHandler = h;
  set mountGetStatusHandler(MountGetStatusHandler? h) => _mountGetStatusHandler = h;

  // Focuser handlers
  set focuserMoveToHandler(FocuserMoveToHandler? h) => _focuserMoveToHandler = h;
  set focuserMoveRelativeHandler(FocuserMoveRelativeHandler? h) => _focuserMoveRelativeHandler = h;
  set focuserHaltHandler(FocuserHaltHandler? h) => _focuserHaltHandler = h;
  set autofocusStartHandler(AutofocusStartHandler? h) => _autofocusStartHandler = h;
  set autofocusCancelHandler(AutofocusCancelHandler? h) => _autofocusCancelHandler = h;

  // Filter wheel handlers
  set filterWheelSetPositionHandler(FilterWheelSetPositionHandler? h) => _filterWheelSetPositionHandler = h;
  set filterWheelGetNamesHandler(FilterWheelGetNamesHandler? h) => _filterWheelGetNamesHandler = h;
  set filterWheelSetByNameHandler(FilterWheelSetByNameHandler? h) => _filterWheelSetByNameHandler = h;

  // Rotator handlers
  set rotatorMoveToHandler(RotatorMoveToHandler? h) => _rotatorMoveToHandler = h;
  set rotatorMoveRelativeHandler(RotatorMoveRelativeHandler? h) => _rotatorMoveRelativeHandler = h;
  set rotatorGetStatusHandler(RotatorGetStatusHandler? h) => _rotatorGetStatusHandler = h;
  set rotatorHaltHandler(RotatorHaltHandler? h) => _rotatorHaltHandler = h;

  // Equipment status handlers
  set cameraStatusHandler(EquipmentStatusHandler? h) => _cameraStatusHandler = h;
  set mountStatusHandler(EquipmentStatusHandler? h) => _mountStatusHandler = h;
  set focuserStatusHandler(EquipmentStatusHandler? h) => _focuserStatusHandler = h;
  set filterWheelStatusHandler(EquipmentStatusHandler? h) => _filterWheelStatusHandler = h;

  // PHD2 extended handlers
  set phd2GetStatusHandler(Phd2GetStatusHandler? h) => _phd2GetStatusHandler = h;
  set phd2StartGuidingHandler(Phd2StartGuidingHandler? h) => _phd2StartGuidingHandler = h;
  set phd2StopGuidingHandler(Phd2StopGuidingHandler? h) => _phd2StopGuidingHandler = h;
  set phd2DitherHandler(Phd2DitherHandler? h) => _phd2DitherHandler = h;

  // Settings handlers
  set getSettingsHandler(GetSettingsHandler? h) => _getSettingsHandler = h;
  set updateSettingsHandler(UpdateSettingsHandler? h) => _updateSettingsHandler = h;
  set getLocationHandler(GetLocationHandler? h) => _getLocationHandler = h;
  set setLocationHandler(SetLocationHandler? h) => _setLocationHandler = h;

  // Sequencer extended handlers
  set sequencerStartHandler(SequenceStartHandler? h) => _sequenceStartHandler = h;
  set sequencerStopHandler(SequenceStopHandler? h) => _sequenceStopHandler = h;
  set sequencerStatusHandler(SequenceStatusHandler? h) => _sequenceStatusHandler = h;
  set sequencerPauseHandler(SequencerPauseHandler? h) => _sequencerPauseHandler = h;
  set sequencerResumeHandler(SequencerResumeHandler? h) => _sequencerResumeHandler = h;
  set sequencerLoadHandler(SequencerLoadHandler? h) => _sequencerLoadHandler = h;
  set sequencerSetSimulationHandler(SequencerSetSimulationHandler? h) => _sequencerSetSimulationHandler = h;

  // Plate solve handler
  set plateSolveHandler(PlateSolveHandler? h) => _plateSolveHandler = h;

  // Polar alignment handlers
  set polarAlignmentStartHandler(PolarAlignmentStartHandler? h) => _polarAlignmentStartHandler = h;
  set polarAlignmentStopHandler(PolarAlignmentStopHandler? h) => _polarAlignmentStopHandler = h;

  // Profile handlers
  set getProfilesHandler(GetProfilesHandler? h) => _getProfilesHandler = h;
  set saveProfileHandler(SaveProfileHandler? h) => _saveProfileHandler = h;
  set deleteProfileHandler(DeleteProfileHandler? h) => _deleteProfileHandler = h;
  set loadProfileHandler(LoadProfileHandler? h) => _loadProfileHandler = h;
  set getActiveProfileHandler(GetActiveProfileHandler? h) => _getActiveProfileHandler = h;

  /// Start the web server
  Future<void> start() async {
    if (_isRunning) {
      print('Web server is already running');
      return;
    }

    // Try port range to find available port
    for (int p = port; p < port + 10; p++) {
      try {
        // Try to bind with reuseAddress to handle TIME_WAIT states
        _server = await HttpServer.bind(InternetAddress.anyIPv4, p, shared: true);
        _isRunning = true;
        _actualPort = p;

        print('Nightshade web server started on port $p');
        print('Access at: http://localhost:$p');

        _server!.listen(_handleRequest);
        return; // Success!
      } catch (e) {
        print('Failed to bind port $p: $e');
        if (p == port + 9) {
          print('Failed to start web server after 10 attempts');
          _isRunning = false;
          rethrow;
        }
      }
    }
  }

  /// Stop the web server
  Future<void> stop() async {
    if (!_isRunning) return;

    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    print('Web server stopped');
  }

  void _handleRequest(HttpRequest request) {
    // CORS headers for cross-origin requests
    final response = request.response;
    response.headers.add('Access-Control-Allow-Origin', '*');
    response.headers.add('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.ok;
      response.close();
      return;
    }

    // Handle WebSocket upgrade (support both /api/ws and /events for NetworkBackend compatibility)
    if ((request.uri.path == '/api/ws' || request.uri.path == '/events') &&
        request.headers.value('upgrade')?.toLowerCase() == 'websocket') {
      _handleWebSocketUpgrade(request);
      return;
    }

    // Handle API endpoints
    if (request.uri.path.startsWith('/api/')) {
      _handleApiRequest(request);
      return;
    }

    // In API-only mode, serve info message for root path
    if (_apiOnlyMode && (request.uri.path == '/' || request.uri.path.isEmpty)) {
      _serveApiInfo(request);
      return;
    }

    // Serve static files (Flutter web build) if available
    if (!_apiOnlyMode) {
      _serveStaticFile(request);
    } else {
      response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'error': 'Not found',
          'message': 'This server is running in API-only mode. Use /api/ endpoints.',
        }));
      response.close();
    }
  }

  void _handleApiRequest(HttpRequest request) async {
    final response = request.response;
    final apiPath = request.uri.path;
    final method = request.method;

    try {
      // GET /api/info - Server information and capabilities
      if (apiPath == '/api/info' && method == 'GET') {
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'running',
            'version': '2.0.0',
            'apiOnlyMode': _apiOnlyMode,
            'webUIAvailable': !_apiOnlyMode,
            'timestamp': DateTime.now().toIso8601String(),
            'endpoints': [
              'GET /api/info',
              'GET /api/status',
              'GET /api/devices',
              'POST /api/devices/connect',
              'POST /api/devices/disconnect',
              'GET /api/devices/connected',
              'POST /api/phd2/connect',
              'POST /api/phd2/disconnect',
              'GET /api/sequences/status',
              'POST /api/sequences/start',
              'POST /api/sequences/stop',
              'GET /api/images/recent',
            ],
          }));
        response.close();
        return;
      }

      // GET /api/status - Server status
      if (apiPath == '/api/status' && method == 'GET') {
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'running',
            'version': '2.0.0',
            'timestamp': DateTime.now().toIso8601String(),
          }));
        response.close();
        return;
      }

      // GET /api/devices - List connected devices
      if (apiPath == '/api/devices' && method == 'GET') {
        print('[WebServer] GET /api/devices request received');
        print('[WebServer] _devicesHandler is: ${_devicesHandler != null ? "REGISTERED" : "NULL"}');
        
        if (_devicesHandler != null) {
          try {
            print('[WebServer] Calling devicesHandler...');
            final result = await _devicesHandler!();
            print('[WebServer] Handler returned ${result['devices']?.length ?? 0} devices');
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            print('[WebServer] Response sent successfully');
            return;
          } catch (e) {
            print('[WebServer] Handler threw exception: $e');
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to get devices',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        // Fallback with empty device list structure
        print('[WebServer] No handler registered, returning empty fallback');
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'devices': <Map<String, dynamic>>[],
            'connected': {
              'camera': null,
              'mount': null,
              'focuser': null,
              'filterWheel': null,
              'rotator': null,
            },
            'available': <Map<String, dynamic>>[],
          }));
        response.close();
        return;
      }

      // POST /api/devices/connect - Connect to a device
      if (apiPath == '/api/devices/connect' && method == 'POST') {
        if (_deviceConnectHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final deviceType = json['deviceType'] as String;
            final deviceId = json['deviceId'] as String;
            
            await _deviceConnectHandler!(deviceType, deviceId);
            
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'connected', 'deviceId': deviceId}));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to connect device',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        response
          ..statusCode = HttpStatus.notImplemented
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Device connection handler not registered'}));
        response.close();
        return;
      }

      // POST /api/devices/disconnect - Disconnect from a device
      if (apiPath == '/api/devices/disconnect' && method == 'POST') {
        if (_deviceDisconnectHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final deviceType = json['deviceType'] as String;
            final deviceId = json['deviceId'] as String;
            
            await _deviceDisconnectHandler!(deviceType, deviceId);
            
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'disconnected', 'deviceId': deviceId}));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to disconnect device',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        response
          ..statusCode = HttpStatus.notImplemented
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Device disconnection handler not registered'}));
        response.close();
        return;
      }

      // GET /api/devices/connected - Get list of connected devices
      if (apiPath == '/api/devices/connected' && method == 'GET') {
        if (_connectedDevicesHandler != null) {
          try {
            final devices = await _connectedDevicesHandler!();
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'devices': devices}));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to get connected devices',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'devices': []}));
        response.close();
        return;
      }

      // POST /api/phd2/connect - Connect to PHD2
      if (apiPath == '/api/phd2/connect' && method == 'POST') {
        if (_phd2ConnectHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
            final host = json['host'] as String?;
            final port = json['port'] as int?;
            
            await _phd2ConnectHandler!(host: host, port: port);
            
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'connected'}));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to connect to PHD2',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        response
          ..statusCode = HttpStatus.notImplemented
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'PHD2 connection handler not registered'}));
        response.close();
        return;
      }

      // POST /api/phd2/disconnect - Disconnect from PHD2
      if (apiPath == '/api/phd2/disconnect' && method == 'POST') {
        if (_phd2DisconnectHandler != null) {
          try {
            await _phd2DisconnectHandler!();
            
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'disconnected'}));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to disconnect from PHD2',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        response
          ..statusCode = HttpStatus.notImplemented
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'PHD2 disconnection handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Camera Control Endpoints
      // =====================================================================

      // POST /api/camera/expose - Start camera exposure
      if (apiPath == '/api/camera/expose' && method == 'POST') {
        if (_cameraExposeHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _cameraExposeHandler!(json);
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'exposure_started'}));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to start exposure', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera expose handler not registered'}));
        response.close();
        return;
      }

      // POST /api/camera/abort - Abort camera exposure
      if (apiPath == '/api/camera/abort' && method == 'POST') {
        if (_cameraAbortHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _cameraAbortHandler!(json['deviceId'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'aborted'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to abort exposure', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera abort handler not registered'}));
        response.close();
        return;
      }

      // GET /api/camera/last-image - Get last captured image
      if (apiPath.startsWith('/api/camera/last-image') && method == 'GET') {
        if (_cameraGetLastImageHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _cameraGetLastImageHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'image': result}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get last image', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera get last image handler not registered'}));
        response.close();
        return;
      }

      // POST /api/camera/cooling - Set camera cooling
      if (apiPath == '/api/camera/cooling' && method == 'POST') {
        if (_cameraSetCoolingHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _cameraSetCoolingHandler!(
              json['deviceId'] as String,
              json['enabled'] as bool,
              (json['targetTemp'] as num?)?.toDouble(),
            );
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set cooling', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera cooling handler not registered'}));
        response.close();
        return;
      }

      // POST /api/camera/gain - Set camera gain
      if (apiPath == '/api/camera/gain' && method == 'POST') {
        if (_cameraSetGainHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _cameraSetGainHandler!(json['deviceId'] as String, json['gain'] as int);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set gain', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera gain handler not registered'}));
        response.close();
        return;
      }

      // POST /api/camera/offset - Set camera offset
      if (apiPath == '/api/camera/offset' && method == 'POST') {
        if (_cameraSetOffsetHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _cameraSetOffsetHandler!(json['deviceId'] as String, json['offset'] as int);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set offset', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera offset handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Mount Control Endpoints
      // =====================================================================

      // POST /api/mount/slew - Slew mount to coordinates
      if (apiPath == '/api/mount/slew' && method == 'POST') {
        if (_mountSlewHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountSlewHandler!(
              json['deviceId'] as String,
              (json['ra'] as num).toDouble(),
              (json['dec'] as num).toDouble(),
            );
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'slewing'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to slew mount', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount slew handler not registered'}));
        response.close();
        return;
      }

      // POST /api/mount/sync - Sync mount coordinates
      if (apiPath == '/api/mount/sync' && method == 'POST') {
        if (_mountSyncHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountSyncHandler!(
              json['deviceId'] as String,
              (json['ra'] as num).toDouble(),
              (json['dec'] as num).toDouble(),
            );
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'synced'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to sync mount', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount sync handler not registered'}));
        response.close();
        return;
      }

      // POST /api/mount/park - Park mount
      if (apiPath == '/api/mount/park' && method == 'POST') {
        if (_mountParkHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountParkHandler!(json['deviceId'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'parking'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to park mount', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount park handler not registered'}));
        response.close();
        return;
      }

      // POST /api/mount/unpark - Unpark mount
      if (apiPath == '/api/mount/unpark' && method == 'POST') {
        if (_mountUnparkHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountUnparkHandler!(json['deviceId'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'unparked'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to unpark mount', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount unpark handler not registered'}));
        response.close();
        return;
      }

      // POST /api/mount/tracking - Set mount tracking
      if (apiPath == '/api/mount/tracking' && method == 'POST') {
        if (_mountSetTrackingHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountSetTrackingHandler!(json['deviceId'] as String, json['enabled'] as bool);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set tracking', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount tracking handler not registered'}));
        response.close();
        return;
      }

      // POST /api/mount/pulse-guide - Pulse guide mount
      if (apiPath == '/api/mount/pulse-guide' && method == 'POST') {
        if (_mountPulseGuideHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountPulseGuideHandler!(
              json['deviceId'] as String,
              json['direction'] as String,
              json['durationMs'] as int,
            );
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to pulse guide', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount pulse guide handler not registered'}));
        response.close();
        return;
      }

      // POST /api/mount/abort - Abort mount slew
      if (apiPath == '/api/mount/abort' && method == 'POST') {
        if (_mountAbortHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _mountAbortHandler!(json['deviceId'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'aborted'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to abort mount', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount abort handler not registered'}));
        response.close();
        return;
      }

      // GET /api/mount/status - Get mount status
      if (apiPath.startsWith('/api/mount/status') && method == 'GET') {
        if (_mountGetStatusHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _mountGetStatusHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get mount status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount status handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Focuser Control Endpoints
      // =====================================================================

      // POST /api/focuser/move-to - Move focuser to position
      if (apiPath == '/api/focuser/move-to' && method == 'POST') {
        if (_focuserMoveToHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _focuserMoveToHandler!(json['deviceId'] as String, json['position'] as int);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'moving'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to move focuser', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Focuser move handler not registered'}));
        response.close();
        return;
      }

      // POST /api/focuser/move-relative - Move focuser relative
      if (apiPath == '/api/focuser/move-relative' && method == 'POST') {
        if (_focuserMoveRelativeHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _focuserMoveRelativeHandler!(json['deviceId'] as String, json['delta'] as int);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'moving'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to move focuser', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Focuser move relative handler not registered'}));
        response.close();
        return;
      }

      // POST /api/focuser/halt - Halt focuser
      if (apiPath == '/api/focuser/halt' && method == 'POST') {
        if (_focuserHaltHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _focuserHaltHandler!(json['deviceId'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'halted'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to halt focuser', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Focuser halt handler not registered'}));
        response.close();
        return;
      }

      // POST /api/focuser/autofocus/start - Start autofocus
      if (apiPath == '/api/focuser/autofocus/start' && method == 'POST') {
        if (_autofocusStartHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final result = await _autofocusStartHandler!(json);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to start autofocus', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Autofocus start handler not registered'}));
        response.close();
        return;
      }

      // POST /api/focuser/autofocus/cancel - Cancel autofocus
      if (apiPath == '/api/focuser/autofocus/cancel' && method == 'POST') {
        if (_autofocusCancelHandler != null) {
          try {
            await _autofocusCancelHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'cancelled'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to cancel autofocus', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Autofocus cancel handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Filter Wheel Control Endpoints
      // =====================================================================

      // POST /api/filter-wheel/position - Set filter wheel position
      if (apiPath == '/api/filter-wheel/position' && method == 'POST') {
        if (_filterWheelSetPositionHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _filterWheelSetPositionHandler!(json['deviceId'] as String, json['position'] as int);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'moving'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set filter position', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Filter wheel position handler not registered'}));
        response.close();
        return;
      }

      // GET /api/filter-wheel/names - Get filter names
      if (apiPath.startsWith('/api/filter-wheel/names') && method == 'GET') {
        if (_filterWheelGetNamesHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final names = await _filterWheelGetNamesHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'names': names}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get filter names', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Filter wheel names handler not registered'}));
        response.close();
        return;
      }

      // POST /api/filter-wheel/set-by-name - Set filter by name
      if (apiPath == '/api/filter-wheel/set-by-name' && method == 'POST') {
        if (_filterWheelSetByNameHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _filterWheelSetByNameHandler!(json['deviceId'] as String, json['name'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'moving'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set filter', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Filter wheel set by name handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Rotator Control Endpoints
      // =====================================================================

      // POST /api/rotator/move-to - Move rotator to angle
      if (apiPath == '/api/rotator/move-to' && method == 'POST') {
        if (_rotatorMoveToHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _rotatorMoveToHandler!(json['deviceId'] as String, (json['angle'] as num).toDouble());
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'moving'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to move rotator', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Rotator move handler not registered'}));
        response.close();
        return;
      }

      // POST /api/rotator/move-relative - Move rotator relative
      if (apiPath == '/api/rotator/move-relative' && method == 'POST') {
        if (_rotatorMoveRelativeHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _rotatorMoveRelativeHandler!(json['deviceId'] as String, (json['delta'] as num).toDouble());
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'moving'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to move rotator', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Rotator move relative handler not registered'}));
        response.close();
        return;
      }

      // GET /api/rotator/status - Get rotator status
      if (apiPath.startsWith('/api/rotator/status') && method == 'GET') {
        if (_rotatorGetStatusHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _rotatorGetStatusHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get rotator status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Rotator status handler not registered'}));
        response.close();
        return;
      }

      // POST /api/rotator/halt - Halt rotator
      if (apiPath == '/api/rotator/halt' && method == 'POST') {
        if (_rotatorHaltHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _rotatorHaltHandler!(json['deviceId'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'halted'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to halt rotator', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Rotator halt handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Equipment Status Endpoints
      // =====================================================================

      // GET /api/equipment/camera/status
      if (apiPath.startsWith('/api/equipment/camera/status') && method == 'GET') {
        if (_cameraStatusHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _cameraStatusHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get camera status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Camera status handler not registered'}));
        response.close();
        return;
      }

      // GET /api/equipment/mount/status
      if (apiPath.startsWith('/api/equipment/mount/status') && method == 'GET') {
        if (_mountStatusHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _mountStatusHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get mount status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Mount status handler not registered'}));
        response.close();
        return;
      }

      // GET /api/equipment/focuser/status
      if (apiPath.startsWith('/api/equipment/focuser/status') && method == 'GET') {
        if (_focuserStatusHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _focuserStatusHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get focuser status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Focuser status handler not registered'}));
        response.close();
        return;
      }

      // GET /api/equipment/filter-wheel/status
      if (apiPath.startsWith('/api/equipment/filter-wheel/status') && method == 'GET') {
        if (_filterWheelStatusHandler != null) {
          try {
            final deviceId = request.uri.queryParameters['deviceId'] ?? '';
            final result = await _filterWheelStatusHandler!(deviceId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get filter wheel status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Filter wheel status handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // PHD2 Extended Endpoints
      // =====================================================================

      // GET /api/phd2/status - Get PHD2 status
      if (apiPath == '/api/phd2/status' && method == 'GET') {
        if (_phd2GetStatusHandler != null) {
          try {
            final result = await _phd2GetStatusHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get PHD2 status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'PHD2 status handler not registered'}));
        response.close();
        return;
      }

      // POST /api/phd2/start-guiding - Start PHD2 guiding
      if (apiPath == '/api/phd2/start-guiding' && method == 'POST') {
        if (_phd2StartGuidingHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
            await _phd2StartGuidingHandler!(json);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'guiding'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to start guiding', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'PHD2 start guiding handler not registered'}));
        response.close();
        return;
      }

      // POST /api/phd2/stop-guiding - Stop PHD2 guiding
      if (apiPath == '/api/phd2/stop-guiding' && method == 'POST') {
        if (_phd2StopGuidingHandler != null) {
          try {
            await _phd2StopGuidingHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'stopped'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to stop guiding', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'PHD2 stop guiding handler not registered'}));
        response.close();
        return;
      }

      // POST /api/phd2/dither - Dither PHD2
      if (apiPath == '/api/phd2/dither' && method == 'POST') {
        if (_phd2DitherHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
            await _phd2DitherHandler!(json);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'dithering'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to dither', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'PHD2 dither handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Settings Endpoints
      // =====================================================================

      // GET /api/settings - Get settings
      if (apiPath == '/api/settings' && method == 'GET') {
        if (_getSettingsHandler != null) {
          try {
            final result = await _getSettingsHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'settings': result}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get settings', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Get settings handler not registered'}));
        response.close();
        return;
      }

      // POST /api/settings - Update settings
      if (apiPath == '/api/settings' && method == 'POST') {
        if (_updateSettingsHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _updateSettingsHandler!(json['settings'] as Map<String, dynamic>);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'updated'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to update settings', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Update settings handler not registered'}));
        response.close();
        return;
      }

      // GET /api/settings/location - Get location
      if (apiPath == '/api/settings/location' && method == 'GET') {
        if (_getLocationHandler != null) {
          try {
            final result = await _getLocationHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'location': result}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get location', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Get location handler not registered'}));
        response.close();
        return;
      }

      // POST /api/settings/location - Set location
      if (apiPath == '/api/settings/location' && method == 'POST') {
        if (_setLocationHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _setLocationHandler!(json['location'] as Map<String, dynamic>?);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'updated'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set location', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Set location handler not registered'}));
        response.close();
        return;
      }

      // GET /api/location - Alias for settings/location (for NetworkBackend compatibility)
      if (apiPath == '/api/location' && method == 'GET') {
        if (_getLocationHandler != null) {
          try {
            final result = await _getLocationHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result ?? {'latitude': 0.0, 'longitude': 0.0, 'elevation': 0.0}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get location', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
          ..write(jsonEncode({'latitude': 0.0, 'longitude': 0.0, 'elevation': 0.0}));
        response.close();
        return;
      }

      // =====================================================================
      // Profile Endpoints
      // =====================================================================

      // GET /api/profiles - List profiles
      if (apiPath == '/api/profiles' && method == 'GET') {
        if (_getProfilesHandler != null) {
          try {
            final profiles = await _getProfilesHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'profiles': profiles}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get profiles', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
          ..write(jsonEncode({'profiles': []}));
        response.close();
        return;
      }

      // POST /api/profiles - Save profile
      if (apiPath == '/api/profiles' && method == 'POST') {
        if (_saveProfileHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _saveProfileHandler!(json['profile'] as Map<String, dynamic>);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'saved'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to save profile', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Save profile handler not registered'}));
        response.close();
        return;
      }

      // DELETE /api/profiles/{id} - Delete profile
      if (apiPath.startsWith('/api/profiles/') && !apiPath.contains('/load') && !apiPath.contains('/active') && method == 'DELETE') {
        if (_deleteProfileHandler != null) {
          try {
            final profileId = apiPath.split('/').last;
            await _deleteProfileHandler!(profileId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'deleted'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to delete profile', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Delete profile handler not registered'}));
        response.close();
        return;
      }

      // POST /api/profiles/{id}/load - Load profile
      if (apiPath.contains('/load') && method == 'POST') {
        if (_loadProfileHandler != null) {
          try {
            final parts = apiPath.split('/');
            final profileId = parts[parts.length - 2]; // Get ID before /load
            await _loadProfileHandler!(profileId);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'loaded'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to load profile', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Load profile handler not registered'}));
        response.close();
        return;
      }

      // GET /api/profiles/active - Get active profile
      if (apiPath == '/api/profiles/active' && method == 'GET') {
        if (_getActiveProfileHandler != null) {
          try {
            final profile = await _getActiveProfileHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'profile': profile}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get active profile', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
          ..write(jsonEncode({'profile': null}));
        response.close();
        return;
      }

      // =====================================================================
      // Sequencer Extended Endpoints
      // =====================================================================

      // POST /api/sequencer/start - Start sequencer (alias for sequences/start)
      if (apiPath == '/api/sequencer/start' && method == 'POST') {
        if (_sequenceStartHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final result = await _sequenceStartHandler!(body.isEmpty ? null : body);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to start sequencer', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Sequencer start handler not registered'}));
        response.close();
        return;
      }

      // POST /api/sequencer/stop - Stop sequencer (alias for sequences/stop)
      if (apiPath == '/api/sequencer/stop' && method == 'POST') {
        if (_sequenceStopHandler != null) {
          try {
            final result = await _sequenceStopHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to stop sequencer', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Sequencer stop handler not registered'}));
        response.close();
        return;
      }

      // POST /api/sequencer/pause - Pause sequencer
      if (apiPath == '/api/sequencer/pause' && method == 'POST') {
        if (_sequencerPauseHandler != null) {
          try {
            await _sequencerPauseHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'paused'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to pause sequencer', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Sequencer pause handler not registered'}));
        response.close();
        return;
      }

      // POST /api/sequencer/resume - Resume sequencer
      if (apiPath == '/api/sequencer/resume' && method == 'POST') {
        if (_sequencerResumeHandler != null) {
          try {
            await _sequencerResumeHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'resumed'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to resume sequencer', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Sequencer resume handler not registered'}));
        response.close();
        return;
      }

      // POST /api/sequencer/load - Load sequence JSON
      if (apiPath == '/api/sequencer/load' && method == 'POST') {
        if (_sequencerLoadHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _sequencerLoadHandler!(json['json'] as String);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'loaded'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to load sequence', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Sequencer load handler not registered'}));
        response.close();
        return;
      }

      // POST /api/sequencer/simulation - Set simulation mode
      if (apiPath == '/api/sequencer/simulation' && method == 'POST') {
        if (_sequencerSetSimulationHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _sequencerSetSimulationHandler!(json['enabled'] as bool);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'ok'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to set simulation mode', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Sequencer simulation handler not registered'}));
        response.close();
        return;
      }

      // GET /api/sequencer/status - Get sequencer status (alias for sequences/status)
      if (apiPath == '/api/sequencer/status' && method == 'GET') {
        if (_sequenceStatusHandler != null) {
          try {
            final result = await _sequenceStatusHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to get sequencer status', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
          ..write(jsonEncode({'state': 'Idle', 'currentNodeId': null, 'progress': 0.0, 'message': null}));
        response.close();
        return;
      }

      // =====================================================================
      // Plate Solve Endpoint
      // =====================================================================

      // POST /api/plate-solve - Plate solve image
      if (apiPath == '/api/plate-solve' && method == 'POST') {
        if (_plateSolveHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            final result = await _plateSolveHandler!(json);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to plate solve', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Plate solve handler not registered'}));
        response.close();
        return;
      }

      // =====================================================================
      // Polar Alignment Endpoints
      // =====================================================================

      // POST /api/polar-alignment/start - Start polar alignment
      if (apiPath == '/api/polar-alignment/start' && method == 'POST') {
        if (_polarAlignmentStartHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final json = jsonDecode(body) as Map<String, dynamic>;
            await _polarAlignmentStartHandler!(json);
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'started'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to start polar alignment', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Polar alignment start handler not registered'}));
        response.close();
        return;
      }

      // POST /api/polar-alignment/stop - Stop polar alignment
      if (apiPath == '/api/polar-alignment/stop' && method == 'POST') {
        if (_polarAlignmentStopHandler != null) {
          try {
            await _polarAlignmentStopHandler!();
            response..statusCode = HttpStatus.ok..headers.contentType = ContentType.json
              ..write(jsonEncode({'status': 'stopped'}));
            response.close();
            return;
          } catch (e) {
            response..statusCode = HttpStatus.internalServerError..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': 'Failed to stop polar alignment', 'message': e.toString()}));
            response.close();
            return;
          }
        }
        response..statusCode = HttpStatus.notImplemented..headers.contentType = ContentType.json
          ..write(jsonEncode({'error': 'Polar alignment stop handler not registered'}));
        response.close();
        return;
      }

      // GET /api/sequences/status - Get sequence status
      if (apiPath == '/api/sequences/status' && method == 'GET') {
        if (_sequenceStatusHandler != null) {
          try {
            final result = await _sequenceStatusHandler!();
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to get sequence status',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        // Fallback if handler not set
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'state': 'idle',
            'currentNodeId': null,
            'currentNodeName': null,
            'totalExposures': 0,
            'completedExposures': 0,
            'totalIntegrationSecs': 0.0,
            'elapsedSecs': 0.0,
            'estimatedRemainingSecs': null,
            'currentTarget': null,
            'currentFilter': null,
            'message': null,
          }));
        response.close();
        return;
      }

      // POST /api/sequences/start - Start a sequence
      if (apiPath == '/api/sequences/start' && method == 'POST') {
        if (_sequenceStartHandler != null) {
          try {
            final body = await utf8.decoder.bind(request).join();
            final result = await _sequenceStartHandler!(body.isEmpty ? null : body);
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to start sequence',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        // Fallback if handler not set
        final body = await utf8.decoder.bind(request).join();
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'accepted',
            'message': 'Sequence start not yet implemented',
            'body': body.isEmpty ? null : body,
          }));
        response.close();
        return;
      }

      // POST /api/sequences/stop - Stop current sequence
      if (apiPath == '/api/sequences/stop' && method == 'POST') {
        if (_sequenceStopHandler != null) {
          try {
            final result = await _sequenceStopHandler!();
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(result));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to stop sequence',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        // Fallback if handler not set
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'accepted',
            'message': 'Sequence stop not yet implemented',
          }));
        response.close();
        return;
      }

      // GET /api/images/recent - List recent images
      if (apiPath == '/api/images/recent' && method == 'GET') {
        if (_imagesHandler != null) {
          try {
            // Parse limit query parameter
            final limitParam = request.uri.queryParameters['limit'];
            final limit = limitParam != null ? int.tryParse(limitParam) : null;
            
            final images = await _imagesHandler!(limit: limit);
            response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'images': images,
                'count': images.length,
              }));
            response.close();
            return;
          } catch (e) {
            response
              ..statusCode = HttpStatus.internalServerError
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({
                'error': 'Failed to get images',
                'message': e.toString(),
              }));
            response.close();
            return;
          }
        }
        // Fallback if handler not set
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'images': [],
            'message': 'Image listing not yet implemented',
          }));
        response.close();
        return;
      }

      // Not found
      response
        ..statusCode = HttpStatus.notFound
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'error': 'Not found',
          'path': apiPath,
          'method': method,
        }));
      response.close();
    } catch (e) {
      response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'error': 'Internal server error',
          'message': e.toString(),
        }));
      response.close();
    }
  }

  void _serveApiInfo(HttpRequest request) {
    final response = request.response;
    response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write('''
<!DOCTYPE html>
<html>
<head>
  <title>Nightshade API Server</title>
  <style>
    body { font-family: sans-serif; padding: 20px; max-width: 800px; margin: 0 auto; }
    h1 { color: #333; }
    .endpoint { background: #f5f5f5; padding: 10px; margin: 10px 0; border-radius: 4px; }
    .method { display: inline-block; padding: 2px 8px; border-radius: 3px; font-weight: bold; }
    .get { background: #4CAF50; color: white; }
    .post { background: #2196F3; color: white; }
  </style>
</head>
<body>
  <h1>Nightshade API Server</h1>
  <p>This server is running in <strong>API-only mode</strong>. Use the following endpoints:</p>
  
  <div class="endpoint">
    <span class="method get">GET</span> <code>/api/info</code> - Server information and capabilities
  </div>
  
  <div class="endpoint">
    <span class="method get">GET</span> <code>/api/status</code> - Server status
  </div>
  
  <div class="endpoint">
    <span class="method get">GET</span> <code>/api/devices</code> - List connected devices
  </div>
  
  <div class="endpoint">
    <span class="method get">GET</span> <code>/api/sequences/status</code> - Get sequence status
  </div>
  
  <div class="endpoint">
    <span class="method post">POST</span> <code>/api/sequences/start</code> - Start a sequence
  </div>
  
  <div class="endpoint">
    <span class="method post">POST</span> <code>/api/sequences/stop</code> - Stop current sequence
  </div>
  
  <div class="endpoint">
    <span class="method get">GET</span> <code>/api/images/recent</code> - List recent images
  </div>
</body>
</html>
''');
    response.close();
  }

  void _serveStaticFile(HttpRequest request) {
    final response = request.response;
    var requestPath = request.uri.path;

    if (webRoot == null) {
      response
        ..statusCode = HttpStatus.notFound
        ..write('Web root not configured');
      response.close();
      return;
    }

    // Default to index.html
    if (requestPath == '/' || requestPath.isEmpty) {
      requestPath = '/index.html';
    }

    // Remove leading slash for file system
    final filePath = requestPath.startsWith('/') ? requestPath.substring(1) : requestPath;
    final file = File(path.join(webRoot!, filePath));

    if (file.existsSync()) {
      final ext = filePath.split('.').last.toLowerCase();
      final contentType = _getContentType(ext);

      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = contentType
        ..add(file.readAsBytesSync());
    } else {
      // SPA fallback - serve index.html for all routes
      final indexFile = File(path.join(webRoot!, 'index.html'));
      if (indexFile.existsSync()) {
        response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..add(indexFile.readAsBytesSync());
      } else {
        response
          ..statusCode = HttpStatus.notFound
          ..write('File not found');
      }
    }

    response.close();
  }

  ContentType _getContentType(String extension) {
    switch (extension) {
      case 'html':
        return ContentType.html;
      case 'js':
        return ContentType('application', 'javascript');
      case 'css':
        return ContentType('text', 'css');
      case 'json':
        return ContentType.json;
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'svg':
        return ContentType('image', 'svg+xml');
      default:
        return ContentType.binary;
    }
  }

  // WebSocket support for real-time updates
  final Set<WebSocket> _webSocketClients = {};

  void _handleWebSocketUpgrade(HttpRequest request) {
    WebSocketTransformer.upgrade(request).then((WebSocket webSocket) {
      _webSocketClients.add(webSocket);
      print('WebSocket client connected (${_webSocketClients.length} total)');

      webSocket.listen(
        (message) {
          // Handle incoming messages
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            final type = data['type'] as String?;
            
            if (type == 'ping') {
              webSocket.add(jsonEncode({'type': 'pong'}));
            }
          } catch (e) {
            // Ignore malformed messages
          }
        },
        onDone: () {
          _webSocketClients.remove(webSocket);
          print('WebSocket client disconnected (${_webSocketClients.length} total)');
        },
        onError: (error) {
          _webSocketClients.remove(webSocket);
          print('WebSocket error: $error');
        },
      );
    }).catchError((error) {
      print('WebSocket upgrade failed: $error');
    });
  }

  /// Broadcast a message to all connected WebSocket clients
  void broadcastMessage(Map<String, dynamic> message) {
    final json = jsonEncode(message);
    final clientsToRemove = <WebSocket>[];
    
    for (final client in _webSocketClients) {
      try {
        client.add(json);
      } catch (e) {
        clientsToRemove.add(client);
      }
    }
    
    for (final client in clientsToRemove) {
      _webSocketClients.remove(client);
    }
  }
}



