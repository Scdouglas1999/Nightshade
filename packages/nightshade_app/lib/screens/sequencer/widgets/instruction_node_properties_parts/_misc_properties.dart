// Part of ../instruction_node_properties.dart -- extracted for maintainability.
//
// Properties widgets that don't fit the capture/motion/notification buckets: DelayProperties, SimpleInstructionInfo, DomeProperties, InstructionSetInfo, and the four cover/calibrator widgets (OpenCover, CloseCover, CalibratorOn, CalibratorOff).
part of '../instruction_node_properties.dart';

class DelayProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final DelayNode node;

  const DelayProperties({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delay Settings',
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Duration',
          child: NodeNumberInput(
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

class SimpleInstructionInfo extends StatelessWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const SimpleInstructionInfo(
      {super.key, required this.colors, required this.node});

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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.primary),
          const SizedBox(height: 12),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class DomeProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final SequenceNode node;

  const DomeProperties({super.key, required this.colors, required this.node});

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
          style: TextStyle(
            fontSize: Responsive.fontSize(context, 13),
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Shutter Only',
          child: NodeToggleSwitch(
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
            fontSize: Responsive.fontSize(context, 12),
            color: colors.textMuted,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.primary),
              const SizedBox(height: 12),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Responsive.fontSize(context, 13),
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

class InstructionSetInfo extends StatelessWidget {
  final NightshadeColors colors;
  final InstructionSetNode node;

  const InstructionSetInfo(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.listTree, size: 32, color: colors.accent),
          const SizedBox(height: 12),
          Text(
            'Container for sequential instructions. All children execute in order from top to bottom.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Responsive.fontSize(context, 13),
              color: colors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Builder(
              builder: (context) => Text(
                    '${node.childIds.length} children',
                    style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: colors.textMuted,
                    ),
                  )),
        ],
      ),
    );
  }
}

class OpenCoverProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final OpenCoverNode node;

  const OpenCoverProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 300,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.iconChip(
            colors.info,
            borderRadius: BorderRadius.circular(8),
            borderAlpha: 0.2,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Opens the motorized dust cover or flat panel lid. Requires a cover calibrator device.',
                  style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CloseCoverProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CloseCoverNode node;

  const CloseCoverProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 300,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.iconChip(
            colors.info,
            borderRadius: BorderRadius.circular(8),
            borderAlpha: 0.2,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Closes the motorized dust cover or flat panel lid. Requires a cover calibrator device.',
                  style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalibratorOnProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CalibratorOnNode node;

  const CalibratorOnProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Brightness',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: node.brightness.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (value) {
                        ref.read(currentSequenceProvider.notifier).updateNode(
                              node.copyWith(brightness: value.round()),
                            );
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${node.brightness}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: Responsive.fontSize(context, 13),
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              Text(
                '0 = off, 255 = maximum brightness',
                style: TextStyle(
                    fontSize: Responsive.fontSize(context, 11),
                    color: colors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 120,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.iconChip(
            colors.info,
            borderRadius: BorderRadius.circular(8),
            borderAlpha: 0.2,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Turns on the flat panel light at the specified brightness. Use with flat frame sequences.',
                  style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalibratorOffProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final CalibratorOffNode node;

  const CalibratorOffProperties(
      {super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NodePropertyField(
          colors: colors,
          label: 'Timeout (seconds)',
          child: NodeNumberInput(
            colors: colors,
            value: node.timeoutSecs.toDouble(),
            min: 5,
            max: 120,
            onChanged: (value) {
              ref.read(currentSequenceProvider.notifier).updateNode(
                    node.copyWith(timeoutSecs: value.round()),
                  );
            },
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: NightshadeDecorations.iconChip(
            colors.info,
            borderRadius: BorderRadius.circular(8),
            borderAlpha: 0.2,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: colors.info),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Turns off the flat panel light. Use after flat frame capture is complete.',
                  style: TextStyle(
                      fontSize: Responsive.fontSize(context, 12),
                      color: colors.info),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
