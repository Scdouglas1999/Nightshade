import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../sky_atlas_format.dart';

/// Atlas-wide coverage + growth summary card shown atop the Your Sky gallery.
///
/// Rolls up every materialized tile into the headline numbers (total
/// integration, tiles occupied, deepest tile) and renders an all-sky Aitoff
/// coverage map so the observer can see WHERE on the sphere their personal
/// "deep field" is forming — each tile plotted at its true RA/Dec, brightness
/// scaled by integration depth, tappable for the per-tile breakdown. Pure
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
              'All-sky map',
              style: NightshadeTypography.labelSm
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            _AllSkyCoverageMap(coverage: coverage, maxSeconds: maxSeconds),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              'Each point is a tile at its place on the sky (Aitoff projection); '
              'brighter = deeper. Tap a point for its depth. Deepest: '
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

/// An equal-area **Aitoff** all-sky map of atlas coverage. Every materialized
/// tile is plotted at its true (RA, Dec) — RA increasing leftward astronomical
/// convention, centred on RA = 12h — with marker brightness/size scaled by
/// integration depth. Tapping the nearest tile opens a per-tile breakdown sheet;
/// the whole map carries a [Semantics] summary and each tile a per-point label.
class _AllSkyCoverageMap extends StatelessWidget {
  final List<AtlasTileCoverage> coverage;
  final double maxSeconds;

