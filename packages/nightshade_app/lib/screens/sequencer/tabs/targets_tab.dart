import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:intl/intl.dart';

import '../../../utils/snackbar_helper.dart';
import '../widgets/delete_node_confirmation.dart';

part 'targets_tab_parts/timeline.dart';
part 'targets_tab_parts/target_list.dart';
part 'targets_tab_parts/dialogs.dart';

class TargetsTab extends ConsumerWidget {
  const TargetsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final sequence = ref.watch(currentSequenceProvider);
    final isMobile = Responsive.isMobile(context);
    // Trust-patch §B: Add Target opens a dialog that ultimately calls
    // addTargetHeader / addNode, and Optimize Order calls reorderTargets.
    // Both must be disabled while the sequence is running.
    final canEdit = ref.watch(canEditSequenceProvider);
    final lockedTooltip =
        canEdit ? null : 'Cannot edit while sequence is running';

    Widget wrapWithTooltip(Widget child) {
      if (lockedTooltip == null) return child;
      return Tooltip(message: lockedTooltip, child: child);
    }

    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          if (isMobile) ...[
            // Mobile: stack title and buttons vertically
            Text(
              'Session Planner',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (sequence != null && sequence.targetHeaders.length > 1)
                  Expanded(
                    child: wrapWithTooltip(NightshadeButton(
                      label: 'Optimize',
                      icon: LucideIcons.sparkles,
                      variant: ButtonVariant.outline,
                      size: ButtonSize.small,
                      onPressed: canEdit
                          ? () {
                              showDialog(
                                context: context,
                                builder: (context) => _OptimizeOrderDialog(
                                  targets: sequence.targetHeaders,
                                ),
                              );
                            }
                          : null,
                    )),
                  ),
                if (sequence != null && sequence.targetHeaders.length > 1)
                  const SizedBox(width: 8),
                Expanded(
                  child: wrapWithTooltip(NightshadeButton(
                    label: 'Add Target',
                    icon: LucideIcons.plus,
                    size: ButtonSize.small,
                    onPressed: canEdit
                        ? () {
                            showDialog(
                              context: context,
                              builder: (context) => const _AddTargetDialog(),
                            );
                          }
                        : null,
                  )),
                ),
              ],
            ),
          ] else ...[
            // Desktop: row layout
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Session Planner',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Visualize and optimize your imaging session',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (sequence != null && sequence.targetHeaders.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: wrapWithTooltip(NightshadeButton(
                      label: 'Optimize Order',
                      icon: LucideIcons.sparkles,
                      variant: ButtonVariant.outline,
                      onPressed: canEdit
                          ? () {
                              showDialog(
                                context: context,
                                builder: (context) => _OptimizeOrderDialog(
                                  targets: sequence.targetHeaders,
                                ),
                              );
                            }
                          : null,
                    )),
                  ),
                wrapWithTooltip(NightshadeButton(
                  label: 'Add Target',
                  icon: LucideIcons.plus,
                  onPressed: canEdit
                      ? () {
                          showDialog(
                            context: context,
                            builder: (context) => const _AddTargetDialog(),
                          );
                        }
                      : null,
                )),
              ],
            ),
          ],

          SizedBox(height: isMobile ? 16 : 24),

          // Timeline Chart
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const _NightTimeline(),
              ),
            ),
          ),

          SizedBox(height: isMobile ? 12 : 24),

          Text(
            'Scheduled Targets',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Active Target List
          Expanded(
            flex: 3,
            child: sequence == null || sequence.targetHeaders.isEmpty
                ? const EmptyState.compact(
                    icon: LucideIcons.calendarClock,
                    title: 'No targets scheduled',
                    body: 'Add a target to see the plan',
                  )
                : _ActiveTargetList(colors: colors, sequence: sequence),
          ),
        ],
      ),
    );
  }
}
