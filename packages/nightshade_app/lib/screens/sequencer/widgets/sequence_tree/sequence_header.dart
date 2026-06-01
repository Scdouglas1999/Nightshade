part of '../sequence_tree.dart';

class _SequenceHeader extends ConsumerWidget {
  final NightshadeColors colors;
  final Sequence sequence;
  final LiveValidationState validation;

  const _SequenceHeader({
    required this.colors,
    required this.sequence,
    required this.validation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = Responsive.isMobile(context);
    final padding = isMobile
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 20, vertical: 12);
    final iconSize = isMobile ? 14.0 : 16.0;
    final titleFontSize = isMobile ? 13.0 : 14.0;
    final executionState = ref.watch(sequenceExecutionStateProvider);
    final isRunning = executionState == SequenceExecutionState.running ||
        executionState == SequenceExecutionState.paused;
    final followExecution = ref.watch(followExecutionProvider);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Hide secondary info on narrow widths
          final showTargetCount = constraints.maxWidth > 280;
          final showNodeCount = constraints.maxWidth > 380;
          final showValidation = constraints.maxWidth > 320;

          return Row(
            children: [
              Icon(
                LucideIcons.workflow,
                size: iconSize,
                color: colors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    _showRenameDialog(context, ref);
                  },
                  child: Text(
                    sequence.name,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),

              // Validation issue badges
              if (showValidation && validation.totalCount > 0) ...[
                const SizedBox(width: 8),
                _ValidationBadges(
                  colors: colors,
                  errorCount: validation.errorCount,
                  warningCount: validation.warningCount,
                  infoCount: validation.infoCount,
                ),
              ],

              // Follow execution toggle (only shown when running)
              if (isRunning && !isMobile) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: followExecution
                      ? 'Auto-scroll ON (click to disable)'
                      : 'Auto-scroll OFF (click to enable)',
                  child: GestureDetector(
                    onTap: () {
                      ref.read(followExecutionProvider.notifier).state =
                          !followExecution;
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: followExecution
                            ? NightshadeDecorations.statusChip(
                                colors.info,
                                borderRadius: BorderRadius.circular(4),
                                bordered: false,
                              ).color
                            : colors.surfaceAlt,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: followExecution
                              ? colors.info.withValues(alpha: 0.4)
                              : colors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            followExecution
                                ? LucideIcons.locateFixed
                                : LucideIcons.locate,
                            size: 12,
                            color: followExecution
                                ? colors.info
                                : colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Follow',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: followExecution
                                  ? colors.info
                                  : colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              if (showTargetCount) ...[
                const SizedBox(width: 8),
                Text(
                  '${sequence.targetHeaders.length} targets',
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    color: colors.textMuted,
                  ),
                ),
              ],
              if (showNodeCount) ...[
                const SizedBox(width: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.boxes,
                        size: 12,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${sequence.nodes.length} nodes',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Timeline toggle
              if (!isMobile) ...[
                const SizedBox(width: 8),
                _TimelineToggle(colors: colors),
              ],

              // Mini-map toggle
              if (!isMobile) ...[
                const SizedBox(width: 8),
                _MinimapToggle(colors: colors),
              ],

              // Color legend button
              if (!isMobile) ...[
                const SizedBox(width: 8),
                _NodeColorLegend(colors: colors),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: sequence.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Rename Sequence',
          style: TextStyle(color: colors.textPrimary),
        ),
        content: ConstrainedBox(
          constraints: AdaptiveDialogConstraints.hybrid(
            context,
            designMaxWidth: 400,
          ),
          child: TextField(
            controller: controller,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Sequence name',
              hintStyle: TextStyle(color: colors.textMuted),
            ),
          ),
        ),
        actions: [
          NightshadeButton(
            onPressed: () => Navigator.pop(context),
            label: 'Cancel',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
          ),
          NightshadeButton(
            onPressed: () {
              ref
                  .read(currentSequenceProvider.notifier)
                  .setName(controller.text);
              Navigator.pop(context);
            },
            label: 'Rename',
            variant: ButtonVariant.primary,
            size: ButtonSize.small,
          ),
        ],
      ),
    );
  }
}
