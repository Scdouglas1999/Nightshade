import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class FrameScienceChip extends ConsumerWidget {
  const FrameScienceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calibration = ref.watch(currentScienceSnapshotProvider).$1;
    if (calibration == null ||
        !calibration.isCalibrated ||
        calibration.zeroPoint == null) {
      return const SizedBox.shrink();
    }

    final colors = NightshadeColors.of(context);
    final limitingMag =
        calibration.limitingMag5Sigma ?? calibration.limitingMag3Sigma;

    return InkWell(
      onTap: () => context.go('/science'),
      borderRadius: NightshadeTokens.borderRadiusMd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: NightshadeTokens.minTouchTarget,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface
                .withValues(alpha: NightshadeTokens.opacityStrong),
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: NightshadeTokens.paddingSm,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MetricChip(
                  label: 'ZP',
                  value: calibration.zeroPoint!.toStringAsFixed(2),
                  colors: colors,
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                _MetricChip(
                  label: 'lim',
                  value: limitingMag != null
                      ? limitingMag.toStringAsFixed(2)
                      : '—',
                  colors: colors,
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                _MetricChip(
                  label: null,
                  value: '${calibration.matchedStarCount}',
                  trailingGlyph: '★',
                  colors: colors,
                ),
                const SizedBox(width: NightshadeTokens.spaceSm),
                Icon(
                  NightshadeIcons.chevronRight,
                  size: NightshadeTokens.iconXs,
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String? label;
  final String value;
  final String? trailingGlyph;
  final NightshadeColors colors;

  const _MetricChip({
    required this.label,
    required this.value,
    required this.colors,
    this.trailingGlyph,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = NightshadeTypography.withTabular(
      NightshadeTypography.monoSm,
    ).copyWith(color: colors.textPrimary);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: NightshadeTypography.labelQuiet.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(width: NightshadeTokens.spaceXs),
        ],
        Text(value, style: valueStyle),
        if (trailingGlyph != null) ...[
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            trailingGlyph!,
            style: NightshadeTypography.monoSm.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
