// Part of ../planner_screen.dart -- extracted for maintainability.
//
// The hero card for tonight's primary recommendation plus the auxiliary RiskFactors and Rationale lists. Public API: invoked from the Recommendation tab when an effective primary exists.
part of '../planner_screen.dart';

// ============================================================================
// Primary target card + auxiliary lists (kept from original screen)
// ============================================================================

class _PrimaryTargetCard extends ConsumerWidget {
  final TargetSuggestion target;
  final SessionOptimizationPlan plan;
  final NightshadeColors colors;
  final bool isMobile;
  final bool isOverride;
  final VoidCallback onSendToFraming;

  const _PrimaryTargetCard({
    required this.target,
    required this.plan,
    required this.colors,
    required this.isMobile,
    required this.isOverride,
    required this.onSendToFraming,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raFormatted = CoordinateUtils.formatRA(target.raHours);
    final decFormatted = CoordinateUtils.formatDec(target.decDegrees);
    final peakAlt =
        target.visibility.peakAltitude ?? target.visibility.currentAltitude;
    final hoursAbove = target.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = target.visibility.moonDistance;
    final integrationPreview =
        ref.watch(plannerTargetIntegrationPreviewProvider(target.targetId));

    final infoSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            _IntegrationEstimateChip(
              targetId: target.targetId,
              fallbackVisibleHours: hoursAbove,
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
            if (plan.recommendedFilterNames.isNotEmpty)
              _StatChip(
                icon: LucideIcons.aperture,
                label: plan.recommendedFilterNames.join(' · '),
                colors: colors,
              )
            else if (plan.recommendedFilterName != null)
              _StatChip(
                icon: LucideIcons.aperture,
                label: plan.recommendedFilterName!,
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
            if (target.sizeArcmin != null && target.sizeArcmin! > 0)
              _StatChip(
                icon: LucideIcons.ruler,
                label: _formatSizeLabel(target.sizeArcmin),
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
        integrationPreview.when(
          data: (preview) {
            if (preview == null || preview.estimatedIntegrationHours <= 0) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: NightshadeTokens.spaceMd),
              child: Row(
                children: [
                  Icon(LucideIcons.timer, size: 14, color: colors.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.text(
                      'plannerEstimatedIntegration',
                      params: {
                        'value': _formatUsableHours(
                          preview.estimatedIntegrationHours,
                        ),
                      },
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: NightshadeTokens.spaceSm,
          children: [
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.frame,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onSendToFraming,
            ),
          ],
        ),
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
    );
    final chartPanel = _CandidateAltitudePanel(
      suggestion: target,
      colors: colors,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(
          color: isOverride
              ? colors.warning.withValues(alpha: 0.5)
              : colors.primary.withValues(alpha: 0.4),
        ),
      ),
      padding: NightshadeTokens.cardPadding,
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                infoSection,
                const SizedBox(height: NightshadeTokens.spaceMd),
                chartPanel,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: infoSection),
                const SizedBox(width: NightshadeTokens.spaceLg),
                SizedBox(
                  width: 360,
                  child: chartPanel,
                ),
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
                color: colors.border,
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
