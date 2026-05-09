import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'node_property_widgets.dart';

class LoopProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final LoopNode node;

  const LoopProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Loop Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Condition Type',
          child: NodeDropdown<LoopConditionType>(
            colors: colors,
            value: node.conditionType,
            items: LoopConditionType.values,
            labelBuilder: (t) {
              switch (t) {
                case LoopConditionType.count:
                  return 'Fixed Count';
                case LoopConditionType.untilTime:
                  return 'Until Time';
                case LoopConditionType.untilAltitude:
                  return 'Until Altitude Below';
                case LoopConditionType.altitudeAbove:
                  return 'Until Altitude Above';
                case LoopConditionType.integrationTime:
                  return 'Until Integration Time';
                case LoopConditionType.forever:
                  return 'Forever';
                case LoopConditionType.whileDark:
                  return 'While Dark';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(conditionType: value),
                  );
            },
          ),
        ),
        if (node.conditionType == LoopConditionType.count)
          NodePropertyField(
            colors: colors,
            label: 'Repeat Count',
            child: NodeNumberInput(
              colors: colors,
              value: (node.repeatCount ?? 1).toDouble(),
              min: 1,
              max: 9999,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(repeatCount: value.toInt()),
                    );
              },
            ),
          ),
        if (node.conditionType == LoopConditionType.untilTime)
          NodePropertyField(
            colors: colors,
            label: 'Stop Time',
            child: Column(
              children: [
                GestureDetector(
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                          node.repeatUntil ?? DateTime.now()),
                    );
                    if (time != null) {
                      final now = DateTime.now();
                      var targetDate = DateTime(
                          now.year, now.month, now.day, time.hour, time.minute);
                      if (targetDate.isBefore(now)) {
                        targetDate = targetDate.add(const Duration(days: 1));
                      }
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(repeatUntil: targetDate),
                          );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.clock,
                            size: 14, color: colors.textMuted),
                        const SizedBox(width: 8),
                        Text(
                          node.repeatUntil != null
                              ? '${node.repeatUntil!.hour.toString().padLeft(2, '0')}:${node.repeatUntil!.minute.toString().padLeft(2, '0')}'
                              : 'Select time...',
                          style: TextStyle(
                            fontSize: 13,
                            color: node.repeatUntil != null
                                ? colors.textPrimary
                                : colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Quick set buttons for common times
                Row(
                  children: [
                    NodeQuickTimeButton(
                      colors: colors,
                      label: 'Civil Dawn',
                      onPressed: () {
                        final location = ref.read(observerLocationProvider);
                        final now = DateTime.now();

                        // Calculate for today first
                        var twilight =
                            AstronomyCalculations.calculateTwilightTimes(
                          date: now,
                          latitudeDeg: location.latitude,
                          longitudeDeg: location.longitude,
                        );

                        var target = twilight.civilDawn;

                        // If dawn passed or not available today, try tomorrow
                        if (target == null || target.isBefore(now)) {
                          twilight =
                              AstronomyCalculations.calculateTwilightTimes(
                            date: now.add(const Duration(days: 1)),
                            latitudeDeg: location.latitude,
                            longitudeDeg: location.longitude,
                          );
                          target = twilight.civilDawn;
                        }

                        if (target != null) {
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(repeatUntil: target),
                              );
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    NodeQuickTimeButton(
                      colors: colors,
                      label: 'Nautical Dawn',
                      onPressed: () {
                        final location = ref.read(observerLocationProvider);
                        final now = DateTime.now();

                        // Calculate for today first
                        var twilight =
                            AstronomyCalculations.calculateTwilightTimes(
                          date: now,
                          latitudeDeg: location.latitude,
                          longitudeDeg: location.longitude,
                        );

                        var target = twilight.nauticalDawn;

                        // If dawn passed or not available today, try tomorrow
                        if (target == null || target.isBefore(now)) {
                          twilight =
                              AstronomyCalculations.calculateTwilightTimes(
                            date: now.add(const Duration(days: 1)),
                            latitudeDeg: location.latitude,
                            longitudeDeg: location.longitude,
                          );
                          target = twilight.nauticalDawn;
                        }

                        if (target != null) {
                          ref.read(currentSequenceProvider.notifier).updateNode(
                                node.copyWith(repeatUntil: target),
                              );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (node.conditionType == LoopConditionType.untilAltitude)
          NodePropertyField(
            colors: colors,
            label: 'Stop Below Altitude',
            child: NodeNumberInput(
              colors: colors,
              value: node.repeatUntilAltitude ?? 30,
              suffix: '\u00B0',
              min: 0,
              max: 90,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(repeatUntilAltitude: value),
                    );
              },
            ),
          ),
        if (node.conditionType == LoopConditionType.altitudeAbove)
          NodePropertyField(
            colors: colors,
            label: 'Loop Until Above Altitude',
            child: NodeNumberInput(
              colors: colors,
              value: node.repeatUntilAltitude ?? 30,
              suffix: '\u00B0',
              min: 0,
              max: 90,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(repeatUntilAltitude: value),
                    );
              },
            ),
          ),
        if (node.conditionType == LoopConditionType.integrationTime)
          NodePropertyField(
            colors: colors,
            label: 'Target Integration Time',
            child: NodeNumberInput(
              colors: colors,
              value: (node.integrationTimeTarget ?? 3600) / 60.0,
              suffix: 'min',
              min: 1,
              max: 1440,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(integrationTimeTarget: value * 60.0),
                    );
              },
            ),
          ),

        // Safety iteration limit for unbounded loops
        if (node.isUnbounded) ...[
          const SizedBox(height: 8),
          _UnboundedLoopSafetySection(colors: colors, node: node),
        ],
      ],
    );
  }
}

