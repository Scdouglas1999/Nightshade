// The Tonight tab's detail column: the selected target's field, its four
// readouts, its altitude tonight, its facts, and the one pair of actions.
part of '../planner_screen.dart';

/// The 380px column beside the candidate list.
///
/// Everything on it describes the ONE selected target. The page's single
/// primary action — "Build sequence" — lives at the bottom of it (06 §Plan).
class _TargetDetailColumn extends ConsumerWidget {
  final TargetSuggestion target;
  final SessionOptimizationPlan plan;

  /// Pins the action pair to the bottom of the column. False when the column
  /// is stacked above the list on a narrow window, where there is no bottom to
  /// pin to.
  final bool bottomPinned;

  final VoidCallback onFrameIt;
  final VoidCallback onBuildSequence;

  const _TargetDetailColumn({
    required this.target,
    required this.plan,
    required this.bottomPinned,
    required this.onFrameIt,
    required this.onBuildSequence,
  });

  /// Height of the field preview at the top of the column.
  static const double _previewHeight = 150;

  /// Height of the altitude well.
  static const double _altitudeHeight = 110;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    final visibility = target.visibility;
    final minAltitude =
        ref.watch(suggestionFilterProvider).minCurrentAltitude ??
            _kPlannerDefaultMinAltitude;

    final content = <Widget>[
      SizedBox(
        height: _previewHeight,
        child: _TargetFieldPreview(target: target),
      ),
      const SizedBox(height: NightshadeTokens.spaceMd),
      Text(
        target.targetName,
        style: NightshadeTypography.pageTitle.copyWith(
          color: colors.textPrimary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        _candidateDetailLine(target),
        style: NightshadeTypography.bodySm.copyWith(
          color: colors.textSecondary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: NightshadeTokens.spaceMd),
      ReadoutRow(
        gap: NightshadeTokens.spaceMd,
        children: [
          Readout(
            value: visibility.currentAltitude.toStringAsFixed(1),
            unit: '°',
            label: l10n.text('plannerAltNow'),
          ),
          Readout(
            value: visibility.transitAltitude?.round().toString(),
            unit: '°',
            label: l10n.text('plannerColTransit'),
          ),
          Readout(
            value: _hoursAndMinutes(visibility.hoursAboveMinAlt),
            label: l10n.text('plannerWindow'),
          ),
          Readout(
            value: visibility.moonDistance.round().toString(),
            unit: '°',
            label: l10n.text('plannerFromMoon'),
          ),
        ],
      ),
      const SizedBox(height: NightshadeTokens.spaceMd),
      Container(
        height: _altitudeHeight,
        padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
        decoration: NightshadeDecorations.well(colors),
        child: AltitudeChart(
          raHours: target.raHours,
          decDegrees: target.decDegrees,
          targetName: target.targetName,
        ),
      ),
      const SizedBox(height: NightshadeTokens.spaceMd),
      KeyValueList(rows: _facts(context, ref, minAltitude)),
      if (target.warnings.isNotEmpty) ...[
        const SizedBox(height: NightshadeTokens.spaceMd),
        // ONE banner for the target's problems, not one per warning: the
        // loudest warning is the title and the rest ride on it.
        NightshadeBanner(
          title: target.warnings.first.message,
          message: target.warnings.length > 1
              ? target.warnings.skip(1).map((w) => w.message).join(' · ')
              : null,
          tone: _bannerTone(target.warnings.first.severity),
        ),
      ],
    ];

    final actions = Row(
      children: [
        Expanded(
          child: NightshadeButton(
            label: l10n.text('plannerFrameIt'),
            icon: LucideIcons.crop,
            variant: ButtonVariant.secondary,
            onPressed: onFrameIt,
          ),
        ),
        const SizedBox(width: NightshadeTokens.spaceSm),
        Expanded(
          child: NightshadeButton(
            label: l10n.text('plannerBuildSequence'),
            icon: LucideIcons.listOrdered,
            variant: ButtonVariant.primary,
            onPressed: onBuildSequence,
          ),
        ),
      ],
    );

    if (!bottomPinned) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ...content,
          const SizedBox(height: NightshadeTokens.spaceMd),
          actions,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: content,
            ),
          ),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        actions,
      ],
    );
  }

  /// The facts under the readouts. Only rows the app actually knows are
  /// listed; a row with nothing behind it is left out rather than filled with
  /// a placeholder.
  List<(String, String)> _facts(
    BuildContext context,
    WidgetRef ref,
    double minAltitude,
  ) {
    final l10n = context.l10n;
    final preview =
        ref.watch(plannerTargetIntegrationPreviewProvider(target.targetId));
    final estimated = preview.valueOrNull;
    final filters = plan.recommendedFilterNames.isNotEmpty
        ? plan.recommendedFilterNames.join('  ')
        : plan.recommendedFilterName;

    return <(String, String)>[
      if (target.objectType != null)
        (l10n.text('plannerKvObjectType'), target.objectType!),
      if (target.constellation != null)
        (l10n.text('plannerKvConstellation'), target.constellation!),
      if (target.magnitude != null)
        (
          l10n.text('plannerKvMagnitude'),
          target.magnitude!.toStringAsFixed(1),
        ),
      if (target.sizeArcmin != null && target.sizeArcmin! > 0)
        (l10n.text('plannerKvSize'), _formatSizeLabel(target.sizeArcmin)),
      if (filters != null) (l10n.text('plannerKvSuggestedFilters'), filters),
      (
        l10n.text('plannerKvExposure'),
        '${plan.recommendedExposureSeconds.round()} s',
      ),
      if (estimated != null && estimated.estimatedIntegrationHours > 0)
        (
          l10n.text(
            'plannerAboveMin',
            params: {'value': minAltitude.round().toString()},
          ),
          _hoursAndMinutes(estimated.estimatedIntegrationHours) ??
              kReadoutUnknown,
        ),
    ];
  }

  BannerTone _bannerTone(WarningSeverity severity) {
    switch (severity) {
      case WarningSeverity.critical:
        return BannerTone.error;
      case WarningSeverity.warning:
        return BannerTone.warning;
      case WarningSeverity.caution:
      case WarningSeverity.info:
        return BannerTone.info;
    }
  }
}

