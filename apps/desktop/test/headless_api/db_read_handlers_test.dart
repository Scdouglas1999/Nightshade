// P2-8 — Tests for the read-only DB endpoints surfaced by DbReadHandlers.
//
// One happy-path test per endpoint, plus filter/pagination spot-checks
// so the wire envelope stays stable. In-memory Drift DB keeps the tests
// fast; the DAOs are exercised real, not mocked.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_desktop/headless_api/handlers/db_read_handlers.dart';
import 'package:shelf/shelf.dart';

import 'handler_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DbReadHandlers', () {
    late ProviderContainer container;
    late NightshadeDatabase db;
    late DbReadHandlers handlers;

    setUp(() {
      db = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(db),
        ],
      );
      handlers = DbReadHandlers(container);
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<Map<String, dynamic>> doGet(
      Future<Response> Function(Request) handler,
      String url,
    ) async {
      final response = await translateHandlerErrors(
        handler(Request('GET', Uri.parse(url))),
      );
      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers['content-type'], 'application/json');
      return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    }

    // =====================================================================
    // /api/sequence-runs
    // =====================================================================

    test('GET /api/sequence-runs lists runs with envelope', () async {
      await db.sequenceRunsDao.startRun(
        sequenceId: null,
        sequenceName: 'M31 Imaging',
      );
      await db.sequenceRunsDao.startRun(
        sequenceId: null,
        sequenceName: 'M42 Imaging',
      );

      final body = await doGet(
        handlers.handleListSequenceRuns,
        'http://localhost/api/sequence-runs',
      );

      final items = body['items'] as List;
      expect(items, hasLength(2));
      expect(body['total'], 2);
      // The handler does not specify ordering explicitly; both rows should
      // round-trip with full metadata regardless of order.
      final names = items
          .map((e) => (e as Map)['sequenceName'])
          .whereType<String>()
          .toSet();
      expect(names, containsAll(['M31 Imaging', 'M42 Imaging']));
      final first = items.first as Map;
      expect(first['startedAt'], isA<String>());
      expect(first['status'], isA<String>());
    });

    test('sequence-runs respects ?limit=', () async {
      for (var i = 0; i < 5; i++) {
        await db.sequenceRunsDao.startRun(
          sequenceId: null,
          sequenceName: 'Run #$i',
        );
      }

      final body = await doGet(
        handlers.handleListSequenceRuns,
        'http://localhost/api/sequence-runs?limit=2',
      );

      expect((body['items'] as List), hasLength(2));
      expect(body['total'], 5);
    });

    // =====================================================================
    // /api/notes-journal
    // =====================================================================

    test('GET /api/notes-journal lists observation log entries', () async {
      await db.observationLogsDao.insertLog(
        timestamp: DateTime.utc(2026, 5, 1, 22, 0),
        objectName: 'M31',
        ra: 0.7,
        dec: 41.3,
        notes: 'Hazy sky',
      );

      final body = await doGet(
        handlers.handleListNotesJournal,
        'http://localhost/api/notes-journal',
      );

      final items = body['items'] as List;
      expect(items, hasLength(1));
      final first = items.first as Map;
      expect(first['objectName'], 'M31');
      expect(first['notes'], 'Hazy sky');
      expect(body['total'], 1);
    });

    // =====================================================================
    // /api/guide-rms-history
    // =====================================================================

    test('GET /api/guide-rms-history lists guide-rms samples', () async {
      await db.guideRmsHistoryDao.insertSample(
        GuideRmsHistoryCompanion.insert(
          sessionId: 'session-1',
          mountId: 'mount-1',
          totalRmsArcsec: 0.45,
          sampleCount: 120,
          exposureSeconds: 5.0,
          recordedAt: DateTime.utc(2026, 5, 1, 22, 0),
        ),
      );
      await db.guideRmsHistoryDao.insertSample(
        GuideRmsHistoryCompanion.insert(
          sessionId: 'session-1',
          mountId: 'mount-1',
          totalRmsArcsec: 0.62,
          sampleCount: 240,
          exposureSeconds: 5.0,
          recordedAt: DateTime.utc(2026, 5, 1, 23, 0),
        ),
      );

      final body = await doGet(
        handlers.handleListGuideRmsHistory,
        'http://localhost/api/guide-rms-history',
      );

      expect((body['items'] as List), hasLength(2));
      expect(body['total'], 2);
      final first = (body['items'] as List).first as Map;
      expect(first['mountId'], 'mount-1');
      expect((first['totalRmsArcsec'] as num).toDouble(), inExclusiveRange(0.0, 5.0));
    });

    // =====================================================================
    // /api/polar-alignment-history
    // =====================================================================

    test('GET /api/polar-alignment-history lists alignment runs', () async {
      await db.into(db.polarAlignmentHistory).insert(
            PolarAlignmentHistoryCompanion.insert(
              startedAt: DateTime.utc(2026, 4, 1, 21, 0),
              completedAt: DateTime.utc(2026, 4, 1, 21, 5),
              autoCompleted: const Value(true),
              isNorth: const Value(true),
              initialAzimuthError: 0.0,
              initialAltitudeError: 0.0,
              initialTotalError: 0.0,
              finalAzimuthError: 0.5,
              finalAltitudeError: 0.7,
              finalTotalError: 0.85,
              configJson: '{}',
            ),
          );

      final body = await doGet(
        handlers.handleListPolarAlignmentHistory,
        'http://localhost/api/polar-alignment-history',
      );

      final items = body['items'] as List;
      expect(items, hasLength(1));
      final first = items.first as Map;
      expect(first['autoCompleted'], isTrue);
      expect(first['isNorth'], isTrue);
      expect((first['finalTotalError'] as num).toDouble(), closeTo(0.85, 1e-9));
      expect(body['total'], 1);
    });

    // =====================================================================
    // /api/db/dark-library
    // =====================================================================

    test('GET /api/db/dark-library lists dark frames', () async {
      await db.darkLibraryDao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark1.fits',
          exposureTime: 60.0,
          gain: const Value(100),
          offset: const Value(10),
          temperature: const Value(-10.0),
        ),
      );
      await db.darkLibraryDao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark2.fits',
          exposureTime: 30.0,
          gain: const Value(200),
          offset: const Value(5),
          temperature: const Value(-15.0),
        ),
      );

      final body = await doGet(
        handlers.handleListDarkLibrary,
        'http://localhost/api/db/dark-library',
      );

      expect((body['items'] as List), hasLength(2));
      expect(body['total'], 2);
    });

    test('dark-library respects ?gainMin= filter', () async {
      await db.darkLibraryDao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/g100.fits',
          exposureTime: 60.0,
          gain: const Value(100),
          offset: const Value(10),
        ),
      );
      await db.darkLibraryDao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/g200.fits',
          exposureTime: 60.0,
          gain: const Value(200),
          offset: const Value(10),
        ),
      );

      final body = await doGet(
        handlers.handleListDarkLibrary,
        'http://localhost/api/db/dark-library?gainMin=150',
      );

      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['gain'], 200);
      expect(body['total'], 1);
    });

    // =====================================================================
    // /api/db/flat-history
    // =====================================================================

    test('GET /api/db/flat-history lists flats with filter', () async {
      await db.flatHistoryDao.insertEntry(
        FlatHistoryCompanion.insert(
          filterName: 'L',
          exposureTime: 2.5,
          histogramTarget: 30000.0,
          actualAdu: 31000,
          timestamp: Value(DateTime.utc(2026, 4, 1, 18, 0)),
        ),
      );
      await db.flatHistoryDao.insertEntry(
        FlatHistoryCompanion.insert(
          filterName: 'R',
          exposureTime: 4.0,
          histogramTarget: 30000.0,
          actualAdu: 29500,
          timestamp: Value(DateTime.utc(2026, 4, 1, 18, 5)),
        ),
      );

      final body = await doGet(
        handlers.handleListFlatHistory,
        'http://localhost/api/db/flat-history?filterName=L',
      );

      final items = body['items'] as List;
      expect(items, hasLength(1));
      expect((items.first as Map)['filterName'], 'L');
      expect(body['total'], 1);
    });
  });
}
