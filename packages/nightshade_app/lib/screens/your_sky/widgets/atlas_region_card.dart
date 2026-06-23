import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sky_atlas_format.dart';
import 'atlas_region_cutout.dart';

/// One region in the Your Sky gallery: a deep co-added preview, the region name
/// + kind, its centre, and the depth / growth rollups. Tapping opens the region
/// detail (cutout + time-scrub).
///
/// The preview renders the region's co-added cone via [AtlasRegionCutout], which
/// is portable across backends (host file path / remote PNG bytes), so the
/// gallery thumbnail renders on a slave instead of reading an empty local store.
class AtlasRegionCard extends ConsumerWidget {
  final SkyAtlasRegionRow region;
  final VoidCallback onTap;

  const AtlasRegionCard({
    super.key,
    required this.region,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final tilesAsync = ref.watch(atlasRegionTilesProvider(region.id));
    final timelineAsync = ref.watch(atlasRegionTimelineProvider(region.id));

    return NightshadeCard(
      onTap: onTap,
      enableHover: true,
      padding: EdgeInsets.zero,
      borderRadius: NightshadeTokens.radiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(NightshadeTokens.radiusLg),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: tilesAsync.when(
                data: (tiles) => tiles.isEmpty
                    ? _PreviewPlaceholder(colors: colors)
                    : AtlasRegionCutout(regionId: region.id),
                loading: () =>
                    _PreviewPlaceholder(colors: colors, loading: true),
                error: (_, __) => _PreviewPlaceholder(colors: colors),
              ),
            ),
          ),
          Padding(
            padding: NightshadeTokens.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        region.name,
                        style: NightshadeTypography.h5
                            .copyWith(color: colors.textPrimary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    _KindBadge(kind: region.kind),
                  ],
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
                Text(
                  formatCenter(region.centerRaDeg, region.centerDecDeg),
                  style: NightshadeTypography.monoSm
                      .copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                Row(
                  children: [
                    _Pill(
                      icon: LucideIcons.clock,
                      label: formatIntegration(region.integrationSeconds),
                      colors: colors,
                    ),
                    const SizedBox(width: NightshadeTokens.spaceSm),
                    _Pill(
                      icon: LucideIcons.layoutGrid,
                      label:
                          '${region.tileCount} tile${region.tileCount == 1 ? '' : 's'}',
                      colors: colors,
                    ),
                  ],
                ),
                timelineAsync.maybeWhen(
                  data: (folds) {
                    final phrase = _growthPhrase(folds);
                    if (phrase == null) return const SizedBox.shrink();
                    return Padding(
                      padding:
                          const EdgeInsets.only(top: NightshadeTokens.spaceSm),
                      child: Row(
                        children: [
                          Icon(LucideIcons.trendingUp,
                              size: NightshadeTokens.iconSm,
                              color: colors.success),
                          const SizedBox(width: NightshadeTokens.spaceXs),
                          Expanded(
                            child: Text(
                              phrase,
                              style: NightshadeTypography.captionSm
                                  .copyWith(color: colors.success),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A day-over-day "deeper than" phrase from the fold timeline: the integration
  /// gained on the most recent imaging day versus what existed before it. This
  /// is the "4h deeper than yesterday" headline. Returns null when the region
  /// has been touched on a single day (nothing comparative to say).
  String? _growthPhrase(List<SkyAtlasFoldRow> folds) {
    if (folds.isEmpty) return null;

    // Bucket the per-fold integration by UTC calendar day.
    final byDay = <int, double>{};
    for (final fold in folds) {
      final utc = fold.foldedAt.toUtc();
      final dayKey = utc.year * 10000 + utc.month * 100 + utc.day;
      byDay[dayKey] = (byDay[dayKey] ?? 0) + fold.integrationSecondsAdded;
    }
    final days = byDay.keys.toList()..sort();
    final latestDay = days.last;
    final recent = byDay[latestDay] ?? 0;
    if (recent <= 0) return null;

    final priorTotal = [
      for (final d in days)
        if (d != latestDay) byDay[d] ?? 0,
    ].fold<double>(0, (a, b) => a + b);

    if (days.length == 1) {
      return formatGrowthDelta(recentSeconds: recent, priorSeconds: 0);
    }
    return formatGrowthDelta(
      recentSeconds: recent,
      priorSeconds: priorTotal,
      period: 'before tonight',
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  final NightshadeColors colors;
  final bool loading;

  const _PreviewPlaceholder({required this.colors, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surfaceAlt,
      alignment: Alignment.center,
      child: loading
          ? const NightshadeCircularProgress(
              value: 0,
              indeterminate: true,
              size: NightshadeTokens.iconLg,
            )
          : Icon(LucideIcons.orbit,
              size: NightshadeTokens.iconLg, color: colors.textMuted),
    );
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;

  const _KindBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final tint = switch (kind) {
      'target' => colors.primary,
      'mosaic' => colors.info,
      'polar' => colors.warning,
      _ => colors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: 2,
      ),
      decoration: NightshadeDecorations.tintedBadge(tint),
      child: Text(
        _label(kind),
        style: NightshadeTypography.captionSm.copyWith(color: tint),
      ),
    );
  }

  static String _label(String kind) => switch (kind) {
        'target' => 'Target',
        'mosaic' => 'Mosaic',
        'polar' => 'Polar',
        'custom' => 'Custom',
        _ => kind.isEmpty ? 'Region' : kind,
      };
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _Pill({required this.icon, required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm,
        vertical: NightshadeTokens.spaceXs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusInline8,
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: NightshadeTokens.iconSm, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Text(
            label,
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
