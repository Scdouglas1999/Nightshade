/// Wave 8 — Frame-Failure Forensics: post-session report section.
///
/// Renders the "Frame Forensics" block inside the post-session report
/// (and the History tab's per-run drill-down). Aggregates every
/// rejection in the run, groups by `LikelyCause`, and offers a "Show me
/// all CloudPassage rejections" link that opens a filtered list.
///
/// Defaults to taking a `sequenceRunId` (the canonical join key for
/// the `frame_forensics` table). When the caller only has a Drift
/// `imaging_sessions.id` and no run-id mapping, an alternative
/// `[ForensicsSessionSection]` widget below is provided for convenience.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard/forensics_panel.dart' show forensicsCauseColor;
import 'run_dashboard/frame_detail_dialog.dart';

class ForensicsRunSection extends ConsumerWidget {
  final int sequenceRunId;
  const ForensicsRunSection({super.key, required this.sequenceRunId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final recordsAsync =
        ref.watch(forensicsRecordsForRunProvider(sequenceRunId));
    return recordsAsync.when(
      loading: () => const SizedBox(height: 24),
      error: (e, st) => _ErrorRow(message: e.toString(), colors: colors),
      data: (records) {
        if (records.isEmpty) return const SizedBox.shrink();
        return _ForensicsSummaryBlock(
          records: records,
          colors: colors,
          onShowCause: (cause) =>
              _showCauseDrilldown(context, ref, sequenceRunId, cause),
        );
      },
    );
  }

  void _showCauseDrilldown(
    BuildContext context,
    WidgetRef ref,
    int sequenceRunId,
    LikelyCause cause,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _CauseDrilldownDialog(
        sequenceRunId: sequenceRunId,
        cause: cause,
      ),
    );
  }
}

class _ForensicsSummaryBlock extends StatelessWidget {
  final List<FrameForensicsRecord> records;
  final NightshadeColors colors;
  final void Function(LikelyCause) onShowCause;

  const _ForensicsSummaryBlock({
    required this.records,
    required this.colors,
    required this.onShowCause,
  });

  @override
  Widget build(BuildContext context) {
    final summary = ForensicsService.summarize(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.search, size: 14, color: colors.primary),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'FRAME FORENSICS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Text(
          _buildHeadline(summary, records),
          style: TextStyle(
            fontSize: 12,
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        _StackedBar(summary: summary, colors: colors),
        const SizedBox(height: NightshadeTokens.spaceMd),
        ...summary.rankedCauses.map(
          (entry) => _CauseSummaryRow(
            cause: entry.key,
            count: entry.value,
            total: summary.total,
            colors: colors,
            onTap: () => onShowCause(entry.key),
          ),
        ),
      ],
    );
  }

  String _buildHeadline(
      ForensicSummary summary, List<FrameForensicsRecord> records) {
    final top = summary.rankedCauses.isNotEmpty
        ? summary.rankedCauses.first
        : null;
    if (top == null) {
      return 'Out of ${summary.total} rejections, no dominant cause was identified.';
    }
    final topWindow = _findCauseWindow(records, top.key);
    final topWindowText = topWindow == null
        ? ''
        : ' between ${topWindow.$1} and ${topWindow.$2}';
    return 'Out of ${summary.total} rejection${summary.total == 1 ? '' : 's'}, '
        '${top.value} ${top.value == 1 ? 'was' : 'were'} '
        '${top.key.humanLabel}$topWindowText.';
  }

  (String, String)? _findCauseWindow(
    List<FrameForensicsRecord> records,
    LikelyCause cause,
  ) {
    DateTime? first;
    DateTime? last;
    for (final r in records) {
      if (r.likelyCause != cause) continue;
      if (first == null || r.createdAt.isBefore(first)) first = r.createdAt;
      if (last == null || r.createdAt.isAfter(last)) last = r.createdAt;
    }
    if (first == null || last == null) return null;
    return (_fmt(first), _fmt(last));
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _StackedBar extends StatelessWidget {
  final ForensicSummary summary;
  final NightshadeColors colors;
  const _StackedBar({required this.summary, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (summary.isEmpty) return const SizedBox.shrink();
    final entries = summary.rankedCauses;
    return Row(
      children: entries.map((e) {
        return Expanded(
          flex: (e.value * 100).clamp(1, 1000),
          child: Container(
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: forensicsCauseColor(e.key, colors),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _CauseSummaryRow extends StatelessWidget {
  final LikelyCause cause;
  final int count;
  final int total;
  final NightshadeColors colors;
  final VoidCallback onTap;

  const _CauseSummaryRow({
    required this.cause,
    required this.count,
    required this.total,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count * 100 / total) : 0;
    final color = forensicsCauseColor(cause, colors);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                cause.humanLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '$count (${pct.toStringAsFixed(0)}%)',
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Text(
              'view',
              style: TextStyle(
                fontSize: 11,
                color: colors.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CauseDrilldownDialog extends ConsumerWidget {
  final int sequenceRunId;
  final LikelyCause cause;

  const _CauseDrilldownDialog({
    required this.sequenceRunId,
    required this.cause,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final filter = forensicsCauseFilter(cause, sequenceRunId: sequenceRunId);
    final recordsAsync = ref.watch(forensicsRecordsByCauseProvider(filter));
    final dialogSize = AdaptiveDialogConstraints.dialogSize(
      context,
      designWidth: 600,
      designHeight: 540,
    );
    return Dialog(
      child: SizedBox(
        width: dialogSize.width,
        height: dialogSize.height,
        child: Padding(
          padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${cause.humanLabel} rejections',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: forensicsCauseColor(cause, colors),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceMd),
              Expanded(
                child: recordsAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  error: (e, _) => Text('Error: $e'),
                  data: (records) {
                    if (records.isEmpty) {
                      return Center(
                        child: Text(
                          'No matching rejections',
                          style: TextStyle(color: colors.textMuted),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: records.length,
                      itemBuilder: (_, idx) {
                        final r = records[idx];
                        return ListTile(
                          dense: true,
                          title: Text(
                            'Frame ${r.frameIndex}/${r.totalFrames}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            r.reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                          trailing: Text(
                            _fmtTime(r.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textMuted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  FrameDetailDialog(record: r),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}:'
        '${l.second.toString().padLeft(2, '0')}';
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  final NightshadeColors colors;
  const _ErrorRow({required this.message, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Forensics section unavailable: $message',
      style: TextStyle(fontSize: 11, color: colors.error),
    );
  }
}
