// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

class _ProjectsTab extends ConsumerWidget {
  const _ProjectsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final isRemote = ref.watch(backendProvider) is NetworkBackend;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Entry point into the multi-panel mosaic projects list (the durable
          // capture/integrate/stitch projects created from the Mosaic Wizard).
          // Always present, independent of the target-tracking data below, so
          // the list is reachable even before any single target is tracked.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const ValueKey('mosaic_projects_entry'),
              onPressed: () {
                if (isRemote) {
                  context.showInfoSnackBar(
                    'Open Mosaic Projects on the imaging host.',
                  );
                  return;
                }
                context.push('/mosaic');
              },
              icon:
                  Icon(LucideIcons.layoutGrid, size: 14, color: colors.accent),
              label: Text(
                isRemote
                    ? 'Mosaic projects on imaging host'
                    : 'Mosaic projects',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12,
                  color: colors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(child: ProjectTrackingPanel()),
        ],
      ),
    );
  }
}

/// Session history card widget
class _SessionHistoryCard extends ConsumerWidget {
  final ImagingSession session;

  const _SessionHistoryCard({required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);

    // Both surfaces go through sessionElapsed(), which prints wall-clock time
    // only for the session that is genuinely running: a row with no end_time
    // would otherwise accrue `now - startTime` without bound.
    final sessionState = ref.watch(sessionStateProvider);
    final isLive =
        sessionState.isActive && sessionState.dbSessionId == session.id;
    final elapsed = sessionElapsed(
      session,
      isLive: isLive,
      lastFrameAt: ref.watch(lastFrameBySessionProvider)[session.id],
    );

    final titleRow = Row(
      children: [
        Flexible(
          child: Text(
            session.name ?? context.l10n.text('analyticsUnnamedSession'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NightshadeTypography.h5.copyWith(
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _getStatusColor(session.status, colors),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
          ),
          child: Text(
            session.status.toUpperCase(),
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize9,
              fontWeight: FontWeight.w600,
              color: colors.background,
            ),
          ),
        ),
      ],
    );

    final dateText = Text(
      DateFormat('MMM d, yyyy HH:mm').format(session.startTime),
      style: TextStyle(
          fontSize: NightshadeTypography.fontSize12,
          color: colors.textSecondary),
    );

    // Stats reflow as a Wrap so a narrow phone column never overflows; on wide
    // layouts the chips sit on a single line beside the session info.
    // Every chip carries a caption. Four bare numbers behind icons ("4h 12m",
    // "206", "3.4h", "2.14") left the two durations indistinguishable and gave
    // no clue that the last figure was HFR in pixels.
    final statChips = <Widget>[
      _StatChip(
        icon: LucideIcons.clock,
        caption: elapsed.captionLabel,
        label: elapsed.valueLabel,
        colors: colors,
      ),
      _StatChip(
        icon: LucideIcons.image,
        caption: 'frames',
        label: '${session.successfulExposures}',
        colors: colors,
      ),
      _StatChip(
        icon: LucideIcons.timer,
        caption: 'integration',
        label: _formatIntegrationHours(session.totalIntegrationSecs),
        colors: colors,
      ),
      if (session.avgHfr != null)
        _StatChip(
          icon: LucideIcons.focus,
          caption: 'HFR px',
          label: session.avgHfr!.toStringAsFixed(2),
          colors: colors,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: NightshadeCard(
        child: Semantics(
            button: true,
            enabled: true,
            child: InkWell(
              onTap: () => _showSessionDetail(context, ref, session),
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isPhone =
                        constraints.maxWidth < BreakpointTokens.breakpointPhone;

                    if (isPhone) {
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                titleRow,
                                const SizedBox(height: 4),
                                dateText,
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: statChips,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(LucideIcons.chevronRight,
                              size: 20, color: colors.textMuted),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleRow,
                              const SizedBox(height: 4),
                              dateText,
                            ],
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: statChips,
                        ),
                        const SizedBox(width: 12),
                        Icon(LucideIcons.chevronRight,
                            size: 20, color: colors.textMuted),
                      ],
                    );
                  },
                ),
              ),
            )),
      ),
    );
  }

  Color _getStatusColor(String status, NightshadeColors colors) {
    switch (status.toLowerCase()) {
      case 'completed':
        return colors.success;
      case 'active':
        return colors.info;
      case 'aborted':
        return colors.warning;
      case 'error':
        return colors.error;
      default:
        return colors.textMuted;
    }
  }

  /// Integration in hours, dropping to minutes and seconds below the point
  /// where "0.0h" stops carrying information.
  static String _formatIntegrationHours(double seconds) {
    if (!seconds.isFinite || seconds <= 0) return '0';
    if (seconds >= 3600) return '${(seconds / 3600).toStringAsFixed(1)}h';
    if (seconds >= 60) return '${(seconds / 60).round()}m';
    return '${seconds.round()}s';
  }

  void _showSessionDetail(
      BuildContext context, WidgetRef ref, ImagingSession session) {
    showDialog(
      context: context,
      builder: (context) => _SessionDetailDialog(session: session),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// What the number means. Without it a row of icon+number chips is a puzzle.
  final String? caption;
  final NightshadeColors colors;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: NightshadeTypography.labelSm.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              if (caption != null)
                Text(
                  caption!,
                  style: NightshadeTypography.caption.copyWith(
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Session detail dialog with export functionality
