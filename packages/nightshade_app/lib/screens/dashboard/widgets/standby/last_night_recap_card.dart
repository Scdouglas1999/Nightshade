import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../glass_card.dart';

/// Recap of the most recent sequence run: status, name, relative time, and —
/// when the stored stats blob parses — a row of stat chips (integration time,
/// frames, rejections, duration). Falls back to the bare status row when the
/// stats JSON is missing or malformed, and to a friendly one-liner when there
/// are no runs yet.
class LastNightRecapCard extends ConsumerWidget {
  final NightshadeColors colors;

  const LastNightRecapCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsAsync = ref.watch(sequenceRunsProvider);
    // watchAllRuns() orders by startedAt desc, so the head is the newest run.
    final lastRun = runsAsync.maybeWhen(
      data: (runs) => runs.isEmpty ? null : runs.first,
      orElse: () => null,
    );

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.history,
            title: 'Last night',
            accent: colors.textMuted,
          ),
          const SizedBox(height: DashboardCardStyle.headerGap),
          if (lastRun == null)
            Text(
              'No runs yet — your first night will appear here.',
              style: NightshadeTypography.bodySm.copyWith(
                color: colors.textMuted,
              ),
            )
          else
            _runBody(context, lastRun),
        ],
      ),
    );
  }

  Widget _runBody(BuildContext context, SequenceRun run) {
    final stats = _tryParse(run.statsJson);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(_statusIcon(run.status),
                size: 16, color: _statusColor(run.status, colors)),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                run.sequenceName,
                style: NightshadeTypography.body.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${_statusLabel(run.status)} · ${_relativeTime(run.startedAt)}',
          style: NightshadeTypography.withTabular(
            NightshadeTypography.caption.copyWith(color: colors.textMuted),
          ),
        ),
        if (stats != null) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          Wrap(
            spacing: NightshadeTokens.spaceSm,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              _StatChip(
                colors: colors,
                icon: LucideIcons.timer,
                value: stats.formatDuration(stats.integrationSecs),
                label: 'integration',
              ),
              _StatChip(
                colors: colors,
                icon: LucideIcons.image,
                value: '${stats.framesCaptured}',
                label: 'frames',
              ),
              if (stats.framesRejected > 0)
                _StatChip(
                  colors: colors,
                  icon: LucideIcons.xCircle,
                  value: '${stats.framesRejected}',
                  label: 'rejected',
                  tint: colors.warning,
                ),
              _StatChip(
                colors: colors,
                icon: LucideIcons.clock,
                value: stats.formatDuration(stats.wallClockSecs),
                label: 'duration',
              ),
            ],
          ),
        ],
        const SizedBox(height: NightshadeTokens.spaceMd),
        Align(
          alignment: Alignment.centerRight,
          child: NightshadeButton(
            label: 'Open last run',
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            // History deep-linking by run id isn't a stable route, so we link
            // to the Sequencer where the History tab surfaces the run list.
            onPressed: () => context.go('/sequencer'),
          ),
        ),
      ],
    );
  }

  /// Defensive parse: the stored blob may be empty/null/malformed. Any failure
  /// → null so we degrade to the bare status row instead of throwing.
  ParsedRunStats? _tryParse(String json) {
    if (json.isEmpty) return null;
    try {
      final parsed = ParsedRunStats.fromJson(json);
      // A run with zero frames and zero wall-clock carries no useful chips.
      if (parsed.framesCaptured == 0 && parsed.wallClockSecs <= 0) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return LucideIcons.checkCircle;
      case 'failed':
        return LucideIcons.xCircle;
      case 'aborted':
        return LucideIcons.octagon;
      case 'running':
        return LucideIcons.activity;
      default:
        return LucideIcons.history;
    }
  }

  Color _statusColor(String status, NightshadeColors colors) {
    switch (status) {
      case 'completed':
        return colors.success;
      case 'failed':
      case 'aborted':
        return colors.error;
      case 'running':
        return colors.info;
      default:
        return colors.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed';
      case 'aborted':
        return 'Aborted';
      case 'running':
        return 'Running';
      default:
        return status.isEmpty
            ? 'Unknown'
            : '${status[0].toUpperCase()}${status.substring(1)}';
    }
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final d = diff.inDays;
    if (d < 30) return '$d day${d == 1 ? '' : 's'} ago';
    final months = (d / 30).floor();
    return '$months month${months == 1 ? '' : 's'} ago';
  }
}

class _StatChip extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String value;
  final String label;
  final Color? tint;

  const _StatChip({
    required this.colors,
    required this.icon,
    required this.value,
    required this.label,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final accent = tint ?? colors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 6),
          Text(
            value,
            style: NightshadeTypography.withTabular(
              NightshadeTypography.labelStrongSm.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                NightshadeTypography.caption.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}
