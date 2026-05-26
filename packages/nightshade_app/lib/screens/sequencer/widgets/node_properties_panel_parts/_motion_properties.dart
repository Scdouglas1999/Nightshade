// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// Properties widgets for mount/optics motion: center, autofocus, rotator, slew, meridian flip, polar alignment.
part of '../node_properties_panel.dart';

class _CenterProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CenterNode node;

  const _CenterProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Centering Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Accuracy',
          child: _NumberInput(
            colors: colors,
            value: node.accuracyArcsec,
            suffix: '"',
            min: 0.1,
            max: 60,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(accuracyArcsec: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Max Attempts',
          child: _NumberInput(
            colors: colors,
            value: node.maxAttempts.toDouble(),
            min: 1,
            max: 20,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(maxAttempts: value.toInt()),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _AutofocusProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final AutofocusNode node;

  const _AutofocusProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Autofocus Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Method',
          child: _Dropdown<AutofocusMethod>(
            colors: colors,
            value: node.method,
            items: AutofocusMethod.values,
            labelBuilder: (m) {
              switch (m) {
                case AutofocusMethod.vCurve:
                  return 'V-Curve';
                case AutofocusMethod.hyperbolic:
                  return 'Hyperbolic';
                case AutofocusMethod.quadratic:
                  return 'Quadratic';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(method: value),
                  );
            },
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Step Size',
                child: _NumberInput(
                  colors: colors,
                  value: node.stepSize.toDouble(),
                  min: 1,
                  max: 1000,
                  onChanged: (value) {
                    final stepSize = value.toInt();
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(stepSize: stepSize),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateAutofocusDefaults(
                          stepSize: stepSize,
                        );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PropertyField(
                colors: colors,
                label: 'Steps Out',
                child: _NumberInput(
                  colors: colors,
                  value: node.stepsOut.toDouble(),
                  min: 3,
                  max: 15,
                  onChanged: (value) {
                    final stepsOut = value.toInt();
                    ref.read(currentSequenceProvider.notifier).updateNode(
                          node.copyWith(stepsOut: stepsOut),
                        );
                    // Save as default for future nodes
                    ref
                        .read(sequencerDefaultsProvider.notifier)
                        .updateAutofocusDefaults(
                          stepsOut: stepsOut,
                        );
                  },
                ),
              ),
            ),
          ],
        ),
        _PropertyField(
          colors: colors,
          label: 'Exposure Duration',
          child: _NumberInput(
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
              // Save as default for future nodes
              ref
                  .read(sequencerDefaultsProvider.notifier)
                  .updateAutofocusDefaults(
                    exposureDuration: value,
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _RotatorProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RotatorNode node;

  const _RotatorProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotator Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Target Angle',
          child: _NumberInput(
            colors: colors,
            value: node.targetAngle,
            suffix: '°',
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
        _PropertyField(
          colors: colors,
          label: 'Relative Movement',
          child: _ToggleSwitch(
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
            fontSize: 11,
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _SlewProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SlewNode node;

  const _SlewProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Slew Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Use Target Coordinates',
          child: _ToggleSwitch(
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
                child: _PropertyField(
                  colors: colors,
                  label: 'RA (hours)',
                  child: _NumberInput(
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
                child: _PropertyField(
                  colors: colors,
                  label: 'Dec (degrees)',
                  child: _NumberInput(
                    colors: colors,
                    value: node.customDec ?? 0,
                    suffix: '°',
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
                decoration: BoxDecoration(
                  color: targetGroup != null
                      ? colors.success.withValues(alpha: 0.1)
                      : colors.warning.withValues(alpha: 0.1),
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
                            ? 'Will use target: ${targetGroup.targetName}\nRA: ${targetGroup.raHours.toStringAsFixed(4)}h, Dec: ${targetGroup.decDegrees.toStringAsFixed(4)}°'
                            : 'No target group found in sequence',
                        style: TextStyle(
                          fontSize: 11,
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

class _MeridianFlipProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final MeridianFlipNode node;

  const _MeridianFlipProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meridian Flip Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Minutes Past Meridian',
          child: _NumberInput(
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
        _PropertyField(
          colors: colors,
          label: 'Pause Guiding',
          child: _ToggleSwitch(
            colors: colors,
            value: node.pauseGuiding,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, pauseGuiding: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Auto Center After Flip',
          child: _ToggleSwitch(
            colors: colors,
            value: node.autoCenter,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    applyMeridianFlipEdit(node, autoCenter: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Settle Time',
          child: _NumberInput(
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
                  'Performs pier flip when target crosses meridian. Pauses guiding, flips, then optionally re-centers.',
                  style: TextStyle(
                    fontSize: 11,
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

class _PolarAlignmentProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final PolarAlignmentNode node;

  const _PolarAlignmentProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Polar Alignment Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Hemisphere',
          child: _Dropdown<bool>(
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
              child: _PropertyField(
                colors: colors,
                label: 'Exposure Duration',
                child: _NumberInput(
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
              child: _PropertyField(
                colors: colors,
                label: 'Binning',
                child: _NumberInput(
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
        _PropertyField(
          colors: colors,
          label: 'Start Altitude',
          child: _NumberInput(
            colors: colors,
            value: node.startAltitude,
            suffix: '°',
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
        _PropertyField(
          colors: colors,
          label: 'Rotation Step',
          child: _NumberInput(
            colors: colors,
            value: node.rotationStep,
            suffix: '°',
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
              child: _PropertyField(
                colors: colors,
                label: 'Gain',
                child: _NumberInput(
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
              child: _PropertyField(
                colors: colors,
                label: 'Offset',
                child: _NumberInput(
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
        _PropertyField(
          colors: colors,
          label: 'Start From Current Position',
          child: _ToggleSwitch(
            colors: colors,
            value: node.startFromCurrent,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(startFromCurrent: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Manual Slew Mode',
          child: _ToggleSwitch(
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
          decoration: BoxDecoration(
            color: colors.info.withValues(alpha: 0.1),
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
                    fontSize: 11,
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
