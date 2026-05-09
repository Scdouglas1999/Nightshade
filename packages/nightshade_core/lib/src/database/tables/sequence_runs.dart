import 'package:drift/drift.dart';

import 'sequences.dart';

/// Stores execution history for sequences.
/// Each row represents a single run of a sequence (completed, failed, or aborted).
@DataClassName('SequenceRun')
@TableIndex(name: 'idx_sequence_runs_sequence', columns: {#sequenceId})
@TableIndex(name: 'idx_sequence_runs_started', columns: {#startedAt})
@TableIndex(name: 'idx_sequence_runs_status', columns: {#status})
class SequenceRuns extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// FK to sequences table (nullable because the sequence may be deleted)
  IntColumn get sequenceId =>
      integer().nullable().references(Sequences, #id, onDelete: KeyAction.setNull)();

  /// Snapshot of the sequence name at the time of execution
  TextColumn get sequenceName => text()();

  /// When the run started
  DateTimeColumn get startedAt => dateTime()();

  /// When the run ended (null if still running)
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// Final status: 'completed', 'failed', 'aborted', 'running'
  TextColumn get status => text().withDefault(const Constant('running'))();

  /// JSON blob with detailed statistics
  /// Structure: {
  ///   "wallClockSecs": double,
  ///   "integrationSecs": double,
  ///   "overheadSecs": double,
  ///   "framesCaptured": int,
  ///   "framesRejected": int,
  ///   "targetBreakdown": { "targetName": { "filter": { "captured": int, "rejected": int, "integrationSecs": double } } },
  ///   "triggerFires": int,
  ///   "autofocusRuns": int,
  ///   "meridianFlips": int,
  ///   "ditherCount": int,
  ///   "errorMessages": [ "..." ]
  /// }
  TextColumn get statsJson => text().withDefault(const Constant('{}'))();
}
