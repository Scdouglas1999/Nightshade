import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sky_atlas_format.dart';

/// Atlas-wide coverage + growth summary card shown atop the Your Sky gallery.
///
/// Rolls up every materialized tile into the headline numbers (total
/// integration, tiles occupied, deepest tile) and renders a compact depth heat
/// strip so the observer can see their personal "deep field" forming. Pure
/// presentation over the [AtlasTileCoverage] list — no I/O, no ambient time.
class AtlasCoverageOverlay extends StatelessWidget {
  final List<AtlasTileCoverage> coverage;

  const AtlasCoverageOverlay({super.key, required this.coverage});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final totalSeconds =
        coverage.fold<double>(0, (sum, t) => sum + t.integrationSeconds);
    final totalFrames = coverage.fold<int>(0, (sum, t) => sum + t.totalFrames);
    final maxSeconds = coverage.isEmpty
        ? 0.0
        : coverage
            .map((t) => t.integrationSeconds)
            .reduce((a, b) => a > b ? a : b);

    return NightshadeCard(
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: NightshadeDecorations.tintedBadge(colors.primary),
                child: Icon(LucideIcons.layers,
                    size: NightshadeTokens.iconSm, color: colors.primary),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'Atlas coverage',
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _StatRow(
            stats: [
              _Stat(
                icon: LucideIcons.clock,
                label: 'Integration',
                value: formatIntegration(totalSeconds),
                tint: colors.primary,
              ),
              _Stat(
                icon: LucideIcons.layoutGrid,
                label: 'Tiles',
                value: '${coverage.length}',
                tint: colors.info,
              ),
              _Stat(
                icon: LucideIcons.image,
                label: 'Frames',
                value: '$totalFrames',
                tint: colors.success,
              ),
            ],
          ),
          if (coverage.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              'Depth map',
              style: NightshadeTypography.labelSm
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            _DepthHeatStrip(coverage: coverage, maxSeconds: maxSeconds),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'Each cell is a tile, brighter = deeper. Deepest: '
              '${formatIntegration(maxSeconds)}.',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The depth heat strip — one cell per tile, brightness scaled by integration
/// depth relative to the deepest tile (perceptual sqrt ramp).
class _DepthHeatStrip extends StatelessWidget {
  final List<AtlasTileCoverage> coverage;
  final double maxSeconds;

  const _DepthHeatStrip({required this.coverage, required this.maxSeconds});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    // Cap the number of rendered cells so a very large atlas does not blow out
    // the row; the deepest tiles come first (coverage is sorted deepest-first).
    const maxCells = 64;
    final cells =
        coverage.length > maxCells ? coverage.sublist(0, maxCells) : coverage;

    return Wrap(
      spacing: NightshadeTokens.spaceXs,
      runSpacing: NightshadeTokens.spaceXs,
      children: [
        for (final tile in cells)
          NightshadeTooltip(
            message: '${formatCenter(tile.centerRaDeg, tile.centerDecDeg)}\n'
                '${formatIntegration(tile.integrationSeconds)} · '
                '${tile.totalFrames} frames',
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Color.lerp(
                  colors.surfaceHover,
                  colors.primary,
                  normalizedDepth(tile.integrationSeconds, maxSeconds),
                ),
                borderRadius: NightshadeTokens.borderRadiusInline8,
                border: Border.all(
                    color: colors.border.withValues(alpha: 0.4), width: 0.5),
              ),
            ),
          ),
        if (coverage.length > maxCells)
          Container(
            height: 18,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(
                horizontal: NightshadeTokens.spaceXs),
            child: Text(
              '+${coverage.length - maxCells}',
              style: NightshadeTypography.captionSm
                  .copyWith(color: colors.textMuted),
            ),
          ),
      ],
    );
  }
}

class _Stat {
  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });
}

class _StatRow extends StatelessWidget {
  final List<_Stat> stats;

  const _StatRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < stats.length; i++) ...[
          if (i > 0) const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(child: _StatTile(stat: stats[i])),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final _Stat stat;

  const _StatTile({required this.stat});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Container(
      padding: const EdgeInsets.all(NightshadeTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(stat.icon, size: NightshadeTokens.iconSm, color: stat.tint),
          const SizedBox(height: NightshadeTokens.spaceSm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              stat.value,
              style: NightshadeTypography.statValue
                  .copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Text(
            stat.label,
            style: NightshadeTypography.captionSm
                .copyWith(color: colors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
