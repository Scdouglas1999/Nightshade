import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/stacked_results_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/imaging/stack_and_share_models.dart';
import 'package:nightshade_core/src/services/live_stacking_service.dart';

/// Round-trip tests for [StackedResultsDao] (Stack-and-Share Loop, C3) against
/// a fresh in-memory database. The DAO is exercised end-to-end:
/// insert → read (by session + recent) → update exported path → delete.
///
/// The `stacked_results` table is created by the v38 raw-DDL migration which
/// `NightshadeDatabase.forTesting` runs through `onCreate`, so no manual table
/// setup is required here.
void main() {
  late NightshadeDatabase db;
  late StackedResultsDao dao;

  /// A fixed UTC creation instant truncated to whole seconds, because the table
  /// stores epoch seconds and the DAO round-trips through that resolution.
  final createdAt = DateTime.utc(2026, 3, 14, 21, 47, 30);

  StackAndShareResult sample({
    int? sessionId = 42,
    int? targetId = 7,
    String? targetName = 'M51',
    int width = 4144,
    int height = 2822,
    int framesStacked = 38,
    int framesAttempted = 40,
    double integrationSecs = 4560,
    double avgAlignmentResidual = 0.42,
    double? avgHfr = 2.31,
    String? filter = 'L',
    String? exportedImagePath,
    DateTime? when,
  }) {
    return StackAndShareResult(
      sessionId: sessionId,
      targetId: targetId,
      targetName: targetName,
      width: width,
      height: height,
      framesStacked: framesStacked,
      framesAttempted: framesAttempted,
      integrationSecs: integrationSecs,
      avgAlignmentResidual: avgAlignmentResidual,
      avgHfr: avgHfr,
      filter: filter,
      exportedImagePath: exportedImagePath,
      createdAt: when ?? createdAt,
      stats: LiveStackingStats(
        stackedFrameCount: framesStacked,
        totalFramesAttempted: framesAttempted,
        avgAlignmentResidual: avgAlignmentResidual,
      ),
    );
  }

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    dao = StackedResultsDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('StackedResultsDao insert + read', () {
    test('insert returns a positive row id and round-trips every field',
        () async {
      final id = await dao.insertResult(sample());
      expect(id, greaterThan(0));

      final rows = await dao.getResultsForSession(42);
      expect(rows, hasLength(1));
      final read = rows.single;

      expect(read.id, id);
      expect(read.sessionId, 42);
      expect(read.targetId, 7);
      expect(read.targetName, 'M51');
      expect(read.width, 4144);
      expect(read.height, 2822);
      expect(read.framesStacked, 38);
      expect(read.framesAttempted, 40);
      expect(read.integrationSecs, 4560);
      expect(read.avgAlignmentResidual, closeTo(0.42, 1e-9));
      expect(read.avgHfr, closeTo(2.31, 1e-9));
      expect(read.filter, 'L');
      expect(read.exportedImagePath, isNull);
      // Stored as epoch seconds (UTC); the model round-trips to a UTC instant.
      expect(read.createdAt.toUtc(), createdAt);
      // The reconstructed stats carry only the persisted aggregate columns.
      expect(read.stats.stackedFrameCount, 38);
      expect(read.stats.totalFramesAttempted, 40);
      expect(read.stats.avgAlignmentResidual, closeTo(0.42, 1e-9));
    });

    test('persists nullable columns as null', () async {
      await dao.insertResult(sample(
        sessionId: null,
        targetId: null,
        targetName: null,
        avgHfr: null,
        filter: null,
      ));

      final rows = await dao.getRecentResults();
      expect(rows, hasLength(1));
      final read = rows.single;
      expect(read.sessionId, isNull);
      expect(read.targetId, isNull);
      expect(read.targetName, isNull);
      expect(read.avgHfr, isNull);
      expect(read.filter, isNull);
      // avg_alignment_residual is non-null here; verify it survives the trip.
      expect(read.avgAlignmentResidual, closeTo(0.42, 1e-9));
    });

    test('getResultsForSession scopes to the session and orders newest-first',
        () async {
      await dao.insertResult(sample(
        sessionId: 1,
        when: DateTime.utc(2026, 1, 1, 0, 0, 0),
        targetName: 'older',
      ));
      await dao.insertResult(sample(
        sessionId: 1,
        when: DateTime.utc(2026, 1, 2, 0, 0, 0),
        targetName: 'newer',
      ));
      await dao.insertResult(sample(sessionId: 2, targetName: 'other-session'));

      final session1 = await dao.getResultsForSession(1);
      expect(session1.map((r) => r.targetName), ['newer', 'older']);

      final session2 = await dao.getResultsForSession(2);
      expect(session2.single.targetName, 'other-session');

      expect(await dao.getResultsForSession(999), isEmpty);
    });

    test('getRecentResults returns newest-first and honours the limit',
        () async {
      for (var day = 1; day <= 5; day++) {
        await dao.insertResult(sample(
          sessionId: day,
          targetName: 'day$day',
          when: DateTime.utc(2026, 2, day, 0, 0, 0),
        ));
      }

      final recent = await dao.getRecentResults(limit: 3);
      expect(recent.map((r) => r.targetName), ['day5', 'day4', 'day3']);
    });

    test('getRecentResults rejects a non-positive limit', () async {
      expect(() => dao.getRecentResults(limit: 0), throwsArgumentError);
      expect(() => dao.getRecentResults(limit: -5), throwsArgumentError);
    });
  });

  group('StackedResultsDao update + delete', () {
    test('updateExportedPath stamps the path and returns the affected count',
        () async {
      final id = await dao.insertResult(sample());

      final updated = await dao.updateExportedPath(id, '/exports/m51.png');
      expect(updated, 1);

      final read = (await dao.getResultsForSession(42)).single;
      expect(read.exportedImagePath, '/exports/m51.png');
    });

    test('updateExportedPath returns 0 for a stale id and changes nothing',
        () async {
      final id = await dao.insertResult(sample());

      final updated = await dao.updateExportedPath(999999, '/nope.png');
      expect(updated, 0);

      // The real row is untouched.
      final read = (await dao.getResultsForSession(42)).single;
      expect(read.id, id);
      expect(read.exportedImagePath, isNull);
    });

    test('deleteResult removes the row and returns the affected count',
        () async {
      final id = await dao.insertResult(sample());
      expect(await dao.getResultsForSession(42), hasLength(1));

      final deleted = await dao.deleteResult(id);
      expect(deleted, 1);
      expect(await dao.getResultsForSession(42), isEmpty);
    });

    test('deleteResult returns 0 for a missing id', () async {
      await dao.insertResult(sample());
      final deleted = await dao.deleteResult(123456);
      expect(deleted, 0);
      // The existing row is still present.
      expect(await dao.getResultsForSession(42), hasLength(1));
    });

    test('full lifecycle: insert, update, then delete', () async {
      final id = await dao.insertResult(sample(exportedImagePath: null));

      // Stamp the export path after the share step runs.
      expect(await dao.updateExportedPath(id, '/exports/final.jpg'), 1);
      final afterUpdate = (await dao.getRecentResults()).single;
      expect(afterUpdate.id, id);
      expect(afterUpdate.exportedImagePath, '/exports/final.jpg');

      // Delete it and confirm both read paths agree it is gone.
      expect(await dao.deleteResult(id), 1);
      expect(await dao.getRecentResults(), isEmpty);
      expect(await dao.getResultsForSession(42), isEmpty);
    });
  });

  group('StackedResultsDao storage semantics', () {
    test('created_at is stored as UTC epoch seconds', () async {
      // A local-time instant should round-trip to the same absolute moment.
      final localWhen = DateTime(2026, 7, 4, 13, 30, 15);
      final id = await dao.insertResult(sample(when: localWhen));

      final stored = await db.customSelect(
        'SELECT created_at FROM stacked_results WHERE id = ?',
        variables: [Variable<int>(id)],
      ).getSingle();
      final epochSeconds = stored.read<int>('created_at');
      expect(epochSeconds, localWhen.toUtc().millisecondsSinceEpoch ~/ 1000);

      final read = (await dao.getRecentResults()).single;
      expect(
        read.createdAt.millisecondsSinceEpoch,
        localWhen.millisecondsSinceEpoch ~/ 1000 * 1000,
      );
    });
  });
}
