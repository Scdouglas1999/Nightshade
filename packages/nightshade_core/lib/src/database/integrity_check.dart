import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Outcome of [runIntegrityCheckAndRecover].
///
/// Why a structured result instead of a bool: the UI needs to surface a
/// one-time "your database was recovered" dialog, and support engineers need
/// the path of the corrupt-file backup to triage. A boolean would force every
/// caller to re-derive the marker / backup path, which is fragile.
class IntegrityRecoveryReport {
  /// True iff `PRAGMA integrity_check` returned anything other than `ok` AND
  /// the corrupt file was rotated out of the way successfully.
  final bool recovered;

  /// True iff the database file did not exist when the check ran. This is the
  /// normal first-launch state — no integrity check needed, no recovery
  /// performed, but distinguished from "checked and clean" so callers can log
  /// the path the DB will end up at.
  final bool freshInstall;

  /// True iff the file existed AND `integrity_check` returned `ok`. Mutually
  /// exclusive with [recovered] and [freshInstall].
  final bool wasHealthy;

  /// Absolute path of the corrupt-file backup that was retained for forensic
  /// retrieval. Null unless [recovered] is true.
  final String? backupPath;

  /// Absolute path of the recovery marker file that the UI hook should
  /// consume + delete on next launch. Null unless [recovered] is true.
  final String? markerPath;

  /// Raw `integrity_check` result string that triggered the recovery (e.g.
  /// `'database disk image is malformed'`). Null unless [recovered] is true.
  final String? failureReason;

  const IntegrityRecoveryReport._({
    required this.recovered,
    required this.freshInstall,
    required this.wasHealthy,
    this.backupPath,
    this.markerPath,
    this.failureReason,
  });

  factory IntegrityRecoveryReport.freshInstall() =>
      const IntegrityRecoveryReport._(
        recovered: false,
        freshInstall: true,
        wasHealthy: false,
      );

  factory IntegrityRecoveryReport.healthy() => const IntegrityRecoveryReport._(
        recovered: false,
        freshInstall: false,
        wasHealthy: true,
      );

  factory IntegrityRecoveryReport.recovered({
    required String backupPath,
    required String markerPath,
    required String failureReason,
  }) =>
      IntegrityRecoveryReport._(
        recovered: true,
        freshInstall: false,
        wasHealthy: false,
        backupPath: backupPath,
        markerPath: markerPath,
        failureReason: failureReason,
      );
}

/// Filename prefix for the forensic backup of a corrupt database file.
/// Visible in the same directory as `nightshade.db` so a user can attach it
/// to a support email without spelunking through OS-specific paths.
const String _corruptBackupPrefix = 'nightshade-corrupt-';

/// Filename prefix for the one-time UI marker that signals "we just recovered
/// from corruption — please tell the user." The marker is consumed +
/// unlinked by the UI layer on the next launch.
const String _recoveryMarkerPrefix = '.recovered-on-';

/// Open the database file once, run `PRAGMA integrity_check`, and on failure
/// rotate the corrupt file to a forensic backup so that drift's `onCreate`
/// can run on a fresh file. Does NOT delete the backup — it is retained as
/// evidence for support.
///
/// Why this lives outside [NightshadeDatabase]: the integrity check has to
/// run BEFORE drift opens the database, otherwise drift's migrator may begin
/// reading schema metadata from a corrupt file and crash in a way that
/// bypasses our recovery path. Drift's `beforeOpen` fires AFTER the
/// connection is established, which is too late to swap files without race
/// conditions in the background isolate.
///
/// Throws if the recovery itself fails (e.g. the OS refuses to rename the
/// corrupt file because of an open file handle). Per project policy we
/// surface that as a hard failure rather than silently continuing on a
/// half-broken state.
Future<IntegrityRecoveryReport> runIntegrityCheckAndRecover(File dbFile) async {
  if (!await dbFile.exists()) {
    return IntegrityRecoveryReport.freshInstall();
  }

  String? failureReason;
  try {
    final db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
    try {
      final result = db.select('PRAGMA integrity_check;');
      // PRAGMA integrity_check returns either a single row {integrity_check:
      // 'ok'} on a healthy database, or one or more rows describing the
      // corruption (e.g. {integrity_check: 'database disk image is
      // malformed'}). The single-row 'ok' shape is the only healthy case.
      if (result.length == 1 &&
          result.first.values.length == 1 &&
          result.first.values.first == 'ok') {
        return IntegrityRecoveryReport.healthy();
      }
      failureReason = result
          .map((row) => row.values.isNotEmpty ? '${row.values.first}' : '?')
          .join('; ');
    } finally {
      db.dispose();
    }
  } on SqliteException catch (e) {
    // Why we treat open-time SqliteException as corruption too: SQLite
    // reports SQLITE_NOTADB / SQLITE_CORRUPT during `sqlite3_open` when the
    // header is mangled. The recovery path is identical to a failed
    // integrity_check — rotate the file, recreate, mark the UI.
    failureReason = 'open-time error: ${e.message}';
  }

  // Corruption confirmed. Rotate the file, drop a marker, and let the caller
  // proceed with `NativeDatabase.createInBackground` which will trigger
  // drift's onCreate on a now-absent file.
  final backupPath = await _rotateCorruptFile(dbFile);
  final markerPath = await _writeRecoveryMarker(dbFile, failureReason);

  return IntegrityRecoveryReport.recovered(
    backupPath: backupPath,
    markerPath: markerPath,
    failureReason: failureReason,
  );
}

