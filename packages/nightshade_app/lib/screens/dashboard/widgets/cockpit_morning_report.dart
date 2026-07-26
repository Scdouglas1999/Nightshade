import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class CockpitMorningReport extends ConsumerWidget {
  const CockpitMorningReport({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final runsAsync = ref.watch(sequenceRunsProvider);

    return runsAsync.when(
      loading: () => _ReportStatusCard(
        colors: colors,
        icon: LucideIcons.loader2,
        title: 'Loading morning report…',
      ),
      error: (error, _) => _ReportStatusCard(
        colors: colors,
        icon: LucideIcons.alertTriangle,
        title: 'Morning report unavailable',
        detail: '$error',
        onRetry: () => ref.invalidate(sequenceRunsProvider),
      ),
      data: (runs) {
        if (runs.isEmpty) return const SizedBox.shrink();
        return _RunReportCard(run: runs.first, colors: colors);
      },
    );
  }
}

class _RunReportCard extends ConsumerWidget {
  const _RunReportCard({required this.run, required this.colors});

  final SequenceRun run;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sequenceRunSessionIdProvider(run.id));
    final sessionId = sessionAsync.valueOrNull;
    final destination = sessionId == null
        ? '/sequencer?tab=history'
        : '/session-review?session=$sessionId';

    final stats = _tryParse(run.statsJson);
    final accepted =
        stats == null ? null : stats.framesCaptured - stats.framesRejected;

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      onTap: () => context.go(destination),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sunrise, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'MORNING REPORT',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.chevronRight, size: 14, color: colors.textMuted),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          Text(
            run.sequenceName,
            style: NightshadeTypography.body.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (accepted != null) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Row(
              children: [
                Flexible(
                  child: _Metric(
                    label: 'accepted',
                    value: '$accepted',
                    colors: colors,
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceLg),
                Flexible(
                  child: _Metric(
                    label: 'rejected',
                    value: '${stats!.framesRejected}',
                    colors: colors,
                    tint: stats.framesRejected > 0 ? colors.warning : null,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: NightshadeTokens.spaceSm),
          sessionAsync.when(
            loading: () => Text(
              'Finding the matching imaging session…',
              style: NightshadeTypography.caption.copyWith(
                color: colors.textMuted,
              ),
            ),
            error: (error, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    'Session link unavailable — opens run history instead.',
                    style: NightshadeTypography.caption.copyWith(
                      color: colors.warning,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      ref.invalidate(sequenceRunSessionIdProvider(run.id)),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (resolvedSessionId) => Text(
              resolvedSessionId == null
                  ? 'No matching session — open run history'
                  : 'Open morning report',
              style: NightshadeTypography.caption.copyWith(
                color:
                    resolvedSessionId == null ? colors.warning : colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ParsedRunStats? _tryParse(String json) {
    if (json.isEmpty) return null;
    try {
      final parsed = ParsedRunStats.fromJson(json);
      if (parsed.framesCaptured == 0 && parsed.wallClockSecs <= 0) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }
}

class _ReportStatusCard extends StatelessWidget {
  const _ReportStatusCard({
    required this.colors,
    required this.icon,
    required this.title,
    this.detail,
    this.onRetry,
  });

  final NightshadeColors colors;
  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: onRetry == null ? colors.info : colors.error),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: NightshadeTypography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NightshadeTypography.caption.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.colors,
    this.tint,
  });

  final String label;
  final String value;
  final NightshadeColors colors;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: NightshadeTypography.fontSize10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: colors.textMuted,
          ),
        ),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            NightshadeTypography.h4.copyWith(
              fontWeight: FontWeight.w700,
              color: tint ?? colors.textPrimary,
              height: 1.1,
            ),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