  const _AllSkyCoverageMap({required this.coverage, required this.maxSeconds});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);

    final summary = 'All-sky coverage map: ${coverage.length} tile'
        '${coverage.length == 1 ? '' : 's'} imaged, deepest '
        '${formatIntegration(maxSeconds)}.';

    return Semantics(
      container: true,
      label: summary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Aitoff fills a 2:1 frame; clamp the height so the card stays compact.
          final height = (width / 2).clamp(120.0, 220.0);
          return Stack(
            children: [
              SizedBox(
                width: width,
                height: height,
                child: GestureDetector(
                  onTapUp: (details) => _handleTap(
                    context,
                    details.localPosition,
                    Size(width, height),
                  ),
                  child: CustomPaint(
                    painter: _AitoffPainter(
                      coverage: coverage,
                      maxSeconds: maxSeconds,
                      grid: colors.border.withValues(alpha: 0.35),
                      outline: colors.border.withValues(alpha: 0.55),
                      surface: colors.surfaceHover,
                      deep: colors.primary,
                    ),
                    size: Size(width, height),
                  ),
                ),
              ),
              // Per-tile accessibility labels: invisible Semantics nodes at each
              // projected point so a screen reader can enumerate coverage that
              // the CustomPaint alone cannot expose.
              for (final tile in coverage)
                if (aitoffProject(
                  tile.centerRaDeg,
                  tile.centerDecDeg,
                  Size(width, height),
                )
                    case final Offset pos)
                  Positioned(
                    left: pos.dx - 8,
                    top: pos.dy - 8,
                    width: 16,
                    height: 16,
                    child: Semantics(
                      button: true,
                      label:
                          '${formatCenter(tile.centerRaDeg, tile.centerDecDeg)}, '
                          '${formatIntegration(tile.integrationSeconds)}, '
                          '${tile.totalFrames} frame'
                          '${tile.totalFrames == 1 ? '' : 's'}',
                      onTap: () => _showTile(context, tile),
                      child: const SizedBox.shrink(),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  void _handleTap(BuildContext context, Offset local, Size size) {
    AtlasTileCoverage? nearest;
    var nearestDist = double.infinity;
    for (final tile in coverage) {
      final pos = aitoffProject(tile.centerRaDeg, tile.centerDecDeg, size);
      if (pos == null) continue;
      final d = (pos - local).distanceSquared;
      if (d < nearestDist) {
        nearestDist = d;
        nearest = tile;
      }
    }
    // Only register a hit within a generous touch radius so a tap on empty sky
    // does nothing rather than selecting a far-off tile.
    if (nearest != null && nearestDist <= 28 * 28) {
      _showTile(context, nearest);
    }
  }

  void _showTile(BuildContext context, AtlasTileCoverage tile) {
    showAdaptiveModal<void>(
      context: context,
      designWidth: 420,
      builder: (context) =>
          _TileDetailSheet(tile: tile, maxSeconds: maxSeconds),
    );
  }
}

/// Aitoff (Hammer equal-area) projection of (RA°, Dec°) onto a 2:1 frame. RA is
/// shown increasing LEFTWARD (astronomical sky convention), centred on RA = 180°
/// (12h) so the galactic-rich half of the sky is not split at the seam. Returns
/// null only for non-finite inputs. Exposed for unit testing the math.
@visibleForTesting
Offset? aitoffProject(double raDeg, double decDeg, Size size) {
  if (!raDeg.isFinite || !decDeg.isFinite) return null;

  // Longitude relative to the RA=180° centre, RA increasing leftward, wrapped
  // to (-180, 180].
  var lon = 180.0 - raDeg;
  lon = ((lon + 180.0) % 360.0) - 180.0;
  final lambda = lon * math.pi / 180.0; // -pi..pi
  final phi = decDeg.clamp(-90.0, 90.0) * math.pi / 180.0;

  // Hammer-Aitoff equal-area projection. With z = sqrt(1 + cos phi · cos(λ/2))
  // the image is the ellipse x ∈ [-2√2, 2√2], y ∈ [-√2, √2]; the 2:1 aspect of
  // that bounding box is exactly the 2:1 frame this map draws into.
  final cosPhi = math.cos(phi);
  final cosHalfLambda = math.cos(lambda / 2.0);
  final z = math.sqrt(1.0 + cosPhi * cosHalfLambda);
  if (z == 0.0) return null;
  final x = 2.0 * math.sqrt2 * cosPhi * math.sin(lambda / 2.0) / z;
  final y = math.sqrt2 * math.sin(phi) / z;

  // Normalise the bounding ellipse (x: ±2√2, y: ±√2) into the widget frame with
  // a small inset so edge points are not clipped.
  const inset = 4.0;
  const xHalf = 2.0 * math.sqrt2;
  const yHalf = math.sqrt2;
  final w = size.width - inset * 2;
  final h = size.height - inset * 2;
  final px = inset + (x / xHalf + 1.0) / 2.0 * w;
  final py = inset + (1.0 - y / yHalf) / 2.0 * h;
  return Offset(px, py);
}

/// Paints the Aitoff frame: an elliptical sky outline, a light RA/Dec graticule,
/// and one depth-scaled dot per tile.
class _AitoffPainter extends CustomPainter {
  final List<AtlasTileCoverage> coverage;
  final double maxSeconds;
  final Color grid;
  final Color outline;
  final Color surface;
  final Color deep;

  _AitoffPainter({
    required this.coverage,
    required this.maxSeconds,
    required this.grid,
    required this.outline,
    required this.surface,
    required this.deep,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 4.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = (size.width - inset * 2) / 2;
    final ry = (size.height - inset * 2) / 2;

    // Sky outline (the Aitoff boundary is an ellipse).
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = outline;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2),
      outlinePaint,
    );

    // Graticule: meridians every 60° of RA, parallels every 30° of Dec.
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = grid;
    for (var ra = 0; ra < 360; ra += 60) {
      final path = Path();
      var started = false;
      for (var dec = -90; dec <= 90; dec += 5) {
        final pos = aitoffProject(ra.toDouble(), dec.toDouble(), size);
        if (pos == null) continue;
        if (!started) {
          path.moveTo(pos.dx, pos.dy);
          started = true;
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      canvas.drawPath(path, gridPaint);
    }
    for (var dec = -60; dec <= 60; dec += 30) {
      final path = Path();
      var started = false;
      for (var ra = 0; ra <= 360; ra += 5) {
        final pos = aitoffProject(ra.toDouble(), dec.toDouble(), size);
        if (pos == null) continue;
        if (!started) {
          path.moveTo(pos.dx, pos.dy);
          started = true;
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      canvas.drawPath(path, gridPaint);
    }

    // Tile dots — shallow first so the deepest sit on top.
    final sorted = [...coverage]
      ..sort((a, b) => a.integrationSeconds.compareTo(b.integrationSeconds));
    for (final tile in sorted) {
      final pos = aitoffProject(tile.centerRaDeg, tile.centerDecDeg, size);
      if (pos == null) continue;
      final depth = normalizedDepth(tile.integrationSeconds, maxSeconds);
      final radius = 1.6 + depth * 3.4;
      final color = Color.lerp(surface, deep, depth) ?? deep;
      canvas.drawCircle(
        pos,
        radius,
        Paint()..color = color.withValues(alpha: 0.4 + 0.6 * depth),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AitoffPainter old) =>
      old.coverage != coverage ||
      old.maxSeconds != maxSeconds ||
      old.deep != deep;
}

/// The per-tile breakdown sheet opened by tapping a point on the all-sky map.
class _TileDetailSheet extends StatelessWidget {
  final AtlasTileCoverage tile;
  final double maxSeconds;

  const _TileDetailSheet({required this.tile, required this.maxSeconds});

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    return Padding(
      padding: NightshadeTokens.cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
                decoration: NightshadeDecorations.tintedBadge(colors.primary),
                child: Icon(LucideIcons.mapPin,
                    size: NightshadeTokens.iconSm, color: colors.primary),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              Expanded(
                child: Text(
                  'Tile ${tile.tileId}',
                  style: NightshadeTypography.h5
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          _DetailLine(
            icon: LucideIcons.compass,
            label: 'Centre',
            value: formatCenter(tile.centerRaDeg, tile.centerDecDeg),
            colors: colors,
          ),
          _DetailLine(
            icon: LucideIcons.clock,
            label: 'Integration',
            value: formatIntegration(tile.integrationSeconds),
            colors: colors,
          ),
          _DetailLine(
            icon: LucideIcons.image,
            label: 'Frames',
            value: '${tile.totalFrames}',
            colors: colors,
          ),
          _DetailLine(
            icon: LucideIcons.target,
            label: 'Coverage',
            value: formatCoverageDepth(tile.coverageMean),
            colors: colors,
          ),
          if (tile.lastFoldIso != null && tile.lastFoldIso!.isNotEmpty)
            _DetailLine(
              icon: LucideIcons.history,
              label: 'Last fold',
              value: tile.lastFoldIso!.split('T').first,
              colors: colors,
              isLast: true,
            ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;
  final bool isLast;

  const _DetailLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : NightshadeTokens.spaceMd),
      child: Row(
        children: [
          Icon(icon,
              size: NightshadeTokens.iconSm, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Expanded(
            child: Text(
              label,
              style: NightshadeTypography.bodySm
                  .copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            value,
            style:
                NightshadeTypography.monoSm.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
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
