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
                  Flexible(
                    child: Text(
                      a.label!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        color: a.onPressed == null
                            ? colors.textMuted
                            : colors.textPrimary,
                      ),
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
class _SequenceTimeEstimate extends ConsumerWidget {
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

  /// Natural width of [text] in [style], used to decide which segments of the
  /// pill actually fit before any of them is laid out.
  double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Total from the SAME estimator the tree-row chips, the timeline and the
    // Pre-Flight simulation use. `Sequence.estimateWithOverhead` is a third,
    // coarser model (flat per-node constants, no clock-dependent nodes), and
    // billing this chip against it is what made the Builder header and the
    // Pre-Flight panel print different totals for one sequence.
    final estimator = SequenceTimeEstimator(
      overhead: ref.watch(sequencerOverheadConfigProvider),
    );
    final integrationSecs = sequence.estimateIntegrationSecs().estimatedSecs;
    final totalSecs = estimator
        .estimateTotalDuration(sequence, DateTime.now())
        .inSeconds
        .toDouble();
    final overheadSecs = totalSecs - integrationSecs;

    final valueStyle = TextStyle(
      fontSize: NightshadeTypography.fontSize12,
      color: colors.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final overheadStyle = TextStyle(
      fontSize: NightshadeTypography.fontSize12,
      color: colors.textMuted,
      fontStyle: FontStyle.italic,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final framesText = '${sequence.totalExposures} frames';
    final timeText = _formatDuration(integrationSecs);
    final overheadText = '~${_formatDuration(totalSecs)}';

    return Tooltip(
      message: overheadSecs > 0
          ? 'Integration: ${_formatDuration(integrationSecs)}\n'
              'Overhead: ${_formatDuration(overheadSecs)} '
              '(slews, AF, dithers, downloads, etc.)\n'
              'Estimated total: ${_formatDuration(totalSecs)}'
          : 'Integration time: ${_formatDuration(integrationSecs)}',
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Icons and their gaps cannot shrink, so a `Flexible` text alone
          // does NOT stop this row overflowing: below ~66 px the icons alone
          // exceed the box. Measure each segment up front and drop the ones
          // that do not fit, rather than painting a half-clipped icon with
          // no number next to it (which is what a crowded 1440-wide toolbar
          // used to show).
          const padding = 12.0 * 2 + 2; // horizontal padding + 1 px borders
          final framesSegment =
              14 + 6 + _measure(context, framesText, valueStyle);
          final timeSegment =
              12 + 14 + 6 + _measure(context, timeText, valueStyle);
          final overheadSegment = 8 +
              1 +
              8 +
              14 +
              4 +
              _measure(context, overheadText, overheadStyle);

          final available = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : double.infinity;

          final showFrames = available >= padding + framesSegment;
          final showTime = available >= padding + framesSegment + timeSegment;
          final showOverhead = overheadSecs > 0 &&
              available >=
                  padding + framesSegment + timeSegment + overheadSegment;

          // Nothing meaningful fits: render nothing at all instead of a
          // clipped icon that tells the user neither a count nor a duration.
          if (!showFrames) return const SizedBox.shrink();

          return Container(
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
                Text(
                  framesText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: valueStyle,
                ),
                if (showTime) ...[
                  const SizedBox(width: 12),
                  Icon(LucideIcons.clock, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    timeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: valueStyle,
                  ),
                ],
                if (showOverhead) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 1,
                    height: 16,
                    color: colors.border,
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.timer, size: 14, color: colors.textMuted),
                  const SizedBox(width: 4),
                  Text(
                    overheadText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: overheadStyle,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
