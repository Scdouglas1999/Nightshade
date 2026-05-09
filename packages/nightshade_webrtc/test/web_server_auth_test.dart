import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nightshade_webrtc/nightshade_webrtc.dart';

void main() {
  group('NightshadeWebServer pairing protection', () {
    late PairingDatabase database;
    late TokenManager tokenManager;
    late NightshadeWebServer server;
    late http.Client client;
    late Uri baseUri;

    setUp(() async {
      database = PairingDatabase.forTesting(NativeDatabase.memory());
      tokenManager = TokenManager(database);
      server = NightshadeWebServer(
        port: 0,
        bindLocalOnly: false,
        tokenManager: tokenManager,
        requireAuthentication: true,
      );
      await server.start();
      client = http.Client();
      baseUri = Uri.parse('http://127.0.0.1:${server.actualPort}');
    });

    tearDown(() async {
      client.close();
      await server.stop();
      await database.close();
    });

    Future<http.Response> postPairingAttempt(String pairingCode) {
      return client.post(
        baseUri.resolve('/api/pairing/verify'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'pairingCode': pairingCode,
          'deviceId': 'browser-1',
          'deviceName': 'QA Browser',
        }),
      );
    }

    test('locks out repeated invalid pairing attempts from the same client',
        () async {
      for (var attempt = 0; attempt < 5; attempt++) {
        final response = await postPairingAttempt('BAD-CODE-0000');
        expect(response.statusCode, HttpStatus.unauthorized);
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        expect(body['error'], 'invalid_code');
      }

      final lockedResponse = await postPairingAttempt('BAD-CODE-0000');
      expect(lockedResponse.statusCode, HttpStatus.tooManyRequests);
      expect(
        lockedResponse.headers.containsKey('retry-after'),
        isTrue,
      );
      final body = jsonDecode(lockedResponse.body) as Map<String, dynamic>;
      expect(body['error'], 'pairing_rate_limited');
    });
  });

  group('NightshadeWebServer static files', () {
    late Directory tempRoot;
    late Directory webRoot;
    late NightshadeWebServer server;
    late http.Client client;
    late Uri baseUri;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('nightshade_web_test_');
      webRoot = Directory('${tempRoot.path}${Platform.pathSeparator}web');
      await webRoot.create(recursive: true);
      await File('${webRoot.path}${Platform.pathSeparator}index.html')
          .writeAsString('dashboard');
      await File('${tempRoot.path}${Platform.pathSeparator}secret.txt')
          .writeAsString('outside secret');

      server = NightshadeWebServer(
        port: 0,
        webRoot: webRoot.path,
        bindLocalOnly: true,
      );
      await server.start();
      client = http.Client();
      baseUri = Uri.parse('http://127.0.0.1:${server.actualPort}');
    });

    tearDown(() async {
      client.close();
      await server.stop();
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('rejects encoded traversal paths before SPA fallback', () async {
      final response = await client.get(
        Uri.parse('http://127.0.0.1:${server.actualPort}/..%5csecret.txt'),
      );

      expect(response.statusCode, HttpStatus.forbidden);
      expect(response.body, isNot(contains('outside secret')));
    });

    test('serves dashboard assets from the configured web root', () async {
      final response = await client.get(baseUri.resolve('/index.html'));

      expect(response.statusCode, HttpStatus.ok);
      expect(response.body, 'dashboard');
    });
  });
}