/// The field preview at the top of the detail column.
///
/// The mockup fills this with a decorative star field. Nightshade does not
/// have the target's sky in hand here — the HiPS surface that does lives on
/// the Framing tab and needs its own tile loader — and a synthetic star field
/// in a slot that reads as a preview would be the app claiming to show
/// something it has not fetched. So the well carries the ONE thing that IS
/// known from the numbers on this column: the target's angular extent against
/// the frame, drawn as the `primary` rectangle the mockup puts there, with the
/// action that opens the real sky.
class _TargetFieldPreview extends ConsumerWidget {
  final TargetSuggestion target;

  const _TargetFieldPreview({required this.target});

  /// The size (in arcminutes) the preview treats as filling the well. Anything
  /// larger is drawn at the full width.
  static const double _fullFrameArcmin = 90;

  /// The smallest fraction of the well the rectangle is drawn at, so a small
  /// target is still a visible mark rather than a dot.
  static const double _minFraction = 0.12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = NightshadeColors.of(context);
    final size = target.sizeArcmin;
    final fraction = size == null || size <= 0
        ? null
        : (size / _fullFrameArcmin).clamp(_minFraction, 1.0);

    return Semantics(
      label: 'Field preview for ${target.targetName}',
      child: Container(
        decoration: NightshadeDecorations.well(colors),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fraction != null)
              Center(
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  heightFactor: fraction,
                  child: DecoratedBox(
                    // The mockup softens this hairline to 80% primary; there
                    // is no 0.8 opacity token and 03 §5.1 forbids inventing
                    // one, so a 1px line takes the token colour whole.
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.primary),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: NightshadeTokens.spaceSm,
              bottom: NightshadeTokens.spaceSm,
              child: NightshadeIconButton(
                icon: LucideIcons.globe,
                tooltip: context.l10n.text('plannerOpenPlanetarium'),
                size: IconButtonSize.sm,
                onPressed: () => showTargetInSky(
                  context,
                  ref,
                  raHours: target.raHours,
                  decDegrees: target.decDegrees,
                  name: target.targetName,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
