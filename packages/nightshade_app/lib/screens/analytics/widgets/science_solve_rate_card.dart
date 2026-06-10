import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Inline card on the Analytics Science tab that reports the plate-solve
/// success rate for the current session and offers a one-click jump to the
/// plate-solver settings page when the rate is bad.
///
/// This addresses P0.3: "plate solve is a hard prerequisite for most science
/// products, but the existing empty state never tells the user that *this*
/// session is failing — only that data is missing." Surfacing the rate plus
/// a path-forward closes that loop.
class ScienceSolveRateCard extends StatelessWidget {
  final NightshadeColors colors;

  /// All light frames captured this session (or all standalone lights when
  /// no session is active).
  final List<DbCapturedImage> lightFrames;

  const ScienceSolveRateCard({
    super.key,
    required this.colors,
    required this.lightFrames,
  });

  @override
  Widget build(BuildContext context) {
    final total = lightFrames.length;
    final solved = lightFrames.where((image) => image.isPlateSolved).length;
    final rate = total == 0 ? 0.0 : solved / total;
    final pct = (rate * 100).round();

    final _Tier tier = _classify(total: total, rate: rate);

    return NightshadeCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.crosshair, size: 15, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Plate solve health',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _StatusPill(tier: tier, colors: colors),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  total == 0 ? '—' : '$pct%',
                  style: TextStyle(
                    fontSize: NightshadeTypography.fontSize26,
                    fontWeight: FontWeight.w800,
                    color: tier.color(colors),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    total == 0
                        ? 'no light frames yet'
                        : '$solved of $total solved',
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize11,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusInline4),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : rate.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: colors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation<Color>(tier.color(colors)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tier.message(total: total),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: NightshadeTypography.fontSize11,
                height: 1.4,
              ),
            ),
            if (tier.showConfigureCta) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: NightshadeButton(
                  onPressed: () => context.push('/settings/plate-solving'),
                  label: 'Configure plate solver',
                  variant: ButtonVariant.outline,
                  size: ButtonSize.small,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static _Tier _classify({required int total, required double rate}) {
    if (total == 0) return _Tier.warmup;
    if (total < 3) return _Tier.warmup;
    if (rate >= 0.9) return _Tier.excellent;
    if (rate >= 0.6) return _Tier.acceptable;
    if (rate > 0) return _Tier.struggling;
    return _Tier.broken;
  }
}

enum _Tier {
  warmup,
  excellent,
  acceptable,
  struggling,
  broken;

  bool get showConfigureCta => this == _Tier.struggling || this == _Tier.broken;

  String get label {
    switch (this) {
      case _Tier.warmup:
        return 'Warming up';
      case _Tier.excellent:
        return 'Excellent';
      case _Tier.acceptable:
        return 'Acceptable';
      case _Tier.struggling:
        return 'Struggling';
      case _Tier.broken:
        return 'No solves yet';
    }
  }

  Color color(NightshadeColors c) {
    switch (this) {
      case _Tier.warmup:
        return c.textSecondary;
      case _Tier.excellent:
        return c.success;
      case _Tier.acceptable:
        return c.info;
      case _Tier.struggling:
        return c.warning;
      case _Tier.broken:
        return c.error;
    }
  }

  String message({required int total}) {
    switch (this) {
      case _Tier.warmup:
        return total == 0
            ? 'Solve health appears once light frames start arriving.'
            : 'A few more frames will produce a stable solve rate.';
      case _Tier.excellent:
        return 'Most frames are solving. Photometry, PSF maps, and residuals all benefit.';
      case _Tier.acceptable:
        return 'Most frames solve. Failures are usually due to clouds or transient guiding excursions.';
      case _Tier.struggling:
        return 'Many frames are failing to solve. Verify focal length, pixel scale, and that the catalog index is reachable.';
      case _Tier.broken:
        return 'No frames have solved this session — most science products will stay empty until a solver is reachable.';
    }
  }
}

class _StatusPill extends StatelessWidget {
  final _Tier tier;
  final NightshadeColors colors;

  const _StatusPill({required this.tier, required this.colors});

  @override
  Widget build(BuildContext context) {
    final c = tier.color(colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: NightshadeDecorations.statusChip(
        c,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusFull),
      ),
      child: Text(
        tier.label,
        style: TextStyle(
          fontSize: NightshadeTypography.fontSize10,
          fontWeight: FontWeight.w700,
          color: c,
        ),
      ),
    );
  }
}
