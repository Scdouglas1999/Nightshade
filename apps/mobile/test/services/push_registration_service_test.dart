// Phase E — PushRegistrationService tests.
//
// Validates the iOS APNs token plumbing at the channel + HTTP boundary:
//   * the platform string is `apns` (the server's contract, NOT `ios`),
//   * the POST body carries deviceId + token + the bearer header,
//   * non-iOS short-circuits without touching the channel (no
//     MissingPluginException, no HTTP),
//   * a host-pushed `onApnsToken` triggers a register POST,
//   * an unchanged token is not re-POSTed.
//
// The service is normally iOS-only at runtime; `isIosOverride` lets the unit
// test drive both branches deterministically on a Linux/CI host where
// Platform.isIOS is false.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/services/push_registration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'nightshade/push';

  /// A NetworkBackend that never opens a socket (autoConnectWebSocket: false)
  /// so the test only exercises the fields the service reads.
  NetworkBackend buildBackend({
    String host = 'rig.local',
    int port = 8080,
    String scheme = 'http',
    String? token = 'bearer-xyz',
  }) {
    return NetworkBackend(
      serverHost: host,
      serverPort: port,
      scheme: scheme,
      authToken: token,
      autoConnectWebSocket: false,
    );
  }

  group('non-iOS gating', () {
    test('ensureRegistered no-ops off iOS and never POSTs', () async {
      var httpCalls = 0;
      final client = MockClient((req) async {
        httpCalls++;
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        httpClient: client,
        isIosOverride: false,
      );
      addTearDown(service.dispose);

      await service.ensureRegistered(
        backend: buildBackend(),
        deviceId: 'mobile:abc',
      );

      expect(httpCalls, 0, reason: 'must not register off iOS');
    });
  });

  group('iOS registration', () {
    late MethodChannel channel;
    late List<MethodCall> hostCalls;

    setUp(() {
      channel = const MethodChannel(channelName);
      hostCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        hostCalls.add(call);
        switch (call.method) {
          case 'registerForRemoteNotifications':
            return true;
          case 'getApnsToken':
            // Default: token already issued by the OS, returned synchronously.
            return 'a1b2c3d4';
          default:
            throw MissingPluginException('no mock for ${call.method}');
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('POSTs platform=apns with deviceId, token, and bearer header',
        () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({'status': 'registered'}),
          200,
        );
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      await service.ensureRegistered(
        backend: buildBackend(token: 'bearer-xyz'),
        deviceId: 'mobile:deadbeef',
      );

      // Asked the OS to register.
      expect(
        hostCalls.map((c) => c.method),
        contains('registerForRemoteNotifications'),
      );

      // POSTed to the right endpoint with the right contract.
      expect(captured, isNotNull);
      expect(captured!.method, 'POST');
      expect(captured!.url.path, '/api/push/register-token');
      expect(captured!.url.host, 'rig.local');
      expect(captured!.url.port, 8080);
      expect(captured!.headers['Authorization'], 'Bearer bearer-xyz');

      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['platform'], 'apns');
      expect(body['deviceId'], 'mobile:deadbeef');
      expect(body['token'], 'a1b2c3d4');
    });

    test('omits Authorization header when the backend has no token', () async {
      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      await service.ensureRegistered(
        backend: buildBackend(token: null),
        deviceId: 'mobile:x',
      );

      expect(captured!.headers.containsKey('Authorization'), isFalse);
    });

    test('empty deviceId skips registration entirely', () async {
      var httpCalls = 0;
      final client = MockClient((req) async {
        httpCalls++;
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      await service.ensureRegistered(
        backend: buildBackend(),
        deviceId: '',
      );

      expect(httpCalls, 0);
      expect(hostCalls, isEmpty,
          reason: 'no channel traffic when not paired');
    });

    test('unchanged token is not re-POSTed on a second ensureRegistered',
        () async {
      var httpCalls = 0;
      final client = MockClient((req) async {
        httpCalls++;
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      final backend = buildBackend();
      await service.ensureRegistered(backend: backend, deviceId: 'mobile:x');
      await service.ensureRegistered(backend: backend, deviceId: 'mobile:x');

      expect(httpCalls, 1, reason: 'same token must POST only once');
    });

    test(
        'switching server target re-POSTs the same token (Blocker #8: '
        'APNs hands back the same token across servers)', () async {
      final targets = <String>[];
      final client = MockClient((req) async {
        targets.add('${req.url.host}:${req.url.port}');
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      // Register with server A. getApnsToken returns the SAME 'a1b2c3d4' below
      // regardless of which server we point at — exactly the production case
      // where APNs reissues the identical device token on the next connect.
      await service.ensureRegistered(
        backend: buildBackend(host: 'serverA.local', port: 8080),
        deviceId: 'mobile:x',
      );
      // Re-pair / switch to server B with the unchanged token. The pre-fix
      // token-only gate suppressed this POST, so server B never learned the
      // token and no cellular alerts could reach the phone.
      await service.ensureRegistered(
        backend: buildBackend(host: 'serverB.local', port: 9090),
        deviceId: 'mobile:x',
      );

      // Uri lowercases the host on the wire; assert against that canonical form.
      expect(
        targets,
        ['servera.local:8080', 'serverb.local:9090'],
        reason: 'a target change must force a re-POST even when the APNs '
            'token is unchanged',
      );
    });

    test(
        'switching deviceId (re-pair as a different device) re-POSTs the same '
        'token', () async {
      final deviceIds = <String>[];
      final client = MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        deviceIds.add(body['deviceId'] as String);
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      final backend = buildBackend();
      await service.ensureRegistered(backend: backend, deviceId: 'mobile:old');
      await service.ensureRegistered(backend: backend, deviceId: 'mobile:new');

      expect(
        deviceIds,
        ['mobile:old', 'mobile:new'],
        reason: 'a deviceId change must force a re-POST even when the APNs '
            'token and target host are unchanged',
      );
    });

    test('reset() forces a re-POST of the same token', () async {
      var httpCalls = 0;
      final client = MockClient((req) async {
        httpCalls++;
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      final backend = buildBackend();
      await service.ensureRegistered(backend: backend, deviceId: 'mobile:x');
      service.reset();
      await service.ensureRegistered(backend: backend, deviceId: 'mobile:x');

      expect(httpCalls, 2);
    });
  });

  group('host-pushed token (onApnsToken)', () {
    test('a token pushed by the host after ensureRegistered triggers a POST',
        () async {
      const channel = MethodChannel(channelName);
      // Host returns null from getApnsToken (token not ready yet), then later
      // pushes it via onApnsToken.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'registerForRemoteNotifications') return true;
        if (call.method == 'getApnsToken') return null;
        throw MissingPluginException('no mock for ${call.method}');
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      http.Request? captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      });
      final service = PushRegistrationService(
        channel: channel,
        httpClient: client,
        isIosOverride: true,
      );
      addTearDown(service.dispose);

      // Establish the target (getApnsToken returns null, so no POST yet).
      await service.ensureRegistered(
        backend: buildBackend(),
        deviceId: 'mobile:late',
      );
      expect(captured, isNull);

      // Now the host delivers the token asynchronously.
      const codec = StandardMethodCodec();
      final message = codec.encodeMethodCall(
        const MethodCall('onApnsToken', 'ffeeddcc'),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channelName, message, (_) {});

      expect(captured, isNotNull);
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['platform'], 'apns');
      expect(body['token'], 'ffeeddcc');
      expect(body['deviceId'], 'mobile:late');
    });
  });
}
