import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/models/backend/device_types.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart';

void main() {
  group('NetworkBackend WebSocket heartbeat', () {
    test('sends ping heartbeats and accepts pong replies', () async {
      final firstPing = Completer<void>();
      final server = await _startServer((socket) {
        socket.listen((message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'ping') {
            if (!firstPing.isCompleted) {
              firstPing.complete();
            }
            socket.add(jsonEncode({'type': 'pong'}));
          }
        });
      });

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 250),
      );

      try {
        await firstPing.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(backend.connectionState, BackendConnectionState.connected);
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });

    test('marks a silent socket disconnected so reconnect can start', () async {
      final server = await _startServer((socket) {
        socket.listen((_) {
          // Deliberately ignore heartbeat pings.
        });
      });

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 120),
      );

      try {
        await backend.connectionStateStream
            .firstWhere((state) => state == BackendConnectionState.connected)
            .timeout(const Duration(seconds: 2));
        await backend.connectionStateStream
            .firstWhere((state) => state == BackendConnectionState.disconnected)
            .timeout(const Duration(seconds: 2));
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });

    test('rejects incompatible servers before opening WebSocket', () async {
      for (final infoBody in const [
        <String, dynamic>{'version': '1.9.9'},
        <String, dynamic>{'version': '3.0.0'},
        <String, dynamic>{'version': 'not-a-version'},
        <String, dynamic>{},
      ]) {
        var websocketOpened = false;
        final server = await _startServer(
          (socket) {
            websocketOpened = true;
            socket.listen((_) {});
          },
          infoBody: infoBody,
        );

        final backend = NetworkBackend(
          serverHost: InternetAddress.loopbackIPv4.address,
          serverPort: server.port,
          webSocketPort: server.port,
          webSocketHeartbeatInterval: const Duration(milliseconds: 50),
          webSocketHeartbeatTimeout: const Duration(milliseconds: 120),
        );

        try {
          await backend.connectionStateStream
              .firstWhere(
                  (state) => state == BackendConnectionState.disconnected)
              .timeout(const Duration(seconds: 2));

          expect(backend.connectionState, BackendConnectionState.disconnected);
          expect(websocketOpened, isFalse);
        } finally {
          backend.dispose();
          await server.close(force: true);
        }
      }
    });

    test('discovers devices using headless deviceType field', () async {
      final server = await _startServer(
        (socket) {
          socket.listen((_) {});
        },
        devicesBody: {
          'devices': [
            {
              'id': 'camera-1',
              'name': 'Simulator Camera',
              'deviceType': 'camera',
              'driverType': 'simulator',
            },
            {
              'id': 'filter-1',
              'name': 'Simulator Filter Wheel',
              'deviceType': 'Filter Wheel',
              'driverType': 'simulator',
            },
            {
              'id': 'legacy-mount-1',
              'name': 'Legacy Mount',
              'type': 'mount',
              'driverType': 'simulator',
            },
          ],
        },
      );

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 120),
      );

      try {
        await backend.connectionStateStream
            .firstWhere((state) => state == BackendConnectionState.connected)
            .timeout(const Duration(seconds: 2));

        final cameras = await backend.discoverDevices(DeviceType.camera);
        final filterWheels =
            await backend.discoverDevices(DeviceType.filterWheel);
        final mounts = await backend.discoverDevices(DeviceType.mount);

        expect(cameras.map((device) => device.id), ['camera-1']);
        expect(filterWheels.map((device) => device.id), ['filter-1']);
        expect(mounts.map((device) => device.id), ['legacy-mount-1']);
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });

    test('routes headless event wrappers to event and polar alignment streams',
        () async {
      final server = await _startServer((socket) {
        Timer(const Duration(milliseconds: 50), () {
          socket.add(jsonEncode({
            'type': 'event',
            'timestamp': 1700000000000,
            'severity': 'warning',
            'category': 'polarAlignment',
            'eventType': 'PolarAlignmentProgress',
            'data': {
              'azimuthErrorArcmin': 3.2,
              'altitudeErrorArcmin': 1.4,
            },
          }));
        });
        socket.listen((message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'ping') {
            socket.add(jsonEncode({'type': 'pong'}));
          }
        });
      });

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 250),
      );
      final eventFuture = backend.eventStream
          .firstWhere((event) => event.eventType == 'PolarAlignmentProgress')
          .timeout(const Duration(seconds: 2));
      final polarFuture = backend.polarAlignmentEvents
          .firstWhere((event) => event['azimuthErrorArcmin'] == 3.2)
          .timeout(const Duration(seconds: 2));

      try {
        final event = await eventFuture;
        final polarEvent = await polarFuture;

        expect(event.category, EventCategory.polarAlignment);
        expect(event.severity, EventSeverity.warning);
        expect(event.data['altitudeErrorArcmin'], 1.4);
        expect(polarEvent['altitudeErrorArcmin'], 1.4);
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });
  });
}

Future<HttpServer> _startServer(
  void Function(WebSocket socket) onSocket, {
  Map<String, dynamic> infoBody = const {'version': '2.5.0'},
  Map<String, dynamic> devicesBody = const {'devices': []},
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

  server.listen((request) async {
    if (request.uri.path == '/api/info') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(infoBody));
      await request.response.close();
      return;
    }

    if (request.uri.path == '/api/devices') {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(devicesBody));
      await request.response.close();
      return;
    }

    if (request.uri.path == '/events') {
      final socket = await WebSocketTransformer.upgrade(request);
      onSocket(socket);
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await request.response.close();
  });

  return server;
}
