// Smoke tests for `NetworkBackend` request/response paths, using the
// `FakeNetworkClient` MockClient-based fake so no real HTTP server is needed.
//
// Why: `NetworkBackend` is the Mobile app's contract surface with the
// headless desktop. Before a later refactor rewrites it, we need a guard that:
//
//   * GETs go to the documented endpoints (`/api/devices`)
//   * HTTP failure codes are surfaced as `NightshadeError`, never silently
// dropped or returned as empty lists (no silent fallbacks here)
//   * Malformed JSON propagates as an exception
//   * The pairing token is sent in the `Authorization: Bearer ...` header
//
// These are intentionally a small set of high-signal cases; full coverage
// of every endpoint is the follow-on scope of W-TEST.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/models/backend/device_types.dart';
import 'package:nightshade_core/src/models/backend/image_result.dart';
import 'package:nightshade_core/src/models/errors/nightshade_error.dart';
import 'package:nightshade_core/src/models/plate_solver.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';

import '../fakes/fakes.dart';

NetworkBackend _buildBackend(
  FakeNetworkClient fake, {
  String? authToken,
  Future<String?> Function()? refreshAuthToken,
}) {
  return NetworkBackend(
    serverHost: '127.0.0.1',
    serverPort: 9999,
    webSocketPort: 9999,
    authToken: authToken,
    refreshAuthToken: refreshAuthToken,
    httpClient: fake,
    autoConnectWebSocket: false,
  );
}

