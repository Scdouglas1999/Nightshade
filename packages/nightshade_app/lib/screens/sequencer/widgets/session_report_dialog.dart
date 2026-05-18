import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Rich end-of-session report dialog (Feature A).
///
/// Opens automatically after a sequence run completes (or aborts / errors)
/// and is also reachable from the analytics history tab "View Report"
/// button. Renders the per-target / per-filter rollup, guiding summary,
/// mount events and recorded errors and exposes Markdown / .txt exports.
class SessionReportDialog extends ConsumerWidget {
  /// The session whose report should be rendered.
  final int sessionId;

  const SessionReportDialog({super.key, required this.sessionId});

  /// Convenience launcher — mirrors how the other sequencer dialogs in this
  /// folder are opened.
  static Future<void> show(BuildContext context, int sessionId) {
    return showDialog<void>(
      context: context,
      builder: (_) => SessionReportDialog(sessionId: sessionId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final reportAsync = ref.watch(sessionReportProvider(sessionId));

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: reportAsync.when(
          data: (report) => _ReportBody(report: report, colors: colors),
          loading: () => SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(color: colors.primary),
            ),
          ),
          error: (err, _) => Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.alertTriangle,
                    size: 32, color: colors.error),
                const SizedBox(height: 12),
                Text(
                  'Could not build session report',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$err',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  final SessionReport report;
  final NightshadeColors colors;

  const _ReportBody({required this.report, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Header(
          report: report,
          colors: colors,
          dateFormat: dateFormat,
          onCopyMarkdown: () => _copyMarkdown(context, ref),
          onExportTxt: () => _exportText(context, ref),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OverviewGrid(report: report, colors: colors),
                const SizedBox(height: 20),
                _SectionTitle(
                    title: 'Mount / operations',
                    icon: LucideIcons.settings2,
                    colors: colors),
                _MountStatsRow(report: report, colors: colors),
                const SizedBox(height: 20),
                _SectionTitle(
                    title: 'Guiding',
                    icon: LucideIcons.activity,
                    colors: colors),
                _GuideStatsBlock(report: report, colors: colors),
                if (report.avgTemperatureC != null ||
                    report.avgHumidityPercent != null ||
                    report.avgSeeingArcsec != null) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                      title: 'Conditions',
                      icon: LucideIcons.thermometer,
                      colors: colors),
                  _ConditionsRow(report: report, colors: colors),
                ],
                const SizedBox(height: 20),
                _SectionTitle(
                    title: 'Targets',
                    icon: LucideIcons.target,
                    colors: colors),
                if (report.targets.isEmpty)
                  _muted('No accepted light frames recorded.'),
                for (final target in report.targets) ...[
                  const SizedBox(height: 8),
                  _TargetBlock(target: target, colors: colors),
                ],
                if (report.errorMessages.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                      title: 'Errors',
                      icon: LucideIcons.xCircle,
                      colors: colors,
                      titleColor: colors.error),
                  ..._buildErrorList(),
                ],
                // Surface the live warningMessages we accumulated during
                // the run. Pre-patch these were collected by the
                // executor but never rendered anywhere post-session —
                // "filter Hα could not be matched 14 times" used to be
                // invisible the moment the run ended.
                if (report.warningMessages.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                      title: 'Warnings',
                      icon: LucideIcons.alertTriangle,
                      colors: colors,
                      titleColor: colors.warning),
                  ..._buildWarningList(),
                ],
                if (report.notes != null && report.notes!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                      title: 'Notes',
                      icon: LucideIcons.fileText,
                      colors: colors),
                  Text(
                    report.notes!,
                    style:
                        TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _muted(String text) => Text(
        text,
        style: TextStyle(fontSize: 13, color: colors.textMuted),
      );

  List<Widget> _buildErrorList() {
    return [
      for (final msg in report.errorMessages)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            msg,
            style: TextStyle(fontSize: 12, color: colors.error),
          ),
        ),
    ];
  }

  List<Widget> _buildWarningList() {
    return [
      for (final msg in report.warningMessages)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(LucideIcons.chevronRight,
                    size: 13, color: colors.warning),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  msg,
                  style: TextStyle(fontSize: 12, color: colors.warning),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Future<void> _copyMarkdown(BuildContext context, WidgetRef ref) async {
    final service = ref.read(sessionReportServiceProvider);
    final markdown = service.renderMarkdown(report);
    await Clipboard.setData(ClipboardData(text: markdown));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Session report copied as Markdown'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportText(BuildContext context, WidgetRef ref) async {
    final service = ref.read(sessionReportServiceProvider);
    final text = service.renderPlainText(report);
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docsDir.path, 'Nightshade', 'reports'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final safeName = report.sessionName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file = File(p.join(dir.path, '${safeName}_${report.sessionId}_$ts.txt'));
      await file.writeAsString(text);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report exported to ${file.path}'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }
}

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
                  style:
                      TextStyle(fontSize: 13, color: colors.textMuted),
                ),
                if (report.endTime != null)
                  Text(
                    '${dateFormat.format(report.startTime)} - ${dateFormat.format(report.endTime!)}',
                    style:
                        TextStyle(fontSize: 11, color: colors.textMuted),
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
          value:
              '${report.totalFramesAccepted}/${report.totalFramesAttempted}',
          colors: colors,
        ),
        _OverviewTile(
          label: 'Frames rejected',
          value: report.totalFramesRejected.toString(),
          colors: colors,
          valueColor:
              report.totalFramesRejected > 0 ? colors.warning : null,
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

class _MountStatsRow extends StatelessWidget {
  final SessionReport report;
  final NightshadeColors colors;

  const _MountStatsRow({required this.report, required this.colors});

  @override
  Widget build(BuildContext context) {
    final mount = report.mountStats;
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _StatChip(label: 'Autofocus runs', value: '${mount.autofocusRuns}', colors: colors),
        _StatChip(label: 'Meridian flips', value: '${mount.meridianFlips}', colors: colors),
        _StatChip(label: 'Dithers', value: '${mount.ditherCount}', colors: colors),
        _StatChip(label: 'Trigger fires', value: '${mount.triggerFires}', colors: colors),
      ],
    );
  }
}

class _GuideStatsBlock extends StatelessWidget {
  final SessionReport report;
  final NightshadeColors colors;

