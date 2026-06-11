import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../glass_card.dart';

/// Builds tonight's optimized target plan, guarded by a configured location.
///
/// This mirrors the provider pattern at the head of `tonight_card.dart` so the
/// briefing and the cockpit Tonight tile agree on the recommended plan. It is
/// kept private to the standby briefing; the cockpit tile owns its own copy.
final _briefingPlanProvider =
    FutureProvider.autoDispose<SessionOptimizationPlan>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  if (settings.latitude == 0.0 && settings.longitude == 0.0) {
    return SessionOptimizationPlan(
      generatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      primaryTarget: null,
      alternates: const [],
      recommendedExposureSeconds: 0,
      estimatedUsableHours: 0,
      rationale: const ['Set an observing location to generate target plans.'],
      riskFactors: const [],
    );
  }

  final suggestions = await ref.watch(tonightSuggestionsProvider.future);
  final exposureContext = suggestions.isEmpty
      ? null
      : await ref.watch(smartNightExposureContextProvider.future);
  final optimizer = SessionOptimizerService(
    suggestionService: ref.watch(targetSuggestionServiceProvider),
  );

  return optimizer.buildPlanFromSuggestions(
    suggestions,
    generatedAt: DateTime.now(),
    exposureContext: exposureContext,
  );
});

/// Tonight's recommended targets: the primary prominently, with up to three
/// compact alternates. Empty/no-location states explain themselves rather than
/// showing a blank card.
class TonightTargetsCard extends ConsumerWidget {
  final NightshadeColors colors;

  const TonightTargetsCard({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(_briefingPlanProvider);
    final plan = planAsync.valueOrNull;
    final loading = planAsync.isLoading;

    return DashboardGlassCard(
      colors: colors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DashboardCardHeader(
            colors: colors,
            icon: LucideIcons.target,
            title: "Tonight's targets",
            accent: colors.primary,
          ),
          const SizedBox(height: DashboardCardStyle.headerGap),
          if (plan == null || !plan.hasRecommendation)
            _emptyBody(context, loading)
          else
            _planBody(context, plan),
        ],
      ),
    );
  }

  Widget _emptyBody(BuildContext context, bool loading) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Planning tonight’s best targets…',
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textMuted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'No target plan yet. Set your observing location to see tonight’s '
          'best targets ranked for your sky.',
          style: NightshadeTypography.bodySm.copyWith(
            color: colors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Align(
          alignment: Alignment.centerLeft,
          child: NightshadeButton(
            label: 'Set location',
            icon: LucideIcons.mapPin,
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: () => context.go('/settings'),
          ),
        ),
      ],
    );
  }

  Widget _planBody(BuildContext context, SessionOptimizationPlan plan) {
    final primary = plan.primaryTarget!;
    final alternates = plan.alternates.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Primary target, prominent.
        Text(
          primary.targetName,
          style: NightshadeTypography.h5.copyWith(color: colors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (primary.catalogId != null) primary.catalogId!,
            if (primary.objectType != null) primary.objectType!,
          ].join(' · '),
          style: NightshadeTypography.caption.copyWith(color: colors.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Row(
          children: [
            _Stat(
              colors: colors,
              label: 'Exposure',
              value: plan.recommendedExposureSeconds > 0
                  ? '${plan.recommendedExposureSeconds.toStringAsFixed(0)}s'
                  : '--',
            ),
            const SizedBox(width: NightshadeTokens.spaceLg),
            _Stat(
              colors: colors,
              label: 'Usable',
              value: plan.estimatedUsableHours > 0
                  ? '${plan.estimatedUsableHours.toStringAsFixed(1)}h'
                  : '--',
            ),
            const SizedBox(width: NightshadeTokens.spaceLg),
            _Stat(
              colors: colors,
              label: 'Score',
              value: primary.totalScore.toStringAsFixed(0),
            ),
          ],
        ),
        if (alternates.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceMd),
          Divider(height: 1, color: colors.border),
          const SizedBox(height: NightshadeTokens.spaceSm),
          for (final alt in alternates) ...[
            _AlternateRow(colors: colors, target: alt),
            const SizedBox(height: 4),
          ],
        ],
        const SizedBox(height: NightshadeTokens.spaceMd),
        Align(
          alignment: Alignment.centerRight,
          child: NightshadeButton(
            label: 'Open planner',
            icon: LucideIcons.arrowRight,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () => context.go('/planner'),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final NightshadeColors colors;
  final String label;
  final String value;

  const _Stat({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style:
              NightshadeTypography.overline.copyWith(color: colors.textMuted),
        ),
        Text(
          value,
          style: NightshadeTypography.withTabular(
            NightshadeTypography.monoSm.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AlternateRow extends StatelessWidget {
  final NightshadeColors colors;
  final TargetSuggestion target;

  const _AlternateRow({required this.colors, required this.target});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(LucideIcons.dot, size: 16, color: colors.textMuted),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            target.catalogId ?? target.targetName,
            style: NightshadeTypography.bodySm.copyWith(
              color: colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Text(
          target.totalScore.toStringAsFixed(0),
          style: NightshadeTypography.withTabular(
            NightshadeTypography.monoXs.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}
