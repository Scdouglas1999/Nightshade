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

class HeadlessApiServer {
  final int port;
  final ProviderContainer container;
  HttpServer? _server;
  final List<WebSocketChannel> _sockets = [];

  HeadlessApiServer({
    required this.port,
    required this.container,
  });

  Future<void> start() async {
    final router = Router();

    // Server Info
    router.get('/api/info', _handleInfo);
    router.get('/api/status', _handleStatus);

    // Devices
    router.get('/api/devices', _handleGetDevices);
    router.get('/api/devices/connected', _handleGetConnectedDevices);
    router.post('/api/devices/connect', _handleConnectDevice);
    router.post('/api/devices/disconnect', _handleDisconnectDevice);

    // Sequencing
    router.get('/api/sequences/status', _handleSequenceStatus);
    router.post('/api/sequences/start', _handleSequenceStart);
    router.post('/api/sequences/stop', _handleSequenceStop);

    // WebSocket
    router.get('/api/ws', webSocketHandler(_handleWebSocket));

    // Middleware pipeline
    final handler = const Pipeline()
        .addMiddleware(_corsMiddleware())
        .addMiddleware(logRequests())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    print('Serving at http://${_server!.address.host}:${_server!.port}');
  }

  Future<void> stop() async {
    for (final socket in _sockets) {
      await socket.sink.close();
    }
    await _server?.close();
    _server = null;
  }

