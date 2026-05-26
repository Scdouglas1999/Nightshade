import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'framing_assistant_inline.dart';
import 'node_property_widgets.dart';

enum _BrightnessTierChoice {
  auto(null, 'Auto (infer from target)'),
  faint(BrightnessTier.faint, 'Faint (galaxies, dim nebulae)'),
  medium(BrightnessTier.medium, 'Medium (bright galaxies, dim nebulae)'),
  bright(BrightnessTier.bright, 'Bright (planetary nebulae, open clusters)');

  final BrightnessTier? tier;
  final String label;

  const _BrightnessTierChoice(this.tier, this.label);

  static _BrightnessTierChoice fromTier(BrightnessTier? tier) {
    for (final choice in values) {
      if (choice.tier == tier) return choice;
    }
    return auto;
  }
}

class TargetGroupProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;

  const TargetGroupProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Trust-patch §B: belt-and-suspenders gate. The parent
    // `NodePropertiesPanel` already wraps the editor body in
    // AbsorbPointer when [canEditSequenceProvider] is false, but we
    // also wrap our own subtree in IgnorePointer here. This guarantees
    // that any future refactor that extracts this widget out of the
    // panel can't lose the gate silently — the safety reads as
    // intentional in the code, not implicit through ancestor wrapping.
    final canEdit = ref.watch(canEditSequenceProvider);
    return IgnorePointer(
      ignoring: !canEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target Settings',
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          NodePropertyField(
            colors: colors,
            label: 'Target Name',
            child: NodeTextInput(
              colors: colors,
              value: node.targetName,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(targetName: value),
                    );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'RA (hours)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.raHours,
                    suffix: 'h',
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(raHours: value),
                          );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'Dec (degrees)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.decDegrees,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(decDegrees: value),
                          );
                    },
                  ),
                ),
              ),
            ],
          ),
          NodePropertyField(
            colors: colors,
            label: 'Rotation (optional)',
            child: NodeNumberInput(
              colors: colors,
              value: node.rotation ?? 0,
              suffix: '\u00B0',
              min: 0,
              max: 360,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(rotation: value),
                    );
              },
            ),
          ),
          // Wave 5 Agent 1 \u2014 Frame target affordance. Opens the
          // planetarium framing assistant in a full-screen modal so the
          // user can drag the FOV outline to align rotation against the
          // sky. Disabled while the sequencer is running (the wrapping
          // IgnorePointer above the whole TargetGroupProperties handles
          // that case for us).
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              width: double.infinity,
              child: NightshadeButton(
                onPressed: () async {
                  final newRotation = await showFramingAssistantDialog(
                    context: context,
                    ref: ref,
                    target: node,
                  );
                  if (newRotation != null) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(rotation: newRotation),
                        );
                  }
                },
                icon: LucideIcons.scanLine,
                label: 'Frame target',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
              ),
            ),
          ),
          NodePropertyField(
            colors: colors,
            label: 'Priority',
            child: NodeNumberInput(
              colors: colors,
              value: node.priority.toDouble(),
              min: 0,
              max: 100,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(priority: value.toInt()),
                    );
              },
            ),
          ),
          NodePropertyField(
            colors: colors,
            label: 'Adaptive Brightness Tier',
            child: NodeDropdown<_BrightnessTierChoice>(
              colors: colors,
              value: _BrightnessTierChoice.fromTier(node.brightnessTierHint),
              items: _BrightnessTierChoice.values,
              labelBuilder: (choice) => choice.label,
              onChanged: (choice) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(brightnessTierHint: choice.tier),
                    );
              },
            ),
          ),
          Row(
            children: [
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'Min Altitude',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.minAltitude ?? 30,
                    suffix: '\u00B0',
                    min: 0,
                    max: 90,
                    decimals: 0,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(minAltitude: value),
                          );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'Max Altitude',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.maxAltitude ?? 90,
                    suffix: '\u00B0',
                    min: 0,
                    max: 90,
                    decimals: 0,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(maxAltitude: value),
                          );
                    },
                  ),
                ),
              ),
            ],
          ),
          NodePropertyField(
            colors: colors,
            label: 'Start After (optional)',
            child: GestureDetector(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime:
                      TimeOfDay.fromDateTime(node.startAfter ?? DateTime.now()),
                );
                if (time != null) {
                  final now = DateTime.now();
                  var targetDate = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                  if (targetDate.isBefore(now)) {
                    targetDate = targetDate.add(const Duration(days: 1));
                  }
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        node.copyWith(startAfter: targetDate),
                      );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        node.startAfter != null
                            ? '${node.startAfter!.hour.toString().padLeft(2, '0')}:${node.startAfter!.minute.toString().padLeft(2, '0')}'
                            : 'Not set',
                        style: TextStyle(
                          fontSize: 13,
                          color: node.startAfter != null
                              ? colors.textPrimary
                              : colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          NodePropertyField(
            colors: colors,
            label: 'End Before (optional)',
            child: GestureDetector(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime:
                      TimeOfDay.fromDateTime(node.endBefore ?? DateTime.now()),
                );
                if (time != null) {
                  final now = DateTime.now();
                  var targetDate = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                  if (targetDate.isBefore(now)) {
                    targetDate = targetDate.add(const Duration(days: 1));
                  }
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        node.copyWith(endBefore: targetDate),
                      );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        node.endBefore != null
                            ? '${node.endBefore!.hour.toString().padLeft(2, '0')}:${node.endBefore!.minute.toString().padLeft(2, '0')}'
                            : 'Not set',
                        style: TextStyle(
                          fontSize: 13,
                          color: node.endBefore != null
                              ? colors.textPrimary
                              : colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Wave 4 — start_when / end_when crossings editor.
          const SizedBox(height: 16),
          _TriggerSection(
            colors: colors,
            node: node,
            isStart: true,
          ),
          const SizedBox(height: 8),
          _TriggerSection(
            colors: colors,
            node: node,
            isStart: false,
          ),
          // Wave 3 Agent 3 — Per-target integration budget editor.
          const SizedBox(height: 16),
          _IntegrationBudgetSection(colors: colors, node: node),
        ],
      ),
    );
  }
}

