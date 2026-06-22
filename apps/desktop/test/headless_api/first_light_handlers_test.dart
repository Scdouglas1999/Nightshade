import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/first_light_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  group('FirstLightHandlers', () {
    late NightshadeDatabase db;
    late TransientDetectionsDao dao;
    late ProviderContainer container;
    late FirstLightHandlers handlers;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      dao = TransientDetectionsDao(db);
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      handlers = FirstLightHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> seed({
      int? sessionId,
      String kind = 'newSource',
      String? catalogMatch,
      double snr = 18.0,
    }) {
      return dao.insertDetection(
        TransientDetectionsCompanion.insert(
          tileId: 42,
          raDeg: 120.0,
          decDeg: 25.0,
          residualFlux: 1500.0,
          snr: snr,
          fwhm: 2.1,
          eccentricity: 0.1,
          positionAngleDeg: const Value(63.5),
          kind: kind,
          confidence: 0.8,
          sessionId: Value(sessionId),
          catalogMatch: Value(catalogMatch),
        ),
      );
    }

    test(
      'GET candidates returns the persisted detections newest-first',
      () async {
        await seed(kind: 'newSource');
        await seed(kind: 'pointBrightening', catalogMatch: 'Star V=12.3');

        final response = await translateHandlerErrors(
          handlers.handleGetCandidates(
            Request(
              'GET',
              Uri.parse('http://localhost/api/firstlight/candidates'),
            ),
          ),
        );

        expect(response.statusCode, HttpStatus.ok);
        expect(response.headers['content-type'], 'application/json');
        final body = jsonDecode(await response.readAsString()) as Map;
        final candidates = body['candidates'] as List;
        expect(candidates, hasLength(2));
        expect(body['unnamedCount'], 1);
        // Wire shape carries the fields the client reconstructs.
        final first = candidates.first as Map<String, dynamic>;
        expect(first['tileId'], 42);
        expect(first['kind'], isA<String>());
        expect(first['raDeg'], isA<num>());
        // positionAngleDeg must survive the wire so remote clients orient the
        // residual ellipse / streak trail correctly (not silently to 0deg).
        expect(first['positionAngleDeg'], 63.5);
      },
    );

    test('GET candidates scoped to a session filters by sessionId', () async {
      // Detections reference imaging_sessions (FKs are enforced), so seed the
      // sessions first.
      for (final sessionId in [7, 9]) {
        await db
            .into(db.imagingSessions)
            .insert(
              ImagingSessionsCompanion.insert(
                id: Value(sessionId),
                startTime: DateTime.utc(2026, 6, 19, 21),
              ),
            );
      }
      await seed(sessionId: 7);
      await seed(sessionId: 9);

      final response = await translateHandlerErrors(
        handlers.handleGetCandidates(
          Request(
            'GET',
            Uri.parse('http://localhost/api/firstlight/candidates?sessionId=7'),
          ),
        ),
      );

      final body = jsonDecode(await response.readAsString()) as Map;
      final candidates = body['candidates'] as List;
      expect(candidates, hasLength(1));
      expect((candidates.single as Map)['sessionId'], 7);
    });

    test('GET candidates rejects a non-integer sessionId', () async {
      final response = await translateHandlerErrors(
        handlers.handleGetCandidates(
          Request(
            'GET',
            Uri.parse(
              'http://localhost/api/firstlight/candidates?sessionId=abc',
            ),
          ),
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });

    test('POST review marks a detection reviewed', () async {
      final id = await seed();

      final response = await translateHandlerErrors(
        handlers.handleReview(
          Request(
            'POST',
            Uri.parse('http://localhost/api/firstlight/$id/review'),
          ),
          '$id',
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'reviewed');
      expect((body['detection'] as Map)['reviewed'], isTrue);

      final row = await dao.detectionById(id);
      expect(row!.reviewed, isTrue);
      expect(row.dismissed, isFalse);
    });

    test('POST dismiss flags a detection dismissed', () async {
      final id = await seed();

      final response = await translateHandlerErrors(
        handlers.handleDismiss(
          Request(
            'POST',
            Uri.parse('http://localhost/api/firstlight/$id/dismiss'),
          ),
          '$id',
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      final body = jsonDecode(await response.readAsString()) as Map;
      expect(body['status'], 'dismissed');

      final row = await dao.detectionById(id);
      expect(row!.dismissed, isTrue);
      expect(row.reviewed, isTrue);
    });

    test('POST review on a missing id returns 404', () async {
      final response = await translateHandlerErrors(
        handlers.handleReview(
          Request(
            'POST',
            Uri.parse('http://localhost/api/firstlight/9999/review'),
          ),
          '9999',
        ),
      );
      expect(response.statusCode, HttpStatus.notFound);
    });

    test('POST review rejects a non-integer id', () async {
      final response = await translateHandlerErrors(
        handlers.handleReview(
          Request(
            'POST',
            Uri.parse('http://localhost/api/firstlight/nope/review'),
          ),
          'nope',
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
    });
  });
}
