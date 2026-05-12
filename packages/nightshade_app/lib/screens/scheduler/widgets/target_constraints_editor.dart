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

/// Per-target hard-constraint editor.
///
/// Manages three constraint kinds:
///   * timeWindow:            HH:MM start / HH:MM end (local time).
///   * moonIlluminationMax:   0..1 slider.
///   * customHorizon:         picks an existing HorizonProfile by id.
///
/// Constraints are persisted directly via raw SQL through the
/// shared database provider (no dedicated DAO exists yet — matching the
/// scheduler engine's loader which does the same). Editing emits a
/// candidatesUpdated trigger upstream so the engine re-evaluates.
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

    final hpRows = await db.customSelect(
      'SELECT id, name, samples_json FROM horizon_profiles ORDER BY name ASC',
    ).get();
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
    final db = ref.read(databaseProvider);
    final payload = c.encodePayload();
    if (c.id == null) {
      await db.customInsert(
        'INSERT INTO target_constraints (target_id, kind, payload_json, enabled) '
        'VALUES (?, ?, ?, ?)',
        variables: [
          Variable.withInt(c.targetId),
          Variable.withString(c.kind.name),
          Variable.withString(payload),
          Variable.withInt(c.enabled ? 1 : 0),
        ],
      );
    } else {
      await db.customStatement(
        'UPDATE target_constraints SET kind = ?, payload_json = ?, enabled = ? WHERE id = ?',
        [c.kind.name, payload, c.enabled ? 1 : 0, c.id],
      );
    }
    await _refresh();
  }

  Future<void> _deleteConstraint(int id) async {
    final db = ref.read(databaseProvider);
    await db.customStatement(
      'DELETE FROM target_constraints WHERE id = ?',
      [id],
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
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
            style: TextStyle(fontSize: 12, color: colors.error),
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'A failing constraint excludes ${widget.targetName} from selection regardless of score.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
            _AddConstraintMenu(
              targetId: widget.targetId,
              existingKinds:
                  loaded.constraints.map((c) => c.kind).toSet(),
              horizonProfiles: loaded.horizonProfiles,
              onAdd: _upsertConstraint,
            ),
          ],
        );
      },
    );
  }
}

class _LoadedConstraints {
  final List<TargetConstraint> constraints;
  final List<HorizonProfile> horizonProfiles;
  _LoadedConstraints({
    required this.constraints,
    required this.horizonProfiles,
  });
}

class _ConstraintRow extends StatefulWidget {
  final TargetConstraint constraint;
  final List<HorizonProfile> horizonProfiles;
  final Future<void> Function(TargetConstraint) onChange;
  final Future<void> Function() onDelete;

  const _ConstraintRow({
    required this.constraint,
    required this.horizonProfiles,
    required this.onChange,
    required this.onDelete,
  });

  @override
  State<_ConstraintRow> createState() => _ConstraintRowState();
}

class _ConstraintRowState extends State<_ConstraintRow> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final c = widget.constraint;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm,
        ),
        decoration: BoxDecoration(
          color: c.enabled ? colors.surfaceAlt : colors.surfaceHover,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Switch(
              value: c.enabled,
              onChanged: (v) => widget.onChange(c.copyWith(enabled: v)),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            SizedBox(
              width: 150,
              child: Text(
                _kindLabel(c.kind),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: _ConstraintBody(
                constraint: c,
                horizonProfiles: widget.horizonProfiles,
                onChange: widget.onChange,
              ),
            ),
            IconButton(
              tooltip: 'Remove constraint',
              onPressed: widget.onDelete,
              icon: Icon(LucideIcons.trash2,
                  size: NightshadeTokens.iconSm, color: colors.error),
            ),
          ],
        ),
      ),
    );
  }

  String _kindLabel(TargetConstraintKind k) {
    switch (k) {
      case TargetConstraintKind.timeWindow:
        return 'Time window';
      case TargetConstraintKind.moonIlluminationMax:
        return 'Max moon illumination';
      case TargetConstraintKind.customHorizon:
        return 'Custom horizon';
    }
  }
}

class _ConstraintBody extends StatelessWidget {
  final TargetConstraint constraint;
  final List<HorizonProfile> horizonProfiles;
  final Future<void> Function(TargetConstraint) onChange;

