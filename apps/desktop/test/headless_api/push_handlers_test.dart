import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_desktop/headless_api/auth/pairing_service.dart';
import 'package:nightshade_desktop/headless_api_server.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_remote_protocol/nightshade_remote_protocol.dart';

/// Phase D — end-to-end `/api/push/*` endpoint tests. Boots a real
/// [HeadlessApiServer] over an in-memory pairing DB, pairs a device, then
/// drives the token + preference endpoints over HTTP. Covers:
///  - register-token upserts (register twice → one row, latest token),
///  - preferences round-trip (PUT then GET identical),
///  - the routes are authenticated (no bearer → 401).
void main() {
  group('HeadlessApiServer push endpoints', () {
    late ProviderContainer container;
    late HeadlessApiServer server;
    late HttpClient client;
    late Uri baseUri;
    late PairingService pairingService;
    late PairingDatabase database;
    late String controlToken;
    const deviceId = 'push-phone';

    setUp(() async {
      database = PairingDatabase.forTesting(NativeDatabase.memory());
      pairingService = PairingService(database: database);
      container = ProviderContainer(
        overrides: [
          appVersionProvider.overrideWithValue(
            const AppVersionInfo(version: '4.0.0', buildNumber: 1),
          ),
        ],
      );
      server = HeadlessApiServer(
        port: 0,
        container: container,
        bindLocalOnly: true,
        authToken: 'admin-token',
        pairingService: pairingService,
      );
      await server.start();
      client = HttpClient();
      baseUri = Uri.parse('http://127.0.0.1:${server.actualPort}');

      // Pair the phone so its deviceId is a known paired device (the push
      // endpoints reject unknown devices).
      final start = await pairingService.startPairing();
      final verify = await _request(
        client,
        baseUri,
        '/api/pairing/verify',
        method: 'POST',
        body: {
          'code': start.code,
          'deviceId': deviceId,
          'deviceName': 'Push Phone',
          'deviceType': 'mobile',
        },
      );
      expect(verify.statusCode, HttpStatus.ok);
      controlToken = verify.body['token'] as String;
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
      await pairingService.close();
      container.dispose();
    });

    test('register-token upserts (second register overwrites in place)',
        () async {
      final first = await _request(
        client,
        baseUri,
        '/api/push/register-token',
        method: 'POST',
        token: controlToken,
        body: {'deviceId': deviceId, 'platform': 'fcm', 'token': 'tok-1'},
      );
      expect(first.statusCode, HttpStatus.ok);
      expect(first.body['status'], 'registered');

      // Re-register with a refreshed token — must overwrite, not duplicate.
      final second = await _request(
        client,
        baseUri,
        '/api/push/register-token',
        method: 'POST',
        token: controlToken,
        body: {'deviceId': deviceId, 'platform': 'fcm', 'token': 'tok-2'},
      );
      expect(second.statusCode, HttpStatus.ok);

      final rows = await database.getPushTokensByPlatform('fcm');
      expect(rows, hasLength(1), reason: 'upsert must not duplicate');
      expect(rows.single.token, 'tok-2');
      expect(rows.single.deviceId, deviceId);
    });

    test('register-token rejects an unknown deviceId with 404', () async {
      final res = await _request(
        client,
        baseUri,
        '/api/push/register-token',
        method: 'POST',
        token: controlToken,
        body: {'deviceId': 'never-paired', 'platform': 'fcm', 'token': 't'},
      );
      expect(res.statusCode, HttpStatus.notFound);
      expect(res.body['error'], 'unknown_device');
    });

    test('register-token rejects an invalid platform with 400', () async {
      final res = await _request(
        client,
        baseUri,
        '/api/push/register-token',
        method: 'POST',
        token: controlToken,
        body: {'deviceId': deviceId, 'platform': 'sms', 'token': 't'},
      );
      expect(res.statusCode, HttpStatus.badRequest);
    });

    test('DELETE /api/push/token removes a device\'s tokens', () async {
      await _request(
        client,
        baseUri,
        '/api/push/register-token',
        method: 'POST',
        token: controlToken,
        body: {'deviceId': deviceId, 'platform': 'apns', 'token': 'a'},
      );
      expect(await database.getPushTokensForDevice(deviceId), hasLength(1));

      final del = await _request(
        client,
        baseUri,
        '/api/push/token',
        method: 'DELETE',
        token: controlToken,
        body: {'deviceId': deviceId},
      );
      expect(del.statusCode, HttpStatus.ok);
      expect(await database.getPushTokensForDevice(deviceId), isEmpty);
    });

    test('preferences round-trip: PUT then GET returns the same matrix',
        () async {
      final put = await _request(
        client,
        baseUri,
        '/api/push/preferences',
        method: 'PUT',
        token: controlToken,
        body: {
          'deviceId': deviceId,
          'enabled': true,
          'muteWeatherUnsafe': true,
          'muteAutofocusFailed': true,
        },
      );
      expect(put.statusCode, HttpStatus.ok);

      final get = await _request(
        client,
        baseUri,
        '/api/push/preferences?deviceId=$deviceId',
        token: controlToken,
      );
      expect(get.statusCode, HttpStatus.ok);
      expect(get.body['enabled'], isTrue);
      expect(get.body['muteWeatherUnsafe'], isTrue);
      expect(get.body['muteAutofocusFailed'], isTrue);
      // Flags not sent default to "not muted".
      expect(get.body['muteSequenceFailed'], isFalse);
      expect(get.body['muteGuidingLost'], isFalse);
      expect(get.body['muteEquipmentDisconnected'], isFalse);
    });

    test('GET preferences returns all-enabled defaults when no row exists',
        () async {
      final get = await _request(
        client,
        baseUri,
        '/api/push/preferences?deviceId=$deviceId',
        token: controlToken,
      );
      expect(get.statusCode, HttpStatus.ok);
      expect(get.body['enabled'], isTrue);
      expect(get.body['muteWeatherUnsafe'], isFalse);
    });

    test('push endpoints require authentication (no bearer → 401)', () async {
      final res = await _request(
        client,
        baseUri,
        '/api/push/register-token',
        method: 'POST',
        body: {'deviceId': deviceId, 'platform': 'fcm', 'token': 't'},
      );
      expect(res.statusCode, HttpStatus.unauthorized);
    });
  });
}

Future<_TestResponse> _request(
  HttpClient client,
  Uri baseUri,
  String path, {
  String method = 'GET',
  String? token,
  Map<String, dynamic>? body,
}) async {
  final request = await client.openUrl(
    method,
    baseUri.replace(path: path.split('?').first, query: _queryOf(path)),
  );
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  if (body != null) {
    final encoded = jsonEncode(body);
    request.headers.set('Content-Type', 'application/json');
    request.add(utf8.encode(encoded));
  }
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  final parsed = text.trim().isEmpty
      ? <String, dynamic>{}
      : jsonDecode(text) as Map<String, dynamic>;
  return _TestResponse(statusCode: response.statusCode, body: parsed);
}

String? _queryOf(String path) {
  final idx = path.indexOf('?');
  return idx < 0 ? null : path.substring(idx + 1);
}

class _TestResponse {
  final int statusCode;
  final Map<String, dynamic> body;

  const _TestResponse({required this.statusCode, required this.body});
}
