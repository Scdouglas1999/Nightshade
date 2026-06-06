// Part of ../node_properties_panel.dart -- extracted for maintainability.
//
// Properties widgets for nodes that don't fit the capture/motion/flow buckets: notification, script, simple-instruction info card, dome, unknown-node fallback, the four cover/calibrator nodes plus their shared scaffold & timeout field, and the instruction-set info widget.
part of '../node_properties_panel.dart';

class _ScriptProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final ScriptNode node;

  const _ScriptProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Script Settings',
          style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Script Path',
          child: _TextInput(
            colors: colors,
            value: node.scriptPath,
            hint: 'Path to script file',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(scriptPath: value),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Arguments',
          child: _TextInput(
            colors: colors,
            value: node.arguments.join(' '),
            hint: 'Space-separated arguments',
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(
                        arguments: value
                            .split(' ')
                            .where((s) => s.isNotEmpty)
                            .toList()),
                  );
            },
          ),
        ),
        _PropertyField(
          colors: colors,
          label: 'Timeout',
          child: _NumberInput(
            colors: colors,
            value: (node.timeoutSecs ?? 300).toDouble(),
            suffix: 's',
            min: 1,
            max: 3600,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.toInt()),
                  );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.alertTriangle, size: 14, color: colors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scripts run with sequence context variables available as environment variables',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.warning,
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

class _SimpleInstructionInfo extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _SimpleInstructionInfo({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final String description;
    final IconData icon;

    if (node is ParkNode) {
      description =
          'Parks the mount at its home position. The mount will not track after parking.';
      icon = LucideIcons.parkingCircle;
    } else if (node is UnparkNode) {
      description =
          'Unparks the mount and enables tracking. Required before slewing or imaging.';
      icon = LucideIcons.unlock;
    } else {
      description = 'This instruction has no additional settings.';
      icon = LucideIcons.settings;
    }

    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      borderRadius: NightshadeTokens.radiusLg,
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DomeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _DomeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String title;
    final String description;
    final IconData icon;
    final bool shutterOnly;

    if (node is OpenDomeNode) {
      title = 'Open Dome Settings';
      description =
          'Opens the dome shutter to allow imaging. If not using shutter-only mode, will also rotate dome to tracking position.';
      icon = LucideIcons.doorOpen;
      shutterOnly = (node as OpenDomeNode).shutterOnly;
    } else if (node is CloseDomeNode) {
      title = 'Close Dome Settings';
      description =
          'Closes the dome shutter to protect equipment. Typically used at end of session or when weather becomes unsafe.';
      icon = LucideIcons.doorClosed;
      shutterOnly = (node as CloseDomeNode).shutterOnly;
    } else {
      title = 'Park Dome Settings';
      description =
          'Parks the dome at its home position. The dome will stop tracking the telescope.';
      icon = LucideIcons.parkingCircle;
      shutterOnly = (node as ParkDomeNode).shutterOnly;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        _PropertyField(
          colors: colors,
          label: 'Shutter Only',
          child: _ToggleSwitch(
            colors: colors,
            value: shutterOnly,
            onChanged: (value) {
              if (node is OpenDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as OpenDomeNode).copyWith(shutterOnly: value),
                    );
              } else if (node is CloseDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as CloseDomeNode).copyWith(shutterOnly: value),
                    );
              } else if (node is ParkDomeNode) {
                ref.read(currentSequenceProvider.notifier).updateNode(
                      (node as ParkDomeNode).copyWith(shutterOnly: value),
                    );
              }
            },
          ),
        ),
        Text(
          shutterOnly
              ? 'Only operates the shutter, dome will not rotate'
              : 'Will operate both shutter and dome rotation',
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize11,
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 16),
        NightshadeCard(
          padding: const EdgeInsets.all(16),
          borderRadius: NightshadeTokens.radiusLg,
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UnknownNodeProperties extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const _UnknownNodeProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final typeName = node.runtimeType.toString();
    // Log so any unexpected dispatch falls into the debug stream rather than
    // hiding behind a vague UI message.
    assert(() {
      // ignore: avoid_print
      print('[NodePropertiesPanel] No property panel registered for $typeName');
      return true;
    }());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.08),
        border: Border.all(color: colors.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.alertTriangle, size: 16, color: colors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No property editor for $typeName',
                  style:
                      NightshadeTypography.h6.copyWith(color: colors.warning),
                ),
                const SizedBox(height: 4),
                Text(
                  'This node will still run with its current values, but you cannot edit them here. '
                  'Save and re-load to keep its state; report this if you expected an editor.',
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenCoverProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final OpenCoverNode node;

  const _OpenCoverProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CoverCalibratorScaffold(
      colors: colors,
      title: 'Open Cover Settings',
      icon: LucideIcons.doorOpen,
      description:
          'Opens the motorized dust cover or flat panel lid. Requires a cover calibrator device.',
      children: [
        _CoverCalibratorTimeoutField(
          colors: colors,
          timeoutSecs: node.timeoutSecs,
          min: 5,
          max: 300,
          onChanged: (value) {
            ref
                .read(currentSequenceProvider.notifier)
                .updateNode(node.copyWith(timeoutSecs: value));
          },
        ),
      ],
    );
  }
}

