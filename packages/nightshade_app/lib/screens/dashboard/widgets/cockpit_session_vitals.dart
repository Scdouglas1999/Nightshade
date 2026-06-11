import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Cockpit "Session Vitals" panel — the live pulse of the current run.
///
/// Surfaces the two things the operator most wants at a glance while a
/// sequence is running:
///   * how *efficient* the night is (integration vs. overhead), rendered as a
///     stacked bar plus an "NN% efficient" readout, and
///   * the run *counters* (frames captured / rejected, autofocus, flips,
///     dithers, trigger fires) in a compact stat-tile row.
///
/// Reads [liveSequenceStatsProvider] (null when no run is active). Idle, it
/// collapses to a single slim row like the other cockpit panels. Never throws
/// on nulls — every readout degrades to a `—` or `0`.
class CockpitSessionVitals extends ConsumerWidget {
  const CockpitSessionVitals({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final stats = ref.watch(liveSequenceStatsProvider);

    if (stats == null) {
      return _Shell(
        colors: colors,
        child: Row(
          children: [
            Icon(LucideIcons.activity, size: 15, color: colors.textMuted),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: Text(
                'No active session — vitals appear during a run.',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize12_5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final wall = stats.wallClockSecs;
    final integration =
        stats.integrationSecs.clamp(0.0, wall <= 0 ? 0.0 : wall);
    final overhead = (wall - integration).clamp(0.0, double.infinity);
    // Efficiency is integration / wall-clock. Guard the divide so a run that
    // has only just started (wall ≈ 0) reads 0% rather than NaN.
    final efficiency = wall > 0 ? (integration / wall).clamp(0.0, 1.0) : 0.0;
    final efficiencyPct = (efficiency * 100).round();

    return _Shell(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(LucideIcons.activity, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Text(
                'SESSION VITALS',
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '$efficiencyPct% efficient',
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelStrongSm.copyWith(
                    color: efficiency >= 0.75
                        ? colors.success
                        : efficiency >= 0.5
                            ? colors.textPrimary
                            : colors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),

          // Integration vs. overhead stacked bar.
          _EfficiencyBar(
            integrationSecs: integration,
            overheadSecs: overhead,
            colors: colors,
          ),
          const SizedBox(height: NightshadeTokens.spaceXs),
          Row(
            children: [
              _legendDot(colors.primary),
              const SizedBox(width: 4),
              Text(
                'Integration ${_fmt(integration)}',
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelQuiet
                      .copyWith(color: colors.textSecondary),
                ),
              ),
              const SizedBox(width: NightshadeTokens.spaceMd),
              _legendDot(colors.textMuted),
              const SizedBox(width: 4),
              Text(
                'Overhead ${_fmt(overhead)}',
                style: NightshadeTypography.withTabular(
                  NightshadeTypography.labelQuiet
                      .copyWith(color: colors.textSecondary),
                ),
              ),
            ],
          ),

          const SizedBox(height: NightshadeTokens.spaceMd),

          // Counters row.
          Wrap(
            spacing: NightshadeTokens.spaceLg,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              _StatTile(
                colors: colors,
                icon: LucideIcons.image,
                label: 'Captured',
                value: '${stats.framesCaptured}',
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.x,
                label: 'Rejected',
                value: '${stats.framesRejected}',
                valueColor: stats.framesRejected > 0 ? colors.error : null,
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.focus,
                label: 'Autofocus',
                value: '${stats.autofocusRuns}',
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.flipHorizontal,
                label: 'Flips',
                value: '${stats.meridianFlips}',
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.move,
                label: 'Dithers',
                value: '${stats.ditherCount}',
              ),
              _StatTile(
                colors: colors,
                icon: LucideIcons.zap,
                label: 'Triggers',
                value: '${stats.triggerFires}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline2),
      ),
    );
  }
}

/// Format a seconds value as `Hh Mm` / `Mm Ss` for the efficiency legend.
String _fmt(double secs) {
  final total = secs.round();
  if (total >= 3600) {
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
  if (total >= 60) {
    final m = total ~/ 60;
    final s = total % 60;
    return s > 0 ? '${m}m ${s}s' : '${m}m';
  }
  return '${total}s';
}

/// Horizontal stacked bar: integration (primary) + overhead (muted).
class _EfficiencyBar extends StatelessWidget {
  final double integrationSecs;
  final double overheadSecs;
  final NightshadeColors colors;

  const _EfficiencyBar({
    required this.integrationSecs,
    required this.overheadSecs,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final integrationFlex = (integrationSecs * 100).round().clamp(0, 1 << 30);
    final overheadFlex = (overheadSecs * 100).round().clamp(0, 1 << 30);
    // When both are zero the bar would have no children with flex; fall back to
    // an empty muted track so the panel still reads sensibly at t≈0.
    final empty = integrationFlex == 0 && overheadFlex == 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
      child: SizedBox(
        height: 6,
        child: empty
            ? ColoredBox(color: colors.surfaceAlt)
            : Row(
                children: [
                  if (integrationFlex > 0)
                    Expanded(
                      flex: integrationFlex,
                      child: ColoredBox(color: colors.primary),
                    ),
                  if (overheadFlex > 0)
                    Expanded(
                      flex: overheadFlex,
                      child: ColoredBox(color: colors.textMuted),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Compact label-over-value stat tile with tabular figures.
class _StatTile extends StatelessWidget {
  final NightshadeColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: NightshadeTypography.fontSize9_5,
                color: colors.textMuted,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            TextStyle(
              fontSize: NightshadeTypography.fontSize15,
              fontWeight: FontWeight.w700,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Self-chromed container matching the cockpit card styling.
class _Shell extends StatelessWidget {
  final NightshadeColors colors;
  final Widget child;

  const _Shell({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg,
        vertical: NightshadeTokens.spaceMd,
      ),
      child: child,
    );
  }
}
