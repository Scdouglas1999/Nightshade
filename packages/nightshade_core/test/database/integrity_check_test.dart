import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/integrity_check.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ns_integrity_test_');
    dbFile = File(p.join(tempDir.path, 'nightshade.db'));
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      // Why best-effort: WAL/SHM file handles can briefly outlive a
      // failed test on Windows; we don't want one leftover handle to
      // poison the next test run with a hard delete failure.
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Tolerable — the temp dir cleaner will sweep this on reboot.
      }
    }
  });

  group('runIntegrityCheckAndRecover', () {
    test('reports freshInstall when DB file does not exist', () async {
      // No file on disk yet. This is the canonical first-launch path —
      // nothing to check, nothing to recover, but we must distinguish it
      // from a "checked clean" case so callers can log appropriately.
      final report = await runIntegrityCheckAndRecover(dbFile);

      expect(report.freshInstall, isTrue);
      expect(report.wasHealthy, isFalse);
      expect(report.recovered, isFalse);
      expect(report.backupPath, isNull);
      expect(report.markerPath, isNull);
    });

    test(
      'reports healthy when integrity_check returns ok on a fresh DB',
      () async {
        // Create a real, valid sqlite3 database file. We pre-seed it with a
        // single table + row so the file has meaningful pages, which makes
        // the integrity check work harder than on an empty file.
        final db = sqlite3.open(dbFile.path);
        db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);');
        db.execute("INSERT INTO t (name) VALUES ('hello');");
        db.close();

        final report = await runIntegrityCheckAndRecover(dbFile);

        expect(report.wasHealthy, isTrue);
        expect(report.freshInstall, isFalse);
        expect(report.recovered, isFalse);
        // The original file must remain in place untouched.
        expect(await dbFile.exists(), isTrue);
        // No backup or marker should have been written on a clean check.
        final entries = await tempDir.list().toList();
        expect(entries.length, equals(1));
        expect(p.basename(entries.first.path), equals('nightshade.db'));
      },
    );

    test('corrupt DB triggers recovery: backup retained, marker written, '
        'original file rotated', () async {
      // Fabricate a corrupt SQLite file by writing a header-shaped blob
      // that is NOT a valid database. sqlite3.open will either fail with
      // SQLITE_NOTADB or open and have integrity_check report disk image
      // malformation — either path must end in the same recovery outcome.
      //
      // We intentionally use a length and prefix that imitate a real
      // SQLite header so we exercise the integrity_check failure branch
      // and the open-time-exception branch in a single test run. The
      // first 16 bytes are the SQLite magic string; everything after is
      // garbage that the page parser cannot make sense of.
      final magic = 'SQLite format 3\x00'.codeUnits;
      final junk = Uint8List(4096);
      for (var i = magic.length; i < junk.length; i++) {
        junk[i] = (i * 13) & 0xff;
      }
      for (var i = 0; i < magic.length; i++) {
        junk[i] = magic[i];
      }
      await dbFile.writeAsBytes(junk, flush: true);

      final report = await runIntegrityCheckAndRecover(dbFile);

      expect(
        report.recovered,
        isTrue,
        reason:
            'A corrupt file must be detected and rotated. '
            'wasHealthy=${report.wasHealthy} freshInstall=${report.freshInstall} '
            'failureReason=${report.failureReason}',
      );
      expect(report.freshInstall, isFalse);
      expect(report.wasHealthy, isFalse);
      expect(report.backupPath, isNotNull);
      expect(report.markerPath, isNotNull);
      expect(report.failureReason, isNotNull);

      // The original DB file must no longer exist (drift's onCreate will
      // recreate it on next open) ...
      expect(
        await dbFile.exists(),
        isFalse,
        reason: 'Corrupt file should be rotated, not left in place.',
      );

      // ... and the backup must still be there so support can extract data.
      final backup = File(report.backupPath!);
      expect(await backup.exists(), isTrue);
      expect(p.basename(backup.path), startsWith('nightshade-corrupt-'));

      // The marker file is what the UI hook reads on next launch.
      final marker = File(report.markerPath!);
      expect(await marker.exists(), isTrue);
      final markerContent = await marker.readAsString();
      expect(markerContent, contains('db_path='));
      expect(markerContent, contains('recovered_at_utc='));
      expect(markerContent, contains('reason='));
    });

    test(
      'integrity_check failure with valid-but-damaged DB also recovers',
      () async {
        // Create a real SQLite file, then truncate it mid-page so the
        // header survives (sqlite3.open succeeds) but page-level
        // integrity_check reports malformation. This exercises the
        // "open succeeds, integrity_check fails" branch specifically.
        final db = sqlite3.open(dbFile.path);
        db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, blob BLOB);');
        // Insert a row big enough to span multiple pages.
        final big = Uint8List(64 * 1024);
        for (var i = 0; i < big.length; i++) {
          big[i] = i & 0xff;
        }
        final stmt = db.prepare('INSERT INTO t (blob) VALUES (?);');
        stmt.execute([big]);
        stmt.close();
        db.close();

        // Truncate to the first 8KB. SQLite's first page is intact (4 KB
        // default page size) so the open succeeds, but the second page
        // referenced by the overflow chain is now gone.
        final bytes = await dbFile.readAsBytes();
        await dbFile.writeAsBytes(bytes.sublist(0, 8192), flush: true);

        final report = await runIntegrityCheckAndRecover(dbFile);

        // The recovery path must trigger regardless of which sub-branch
        // (open-time exception vs. failed integrity_check) actually caught
        // the corruption.
        expect(
          report.recovered,
          isTrue,
          reason:
              'A truncated DB must trigger recovery. '
              'failureReason=${report.failureReason}',
        );
        expect(await File(report.backupPath!).exists(), isTrue);
        expect(await File(report.markerPath!).exists(), isTrue);
      },
    );

    test('WAL companion files are rotated alongside the main DB', () async {
      // Hand-place a corrupt main file plus a synthetic -wal / -shm pair
      // so we can deterministically verify the rotation step without
      // depending on sqlite3's checkpoint timing (the WAL files are
      // sometimes collapsed back into the main file before dispose()
      // returns, which would make this test flaky).
      await dbFile.writeAsBytes(Uint8List(4096), flush: true);
      final walFile = File('${dbFile.path}-wal');
      final shmFile = File('${dbFile.path}-shm');
      await walFile.writeAsBytes(Uint8List(1024), flush: true);
      await shmFile.writeAsBytes(Uint8List(32 * 1024), flush: true);

      final report = await runIntegrityCheckAndRecover(dbFile);
      expect(report.recovered, isTrue);

      // The main DB file must be gone (rotated) ...
      expect(await dbFile.exists(), isFalse);
      // ... and any -wal / -shm files that existed before recovery must
      // also be gone, otherwise a fresh drift open would replay them.
      expect(
        await walFile.exists(),
        isFalse,
        reason: '-wal sidecar must be rotated alongside the main file.',
      );
      expect(
        await shmFile.exists(),
        isFalse,
        reason: '-shm sidecar must be rotated alongside the main file.',
      );

      // The companion backups must be co-located with the main backup
      // so support can grab everything in one folder. We don't assert on
      // exact filenames (timestamp-dependent) but on the count.
      final companionBackups = await tempDir
          .list()
          .where(
            (e) =>
                e is File &&
                (p.basename(e.path).endsWith('-wal') ||
                    p.basename(e.path).endsWith('-shm')),
          )
          .toList();
      expect(
        companionBackups.length,
        equals(2),
        reason: 'Both -wal and -shm should have been rotated to backups.',
      );
    });
  });

  group('consumeRecoveryMarker', () {
    test('returns null when no marker file is present', () async {
      // Sanity: a clean directory with no recovery history must not
      // surface a phantom marker to the UI.
      final marker = await consumeRecoveryMarker(tempDir);
      expect(marker, isNull);
    });

    test('returns null when directory does not exist', () async {
      final ghost = Directory(p.join(tempDir.path, 'no-such-dir'));
      final marker = await consumeRecoveryMarker(ghost);
      expect(marker, isNull);
    });

    test('consumes and clears the marker after recovery', () async {
      // Stage a corrupt DB and run recovery so a real marker is on disk.
      await dbFile.writeAsBytes(Uint8List(4096), flush: true);
      final report = await runIntegrityCheckAndRecover(dbFile);
      expect(report.recovered, isTrue);

      final marker = await consumeRecoveryMarker(tempDir);
      expect(marker, isNotNull);
      expect(marker!.backupPath, equals(report.backupPath));
      expect(marker.reason, isNotNull);

      // The marker file must be unlinked after the first read — the
      // dialog must be one-shot across app launches.
      final secondRead = await consumeRecoveryMarker(tempDir);
      expect(
        secondRead,
        isNull,
        reason: 'Marker should be cleared after first consumption.',
      );
    });

    test('clears every marker when multiple are present', () async {
      // Two recoveries happened without the UI ever surfacing the
      // dialog (e.g. headless boot). Both markers exist on disk; only
      // the newest is reported and BOTH are cleared so the user does
      // not see two cascading dialogs on the next launch.
      await dbFile.writeAsBytes(Uint8List(4096), flush: true);
      await runIntegrityCheckAndRecover(dbFile);

      // Create a synthetic older marker with a hand-rolled filename so
      // we don't have to wait for a millisecond-resolution clock tick.
      final olderPath = p.join(tempDir.path, '.recovered-on-100.txt');
      await File(olderPath).writeAsString(
        'db_path=${dbFile.path}\n'
        'recovered_at_utc=1970-01-01T00:00:00.100Z\n'
        'reason=older synthetic marker\n',
      );

      final marker = await consumeRecoveryMarker(tempDir);
      expect(marker, isNotNull);
      // No markers should remain in the directory after consumption.
      final remaining = await tempDir
          .list()
          .where(
            (e) => e is File && p.basename(e.path).startsWith('.recovered-on-'),
          )
          .toList();
      expect(
        remaining,
        isEmpty,
        reason: 'All recovery markers must be cleared on consume.',
      );
    });

    test('two-phase read preserves the marker until acknowledgement', () async {
      await dbFile.writeAsBytes(Uint8List(4096), flush: true);
      await runIntegrityCheckAndRecover(dbFile);

      final marker = await readRecoveryMarker(tempDir);
      expect(marker, isNotNull);
      expect(await readRecoveryMarker(tempDir), isNotNull);

      await acknowledgeRecoveryMarker(tempDir, marker!);
      expect(await readRecoveryMarker(tempDir), isNull);
    });
  });
}
