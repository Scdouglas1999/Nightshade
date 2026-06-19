import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'notes_panel.dart';
part 'session_report_dialog/header_overview.dart';
part 'session_report_dialog/target_conditions.dart';
part 'session_report_dialog/recovery_insights.dart';
part 'session_report_dialog/diagnostic_issue_tile.dart';

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
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
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
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textMuted),
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
                // "filter HÎ± could not be matched 14 times" used to be
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
                // List every recovery loop that fired during the run
                // with its cause, attempt count, duration, and outcome.
                // Scoped to this report's session via
                // `recoveryHistoryForSessionProvider`, which reloads the
                // persisted `session_diagnostics` row rather than the live
                // `recoveryHistoryProvider` — so a report viewed from the
                // History tab shows that session's recoveries, not the
                // currently-running one's.
                Consumer(builder: (context, ref, _) {
                  final recoveriesAsync = ref.watch(
                      recoveryHistoryForSessionProvider(report.sessionId));
                  final recoveries = recoveriesAsync.valueOrNull ?? const [];
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
                // Diagnostics section. Rendered last, after warnings +
                // recoveries. Combines the
                // optical-train drift comparison (pre/post snapshot)
                // with the equipment-health summary (USB disconnects,
                // cooler stability, focuser moves, sky brightness,
                // noticed concerns).
                Consumer(builder: (context, ref, _) {
                  final settingsAsync = ref.watch(appSettingsProvider);
                  final settings = settingsAsync.valueOrNull;
                  if (settings == null) return const SizedBox.shrink();

                  // Scoped to this report's session: reload the persisted
                  // pre/post optical-train snapshots from the
                  // `session_diagnostics` row instead of the live
                  // `opticalTrainBaselineProvider` /
                  // `opticalTrainCurrentSnapshotProvider`, so a historical
                  // report shows that session's drift, not the live run's.
                  final snapshot = ref
                      .watch(opticalTrainSnapshotForSessionProvider(
                          report.sessionId))
                      .valueOrNull;
                  final baseline = snapshot?.baseline;
                  final current = snapshot?.current;
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
                // Post-session retrospective insights. Renders after
                // Diagnostics so the operator sees raw observations
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
                    style: TextStyle(
                        fontSize: NightshadeTypography.fontSize13,
                        color: colors.textSecondary),
                  ),
                ],
                // Journal notes attached to either this session's run
                // or its primary target. Renders
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
        style: TextStyle(
            fontSize: NightshadeTypography.fontSize13, color: colors.textMuted),
      );

  List<Widget> _buildErrorList() {
    return [
      for (final msg in report.errorMessages)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            msg,
            style: TextStyle(
                fontSize: NightshadeTypography.fontSize12, color: colors.error),
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
                  style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.warning),
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

  /// Platforms with a system share sheet `share_plus` can drive. Desktop
  /// (Windows / Linux) has none, so those write to the documents dir and
  /// report the path instead. Mirrors the snippet-palette share gate.
  bool get _platformHasShareSheet {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.android:
      case TargetPlatform.macOS:
        return true;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  Future<void> _exportText(BuildContext context, WidgetRef ref) async {
    final service = ref.read(sessionReportServiceProvider);
    final text = service.renderPlainText(report);
    final ts =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final safeName =
        report.sessionName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final filename = '${safeName}_${report.sessionId}_$ts.txt';
    try {
      // On mobile, route through the system share sheet so the .txt is
      // actually reachable (the documents-dir write + 4s snackbar path was
      // a dead end on phones). Stage in the OS temp dir for the share.
      if (_platformHasShareSheet) {
        final tmpDir = await getTemporaryDirectory();
        final tmpFile = File(p.join(tmpDir.path, filename));
        await tmpFile.writeAsString(text);
        await Share.shareXFiles(
          [XFile(tmpFile.path, mimeType: 'text/plain')],
          subject: 'Session report — ${report.sessionName}',
        );
        return;
      }

      // Desktop: write to the documents dir and surface the path with a
      // reveal-in-clipboard action so the snackbar isn't a dead end.
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docsDir.path, 'Nightshade', 'reports'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File(p.join(dir.path, filename));
      await file.writeAsString(text);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report exported to ${file.path}'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Copy path',
            onPressed: () => Clipboard.setData(ClipboardData(text: file.path)),
          ),
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
