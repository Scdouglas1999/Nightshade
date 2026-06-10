// P2-9 — Round-trip tests for the broadened backup-service coverage.
//
// Two newly-included tables (dark_library + notes_journal/observation_logs)
// are written into an in-memory database, backed up to disk, then restored
// into a fresh database and verified row-for-row. The test covers the
// idempotency guarantee too: re-running the restore against a populated
// destination must not duplicate rows.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;

/// Test-only LoggingService that skips native init. The defaults inject
/// no-op callbacks so the FFI is never touched; `ensureInitialized` still
/// resolves quickly because the `applicationSupportDirectoryProvider` we
/// pass returns the system temp dir.
LoggingService _testLogger(Directory tempDir) {
  return LoggingService(
    applicationSupportDirectoryProvider: () async => tempDir,
    nativeInitWithLogging: ({String? logDirectory}) {},
    nativeInit: () {},
    currentLogFileProvider: () => null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupService P2-9 extended coverage', () {
    late NightshadeDatabase srcDb;
    late NightshadeDatabase dstDb;
    late Directory tempDir;
    late LoggingService logger;

    setUp(() async {
      srcDb = NightshadeDatabase.forTesting(NativeDatabase.memory());
      dstDb = NightshadeDatabase.forTesting(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('ns_backup_ext_test_');
      logger = _testLogger(tempDir);
    });

    tearDown(() async {
      await srcDb.close();
      await dstDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    BackupService serviceFor(NightshadeDatabase db) => BackupService(
      database: db,
      sequenceRepository: SequenceRepository(db.sequencesDao),
      logger: logger,
    );

    test(
      'dark_library + notes_journal round-trip through backup/restore',
      () async {
        // Seed two tables that the legacy backup did NOT cover so the round
        // trip exercises the new P2-9 code path specifically.
        await srcDb.darkLibraryDao.addEntry(
          DarkLibraryCompanion.insert(
            filePath: '/tmp/dark1.fits',
            exposureTime: 60.0,
            gain: const Value(100),
            offset: const Value(10),
            temperature: const Value(-10.0),
            binX: const Value(1),
            binY: const Value(1),
          ),
        );
        await srcDb.darkLibraryDao.addEntry(
          DarkLibraryCompanion.insert(
            filePath: '/tmp/dark2.fits',
            exposureTime: 30.0,
            gain: const Value(200),
            offset: const Value(5),
            temperature: const Value(-15.0),
          ),
        );
        await srcDb.observationLogsDao.insertLog(
          timestamp: DateTime.utc(2026, 4, 1, 22, 0),
          objectName: 'M31',
          ra: 0.7,
          dec: 41.3,
          notes: 'Hazy sky',
        );
        await srcDb.observationLogsDao.insertLog(
          timestamp: DateTime.utc(2026, 4, 2, 22, 0),
          objectName: 'M42',
          ra: 5.6,
          dec: -5.4,
          notes: 'Crisp Orion',
        );

        // Backup
        final backupFile = File(p.join(tempDir.path, 'backup.nsbackup'));
        final backupResult = await serviceFor(
          srcDb,
        ).createBackup(customPath: backupFile.path);
        expect(backupResult.success, isTrue, reason: backupResult.errorMessage);
        expect(await backupFile.exists(), isTrue);

        // Restore into a fresh DB.
        final restore = await serviceFor(
          dstDb,
        ).restoreBackup(filePath: backupFile.path);
        expect(restore.success, isTrue, reason: restore.errorMessage);
        expect(restore.categoryCounts['darkLibrary'], 2);
        expect(restore.categoryCounts['notesJournal'], 2);

        // Verify row content survived end-to-end.
        final darks = await dstDb.darkLibraryDao.getAllEntries();
        expect(darks, hasLength(2));
        final paths = darks.map((d) => d.filePath).toSet();
        expect(paths, containsAll(['/tmp/dark1.fits', '/tmp/dark2.fits']));

        final logs = await dstDb.observationLogsDao.getAllLogs();
        expect(logs, hasLength(2));
        final names = logs.map((l) => l.objectName).toSet();
        expect(names, containsAll(['M31', 'M42']));
      },
    );

    test('second restore is idempotent (no row duplication)', () async {
      await srcDb.darkLibraryDao.addEntry(
        DarkLibraryCompanion.insert(
          filePath: '/tmp/dark1.fits',
          exposureTime: 60.0,
          gain: const Value(100),
          offset: const Value(10),
        ),
      );
      await srcDb.observationLogsDao.insertLog(
        timestamp: DateTime.utc(2026, 4, 1, 22, 0),
        objectName: 'M31',
        ra: 0.7,
        dec: 41.3,
      );

      final backupFile = File(p.join(tempDir.path, 'backup.nsbackup'));
      final backupResult = await serviceFor(
        srcDb,
      ).createBackup(customPath: backupFile.path);
      expect(backupResult.success, isTrue, reason: backupResult.errorMessage);

      // First restore populates dst.
      final first = await serviceFor(
        dstDb,
      ).restoreBackup(filePath: backupFile.path);
      expect(first.success, isTrue, reason: first.errorMessage);

      // Second restore must NOT double the row counts. InsertMode.insertOrIgnore
      // means the existing primary keys conflict and the new rows are silently
      // dropped — which is exactly what we want so a panicked operator can
      // re-run a restore without destroying data.
      final second = await serviceFor(
        dstDb,
      ).restoreBackup(filePath: backupFile.path);
      expect(second.success, isTrue);

      final darks = await dstDb.darkLibraryDao.getAllEntries();
      expect(darks, hasLength(1), reason: 'restore must be idempotent');

      final logs = await dstDb.observationLogsDao.getAllLogs();
      expect(logs, hasLength(1), reason: 'restore must be idempotent');
    });

    test('backup format version is bumped (P2-9)', () {
      expect(BackupService.backupVersion, '2.1');
    });
  });
}
