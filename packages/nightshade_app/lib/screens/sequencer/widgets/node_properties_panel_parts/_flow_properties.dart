// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// Properties widgets for flow-control nodes: target group, loop, delay, wait-time, conditional, parallel, recovery.
part of '../node_properties_panel.dart';

class _TargetGroupProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;

  const _TargetGroupProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Target Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Target Name',
          child: _TextInput(
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
              child: _PropertyField(
                colors: colors,
                label: 'RA (hours)',
                child: _NumberInput(
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
              child: _PropertyField(
                colors: colors,
                label: 'Dec (degrees)',
                child: _NumberInput(
                  colors: colors,
                  value: node.decDegrees,
                  suffix: '°',
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
        _PropertyField(
          colors: colors,
          label: 'Rotation (optional)',
          child: _NumberInput(
            colors: colors,
            value: node.rotation ?? 0,
            suffix: '°',
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
        _PropertyField(
          colors: colors,
          label: 'Min Altitude',
          child: _NumberInput(
            colors: colors,
            value: node.minAltitude ?? 30,
            suffix: '°',
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
      ],
    );
  }
}

class _LoopProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final LoopNode node;

  const _LoopProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Loop Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Condition Type',
          child: _Dropdown<LoopConditionType>(
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
                  return 'Until Altitude';
                case LoopConditionType.altitudeAbove:
                  return 'Altitude Above';
                case LoopConditionType.integrationTime:
                  return 'Integration Time';
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
          _PropertyField(
            colors: colors,
            label: 'Repeat Count',
            child: _NumberInput(
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
          _PropertyField(
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
                    _QuickTimeButton(
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
                    _QuickTimeButton(
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
          _PropertyField(
            colors: colors,
            label: 'Stop Below Altitude',
            child: _NumberInput(
              colors: colors,
              value: node.repeatUntilAltitude ?? 30,
              suffix: '°',
              min: 0,
              max: 90,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(repeatUntilAltitude: value),
                    );
              },
            ),
          ),
      ],
    );
  }
}

class _DelayProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DelayNode node;

  const _DelayProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delay Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Duration',
          child: _NumberInput(
            colors: colors,
            value: node.seconds,
            suffix: 's',
            min: 0.1,
            max: 3600,
            decimals: 1,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(seconds: value),
                  );
            },
          ),
        ),
      ],
    );
  }
}

class _WaitTimeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final WaitTimeNode node;

  const _WaitTimeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wait Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Wait For',
          child: _Dropdown<String>(
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
          _PropertyField(
            colors: colors,
            label: 'Twilight Type',
            child: _Dropdown<TwilightType>(
              colors: colors,
              value: node.waitForTwilight!,
              items: TwilightType.values,
              labelBuilder: (t) {
                switch (t) {
                  case TwilightType.civil:
                    return 'Civil (-6°)';
                  case TwilightType.nautical:
                    return 'Nautical (-12°)';
                  case TwilightType.astronomical:
                    return 'Astronomical (-18°)';
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
          _PropertyField(
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

class _ConditionalProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ConditionalNode node;

  const _ConditionalProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Condition Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Condition Type',
          child: _Dropdown<ConditionalType>(
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
          _PropertyField(
            colors: colors,
            label: 'Threshold (degrees)',
            child: _NumberInput(
              colors: colors,
              value: node.thresholdValue ?? 30,
              suffix: '°',
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
          _PropertyField(
            colors: colors,
            label: 'Max RMS (arcsec)',
            child: _NumberInput(
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
          _PropertyField(
            colors: colors,
            label: 'Max HFR (pixels)',
            child: _NumberInput(
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
      ],
    );
  }
}

class _ParallelProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ParallelNode node;

  const _ParallelProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Parallel Execution',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Required Successes',
          child: _NumberInput(
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

class _RecoveryProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final RecoveryNode node;

  const _RecoveryProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery Settings',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Trigger Type',
          child: _Dropdown<TriggerType?>(
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
                case TriggerType.humidityThreshold:
                  return 'Humidity Threshold';
                case TriggerType.focusDrift:
                  return 'Focus Drift';
                case TriggerType.mountTrackingLost:
                  return 'Mount Tracking Lost';
                case TriggerType.domeShutterNotOpen:
                  return 'Dome Shutter Not Open';
                case TriggerType.guideStarLost:
                  return 'Guide Star Lost';
                case TriggerType.autofocusInterval:
                  return 'Autofocus Interval';
                case TriggerType.ditherInterval:
                  return 'Dither Interval';
                case TriggerType.driftLimit:
                  return 'Drift Limit';
                case TriggerType.cloudArrivingIn:
                  return 'Cloud Arriving In';
                case TriggerType.cloudOpeningIn:
                  return 'Cloud Opening In';
                case TriggerType.cloudCoverThreshold:
                  return 'Cloud Cover Threshold';
                case TriggerType.transparencyDropped:
                  return 'Transparency Dropped';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(triggerType: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Recovery Action',
          child: _Dropdown<RecoveryActionType>(
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
                case RecoveryActionType.pauseAndWaitForClear:
                  return 'Pause and Wait for Clear';
                case RecoveryActionType.slewToGapAndContinue:
                  return 'Slew to Gap and Continue';
                case RecoveryActionType.switchTargetOrFilter:
                  return 'Switch Target or Filter';
              }
            },
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(recoveryAction: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Max Retries',
          child: _NumberInput(
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
        if (node.triggerType == TriggerType.hfrDegraded)
          _PropertyField(
            colors: colors,
            label: 'HFR Threshold',
            child: _NumberInput(
              colors: colors,
              value: node.triggerThreshold ?? 4.0,
              suffix: 'px',
              min: 1,
              max: 20,
              decimals: 1,
              onChanged: (value) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      node.copyWith(triggerThreshold: value),
                    );
              },
            ),
          ),
        if (node.triggerType == TriggerType.altitudeLimit)
          _PropertyField(
            colors: colors,
            label: 'Min Altitude',
            child: _NumberInput(
              colors: colors,
              value: node.triggerThreshold ?? 30,
              suffix: '°',
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
