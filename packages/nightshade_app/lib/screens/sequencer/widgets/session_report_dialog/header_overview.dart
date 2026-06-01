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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.fileBarChart, size: 22, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Session Report',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  '${report.sessionName} - ${report.status}',
                  style: TextStyle(fontSize: 13, color: colors.textMuted),
                ),
                if (report.endTime != null)
                  Text(
                    '${dateFormat.format(report.startTime)} - ${dateFormat.format(report.endTime!)}',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCopyMarkdown,
            icon: const Icon(LucideIcons.clipboardCopy, size: 18),
            tooltip: 'Copy as Markdown',
          ),
          IconButton(
            onPressed: onExportTxt,
            icon: const Icon(LucideIcons.fileText, size: 18),
            tooltip: 'Export to .txt',
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(LucideIcons.x, color: colors.textMuted),
            tooltip: 'Close',
          ),
        ],
      ),
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
      spacing: 16,
      runSpacing: 8,
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
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ],
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: titleColor ?? colors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: titleColor ?? colors.textPrimary,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
