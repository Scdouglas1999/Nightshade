// ignore_for_file: unused_element_parameter

part of '../analytics_screen.dart';

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: ProjectTrackingPanel(),
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

    final duration = session.endTime != null
        ? session.endTime!.difference(session.startTime)
        : DateTime.now().difference(session.startTime);

    final titleRow = Row(
      children: [
        Flexible(
          child: Text(
            session.name ?? context.l10n.text('analyticsUnnamedSession'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              fontWeight: FontWeight.w600,
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
      style: TextStyle(fontSize: NightshadeTypography.fontSize12, color: colors.textSecondary),
    );

    // Stats reflow as a Wrap so a narrow phone column never overflows; on wide
    // layouts the chips sit on a single line beside the session info.
    final statChips = <Widget>[
      _StatChip(
        icon: LucideIcons.clock,
        label: _formatDuration(duration),
        colors: colors,
      ),
      _StatChip(
        icon: LucideIcons.image,
        label: '${session.successfulExposures}',
        colors: colors,
      ),
      _StatChip(
        icon: LucideIcons.timer,
        label: '${(session.totalIntegrationSecs / 3600).toStringAsFixed(1)}h',
        colors: colors,
      ),
      if (session.avgHfr != null)
        _StatChip(
          icon: LucideIcons.focus,
          label: session.avgHfr!.toStringAsFixed(2),
          colors: colors,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: NightshadeCard(
        child: InkWell(
          onTap: () => _showSessionDetail(context, ref, session),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
        ),
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

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
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
  final NightshadeColors colors;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
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
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              fontWeight: FontWeight.w500,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Session detail dialog with export functionality