class _CloseCoverProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CloseCoverNode node;

  const _CloseCoverProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CoverCalibratorScaffold(
      colors: colors,
      title: 'Close Cover Settings',
      icon: LucideIcons.doorClosed,
      description:
          'Closes the motorized dust cover or flat panel lid. Use to protect optics or transition out of flats.',
      children: [
        _CoverCalibratorTimeoutField(
          colors: colors,
          timeoutSecs: node.timeoutSecs,
          min: 5,
          max: 300,
          onChanged: (value) {
            ref
                .read(currentSequenceProvider.notifier)
                .updateNode(node.copyWith(timeoutSecs: value));
          },
        ),
      ],
    );
  }
}

class _CalibratorOnProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CalibratorOnNode node;

  const _CalibratorOnProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CoverCalibratorScaffold(
      colors: colors,
      title: 'Calibrator On Settings',
      icon: LucideIcons.lightbulb,
      description:
          'Turns on the flat panel light at the specified brightness. Use with flat frame sequences.',
      children: [
        _PropertyField(
          colors: colors,
          label: 'Brightness',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: node.brightness.toDouble().clamp(0.0, 255.0),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (value) {
                        ref.read(currentSequenceProvider.notifier).updateNode(
                            node.copyWith(brightness: value.round()));
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${node.brightness}',
                      textAlign: TextAlign.right,
                      style: NightshadeTypography.labelStrong
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
              Text(
                '0 = off, 255 = maximum brightness',
                style: TextStyle(
                    fontSize: NightshadeTypography.fontSize11,
                    color: colors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CoverCalibratorTimeoutField(
          colors: colors,
          timeoutSecs: node.timeoutSecs,
          min: 5,
          max: 120,
          onChanged: (value) {
            ref
                .read(currentSequenceProvider.notifier)
                .updateNode(node.copyWith(timeoutSecs: value));
          },
        ),
      ],
    );
  }
}

class _CalibratorOffProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CalibratorOffNode node;

  const _CalibratorOffProperties({required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _CoverCalibratorScaffold(
      colors: colors,
      title: 'Calibrator Off Settings',
      icon: LucideIcons.lightbulbOff,
      description:
          'Turns off the flat panel light. Use after flat frame capture is complete.',
      children: [
        _CoverCalibratorTimeoutField(
          colors: colors,
          timeoutSecs: node.timeoutSecs,
          min: 5,
          max: 120,
          onChanged: (value) {
            ref
                .read(currentSequenceProvider.notifier)
                .updateNode(node.copyWith(timeoutSecs: value));
          },
        ),
      ],
    );
  }
}

class _CoverCalibratorScaffold extends StatelessWidget {
  final NightshadeColors colors;
  final String title;
  final IconData icon;
  final String description;
  final List<Widget> children;

  const _CoverCalibratorScaffold({
    required this.colors,
    required this.title,
    required this.icon,
    required this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 16),
        NightshadeCard(
          padding: const EdgeInsets.all(16),
          borderRadius: NightshadeTokens.radiusLg,
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CoverCalibratorTimeoutField extends StatelessWidget {
  final NightshadeColors colors;
  final int timeoutSecs;
  final double min;
  final double max;
  final ValueChanged<int> onChanged;

  const _CoverCalibratorTimeoutField({
    required this.colors,
    required this.timeoutSecs,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _PropertyField(
      colors: colors,
      label: 'Timeout (seconds)',
      child: _NumberInput(
        colors: colors,
        value: timeoutSecs.toDouble(),
        min: min,
        max: max,
        suffix: 's',
        onChanged: (value) => onChanged(value.round()),
      ),
    );
  }
}

class _InstructionSetInfo extends StatelessWidget {
  final NightshadeColors colors;
  final InstructionSetNode node;

  const _InstructionSetInfo({required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.all(16),
      borderRadius: NightshadeTokens.radiusLg,
      child: Column(
        children: [
          Icon(LucideIcons.listTree, size: 32, color: colors.accent),
          const SizedBox(height: 12),
          Text(
            'Container for sequential instructions. All children execute in order from top to bottom.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${node.childIds.length} children',
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize11,
              color: colors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
