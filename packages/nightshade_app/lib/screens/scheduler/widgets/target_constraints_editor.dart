import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
// nightshade_core re-exports a `ConnectionState` from its device-types model
// that collides with Flutter's async `ConnectionState`. Hide the core one
// here; everything else we need from the barrel is unaffected.
import 'package:nightshade_core/nightshade_core.dart' hide ConnectionState;
// targetConstraintsSchemaSql + horizonProfilesSchemaSql are intentionally
// hidden from the package barrel (they're DDL constants, not public API).
// Pull them in via the source file directly so we can guarantee the tables
// exist before reading.
// ignore: implementation_imports
import 'package:nightshade_core/src/services/scheduler/integration_goal_service.dart'
    show targetConstraintsSchemaSql, horizonProfilesSchemaSql;
import 'package:nightshade_ui/nightshade_ui.dart';

part 'target_constraints_editor/constraint_rows.dart';
part 'target_constraints_editor/constraint_fields.dart';
part 'target_constraints_editor/add_constraint_wizard_dialog.dart';
part 'target_constraints_editor/wizard_kind_step.dart';
part 'target_constraints_editor/wizard_params_review.dart';

///
/// Manages four constraint kinds:
///   * timeWindow:            HH:MM start / HH:MM end (local time).
///   * moonIlluminationMax:   0..1 slider.
///   * customHorizon:         picks an existing HorizonProfile by id.
///   * scheduledWindow:       absolute-UTC forced-priority window.
///
/// Constraints are persisted directly via raw SQL through the
/// shared database provider (no dedicated DAO exists yet — matching the
/// scheduler engine's loader which does the same). Editing emits a
/// candidatesUpdated trigger upstream so the engine re-evaluates.
///
/// "Add constraint" opens a 3-step wizard (kind → params with defaults →
/// review). "Edit constraint" keeps the existing direct-dialog form so
/// power users tweaking a single row don't pay a 3-step tax.
class TargetConstraintsEditor extends ConsumerStatefulWidget {
  final int targetId;
  final String targetName;
  final VoidCallback? onChanged;

  const TargetConstraintsEditor({
    super.key,
    required this.targetId,
    required this.targetName,
    this.onChanged,
  });

  @override
  ConsumerState<TargetConstraintsEditor> createState() =>
      _TargetConstraintsEditorState();
}

class _TargetConstraintsEditorState
    extends ConsumerState<TargetConstraintsEditor> {
  late Future<_LoadedConstraints> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LoadedConstraints> _load() async {
    final db = ref.read(databaseProvider);
    await db.customStatement(targetConstraintsSchemaSql);
    await db.customStatement(horizonProfilesSchemaSql);
    final rows = await db.customSelect(
      'SELECT id, target_id, kind, payload_json, enabled '
      'FROM target_constraints WHERE target_id = ?',
      variables: [Variable.withInt(widget.targetId)],
    ).get();
    final constraints = rows
        .map((r) => TargetConstraint.fromRow(
              id: r.read<int>('id'),
              targetId: r.read<int>('target_id'),
              kindName: r.read<String>('kind'),
              payloadJson: r.read<String>('payload_json'),
              enabled: r.read<int>('enabled') == 1,
            ))
        .toList();

    final hpRows = await db
        .customSelect(
          'SELECT id, name, samples_json FROM horizon_profiles ORDER BY name ASC',
        )
        .get();
    final profiles = hpRows
        .map((r) => HorizonProfile.fromRow(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
              samplesJson: r.read<String>('samples_json'),
            ))
        .toList();

    return _LoadedConstraints(
      constraints: constraints,
      horizonProfiles: profiles,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    final result = await _future;
    if (!mounted) return;
    setState(() {});
    widget.onChanged?.call();
    return Future.value(result).then((_) {});
  }

  Future<void> _upsertConstraint(TargetConstraint c) async {
    final svc = ref.read(targetConstraintServiceProvider);
    if (c.id == null) {
      await svc.insert(c);
    } else {
      await svc.update(c);
    }
    await _refresh();
  }

  Future<void> _deleteConstraint(int id) async {
    final svc = ref.read(targetConstraintServiceProvider);
    await svc.delete(id);
    await _refresh();
  }

  Future<void> _openWizard(_LoadedConstraints loaded) async {
    final created = await showDialog<TargetConstraint>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => _AddConstraintWizardDialog(
        targetId: widget.targetId,
        targetName: widget.targetName,
        horizonProfiles: loaded.horizonProfiles,
        existingKinds: loaded.constraints.map((c) => c.kind).toSet(),
      ),
    );
    if (created == null) return;
    await _upsertConstraint(created);
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return FutureBuilder<_LoadedConstraints>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.primary,
              ),
            ),
          );
        }
        if (snap.hasError) {
          return Text(
            'Failed to load constraints: ${snap.error}',
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12, color: colors.error),
          );
        }
        final loaded = snap.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.filter,
                    size: NightshadeTokens.iconSm, color: colors.primary),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Text(
                  'Hard constraints',
                  style: NightshadeTypography.h5.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'A failing constraint excludes ${widget.targetName} from selection regardless of score.',
              style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final c in loaded.constraints)
              _ConstraintRow(
                constraint: c,
                horizonProfiles: loaded.horizonProfiles,
                onChange: _upsertConstraint,
                onDelete: () => _deleteConstraint(c.id!),
              ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            _AddConstraintButton(
              key: const ValueKey('add-constraint-wizard-button'),
              onPressed: () => _openWizard(loaded),
            ),
          ],
        );
      },
    );
  }
}
