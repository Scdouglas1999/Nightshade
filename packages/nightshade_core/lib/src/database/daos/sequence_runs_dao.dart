import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/sequence_runs.dart';

part 'sequence_runs_dao.g.dart';

@DriftAccessor(tables: [SequenceRuns])
class SequenceRunsDao extends DatabaseAccessor<NightshadeDatabase>
    with _$SequenceRunsDaoMixin {
  SequenceRunsDao(NightshadeDatabase db) : super(db);

  /// Start a new run record. Returns the row ID.
  Future<int> startRun({
    required int? sequenceId,
    required String sequenceName,
  }) {
    return into(sequenceRuns).insert(
      SequenceRunsCompanion.insert(
        sequenceId: Value(sequenceId),
        sequenceName: sequenceName,
        startedAt: DateTime.now(),
      ),
    );
  }

  /// Finish a run with final status and statistics.
  Future<void> finishRun(int runId, String status, String statsJson) async {
    await (update(sequenceRuns)..where((r) => r.id.equals(runId))).write(
      SequenceRunsCompanion(
        endedAt: Value(DateTime.now()),
        status: Value(status),
        statsJson: Value(statsJson),
      ),
    );
  }

  /// Update stats during execution (for live tracking).
  Future<void> updateStats(int runId, String statsJson) async {
    await (update(sequenceRuns)..where((r) => r.id.equals(runId))).write(
      SequenceRunsCompanion(statsJson: Value(statsJson)),
    );
  }

  /// Get all runs ordered by most recent first.
  Future<List<SequenceRun>> getAllRuns() {
    return (select(
      sequenceRuns,
    )..orderBy([(r) => OrderingTerm.desc(r.startedAt)])).get();
  }

  /// Watch all runs for reactive UI.
  Stream<List<SequenceRun>> watchAllRuns() {
    return (select(
      sequenceRuns,
    )..orderBy([(r) => OrderingTerm.desc(r.startedAt)])).watch();
  }

  /// Get runs for a specific sequence.
  Future<List<SequenceRun>> getRunsForSequence(int sequenceId) {
    return (select(sequenceRuns)
          ..where((r) => r.sequenceId.equals(sequenceId))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
        .get();
  }

  /// Watch runs for a specific sequence.
  Stream<List<SequenceRun>> watchRunsForSequence(int sequenceId) {
    return (select(sequenceRuns)
          ..where((r) => r.sequenceId.equals(sequenceId))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
        .watch();
  }

  /// Get a single run by ID.
  Future<SequenceRun?> getRunById(int id) {
    return (select(
      sequenceRuns,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Delete a run.
  Future<int> deleteRun(int id) {
    return (delete(sequenceRuns)..where((r) => r.id.equals(id))).go();
  }

  /// Delete all runs older than a given date.
  Future<int> deleteRunsOlderThan(DateTime cutoff) {
    return (delete(
      sequenceRuns,
    )..where((r) => r.startedAt.isSmallerThanValue(cutoff))).go();
  }

  /// P2-8: paginated listing for the remote read API. Newest-first by
  /// `startedAt` so the phone always sees the most recent run at index 0.
  /// Callers MUST validate and clamp [limit] / [offset] before delegating.
  Future<List<SequenceRun>> listPaginated({
    int? sequenceId,
    int limit = 200,
    int offset = 0,
  }) {
    final query = select(sequenceRuns)
      ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
      ..limit(limit, offset: offset);
    if (sequenceId != null) {
      query.where((r) => r.sequenceId.equals(sequenceId));
    }
    return query.get();
  }

  /// P2-8: row count for the same filter set [listPaginated] uses; the
  /// handler returns this in the `total` field so the phone can render a
  /// progress indicator.
  Future<int> countFiltered({int? sequenceId}) async {
    final countExpr = sequenceRuns.id.count();
    final query = selectOnly(sequenceRuns)..addColumns([countExpr]);
    if (sequenceId != null) {
      query.where(sequenceRuns.sequenceId.equals(sequenceId));
    }
    final row = await query.getSingle();
    return row.read(countExpr) ?? 0;
  }
}
