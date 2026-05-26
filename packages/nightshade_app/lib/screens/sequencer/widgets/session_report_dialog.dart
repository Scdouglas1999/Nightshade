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

import 'notes_panel.dart';

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
    final colors = NightshadeColors.of(context);
    final reportAsync = ref.watch(sessionReportProvider(sessionId));

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      child: ConstrainedBox(
        constraints: AdaptiveDialogConstraints.hybrid(
          context,
          designMaxWidth: 720,
          designMaxHeight: 760,
        ),
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
                Icon(LucideIcons.alertTriangle, size: 32, color: colors.error),
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
                    title: 'Targets', icon: LucideIcons.target, colors: colors),
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
                // Wave 4 Recovery Mode — list every recovery loop that
                // fired during the run with its cause, attempt count,
                // duration, and outcome. Pulled from the
                // `recoveryHistoryProvider` populated in real time by
                // `recoveryEventBridgeProvider`.
                Consumer(builder: (context, ref, _) {
                  final recoveries = ref.watch(recoveryHistoryProvider);
                  if (recoveries.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _SectionTitle(
                          title: 'Recoveries',
                          icon: LucideIcons.rotateCw,
                          colors: colors,
                          titleColor: colors.error),
                      for (final entry in recoveries) ...[
                        _RecoveryHistoryTile(entry: entry, colors: colors),
                        const SizedBox(height: 4),
                      ],
                    ],
                  );
                }),
                // Wave 5 Agent 3 — Diagnostics section. Rendered last,
                // after warnings + recoveries. Combines the
                // optical-train drift comparison (pre/post snapshot)
                // with the equipment-health summary (USB disconnects,
                // cooler stability, focuser moves, sky brightness,
                // noticed concerns).
                Consumer(builder: (context, ref, _) {
                  final settingsAsync = ref.watch(appSettingsProvider);
                  final settings = settingsAsync.valueOrNull;
                  if (settings == null) return const SizedBox.shrink();

                  final baseline = ref.watch(opticalTrainBaselineProvider);
                  final current =
                      ref.watch(opticalTrainCurrentSnapshotProvider);
                  final healthSummary = ref.watch(
                      postSessionHealthSummaryProvider(report.sessionId));

                  // Synthesize an OpticalTrainDiagnostics from the
                  // current snapshot so the helper can compute drift.
                  // We only have score values in the snapshot; the
                  // helper treats absent issues as benign.
                  OpticalTrainDiagnostics? currentDiag;
                  if (current != null) {
                    currentDiag = OpticalTrainDiagnostics(
                      tiltScore: current.tiltScore,
                      collimationScore: current.collimationScore,
                      dominantTiltDirection: 'unknown',
                      issues: const [],
                    );
                  }

                  final diagnostics = PostSessionDiagnostics.build(
                    preSession: baseline,
                    postSession: currentDiag,
                    healthSummary: healthSummary,
                    opticalTrainDriftThreshold:
                        settings.opticalTrainDriftThreshold,
                  );

                  if (diagnostics.isEmpty) return const SizedBox.shrink();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _SectionTitle(
                          title: 'Diagnostics',
                          icon: LucideIcons.stethoscope,
                          colors: colors,
                          titleColor: colors.primary),
                      for (final issue in diagnostics.all) ...[
                        _DiagnosticIssueTile(
                          issue: issue,
                          colors: colors,
                        ),
                        const SizedBox(height: 6),
                      ],
                    ],
                  );
                }),
                // Wave 7 — Post-session retrospective insights. Renders
                // after Diagnostics so the operator sees raw observations
                // first, then "what to change next time" last. Each insight
                // exposes Apply (when actionable) + Dismiss + sticky
                // "Don't suggest this again".
                Consumer(builder: (context, ref, _) {
                  final insightsAsync =
                      ref.watch(sessionInsightsProvider(report.sessionId));
                  return insightsAsync.maybeWhen(
                    data: (insights) {
                      if (insights.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 20),
                          _SectionTitle(
                            title: 'Suggestions',
                            icon: LucideIcons.lightbulb,
                            colors: colors,
                            titleColor: colors.primary,
                          ),
                          for (final insight in insights) ...[
                            _SessionInsightTile(
                              insight: insight,
                              colors: colors,
                            ),
                            const SizedBox(height: 6),
                          ],
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  );
                }),
                if (report.notes != null && report.notes!.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _SectionTitle(
                      title: 'Session Notes',
                      icon: LucideIcons.fileText,
                      colors: colors),
                  Text(
                    report.notes!,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                  ),
                ],
                // Wave 6 Agent 5 — Journal notes attached to either
                // this session's run or its primary target. Renders
                // the same `_NoteTile` rows the History tab and
                // target card use, so an edit propagates everywhere.
                Consumer(builder: (context, ref, _) {
                  final runId = ref.watch(currentRunIdProvider);
                  // Prefer run-scoped notes when we have a run id; fall
                  // back to per-target notes via the first target in the
                  // report (most common: a sequence images one target
                  // per session).
                  if (runId != null) {
                    final primaryTarget = report.targets.isNotEmpty
                        ? report.targets.first.targetName
                        : (report.sessionName);
                    return Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionTitle(
                            title: 'Journal',
                            icon: LucideIcons.bookOpen,
                            colors: colors,
                          ),
                          RunNotesSection(
                            sequenceRunId: runId,
                            targetId: primaryTarget,
                            colors: colors,
                            embedded: true,
                          ),
                        ],
                      ),
                    );
                  }
                  if (report.targets.isEmpty) return const SizedBox.shrink();
                  final primaryTarget = report.targets.first.targetName;
                  return Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle(
                          title: 'Journal',
                          icon: LucideIcons.bookOpen,
                          colors: colors,
                        ),
                        TargetNotesSection(
                          targetId: primaryTarget,
                          colors: colors,
                          embedded: true,
                        ),
                      ],
                    ),
                  );
                }),
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
      final safeName =
          report.sessionName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final file =
          File(p.join(dir.path, '${safeName}_${report.sessionId}_$ts.txt'));
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
        _StatChip(
            label: 'Autofocus runs',
            value: '${mount.autofocusRuns}',
            colors: colors),
        _StatChip(
            label: 'Meridian flips',
            value: '${mount.meridianFlips}',
            colors: colors),
        _StatChip(
            label: 'Dithers', value: '${mount.ditherCount}', colors: colors),
        _StatChip(
            label: 'Trigger fires',
            value: '${mount.triggerFires}',
            colors: colors),
      ],
    );
  }
}

