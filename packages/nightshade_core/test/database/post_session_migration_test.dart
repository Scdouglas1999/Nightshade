// Migration round-trip test for the v40 -> v41 step (Post-Session Integration).
//
// Verifies that upgrading a pre-v41 (v40) database creates the three new
// raw-DDL tables (`integrated_masters`, `integrated_master_frames`,
// `flat_library`) with their indexes, that a master + fold record + flat entry
// round-trips through the DAOs after the upgrade, and that re-running the v41
// migration block is idempotent (no throw).
//
// Strategy mirrors `project_migration_test.dart`:
//   1. Open a fresh on-disk DB at v41 via onCreate (lands the full schema).
//   2. Simulate the pre-v41 (v40) state: DROP the three new tables and rewind
//      `PRAGMA user_version = 40`.
//   3. Reopen — triggers onUpgrade(40, 41), which runs `_createPostSessionTables()`.
//   4. Assert the tables + indexes exist and round-trip data.

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/daos/flat_library_dao.dart';
import 'package:nightshade_core/src/database/daos/integrated_masters_dao.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/imaging/integrated_master.dart';

void main() {
  group('migration onUpgrade v40 -> v41 (post-session integration)', () {
    Future<File> createV40Database(Directory dir) async {
      final dbFile = File('${dir.path}/nightshade.db');
      final setupDb = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
      try {
        await setupDb
            .customStatement('DROP TABLE IF EXISTS integrated_master_frames');
        await setupDb.customStatement('DROP TABLE IF EXISTS integrated_masters');
        await setupDb.customStatement('DROP TABLE IF EXISTS flat_library');
        await setupDb.customStatement('PRAGMA user_version = 40');
      } finally {
        await setupDb.close();
      }
      return dbFile;
    }

    Future<Set<String>> tableNames(NightshadeDatabase db) async {
      final rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
          .get();
      return rows.map((r) => r.read<String>('name')).toSet();
    }

    test('creates the three tables + indexes on upgrade', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('nightshade_v40_v41_create_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final dbFile = await createV40Database(tempDir);

      final upgraded = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
      try {
        final names = await tableNames(upgraded);
        expect(names, contains('integrated_masters'));
        expect(names, contains('integrated_master_frames'));
        expect(names, contains('flat_library'));

        final indexes = await upgraded
            .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
            .get();
        final indexNames = indexes.map((r) => r.read<String>('name')).toSet();
        expect(indexNames, contains('idx_integrated_masters_target'));
        expect(indexNames, contains('idx_integrated_master_frames_master'));
        expect(indexNames, contains('idx_flat_library_match'));
      } finally {
        await upgraded.close();
      }
    });

    test('a master + fold record + flat round-trips after the upgrade',
        () async {
      final tempDir = await Directory.systemTemp
          .createTemp('nightshade_v40_v41_roundtrip_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final dbFile = await createV40Database(tempDir);

      final upgraded = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
      try {
        final mastersDao = IntegratedMastersDao(upgraded);
        final flatDao = FlatLibraryDao(upgraded);

        // A captured sub to fold (FK target of integrated_master_frames).
        final imageId = await upgraded.customInsert(
          'INSERT INTO captured_images '
          '(file_path, file_name, frame_type, exposure_duration, captured_at) '
          'VALUES (?, ?, ?, ?, ?)',
          variables: [
            Variable.withString('/l/a.fits'),
            Variable.withString('a.fits'),
            Variable.withString('light'),
            Variable.withReal(120.0),
            Variable.withInt(
                DateTime.utc(2026, 6, 7).millisecondsSinceEpoch ~/ 1000),
          ],
        );

        final masterId = await mastersDao.insertMaster(
          name: 'M51 · L',
          status: IntegratedMasterStatus.finalized,
          accumulationMode: AccumulationMode.batch,
          masterFitsPath: '/out/m51.fits',
          frameCount: 1,
          filter: 'L',
        );
        expect(masterId, greaterThan(0));

        await mastersDao.recordFoldedFrame(
          masterId: masterId,
          imageId: imageId,
          weight: 1.0,
          accepted: true,
        );
        final folded = await mastersDao.getFoldedImageIds(masterId);
        expect(folded, {imageId});

        // The dedup UNIQUE(master_id, image_id) makes a re-fold a no-op upsert.
        await mastersDao.recordFoldedFrame(
            masterId: masterId, imageId: imageId, weight: 0.5);
        expect((await mastersDao.getFramesForMaster(masterId)), hasLength(1));

        final flatId = await flatDao.addEntry(
          filePath: '/cal/flat_L.fits',
          filter: 'L',
          masterFrameCount: 25,
        );
        final flat = await flatDao.getEntryById(flatId);
        expect(flat, isNotNull);
        expect(flat!.filter, 'L');
      } finally {
        await upgraded.close();
      }
    });

    test('re-running the v41 migration block is idempotent', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('nightshade_v40_v41_idem_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      final dbFile = await createV40Database(tempDir);

      // First open performs the upgrade.
      final first = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
      await first.customSelect('SELECT 1').get();
      await first.close();

      // Rewind to v40 again and reopen — the helper must not throw on
      // already-existing tables (every statement is IF NOT EXISTS).
      final rewind = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
      await rewind.customStatement('PRAGMA user_version = 40');
      await rewind.close();

      final second = NightshadeDatabase.forTesting(NativeDatabase(dbFile));
      try {
        final names = await (second
            .customSelect("SELECT name FROM sqlite_master WHERE type='table'")
            .get());
        final set = names.map((r) => r.read<String>('name')).toSet();
        expect(set, contains('integrated_masters'));
        expect(set, contains('flat_library'));
      } finally {
        await second.close();
      }
    });
  });
}