// =============================================================================
// Wave 4 — Start-when / End-when trigger editor.
//
// One section per direction (start vs end). Each section is toggle-gated:
// when off, the trigger is null (no gate). When on, the user picks a kind
// from a dropdown and edits the parameters inline. Compound triggers
// (And/Or) get a nested row of sub-triggers.
// =============================================================================

class _TriggerSection extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;
  final bool isStart;

  const _TriggerSection({
    required this.colors,
    required this.node,
    required this.isStart,
  });

  TargetTrigger? get _current => isStart ? node.startWhen : node.endWhen;
  String get _label => isStart ? 'Start when' : 'End when';
  String get _helpText => isStart
      ? 'Wait until this condition is true before imaging the target. '
          'Common: AltitudeAbove(35°).'
      : 'Stop imaging once this condition becomes true. '
          'Common: AltitudeBelow(30°).';

  void _setTrigger(WidgetRef ref, TargetTrigger? next) {
    if (isStart) {
      ref.read(currentSequenceProvider.notifier).updateNode(
            node.copyWith(startWhen: next),
          );
    } else {
      ref.read(currentSequenceProvider.notifier).updateNode(
            node.copyWith(endWhen: next),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = _current;
    final enabled = current != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isStart ? LucideIcons.playCircle : LucideIcons.stopCircle,
                size: 14,
                color: colors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label,
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              NodeToggleSwitch(
                colors: colors,
                value: enabled,
                onChanged: (on) {
                  if (on) {
                    // Default trigger: AltitudeAbove(35°) for start,
                    // AltitudeBelow(30°) for end — matches the SGP/NINA
                    // defaults most amateur users want.
                    _setTrigger(
                        ref,
                        isStart
                            ? const AltitudeAboveTrigger(35.0)
                            : const AltitudeBelowTrigger(30.0));
                  } else {
                    _setTrigger(ref, null);
                  }
                },
              ),
            ],
          ),
          if (current != null) ...[
            const SizedBox(height: 12),
            _TriggerBuilder(
              colors: colors,
              trigger: current,
              onChanged: (next) => _setTrigger(ref, next),
            ),
            const SizedBox(height: 8),
            _TriggerPreview(
              colors: colors,
              node: node,
              trigger: current,
              isStart: isStart,
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(_helpText,
                style: TextStyle(fontSize: 11, color: colors.textMuted)),
          ],
        ],
      ),
    );
  }
}

