import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Durable "an integration is in flight" marker for the post-session pass.
///
/// WHY A FILE, next to the database, rather than a row: the pass this covers
/// runs BEFORE any `darkroom_jobs` row exists. `AutoIntegrationService`
/// integrates or folds every filter bucket first and only then enqueues the
/// Darkroom job, so a kill during the integrate — the longest, most
/// interruptible stretch of the night — left nothing at all behind: no job row
/// to re-queue, no session note, no log the operator sees. The night simply
/// went quiet, and the half-written master on disk looked like a finished one.
///
/// The file is the same mechanism `integrity_check.dart` already uses for
/// `.recovered-on-*.txt` and `.restore-pending.txt`: written with `flush: true`
/// so it survives a `kill -9` or a power cut, and read on the next open before
/// anything can overwrite it. It deliberately does NOT use `darkroom_jobs` —
/// that table's `kind` column is constrained to `dawn`/`manual` and its
/// open-time recovery RE-QUEUES what it finds, which is the wrong answer for a
/// half-integrated stack whose output files are already suspect.
///
/// Its one prefix is distinct from every marker `integrity_check.dart` globs,
/// so a restore or a corruption recovery never consumes it and it never
/// consumes theirs.
const String kIntegrationMarkerName = '.integration-in-flight.json';

/// What a previous process was integrating when it died.
class InterruptedIntegration {
  /// The imaging session whose subs were being integrated.
  final int sessionId;

  /// The target as it was named when the pass started, or null when the
  /// session's frames carried no target.
  final String? targetName;

  /// When the integration started, in UTC.
  final DateTime startedAtUtc;

  /// The master files the pass was going to write.
  ///
  /// Named in the report because these are the files that are now suspect: a
  /// process killed mid-write leaves a FITS that is present, non-empty, and
  /// truncated. An operator told only "the integration was interrupted" would
  /// reasonably open one and trust it.
  final List<String> intendedMasterPaths;

  const InterruptedIntegration({
    required this.sessionId,
    required this.targetName,
    required this.startedAtUtc,
    required this.intendedMasterPaths,
  });

  /// The intended master files that are actually on disk right now — the
  /// orphans. Distinguished from [intendedMasterPaths] so the report can say
  /// "delete these two" rather than listing paths that were never created.
  Future<List<String>> orphanedMasterFiles() async {
    final present = <String>[];
    for (final path in intendedMasterPaths) {
      if (await File(path).exists()) present.add(path);
    }
    return present;
  }

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'targetName': targetName,
    'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
    'intendedMasterPaths': intendedMasterPaths,
  };

  /// Parse a marker payload, or null when the file is not one this app wrote.
  ///
  /// A marker we cannot read is reported as "no marker" rather than as a
  /// malformed interruption: the only action it drives is a warning, and
  /// inventing a session id to warn about would be worse than the silence this
  /// whole mechanism exists to end. The unreadable file is left on disk for
  /// support instead of being silently deleted.
  static InterruptedIntegration? fromJson(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final sessionId = decoded['sessionId'];
    final startedAt = DateTime.tryParse('${decoded['startedAtUtc']}');
    if (sessionId is! int || startedAt == null) return null;
    final paths = decoded['intendedMasterPaths'];
    return InterruptedIntegration(
      sessionId: sessionId,
      targetName: decoded['targetName'] as String?,
      startedAtUtc: startedAt.toUtc(),
      intendedMasterPaths: paths is List
          ? paths.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

/// Where the marker lives for a database directory.
File integrationMarkerFile(Directory databaseDirectory) =>
    File(p.join(databaseDirectory.path, kIntegrationMarkerName));

/// Record that an integration is starting.
///
/// Written and flushed before the first sub is read, because the window this
/// covers opens at that moment. Overwrites any existing marker: only one
/// post-session integration runs at a time (the coordinator serializes them),
/// and a marker left by a process that died is consumed at open, before this
/// process could reach here.
Future<void> markIntegrationStarted(
  Directory databaseDirectory,
  InterruptedIntegration integration,
) async {
  await integrationMarkerFile(
    databaseDirectory,
  ).writeAsString(jsonEncode(integration.toJson()), flush: true);
}

/// Clear the marker because the integration finished — successfully or with a
/// reported failure.
///
/// A failure that the app itself caught and reported is NOT an interruption:
/// the operator already has the error, and leaving the marker would announce
/// it a second time at the next launch as a crash that never happened.
Future<void> clearIntegrationMarker(Directory databaseDirectory) async {
  final file = integrationMarkerFile(databaseDirectory);
  if (await file.exists()) {
    await file.delete();
  }
}

/// Read the marker a dead process left, or null when the last integration
/// finished.
///
/// Does not delete it — the caller deletes it only once the interruption has
/// been recorded somewhere durable, so a crash between the read and the write
/// of the report cannot lose the warning.
Future<InterruptedIntegration?> readIntegrationMarker(
  Directory databaseDirectory,
) async {
  final file = integrationMarkerFile(databaseDirectory);
  if (!await file.exists()) return null;
  return InterruptedIntegration.fromJson(await file.readAsString());
}
