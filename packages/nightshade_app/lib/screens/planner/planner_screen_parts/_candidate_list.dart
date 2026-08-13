// Part of ../planner_screen.dart -- extracted for maintainability.
//
// Candidate list with cursor-driven pagination, the per-target row (info + altitude panel), score/integration/stat chips, and the skeleton placeholder used while suggestions are loading.
part of '../planner_screen.dart';

// ============================================================================
// Candidate list with pagination
// ============================================================================

class _CandidateList extends ConsumerWidget {
  final List<TargetSuggestion> candidates;
  final NightshadeColors colors;
  final bool isMobile;

  const _CandidateList({
    required this.candidates,
    required this.colors,
    required this.isMobile,
  });

  /// How many candidate cards to put side by side.
  ///
  /// A candidate card needs roughly 1000-1150px to be comfortable: ~610px of
  /// intrinsic info content (name, chip row, one-line rationale, four buttons)
  /// plus the altitude panel, which `clampPanelWidth` caps at 380px. Every
  /// pixel beyond that used to become dead space in the middle of the card —
  /// ~1240px (54% of the card) on a 2560px window, growing linearly with the
  /// window — while only three of 1200+ candidates fit on screen. Splitting
  /// into columns spends the extra width on MORE candidates instead of more
  /// void.
  static int _columnsFor(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) return 1;
    // Capped at 4: this workstation's maximised window is 5120px wide, where a
    // single column left ~74% of every card empty.
    final columns = (availableWidth / 1150).round();
    return columns.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibleCount =
        ref.watch(_plannerVisibleCountProvider).clamp(0, candidates.length);
    final visible = candidates.take(visibleCount).toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = isMobile ? 1 : _columnsFor(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (columns == 1)
              for (final candidate in visible)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
                  child: _CandidateRow(
                    key: ValueKey('candidate-${candidate.targetId}'),
                    suggestion: candidate,
                    colors: colors,
                    isMobile: isMobile,
                  ),
                )
            else
              for (var start = 0; start < visible.length; start += columns)
                Padding(
                  padding:
                      const EdgeInsets.only(bottom: NightshadeTokens.spaceMd),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0)
                          const SizedBox(width: NightshadeTokens.spaceMd),
                        Expanded(
                          child: start + column < visible.length
                              ? _CandidateRow(
                                  key: ValueKey(
                                    'candidate-${visible[start + column].targetId}',
                                  ),
                                  suggestion: visible[start + column],
                                  colors: colors,
                                  isMobile: isMobile,
                                )
                              // Keeps the last row's cards the same width as
                              // every other row's instead of stretching one
                              // card across the full width.
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
            if (visibleCount < candidates.length)
              Padding(
                padding: const EdgeInsets.only(top: NightshadeTokens.spaceSm),
                child: Align(
                  alignment: Alignment.center,
                  child: NightshadeButton(
                    label: 'Load more '
                        '(${candidates.length - visibleCount} remaining)',
                    icon: LucideIcons.chevronDown,
                    variant: ButtonVariant.outline,
                    size: ButtonSize.small,
                    onPressed: () {
                      final next = (visibleCount + _kPlannerPageSize)
                          .clamp(0, candidates.length);
                      ref.read(_plannerVisibleCountProvider.notifier).state =
                          next;
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Target metadata and actions for a planner candidate card.
class _CandidateRowInfo extends ConsumerWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;
  final VoidCallback onReviewInSequencer;
  final VoidCallback onSendToFraming;
  final VoidCallback onShowInSky;
  final VoidCallback onAddToObservingList;

  const _CandidateRowInfo({
    required this.suggestion,
    required this.colors,
    required this.onReviewInSequencer,
    required this.onSendToFraming,
    required this.onShowInSky,
    required this.onAddToObservingList,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peakAlt = suggestion.visibility.peakAltitude ??
        suggestion.visibility.currentAltitude;
    final hoursAbove = suggestion.visibility.hoursAboveMinAlt ?? 0.0;
    final moonDist = suggestion.visibility.moonDistance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    suggestion.targetName,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (suggestion.catalogId != null &&
                      suggestion.catalogId != suggestion.targetName)
                    Text(
                      suggestion.catalogId!,
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize12,
                        color: colors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            _ScoreBadge(score: suggestion.totalScore, colors: colors),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: 4,
          children: [
            if (suggestion.objectType != null)
              _StatChip(
                icon: LucideIcons.shapes,
                label: suggestion.objectType!,
                colors: colors,
              ),
            _StatChip(
              icon: LucideIcons.arrowUp,
              // Same l10n string as the hero card so the two never drift, and
              // the label says WHICH peak this is: the chart's "Transit alt"
              // is a different (also correct) number.
              label: context.l10n.text(
                'plannerPeak',
                params: {'value': peakAlt.toStringAsFixed(0)},
              ),
              colors: colors,
              tooltip:
                  'Highest altitude this target reaches while the sky is astronomically '
                  'dark tonight. The altitude chart\'s "Transit alt" is the '
                  'altitude at culmination, which may fall in daylight.',
            ),
            _IntegrationEstimateChip(
              targetId: suggestion.targetId,
              fallbackVisibleHours: hoursAbove,
              colors: colors,
            ),
            _StatChip(
              icon: LucideIcons.moon,
              label: 'Moon ${moonDist.toStringAsFixed(0)}°',
              colors: colors,
              isWarning: moonDist < 45,
            ),
            if (suggestion.magnitude != null)
              _StatChip(
                icon: LucideIcons.sparkles,
                label: 'Mag ${suggestion.magnitude!.toStringAsFixed(1)}',
                colors: colors,
              ),
            // Why major-axis only: the DB Target schema does not store a
            // minor axis, so plumbing one through from OpenNGC would touch
            // out-of-scope files for this branch.
            if (suggestion.sizeArcmin != null && suggestion.sizeArcmin! > 0)
              _StatChip(
                icon: LucideIcons.ruler,
                label: _formatSizeLabel(suggestion.sizeArcmin),
                colors: colors,
              ),
            if (suggestion.constellation != null)
              _StatChip(
                icon: LucideIcons.star,
                label: suggestion.constellation!,
                colors: colors,
              ),
          ],
        ),
        if (suggestion.reasoning.isNotEmpty) ...[
          const SizedBox(height: NightshadeTokens.spaceSm),
          Text(
            suggestion.reasoning,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: NightshadeTypography.fontSize12,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: NightshadeTokens.spaceMd),
        Wrap(
          spacing: NightshadeTokens.spaceSm,
          runSpacing: NightshadeTokens.spaceSm,
          children: [
            NightshadeButton(
              label: context.l10n.text('plannerReviewInSequencer'),
              icon: LucideIcons.listOrdered,
              variant: ButtonVariant.primary,
              size: ButtonSize.small,
              onPressed: onReviewInSequencer,
            ),
            NightshadeButton(
              label: 'Send to Framing',
              icon: LucideIcons.frame,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onSendToFraming,
            ),
            NightshadeButton(
              label: 'Add to observing list',
              icon: LucideIcons.listPlus,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onAddToObservingList,
            ),
            // Appended, not inserted: the three existing actions keep their
            // familiar positions (and their reach in a short viewport).
            NightshadeButton(
              label: context.l10n.text('plannerOpenPlanetarium'),
              icon: LucideIcons.globe,
              variant: ButtonVariant.outline,
              size: ButtonSize.small,
              onPressed: onShowInSky,
            ),
          ],
        ),
      ],
    );
  }
}

/// Altitude visibility chart shown beside (or below on narrow) candidate info.
class _CandidateAltitudePanel extends StatelessWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;

  const _CandidateAltitudePanel({
    required this.suggestion,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return NightshadeCard(
      padding: const EdgeInsets.all(NightshadeTokens.spaceSm),
      child: AltitudeChart(
        raHours: suggestion.raHours,
        decDegrees: suggestion.decDegrees,
        targetName: suggestion.targetName,
      ),
    );
  }
}

class _CandidateRow extends ConsumerWidget {
  final TargetSuggestion suggestion;
  final NightshadeColors colors;
  final bool isMobile;

  const _CandidateRow({
    super.key,
    required this.suggestion,
    required this.colors,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infoSection = _CandidateRowInfo(
      suggestion: suggestion,
      colors: colors,
      onReviewInSequencer: () => _reviewInSequencer(context, ref),
      onSendToFraming: () => _sendToFraming(context, ref),
      onShowInSky: () => _showInSky(context, ref),
      onAddToObservingList: () => _addToObservingList(context, ref),
    );
    final chartPanel = _CandidateAltitudePanel(
      suggestion: suggestion,
      colors: colors,
    );

    return NightshadeCard(
      variant: CardVariant.subtle,
      borderRadius: NightshadeTokens.radiusLg,
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final panelWidth = clampPanelWidth(
                  constraints.maxWidth,
                  fraction: 0.32,
                  min: 300,
                  max: 380,
                );
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: infoSection),
                    const SizedBox(width: NightshadeTokens.spaceLg),
                    SizedBox(
                      width: panelWidth,
                      child: chartPanel,
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Build a Smart Night sequence for this single candidate and load it into
  /// the editor, replacing the current draft (mirrors the primary card's
  /// "Review in Sequencer"). The helper surfaces any
  /// [SmartNightBuildException] via snackbar and returns false; we only act on
  /// a true result.
  Future<void> _reviewInSequencer(BuildContext context, WidgetRef ref) async {
    final loaded = await addPlanTonightTargetToSequencer(
      context: context,
      ref: ref,
      target: suggestion,
      replaceSequence: true,
      includeSessionPreamble: true,
    );
    if (!loaded || !context.mounted) return;

    final colorsLocal = NightshadeColors.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Loaded ${suggestion.targetName} into the sequencer'),
        backgroundColor: colorsLocal.success,
      ),
    );
    context.go('/sequencer');
  }

  void _sendToFraming(BuildContext context, WidgetRef ref) {
    ref.read(framingProvider.notifier).setTargetSuggestion(suggestion);
    context.goNamed('framing');
  }

  /// Jump to this candidate in the planetarium — the sky-context counterpart to
  /// "Send to Framing", so a candidate can be judged against its neighbourhood
  /// (horizon, moon, neighbouring targets) before it is committed.
  void _showInSky(BuildContext context, WidgetRef ref) {
    showTargetInSky(
      context,
      ref,
      raHours: suggestion.raHours,
      decDegrees: suggestion.decDegrees,
      name: suggestion.targetName,
    );
  }

  Future<void> _addToObservingList(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CandidateObservingListDialog(
        suggestion: suggestion,
        colors: colors,
      ),
    );
  }
}