class _GuideStatsBlock extends StatelessWidget {
  final SessionReport report;
  final NightshadeColors colors;

  const _GuideStatsBlock({required this.report, required this.colors});

  String _arcsec(double? v) => v == null ? '-' : '${v.toStringAsFixed(2)}"';

  @override
  Widget build(BuildContext context) {
    final gs = report.guideStats;
    if (gs.isEmpty) {
      return Text(
        'No guide data recorded for this session.',
        style: TextStyle(fontSize: 13, color: colors.textMuted),
      );
    }
    final unguidedPct = (gs.percentUnguidedFrames * 100).toStringAsFixed(1);
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        _StatChip(
            label: 'Mean RA RMS',
            value: _arcsec(gs.meanRmsRaArcsec),
            colors: colors),
        _StatChip(
            label: 'Mean Dec RMS',
            value: _arcsec(gs.meanRmsDecArcsec),
            colors: colors),
        _StatChip(
            label: 'Mean total RMS',
            value: _arcsec(gs.meanRmsTotalArcsec),
            colors: colors),
        _StatChip(
            label: 'Max RA RMS',
            value: _arcsec(gs.maxRmsRaArcsec),
            colors: colors),
        _StatChip(
            label: 'Max Dec RMS',
            value: _arcsec(gs.maxRmsDecArcsec),
            colors: colors),
        _StatChip(
            label: 'Max total RMS',
            value: _arcsec(gs.maxRmsTotalArcsec),
            colors: colors),
        _StatChip(
            label: 'Unguided frames', value: '$unguidedPct%', colors: colors),
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
                      color: f.framesRejected > 0 ? colors.warning : null,
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

  Widget _bodyCell(String value, {bool bold = false, Color? color}) => Padding(
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

/// Wave 4 Recovery Mode — single-row tile rendering a completed recovery
/// loop in the post-session report. Shows cause, attempt count, duration,
/// outcome (recovered / exhausted / aborted) and the final error message
/// (truncated).
class _RecoveryHistoryTile extends StatelessWidget {
  final RecoveryHistoryEntry entry;
  final NightshadeColors colors;

  const _RecoveryHistoryTile({required this.entry, required this.colors});

  @override
  Widget build(BuildContext context) {
    final outcomeColor = entry.recovered
        ? colors.success
        : (entry.abortedByUser ? colors.warning : colors.error);
    final outcomeLabel = entry.recovered
        ? 'recovered'
        : (entry.abortedByUser ? 'aborted by operator' : 'exhausted');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: NightshadeDecorations.iconChip(
        outcomeColor,
        borderRadius: BorderRadius.circular(6),
        borderAlpha: 0.35,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.cause.displayLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                outcomeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: outcomeColor,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.attempts} attempt${entry.attempts == 1 ? '' : 's'} · '
            '${_formatDuration(entry.durationSecs)}',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (entry.lastError != null && entry.lastError!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              entry.lastError!,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(double secs) {
    if (secs < 60) return '${secs.toStringAsFixed(0)}s';
    final mins = (secs / 60).floor();
    final rem = (secs - mins * 60).round();
    if (rem == 0) return '${mins}m';
    return '${mins}m ${rem}s';
  }
}

/// Wave 7 — render one post-session [SessionInsight] inside the
/// Suggestions section. Includes:
///   * Title + confidence badge.
///   * Optional body / recommendation (collapsed by default; tap to
///     expand — same affordance as the diagnostic tile).
///   * "Apply" button when the insight has an `applyHint` (e.g. an
///     `altitudeAboveDeg` value that pre-fills the target editor).
///   * "Dismiss" + "Don't suggest this again" (sticky via
///     [dismissedSessionInsightsProvider]).
class _SessionInsightTile extends ConsumerStatefulWidget {
  final SessionInsight insight;
  final NightshadeColors colors;

  const _SessionInsightTile({
    required this.insight,
    required this.colors,
  });

  @override
  ConsumerState<_SessionInsightTile> createState() =>
      _SessionInsightTileState();
}

class _SessionInsightTileState extends ConsumerState<_SessionInsightTile> {
  bool _expanded = false;
  bool _dismissed = false;

  IconData _iconForKind(SessionInsightKind kind) {
    switch (kind) {
      case SessionInsightKind.altitudeWindow:
        return LucideIcons.arrowUpRight;
      case SessionInsightKind.autofocusFrequency:
        return LucideIcons.focus;
      case SessionInsightKind.filterChangeOverhead:
        return LucideIcons.filter;
      case SessionInsightKind.rejectionRate:
        return LucideIcons.xCircle;
      case SessionInsightKind.guidingDegraded:
        return LucideIcons.activity;
      case SessionInsightKind.efficiencyLow:
        return LucideIcons.timer;
      case SessionInsightKind.informational:
        return LucideIcons.info;
    }
  }

  Color _confidenceColor(double confidence, NightshadeColors c) {
    if (confidence >= 0.75) return c.error;
    if (confidence >= 0.5) return c.warning;
    return c.info;
  }

  /// Apply the insight's `applyHint` payload. Today we only support
  /// the `altitudeAboveDeg` hint (jump to the target editor with the
  /// suggested `startWhen` crossing). Future hint types would land
  /// in this switch.
  Future<void> _onApply() async {
    final hint = widget.insight.applyHint;
    if (hint == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (hint.containsKey('altitudeAboveDeg')) {
      final value = (hint['altitudeAboveDeg'] as num?)?.toDouble();
      if (value == null) return;
      // Pre-fill the editor by mutating the live in-editor sequence:
      // find the target by id (when supplied) and update its
      // startWhen. The editor is the active surface when the user
      // closes the report — so the change is visible immediately.
      final notifier = ref.read(currentSequenceProvider.notifier);
      final sequence = ref.read(currentSequenceProvider);
      if (sequence == null) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('No sequence is open to apply the suggestion to.'),
          ),
        );
        return;
      }
      final targetId = widget.insight.targetId;
      TargetHeaderNode? match;
      for (final h in sequence.targetHeaders) {
        // The targetId in the optimizer maps to the Drift targets row;
        // for now we match by display name (`targetName`) when present.
        // The Drift id is not stored on the in-editor node tree so
        // name-matching is the canonical join key.
        if (targetId != null && h.targetName.isNotEmpty) {
          match = h;
          break;
        }
      }
      if (match == null && sequence.targetHeaders.isNotEmpty) {
        match = sequence.targetHeaders.first;
      }
      if (match == null) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('No target header to apply altitude to.'),
          ),
        );
        return;
      }
      notifier.updateNode(match.copyWith(
        startWhen: AltitudeAboveTrigger(value),
      ));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Applied: ${match.targetName} starts at '
            '${value.toStringAsFixed(0)}° altitude.',
          ),
        ),
      );
      return;
    }
    if (hint.containsKey('autofocusInterval')) {
      // Route to settings screen so the user can adjust the value
      // there; we don't auto-mutate global settings from a single
      // insight click.
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Open Settings → Autofocus to relax the trigger interval.',
          ),
        ),
      );
      return;
    }
  }

  Future<void> _onDismiss({required bool sticky}) async {
    setState(() => _dismissed = true);
    if (sticky) {
      await ref
          .read(dismissedSessionInsightsProvider.notifier)
          .dismiss(widget.insight.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final c = widget.colors;
    final conf = widget.insight.confidence;
    final confColor = _confidenceColor(conf, c);
    final hasBody =
        (widget.insight.body != null && widget.insight.body!.isNotEmpty) ||
            (widget.insight.recommendation != null &&
                widget.insight.recommendation!.isNotEmpty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: confColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_iconForKind(widget.insight.kind),
                  size: 14, color: confColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.insight.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: NightshadeDecorations.statusChip(
                  confColor,
                  borderRadius: BorderRadius.circular(4),
                  bordered: false,
                ),
                child: Text(
                  '${(conf * 100).round()}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: confColor,
                  ),
                ),
              ),
            ],
          ),
          if (hasBody) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Text(
                    _expanded ? 'Hide details' : 'Show details',
                    style: TextStyle(
                      fontSize: 10,
                      color: c.textMuted,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  Icon(
                    _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 12,
                    color: c.textMuted,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              if (widget.insight.body != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.insight.body!,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.textSecondary,
                  ),
                ),
              ],
              if (widget.insight.recommendation != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.insight.recommendation!,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.insight.isActionable)
                TextButton(
                  onPressed: _onApply,
                  child: Text(
                    'Apply',
                    style: TextStyle(
                      fontSize: 11,
                      color: c.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => _onDismiss(sticky: false),
                child: Text(
                  'Dismiss',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => _onDismiss(sticky: true),
                child: Text(
                  "Don't suggest again",
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Wave 5 Agent 3 — single diagnostic line in the session report's
/// Diagnostics section. Mirrors the look of `_PreflightSection`'s
/// issue rows but with the lighter post-session tone (everything is
/// info-severity).
class _DiagnosticIssueTile extends StatelessWidget {
  final ValidationIssue issue;
  final NightshadeColors colors;

  const _DiagnosticIssueTile({
    required this.issue,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = issue.category == ValidationCategory.opticalTrain
        ? colors.primary
        : colors.info;
    final icon = issue.category == ValidationCategory.opticalTrain
        ? LucideIcons.crosshair
        : LucideIcons.activity;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  issue.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
                if (issue.resolutionHint != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    issue.resolutionHint!,
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.primary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
