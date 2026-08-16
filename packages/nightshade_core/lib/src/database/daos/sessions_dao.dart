import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/imaging_sessions.dart';
import '../tables/equipment_profiles.dart';
import '../tables/sequences.dart';
import '../tables/targets.dart';

part 'sessions_dao.g.dart';

class ActiveImagingSessionException implements Exception {
  final int sessionId;

  const ActiveImagingSessionException(this.sessionId);

  @override
  String toString() => 'Imaging session $sessionId is already active';
}

@DriftAccessor(tables: [ImagingSessions, EquipmentProfiles, Sequences, Targets])
class SessionsDao extends DatabaseAccessor<NightshadeDatabase>
    with _$SessionsDaoMixin {
  SessionsDao(super.db);

  /// Get all sessions
  Future<List<ImagingSession>> getAllSessions() {
    return (select(
      imagingSessions,
    )..orderBy([(s) => OrderingTerm.desc(s.startTime)])).get();
  }

  /// Watch all sessions
  Stream<List<ImagingSession>> watchAllSessions() {
    return (select(
      imagingSessions,
    )..orderBy([(s) => OrderingTerm.desc(s.startTime)])).watch();
  }

  /// Get recent sessions
  Future<List<ImagingSession>> getRecentSessions({int limit = 10}) {
    return (select(imagingSessions)
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
          ..limit(limit))
        .get();
  }

  /// Get session by ID
  Future<ImagingSession?> getSessionById(int id) {
    return (select(
      imagingSessions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  /// Get sessions for a target
  Future<List<ImagingSession>> getSessionsForTarget(int targetId) {
    return (select(imagingSessions)
          ..where((s) => s.targetId.equals(targetId))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .get();
  }

  /// Get sessions in date range
  Future<List<ImagingSession>> getSessionsInRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(imagingSessions)
          ..where(
            (s) =>
                s.startTime.isBiggerOrEqualValue(start) &
                s.startTime.isSmallerOrEqualValue(end),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .get();
  }

  /// Create a new session
  Future<int> createSession(ImagingSessionsCompanion session) {
    return into(imagingSessions).insert(session);
  }

  /// Start a new session
  Future<int> startSession({
    String? name,
    int? profileId,
    int? targetId,
    int? sequenceId,
  }) async {
    return transaction(() async {
      final active = await getActiveSessions();
      if (active.isNotEmpty) {
        throw ActiveImagingSessionException(active.first.id);
      }
      return into(imagingSessions).insert(
        ImagingSessionsCompanion.insert(
          startTime: DateTime.now(),
          name: Value(name),
          profileId: Value(profileId),
          targetId: Value(targetId),
          sequenceId: Value(sequenceId),
          status: const Value('active'),
        ),
      );
    });
  }

  /// End a session
  Future<void> endSession(int id, {String status = 'completed'}) {
    return (update(imagingSessions)..where((s) => s.id.equals(id))).write(
      ImagingSessionsCompanion(
        endTime: Value(DateTime.now()),
        status: Value(status),
      ),
    );
  }

  /// Close a session that was left `active` — a crash, a kill, a sequencer
  /// reset — stamping `end_time` at the session's LAST ACTUAL ACTIVITY rather
  /// than at the wall clock of the recovery.
  ///
  /// Wall-clock closure is what [endSession] does, and it is right when a run
  /// really did just finish. It is badly wrong here: a session abandoned on
  /// Wednesday and recovered on Friday was stamped with Friday's clock, so its
  /// History card, its wall-clock duration and every efficiency figure derived
  /// from it (campaign efficiency, effective imaging %) reported a 60-hour
  /// night. One crash permanently corrupted the night's duration.
  ///
  /// The last frame's timestamp is the only durable record of when imaging
  /// actually stopped. With no frames at all the session produced nothing, so
  /// it collapses to `start_time` (zero duration) rather than inventing one.
  /// Clamped to `[start_time, now]` so a bad clock or a future-dated frame
  /// cannot produce a negative or still-growing duration.
  Future<void> abortSession(int id) async {
    final session = await getSessionById(id);
    if (session == null) return;
    final lastFrame = await customSelect(
      'SELECT MAX(captured_at) AS last_at FROM captured_images '
      'WHERE session_id = ?',
      variables: [Variable<int>(id)],
      readsFrom: {attachedDatabase.capturedImages},
    ).getSingleOrNull();
    final lastAt = lastFrame?.data['last_at'] as int?;
    final now = DateTime.now();
    // Drift stores DateTime columns as unix seconds and decodes them as local
    // instants; matching that here keeps the round trip lossless.
    var endTime = lastAt == null
        ? session.startTime
        : DateTime.fromMillisecondsSinceEpoch(lastAt * 1000);
    if (endTime.isBefore(session.startTime)) endTime = session.startTime;
    if (endTime.isAfter(now)) endTime = now;

    await (update(imagingSessions)..where((s) => s.id.equals(id))).write(
      ImagingSessionsCompanion(
        endTime: Value(endTime),
        status: const Value('aborted'),
      ),
    );
  }

  /// Update session statistics
  Future<void> updateSessionStats(
    int id, {
    int? totalExposures,
    int? successfulExposures,
    int? failedExposures,
    double? totalIntegrationSecs,
    double? avgHfr,
    double? avgGuidingRms,
    int? autofocusCount,
  }) async {
    final updates = ImagingSessionsCompanion(
      totalExposures: totalExposures != null
          ? Value(totalExposures)
          : const Value.absent(),
      successfulExposures: successfulExposures != null
          ? Value(successfulExposures)
          : const Value.absent(),
      failedExposures: failedExposures != null
          ? Value(failedExposures)
          : const Value.absent(),
      totalIntegrationSecs: totalIntegrationSecs != null
          ? Value(totalIntegrationSecs)
          : const Value.absent(),
      avgHfr: avgHfr != null ? Value(avgHfr) : const Value.absent(),
      avgGuidingRms: avgGuidingRms != null
          ? Value(avgGuidingRms)
          : const Value.absent(),
      autofocusCount: autofocusCount != null
          ? Value(autofocusCount)
          : const Value.absent(),
    );

    await (update(
      imagingSessions,
    )..where((s) => s.id.equals(id))).write(updates);
  }

  /// Add notes to a session
  Future<void> updateNotes(int id, String notes) {
    return (update(imagingSessions)..where((s) => s.id.equals(id))).write(
      ImagingSessionsCompanion(notes: Value(notes)),
    );
  }

  /// Delete a session
  Future<int> deleteSession(int id) {
    return (delete(imagingSessions)..where((s) => s.id.equals(id))).go();
  }

  /// Get total statistics using SQL aggregation.
  Future<Map<String, dynamic>> getTotalStatistics() async {
    final countExp = imagingSessions.id.count();
    final sumExposures = imagingSessions.totalExposures.sum();
    final sumIntegration = imagingSessions.totalIntegrationSecs.sum();

    final query = selectOnly(imagingSessions)
      ..addColumns([countExp, sumExposures, sumIntegration]);

    final row = await query.getSingle();
    final totalSessions = row.read(countExp) ?? 0;
    final totalExposures = row.read(sumExposures) ?? 0;
    final totalIntegration = row.read(sumIntegration) ?? 0.0;

    return {
      'totalSessions': totalSessions,
      'totalExposures': totalExposures,
      'totalIntegrationHours': totalIntegration / 3600,
    };
  }

  // Session recovery methods

  /// Get all active sessions (for recovery)
  Future<List<ImagingSession>> getActiveSessions() {
    return (select(imagingSessions)
          ..where((s) => s.status.equals('active'))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .get();
  }

  /// Watch active sessions
  Stream<List<ImagingSession>> watchActiveSessions() {
    return (select(imagingSessions)
          ..where((s) => s.status.equals('active'))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .watch();
  }

  /// Update session status only
  Future<void> updateSessionStatus(int id, String status) {
    return (update(imagingSessions)..where((s) => s.id.equals(id))).write(
      ImagingSessionsCompanion(status: Value(status)),
    );
  }

  /// Get sessions by status
  Future<List<ImagingSession>> getSessionsByStatus(String status) {
    return (select(imagingSessions)
          ..where((s) => s.status.equals(status))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)]))
        .get();
  }

  /// Get session statistics for a specific target using SQL aggregation.
  Future<Map<String, dynamic>> getTargetStatistics(int targetId) async {
    final countExp = imagingSessions.id.count();
    final sumExposures = imagingSessions.successfulExposures.sum();
    final sumIntegration = imagingSessions.totalIntegrationSecs.sum();
    final avgHfrExp = imagingSessions.avgHfr.avg();

    final query = selectOnly(imagingSessions)
      ..addColumns([countExp, sumExposures, sumIntegration, avgHfrExp])
      ..where(imagingSessions.targetId.equals(targetId));

    final row = await query.getSingle();
    final totalSessions = row.read(countExp) ?? 0;
    final totalExposures = row.read(sumExposures) ?? 0;
    final totalIntegration = row.read(sumIntegration) ?? 0.0;
    final avgHfr = row.read(avgHfrExp);

    return {
      'totalSessions': totalSessions,
      'totalExposures': totalExposures,
      'totalIntegrationHours': totalIntegration / 3600,
      'avgHfr': avgHfr,
    };
  }

  /// Update weather/environmental conditions
  Future<void> updateWeatherConditions(
    int id, {
    double? avgTemperature,
    double? avgHumidity,
    double? avgSeeing,
  }) async {
    final updates = ImagingSessionsCompanion(
      avgTemperature: avgTemperature != null
          ? Value(avgTemperature)
          : const Value.absent(),
      avgHumidity: avgHumidity != null
          ? Value(avgHumidity)
          : const Value.absent(),
      avgSeeing: avgSeeing != null ? Value(avgSeeing) : const Value.absent(),
    );

    await (update(
      imagingSessions,
    )..where((s) => s.id.equals(id))).write(updates);
  }

  /// Check if there are any incomplete/crashed sessions
  Future<bool> hasIncompleteSessions() async {
    final activeSessions = await getActiveSessions();
    return activeSessions.isNotEmpty;
  }

  // Quick start methods

  /// Get the most recent session for Quick Start (within last 7 days)
  Future<ImagingSession?> getMostRecentSession() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    return (select(imagingSessions)
          ..where((s) => s.startTime.isBiggerOrEqualValue(cutoff))
          ..orderBy([(s) => OrderingTerm.desc(s.startTime)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Update equipment snapshot for a session
  Future<void> updateEquipmentSnapshot(int id, String snapshotJson) {
    return (update(imagingSessions)..where((s) => s.id.equals(id))).write(
      ImagingSessionsCompanion(equipmentSnapshot: Value(snapshotJson)),
    );
  }

  /// Update sequence ID for a session
  Future<void> updateSequenceId(int id, int sequenceId) {
    return (update(imagingSessions)..where((s) => s.id.equals(id))).write(
      ImagingSessionsCompanion(sequenceId: Value(sequenceId)),
    );
  }
}
