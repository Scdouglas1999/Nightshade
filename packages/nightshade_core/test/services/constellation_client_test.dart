// Pillar C ("Constellation") — hub client unit tests against a fake HTTP layer.
//
// Verifies request shape (method, /v1 path, bearer auth, order query), JSON
// decode of each typed result, the binary tile blob round-trip to disk, the
// HTTP-status -> ConstellationException mapping (including 409 ->
// geometryMismatch), and the handoff 404 -> null contract. No network access:
// every request is served by `package:http/testing.dart`'s MockClient.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  final hub = Uri.parse('https://hub.example.org');

  ConstellationClient clientWith(MockClient mock) => ConstellationClient(
    hubBaseUrl: hub,
    bearerToken: 'tok-123',
    client: mock,
  );

  group('request shape', () {
    test('info issues GET /v1/info with bearer auth', () async {
      http.Request? seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'name': 'Backyard Hub',
            'fingerprint': 'abc123',
            'version': '5.0.0',
            'healpixOrder': 9,
            'tilePixels': 1024,
            'selfHosted': true,
          }),
          200,
        );
      });

      final info = await clientWith(mock).info();

      expect(seen!.method, 'GET');
      expect(seen!.url.toString(), 'https://hub.example.org/v1/info');
      expect(seen!.headers['Authorization'], 'Bearer tok-123');
      expect(info.name, 'Backyard Hub');
      expect(info.healpixOrder, 9);
      expect(info.tilePixels, 1024);
      expect(info.selfHosted, isTrue);
    });

    test(
      'pushTile POSTs the .nst blob with order query + provenance headers',
      () async {
        final dir = await Directory.systemTemp.createTemp('nst_push');
        final delta = File('${dir.path}/delta_42.nst');
        await delta.writeAsBytes([9, 8, 7, 6]);

        http.Request? seen;
        final mock = MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'contributionId': 'c-1',
              'accepted': true,
              'trustApplied': 0.85,
              'totalFramesAfter': 130,
              'integrationSecondsAfter': 39000.0,
            }),
            201,
          );
        });

        final receipt = await clientWith(mock).pushTile(
          tileId: 42,
          order: 9,
          deltaPath: delta.path,
          framesDelta: 30,
          integrationSecondsDelta: 9000.0,
          instrument: 'asi2600-fp',
          solver: 'astap',
        );

        expect(seen!.method, 'POST');
        expect(
          seen!.url.toString(),
          'https://hub.example.org/v1/tiles/42/contributions?order=9',
        );
        expect(seen!.headers['framesDelta'], '30');
        expect(seen!.headers['integrationSecondsDelta'], '9000.0');
        expect(seen!.headers['instrument'], 'asi2600-fp');
        expect(seen!.headers['solver'], 'astap');
        expect(seen!.bodyBytes, [9, 8, 7, 6]);
        expect(receipt.contributionId, 'c-1');
        expect(receipt.accepted, isTrue);
        expect(receipt.trustApplied, 0.85);
        expect(receipt.totalFramesAfter, 130);

        await dir.delete(recursive: true);
      },
    );

    test('pullTile GETs the blob and writes it to disk', () async {
      final dir = await Directory.systemTemp.createTemp('nst_pull');
      final out = '${dir.path}/community_42.fits';

      http.Request? seen;
      final mock = MockClient((request) async {
        seen = request;
        return http.Response.bytes([1, 2, 3, 4, 5], 200);
      });

      final written = await clientWith(
        mock,
      ).pullTile(tileId: 42, order: 9, outPath: out, finalized: true);

      expect(seen!.method, 'GET');
      expect(
        seen!.url.toString(),
        'https://hub.example.org/v1/tiles/42?order=9&finalized=true',
      );
      expect(written, out);
      expect(await File(out).readAsBytes(), [1, 2, 3, 4, 5]);

      await dir.delete(recursive: true);
    });
  });

  group('handoff', () {
    test('queryHandoff maps 404 to null (no baton state)', () async {
      final mock = MockClient((_) async => http.Response('not found', 404));
      final claim = await clientWith(mock).queryHandoff(7);
      expect(claim, isNull);
    });

    test('queryHandoff decodes an available baton', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'targetId': 7,
            'activeTileId': 42,
            'holder': null,
            'altitudeOk': true,
            'claimToken': null,
          }),
          200,
        ),
      );
      final claim = await clientWith(mock).queryHandoff(7);
      expect(claim, isNotNull);
      expect(claim!.targetId, 7);
      expect(claim.activeTileId, 42);
      expect(claim.isAvailableNow, isTrue);
    });

    test('claimHandoff returns the granted token + expiry', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'targetId': 7,
            'activeTileId': 42,
            'holder': 'me',
            'altitudeOk': true,
            'claimToken': 'baton-1',
            'expiresAt': '2026-06-20T10:00:00Z',
          }),
          200,
        ),
      );
      final claim = await clientWith(mock).claimHandoff(7);
      expect(claim!.claimToken, 'baton-1');
      expect(claim.expiresAt, DateTime.utc(2026, 6, 20, 10));
      // Held by us -> not "available now" for someone else to grab.
      expect(claim.isAvailableNow, isFalse);
    });
  });

  group('error mapping', () {
    test('409 maps to geometryMismatch', () async {
      final dir = await Directory.systemTemp.createTemp('nst_409');
      final delta = File('${dir.path}/d.nst')..writeAsBytesSync([0]);
      final mock = MockClient(
        (_) async => http.Response('order mismatch', 409),
      );

      await expectLater(
        clientWith(mock).pushTile(tileId: 1, order: 9, deltaPath: delta.path),
        throwsA(
          isA<ConstellationException>().having(
            (e) => e.kind,
            'kind',
            ConstellationErrorKind.geometryMismatch,
          ),
        ),
      );
      await dir.delete(recursive: true);
    });

    test('401 maps to auth', () async {
      final mock = MockClient((_) async => http.Response('nope', 401));
      await expectLater(
        clientWith(mock).info(),
        throwsA(
          isA<ConstellationException>().having(
            (e) => e.kind,
            'kind',
            ConstellationErrorKind.auth,
          ),
        ),
      );
    });

    test('pushTile throws notFound when the delta file is missing', () async {
      final mock = MockClient((_) async => http.Response('', 200));
      await expectLater(
        clientWith(
          mock,
        ).pushTile(tileId: 1, order: 9, deltaPath: '/does/not/exist.nst'),
        throwsA(
          isA<ConstellationException>().having(
            (e) => e.kind,
            'kind',
            ConstellationErrorKind.notFound,
          ),
        ),
      );
    });
  });
}