  const _GuideStatsBlock({required this.report, required this.colors});

  String _arcsec(double? v) =>
      v == null ? '-' : '${v.toStringAsFixed(2)}"';

  @override
  Widget build(BuildContext context) {
    final gs = report.guideStats;
    if (gs.isEmpty) {
      return Text(
        'No guide data recorded for this session.',
        style: TextStyle(fontSize: 13, color: colors.textMuted),
      );
    }
    final unguidedPct =
        (gs.percentUnguidedFrames * 100).toStringAsFixed(1);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _StatChip(label: 'Mean RA RMS', value: _arcsec(gs.meanRmsRaArcsec), colors: colors),
        _StatChip(label: 'Mean Dec RMS', value: _arcsec(gs.meanRmsDecArcsec), colors: colors),
        _StatChip(label: 'Mean total RMS', value: _arcsec(gs.meanRmsTotalArcsec), colors: colors),
        _StatChip(label: 'Max RA RMS', value: _arcsec(gs.maxRmsRaArcsec), colors: colors),
        _StatChip(label: 'Max Dec RMS', value: _arcsec(gs.maxRmsDecArcsec), colors: colors),
        _StatChip(label: 'Max total RMS', value: _arcsec(gs.maxRmsTotalArcsec), colors: colors),
        _StatChip(label: 'Unguided frames', value: '$unguidedPct%', colors: colors),
      ],
    );
  }
}

class _ConditionsRow extends StatelessWidget {
  final SessionReport report;
  final NightshadeColors colors;

  const _ConditionsRow({required this.report, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        if (report.avgTemperatureC != null)
          _StatChip(
            label: 'Mean temp',
            value: '${report.avgTemperatureC!.toStringAsFixed(1)} C',
            colors: colors,
          ),
        if (report.avgHumidityPercent != null)
          _StatChip(
            label: 'Mean humidity',
            value: '${report.avgHumidityPercent!.toStringAsFixed(1)}%',
            colors: colors,
          ),
        if (report.avgSeeingArcsec != null)
          _StatChip(
            label: 'Mean seeing',
            value: '${report.avgSeeingArcsec!.toStringAsFixed(2)}"',
            colors: colors,
          ),
      ],
    );
  }
}

class _TargetBlock extends StatelessWidget {
  final SessionTargetReport target;
  final NightshadeColors colors;

  const _TargetBlock({required this.target, required this.colors});

  String _formatDuration(double seconds) {
    final d = Duration(milliseconds: (seconds * 1000).round());
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  String _formatDouble(double? value, int digits) =>
      value == null ? '-' : value.toStringAsFixed(digits);

  @override
  Widget build(BuildContext context) {
    final allReasons = <String, int>{};
    for (final f in target.filters) {
      for (final entry in f.rejectionReasons.entries) {
        allReasons[entry.key] = (allReasons[entry.key] ?? 0) + entry.value;
      }
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                target.targetName,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${target.framesAccepted}/${target.framesAttempted} frames | ${_formatDuration(target.totalIntegrationSecs)}',
                style: TextStyle(fontSize: 12, color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: IntrinsicColumnWidth(),
              2: IntrinsicColumnWidth(),
              3: IntrinsicColumnWidth(),
              4: IntrinsicColumnWidth(),
              5: IntrinsicColumnWidth(),
              6: IntrinsicColumnWidth(),
              7: IntrinsicColumnWidth(),
              8: IntrinsicColumnWidth(),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.border)),
                ),
                children: [
                  _headerCell('Filter'),
                  _headerCell('Att.'),
                  _headerCell('Acc.'),
                  _headerCell('Rej.'),
                  _headerCell('Integration'),
                  _headerCell('HFR'),
                  _headerCell('FWHM'),
                  _headerCell('Stars'),
                  _headerCell('RMS'),
                ],
              ),
              for (final f in target.filters)
                TableRow(
                  children: [
                    _bodyCell(f.filter, bold: true),
                    _bodyCell('${f.framesAttempted}'),
                    _bodyCell('${f.framesAccepted}'),
                    _bodyCell(
                      '${f.framesRejected}',
                      color:
                          f.framesRejected > 0 ? colors.warning : null,
                    ),
                    _bodyCell(_formatDuration(f.totalIntegrationSecs)),
                    _bodyCell(_formatDouble(f.meanHfr, 2)),
                    _bodyCell(_formatDouble(f.meanFwhm, 2)),
                    _bodyCell(_formatDouble(f.meanStarCount, 0)),
                    _bodyCell(_formatDouble(f.meanGuidingRmsTotal, 2)),
                  ],
                ),
            ],
          ),
          if (allReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Rejections: ${_rejectionSummary(allReasons)}',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _rejectionSummary(Map<String, int> reasons) {
    final entries = reasons.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key} (${e.value})').join(', ');
  }

  Widget _headerCell(String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      );

  Widget _bodyCell(String value, {bool bold = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: color ?? colors.textPrimary,
          ),
        ),
      );
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final NightshadeColors colors;

  const _StatChip({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
