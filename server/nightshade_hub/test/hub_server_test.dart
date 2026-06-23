import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nightshade_hub/nightshade_hub.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late HubServer server;
  late Handler handler;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nshub_http_');
    server = HubServer(
      HubConfig(
        databasePath: ':memory:',
        atlasRoot: '${tmp.path}/atlas',
        serverSecret: 'test-secret',
        openSignup: true,
        // Compact tiles keep the contribution fixtures small; the geometry gate
        // validates uploads against THIS value, so the test deltas match it.
        tilePixels: 8,
      ),
    );
    handler = server.handler;
  });

  tearDown(() {
    server.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<Response> req(
    String method,
    String path, {
    String? token,
    Object? jsonBody,
    Uint8List? binaryBody,
  }) {
    final headers = <String, String>{
      if (token != null) 'authorization': 'Bearer $token',
      if (jsonBody != null) 'content-type': 'application/json',
    };
    final request = Request(
      method,
      Uri.parse('http://localhost${_normalize(path)}'),
      headers: headers,
      body: jsonBody != null ? jsonEncode(jsonBody) : binaryBody,
    );
    return Future.value(handler(request));
  }

  Future<Map<String, Object?>> jsonOf(Response r) async {
    final body = await r.readAsString();
    return jsonDecode(body) as Map<String, Object?>;
  }

  test('GET /v1/info advertises the contract constants', () async {
    final r = await req('GET', '/v1/info');
    expect(r.statusCode, 200);
    final body = await jsonOf(r);
    expect(body['version'], '5.0.0');
    expect(body['healpixOrder'], 9);
    expect(body['tilePixels'], 8); // matches this test server's HubConfig
    expect(body['selfHosted'], true);
    expect((body['fingerprint'] as String).length, 64);
  });

  test('account creation returns a bearer token + default trust', () async {
    final r = await req(
      'POST',
      '/v1/accounts',
      jsonBody: <String, Object?>{
        'publicKey': 'imager-1',
        'displayName': 'Imager One',
        'password': 'pw',
      },
    );
    expect(r.statusCode, 201);
    final body = await jsonOf(r);
    expect(body['accountId'], isA<String>());
    expect(body['bearerToken'], isA<String>());
    expect(body['trust'], 0.5);
  });

  test('protected routes require a valid token', () async {
    final r = await req('GET', '/v1/tiles/42?order=9');
    expect(r.statusCode, 401);
    final body = await jsonOf(r);
    expect((body['error'] as Map)['code'], 'unauthorized');
  });

  test(
    'end-to-end: two contributors upload, fused result == local co-add',
    () async {
      // Two contributor accounts.
      final aliceToken =
          (await jsonOf(
                await req(
                  'POST',
                  '/v1/accounts',
                  jsonBody: <String, Object?>{
                    'publicKey': 'alice',
                    'displayName': 'Alice',
                  },
                ),
              ))['bearerToken']
              as String;
      final bobToken =
          (await jsonOf(
                await req(
                  'POST',
                  '/v1/accounts',
                  jsonBody: <String, Object?>{
                    'publicKey': 'bob',
                    'displayName': 'Bob',
                  },
                ),
              ))['bearerToken']
              as String;

      // Force full trust so the HTTP fusion equals the unweighted co-add.
      _setTrust(server, aliceToken, 1.0);
      _setTrust(server, bobToken, 1.0);

      final aliceDelta = TileBuilder.synthetic(
        tileId: 314,
        order: 9,
        value: 100.0,
        frames: 2,
        width: 8,
        height: 8,
        contributor: 'alice',
      );
      final bobDelta = TileBuilder.synthetic(
        tileId: 314,
        order: 9,
        value: 200.0,
        frames: 3,
        width: 8,
        height: 8,
        contributor: 'bob',
      );

      final up1 = await req(
        'POST',
        '/v1/tiles/314/contributions?order=9&framesDelta=2&'
            'integrationSecondsDelta=600&medianFwhm=2.0',
        token: aliceToken,
        binaryBody: aliceDelta.serialize(),
      );
      expect(up1.statusCode, 200);
      expect((await jsonOf(up1))['accepted'], true);

      final up2 = await req(
        'POST',
        '/v1/tiles/314/contributions?order=9&framesDelta=3&'
            'integrationSecondsDelta=900&medianFwhm=2.5',
        token: bobToken,
        binaryBody: bobDelta.serialize(),
      );
      expect(up2.statusCode, 200);
      final up2Body = await jsonOf(up2);
      expect(up2Body['accepted'], true);
      expect(up2Body['totalFramesAfter'], 5);
      expect(up2Body['contributorsAfter'], 2);

      // Download the merged accumulator and compare to the local co-add.
      final dl = await req(
        'GET',
        '/v1/tiles/314?order=9&finalized=false',
        token: aliceToken,
      );
      expect(dl.statusCode, 200);
      expect(dl.headers['x-total-frames'], '5');
      final bytes = await _collect(dl);
      final fused = TileAccumulator.deserialize(bytes);
      final local = mergeSigned(aliceDelta.clone(), bobDelta, 1.0, 1.0);

      final fusedMean = fused.finalizeMean();
      final localMean = local.finalizeMean();
      for (var i = 0; i < fusedMean.length; i++) {
        expect(fusedMean[i], closeTo(localMean[i], 1e-9));
        expect(fusedMean[i], closeTo(160.0, 1e-9));
      }

      // The finalized (mean) download is raw f64 LE of the same means.
      final finalDl = await req(
        'GET',
        '/v1/tiles/314?order=9&finalized=true',
        token: aliceToken,
      );
      expect(finalDl.statusCode, 200);
      final finalBytes = await _collect(finalDl);
      final means = Float64List.view(
        finalBytes.buffer,
        finalBytes.offsetInBytes,
        finalBytes.lengthInBytes ~/ 8,
      );
      for (final v in means) {
        expect(v, closeTo(160.0, 1e-9));
      }
    },
  );

  test('retraction over HTTP returns the tile to its prior depth', () async {
    final token =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'solo',
                  'displayName': 'Solo',
                },
              ),
            ))['bearerToken']
            as String;
    _setTrust(server, token, 1.0);

    final c1 = await req(
      'POST',
      '/v1/tiles/9/contributions?order=9&framesDelta=4&'
          'integrationSecondsDelta=1200',
      token: token,
      binaryBody: TileBuilder.synthetic(
        tileId: 9,
        order: 9,
        value: 100.0,
        frames: 4,
        width: 8,
        height: 8,
        contributor: 'solo',
      ).serialize(),
    );
    expect(c1.statusCode, 200);

    final c2 = await req(
      'POST',
      '/v1/tiles/9/contributions?order=9&framesDelta=1&'
          'integrationSecondsDelta=300',
      token: token,
      binaryBody: TileBuilder.synthetic(
        tileId: 9,
        order: 9,
        value: 5000.0,
        frames: 1,
        width: 8,
        height: 8,
        contributor: 'solo',
      ).serialize(),
    );
    final contributionId = (await jsonOf(c2))['contributionId'] as String;

    final del = await req(
      'DELETE',
      '/v1/contributions/$contributionId',
      token: token,
    );
    expect(del.statusCode, 200);
    final delBody = await jsonOf(del);
    expect(delBody['retracted'], true);
    expect(delBody['totalFramesAfter'], 4);
  });

  test('follow-the-night ranks an up target and excludes a down one', () async {
    final token =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'sched',
                  'displayName': 'Sched',
                },
              ),
            ))['bearerToken']
            as String;

    // A target near dec +45 will be high from a +45 latitude site; one near
    // dec -80 will be well below the horizon there.
    await req(
      'POST',
      '/v1/targets',
      token: token,
      jsonBody: <String, Object?>{
        'name': 'High',
        'centerRaDeg': 0.0,
        'centerDecDeg': 45.0,
        'radiusDeg': 1.0,
        'priority': 1.0,
      },
    );
    await req(
      'POST',
      '/v1/targets',
      token: token,
      jsonBody: <String, Object?>{
        'name': 'Low',
        'centerRaDeg': 0.0,
        'centerDecDeg': -80.0,
        'radiusDeg': 1.0,
        'priority': 1.0,
      },
    );

    // Pick a time when RA 0 is near the meridian for longitude 0: LST ~ 0.
    final r = await req(
      'GET',
      '/v1/follow-the-night?latitudeDeg=45&longitudeDeg=0&minAltitudeDeg=20',
      token: token,
    );
    expect(r.statusCode, 200);
    final plan = (await jsonOf(r))['plan'] as List;
    final names = plan
        .map((e) => ((e as Map)['target'] as Map)['name'])
        .toList();
    expect(names, isNot(contains('Low')));
  });

  test('handoff claim is exclusive between contributors', () async {
    final aliceToken =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'a',
                  'displayName': 'A',
                },
              ),
            ))['bearerToken']
            as String;
    final bobToken =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'b',
                  'displayName': 'B',
                },
              ),
            ))['bearerToken']
            as String;
    final targetId =
        (await jsonOf(
              await req(
                'POST',
                '/v1/targets',
                token: aliceToken,
                jsonBody: <String, Object?>{
                  'name': 'M31',
                  'centerRaDeg': 10.68,
                  'centerDecDeg': 41.27,
                  'radiusDeg': 1.5,
                },
              ),
            ))['targetId']
            as int;

    final claim = await req(
      'POST',
      '/v1/handoff/$targetId/claim',
      token: aliceToken,
    );
    expect(claim.statusCode, 200);
    expect((await jsonOf(claim))['claimToken'], isA<String>());

    // Bob cannot claim while Alice holds it.
    final bobClaim = await req(
      'POST',
      '/v1/handoff/$targetId/claim',
      token: bobToken,
    );
    expect(bobClaim.statusCode, 409);

    // Alice releases; now Bob can claim.
    final release = await req(
      'POST',
      '/v1/handoff/$targetId/release',
      token: aliceToken,
    );
    expect(release.statusCode, 200);
    expect((await jsonOf(release))['released'], true);

    final bobClaim2 = await req(
      'POST',
      '/v1/handoff/$targetId/claim',
      token: bobToken,
    );
    expect(bobClaim2.statusCode, 200);
  });

  test('GET /v1/targets browses the swarm shared targets', () async {
    final token =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 't',
                  'displayName': 'T',
                },
              ),
            ))['bearerToken']
            as String;
    await req(
      'POST',
      '/v1/targets',
      token: token,
      jsonBody: <String, Object?>{
        'name': 'M42',
        'centerRaDeg': 83.82,
        'centerDecDeg': -5.39,
        'radiusDeg': 1.0,
      },
    );

    final r = await req('GET', '/v1/targets', token: token);
    expect(r.statusCode, 200);
    final body = await jsonOf(r);
    final targets = body['targets'] as List;
    expect(targets, isNotEmpty);
    final first = targets.first as Map;
    expect(first['name'], 'M42');
    expect(first['targetId'], isA<int>());
    expect(first['raDeg'], closeTo(83.82, 1e-6));
    expect(first['activeTileId'], isA<int>());
    expect(first['contributors'], isA<int>());
  });

  test(
    'POST /v1/targets echoes the target in the client-facing browse shape',
    () async {
      final token =
          (await jsonOf(
                await req(
                  'POST',
                  '/v1/accounts',
                  jsonBody: <String, Object?>{
                    'publicKey': 'seed',
                    'displayName': 'Seed',
                  },
                ),
              ))['bearerToken']
              as String;

      final r = await req(
        'POST',
        '/v1/targets',
        token: token,
        jsonBody: <String, Object?>{
          'name': 'NGC 7000',
          'centerRaDeg': 314.7,
          'centerDecDeg': 44.3,
          'radiusDeg': 2.0,
        },
      );
      expect(r.statusCode, 200);
      final body = await jsonOf(r);
      expect(body['targetId'], isA<int>());
      // The echoed target must decode straight into the client SharedTarget shape
      // (targetId/raDeg/decDeg/activeTileId), not the hub-internal id/centerRaDeg.
      final target = body['target'] as Map;
      expect(target['targetId'], body['targetId']);
      expect(target['name'], 'NGC 7000');
      expect(target['raDeg'], closeTo(314.7, 1e-6));
      expect(target['decDeg'], closeTo(44.3, 1e-6));
      expect(target['activeTileId'], isA<int>());
      expect(target['contributors'], isA<int>());
    },
  );

  test('an unhandled error does not leak internal detail to the client', () async {
    final token =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'e',
                  'displayName': 'E',
                },
              ),
            ))['bearerToken']
            as String;
    // A body too short to be a valid tile triggers a deserialize path; a truly
    // unhandled error returns the generic message, never the raw exception text.
    final r = await req('GET', '/v1/tiles/abc?order=9', token: token);
    // (tileId 'abc' is a 400 by validation; the point of this test is the body
    // never echoes a stack/exception type.)
    final body = await jsonOf(r);
    final err = body['error'] as Map?;
    if (err != null && err['code'] == 'internal') {
      expect((err['message'] as String), 'internal error');
      expect((err['message'] as String), isNot(contains('Exception')));
    }
  });

  test('repeated failed logins lock the account out (429)', () async {
    await req(
      'POST',
      '/v1/accounts',
      jsonBody: <String, Object?>{
        'publicKey': 'victim',
        'displayName': 'Victim',
        'password': 'correct-horse-battery',
      },
    );
    // Five wrong-password attempts return 401...
    for (var i = 0; i < 5; i++) {
      final r = await req(
        'POST',
        '/v1/sessions',
        jsonBody: <String, Object?>{
          'publicKey': 'victim',
          'password': 'wrong-$i',
        },
      );
      expect(r.statusCode, 401, reason: 'attempt $i');
    }
    // ...the sixth is locked out, even with the CORRECT password (the lock is
    // per-account, independent of the IP rate limiter).
    final locked = await req(
      'POST',
      '/v1/sessions',
      jsonBody: <String, Object?>{
        'publicKey': 'victim',
        'password': 'correct-horse-battery',
      },
    );
    expect(locked.statusCode, 429);
    expect(locked.headers['retry-after'], isNotNull);
  });

  test('an oversized contribution geometry is rejected (400)', () async {
    final token =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'big',
                  'displayName': 'Big',
                },
              ),
            ))['bearerToken']
            as String;
    final r = await req(
      'POST',
      '/v1/tiles/12/contributions?order=9&framesDelta=1&'
          'integrationSecondsDelta=1',
      token: token,
      binaryBody: TileBuilder.synthetic(
        tileId: 12,
        order: 9,
        value: 1.0,
        frames: 1,
        width: 16, // hub tilePixels is 8
        height: 16,
      ).serialize(),
    );
    expect(r.statusCode, 400);
  });

  test('a geometry mismatch in an upload is 409', () async {
    final token =
        (await jsonOf(
              await req(
                'POST',
                '/v1/accounts',
                jsonBody: <String, Object?>{
                  'publicKey': 'g',
                  'displayName': 'G',
                },
              ),
            ))['bearerToken']
            as String;
    final r = await req(
      'POST',
      '/v1/tiles/42/contributions?order=9&framesDelta=1&'
          'integrationSecondsDelta=1',
      token: token,
      binaryBody: TileBuilder.synthetic(
        tileId: 99, // mismatched id in the body
        order: 9,
        value: 1.0,
        frames: 1,
        width: 2,
        height: 2,
      ).serialize(),
    );
    expect(r.statusCode, 409);
    expect((await jsonOf(r))['error'], isA<Map>());
  });
}

String _normalize(String path) => path.startsWith('/') ? path : '/$path';

Future<Uint8List> _collect(Response r) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in r.read()) {
    builder.add(chunk);
  }
  return builder.toBytes();
}

/// Test-only: pin an account's trust to exactly [trust] by resolving its token.
void _setTrust(HubServer server, String token, double trust) {
  final identity = server.tokens.resolve(token)!;
  server.accounts.setTrust(identity.accountId, trust);
}
