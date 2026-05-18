import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'node_property_widgets.dart';

class TargetGroupProperties extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetHeaderNode node;

  const TargetGroupProperties({super.key, required this.colors, required this.node});

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
                initialTime: TimeOfDay.fromDateTime(
                    node.startAfter ?? DateTime.now()),
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
                  Icon(LucideIcons.clock,
                      size: 14, color: colors.textMuted),
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
                initialTime: TimeOfDay.fromDateTime(
                    node.endBefore ?? DateTime.now()),
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
                  Icon(LucideIcons.clock,
                      size: 14, color: colors.textMuted),
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
        ],
      ),
    );
  }
}
