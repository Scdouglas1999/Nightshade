import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database.dart' as db;
import '../../models/scheduler/integration_goal.dart';
import '../../providers/database_provider.dart';

/// SQL schema for the three scheduler tables.
///
/// Tables are managed outside drift's `@DriftDatabase` declaration (which
/// would require codegen) by issuing raw `CREATE TABLE IF NOT EXISTS`
/// statements on first access. Schema is additive only; no migrations are
/// needed because the tables are new and operator data is not at risk.
const _integrationGoalsSchema = '''
CREATE TABLE IF NOT EXISTS integration_goals (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_id INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,
  filter TEXT NOT NULL,
  exposure_seconds REAL NOT NULL,
  frame_count INTEGER NOT NULL,
  priority INTEGER NOT NULL DEFAULT 5,
  created_at INTEGER NOT NULL,
  UNIQUE(target_id, filter, exposure_seconds)
)
''';

const _targetConstraintsSchema = '''
CREATE TABLE IF NOT EXISTS target_constraints (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  target_id INTEGER NOT NULL REFERENCES targets(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1
)
''';

const _horizonProfilesSchema = '''
CREATE TABLE IF NOT EXISTS horizon_profiles (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  samples_json TEXT NOT NULL
)
''';

const _integrationGoalsTargetIndex =
    'CREATE INDEX IF NOT EXISTS idx_integration_goals_target ON integration_goals (target_id)';
const _targetConstraintsTargetIndex =
    'CREATE INDEX IF NOT EXISTS idx_target_constraints_target ON target_constraints (target_id)';

/// Persistence + business-logic for integration goals.
///
/// Persists `IntegrationGoal` rows in the database and computes per-goal
/// "remaining frames" by counting matching rows in `captured_images` for
/// the same `(target_id, filter)`. The captured-image match is filter-name
/// case-insensitive because users sometimes type 'Lum' and the wheel
/// reports 'L', etc.
class IntegrationGoalService {
  final db.NightshadeDatabase _db;
  bool _schemaEnsured = false;

  IntegrationGoalService(this._db);

  Future<void> _ensureSchema() async {
    if (_schemaEnsured) return;
    await _db.customStatement(_integrationGoalsSchema);
    await _db.customStatement(_integrationGoalsTargetIndex);
    _schemaEnsured = true;
  }

  /// Insert a new integration goal. The (target_id, filter, exposure)
  /// uniqueness constraint replaces an existing row with the same key so
  /// the operator can iteratively tune one filter's goal without leaving
  /// duplicates.
  Future<int> upsert(IntegrationGoal goal) async {
    await _ensureSchema();
    final existing = await _db.customSelect(
      'SELECT id FROM integration_goals WHERE target_id = ? AND filter = ? AND exposure_seconds = ?',
      variables: [
        Variable.withInt(goal.targetId),
        Variable.withString(goal.filter),
        Variable.withReal(goal.exposureSeconds),
      ],
    ).getSingleOrNull();
    if (existing != null) {
      final id = existing.read<int>('id');
      await _db.customStatement(
        'UPDATE integration_goals SET frame_count = ?, priority = ? WHERE id = ?',
        [goal.frameCount, goal.priority, id],
      );
      return id;
    }
    final inserted = await _db.customInsert(
      'INSERT INTO integration_goals (target_id, filter, exposure_seconds, frame_count, priority, created_at) VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withInt(goal.targetId),
        Variable.withString(goal.filter),
        Variable.withReal(goal.exposureSeconds),
        Variable.withInt(goal.frameCount),
        Variable.withInt(goal.priority),
        Variable.withInt(
            goal.createdAt.toUtc().millisecondsSinceEpoch ~/ 1000),
      ],
    );
    return inserted;
  }

  Future<void> delete(int goalId) async {
    await _ensureSchema();
    await _db.customStatement(
      'DELETE FROM integration_goals WHERE id = ?',
      [goalId],
    );
  }

  Future<List<IntegrationGoal>> listForTarget(int targetId) async {
    await _ensureSchema();
    final rows = await _db.customSelect(
      'SELECT id, target_id, filter, exposure_seconds, frame_count, priority, created_at '
      'FROM integration_goals WHERE target_id = ? ORDER BY priority DESC, filter ASC',
      variables: [Variable.withInt(targetId)],
    ).get();
    return rows.map(_rowToGoal).toList();
  }

  Future<List<IntegrationGoal>> listAll() async {
    await _ensureSchema();
    final rows = await _db.customSelect(
      'SELECT id, target_id, filter, exposure_seconds, frame_count, priority, created_at FROM integration_goals',
    ).get();
    return rows.map(_rowToGoal).toList();
  }

  /// Compute the captured-frame count for one (target, filter) pair.
  ///
  /// Counts only frames with frame_type='light' and is_accepted=1 so
  /// rejected subs do not artificially advance the goal. Filter matching
  /// is case-insensitive.
  Future<int> capturedFrameCount({
    required int targetId,
    required String filter,
  }) async {
    final rows = await _db.customSelect(
      "SELECT COUNT(*) AS c FROM captured_images "
      "WHERE target_id = ? AND frame_type = 'light' AND is_accepted = 1 "
      "AND LOWER(filter) = LOWER(?)",
      variables: [
        Variable.withInt(targetId),
        Variable.withString(filter),
      ],
    ).get();
    if (rows.isEmpty) return 0;
    return rows.first.read<int>('c');
  }

  /// Return all goals for a target paired with their captured counts.
  Future<List<IntegrationGoalProgress>> progressForTarget(int targetId) async {
    final goals = await listForTarget(targetId);
    final out = <IntegrationGoalProgress>[];
    for (final g in goals) {
      final captured = await capturedFrameCount(
        targetId: g.targetId,
        filter: g.filter,
      );
      out.add(IntegrationGoalProgress(goal: g, capturedCount: captured));
    }
    return out;
  }

  IntegrationGoal _rowToGoal(QueryRow row) {
    return IntegrationGoal(
      id: row.read<int>('id'),
      targetId: row.read<int>('target_id'),
      filter: row.read<String>('filter'),
      exposureSeconds: row.read<double>('exposure_seconds'),
      frameCount: row.read<int>('frame_count'),
      priority: row.read<int>('priority'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('created_at') * 1000,
        isUtc: true,
      ),
    );
  }
}

final integrationGoalServiceProvider = Provider<IntegrationGoalService>((ref) {
  return IntegrationGoalService(ref.watch(databaseProvider));
});

/// Re-used DDL strings exported so the scheduler engine init can ensure
/// all three tables exist in one place.
const String integrationGoalsSchemaSql = _integrationGoalsSchema;
const String integrationGoalsTargetIndexSql = _integrationGoalsTargetIndex;
const String targetConstraintsSchemaSql = _targetConstraintsSchema;
const String targetConstraintsTargetIndexSql = _targetConstraintsTargetIndex;
const String horizonProfilesSchemaSql = _horizonProfilesSchema;