/// Safety limit section for Forever/WhileDark loops.
/// Shows a warning badge if no limit is set, and provides a field to configure one.
class _UnboundedLoopSafetySection extends ConsumerWidget {
  final NightshadeColors colors;
  final LoopNode node;

  const _UnboundedLoopSafetySection({
    required this.colors,
    required this.node,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasLimit = node.maxSafetyIterations != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warning banner when no limit is set
        if (!hasLimit)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: colors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 14, color: colors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This loop has no safety limit and could run indefinitely. '
                    'Set a max iterations limit as a safety net.',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: colors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),

        NodePropertyField(
          colors: colors,
          label: 'Max Iterations (safety)',
          child: Row(
            children: [
              Expanded(
                child: NodeNumberInput(
                  colors: colors,
                  value: (node.maxSafetyIterations ?? 999).toDouble(),
                  min: 1,
                  max: 99999,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(
                              maxSafetyIterations: value.toInt()),
                        );
                  },
                ),
              ),
              if (hasLimit) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Remove safety limit',
                  child: GestureDetector(
                    onTap: () {
                      // Create a new LoopNode with maxSafetyIterations explicitly null.
                      // Since copyWith uses ?? semantics, we must construct directly.
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            LoopNode(
                              id: node.id,
                              name: node.name,
                              isEnabled: node.isEnabled,
                              childIds: node.childIds,
                              parentId: node.parentId,
                              orderIndex: node.orderIndex,
                              comment: node.comment,
                              conditionType: node.conditionType,
                              repeatCount: node.repeatCount,
                              repeatUntil: node.repeatUntil,
                              repeatUntilAltitude: node.repeatUntilAltitude,
                              integrationTimeTarget:
                                  node.integrationTimeTarget,
                              maxSafetyIterations: null,
                            ),
                          );
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.border),
                      ),
                      child: Icon(LucideIcons.x,
                          size: 14, color: colors.textMuted),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Info box
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 12, color: colors.info),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasLimit
                      ? 'Loop will stop after ${node.maxSafetyIterations} iterations even if the condition is still met.'
                      : 'Tap the field above to set a safety limit (recommended: 999).',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 11),
                    color: colors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class WaitTimeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final WaitTimeNode node;

  const WaitTimeProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wait Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Wait For',
          child: NodeDropdown<String>(
            colors: colors,
            value: node.waitForTwilight != null ? 'twilight' : 'time',
            items: const ['time', 'twilight'],
            labelBuilder: (v) => v == 'time' ? 'Specific Time' : 'Twilight',
            onChanged: (value) {
              if (value == 'twilight') {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(
                          waitForTwilight: TwilightType.astronomical,
                          waitUntil: null),
                    );
              } else {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(waitForTwilight: null),
                    );
              }
            },
          ),
        ),
        if (node.waitForTwilight != null) ...[
          NodePropertyField(
            colors: colors,
            label: 'Twilight Type',
            child: NodeDropdown<TwilightType>(
              colors: colors,
              value: node.waitForTwilight!,
              items: TwilightType.values,
              labelBuilder: (t) {
                switch (t) {
                  case TwilightType.civil:
                    return 'Civil (-6\u00B0)';
                  case TwilightType.nautical:
                    return 'Nautical (-12\u00B0)';
                  case TwilightType.astronomical:
                    return 'Astronomical (-18\u00B0)';
                }
              },
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(waitForTwilight: value),
                    );
              },
            ),
          ),
        ],
        if (node.waitForTwilight == null) ...[
          NodePropertyField(
            colors: colors,
            label: 'Wait Until',
            child: GestureDetector(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  final now = DateTime.now();
                  var targetDate = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                  if (targetDate.isBefore(now)) {
                    targetDate = targetDate.add(const Duration(days: 1));
                  }
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        node.copyWith(waitUntil: targetDate),
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
                    Text(
                      node.waitUntil != null
                          ? '${node.waitUntil!.hour.toString().padLeft(2, '0')}:${node.waitUntil!.minute.toString().padLeft(2, '0')}'
                          : 'Select time...',
                      style: TextStyle(
                        fontSize: 13,
                        color: node.waitUntil != null
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ConditionalProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ConditionalNode node;

  const ConditionalProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Condition Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Condition Type',
          child: NodeDropdown<ConditionalType>(
            colors: colors,
            value: node.conditionType,
            items: ConditionalType.values,
            labelBuilder: (t) {
              switch (t) {
                case ConditionalType.always:
                  return 'Always Execute';
                case ConditionalType.altitudeAbove:
                  return 'Altitude Above';
                case ConditionalType.timeAfter:
                  return 'Time After';
                case ConditionalType.guidingRmsBelow:
                  return 'Guiding RMS Below';
                case ConditionalType.hfrBelow:
                  return 'HFR Below';
                case ConditionalType.weatherSafe:
                  return 'Weather is Safe';
                case ConditionalType.moonSeparationAbove:
                  return 'Moon Separation Above';
                case ConditionalType.safetyMonitorSafe:
                  return 'Safety Monitor Safe';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(conditionType: value),
                  );
            },
          ),
        ),
        if (node.conditionType == ConditionalType.altitudeAbove ||
            node.conditionType == ConditionalType.moonSeparationAbove)
          NodePropertyField(
            colors: colors,
            label: 'Threshold (degrees)',
            child: NodeNumberInput(
              colors: colors,
              value: node.thresholdValue ?? 30,
              suffix: '\u00B0',
              min: 0,
              max: 90,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(thresholdValue: value),
                    );
              },
            ),
          ),
        if (node.conditionType == ConditionalType.guidingRmsBelow)
          NodePropertyField(
            colors: colors,
            label: 'Max RMS (arcsec)',
            child: NodeNumberInput(
              colors: colors,
              value: node.thresholdValue ?? 1.5,
              suffix: '"',
              min: 0.1,
              max: 10,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(thresholdValue: value),
                    );
              },
            ),
          ),
        if (node.conditionType == ConditionalType.hfrBelow)
          NodePropertyField(
            colors: colors,
            label: 'Max HFR (pixels)',
            child: NodeNumberInput(
              colors: colors,
              value: node.thresholdValue ?? 3.0,
              suffix: 'px',
              min: 0.5,
              max: 20,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(thresholdValue: value),
                    );
              },
            ),
          ),
        if (node.conditionType == ConditionalType.timeAfter)
          NodePropertyField(
            colors: colors,
            label: 'Execute After Time',
            child: GestureDetector(
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(
                      node.thresholdTime ?? DateTime.now()),
                );
                if (time != null) {
                  final now = DateTime.now();
                  var targetDate = DateTime(
                      now.year, now.month, now.day, time.hour, time.minute);
                  if (targetDate.isBefore(now)) {
                    targetDate = targetDate.add(const Duration(days: 1));
                  }
                  ref.read(currentSequenceProvider.notifier).updateNode(
                        node.copyWith(thresholdTime: targetDate),
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
                    Icon(LucideIcons.clock,
                        size: 14, color: colors.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      node.thresholdTime != null
                          ? '${node.thresholdTime!.hour.toString().padLeft(2, '0')}:${node.thresholdTime!.minute.toString().padLeft(2, '0')}'
                          : 'Select time...',
                      style: TextStyle(
                        fontSize: 13,
                        color: node.thresholdTime != null
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ParallelProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ParallelNode node;

  const ParallelProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parallel Execution',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Required Successes',
          child: NodeNumberInput(
            colors: colors,
            value: (node.requiredSuccesses ?? 1).toDouble(),
            min: 1,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(requiredSuccesses: value.toInt()),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'All child nodes will execute simultaneously. Node succeeds when required number of children complete.',
                  style: TextStyle(
                    fontSize: Responsive.fontSize(context, 12),
                    color: colors.info,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class RecoveryProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RecoveryNode node;

  const RecoveryProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Trigger Type',
          child: NodeDropdown<TriggerType?>(
            colors: colors,
            value: node.triggerType,
            items: const [null, ...TriggerType.values],
            labelBuilder: (t) {
              if (t == null) return 'Any Error';
              switch (t) {
                case TriggerType.hfrDegraded:
                  return 'HFR Degraded';
                case TriggerType.meridianFlip:
                  return 'Meridian Flip Needed';
                case TriggerType.guidingFailed:
                  return 'Guiding Failed';
                case TriggerType.altitudeLimit:
                  return 'Altitude Limit';
                case TriggerType.weatherUnsafe:
                  return 'Weather Unsafe';
                case TriggerType.temperatureShift:
                  return 'Temperature Shift';
                case TriggerType.filterChange:
                  return 'Filter Change';
                case TriggerType.dawnApproaching:
                  return 'Dawn Approaching';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(triggerType: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Recovery Action',
          child: NodeDropdown<RecoveryActionType>(
            colors: colors,
            value: node.recoveryAction,
            items: RecoveryActionType.values,
            labelBuilder: (a) {
              switch (a) {
                case RecoveryActionType.continueExecution:
                  return 'Continue';
                case RecoveryActionType.pause:
                  return 'Pause Sequence';
                case RecoveryActionType.autofocus:
                  return 'Run Autofocus';
                case RecoveryActionType.nextTarget:
                  return 'Skip to Next Target';
                case RecoveryActionType.retry:
                  return 'Retry Operation';
                case RecoveryActionType.parkAndAbort:
                  return 'Park & Abort';
                case RecoveryActionType.customBranch:
                  return 'Custom Branch';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(recoveryAction: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Max Retries',
          child: NodeNumberInput(
            colors: colors,
            value: node.maxRetries.toDouble(),
            min: 1,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxRetries: value.toInt()),
                  );
            },
          ),
        ),
        if (node.triggerType == TriggerType.hfrDegraded) ...[
          NodePropertyField(
            colors: colors,
            label: 'Absolute HFR Threshold',
            child: NodeNumberInput(
              colors: colors,
              value: node.triggerThreshold ?? 0.0,
              suffix: 'px',
              min: 0,
              max: 20,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(triggerThreshold: value),
                    );
              },
            ),
          ),
          NodePropertyField(
            colors: colors,
            label: '% Above Baseline',
            child: NodeNumberInput(
              colors: colors,
              value: node.hfrThresholdPercent,
              suffix: '%',
              min: 0,
              max: 100,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(hfrThresholdPercent: value),
                    );
              },
            ),
          ),
          NodePropertyField(
            colors: colors,
            label: 'Consecutive Frames',
            child: NodeNumberInput(
              colors: colors,
              value: node.hfrConsecutiveFrames.toDouble(),
              suffix: '',
              min: 1,
              max: 20,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(hfrConsecutiveFrames: value.toInt()),
                    );
              },
            ),
          ),
        ],
        if (node.triggerType == TriggerType.altitudeLimit)
          NodePropertyField(
            colors: colors,
            label: 'Min Altitude',
            child: NodeNumberInput(
              colors: colors,
              value: node.triggerThreshold ?? 30,
              suffix: '\u00B0',
              min: 0,
              max: 90,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(triggerThreshold: value),
                    );
              },
            ),
          ),
      ],
    );
  }
}
