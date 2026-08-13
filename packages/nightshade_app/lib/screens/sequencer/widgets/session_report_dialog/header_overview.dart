part of '../session_report_dialog.dart';

class _Header extends StatelessWidget {
  final SessionReport report;
  final NightshadeColors colors;
  final DateFormat dateFormat;
  final VoidCallback onCopyMarkdown;
  final VoidCallback onExportTxt;

  const _Header({
    required this.report,
    required this.colors,
    required this.dateFormat,
    required this.onCopyMarkdown,
    required this.onExportTxt,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${report.sessionName} - ${runStatusLabel(report.status)}',
                style: NightshadeTypography.labelStrong
                    .copyWith(color: colors.textPrimary),
              ),
              if (report.endTime != null)
                Text(
                  '${dateFormat.format(report.startTime)} - ${dateFormat.format(report.endTime!)}',
                  style: NightshadeTypography.captionSm
                      .copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onCopyMarkdown,
          icon: const Icon(LucideIcons.clipboardCopy,
              size: NightshadeTokens.iconSm),
          tooltip: 'Copy as Markdown',
        ),
        IconButton(
          onPressed: onExportTxt,
          icon: const Icon(LucideIcons.fileText, size: NightshadeTokens.iconSm),
          tooltip: 'Export to .txt',
        ),
      ],
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  final SessionReport report;
  final NightshadeColors colors;

  const _OverviewGrid({required this.report, required this.colors});

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final efficiencyPct =
        (report.effectiveImagingFraction * 100).toStringAsFixed(1);
    return Wrap(
      spacing: NightshadeTokens.spaceLg,
      runSpacing: NightshadeTokens.spaceSm,
      children: [
        _OverviewTile(
          label: 'Wall clock',
          value: _formatDuration(report.wallClockDuration),
          colors: colors,
        ),
        _OverviewTile(
          label: 'Integration',
          value: _formatDuration(report.totalIntegration),
          colors: colors,
        ),
        _OverviewTile(
          label: 'Effective imaging',
          value: '$efficiencyPct%',
          colors: colors,
        ),
        _OverviewTile(
          label: 'Downtime',
          value: _formatDuration(report.downtime),
          colors: colors,
        ),
        _OverviewTile(
          label: 'Frames accepted',
          value: '${report.totalFramesAccepted}/${report.totalFramesAttempted}',
          colors: colors,
        ),
        _OverviewTile(
          label: 'Frames rejected',
          value: report.totalFramesRejected.toString(),
          colors: colors,
          valueColor: report.totalFramesRejected > 0 ? colors.warning : null,
        ),
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? valueColor;

  const _OverviewTile({
    required this.label,
    required this.value,
    required this.colors,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      child: NightshadeCard(
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceMd,
          vertical: NightshadeTokens.spaceSm + 2,
        ),
        borderRadius: NightshadeTokens.radiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: NightshadeTokens.spaceXs),
            Text(
              value,
              style: NightshadeTypography.h4.copyWith(
                color: valueColor ?? colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final NightshadeColors colors;
  final Color? titleColor;

  const _SectionTitle({
    required this.title,
    required this.icon,
    required this.colors,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceSm),
      child: Row(
        children: [
          Icon(icon,
              size: NightshadeTokens.iconXs,
              color: titleColor ?? colors.primary),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Text(
            title,
            style: NightshadeTypography.labelStrong
                .copyWith(color: titleColor ?? colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
