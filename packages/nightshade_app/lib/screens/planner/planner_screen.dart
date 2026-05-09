import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';

/// FutureProvider that produces tonight's optimization plan.
///
/// Returns an error to callers rather than swallowing it, because
/// "errors are a feature -- silent fallbacks hide bugs for months."
final _plannerOptimizationProvider =
    FutureProvider.autoDispose<SessionOptimizationPlan>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  if (settings.latitude == 0.0 && settings.longitude == 0.0) {
    throw StateError(
      'Observing location is not configured. '
      'Set your latitude and longitude in Settings before using the planner.',
    );
  }

  final suggestions = await ref.watch(tonightSuggestionsProvider.future);
  final optimizer = ref.watch(sessionOptimizerServiceProvider);

  return optimizer.buildPlanFromSuggestions(
    suggestions,
    generatedAt: DateTime.now(),
  );
});

/// Full "Plan Tonight" screen.
///
/// Shows the session optimizer's primary recommendation, alternate targets,
/// risk factors, and a button to push the recommendation into the sequencer.
class PlannerScreen extends ConsumerStatefulWidget {
  const PlannerScreen({super.key});

  @override
  ConsumerState<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends ConsumerState<PlannerScreen> {
  /// Index into the alternates list of the user-selected override, or null
  /// to use the optimizer's primary pick.
  int? _selectedAlternateIndex;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final planAsync = ref.watch(_plannerOptimizationProvider);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          _PlannerHeader(colors: colors),
          Expanded(
            child: planAsync.when(
              data: (plan) => _buildPlanContent(context, colors, plan),
              loading: () => _buildLoadingState(colors),
              error: (error, _) => _buildErrorState(context, colors, error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanContent(
    BuildContext context,
    NightshadeColors colors,
    SessionOptimizationPlan plan,
  ) {
    final l10n = context.l10n;

    if (!plan.hasRecommendation) {
      return _buildEmptyState(colors, plan);
    }

    // The "effective" primary is either the optimizer pick or the user override.
    final TargetSuggestion effectivePrimary;
    if (_selectedAlternateIndex != null &&
        _selectedAlternateIndex! < plan.alternates.length) {
      effectivePrimary = plan.alternates[_selectedAlternateIndex!];
    } else {
      effectivePrimary = plan.primaryTarget!;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile =
            constraints.maxWidth < NightshadeTokens.breakpointTablet;

        return SingleChildScrollView(
          padding: isMobile
              ? NightshadeTokens.screenPaddingCompact
              : NightshadeTokens.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary target card
              _PrimaryTargetCard(
                target: effectivePrimary,
                plan: plan,
                colors: colors,
                isOverride: _selectedAlternateIndex != null,
              ),

              const SizedBox(height: NightshadeTokens.spaceLg),

              // Review in Sequencer button
              SizedBox(
                width: double.infinity,
                child: NightshadeButton(
                  label: l10n.text('plannerReviewInSequencer'),
                  icon: LucideIcons.listOrdered,
                  variant: ButtonVariant.primary,
                  onPressed: () =>
                      _createSequence(context, colors, effectivePrimary, plan),
                ),
              ),
              const SizedBox(height: NightshadeTokens.spaceSm),
              Text(
                l10n.text('plannerReviewHint'),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),

              // Alternate targets
              if (plan.alternates.isNotEmpty) ...[
                const SizedBox(height: NightshadeTokens.space2xl),
                _SectionHeader(
                  title: l10n.text('plannerAlternateTargets'),
                  subtitle: l10n.text(
                    'plannerAlternateTargetsSubtitle',
                    params: {
                      'count': plan.alternates.length.toString(),
                      'suffix': plan.alternates.length == 1 ? '' : 's',
                    },
                  ),
                  colors: colors,
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                ..._buildAlternateCards(colors, plan),
              ],

              // Risk factors
              if (plan.riskFactors.isNotEmpty) ...[
                const SizedBox(height: NightshadeTokens.space2xl),
                _SectionHeader(
                  title: l10n.text('plannerRiskFactors'),
                  subtitle: l10n.text('plannerRiskFactorsSubtitle'),
                  colors: colors,
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                _RiskFactorsList(riskFactors: plan.riskFactors, colors: colors),
              ],

              // Rationale
              if (plan.rationale.isNotEmpty) ...[
                const SizedBox(height: NightshadeTokens.space2xl),
                _SectionHeader(
                  title: l10n.text('plannerRationale'),
                  subtitle: l10n.text('plannerRationaleSubtitle'),
                  colors: colors,
                ),
                const SizedBox(height: NightshadeTokens.spaceMd),
                _RationaleList(rationale: plan.rationale, colors: colors),
              ],

              const SizedBox(height: NightshadeTokens.space2xl),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildAlternateCards(
      NightshadeColors colors, SessionOptimizationPlan plan) {
    return [
      for (int i = 0; i < plan.alternates.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
          child: _AlternateTargetCard(
            target: plan.alternates[i],
            isSelected: _selectedAlternateIndex == i,
            colors: colors,
            onSelect: () {
              setState(() {
                if (_selectedAlternateIndex == i) {
                  // Deselect to go back to optimizer's primary
                  _selectedAlternateIndex = null;
                } else {
                  _selectedAlternateIndex = i;
                }
              });
            },
          ),
        ),
    ];
  }

  void _createSequence(
    BuildContext context,
    NightshadeColors colors,
    TargetSuggestion target,
    SessionOptimizationPlan plan,
  ) {
    final sequenceNotifier = ref.read(currentSequenceProvider.notifier);
    final targetNode = TargetHeaderNode(
      targetName: target.targetName,
      raHours: target.raHours,
      decDegrees: target.decDegrees,
    );
    final estimatedFrames =
        (plan.estimatedUsableHours * 3600 / plan.recommendedExposureSeconds)
            .floor()
            .clamp(1, 999);
    final exposureNode = ExposureNode(
      durationSecs: plan.recommendedExposureSeconds,
      count: estimatedFrames,
      frameType: FrameType.light,
    );

    sequenceNotifier.createSequence(name: '${target.targetName} Plan');
    sequenceNotifier.addTargetHeader(targetNode);
    sequenceNotifier.addNode(exposureNode, parentId: targetNode.id);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.text(
            'plannerDraftCreated',
            params: {
              'target': target.targetName,
              'exposure': plan.recommendedExposureSeconds.toStringAsFixed(0),
            },
          ),
        ),
        backgroundColor: colors.success,
      ),
    );

    // Navigate to sequencer so the user can finish configuring
    context.go('/sequencer');
  }

  Widget _buildLoadingState(NightshadeColors colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: NightshadeTokens.spaceLg),
          Text(
            context.l10n.text('plannerLoading'),
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    NightshadeColors colors,
    Object error,
  ) {
    final isLocationError = error is StateError;

    return Center(
      child: Padding(
        padding: NightshadeTokens.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLocationError ? LucideIcons.mapPin : LucideIcons.alertCircle,
              size: NightshadeTokens.icon2xl,
              color: isLocationError ? colors.warning : colors.error,
            ),
            const SizedBox(height: NightshadeTokens.spaceLg),
            Text(
              isLocationError
                  ? context.l10n.text('plannerLocationMissingTitle')
                  : context.l10n.text('plannerPlanFailedTitle'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Text(
              isLocationError
                  ? context.l10n.text('plannerLocationMissingBody')
                  : context.l10n.text('plannerPlanFailedBody'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: NightshadeTokens.spaceXl),
            if (isLocationError)
              NightshadeButton(
                label: context.l10n.text('plannerOpenSettings'),
                icon: LucideIcons.settings,
                onPressed: () => context.go('/settings'),
              )
            else
              NightshadeButton(
                label: context.l10n.text('plannerRetry'),
                icon: LucideIcons.refreshCw,
                onPressed: () => ref.invalidate(_plannerOptimizationProvider),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
      NightshadeColors colors, SessionOptimizationPlan plan) {
    final l10n = context.l10n;
    final config = ref.watch(targetSuggestionConfigProvider);
    final preferredTypes = config.preferredObjectTypes.isEmpty
        ? l10n.text('plannerConstraintTypesAny')
        : config.preferredObjectTypes.join(', ');
    final moonConstraint = config.maxMoonDistance == null
        ? l10n.text('plannerConstraintMoonAny')
        : l10n.text(
            'plannerConstraintMoon',
            params: {'value': config.maxMoonDistance!.toStringAsFixed(0)},
          );
    final rationale = plan.rationale.isEmpty
        ? [l10n.text('plannerNoTargetsBody')]
        : plan.rationale;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: NightshadeTokens.screenPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Container(
                  padding: const EdgeInsets.all(NightshadeTokens.space2xl),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: NightshadeTokens.borderRadiusLg,
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        LucideIcons.moonStar,
                        size: NightshadeTokens.icon2xl,
                        color: colors.warning,
                      ),
                      const SizedBox(height: NightshadeTokens.spaceLg),
                      Text(
                        l10n.text('plannerNoTargetsTitle'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: NightshadeTokens.spaceSm),
                      Text(
                        l10n.text('plannerNoTargetsBody'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: NightshadeTokens.spaceLg),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: NightshadeTokens.spaceSm,
                        runSpacing: NightshadeTokens.spaceSm,
                        children: [
                          _PlannerConstraintChip(
                            icon: LucideIcons.mountain,
                            label: l10n.text(
                              'plannerConstraintAltitude',
                              params: {
                                'value': config.minAltitude.toStringAsFixed(0),
                              },
                            ),
                            colors: colors,
                          ),
                          _PlannerConstraintChip(
                            icon: LucideIcons.lineChart,
                            label: l10n.text(
                              'plannerConstraintScore',
                              params: {
                                'value': config.minScore.toStringAsFixed(0),
                              },
                            ),
                            colors: colors,
                          ),
                          _PlannerConstraintChip(
                            icon: LucideIcons.moon,
                            label: moonConstraint,
                            colors: colors,
                          ),
                          _PlannerConstraintChip(
                            icon: LucideIcons.sparkles,
                            label: l10n.text(
                              'plannerConstraintTypes',
                              params: {'value': preferredTypes},
                            ),
                            colors: colors,
                          ),
                        ],
                      ),
                      const SizedBox(height: NightshadeTokens.spaceXl),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.text('plannerTryThis'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: NightshadeTokens.spaceSm),
                      for (final line in rationale.take(3))
                        _PlannerEmptyHint(
                          text: line,
                          colors: colors,
                        ),
                      _PlannerEmptyHint(
                        text: l10n.text('plannerTryPlanetarium'),
                        colors: colors,
                      ),
                      _PlannerEmptyHint(
                        text: l10n.text('plannerTryFraming'),
                        colors: colors,
                      ),
                      const SizedBox(height: NightshadeTokens.spaceXl),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: NightshadeTokens.spaceSm,
                        runSpacing: NightshadeTokens.spaceSm,
                        children: [
                          NightshadeButton(
                            label: l10n.text('plannerOpenPlanetarium'),
                            icon: LucideIcons.star,
                            onPressed: () => context.go('/planetarium'),
                          ),
                          NightshadeButton(
                            label: l10n.text('plannerOpenFraming'),
                            icon: LucideIcons.crop,
                            variant: ButtonVariant.outline,
                            onPressed: () => context.go('/framing'),
                          ),
                          NightshadeButton(
                            label: l10n.text('plannerOpenSettings'),
                            icon: LucideIcons.settings,
                            variant: ButtonVariant.outline,
                            onPressed: () => context.go('/settings'),
                          ),
                          NightshadeButton(
                            label: l10n.text('plannerRetry'),
                            icon: LucideIcons.refreshCw,
                            variant: ButtonVariant.ghost,
                            onPressed: () =>
                                ref.invalidate(_plannerOptimizationProvider),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlannerConstraintChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;

  const _PlannerConstraintChip({
    required this.icon,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd,
        vertical: NightshadeTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusSm,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.textSecondary),
          const SizedBox(width: NightshadeTokens.spaceXs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlannerEmptyHint extends StatelessWidget {
  final String text;
  final NightshadeColors colors;

  const _PlannerEmptyHint({
    required this.text,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.checkCircle2,
            size: 14,
            color: colors.info,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _PlannerHeader extends StatelessWidget {
  final NightshadeColors colors;

  const _PlannerHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: NightshadeTokens.appBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: NightshadeTokens.spaceLg),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.moonStar, size: 20, color: colors.primary),
          const SizedBox(width: NightshadeTokens.spaceMd),
          Text(
            context.l10n.text('plannerTitle'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final NightshadeColors colors;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: colors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// The main card showing the primary (or overridden) target with full detail.
class _PrimaryTargetCard extends StatelessWidget {
  final TargetSuggestion target;
  final SessionOptimizationPlan plan;
  final NightshadeColors colors;
  final bool isOverride;

  const _PrimaryTargetCard({
    required this.target,
    required this.plan,
    required this.colors,
    required this.isOverride,
  });

  @override
  Widget build(BuildContext context) {
    final raFormatted = CoordinateUtils.formatRA(target.raHours);
    final decFormatted = CoordinateUtils.formatDec(target.decDegrees);
    final peakAlt =
        target.visibility.peakAltitude ?? target.visibility.currentAltitude;
    final hoursAbove = target.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = target.visibility.moonDistance;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(
          color: isOverride
              ? colors.warning.withValues(alpha: 0.5)
              : colors.primary.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: (isOverride ? colors.warning : colors.primary)
                .withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: NightshadeTokens.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: name + score badge
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isOverride)
                      Padding(
                        padding: const EdgeInsets.only(
                            bottom: NightshadeTokens.spaceXs),
                        child: Text(
                          context.l10n.text('plannerUserOverride'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.warning,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    Text(
                      target.targetName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (target.catalogId != null &&
                        target.catalogId != target.targetName)
                      Text(
                        target.catalogId!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              _ScoreBadge(score: target.totalScore, colors: colors),
            ],
          ),

          const SizedBox(height: NightshadeTokens.spaceMd),

          // Coordinates
          Row(
            children: [
              Icon(LucideIcons.locate, size: 14, color: colors.textMuted),
              const SizedBox(width: 6),
              Text(
                '$raFormatted  /  $decFormatted',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),

          const SizedBox(height: NightshadeTokens.spaceMd),

          // Stats grid
          Wrap(
            spacing: NightshadeTokens.spaceMd,
            runSpacing: NightshadeTokens.spaceSm,
            children: [
              if (target.objectType != null)
                _StatChip(
                  icon: LucideIcons.shapes,
                  label: target.objectType!,
                  colors: colors,
                ),
              _StatChip(
                icon: LucideIcons.arrowUp,
                label: context.l10n.text(
                  'plannerPeak',
                  params: {'value': peakAlt.toStringAsFixed(1)},
                ),
                colors: colors,
              ),
              _StatChip(
                icon: LucideIcons.clock,
                label: context.l10n.text(
                  'plannerVisible',
                  params: {'value': hoursAbove.toStringAsFixed(1)},
                ),
                colors: colors,
              ),
              _StatChip(
                icon: LucideIcons.moon,
                label: context.l10n.text(
                  'plannerMoon',
                  params: {'value': moonDist.toStringAsFixed(0)},
                ),
                colors: colors,
                isWarning: moonDist < 45,
              ),
              _StatChip(
                icon: LucideIcons.camera,
                label: context.l10n.text(
                  'plannerExposure',
                  params: {
                    'value': plan.recommendedExposureSeconds.toStringAsFixed(0),
                  },
                ),
                colors: colors,
              ),
              if (target.magnitude != null)
                _StatChip(
                  icon: LucideIcons.sparkles,
                  label: context.l10n.text(
                    'plannerMagnitude',
                    params: {'value': target.magnitude!.toStringAsFixed(1)},
                  ),
                  colors: colors,
                ),
              if (target.sizeArcmin != null)
                _StatChip(
                  icon: LucideIcons.maximize2,
                  label: "${target.sizeArcmin!.toStringAsFixed(1)}'",
                  colors: colors,
                ),
              if (target.constellation != null)
                _StatChip(
                  icon: LucideIcons.star,
                  label: target.constellation!,
                  colors: colors,
                ),
            ],
          ),

          // Data progress bar
          if (target.dataProgress > 0) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            _DataProgressBar(progress: target.dataProgress, colors: colors),
          ],

          // Estimated integration
          if (plan.estimatedUsableHours > 0) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Row(
              children: [
                Icon(LucideIcons.timer, size: 14, color: colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  context.l10n.text(
                    'plannerEstimatedIntegration',
                    params: {
                      'value': _formatUsableHours(plan.estimatedUsableHours),
                    },
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],

          // Tags
          if (target.tags.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final tag in target.tags)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ],

          // Warnings
          if (target.warnings.isNotEmpty) ...[
            const SizedBox(height: NightshadeTokens.spaceMd),
            for (final warning in target.warnings.take(3))
              Padding(
                padding:
                    const EdgeInsets.only(bottom: NightshadeTokens.spaceXs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      LucideIcons.alertTriangle,
                      size: 14,
                      color: _warningColor(warning.severity, colors),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        warning.message,
                        style: TextStyle(
                          fontSize: 12,
                          color: _warningColor(warning.severity, colors),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatUsableHours(double hours) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  Color _warningColor(WarningSeverity severity, NightshadeColors colors) {
    switch (severity) {
      case WarningSeverity.critical:
        return colors.error;
      case WarningSeverity.warning:
        return colors.warning;
      case WarningSeverity.caution:
        return colors.textSecondary;
      case WarningSeverity.info:
        return colors.textMuted;
    }
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;
  final NightshadeColors colors;

  const _ScoreBadge({required this.score, required this.colors});

  @override
  Widget build(BuildContext context) {
    final Color badgeColor;
    if (score >= 75) {
      badgeColor = colors.success;
    } else if (score >= 50) {
      badgeColor = colors.warning;
    } else {
      badgeColor = colors.error;
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: badgeColor.withValues(alpha: 0.15),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: Text(
          score.toStringAsFixed(0),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: badgeColor,
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final NightshadeColors colors;
  final bool isWarning;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.colors,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = isWarning ? colors.warning : colors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isWarning ? colors.warning : colors.surfaceAlt)
            .withValues(alpha: isWarning ? 0.1 : 1.0),
        borderRadius: BorderRadius.circular(6),
        border: isWarning
            ? Border.all(color: colors.warning.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: chipColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: chipColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataProgressBar extends StatelessWidget {
  final double progress;
  final NightshadeColors colors;

  const _DataProgressBar({
    required this.progress,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Data Collected',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: colors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress > 0.85 ? colors.success : colors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Card for an alternate target.
class _AlternateTargetCard extends StatelessWidget {
  final TargetSuggestion target;
  final bool isSelected;
  final NightshadeColors colors;
  final VoidCallback onSelect;

  const _AlternateTargetCard({
    required this.target,
    required this.isSelected,
    required this.colors,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final peakAlt =
        target.visibility.peakAltitude ?? target.visibility.currentAltitude;
    final hoursAbove = target.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = target.visibility.moonDistance;

    return GestureDetector(
      onTap: onSelect,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.warning.withValues(alpha: 0.05)
              : colors.surface,
          borderRadius: NightshadeTokens.borderRadiusLg,
          border: Border.all(
            color: isSelected
                ? colors.warning.withValues(alpha: 0.5)
                : colors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        padding: NightshadeTokens.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.targetName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (target.objectType != null)
                        Text(
                          target.objectType!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                _ScoreBadge(score: target.totalScore, colors: colors),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Wrap(
              spacing: NightshadeTokens.spaceSm,
              runSpacing: 4,
              children: [
                _StatChip(
                  icon: LucideIcons.arrowUp,
                  label: context.l10n.text(
                    'plannerPeak',
                    params: {'value': peakAlt.toStringAsFixed(1)},
                  ),
                  colors: colors,
                ),
                _StatChip(
                  icon: LucideIcons.clock,
                  label: context.l10n.text(
                    'plannerVisible',
                    params: {'value': hoursAbove.toStringAsFixed(1)},
                  ),
                  colors: colors,
                ),
                _StatChip(
                  icon: LucideIcons.moon,
                  label: context.l10n.text(
                    'plannerMoon',
                    params: {'value': moonDist.toStringAsFixed(0)},
                  ),
                  colors: colors,
                  isWarning: moonDist < 45,
                ),
              ],
            ),
            const SizedBox(height: NightshadeTokens.spaceSm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    target.reasoning,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: NightshadeTokens.spaceMd),
                NightshadeButton(
                  label: isSelected
                      ? context.l10n.text('plannerSelected')
                      : context.l10n.text('plannerSelect'),
                  variant: isSelected
                      ? ButtonVariant.primary
                      : ButtonVariant.outline,
                  size: ButtonSize.small,
                  onPressed: onSelect,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskFactorsList extends StatelessWidget {
  final List<String> riskFactors;
  final NightshadeColors colors;

  const _RiskFactorsList({
    required this.riskFactors,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.05),
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.warning.withValues(alpha: 0.2)),
      ),
      padding: NightshadeTokens.cardPadding,
      child: Column(
        children: [
          for (int i = 0; i < riskFactors.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.alertTriangle,
                      size: 14, color: colors.warning),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    riskFactors[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (i < riskFactors.length - 1)
              Divider(
                color: colors.warning.withValues(alpha: 0.1),
                height: NightshadeTokens.spaceLg,
              ),
          ],
        ],
      ),
    );
  }
}

class _RationaleList extends StatelessWidget {
  final List<String> rationale;
  final NightshadeColors colors;

  const _RationaleList({
    required this.rationale,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      padding: NightshadeTokens.cardPadding,
      child: Column(
        children: [
          for (int i = 0; i < rationale.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(LucideIcons.lightbulb,
                      size: 14, color: colors.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rationale[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            if (i < rationale.length - 1)
              Divider(
                color: colors.border,
                height: NightshadeTokens.spaceLg,
              ),
          ],
        ],
      ),
    );
  }
}