void main() {
  group('NetworkBackend (FakeNetworkClient)', () {
    late FakeNetworkClient fake;
    late NetworkBackend backend;

    setUp(() {
      fake = FakeNetworkClient();
    });

    tearDown(() {
      backend.dispose();
    });

    test(
      'discoverDevices issues a GET /api/devices and decodes the body',
      () async {
        fake.setResponse(
          '/api/devices',
          method: 'GET',
          body:
              '{"devices":[{"id":"sim:cam:0","name":"Sim Camera",'
              '"deviceType":"camera","driverType":"simulator",'
              '"description":"","driverVersion":"1.0"}]}',
        );
        backend = _buildBackend(fake);

        final devices = await backend.discoverDevices(DeviceType.camera);

        expect(devices, hasLength(1));
        expect(devices.single.id, 'sim:cam:0');
        expect(devices.single.driverType, DriverType.simulator);

        final issued = fake.requestsFor('/api/devices');
        expect(issued, hasLength(1));
        expect(issued.single.method, 'GET');
      },
    );

    test('a 401 response is surfaced as a structured NightshadeError, '
        'not silently swallowed', () async {
      // 401 is non-transient, so we expect exactly one request and an
      // immediate failure.
      fake.setResponse(
        '/api/devices',
        method: 'GET',
        status: 401,
        body: '{"error":"unauthorized","message":"missing pairing token"}',
      );
      backend = _buildBackend(fake);

      // The fail-closed contract: errors propagate; they are not returned
      // as an empty device list.
      await expectLater(
        backend.discoverDevices(DeviceType.camera),
        throwsA(
          isA<NightshadeError>().having(
            (e) => e.message,
            'message',
            contains('missing pairing token'),
          ),
        ),
      );
      expect(fake.requestsFor('/api/devices'), hasLength(1));
    });

    test('refreshes auth token once after 401 and retries discovery', () async {
      fake.setResponseSequence(
        '/api/devices',
        method: 'GET',
        responses: [
          (
            status: 401,
            body: '{"error":"unauthorized","message":"expired token"}',
            headers: null,
          ),
          (
            status: 200,
            body:
                '{"devices":[{"id":"sim:cam:1","name":"Sim Camera",'
                '"deviceType":"camera","driverType":"simulator",'
                '"description":"","driverVersion":"1.0"}]}',
            headers: null,
          ),
        ],
      );
      var refreshCount = 0;
      backend = _buildBackend(
        fake,
        authToken: 'expired-token',
        refreshAuthToken: () async {
          refreshCount++;
          return 'fresh-token';
        },
      );

      final devices = await backend.discoverDevices(DeviceType.camera);

      expect(devices, hasLength(1));
      expect(refreshCount, 1);
      final requests = fake.requestsFor('/api/devices');
      expect(requests, hasLength(2));
      expect(
        _headerValue(requests.first.headers, 'Authorization'),
        'Bearer expired-token',
      );
      expect(
        _headerValue(requests.last.headers, 'Authorization'),
        'Bearer fresh-token',
      );
    });

    test('a 500 response is retried as a transient failure and surfaces '
        'as a recoverable NightshadeError', () async {
      // Use a plain (non-JSON) body so `_parseErrorResponse` exercises the
      // HTTP-status-based fallback path; that path marks 5xx as recoverable
      // (`_isTransientStatusCode`), which is the behaviour we want to lock
      // in. A structured legacy `{error, message}` body would short-circuit
      // to `NightshadeError.fromString`, which is HTTP-status-blind.
      fake.setResponse(
        '/api/devices',
        method: 'GET',
        status: 500,
        body: 'upstream unavailable',
      );
      backend = _buildBackend(fake);

      try {
        await backend.discoverDevices(DeviceType.camera);
        fail('Expected discoverDevices to throw on persistent 500');
      } on NightshadeError catch (err) {
        expect(
          err.isRecoverable,
          isTrue,
          reason: '5xx must surface as transient/recoverable',
        );
        expect(err.message, contains('500'));
      }

      // The retry policy fires 3 attempts for transient failures.
      expect(fake.requestsFor('/api/devices'), hasLength(3));
    });

    test('malformed JSON in a 200 response is surfaced, not returned as '
        'empty', () async {
      fake.setResponse(
        '/api/devices',
        method: 'GET',
        body: '{this is not valid json',
      );
      backend = _buildBackend(fake);

      // Critical: silent `return []` here would mask backend corruption.
      // We assert that *some* exception propagates.
      await expectLater(
        backend.discoverDevices(DeviceType.camera),
        throwsA(isA<Object>()),
      );
    });

    test(
      'request headers include the pairing token when authToken is set',
      () async {
        fake.setResponse('/api/devices', method: 'GET', body: '{"devices":[]}');
        backend = _buildBackend(fake, authToken: 'secret-token-abc');

        await backend.discoverDevices(DeviceType.camera);

        final captured = fake.requestsFor('/api/devices').single;
        // Why: `package:http` normalises header names to lowercase on the
        // wire, so we look up case-insensitively. The header *value* is
        // load-bearing — it carries the pairing token.
        final auth = _headerValue(captured.headers, 'Authorization');
        expect(
          auth,
          'Bearer secret-token-abc',
          reason: 'Authorization header must carry the bearer token when set',
        );
        // The compat-version and trace-id headers are always added by
        // `_addAuthHeaders`; lock that in so future refactors don't drop
        // them silently.
        final keys = captured.headers.keys.map((k) => k.toLowerCase()).toList();
        expect(keys, contains('x-nightshade-api-version'));
        expect(keys, contains('x-request-id'));
      },
    );

    test(
      'omits the Authorization header when no authToken is configured',
      () async {
        fake.setResponse('/api/devices', method: 'GET', body: '{"devices":[]}');
        backend = _buildBackend(fake);

        await backend.discoverDevices(DeviceType.camera);

        final captured = fake.requestsFor('/api/devices').single;
        // Why: anonymous callers must not send an empty/bogus Authorization
        // header — the headless server treats presence-but-empty as a
        // misconfigured client.
        expect(_headerValue(captured.headers, 'Authorization'), isNull);
      },
    );

    test('cameraGetLastImage uses GET /api/camera/last-image/jpeg', () async {
      final bitmap = img.Image(width: 4, height: 2);
      bitmap.setPixelRgba(0, 0, 10, 20, 30, 255);
      final jpegBytes = img.encodeJpg(bitmap, quality: 90);
      final metaHeader = base64Encode(
        utf8.encode(
          jsonEncode({
            'width': 4,
            'height': 2,
            'encodedWidth': 4,
            'encodedHeight': 2,
            'histogram': List<int>.filled(256, 0),
            'stats': const ImageStatsResult(
              min: 0,
              max: 100,
              mean: 50,
              median: 50,
              stdDev: 10,
              starCount: 3,
            ).toJson(),
            'exposureTime': 1.5,
            'timestamp': '2026-05-23T12:00:00.000Z',
            'isColor': false,
          }),
        ),
      );

      fake.setBinaryResponse(
        '/api/camera/last-image/jpeg',
        bodyBytes: jpegBytes,
        headers: {'content-type': 'image/jpeg', 'x-image-meta': metaHeader},
      );
      backend = _buildBackend(fake);

      final image = await backend.cameraGetLastImage('cam-1');

      expect(image, isNotNull);
      expect(image!.width, 4);
      expect(image.height, 2);
      expect(image.displayData.length, 4 * 2 * 4);
      expect(image.stats.starCount, 3);

      final issued = fake.requestsFor('/api/camera/last-image/jpeg');
      expect(issued, hasLength(1));
      expect(issued.single.method, 'GET');
      expect(issued.single.url.queryParameters['deviceId'], 'cam-1');
      expect(fake.requestsFor('/api/camera/last-image'), isEmpty);
    });

    test('cameraGetLastImage returns null when JPEG endpoint is 404', () async {
      fake.setBinaryResponse(
        '/api/camera/last-image/jpeg',
        status: 404,
        bodyBytes: utf8.encode(
          '{"error":"no_image","message":"No image captured"}',
        ),
        headers: const {'content-type': 'application/json'},
      );
      backend = _buildBackend(fake);

      final image = await backend.cameraGetLastImage('cam-1');
      expect(image, isNull);
    });

    test('detectPlateSolvers GETs the HOST /api/plate-solver/detect and '
        'decodes the host filesystem probe', () async {
      // Remote-parity: a phone's plate-solver setup must probe the HOST,
      // not the phone. This proves the NetworkBackend forwards detection to
      // the host endpoint and returns what the host found on its disk.
      fake.setResponse(
        '/api/plate-solver/detect',
        method: 'GET',
        body:
            '{"astapPath":"C:/ASTAP/astap.exe",'
            '"astrometryPath":null,'
            '"catalogName":"V17",'
            '"catalogMagnitudeLimit":17.0,'
            '"catalogPath":"C:/ASTAP"}',
      );
      backend = _buildBackend(fake);

      final detection = await backend.detectPlateSolvers();

      expect(fake.requestsFor('/api/plate-solver/detect'), hasLength(1));
      expect(detection.astapPath, 'C:/ASTAP/astap.exe');
      expect(detection.astrometryPath, isNull);
      expect(detection.catalogName, 'V17');
      expect(detection.catalogMagnitudeLimit, 17.0);
      expect(detection.catalogPath, 'C:/ASTAP');
      expect(detection.hasAnySolver, isTrue);
    });

    test('getPlateSolverConfig GETs the HOST /api/plate-solver/config and '
        'decodes the host-persisted preference', () async {
      fake.setResponse(
        '/api/plate-solver/config',
        method: 'GET',
        body:
            '{"astapPath":"C:/ASTAP/astap.exe",'
            '"astrometryPath":"",'
            '"catalogPath":"C:/ASTAP",'
            '"solverChoice":"astap"}',
      );
      backend = _buildBackend(fake);

      final pref = await backend.getPlateSolverConfig();

      expect(fake.requestsFor('/api/plate-solver/config'), hasLength(1));
      expect(pref.astapPath, 'C:/ASTAP/astap.exe');
      expect(pref.astrometryPath, '');
      expect(pref.catalogPath, 'C:/ASTAP');
      expect(pref.choice, PlateSolverChoice.astap);
    });

    test('setPlateSolverConfig POSTs the preference to the HOST '
        '/api/plate-solver/config', () async {
      fake.setResponse(
        '/api/plate-solver/config',
        method: 'POST',
        body: '{"status":"saved"}',
      );
      backend = _buildBackend(fake);

      await backend.setPlateSolverConfig(
        const PlateSolverPreference(
          astapPath: 'C:/ASTAP/astap.exe',
          astrometryPath: '',
          catalogPath: 'C:/ASTAP',
          choice: PlateSolverChoice.astap,
        ),
      );

      final posts = fake
          .requestsFor('/api/plate-solver/config')
          .where((r) => r.method == 'POST')
          .toList();
      expect(posts, hasLength(1));
      final sent = jsonDecode(posts.single.body!) as Map<String, dynamic>;
      expect(sent['astapPath'], 'C:/ASTAP/astap.exe');
      expect(sent['catalogPath'], 'C:/ASTAP');
      expect(sent['solverChoice'], 'astap');
    });

    test(
      'getConnectedDevices decodes deviceType field from host API',
      () async {
        fake.setResponse(
          '/api/devices/connected',
          method: 'GET',
          body:
              '{"devices":[{"id":"ascom:mount:0","name":"My Mount",'
              '"deviceType":"mount","driverType":"ascom",'
              '"description":"","driverVersion":"1.0"}]}',
        );
        backend = _buildBackend(fake);

        final devices = await backend.getConnectedDevices();

        expect(devices, hasLength(1));
        expect(devices.single.id, 'ascom:mount:0');
        expect(devices.single.deviceType, DeviceType.mount);
        expect(devices.single.driverType, DriverType.ascom);
      },
    );

    test('webSocketPort defaults to serverPort when explicitly set', () {
      backend = NetworkBackend(
        serverHost: '127.0.0.1',
        serverPort: 4321,
        webSocketPort: 4321,
        autoConnectWebSocket: false,
      );
      expect(backend.serverPort, 4321);
      expect(backend.webSocketPort, 4321);
      backend.dispose();
    });
  });

  group('BackendNotifier remote connect', () {
    test(
      'creates NetworkBackend with matching HTTP and WebSocket ports',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        try {
          await container
              .read(backendProvider.notifier)
              .connect('127.0.0.1', 8765, authToken: 'test-token');
        } catch (_) {
          // No server listening in unit tests; construction is what we verify.
        }

        final backend = container.read(backendProvider);
        expect(backend, isA<NetworkBackend>());
        final remote = backend as NetworkBackend;
        expect(remote.serverPort, 8765);
        expect(remote.webSocketPort, 8765);
        expect(remote.serverHost, '127.0.0.1');
      },
    );
  });
}

/// Case-insensitive header lookup. `package:http` lowercases header names
/// on the wire, but the production code writes them in mixed case via
/// `_addAuthHeaders`, so tests must compare without regard to case.
String? _headerValue(Map<String, String> headers, String name) {
  final lower = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lower) {
      return entry.value;
    }
  }
  return null;
}