  const _ConstraintBody({
    required this.constraint,
    required this.horizonProfiles,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    switch (constraint.kind) {
      case TargetConstraintKind.timeWindow:
        return _TimeWindowField(
          window: constraint.timeWindow ??
              const TargetTimeWindow(
                startMinutes: 22 * 60,
                endMinutes: 5 * 60,
              ),
          onChange: (w) =>
              onChange(constraint.copyWith(timeWindow: w)),
        );
      case TargetConstraintKind.moonIlluminationMax:
        return _MoonField(
          value: constraint.moonIlluminationMax ?? 0.5,
          onChange: (v) =>
              onChange(constraint.copyWith(moonIlluminationMax: v)),
        );
      case TargetConstraintKind.customHorizon:
        return _HorizonField(
          selectedId: constraint.customHorizonId,
          profiles: horizonProfiles,
          onChange: (id) =>
              onChange(constraint.copyWith(customHorizonId: id)),
        );
    }
  }
}

class _TimeWindowField extends StatelessWidget {
  final TargetTimeWindow window;
  final void Function(TargetTimeWindow) onChange;
  const _TimeWindowField({required this.window, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Row(
      children: [
        OutlinedButton.icon(
          icon: const Icon(LucideIcons.clock, size: 14),
          onPressed: () => _pickStart(context),
          label: Text(_format(window.startMinutes)),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text('to', style: TextStyle(color: colors.textSecondary)),
        const SizedBox(width: NightshadeTokens.spaceSm),
        OutlinedButton.icon(
          icon: const Icon(LucideIcons.clock, size: 14),
          onPressed: () => _pickEnd(context),
          label: Text(_format(window.endMinutes)),
        ),
        if (window.endMinutes < window.startMinutes) ...[
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            '(crosses midnight)',
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
        ],
      ],
    );
  }

  Future<void> _pickStart(BuildContext context) async {
    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: window.startMinutes ~/ 60,
        minute: window.startMinutes % 60,
      ),
    );
    if (tod == null) return;
    onChange(TargetTimeWindow(
      startMinutes: tod.hour * 60 + tod.minute,
      endMinutes: window.endMinutes,
    ));
  }

  Future<void> _pickEnd(BuildContext context) async {
    final tod = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: window.endMinutes ~/ 60,
        minute: window.endMinutes % 60,
      ),
    );
    if (tod == null) return;
    onChange(TargetTimeWindow(
      startMinutes: window.startMinutes,
      endMinutes: tod.hour * 60 + tod.minute,
    ));
  }

  String _format(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

class _MoonField extends StatelessWidget {
  final double value;
  final void Function(double) onChange;
  const _MoonField({required this.value, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Row(
      children: [
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            divisions: 100,
            label: '${(value * 100).round()} %',
            onChanged: onChange,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '${(value * 100).round()} %',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _HorizonField extends StatelessWidget {
  final int? selectedId;
  final List<HorizonProfile> profiles;
  final void Function(int) onChange;

  const _HorizonField({
    required this.selectedId,
    required this.profiles,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    if (profiles.isEmpty) {
      return Text(
        'No horizon profiles defined yet.',
        style: TextStyle(fontSize: 12, color: colors.warning),
      );
    }
    return DropdownButton<int>(
      value: selectedId,
      isExpanded: true,
      hint: const Text('Choose horizon profile'),
      items: [
        for (final p in profiles)
          DropdownMenuItem(value: p.id!, child: Text(p.name)),
      ],
      onChanged: (id) {
        if (id != null) onChange(id);
      },
    );
  }
}

class _AddConstraintMenu extends StatelessWidget {
  final int targetId;
  final Set<TargetConstraintKind> existingKinds;
  final List<HorizonProfile> horizonProfiles;
  final Future<void> Function(TargetConstraint) onAdd;

  const _AddConstraintMenu({
    required this.targetId,
    required this.existingKinds,
    required this.horizonProfiles,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = TargetConstraintKind.values
        .where((k) => !existingKinds.contains(k))
        .toList();
    if (remaining.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<TargetConstraintKind>(
      tooltip: 'Add constraint',
      onSelected: (kind) async {
        final TargetConstraint c;
        switch (kind) {
          case TargetConstraintKind.timeWindow:
            c = TargetConstraint(
              targetId: targetId,
              kind: kind,
              timeWindow: const TargetTimeWindow(
                startMinutes: 22 * 60,
                endMinutes: 5 * 60,
              ),
            );
            break;
          case TargetConstraintKind.moonIlluminationMax:
            c = TargetConstraint(
              targetId: targetId,
              kind: kind,
              moonIlluminationMax: 0.5,
            );
            break;
          case TargetConstraintKind.customHorizon:
            if (horizonProfiles.isEmpty) {
              throw StateError(
                'Cannot add a customHorizon constraint: no HorizonProfile rows '
                'exist. Create a horizon profile first.',
              );
            }
            c = TargetConstraint(
              targetId: targetId,
              kind: kind,
              customHorizonId: horizonProfiles.first.id,
            );
            break;
        }
        await onAdd(c);
      },
      itemBuilder: (context) => [
        for (final k in remaining)
          PopupMenuItem(
            value: k,
            child: Text(_label(k)),
          ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.plus, size: 14),
            SizedBox(width: 4),
            Text('Add constraint'),
          ],
        ),
      ),
    );
  }

  String _label(TargetConstraintKind k) {
    switch (k) {
      case TargetConstraintKind.timeWindow:
        return 'Time window';
      case TargetConstraintKind.moonIlluminationMax:
        return 'Max moon illumination';
      case TargetConstraintKind.customHorizon:
        return 'Custom horizon';
    }
  }
}
