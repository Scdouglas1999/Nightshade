// Smoke tests for `NetworkBackend` request/response paths, using the
// `FakeNetworkClient` MockClient-based fake so no real HTTP server is needed.
//
// Why: `NetworkBackend` is the Mobile app's contract surface with the
// headless desktop. Before W-DECOMP rewrites it, we need a guard that:
//
//   * GETs go to the documented endpoints (`/api/devices`)
//   * HTTP failure codes are surfaced as `NightshadeError`, never silently
//     dropped or returned as empty lists (CLAUDE.md "no silent fallbacks")
//   * Malformed JSON propagates as an exception
//   * The pairing token is sent in the `Authorization: Bearer ...` header
//
// These are intentionally a small set of high-signal cases; full coverage
// of every endpoint is the follow-on scope of W-TEST.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/models/backend/device_types.dart';
import 'package:nightshade_core/src/models/errors/nightshade_error.dart';

import '../fakes/fakes.dart';

NetworkBackend _buildBackend(
  FakeNetworkClient fake, {
  String? authToken,
}) {
  return NetworkBackend(
    serverHost: '127.0.0.1',
    serverPort: 9999,
    webSocketPort: 9999,
    authToken: authToken,
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

    test('discoverDevices issues a GET /api/devices and decodes the body',
        () async {
      fake.setResponse(
        '/api/devices',
        method: 'GET',
        body: '{"devices":[{"id":"sim:cam:0","name":"Sim Camera",'
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
    });

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
        throwsA(isA<NightshadeError>()
            .having((e) => e.message, 'message',
                contains('missing pairing token'))),
      );
      expect(fake.requestsFor('/api/devices'), hasLength(1));
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
        expect(err.isRecoverable, isTrue,
            reason: '5xx must surface as transient/recoverable');
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

    test('request headers include the pairing token when authToken is set',
        () async {
      fake.setResponse(
        '/api/devices',
        method: 'GET',
        body: '{"devices":[]}',
      );
      backend = _buildBackend(fake, authToken: 'secret-token-abc');

      await backend.discoverDevices(DeviceType.camera);

      final captured = fake.requestsFor('/api/devices').single;
      // Why: `package:http` normalises header names to lowercase on the
      // wire, so we look up case-insensitively. The header *value* is
      // load-bearing — it carries the pairing token.
      final auth = _headerValue(captured.headers, 'Authorization');
      expect(auth, 'Bearer secret-token-abc',
          reason:
              'Authorization header must carry the bearer token when set');
      // The compat-version and trace-id headers are always added by
      // `_addAuthHeaders`; lock that in so future refactors don't drop
      // them silently.
      final keys =
          captured.headers.keys.map((k) => k.toLowerCase()).toList();
      expect(keys, contains('x-nightshade-api-version'));
      expect(keys, contains('x-request-id'));
    });

    test('omits the Authorization header when no authToken is configured',
        () async {
      fake.setResponse(
        '/api/devices',
        method: 'GET',
        body: '{"devices":[]}',
      );
      backend = _buildBackend(fake);

      await backend.discoverDevices(DeviceType.camera);

      final captured = fake.requestsFor('/api/devices').single;
      // Why: anonymous callers must not send an empty/bogus Authorization
      // header — the headless server treats presence-but-empty as a
      // misconfigured client.
      expect(_headerValue(captured.headers, 'Authorization'), isNull);
    });
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
