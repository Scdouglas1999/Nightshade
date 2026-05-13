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
      case TargetConstraintKind.scheduledWindow:
        return 'Scheduled window';
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
      case TargetConstraintKind.scheduledWindow:
        return _ScheduledWindowField(
          window: constraint.scheduledWindow ??
              ScheduledWindow(
                startUtc: DateTime.now().toUtc(),
                endUtc: DateTime.now().toUtc().add(const Duration(hours: 6)),
                priorityBoost: 0.5,
              ),
          onChange: (w) =>
              onChange(constraint.copyWith(scheduledWindow: w)),
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

class _ScheduledWindowField extends StatelessWidget {
  final ScheduledWindow window;
  final void Function(ScheduledWindow) onChange;
  const _ScheduledWindowField(
      {required this.window, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final startLocal = window.startUtc.toLocal();
    final endLocal = window.endUtc.toLocal();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: NightshadeTokens.spaceSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.calendar, size: 14),
              onPressed: () => _pickStart(context),
              label: Text('Start ${_fmt(startLocal)}'),
            ),
            Text('to', style: TextStyle(color: colors.textSecondary)),
            OutlinedButton.icon(
              icon: const Icon(LucideIcons.calendar, size: 14),
              onPressed: () => _pickEnd(context),
              label: Text('End ${_fmt(endLocal)}'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                'Priority boost',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
            Expanded(
              child: Slider(
                value: window.priorityBoost.clamp(0.1, 1.0),
                min: 0.1,
                max: 1.0,
                divisions: 9,
                label: '+${window.priorityBoost.toStringAsFixed(1)}',
                onChanged: (v) => onChange(ScheduledWindow(
                  startUtc: window.startUtc,
                  endUtc: window.endUtc,
                  priorityBoost: v,
                )),
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '+${window.priorityBoost.toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickStart(BuildContext context) async {
    final picked = await _pickDateTime(context, window.startUtc.toLocal());
    if (picked == null) return;
    onChange(ScheduledWindow(
      startUtc: picked.toUtc(),
      endUtc: window.endUtc,
      priorityBoost: window.priorityBoost,
    ));
  }

  Future<void> _pickEnd(BuildContext context) async {
    final picked = await _pickDateTime(context, window.endUtc.toLocal());
    if (picked == null) return;
    onChange(ScheduledWindow(
      startUtc: window.startUtc,
      endUtc: picked.toUtc(),
      priorityBoost: window.priorityBoost,
    ));
  }

  String _fmt(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mn = t.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mn';
  }
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime.now().subtract(const Duration(days: 1)),
    lastDate: DateTime.now().add(const Duration(days: 365)),
  );
  if (date == null) return null;
  if (!context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class _AddConstraintButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddConstraintButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return NightshadeButton(
      key: const ValueKey('add-constraint-button'),
      label: 'Add constraint',
      icon: LucideIcons.plus,
      size: ButtonSize.small,
      variant: ButtonVariant.outline,
      onPressed: onPressed,
    );
  }
}

/// 3-step wizard for creating a new constraint. The dialog itself owns the
/// step state — selecting a kind on step 1 prefills sensible defaults so
/// step 2 starts useful immediately. The wizard returns the persisted
/// [TargetConstraint] via `Navigator.pop` on Save.
class _AddConstraintWizardDialog extends StatefulWidget {
  final int targetId;
  final String targetName;
  final List<HorizonProfile> horizonProfiles;
  final Set<TargetConstraintKind> existingKinds;

  const _AddConstraintWizardDialog({
    required this.targetId,
    required this.targetName,
    required this.horizonProfiles,
    required this.existingKinds,
  });

  @override
  State<_AddConstraintWizardDialog> createState() =>
      _AddConstraintWizardDialogState();
}

class _AddConstraintWizardDialogState
    extends State<_AddConstraintWizardDialog> {
  int _step = 1;
  TargetConstraintKind? _kind;
  TargetTimeWindow _timeWindow = const TargetTimeWindow(
    startMinutes: 22 * 60,
    endMinutes: 2 * 60,
  );
  double _moonMax = 0.30;
  int? _horizonId;
  late ScheduledWindow _scheduledWindow;

  @override
  void initState() {
    super.initState();
    if (widget.horizonProfiles.isNotEmpty) {
      _horizonId = widget.horizonProfiles.first.id;
    }
    final now = DateTime.now();
    // Defaults: today's sunset → tomorrow's sunrise approximated as
    // 20:00 → 06:00 local. Astronomical twilight varies by latitude /
    // time of year; this is the operator-friendly fallback that's
    // obviously editable on the next step.
    final start = DateTime(now.year, now.month, now.day, 20, 0);
    final end = start.add(const Duration(hours: 10));
    _scheduledWindow = ScheduledWindow(
      startUtc: start.toUtc(),
      endUtc: end.toUtc(),
      priorityBoost: 0.5,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WizardHeader(step: _step, colors: colors),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildStep(colors),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceLg),
              _buildFooter(colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(NightshadeColors colors) {
    switch (_step) {
      case 1:
        return _Step1ChooseKind(
          existingKinds: widget.existingKinds,
          selected: _kind,
          onSelect: (k) {
            setState(() {
              _kind = k;
            });
          },
        );
      case 2:
        return _Step2Params(
          targetName: widget.targetName,
          kind: _kind!,
          timeWindow: _timeWindow,
          moonMax: _moonMax,
          horizonId: _horizonId,
          horizonProfiles: widget.horizonProfiles,
          scheduledWindow: _scheduledWindow,
          onTimeWindow: (w) => setState(() => _timeWindow = w),
          onMoonMax: (v) => setState(() => _moonMax = v),
          onHorizon: (id) => setState(() => _horizonId = id),
          onScheduledWindow: (w) => setState(() => _scheduledWindow = w),
        );
      case 3:
        return _Step3Review(
          targetName: widget.targetName,
          kind: _kind!,
          timeWindow: _timeWindow,
          moonMax: _moonMax,
          horizonId: _horizonId,
          horizonProfiles: widget.horizonProfiles,
          scheduledWindow: _scheduledWindow,
        );
      default:
        throw StateError('Unknown wizard step: $_step');
    }
  }

  Widget _buildFooter(NightshadeColors colors) {
    final canAdvance = _step == 1 ? _kind != null : true;
    return Row(
      children: [
        NightshadeButton(
          label: 'Cancel',
          variant: ButtonVariant.ghost,
          size: ButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const Spacer(),
        if (_step > 1)
          NightshadeButton(
            key: const ValueKey('wizard-back'),
            label: 'Back',
            icon: LucideIcons.chevronLeft,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => setState(() => _step -= 1),
          ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        if (_step < 3)
          NightshadeButton(
            key: const ValueKey('wizard-next'),
            label: 'Next',
            icon: LucideIcons.chevronRight,
            size: ButtonSize.small,
            onPressed: canAdvance ? () => setState(() => _step += 1) : null,
          )
        else
          NightshadeButton(
            key: const ValueKey('wizard-save'),
            label: 'Save',
            icon: LucideIcons.check,
            size: ButtonSize.small,
            onPressed: _save,
          ),
      ],
    );
  }

  void _save() {
    final TargetConstraint c;
    switch (_kind!) {
      case TargetConstraintKind.timeWindow:
        c = TargetConstraint(
          targetId: widget.targetId,
          kind: _kind!,
          timeWindow: _timeWindow,
        );
        break;
      case TargetConstraintKind.moonIlluminationMax:
        c = TargetConstraint(
          targetId: widget.targetId,
          kind: _kind!,
          moonIlluminationMax: _moonMax,
        );
        break;
      case TargetConstraintKind.customHorizon:
        if (_horizonId == null) {
          throw StateError(
            'customHorizon step reached step 3 with no horizon profile id; '
            'wizard step 2 must enforce a selection.',
          );
        }
        c = TargetConstraint(
          targetId: widget.targetId,
          kind: _kind!,
          customHorizonId: _horizonId,
        );
        break;
      case TargetConstraintKind.scheduledWindow:
        c = TargetConstraint(
          targetId: widget.targetId,
          kind: _kind!,
          scheduledWindow: _scheduledWindow,
        );
        break;
    }
    Navigator.of(context).pop(c);
  }
}

class _WizardHeader extends StatelessWidget {
  final int step;
  final NightshadeColors colors;
  const _WizardHeader({required this.step, required this.colors});

  @override
  Widget build(BuildContext context) {
    String label;
    switch (step) {
      case 1:
        label = 'Step 1 of 3 — Choose constraint type';
        break;
      case 2:
        label = 'Step 2 of 3 — Set parameters';
        break;
      case 3:
        label = 'Step 3 of 3 — Review';
        break;
      default:
        label = '';
    }
    return Row(
      children: [
        Icon(LucideIcons.filter,
            size: NightshadeTokens.iconMd, color: colors.primary),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          'Add constraint',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceMd),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textMuted,
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _Step1ChooseKind extends StatelessWidget {
  final Set<TargetConstraintKind> existingKinds;
  final TargetConstraintKind? selected;
  final void Function(TargetConstraintKind) onSelect;

  const _Step1ChooseKind({
    required this.existingKinds,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'What kind of constraint?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        _KindCard(
          key: const ValueKey('wizard-kind-timeWindow'),
          kind: TargetConstraintKind.timeWindow,
          icon: LucideIcons.clock,
          title: 'Time window',
          body: 'Only image between these hours of the night.',
          selected: selected == TargetConstraintKind.timeWindow,
          disabled:
              existingKinds.contains(TargetConstraintKind.timeWindow),
          onTap: () => onSelect(TargetConstraintKind.timeWindow),
        ),
        _KindCard(
          key: const ValueKey('wizard-kind-moon'),
          kind: TargetConstraintKind.moonIlluminationMax,
          icon: LucideIcons.moon,
          title: 'Moon avoidance',
          body: 'Skip this target when the moon is bright nearby.',
          selected: selected == TargetConstraintKind.moonIlluminationMax,
          disabled: existingKinds
              .contains(TargetConstraintKind.moonIlluminationMax),
          onTap: () => onSelect(TargetConstraintKind.moonIlluminationMax),
        ),
        _KindCard(
          key: const ValueKey('wizard-kind-horizon'),
          kind: TargetConstraintKind.customHorizon,
          icon: LucideIcons.mountain,
          title: 'Custom horizon',
          body: 'Respect terrain blocking from a saved horizon profile.',
          selected: selected == TargetConstraintKind.customHorizon,
          disabled:
              existingKinds.contains(TargetConstraintKind.customHorizon),
          onTap: () => onSelect(TargetConstraintKind.customHorizon),
        ),
        _KindCard(
          key: const ValueKey('wizard-kind-scheduledWindow'),
          kind: TargetConstraintKind.scheduledWindow,
          icon: LucideIcons.calendar,
          title: 'Scheduled window',
          body: 'Force the scheduler onto this target during these hours.',
          selected: selected == TargetConstraintKind.scheduledWindow,
          // Scheduled windows are not unique per target — multiple
          // windows can be stacked.
          disabled: false,
          onTap: () => onSelect(TargetConstraintKind.scheduledWindow),
        ),
      ],
    );
  }
}

class _KindCard extends StatelessWidget {
  final TargetConstraintKind kind;
  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _KindCard({
    super.key,
    required this.kind,
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final borderColor = selected
        ? colors.primary
        : disabled
            ? colors.border.withValues(alpha: 0.4)
            : colors.border;
    final bg = selected
        ? colors.primary.withValues(alpha: 0.08)
        : disabled
            ? colors.surfaceHover
            : colors.surfaceAlt;
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: selected ? 2 : 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon,
                    size: NightshadeTokens.iconMd,
                    color: disabled
                        ? colors.textMuted
                        : selected
                            ? colors.primary
                            : colors.textSecondary),
                const SizedBox(width: NightshadeTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: disabled
                                  ? colors.textMuted
                                  : colors.textPrimary,
                            ),
                          ),
                          if (disabled) ...[
                            const SizedBox(width: NightshadeTokens.spaceSm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: colors.surfaceHover,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colors.border),
                              ),
                              child: Text(
                                'already added',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: colors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: 12,
                          color: disabled
                              ? colors.textMuted
                              : colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step2Params extends StatelessWidget {
  final String targetName;
  final TargetConstraintKind kind;
  final TargetTimeWindow timeWindow;
  final double moonMax;
  final int? horizonId;
  final List<HorizonProfile> horizonProfiles;
  final ScheduledWindow scheduledWindow;
  final void Function(TargetTimeWindow) onTimeWindow;
  final void Function(double) onMoonMax;
  final void Function(int) onHorizon;
  final void Function(ScheduledWindow) onScheduledWindow;

  const _Step2Params({
    required this.targetName,
    required this.kind,
    required this.timeWindow,
    required this.moonMax,
    required this.horizonId,
    required this.horizonProfiles,
    required this.scheduledWindow,
    required this.onTimeWindow,
    required this.onMoonMax,
    required this.onHorizon,
    required this.onScheduledWindow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    Widget body;
    switch (kind) {
      case TargetConstraintKind.timeWindow:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default 22:00 – 02:00 local — a typical imaging session. '
              'Tap a time to adjust.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _TimeWindowField(
              window: timeWindow,
              onChange: onTimeWindow,
            ),
          ],
        );
        break;
      case TargetConstraintKind.moonIlluminationMax:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Default 30% max illumination — typical for narrowband and '
              'most broadband DSO work. Increase the cap if your target '
              'tolerates more moon.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _MoonField(value: moonMax, onChange: onMoonMax),
          ],
        );
        break;
      case TargetConstraintKind.customHorizon:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (horizonProfiles.isEmpty)
              Text(
                'No horizon profiles defined yet. Manage horizon '
                'profiles in Settings → Observing site, then return here '
                'to attach one.',
                style: TextStyle(fontSize: 12, color: colors.warning),
              )
            else ...[
              Text(
                'Pick an existing horizon profile to use for $targetName.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              _HorizonField(
                selectedId: horizonId,
                profiles: horizonProfiles,
                onChange: onHorizon,
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                'Manage horizon profiles in Settings → Observing site.',
                style: TextStyle(fontSize: 11, color: colors.textMuted),
              ),
            ],
          ],
        );
        break;
      case TargetConstraintKind.scheduledWindow:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Forces the scheduler onto $targetName during the window, '
              'bypassing hysteresis. Defaults to tonight 20:00 → 06:00 '
              'local — adjust as needed.',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceMd),
            _ScheduledWindowField(
              window: scheduledWindow,
              onChange: onScheduledWindow,
            ),
          ],
        );
        break;
    }
    return body;
  }
}

class _Step3Review extends StatelessWidget {
  final String targetName;
  final TargetConstraintKind kind;
  final TargetTimeWindow timeWindow;
  final double moonMax;
  final int? horizonId;
  final List<HorizonProfile> horizonProfiles;
  final ScheduledWindow scheduledWindow;

  const _Step3Review({
    required this.targetName,
    required this.kind,
    required this.timeWindow,
    required this.moonMax,
    required this.horizonId,
    required this.horizonProfiles,
    required this.scheduledWindow,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    String typeLabel;
    String summary;
    switch (kind) {
      case TargetConstraintKind.timeWindow:
        typeLabel = 'Time window';
        summary =
            'Only image $targetName between ${_fmt(timeWindow.startMinutes)} and ${_fmt(timeWindow.endMinutes)} local time.';
        break;
      case TargetConstraintKind.moonIlluminationMax:
        typeLabel = 'Moon avoidance';
        summary =
            'Skip $targetName when the moon illumination is above ${(moonMax * 100).round()}%.';
        break;
      case TargetConstraintKind.customHorizon:
        final profile = horizonProfiles.firstWhere(
          (p) => p.id == horizonId,
          orElse: () => throw StateError(
              'No horizon profile selected on Step 3 (wizard internal bug)'),
        );
        typeLabel = 'Custom horizon';
        summary =
            'Reject $targetName when below the "${profile.name}" horizon profile at its current azimuth.';
        break;
      case TargetConstraintKind.scheduledWindow:
        final startLocal = scheduledWindow.startUtc.toLocal();
        final endLocal = scheduledWindow.endUtc.toLocal();
        typeLabel = 'Scheduled window';
        summary =
            'Force the scheduler onto $targetName from ${_fmtDt(startLocal)} '
            'to ${_fmtDt(endLocal)} local with priority boost '
            '+${scheduledWindow.priorityBoost.toStringAsFixed(1)}.';
        break;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review and save',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Container(
          width: double.infinity,
          padding: NightshadeTokens.paddingMd,
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textPrimary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmt(int mins) {
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _fmtDt(DateTime t) {
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mn = t.minute.toString().padLeft(2, '0');
    return '$mm/$dd $hh:$mn';
  }
}
