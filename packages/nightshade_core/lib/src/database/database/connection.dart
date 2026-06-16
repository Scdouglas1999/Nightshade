part of '../database.dart';

/// Environment variable used by headless/systemd deployments to pin the Drift
/// database under a daemon-owned state directory instead of a user Documents
/// folder.
const nightshadeDatabaseDirEnv = 'NIGHTSHADE_DATABASE_DIR';

/// Resolve the on-disk path the desktop/mobile database lives at. Exposed
/// separately so the UI bootstrap and CLI tools can find the file (e.g. for
/// "Show database location" buttons or post-recovery diagnostics) without
/// re-implementing the path heuristic.
Future<File> resolveDefaultDatabaseFile({
  Map<String, String>? environment,
  Future<Directory> Function()? documentsDirectoryProvider,
}) async {
  final env = environment ?? Platform.environment;
  final overrideDir = env[nightshadeDatabaseDirEnv]?.trim();
  if (overrideDir != null && overrideDir.isNotEmpty) {
    return File(p.join(overrideDir, 'nightshade.db'));
  }

  final dbFolder =
      await (documentsDirectoryProvider ?? getApplicationDocumentsDirectory)();
  return File(p.join(dbFolder.path, 'Nightshade', 'nightshade.db'));
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await resolveDefaultDatabaseFile();

    // Ensure directory exists
    await file.parent.create(recursive: true);

    // WHY pre-flight integrity check: Drift's `beforeOpen` runs after the
    // SQLite connection is established, which is too late to swap a corrupt
    // file out of the way without race conditions inside the background
    // isolate. Running the check here — on the foreground isolate, before
    // `NativeDatabase.createInBackground` ever resolves — lets us rotate the
    // corrupt file to a `nightshade-corrupt-<ts>.db` forensic backup so that
    // drift's `onCreate` then seeds a fresh database.
    //
    // The recovery marker file written by [runIntegrityCheckAndRecover] is
    // consumed on next launch by [NightshadeDatabase.consumeRecoveryMarker]
    // so the UI can show a one-shot "your database was corrupted and
    // recovered from backup" dialog.
    //
    // Per project policy we do NOT swallow recovery failures here: if the
    // integrity check itself throws (file lock, permission denied, etc.)
    // the exception propagates and the operator sees the real error rather
    // than a silently broken database.
    await integrity.runIntegrityCheckAndRecover(file);

    return NativeDatabase.createInBackground(file);
  });
}
