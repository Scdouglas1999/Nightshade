// Part of ../instruction_node_properties.dart -- extracted for maintainability.
//
// Rotator, slew, meridian-flip, and polar-alignment property widgets.
part of '../instruction_node_properties.dart';

class RotatorProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RotatorNode node;

  const RotatorProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotator Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Target Angle',
          child: NodeNumberInput(
            colors: colors,
            value: node.targetAngle,
            suffix: '\u00B0',
            min: 0,
            max: 360,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(targetAngle: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Relative Movement',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.relative,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(relative: value),
                  );
            },
          ),
        ),
        Text(
          node.relative
              ? 'Rotates relative to current position'
              : 'Moves to absolute position angle',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class SlewProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SlewNode node;

  const SlewProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slew Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Use Target Coordinates',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.useTargetCoords,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(useTargetCoords: value),
                  );
            },
          ),
        ),
        if (!node.useTargetCoords) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: NodePropertyField(
                  colors: colors,
                  label: 'RA (hours)',
                  child: NodeNumberInput(
                    colors: colors,
                    value: node.customRa ?? 0,
                    suffix: 'h',
                    min: 0,
                    max: 24,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customRa: value),
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
                    value: node.customDec ?? 0,
                    suffix: '\u00B0',
                    min: -90,
                    max: 90,
                    decimals: 4,
                    onChanged: (value) {
                      ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(customDec: value),
                          );
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
        if (node.useTargetCoords) ...[
          Builder(
            builder: (context) {
              final sequence = ref.watch(currentSequenceProvider);
              TargetHeaderNode? targetGroup;

              if (sequence != null) {
                // Try to find parent target group first
                try {
                  targetGroup = sequence.nodes.values
                      .whereType<TargetHeaderNode>()
                      .where((n) => n.childIds.contains(node.id))
                      .first;
                } catch (e) {
                  // No direct parent found
                }

                // If no direct parent, use first target group in sequence
                if (targetGroup == null && sequence.targetHeaders.isNotEmpty) {
                  targetGroup = sequence.targetHeaders.first;
                }
              }

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: NightshadeDecorations.tintedBadge(
                  targetGroup != null ? colors.success : colors.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      targetGroup != null
                          ? LucideIcons.checkCircle
                          : LucideIcons.alertCircle,
                      size: 14,
                      color:
                          targetGroup != null ? colors.success : colors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        targetGroup != null
                            ? 'Will use target: ${targetGroup.targetName}\nRA: ${targetGroup.raHours.toStringAsFixed(4)}h, Dec: ${targetGroup.decDegrees.toStringAsFixed(4)}\u00B0'
                            : 'No target group found in sequence',
                        style: TextStyle(
                          fontSize: Responsive.fontSize(context, 12),
                          color: targetGroup != null
                              ? colors.success
                              : colors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class MeridianFlipProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final MeridianFlipNode node;

  const MeridianFlipProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meridian Flip Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Trigger Method',
          child: NodeDropdown<MeridianTriggerMethod>(
            colors: colors,
            value: node.triggerMethod,
            items: MeridianTriggerMethod.values,
            labelBuilder: (m) {
              switch (m) {
                case MeridianTriggerMethod.minutesPastMeridian:
                  return 'Minutes Past Meridian';
                case MeridianTriggerMethod.minutesBeforeLimit:
                  return 'Minutes Before Limit';
                case MeridianTriggerMethod.hourAngleThreshold:
                  return 'Hour Angle Threshold';
                case MeridianTriggerMethod.onTrackingLimitHit:
                  return 'On Tracking Limit Hit';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, triggerMethod: value),
                  );
            },
          ),
        ),
        if (node.triggerMethod == MeridianTriggerMethod.minutesPastMeridian)
          NodePropertyField(
            colors: colors,
            label: 'Minutes Past Meridian',
            child: NodeNumberInput(
              colors: colors,
              value: node.minutesPastMeridian,
              suffix: 'min',
              min: 0,
              max: 60,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      applyMeridianFlipEdit(node, minutesPastMeridian: value),
                    );
              },
            ),
          ),
        if (node.triggerMethod == MeridianTriggerMethod.minutesBeforeLimit)
          NodePropertyField(
            colors: colors,
            label: 'Minutes Before Limit',
            child: NodeNumberInput(
              colors: colors,
              value: node.minutesBeforeLimit,
              suffix: 'min',
              min: 1,
              max: 60,
              decimals: 0,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      applyMeridianFlipEdit(node, minutesBeforeLimit: value),
                    );
              },
            ),
          ),
        if (node.triggerMethod == MeridianTriggerMethod.hourAngleThreshold)
          NodePropertyField(
            colors: colors,
            label: 'Hour Angle Threshold',
            child: NodeNumberInput(
              colors: colors,
              value: node.hourAngleThreshold,
              suffix: 'h',
              min: 0.0,
              max: 6.0,
              decimals: 2,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      applyMeridianFlipEdit(node, hourAngleThreshold: value),
                    );
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Flip Sequence',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        NodePropertyField(
          colors: colors,
          label: 'Pause Guiding',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.pauseGuiding,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, pauseGuiding: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Auto Center After Flip',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.autoCenter,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, autoCenter: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Refocus After Flip',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.refocusAfter,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, refocusAfter: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Resume Guiding',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.resumeGuiding,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, resumeGuiding: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Settle Time',
          child: NodeNumberInput(
            colors: colors,
            value: node.settleTime,
            suffix: 's',
            min: 0,
            max: 120,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, settleTime: value),
                  );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Error Handling',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        NodePropertyField(
          colors: colors,
          label: 'Max Retries',
          child: NodeNumberInput(
            colors: colors,
            value: node.maxRetries.toDouble(),
            min: 0,
            max: 10,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, maxRetries: value.toInt()),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Failure Action',
          child: NodeDropdown<FlipFailureAction>(
            colors: colors,
            value: node.failureAction,
            items: FlipFailureAction.values,
            labelBuilder: (a) {
              switch (a) {
                case FlipFailureAction.pauseAndAlert:
                  return 'Pause & Alert';
                case FlipFailureAction.abortAndPark:
                  return 'Abort & Park';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, failureAction: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.tintedBadge(
            colors.info,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Performs pier flip when target crosses meridian. Pauses guiding, flips, then optionally re-centers and refocuses.',
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

class PolarAlignmentProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final PolarAlignmentNode node;

  const PolarAlignmentProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polar Alignment Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Hemisphere',
          child: NodeDropdown<bool>(
            colors: colors,
            value: node.isNorth,
            items: const [true, false],
            labelBuilder: (v) => v ? 'Northern' : 'Southern',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(isNorth: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Exposure Duration',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.exposureDuration,
                  suffix: 's',
                  min: 0.5,
                  max: 30,
                  decimals: 1,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(exposureDuration: value),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Binning',
                child: NodeNumberInput(
                  colors: colors,
                  value: node.binning.toDouble(),
                  min: 1,
                  max: 4,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(binning: value.toInt()),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        NodePropertyField(
          colors: colors,
          label: 'Start Altitude',
          child: NodeNumberInput(
            colors: colors,
            value: node.startAltitude,
            suffix: '\u00B0',
            min: 20,
            max: 80,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startAltitude: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Rotation Step',
          child: NodeNumberInput(
            colors: colors,
            value: node.rotationStep,
            suffix: '\u00B0',
            min: 10,
            max: 45,
            decimals: 0,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(rotationStep: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Gain',
                child: NodeNumberInput(
                  colors: colors,
                  value: (node.gain ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(gain: value.toInt()),
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: NodePropertyField(
                colors: colors,
                label: 'Offset',
                child: NodeNumberInput(
                  colors: colors,
                  value: (node.offset ?? 0).toDouble(),
                  min: 0,
                  max: 1000,
                  onChanged: (value) {
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(offset: value.toInt()),
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        NodePropertyField(
          colors: colors,
          label: 'Start From Current Position',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.startFromCurrent,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startFromCurrent: value),
                  );
            },
          ),
        ),
        NodePropertyField(
          colors: colors,
          label: 'Manual Slew Mode',
          child: NodeToggleSwitch(
            colors: colors,
            value: node.manualSlew,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(manualSlew: value),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.tintedBadge(
            colors.info,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.compass, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Three-point polar alignment using plate solving. Calculates polar error and guides adjustments.',
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