/// Trigger editor — dropdown for kind + inline parameter inputs. For
/// compound (And/Or) kinds, renders a list of nested editors so the user
/// can build "wait for X AND Y" with another tap.
class _TriggerBuilder extends StatelessWidget {
  final NightshadeColors colors;
  final TargetTrigger trigger;
  final ValueChanged<TargetTrigger> onChanged;

  const _TriggerBuilder({
    required this.colors,
    required this.trigger,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<String>(
          isExpanded: true,
          value: _kindKey(trigger),
          dropdownColor: colors.surfaceAlt,
          style: TextStyle(fontSize: 12, color: colors.textPrimary),
          items: const [
            DropdownMenuItem(
                value: 'AltitudeAbove', child: Text('Altitude above')),
            DropdownMenuItem(
                value: 'AltitudeBelow', child: Text('Altitude below')),
            DropdownMenuItem(value: 'TimeAfter', child: Text('Time after')),
            DropdownMenuItem(value: 'TimeBefore', child: Text('Time before')),
            DropdownMenuItem(
                value: 'HourAngleBetween', child: Text('Hour angle in range')),
            DropdownMenuItem(value: 'And', child: Text('All of (AND)')),
            DropdownMenuItem(value: 'Or', child: Text('Any of (OR)')),
          ],
          onChanged: (next) {
            if (next == null) return;
            onChanged(_defaultForKind(next, current: trigger));
          },
        ),
        const SizedBox(height: 8),
        _ParamsEditor(
          colors: colors,
          trigger: trigger,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ParamsEditor extends StatelessWidget {
  final NightshadeColors colors;
  final TargetTrigger trigger;
  final ValueChanged<TargetTrigger> onChanged;

  const _ParamsEditor({
    required this.colors,
    required this.trigger,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (trigger) {
      case AltitudeAboveTrigger(altitudeDeg: final v):
        return _altitudeInput(v, (n) => onChanged(AltitudeAboveTrigger(n)));
      case AltitudeBelowTrigger(altitudeDeg: final v):
        return _altitudeInput(v, (n) => onChanged(AltitudeBelowTrigger(n)));
      case TimeAfterTrigger(unixSeconds: final v):
        return _timeInput(v, (n) => onChanged(TimeAfterTrigger(n)));
      case TimeBeforeTrigger(unixSeconds: final v):
        return _timeInput(v, (n) => onChanged(TimeBeforeTrigger(n)));
      case HourAngleBetweenTrigger(minHa: final lo, maxHa: final hi):
        return Row(
          children: [
            Expanded(
              child: NodeNumberInput(
                colors: colors,
                value: lo,
                suffix: 'h',
                min: -12,
                max: 12,
                decimals: 2,
                onChanged: (n) =>
                    onChanged(HourAngleBetweenTrigger(minHa: n, maxHa: hi)),
              ),
            ),
            const SizedBox(width: 8),
            Text(' to ',
                style: TextStyle(fontSize: 12, color: colors.textMuted)),
            const SizedBox(width: 8),
            Expanded(
              child: NodeNumberInput(
                colors: colors,
                value: hi,
                suffix: 'h',
                min: -12,
                max: 12,
                decimals: 2,
                onChanged: (n) =>
                    onChanged(HourAngleBetweenTrigger(minHa: lo, maxHa: n)),
              ),
            ),
          ],
        );
      case AndTrigger(children: final cs) || OrTrigger(children: final cs):
        final isAnd = trigger is AndTrigger;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...cs.asMap().entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _TriggerBuilder(
                            colors: colors,
                            trigger: e.value,
                            onChanged: (next) {
                              final newList = List<TargetTrigger>.from(cs);
                              newList[e.key] = next;
                              onChanged(isAnd
                                  ? AndTrigger(newList)
                                  : OrTrigger(newList));
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(LucideIcons.x,
                              size: 14, color: colors.textMuted),
                          tooltip: 'Remove sub-trigger',
                          onPressed: () {
                            final newList = List<TargetTrigger>.from(cs)
                              ..removeAt(e.key);
                            onChanged(isAnd
                                ? AndTrigger(newList)
                                : OrTrigger(newList));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            TextButton.icon(
              onPressed: () {
                final newList = List<TargetTrigger>.from(cs)
                  ..add(const AltitudeAboveTrigger(35.0));
                onChanged(isAnd ? AndTrigger(newList) : OrTrigger(newList));
              },
              icon: Icon(LucideIcons.plus, size: 14, color: colors.primary),
              label: Text('Add sub-trigger',
                  style: TextStyle(fontSize: 12, color: colors.primary)),
            ),
          ],
        );
    }
  }

  Widget _altitudeInput(double value, ValueChanged<double> onChanged) {
    return NodeNumberInput(
      colors: colors,
      value: value,
      suffix: '°',
      min: -90,
      max: 90,
      decimals: 1,
      onChanged: onChanged,
    );
  }

  Widget _timeInput(int unixSecs, ValueChanged<int> onChanged) {
    return _TimeInputButton(
      colors: colors,
      unixSecs: unixSecs,
      onChanged: onChanged,
    );
  }
}

/// Small leaf widget so `showTimePicker` has a real BuildContext to
/// anchor against.
class _TimeInputButton extends StatelessWidget {
  final NightshadeColors colors;
  final int unixSecs;
  final ValueChanged<int> onChanged;

  const _TimeInputButton({
    required this.colors,
    required this.unixSecs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000);
    final hhmm =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(dt),
        );
        if (picked != null) {
          final now = DateTime.now();
          var target = DateTime(
              now.year, now.month, now.day, picked.hour, picked.minute);
          if (target.isBefore(now)) {
            target = target.add(const Duration(days: 1));
          }
          onChanged(target.millisecondsSinceEpoch ~/ 1000);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
            const SizedBox(width: 8),
            Text(hhmm,
                style: TextStyle(fontSize: 13, color: colors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

/// Live preview text for the current trigger. Mirrors the Rust
/// `TargetTrigger::label` plus a short evaluation against the live
/// observer location.
class _TriggerPreview extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;
  final TargetTrigger trigger;
  final bool isStart;

  const _TriggerPreview({
    required this.colors,
    required this.node,
    required this.trigger,
    required this.isStart,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = trigger.label;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.eye, size: 12, color: colors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${isStart ? "Starts when" : "Ends when"} $summary',
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

String _kindKey(TargetTrigger t) {
  switch (t) {
    case AltitudeAboveTrigger():
      return 'AltitudeAbove';
    case AltitudeBelowTrigger():
      return 'AltitudeBelow';
    case TimeAfterTrigger():
      return 'TimeAfter';
    case TimeBeforeTrigger():
      return 'TimeBefore';
    case AndTrigger():
      return 'And';
    case OrTrigger():
      return 'Or';
    case HourAngleBetweenTrigger():
      return 'HourAngleBetween';
  }
}

/// Build a sensible default trigger for the given kind, preserving as
/// much of the user's existing config as possible (e.g. switching
/// AltitudeAbove -> AltitudeBelow keeps the threshold).
TargetTrigger _defaultForKind(String kind, {required TargetTrigger current}) {
  double currentAlt() {
    if (current is AltitudeAboveTrigger) return current.altitudeDeg;
    if (current is AltitudeBelowTrigger) return current.altitudeDeg;
    return 35.0;
  }

  switch (kind) {
    case 'AltitudeAbove':
      return AltitudeAboveTrigger(currentAlt());
    case 'AltitudeBelow':
      return AltitudeBelowTrigger(currentAlt());
    case 'TimeAfter':
      return TimeAfterTrigger(
          (DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch /
                  1000)
              .toInt());
    case 'TimeBefore':
      return TimeBeforeTrigger(
          (DateTime.now().add(const Duration(hours: 6)).millisecondsSinceEpoch /
                  1000)
              .toInt());
    case 'HourAngleBetween':
      return const HourAngleBetweenTrigger(minHa: -1, maxHa: 1);
    case 'And':
      return AndTrigger([current]);
    case 'Or':
      return OrTrigger([current]);
    default:
      return current;
  }
}

// =============================================================================
// Wave 3 Agent 3 — Integration budget editor.
//
// The section is toggle-gated: when the toggle is off, the node has no
// budget configured. When on, the user can set a total time and add
// per-filter rows (Absolute seconds or Ratio). The live preview shows
// the resolved per-filter caps so the user can sanity-check before
// pressing Save.
// =============================================================================

class _IntegrationBudgetSection extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;

  const _IntegrationBudgetSection({
    required this.colors,
    required this.node,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budget = node.integrationBudget;
    final enabled = budget != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.target, size: 14, color: colors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Integration budget',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              NodeToggleSwitch(
                colors: colors,
                value: enabled,
                onChanged: (on) {
                  if (on) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(
                              integrationBudget: const IntegrationBudget()),
                        );
                  } else {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(integrationBudget: null),
                        );
                  }
                },
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            _BudgetEditor(colors: colors, node: node, budget: budget),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Stop a target once it has accumulated N hours of '
              'integration, with optional per-filter caps or ratios.',
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BudgetEditor extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;
  final IntegrationBudget budget;

  const _BudgetEditor({
    required this.colors,
    required this.node,
    required this.budget,
  });

  void _updateBudget(WidgetRef ref, IntegrationBudget next) {
    ref
        .read(currentSequenceProvider.notifier)
        .updateNode(node.copyWith(integrationBudget: next));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Total time (hours)',
          child: NodeNumberInput(
            colors: colors,
            value: budget.totalSecs / 3600.0,
            suffix: 'h',
            min: 0,
            max: 24,
            decimals: 2,
            onChanged: (value) {
              _updateBudget(ref, budget.copyWith(totalSecs: value * 3600.0));
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Per-filter caps',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        ...budget.perFilter.entries.map(
          (e) => _FilterRow(
            colors: colors,
            filterName: e.key,
            entry: e.value,
            onChanged: (next) {
              final newMap =
                  Map<String, FilterBudgetEntry>.from(budget.perFilter);
              newMap[e.key] = next;
              _updateBudget(ref, budget.copyWith(perFilter: newMap));
            },
            onRemove: () {
              final newMap =
                  Map<String, FilterBudgetEntry>.from(budget.perFilter);
              newMap.remove(e.key);
              _updateBudget(ref, budget.copyWith(perFilter: newMap));
            },
          ),
        ),
        const SizedBox(height: 4),
        _AddFilterRow(
          colors: colors,
          existingFilters: budget.perFilter.keys.toSet(),
          onAdd: (name) {
            final newMap =
                Map<String, FilterBudgetEntry>.from(budget.perFilter);
            // Default new entries to a ratio of 1 so a user clicking
            // through L/R/G/B yields the canonical 1:1:1:1.
            newMap[name] = const FilterBudgetEntry.ratio(1);
            _updateBudget(ref, budget.copyWith(perFilter: newMap));
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Stop target when budget met',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ),
            NodeToggleSwitch(
              colors: colors,
              value: budget.stopOnBudgetMet,
              onChanged: (v) {
                _updateBudget(ref, budget.copyWith(stopOnBudgetMet: v));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        _BudgetPreview(colors: colors, budget: budget),
      ],
    );
  }
}

/// One row in the per-filter list. The Absolute/Ratio toggle is a small
/// segmented control so the unit on the right always agrees with the
/// number the user is editing.
class _FilterRow extends StatelessWidget {
  final NightshadeColors colors;
  final String filterName;
  final FilterBudgetEntry entry;
  final ValueChanged<FilterBudgetEntry> onChanged;
  final VoidCallback onRemove;

  const _FilterRow({
    required this.colors,
    required this.filterName,
    required this.entry,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final isRatio = entry.isRatio;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              filterName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: NodeNumberInput(
              colors: colors,
              value: isRatio ? entry.value : entry.value / 3600.0,
              suffix: isRatio ? '' : 'h',
              min: 0,
              max: isRatio ? 100 : 24,
              decimals: 2,
              onChanged: (v) {
                if (isRatio) {
                  onChanged(FilterBudgetEntry.ratio(v));
                } else {
                  onChanged(FilterBudgetEntry.absolute(v * 3600.0));
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          _KindToggle(
            colors: colors,
            isRatio: isRatio,
            onChanged: (newRatio) {
              if (newRatio == isRatio) return;
              if (newRatio) {
                onChanged(const FilterBudgetEntry.ratio(1));
              } else {
                onChanged(const FilterBudgetEntry.absolute(3600));
              }
            },
          ),
          IconButton(
            icon: Icon(LucideIcons.x, size: 14, color: colors.textMuted),
            tooltip: 'Remove $filterName',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _KindToggle extends StatelessWidget {
  final NightshadeColors colors;
  final bool isRatio;
  final ValueChanged<bool> onChanged;

  const _KindToggle({
    required this.colors,
    required this.isRatio,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, bool active) {
      return GestureDetector(
        onTap: () => onChanged(label == 'Ratio'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active ? colors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: active ? colors.background : colors.textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill('Hours', !isRatio),
          pill('Ratio', isRatio),
        ],
      ),
    );
  }
}

class _AddFilterRow extends StatefulWidget {
  final NightshadeColors colors;
  final Set<String> existingFilters;
  final ValueChanged<String> onAdd;

  const _AddFilterRow({
    required this.colors,
    required this.existingFilters,
    required this.onAdd,
  });

  @override
  State<_AddFilterRow> createState() => _AddFilterRowState();
}

class _AddFilterRowState extends State<_AddFilterRow> {
  late final TextEditingController _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctl,
              style: TextStyle(fontSize: 12, color: widget.colors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Filter name (e.g. Ha)',
                hintStyle:
                    TextStyle(fontSize: 12, color: widget.colors.textMuted),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.colors.border),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: () {
              final name = _ctl.text.trim();
              if (name.isEmpty) return;
              if (widget.existingFilters.contains(name)) return;
              widget.onAdd(name);
              _ctl.clear();
            },
            icon:
                Icon(LucideIcons.plus, size: 14, color: widget.colors.primary),
            label: Text(
              'Add',
              style: TextStyle(fontSize: 12, color: widget.colors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live "what will this carve up to?" preview, mirroring
/// IntegrationBudget::resolved_filter_cap on the Rust side.
class _BudgetPreview extends StatelessWidget {
  final NightshadeColors colors;
  final IntegrationBudget budget;

  const _BudgetPreview({required this.colors, required this.budget});

  String _formatDuration(double secs) {
    if (secs <= 0) return '0m';
    final h = secs ~/ 3600;
    final m = ((secs % 3600) / 60).round();
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final resolved = <String, double>{
      for (final f in budget.perFilter.keys)
        if (budget.resolvedFilterCap(f) != null)
          f: budget.resolvedFilterCap(f)!,
    };

    final totalResolved = resolved.values.fold<double>(0, (a, b) => a + b);
    final summary = budget.totalSecs > 0
        ? 'Total: ${_formatDuration(budget.totalSecs)}'
        : 'Total: ${_formatDuration(totalResolved)} (sum of caps)';

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resolved budget',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
          ),
          if (resolved.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              resolved.entries
                  .map((e) => '${e.key} ${_formatDuration(e.value)}')
                  .join(' · '),
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
