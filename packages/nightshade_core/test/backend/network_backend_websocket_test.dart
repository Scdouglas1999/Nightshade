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
        final server = await _startServer((socket) {
          websocketOpened = true;
          socket.listen((_) {});
        }, infoBody: infoBody);

        final backend = NetworkBackend(
          serverHost: InternetAddress.loopbackIPv4.address,
          serverPort: server.port,
          webSocketPort: server.port,
          webSocketHeartbeatInterval: const Duration(milliseconds: 50),
          webSocketHeartbeatTimeout: const Duration(milliseconds: 120),
        );

        try {
          // P2-13: incompatible-version is a terminal failure mode now,
          // surfaced as `error` rather than the legacy `disconnected`.
          // We wait for either so this test asserts the documented
          // behaviour (server rejected the upgrade) regardless of which
          // terminal state the backend picked.
          await backend.connectionStateStream
              .firstWhere(
                (state) =>
                    state == BackendConnectionState.error ||
                    state == BackendConnectionState.disconnected,
              )
              .timeout(const Duration(seconds: 2));

          expect(
            backend.connectionState,
            anyOf(
              BackendConnectionState.error,
              BackendConnectionState.disconnected,
            ),
          );
          expect(websocketOpened, isFalse);
        } finally {
          backend.dispose();
          await server.close(force: true);
        }
      }
    });

    test('prefers compatible apiVersion over a newer app version', () async {
      var websocketOpened = false;
      final server = await _startServer((socket) {
        websocketOpened = true;
        socket.listen((message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'ping') {
            socket.add(jsonEncode({'type': 'pong'}));
          }
        });
      }, infoBody: const {'version': '3.0.0', 'apiVersion': '2.6.0'});

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 250),
      );

      try {
        await backend.connectionStateStream
            .firstWhere((state) => state == BackendConnectionState.connected)
            .timeout(const Duration(seconds: 2));
        await _waitUntil(
          () => websocketOpened,
          timeout: const Duration(seconds: 2),
        );
        expect(websocketOpened, isTrue);
      } finally {
        backend.dispose();
        await server.close(force: true);
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
        final filterWheels = await backend.discoverDevices(
          DeviceType.filterWheel,
        );
        final mounts = await backend.discoverDevices(DeviceType.mount);

        expect(cameras.map((device) => device.id), ['camera-1']);
        expect(filterWheels.map((device) => device.id), ['filter-1']);
        expect(mounts.map((device) => device.id), ['legacy-mount-1']);
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });

    test('device-change events invalidate cached discovery results', () async {
      final server = await _startServer(
        (socket) {
          Timer(const Duration(milliseconds: 80), () {
            socket.add(
              jsonEncode({
                'type': 'event',
                'timestamp': 1700000000003,
                'severity': 'info',
                'category': 'equipment',
                'eventType': 'PropertyChanged',
                'data': {
                  'device_type': 'system',
                  'device_id': 'device-bus',
                  'property': 'device_change',
                  'value': 'arrival',
                },
              }),
            );
          });
          socket.listen((message) {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            if (data['type'] == 'ping') {
              socket.add(jsonEncode({'type': 'pong'}));
            }
          });
        },
        devicesBodies: const [
          {
            'devices': [
              {
                'id': 'camera-before',
                'name': 'Before',
                'deviceType': 'camera',
                'driverType': 'simulator',
              },
            ],
          },
          {
            'devices': [
              {
                'id': 'camera-after',
                'name': 'After',
                'deviceType': 'camera',
                'driverType': 'simulator',
              },
            ],
          },
        ],
      );

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 250),
      );
      final deviceChangeFuture = backend.eventStream
          .firstWhere(
            (event) =>
                event.eventType == 'PropertyChanged' &&
                event.data['property'] == 'device_change',
          )
          .timeout(const Duration(seconds: 2));

      try {
        await backend.connectionStateStream
            .firstWhere((state) => state == BackendConnectionState.connected)
            .timeout(const Duration(seconds: 2));

        final before = await backend.discoverDevices(DeviceType.camera);
        expect(before.map((device) => device.id), ['camera-before']);

        await deviceChangeFuture;

        final after = await backend.discoverDevices(DeviceType.camera);
        expect(after.map((device) => device.id), ['camera-after']);
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });

    test(
      'routes headless event wrappers to event and polar alignment streams',
      () async {
        final server = await _startServer((socket) {
          Timer(const Duration(milliseconds: 50), () {
            socket.add(
              jsonEncode({
                'type': 'event',
                'timestamp': 1700000000000,
                'severity': 'warning',
                'category': 'polarAlignment',
                'eventType': 'PolarAlignmentProgress',
                'data': {'azimuthErrorArcmin': 3.2, 'altitudeErrorArcmin': 1.4},
              }),
            );
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
      },
    );

    test(
      'parses HostStateChanged system events from headless wrapper',
      () async {
        final server = await _startServer((socket) {
          Timer(const Duration(milliseconds: 50), () {
            socket.add(
              jsonEncode({
                'type': 'event',
                'timestamp': 1700000000002,
                'severity': 'info',
                'category': 'system',
                'eventType': 'HostStateChanged',
                'data': {
                  'entityType': 'profile',
                  'action': 'updated',
                  'entityId': '1',
                },
              }),
            );
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
            .firstWhere((event) => event.eventType == 'HostStateChanged')
            .timeout(const Duration(seconds: 2));

        try {
          final event = await eventFuture;
          expect(event.category, EventCategory.system);
          expect(event.data['entityType'], 'profile');
          expect(event.data['action'], 'updated');
        } finally {
          backend.dispose();
          await server.close(force: true);
        }
      },
    );

    test('P2-13: first attempt emits `connecting`, post-success drop emits '
        '`reconnecting`', () async {
      var connectionCount = 0;
      final firstClientArrived = Completer<WebSocket>();
      final server = await _startServer((socket) {
        connectionCount++;
        if (!firstClientArrived.isCompleted) {
          firstClientArrived.complete(socket);
        }
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
        autoConnectWebSocket: false,
      );

      final observed = <BackendConnectionState>[];
      final stateSub = backend.connectionStateStream.listen(observed.add);

      try {
        // Kick off the first connect explicitly so we can watch the
        // sequence of state transitions from a known starting point.
        unawaited(backend.connect());
        await backend.connectionStateStream
            .firstWhere((s) => s == BackendConnectionState.connected)
            .timeout(const Duration(seconds: 2));

        // The first transition MUST be `connecting` (never reached the
        // `connected` state before, so this isn't a reconnection).
        expect(
          observed.first,
          BackendConnectionState.connecting,
          reason: 'P2-13: first connect attempt must use the connecting state',
        );
        expect(observed, contains(BackendConnectionState.connected));

        // Now drop the WS server-side and assert the next attempt
        // transitions through `reconnecting`, not `connecting`.
        final initialSocket = await firstClientArrived.future;
        await initialSocket.close();
        await backend.connectionStateStream
            .firstWhere((s) => s == BackendConnectionState.reconnecting)
            .timeout(const Duration(seconds: 5));
        await _waitUntil(
          () => connectionCount > 1,
          timeout: const Duration(seconds: 5),
        );

        expect(connectionCount, greaterThan(1));
      } finally {
        await stateSub.cancel();
        backend.dispose();
        await server.close(force: true);
      }
    });

    test('P2-2: sends collaboration.join after WS handshake', () async {
      // Capture the first non-control message arriving on the server's
      // WebSocket. The WS heartbeat sends `ping` frames so we filter those
      // out and assert the very next frame is our `collaboration.join`.
      final joinFrame = Completer<Map<String, dynamic>>();
      final server = await _startServer((socket) {
        socket.listen((message) {
          final data = jsonDecode(message as String) as Map<String, dynamic>;
          if (data['type'] == 'ping') {
            socket.add(jsonEncode({'type': 'pong'}));
            return;
          }
          if (data['type'] == 'collaboration.join' && !joinFrame.isCompleted) {
            joinFrame.complete(data);
          }
        });
      });

      final backend = NetworkBackend(
        serverHost: InternetAddress.loopbackIPv4.address,
        serverPort: server.port,
        webSocketPort: server.port,
        webSocketHeartbeatInterval: const Duration(milliseconds: 50),
        webSocketHeartbeatTimeout: const Duration(milliseconds: 250),
        autoConnectWebSocket: false,
      );
      backend.setCollaborationIdentity(
        viewerId: 'digest-fingerprint-abc',
        deviceName: 'mobile:cafe1234',
        displayName: 'iPhone · 1234',
      );

      try {
        unawaited(backend.connect());
        final frame = await joinFrame.future.timeout(
          const Duration(seconds: 3),
        );
        expect(frame['type'], 'collaboration.join');
        expect(frame['viewerId'], 'digest-fingerprint-abc');
        expect(frame['name'], 'iPhone · 1234');
        expect(frame['deviceName'], 'mobile:cafe1234');
      } finally {
        backend.dispose();
        await server.close(force: true);
      }
    });

    test(
      'preserves structured sequencer progress payloads over WebSocket',
      () async {
        final server = await _startServer((socket) {
          Timer(const Duration(milliseconds: 50), () {
            socket.add(
              jsonEncode({
                'type': 'event',
                'timestamp': 1700000000001,
                'severity': 'info',
                'category': 'sequencer',
                'eventType': 'InstructionProgressStructured',
                'data': {
                  'node_id': 'exp-1',
                  'instruction': 'Take Exposure',
                  'progress_percent': 40.0,
                  'detail_kind': 'Exposure',
                  'detail_json': jsonEncode({
                    'frame': 2,
                    'total': 5,
                    'duration_secs': 180.0,
                  }),
                },
              }),
            );
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
            .firstWhere(
              (event) => event.eventType == 'InstructionProgressStructured',
            )
            .timeout(const Duration(seconds: 2));

        try {
          final event = await eventFuture;

          expect(event.category, EventCategory.sequencer);
          expect(event.severity, EventSeverity.info);
          expect(event.data['node_id'], 'exp-1');
          expect(event.data['detail_kind'], 'Exposure');

          final detail =
              jsonDecode(event.data['detail_json'] as String)
                  as Map<String, dynamic>;
          expect(detail['frame'], 2);
          expect(detail['total'], 5);
          expect(detail['duration_secs'], 180.0);
        } finally {
          backend.dispose();
          await server.close(force: true);
        }
      },
    );
  });
}

Future<HttpServer> _startServer(
  void Function(WebSocket socket) onSocket, {
  Map<String, dynamic> infoBody = const {'version': '2.5.0'},
  Map<String, dynamic> devicesBody = const {'devices': []},
  List<Map<String, dynamic>>? devicesBodies,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var devicesRequestCount = 0;

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
      final selectedDevicesBody = devicesBodies == null
          ? devicesBody
          : devicesBodies[devicesRequestCount.clamp(
              0,
              devicesBodies.length - 1,
            )];
      devicesRequestCount++;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(selectedDevicesBody));
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

Future<void> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
