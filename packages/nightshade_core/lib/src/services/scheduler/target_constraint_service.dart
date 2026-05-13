import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/database.dart' as db;
import '../../models/scheduler/target_constraint.dart';
import '../../providers/database_provider.dart';
import 'integration_goal_service.dart'
    show targetConstraintsSchemaSql, targetConstraintsTargetIndexSql;

/// Persistence + change-notification for hard target constraints.
///
/// The `target_constraints` table is created out-of-band with raw SQL
/// (see `integration_goal_service.dart` for the shared DDL constants), so
/// drift's reactive `watch()` machinery can't see it. We layer a simple
/// broadcast `StreamController` on top so the scheduler provider can drive
/// `requestReevaluation()` whenever the operator adds, edits, deletes, or
/// toggles a constraint.
class TargetConstraintService {
  final db.NightshadeDatabase _db;
  bool _schemaEnsured = false;
  final StreamController<void> _mutations =
      StreamController<void>.broadcast();

  TargetConstraintService(this._db);

  Future<void> _ensureSchema() async {
    if (_schemaEnsured) return;
    await _db.customStatement(targetConstraintsSchemaSql);
    await _db.customStatement(targetConstraintsTargetIndexSql);
    _schemaEnsured = true;
  }

  void _notifyMutated() {
    if (!_mutations.isClosed) _mutations.add(null);
  }

  Future<void> dispose() async {
    await _mutations.close();
  }

  /// Insert a constraint and return its row id.
  Future<int> insert(TargetConstraint constraint) async {
    await _ensureSchema();
    final id = await _db.customInsert(
      'INSERT INTO target_constraints (target_id, kind, payload_json, enabled) VALUES (?, ?, ?, ?)',
      variables: [
        Variable.withInt(constraint.targetId),
        Variable.withString(constraint.kind.name),
        Variable.withString(constraint.encodePayload()),
        Variable.withInt(constraint.enabled ? 1 : 0),
      ],
    );
    _notifyMutated();
    return id;
  }

  /// Update an existing constraint in place. The constraint's [id] must
  /// be non-null.
  Future<void> update(TargetConstraint constraint) async {
    if (constraint.id == null) {
      throw StateError('TargetConstraintService.update requires a persisted id');
    }
    await _ensureSchema();
    await _db.customStatement(
      'UPDATE target_constraints SET kind = ?, payload_json = ?, enabled = ? WHERE id = ?',
      [
        constraint.kind.name,
        constraint.encodePayload(),
        constraint.enabled ? 1 : 0,
        constraint.id,
      ],
    );
    _notifyMutated();
  }

  Future<void> setEnabled(int constraintId, bool enabled) async {
    await _ensureSchema();
    await _db.customStatement(
      'UPDATE target_constraints SET enabled = ? WHERE id = ?',
      [enabled ? 1 : 0, constraintId],
    );
    _notifyMutated();
  }

  Future<void> delete(int constraintId) async {
    await _ensureSchema();
    await _db.customStatement(
      'DELETE FROM target_constraints WHERE id = ?',
      [constraintId],
    );
    _notifyMutated();
  }

  /// Remove every constraint attached to [targetId]. Paired with
  /// `IntegrationGoalService.deleteForTarget` by the scheduler queue's
  /// per-row delete action.
  Future<void> deleteForTarget(int targetId) async {
    await _ensureSchema();
    await _db.customStatement(
      'DELETE FROM target_constraints WHERE target_id = ?',
      [targetId],
    );
    _notifyMutated();
  }

  /// Truncate the whole table. Backs the scheduler queue's "Clear all"
  /// action.
  Future<void> deleteAll() async {
    await _ensureSchema();
    await _db.customStatement('DELETE FROM target_constraints');
    _notifyMutated();
  }

  Future<List<TargetConstraint>> listForTarget(int targetId) async {
    await _ensureSchema();
    final rows = await _db.customSelect(
      'SELECT id, target_id, kind, payload_json, enabled FROM target_constraints WHERE target_id = ?',
      variables: [Variable.withInt(targetId)],
    ).get();
    return rows.map(_rowToConstraint).toList();
  }

  Future<List<TargetConstraint>> listAll() async {
    await _ensureSchema();
    final rows = await _db.customSelect(
      'SELECT id, target_id, kind, payload_json, enabled FROM target_constraints',
    ).get();
    return rows.map(_rowToConstraint).toList();
  }

  /// Live stream of every constraint. Emits an initial snapshot then a
  /// fresh list after every mutation made through this service.
  Stream<List<TargetConstraint>> watchAll() async* {
    await _ensureSchema();
    yield await listAll();
    await for (final _ in _mutations.stream) {
      yield await listAll();
    }
  }

  TargetConstraint _rowToConstraint(QueryRow row) {
    return TargetConstraint.fromRow(
      id: row.read<int>('id'),
      targetId: row.read<int>('target_id'),
      kindName: row.read<String>('kind'),
      payloadJson: row.read<String>('payload_json'),
      enabled: row.read<int>('enabled') == 1,
    );
  }
}

final targetConstraintServiceProvider =
    Provider<TargetConstraintService>((ref) {
  final svc = TargetConstraintService(ref.watch(databaseProvider));
  ref.onDispose(() => svc.dispose());
  return svc;
});
