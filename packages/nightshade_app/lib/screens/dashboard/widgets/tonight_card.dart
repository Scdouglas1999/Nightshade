import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import 'glass_card.dart';

final _tonightOptimizationPlanProvider =
    FutureProvider.autoDispose<SessionOptimizationPlan>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  if ((settings.latitude == 0.0 && settings.longitude == 0.0)) {
    return SessionOptimizationPlan(
      generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      primaryTarget: null,
      alternates: [],
      recommendedExposureSeconds: 0,
      estimatedUsableHours: 0,
      rationale: ['Set an observing location to generate target plans.'],
      riskFactors: [],
    );
  }

  final suggestions = await ref.watch(tonightSuggestionsProvider.future);
  final optimizer = SessionOptimizerService(
    suggestionService: ref.watch(targetSuggestionServiceProvider),
  );

  return optimizer.buildPlanFromSuggestions(
    suggestions,
    generatedAt: DateTime.now(),
  );
});

class TonightCard extends ConsumerWidget {
  final NightshadeColors colors;

  const TonightCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twilight = ref.watch(twilightTimesProvider);
    final moonInfo = ref.watch(moonInfoProvider);
    final optimization =
        ref.watch(_tonightOptimizationPlanProvider).valueOrNull;

    // Use select() to only watch the time field
    final now = ref.watch(observationTimeProvider.select((s) => s.time));

    // Format astro twilight time
    String astroTwilightTime = '--:--';
    if (twilight.astronomicalDusk != null) {
      final dusk = twilight.astronomicalDusk!;
      // If dusk is in the future (relative to simulation time), show it
      if (dusk.isAfter(now)) {
        astroTwilightTime =
            '${dusk.hour.toString().padLeft(2, '0')}:${dusk.minute.toString().padLeft(2, '0')}';
      } else {
        // Dusk already passed, show dawn
        if (twilight.astronomicalDawn != null) {
          final dawn = twilight.astronomicalDawn!;
          astroTwilightTime =
              '${dawn.hour.toString().padLeft(2, '0')}:${dawn.minute.toString().padLeft(2, '0')}';
        }
      }
    }

    // Format moon info - compact version without moonrise time
    final moonValue = '${moonInfo.illumination.toStringAsFixed(0)}%';

    // Calculate imaging window (darkness duration)
    String imagingWindow = '--:--';
    if (twilight.astronomicalDusk != null &&
        twilight.astronomicalDawn != null) {
      final duration =
          twilight.astronomicalDawn!.difference(twilight.astronomicalDusk!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      imagingWindow = '${hours}h ${minutes}m';
    }

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.moon,
                  size: 16,
                  color: colors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Tonight',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _TonightRow(
            icon: LucideIcons.sunset,
            label: 'Twilight',
            value: astroTwilightTime,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.moonStar,
            label: 'Moon',
            value: moonValue,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.timer,
            label: 'Window',
            value: imagingWindow,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.target,
            label: 'Target',
            value: optimization?.primaryTarget?.targetName ?? 'Planning...',
            colors: colors,
          ),
          const SizedBox(height: 6),
          _TonightRow(
            icon: LucideIcons.camera,
            label: 'Exposure',
            value: optimization == null || !optimization.hasRecommendation
                ? '--'
                : '${optimization.recommendedExposureSeconds.toStringAsFixed(0)}s',
            colors: colors,
          ),
          if (optimization != null && optimization.rationale.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              optimization.rationale.first,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          if (optimization != null && optimization.alternates.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '+ ${optimization.alternates.length} more target${optimization.alternates.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ],
          if (optimization != null && optimization.hasRecommendation) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => context.go('/planner'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'See Full Plan',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    LucideIcons.arrowRight,
                    size: 14,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TonightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final NightshadeColors colors;

  const _TonightRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
