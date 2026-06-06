part of '../sequence_toolbar.dart';

/// A single toolbar action. `isDivider == true` represents a visual
/// separator between groups (inline) or the start of a new section in
/// the overflow menu. Keeping both renderings driven by the same data
/// is what audit §4.8 asks for so a hidden button never silently
/// disappears.
class _ToolbarAction {
  final IconData? icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool isDivider;

  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  }) : isDivider = false;

  const _ToolbarAction.divider()
      : icon = null,
        label = null,
        onPressed = null,
        isDivider = true;
}

/// Single overflow popup that subsumes every secondary action below the
/// compact breakpoint. PopupMenuItems are disabled-but-visible when an
/// action's `onPressed` is null, matching inline behaviour (audit §4.8).
class _ToolbarOverflowMenu extends StatelessWidget {
  final NightshadeColors colors;
  final List<_ToolbarAction> actions;

  const _ToolbarOverflowMenu({required this.colors, required this.actions});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      icon: Icon(
        LucideIcons.moreHorizontal,
        size: 18,
        color: colors.textSecondary,
      ),
      onSelected: (index) {
        final action = actions[index];
        action.onPressed?.call();
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<int>>[];
        for (var i = 0; i < actions.length; i++) {
          final a = actions[i];
          if (a.isDivider) {
            if (items.isNotEmpty) {
              items.add(const PopupMenuDivider());
            }
            continue;
          }
          items.add(
            PopupMenuItem<int>(
              value: i,
              enabled: a.onPressed != null,
              child: Row(
                children: [
                  Icon(
                    a.icon,
                    size: 16,
                    color: a.onPressed == null
                        ? colors.textMuted
                        : colors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    a.label!,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize13,
                      color: a.onPressed == null
                          ? colors.textMuted
                          : colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return items;
      },
    );
  }
}

/// Displays both pure integration time and overhead-aware total estimate
class _SequenceTimeEstimate extends StatelessWidget {
  final NightshadeColors colors;
  final Sequence sequence;

  const _SequenceTimeEstimate({
    required this.colors,
    required this.sequence,
  });

  String _formatDuration(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final estimate = sequence.estimateWithOverhead();

    return Tooltip(
      message: estimate.overheadSecs > 0
          ? 'Integration: ${_formatDuration(estimate.estimatedSecs)}\n'
              'Overhead: ${_formatDuration(estimate.overheadSecs)} '
              '(slews, AF, dithers, downloads, etc.)\n'
              'Estimated total: ${_formatDuration(estimate.totalEstimatedSecs)}'
          : 'Integration time: ${_formatDuration(estimate.estimatedSecs)}',
      // `clipBehavior` is the load-bearing guard: even if this box is given
      // less width than its content's natural size (a crowded toolbar row),
      // it clips at its own rounded border instead of painting its text out
      // over the equipment-status icons / run-status badge to its right.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.camera, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${sequence.totalExposures} frames',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                _formatDuration(estimate.estimatedSecs),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (estimate.overheadSecs > 0) ...[
              const SizedBox(width: 8),
              Container(
                width: 1,
                height: 16,
                color: colors.border,
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.timer, size: 14, color: colors.textMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '~${_formatDuration(estimate.totalEstimatedSecs)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize12,
                    color: colors.textMuted,
                    fontStyle: FontStyle.italic,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