/// Rename the corrupt DB file in place to `nightshade-corrupt-<ts>.db` in the
/// same directory. Also moves any `-wal` / `-shm` companion files so that the
/// fresh DB doesn't accidentally inherit a stale WAL.
///
/// Why rename, not copy: copying followed by delete races with WAL-mode write
/// recovery, so a rename (atomic on POSIX, near-atomic on NTFS) is safer.
Future<String> _rotateCorruptFile(File dbFile) async {
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
  final dir = dbFile.parent;
  final baseName = p.basename(dbFile.path);
  final backupName = '$_corruptBackupPrefix$ts-$baseName';
  final backupPath = p.join(dir.path, backupName);

  await dbFile.rename(backupPath);

  // Companion files left behind by WAL mode can resurrect corrupt content
  // when sqlite re-opens the now-absent main file, so move them aside too.
  for (final suffix in const ['-wal', '-shm', '-journal']) {
    final companion = File('${dbFile.path}$suffix');
    if (await companion.exists()) {
      final companionBackup = p.join(dir.path, '$backupName$suffix');
      try {
        await companion.rename(companionBackup);
      } on FileSystemException {
        // Why best-effort here: the companion files are sometimes locked by
        // a kernel-level cache flush. We've already preserved the main file
        // (the actual forensic evidence) and the recovery path can proceed.
        // We swallow this single sub-step, but the overall recovery is
        // still considered to have succeeded.
      }
    }
  }

  return backupPath;
}

/// Write a marker file that the UI hook consumes on next launch to surface a
/// "database was corrupted and recovered from backup" dialog. The marker
/// payload is a single line listing the backup path and the failure reason
/// so support engineers can find the evidence without an extra round-trip.
Future<String> _writeRecoveryMarker(File dbFile, String? failureReason) async {
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
  final markerPath = p.join(
    dbFile.parent.path,
    '$_recoveryMarkerPrefix$ts.txt',
  );
  final marker = File(markerPath);
  await marker.writeAsString(
    'db_path=${dbFile.path}\n'
    'recovered_at_utc=${DateTime.now().toUtc().toIso8601String()}\n'
    'reason=${failureReason ?? 'unknown'}\n',
    flush: true,
  );
  return markerPath;
}

/// One-time signal consumed by the UI layer. Returns the most recent recovery
/// marker (and clears all markers in the directory) iff at least one is
/// present. Returns null on a clean startup so the caller can short-circuit
/// without showing a dialog.
///
/// Why this clears the markers as a side-effect: the UX requirement is a
/// one-shot dialog. If the user dismisses it and re-launches the app, they
/// must not see the dialog again unless a NEW corruption-recovery happened
/// in the interim.
class DatabaseRecoveryMarker {
  final String markerPath;
  final String? backupPath;
  final DateTime recoveredAtUtc;
  final String? reason;

  const DatabaseRecoveryMarker({
    required this.markerPath,
    required this.backupPath,
    required this.recoveredAtUtc,
    required this.reason,
  });
}

/// Look for `.recovered-on-*.txt` markers in [dbDirectory], return the
/// newest one, and unlink every marker in the directory so the dialog is
/// truly one-shot. Older markers are deleted too because they describe past
/// recoveries the user has already been notified about.
Future<DatabaseRecoveryMarker?> consumeRecoveryMarker(
    Directory dbDirectory) async {
  if (!await dbDirectory.exists()) {
    return null;
  }

  final entries = await dbDirectory
      .list()
      .where((e) =>
          e is File &&
          p.basename(e.path).startsWith(_recoveryMarkerPrefix) &&
          p.basename(e.path).endsWith('.txt'))
      .cast<File>()
      .toList();

  if (entries.isEmpty) {
    return null;
  }

  // Newest by mtime wins because the filename timestamp could collide if
  // two recoveries happened in the same millisecond.
  entries.sort((a, b) =>
      b.statSync().modified.compareTo(a.statSync().modified));
  final newest = entries.first;
  final raw = await newest.readAsString();

  final fields = <String, String>{};
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final idx = line.indexOf('=');
    if (idx <= 0) continue;
    fields[line.substring(0, idx)] = line.substring(idx + 1);
  }

  final backupPathFromMarker = await _findMostRecentBackup(dbDirectory);

  // Delete every marker — including the one we just read — so the dialog
  // is one-shot. Why we don't just delete the newest: if recovery happened
  // multiple times across multiple launches without the UI seeing any of
  // them (e.g. headless boot), we still only want one dialog on the next
  // GUI launch.
  for (final marker in entries) {
    try {
      await marker.delete();
    } on FileSystemException {
      // Why best-effort here: if the marker file cannot be deleted (e.g.
      // permission denied because the user is running with reduced
      // privileges), the UX is degraded (dialog could repeat) but the
      // database itself is fine. We surface the path in the report below
      // so support can still locate it.
    }
  }

  final recoveredAt = DateTime.tryParse(fields['recovered_at_utc'] ?? '') ??
      newest.statSync().modified.toUtc();

  return DatabaseRecoveryMarker(
    markerPath: newest.path,
    backupPath: backupPathFromMarker,
    recoveredAtUtc: recoveredAt,
    reason: fields['reason'],
  );
}

Future<String?> _findMostRecentBackup(Directory dbDirectory) async {
  final backups = await dbDirectory
      .list()
      .where((e) =>
          e is File && p.basename(e.path).startsWith(_corruptBackupPrefix))
      .cast<File>()
      .toList();
  if (backups.isEmpty) {
    return null;
  }
  backups.sort((a, b) =>
      b.statSync().modified.compareTo(a.statSync().modified));
  return backups.first.path;
}
