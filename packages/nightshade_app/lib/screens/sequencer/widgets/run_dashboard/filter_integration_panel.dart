import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'run_dashboard_format.dart';
import 'run_dashboard_providers.dart';

/// Horizontal "L: 2h12m / 3h | R: 45m / 1h | ..." progress card showing
/// accumulated integration per filter for the active session compared to
/// the goal totals computed from the loaded sequence's exposure nodes.
///
/// Genuinely new: there is no existing per-filter session totals widget
/// elsewhere in the app, so this is built from scratch using the
/// `runDashboardFilterTotalsProvider` aggregator.
class RunDashboardFilterIntegration extends ConsumerWidget {
  const RunDashboardFilterIntegration({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final totals = ref.watch(runDashboardFilterTotalsProvider);

    // Pick a stable filter ordering: a common L/R/G/B/Ha/OIII/SII first,
    // then any additional filters in alphabetic order.
    const preferred = ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'];
    final filterNames = <String>{
      ...totals.goalSecs.keys,
      ...totals.integrationSecs.keys,
    }.toList();
    filterNames.sort((a, b) {
      final ia = preferred.indexOf(a);
      final ib = preferred.indexOf(b);
      if (ia == ib) return a.compareTo(b);
      if (ia == -1) return 1;
      if (ib == -1) return -1;
      return ia.compareTo(ib);
    });

    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.barChart3, size: 14, color: colors.primary),
              const SizedBox(width: NightshadeTokens.spaceSm),
              Expanded(
                child: Text(
                  'PER-FILTER INTEGRATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: colors.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: NightshadeTokens.spaceMd),
          if (filterNames.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: NightshadeTokens.spaceMd),
              child: Text(
                'No exposures configured.',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textMuted,
                ),
              ),
            )
          else
            ...[
              for (final f in filterNames) ...[
                _FilterRow(
                  colors: colors,
                  name: f,
                  acquired: totals.integrationSecs[f] ?? 0.0,
                  goal: totals.goalSecs[f] ?? 0.0,
                ),
                if (f != filterNames.last)
                  const SizedBox(height: NightshadeTokens.spaceSm),
              ],
            ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final NightshadeColors colors;
  final String name;
  final double acquired;
  final double goal;

  const _FilterRow({
    required this.colors,
    required this.name,
    required this.acquired,
    required this.goal,
  });

  Color _bandColor(String f, NightshadeColors c) {
    switch (f.toLowerCase()) {
      case 'l':
      case 'lum':
      case 'luminance':
        return c.textPrimary;
      case 'r':
      case 'red':
        return c.error;
      case 'g':
      case 'green':
        return c.success;
      case 'b':
      case 'blue':
        return c.info;
      case 'ha':
      case 'h-alpha':
        return const Color(0xFFEF4444);
      case 'oiii':
        return const Color(0xFF06B6D4);
      case 'sii':
        return const Color(0xFFF59E0B);
      default:
        return c.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _bandColor(name, colors);
    final fraction =
        goal > 0 ? (acquired / goal).clamp(0.0, 1.0) : 0.0;
    final acquiredStr = formatSeconds(acquired);
    final goalStr = goal > 0 ? formatSeconds(goal) : '—';

    // Narrow column? Render the goal/acquired pair on a second line so
    // the row doesn't overflow when the column is squeezed (the audit
    // flagged this rendering on a 280px-wide test viewport).
    return LayoutBuilder(builder: (context, constraints) {
      final stacked = constraints.maxWidth < 220;
      final amountText = Text(
        goal > 0 ? '$acquiredStr / $goalStr' : acquiredStr,
        textAlign: stacked ? TextAlign.left : TextAlign.right,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: colors.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        overflow: TextOverflow.ellipsis,
      );

      final swatch = Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusXs),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(
          name.length > 3 ? name.substring(0, 3) : name,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );

      final bar = Stack(
        children: [
          Container(
            height: 12,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius:
                  BorderRadius.circular(NightshadeTokens.radiusXs),
            ),
          ),
          FractionallySizedBox(
            widthFactor: fraction,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusXs),
              ),
            ),
          ),
        ],
      );

      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                swatch,
                const SizedBox(width: NightshadeTokens.spaceSm),
                Expanded(child: amountText),
              ],
            ),
            const SizedBox(height: 4),
            bar,
          ],
        );
      }

      return Row(
        children: [
          swatch,
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(child: bar),
          const SizedBox(width: NightshadeTokens.spaceSm),
          // Flexible (not SizedBox) so a too-wide label can shrink
          // gracefully and not push the bar off-screen.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 60, maxWidth: 110),
              child: amountText,
            ),
          ),
        ],
      );
    });
  }
}