  void broadcastEvent(dynamic event) {
    if (_sockets.isEmpty) return;

    String jsonEvent;
    try {
      // Handle NightshadeEvent specifically
      if (event is NightshadeEvent) {
        jsonEvent = jsonEncode({
          'type': event.eventType,
          'category': event.category.toString().split('.').last,
          'data': event.data,
          'timestamp': event.timestamp,
        });
      } else {
        // Fallback for generic objects
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
  // Handlers
  // ===========================================================================

  Response _handleInfo(Request request) {
    print('[API] GET /api/info');
    return Response.ok(
      jsonEncode({
        "status": "running",
        "version": "2.0.0",
        "apiOnlyMode": true,
        "webUIAvailable": false,
        "timestamp": DateTime.now().toIso8601String(),
        "endpoints": [
          "GET /api/info",
          "GET /api/status",
          "GET /api/devices",
          "POST /api/devices/connect",
          "POST /api/devices/disconnect",
          "GET /api/devices/connected",
          "GET /api/sequences/status",
          "POST /api/sequences/start",
          "POST /api/sequences/stop",
        ]
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _handleStatus(Request request) {
    // Don't log status checks to avoid cluttering logs
    return Response.ok(
      jsonEncode({
        "status": "running",
        "version": "2.0.0",
        "timestamp": DateTime.now().toIso8601String()
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _handleGetDevices(Request request) async {
    print('[API] GET /api/devices');
    try {
      final backend = container.read(backendProvider);

      Future<List<DeviceInfo>> safeDiscover(DeviceType type) async {
        try {
          return await backend.discoverDevices(type);
        } catch (e) {
          print('[API] Error discovering $type: $e');
          return <DeviceInfo>[];
        }
      }

      // Collect all devices in parallel to avoid timeouts
      final results = await Future.wait([
        safeDiscover(DeviceType.camera),
        safeDiscover(DeviceType.mount),
        safeDiscover(DeviceType.focuser),
        safeDiscover(DeviceType.filterWheel),
        safeDiscover(DeviceType.guider),
      ]);

      final cameras = results[0];
      final mounts = results[1];
      final focusers = results[2];
      final wheels = results[3];
      final guiders = results[4];

      print(
          '[API] Found: ${cameras.length} cams, ${mounts.length} mounts, ${focusers.length} focusers, ${wheels.length} wheels, ${guiders.length} guiders');

      final allDevices =
          [...cameras, ...mounts, ...focusers, ...wheels, ...guiders]
              .map((d) => {
                    "id": d.id,
                    "name": d.name,
                    "deviceType": d.deviceType.name,
                    "driverType": d.driverType.name,
                    "description": d.description,
                    "driverVersion": d.driverVersion,
                  })
              .toList();

      // Get connected map
      Map<String, String?> connectedMap = {};
      try {
        final connectedList = await backend.getConnectedDevices();
        connectedMap = {
          "camera": connectedList
              .where((d) => d.deviceType == DeviceType.camera)
              .firstOrNull
              ?.id,
          "mount": connectedList
              .where((d) => d.deviceType == DeviceType.mount)
              .firstOrNull
              ?.id,
          "focuser": connectedList
              .where((d) => d.deviceType == DeviceType.focuser)
              .firstOrNull
              ?.id,
          "filterWheel": connectedList
              .where((d) => d.deviceType == DeviceType.filterWheel)
              .firstOrNull
              ?.id,
          "guider": connectedList
              .where((d) => d.deviceType == DeviceType.guider)
              .firstOrNull
              ?.id,
        };
      } catch (e) {
        print('[API] Error getting connected devices: $e');
        // Continue with empty connected map
      }

      return Response.ok(
        jsonEncode({
          "devices": allDevices,
          "connected": connectedMap,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e, stack) {
      print('[API] Error getting devices: $e\n$stack');
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleGetConnectedDevices(Request request) async {
    print('[API] GET /api/devices/connected');
    try {
      final backend = container.read(backendProvider);
      final connectedList = await backend.getConnectedDevices();

      final devices = connectedList
          .map((d) => {
                "id": d.id,
                "name": d.name,
                "deviceType": d.deviceType.name,
                "driverType": d.driverType.name,
              })
          .toList();

      return Response.ok(
        jsonEncode({"devices": devices}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Error getting connected devices: $e');
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleConnectDevice(Request request) async {
    print('[API] POST /api/devices/connect');
    try {
      final payload = jsonDecode(await request.readAsString());
      final typeStr = payload['deviceType'] as String?;
      final deviceId = payload['deviceId'] as String?;

      print('[API] Connecting to $typeStr device: $deviceId');

      if (typeStr == null || deviceId == null) {
        return Response.badRequest(body: 'Missing deviceType or deviceId');
      }

      final deviceType = _parseDeviceType(typeStr);
      if (deviceType == null) {
        return Response.badRequest(body: 'Invalid deviceType: $typeStr');
      }

      final backend = container.read(backendProvider);
      await backend.connectDevice(deviceType, deviceId);

      print('[API] Connected to $deviceId');
      return Response.ok(
        jsonEncode({"status": "connected", "deviceId": deviceId}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Connection error: $e');
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleDisconnectDevice(Request request) async {
    print('[API] POST /api/devices/disconnect');
    try {
      final payload = jsonDecode(await request.readAsString());
      final typeStr = payload['deviceType'] as String?;
      final deviceId = payload['deviceId'] as String?;

      print('[API] Disconnecting from $typeStr device: $deviceId');

      if (typeStr == null || deviceId == null) {
        return Response.badRequest(body: 'Missing deviceType or deviceId');
      }

      final deviceType = _parseDeviceType(typeStr);
      if (deviceType == null) {
        return Response.badRequest(body: 'Invalid deviceType: $typeStr');
      }

      final backend = container.read(backendProvider);
      await backend.disconnectDevice(deviceType, deviceId);

      print('[API] Disconnected from $deviceId');
      return Response.ok(
        jsonEncode({"status": "disconnected", "deviceId": deviceId}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Disconnect error: $e');
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleSequenceStatus(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final status = await backend.sequencerGetStatus();

      return Response.ok(
        jsonEncode({
          "state": status.state,
          "currentNodeId": status.currentNodeId,
          "currentNodeName": status.currentNodeName,
          "progress": status.progress,
          "message": status.message
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleSequenceStart(Request request) async {
    print('[API] POST /api/sequences/start');
    try {
      final backend = container.read(backendProvider);
      // Optional: Parse sequence data if provided, for now just start
      await backend.sequencerStart();
      return Response.ok(
        jsonEncode({"status": "started"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Sequence start error: $e');
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

  Future<Response> _handleSequenceStop(Request request) async {
    print('[API] POST /api/sequences/stop');
    try {
      final backend = container.read(backendProvider);
      await backend.sequencerStop();
      return Response.ok(
        jsonEncode({"status": "stopped"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Sequence stop error: $e');
      return Response.internalServerError(
          body: jsonEncode({"error": e.toString()}),
          headers: {'content-type': 'application/json'});
    }
  }

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

  DeviceType? _parseDeviceType(String type) {
    try {
      return DeviceType.values
          .firstWhere((e) => e.name.toLowerCase() == type.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  Middleware _corsMiddleware() {
    return createMiddleware(
      requestHandler: (request) {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers':
                'Origin, Content-Type, X-Auth-Token',
          });
        }
        return null;
      },
      responseHandler: (response) {
        return response.change(headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, X-Auth-Token',
        });
      },
    );
  }
}
