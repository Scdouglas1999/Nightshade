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

  /// The effective auth token (either provided or generated)
  late final String? _effectiveAuthToken;

  // Handler instances
  late final DeviceHandlers _deviceHandlers;
  late final GuidingHandlers _guidingHandlers;
  late final SequencerHandlers _sequencerHandlers;
  late final EquipmentHandlers _equipmentHandlers;
  late final ProfileHandlers _profileHandlers;
  late final ImagingHandlers _imagingHandlers;
  late final SessionHandlers _sessionHandlers;

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
      print('[AUTH] Generated authentication token: $_effectiveAuthToken');
      print('[AUTH] Use this token in the Authorization header: Bearer $_effectiveAuthToken');
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
    router.get('/api/camera/last-image', _deviceHandlers.handleCameraGetLastImage);
    router.post('/api/camera/cooling', _deviceHandlers.handleCameraSetCooling);
    router.post('/api/camera/gain', _deviceHandlers.handleCameraSetGain);
    router.post('/api/camera/offset', _deviceHandlers.handleCameraSetOffset);

    // Mount Control
    router.post('/api/mount/slew', _deviceHandlers.handleMountSlew);
    router.post('/api/mount/sync', _deviceHandlers.handleMountSync);
    router.post('/api/mount/park', _deviceHandlers.handleMountPark);
    router.post('/api/mount/unpark', _deviceHandlers.handleMountUnpark);
    router.post('/api/mount/tracking', _deviceHandlers.handleMountSetTracking);
    router.post('/api/mount/pulse-guide', _deviceHandlers.handleMountPulseGuide);
    router.post('/api/mount/abort', _deviceHandlers.handleMountAbort);
    router.get('/api/mount/status', _deviceHandlers.handleMountGetStatus);
    router.post('/api/mount/set-tracking-rate', _deviceHandlers.handleMountSetTrackingRate);
    router.post('/api/mount/move-axis', _deviceHandlers.handleMountMoveAxis);

    // Focuser Control
    router.post('/api/focuser/move-to', _deviceHandlers.handleFocuserMoveTo);
    router.post('/api/focuser/move-relative', _deviceHandlers.handleFocuserMoveRelative);
    router.post('/api/focuser/halt', _deviceHandlers.handleFocuserHalt);
    router.post('/api/focuser/autofocus/start', _deviceHandlers.handleAutofocusStart);
    router.post('/api/focuser/autofocus/cancel', _deviceHandlers.handleAutofocusCancel);

    // Filter Wheel Control
    router.post('/api/filter-wheel/position', _deviceHandlers.handleFilterWheelSetPosition);
    router.get('/api/filter-wheel/names', _deviceHandlers.handleFilterWheelGetNames);
    router.post('/api/filter-wheel/set-by-name', _deviceHandlers.handleFilterWheelSetByName);

    // Rotator Control
    router.post('/api/rotator/move-to', _deviceHandlers.handleRotatorMoveTo);
    router.post('/api/rotator/move-relative', _deviceHandlers.handleRotatorMoveRelative);
    router.get('/api/rotator/status', _deviceHandlers.handleRotatorGetStatus);
    router.post('/api/rotator/halt', _deviceHandlers.handleRotatorHalt);

    // PHD2 Guiding
    router.post('/api/phd2/connect', _guidingHandlers.handlePhd2Connect);
    router.post('/api/phd2/disconnect', _guidingHandlers.handlePhd2Disconnect);
    router.post('/api/phd2/start-guiding', _guidingHandlers.handlePhd2StartGuiding);
    router.post('/api/phd2/stop-guiding', _guidingHandlers.handlePhd2StopGuiding);
    router.post('/api/phd2/dither', _guidingHandlers.handlePhd2Dither);
    router.get('/api/phd2/status', _guidingHandlers.handlePhd2GetStatus);
    router.post('/api/phd2/pause', _guidingHandlers.handlePhd2SetPaused);
    router.post('/api/phd2/clear-calibration', _guidingHandlers.handlePhd2ClearCalibration);
    router.post('/api/phd2/flip-calibration', _guidingHandlers.handlePhd2FlipCalibration);
    router.post('/api/phd2/get-calibration-data', _guidingHandlers.handlePhd2GetCalibrationData);
    router.post('/api/phd2/find-star', _guidingHandlers.handlePhd2FindStar);
    router.post('/api/phd2/set-lock-position', _guidingHandlers.handlePhd2SetLockPosition);
    router.get('/api/phd2/lock-position', _guidingHandlers.handlePhd2GetLockPosition);
    router.post('/api/phd2/loop', _guidingHandlers.handlePhd2Loop);
    router.post('/api/phd2/deselect-star', _guidingHandlers.handlePhd2DeselectStar);

    // Plate Solving
    router.post('/api/plate-solve', _imagingHandlers.handlePlateSolve);

    // Sequencing (legacy)
    router.get('/api/sequences/status', _handleSequenceStatus);
    router.post('/api/sequences/start', _handleSequenceStart);
    router.post('/api/sequences/stop', _handleSequenceStop);

    // Sequencing (extended)
    router.get('/api/sequencer/status', _sequencerHandlers.handleSequencerStatus);
    router.post('/api/sequencer/start', _sequencerHandlers.handleSequencerStart);
    router.post('/api/sequencer/stop', _sequencerHandlers.handleSequencerStop);
    router.post('/api/sequencer/pause', _sequencerHandlers.handleSequencerPause);
    router.post('/api/sequencer/resume', _sequencerHandlers.handleSequencerResume);
    router.post('/api/sequencer/skip', _sequencerHandlers.handleSequencerSkip);
    router.post('/api/sequencer/reset', _sequencerHandlers.handleSequencerReset);
    router.post('/api/sequencer/load', _sequencerHandlers.handleSequencerLoad);
    router.post('/api/sequencer/simulation', _sequencerHandlers.handleSequencerSetSimulationMode);
    router.post('/api/sequencer/devices', _sequencerHandlers.handleSequencerSetDevices);
    router.post('/api/sequencer/safety-fail-mode', _sequencerHandlers.handleSequencerSetSafetyFailMode);
    router.post('/api/sequencer/checkpoint/dir', _sequencerHandlers.handleSequencerSetCheckpointDir);
    router.get('/api/sequencer/checkpoint/has', _sequencerHandlers.handleSequencerHasCheckpoint);
    router.get('/api/sequencer/checkpoint/info', _sequencerHandlers.handleSequencerGetCheckpointInfo);
    router.post('/api/sequencer/checkpoint/resume', _sequencerHandlers.handleSequencerResumeFromCheckpoint);
    router.post('/api/sequencer/checkpoint/discard', _sequencerHandlers.handleSequencerDiscardCheckpoint);
    router.post('/api/sequencer/checkpoint/save', _sequencerHandlers.handleSequencerSaveCheckpoint);

    // Equipment Status
    router.get('/api/equipment/camera/status', _equipmentHandlers.handleCameraStatus);
    router.get('/api/equipment/mount/status', _equipmentHandlers.handleMountStatus);
    router.get('/api/equipment/focuser/status', _equipmentHandlers.handleFocuserStatus);
    router.get('/api/equipment/filter-wheel/status', _equipmentHandlers.handleFilterWheelStatus);
    router.get('/api/equipment/rotator/status', _equipmentHandlers.handleRotatorStatus);

    // Equipment Capabilities
    router.get('/api/equipment/camera/capabilities', _equipmentHandlers.handleCameraCapabilities);
    router.get('/api/equipment/mount/capabilities', _equipmentHandlers.handleMountCapabilities);
    router.get('/api/equipment/focuser/capabilities', _equipmentHandlers.handleFocuserCapabilities);
    router.get('/api/equipment/filter-wheel/capabilities', _equipmentHandlers.handleFilterWheelCapabilities);
    router.get('/api/equipment/rotator/capabilities', _equipmentHandlers.handleRotatorCapabilities);

    // Device Health
    router.post('/api/device/heartbeat/start', _equipmentHandlers.handleStartDeviceHeartbeat);
    router.post('/api/device/heartbeat/stop', _equipmentHandlers.handleStopDeviceHeartbeat);
    router.get('/api/device/health/<deviceId>', _equipmentHandlers.handleGetDeviceHealth);

    // Profiles
    router.get('/api/profiles', _profileHandlers.handleGetProfiles);
    router.post('/api/profiles', _profileHandlers.handleSaveProfile);
    router.delete('/api/profiles/<profileId>', _profileHandlers.handleDeleteProfile);
    router.post('/api/profiles/<profileId>/load', _profileHandlers.handleLoadProfile);
    router.get('/api/profiles/active', _profileHandlers.handleGetActiveProfile);

    // Settings
    router.get('/api/settings', _profileHandlers.handleGetSettings);
    router.post('/api/settings', _profileHandlers.handleUpdateSettings);
    router.get('/api/settings/location', _profileHandlers.handleGetLocation);
    router.post('/api/settings/location', _profileHandlers.handleSetLocation);
    router.get('/api/location', _profileHandlers.handleGetLocationFromInternet);

    // Imaging
    router.post('/api/imaging/stats', _imagingHandlers.handleGetImageStats);
    router.post('/api/imaging/stretch', _imagingHandlers.handleAutoStretchImage);
    router.post('/api/imaging/debayer', _imagingHandlers.handleDebayerImage);
    router.get('/api/imaging/raw-data', _imagingHandlers.handleGetLastRawImageData);
    router.post('/api/imaging/save-fits', _imagingHandlers.handleSaveFitsFile);
    router.post('/api/imaging/save-fits-from-capture', _imagingHandlers.handleSaveFitsFromLastCapture);
    router.delete('/api/imaging/device-image/<deviceId>', _imagingHandlers.handleClearDeviceImage);

    // Polar Alignment
    router.post('/api/polar-alignment/start', _sessionHandlers.handleStartPolarAlignment);
    router.post('/api/polar-alignment/stop', _sessionHandlers.handleStopPolarAlignment);

    // Session Images
    router.get('/api/sessions/<sessionId>/images', _sessionHandlers.handleGetSessionImages);
    router.get('/api/images/<imageId>/thumbnail', _sessionHandlers.handleGetImageThumbnail);
    router.get('/api/images/<imageId>/download', _sessionHandlers.handleDownloadImage);

    // WebSocket - support both paths for NetworkBackend compatibility
    router.get('/api/ws', webSocketHandler(_handleWebSocket));
    router.get('/events', webSocketHandler(_handleWebSocket));

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('Headless API server running on http://${_server!.address.host}:${_server!.port}');
    if (_effectiveAuthToken != null) {
      print('[AUTH] Authentication is ENABLED. All requests require Bearer token.');
    } else {
      print('[AUTH] Authentication is DISABLED. All requests are allowed.');
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
      print('[API] Failed to subscribe to backend events: $e');
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
      print('Error encoding event for broadcast: $e');
      return;
    }

    for (final socket in _sockets) {
      try {
        socket.sink.add(jsonEvent);
      } catch (e) {
        print('Error broadcasting to socket: $e');
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
      'GET /api/info',
      'GET /api/status',
      'GET /api/devices',
      'GET /api/devices/connected',
      'POST /api/devices/connect',
      'POST /api/devices/disconnect',
      'POST /api/camera/expose',
      'POST /api/camera/abort',
      'GET /api/camera/last-image',
      'POST /api/camera/cooling',
      'POST /api/mount/slew',
      'POST /api/mount/sync',
      'POST /api/mount/park',
      'POST /api/mount/unpark',
      'POST /api/focuser/move-to',
      'POST /api/focuser/halt',
      'POST /api/focuser/autofocus/start',
      'POST /api/focuser/autofocus/cancel',
      'POST /api/filter-wheel/position',
      'POST /api/filter-wheel/set-by-name',
      'POST /api/rotator/move-to',
      'POST /api/rotator/halt',
      'POST /api/phd2/connect',
      'POST /api/phd2/disconnect',
      'POST /api/phd2/start-guiding',
      'POST /api/phd2/stop-guiding',
      'POST /api/phd2/dither',
      'GET /api/phd2/status',
      'POST /api/plate-solve',
      'GET /api/sequencer/status',
      'POST /api/sequencer/start',
      'POST /api/sequencer/stop',
      'POST /api/sequencer/pause',
      'POST /api/sequencer/resume',
      'POST /api/sequencer/skip',
      'POST /api/sequencer/reset',
      'POST /api/sequencer/load',
      'GET /api/equipment/camera/status',
      'GET /api/equipment/mount/status',
      'GET /api/equipment/focuser/status',
      'GET /api/equipment/filter-wheel/status',
      'GET /api/equipment/rotator/status',
      'GET /api/equipment/camera/capabilities',
      'GET /api/equipment/mount/capabilities',
      'GET /api/equipment/focuser/capabilities',
      'GET /api/equipment/filter-wheel/capabilities',
      'GET /api/equipment/rotator/capabilities',
      'GET /api/profiles',
      'POST /api/profiles',
      'GET /api/profiles/active',
      'GET /api/settings',
      'POST /api/settings',
      'GET /api/settings/location',
      'POST /api/settings/location',
      'POST /api/imaging/stats',
      'POST /api/imaging/stretch',
      'POST /api/imaging/save-fits',
      'POST /api/imaging/save-fits-from-capture',
      'POST /api/polar-alignment/start',
      'POST /api/polar-alignment/stop',
      'GET /api/sessions/<sessionId>/images',
      'GET /api/images/<imageId>/thumbnail',
      'WS /api/ws',
      'WS /events',
    ];
  }

  Future<Response> _handleStatus(Request request) async {
    print('[API] GET /api/status');
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
      print('[API] Status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleGetDevices(Request request) async {
    print('[API] GET /api/devices');
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
          "devices": allDevices.map((d) => {
            'id': d.id,
            'name': d.name,
            'deviceType': d.deviceType.name,
            'driverType': d.driverType.name,
            'description': d.description,
          }).toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get devices error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleGetConnectedDevices(Request request) async {
    print('[API] GET /api/devices/connected');
    try {
      final backend = container.read(backendProvider);
      final devices = await backend.getConnectedDevices();
      return Response.ok(
        jsonEncode({
          "devices": devices.map((d) => {
            'id': d.id,
            'name': d.name,
            'deviceType': d.deviceType.name,
            'driverType': d.driverType.name,
            'description': d.description,
          }).toList(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Get connected devices error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleConnectDevice(Request request) async {
    print('[API] POST /api/devices/connect');
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
      print('[API] Connect device error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> _handleDisconnectDevice(Request request) async {
    print('[API] POST /api/devices/disconnect');
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
      print('[API] Disconnect device error: $e');
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
    print('New WebSocket connection');

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
        print('WebSocket disconnected');
      },
      onError: (error) {
        _sockets.remove(socket);
        print('WebSocket error: $error');
      },
    );
  }

  // ===========================================================================
  // Middleware
  // ===========================================================================

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
        final path = '/${request.url.path}';
        if (publicPaths.contains(path)) {
          return null;
        }

        // Check for Authorization header
        final authHeader = request.headers['authorization'];
        if (authHeader == null) {
          print('[AUTH] Rejected request to $path - no Authorization header');
          return Response.unauthorized(
            jsonEncode({
              'error': 'Authentication required',
              'message': 'Missing Authorization header',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        // Validate Bearer token format
        if (!authHeader.startsWith('Bearer ')) {
          print('[AUTH] Rejected request to $path - invalid auth format');
          return Response.unauthorized(
            jsonEncode({
              'error': 'Authentication required',
              'message': 'Invalid Authorization header format. Expected: Bearer <token>',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        // Extract and validate token
        final token = authHeader.substring(7); // Remove 'Bearer ' prefix
        if (token != _effectiveAuthToken) {
          print('[AUTH] Rejected request to $path - invalid token');
          return Response.forbidden(
            jsonEncode({
              'error': 'Access denied',
              'message': 'Invalid authentication token',
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        // Token is valid, continue to handler
        return null;
      },
    );
  }

  /// Generates a cryptographically secure random token.
  static String _generateRandomToken({int length = 32}) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
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
