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
    final lastRun = ref.watch(sequenceRunsProvider).maybeWhen(
          data: (runs) => runs.isEmpty ? null : runs.first,
          orElse: () => null,
        );

    if (lastRun == null) {
      return const SizedBox.shrink();
    }

    final stats = _tryParse(lastRun.statsJson);
    final accepted =
        stats == null ? null : stats.framesCaptured - stats.framesRejected;

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      onTap: () => context.go('/session-review?session=${lastRun.id}'),
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
            lastRun.sequenceName,
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
