part of '../framing_sidebar.dart';

/// Mosaic planning panel: enable switch, columns/rows spinners, overlap
/// slider, capture pattern (serpentine/numbers), start-corner selector, panel
/// list, and export-to-targets button.
class FramingMosaicSection extends ConsumerWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final AsyncValue<FramingEquipmentResult> equipmentAsync;

  const FramingMosaicSection({
    super.key,
    required this.colors,
    required this.framingState,
    required this.equipmentAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = equipmentAsync.valueOrNull;
    final hasEquipment = result?.isReady ?? false;
    final config = framingState.mosaicConfig;
    final notifier = ref.read(framingProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with toggle
        Row(
          key: FramingTutorialKeys.mosaicBtn,
          children: [
            Expanded(
              child: Text(
                'Mosaic',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
            NightshadeSwitch(
              value: framingState.mosaicEnabled,
              onChanged:
                  hasEquipment ? (v) => notifier.setMosaicEnabled(v) : null,
            ),
          ],
        ),

        if (!hasEquipment)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.info, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure equipment to enable mosaic planning',
                    style: TextStyle(fontSize: 10, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),

        if (framingState.mosaicEnabled && hasEquipment) ...[
          const SizedBox(height: 12),

          // Grid configuration
          Row(
            children: [
              Expanded(
                child: FramingMosaicSpinner(
                  label: 'Columns',
                  value: config.columns,
                  min: 1,
                  max: 10,
                  onChanged: notifier.setMosaicColumns,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FramingMosaicSpinner(
                  label: 'Rows',
                  value: config.rows,
                  min: 1,
                  max: 10,
                  onChanged: notifier.setMosaicRows,
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Overlap slider
          FramingSliderField(
            label: 'Overlap',
            value: config.overlapPercent,
            min: 0,
            max: 50,
            suffix: '%',
            colors: colors,
            onChanged: notifier.setMosaicOverlap,
          ),
          const SizedBox(height: 12),

          // Capture pattern options
          Row(
            children: [
              Expanded(
                child: FramingOptionButton(
                  icon: LucideIcons.moveHorizontal,
                  label: 'Serpentine',
                  isSelected: config.serpentine,
                  onTap: notifier.toggleSerpentine,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FramingOptionButton(
                  icon: LucideIcons.hash,
                  label: 'Numbers',
                  isSelected: framingState.showPanelNumbers,
                  onTap: notifier.togglePanelNumbers,
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Start corner dropdown
          Text(
            'Start Corner',
            style: TextStyle(fontSize: 10, color: colors.textSecondary),
          ),
          const SizedBox(height: 6),
          FramingStartCornerSelector(
            selected: config.startCorner,
            onChanged: notifier.setMosaicStartCorner,
            colors: colors,
          ),
          const SizedBox(height: 12),

          // Panel summary
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.layoutGrid,
                        size: 14, color: colors.primary),
                    const SizedBox(width: 8),
                    Text(
                      '${config.totalPanels} Panels',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (framingState.mosaicPanels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      // Fixed-height panel rows: 20 box + 4*2 vertical padding = 28.
                      itemExtent: 28,
                      itemCount: framingState.mosaicPanels.length,
                      itemBuilder: (context, index) {
                        final panel = framingState.mosaicPanels[index];
                        final isSelected =
                            index == framingState.selectedPanelIndex;
                        return InkWell(
                          onTap: () => notifier.selectPanel(index),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.primary.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? colors.primary
                                        : colors.surface,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected
                                          ? colors.primary
                                          : colors.border,
                                    ),
                                  ),
                                  child: Text(
                                    '${panel.index + 1}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : colors.textSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    panel.raFormatted,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                                Text(
                                  panel.decFormatted,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Export button
          if (framingState.mosaicPanels.isNotEmpty) ...[
            const SizedBox(height: 12),
            FramingExportMosaicButton(
              colors: colors,
              panels: framingState.mosaicPanels,
              targetName: framingState.target?.name ?? 'Mosaic',
            ),
          ],
        ],
      ],
    );
  }
}

/// Actions surface at the bottom of the framing sidebar.
///
/// The canonical, guided "resolve → frame → solve → slew" flow lives in
/// [FramingActionRail] (component C7) — there is no longer a second, inline
/// Slew button here, so the slew/survey controls are not duplicated across two
/// surfaces. This panel mounts that single rail and then exposes only the
/// supplementary utility actions the rail does not own (add the framed target
/// to a sequence, save it, cache the survey cutout, and reload it). The survey
/// source and rotation are read from `framingProvider`, so the rail and the
/// [FramingControlsSection] dropdown stay in lockstep automatically.
class FramingActionsPanel extends ConsumerWidget {
  final NightshadeColors colors;
  final FramingState framingState;

  /// Auto-build a complete Smart Night instruction tree for the framed target
  /// and load it into the sequencer.
  final VoidCallback onAddToSequence;

  /// Insert a bare target header (name / RA / Dec / rotation, no generated
  /// instructions) into a sequence the user picks, leaving the instruction
  /// tree for them to build manually in the Sequencer.
  final VoidCallback onAddToExistingSequence;
  final VoidCallback onSaveTarget;
  final VoidCallback onCacheImage;

  const FramingActionsPanel({
    super.key,
    required this.colors,
    required this.framingState,
    required this.onAddToSequence,
    required this.onAddToExistingSequence,
    required this.onSaveTarget,
    required this.onCacheImage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTarget = framingState.target != null;
    final hasSurveyImage = framingState.surveyImageBytes != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Canonical guided framing flow (target → frame → solve → slew).
        const FramingActionRail(),

        const SizedBox(height: NightshadeTokens.spaceXl),

        // Supplementary utility actions not covered by the guided rail.
        Text(
          'Utilities',
          style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: NightshadeTokens.spaceMd),
        // Utility actions use the design-system NightshadeButton (outline)
        // so the whole panel — guided rail + utilities — speaks one button
        // language (matching the rail's NightshadeButton solve action) rather
        // than mixing in a bespoke local button with different heights/radii.
        Row(
          children: [
            // Bare-header insert: drops the framed target into a chosen
            // sequence with no generated instructions — the user builds the
            // imaging tree under it manually in the Sequencer.
            Expanded(
              child: NightshadeButton(
                icon: LucideIcons.listPlus,
                label: 'Add to Sequence',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: hasTarget ? onAddToExistingSequence : null,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            // Auto-build: generates a complete Smart Night instruction tree for
            // the framed target and loads it.
            Expanded(
              child: NightshadeButton(
                icon: LucideIcons.wand2,
                label: 'Auto-build',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: hasTarget ? onAddToSequence : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        Row(
          children: [
            Expanded(
              child: NightshadeButton(
                icon: LucideIcons.bookmark,
                label: 'Save Target',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: hasTarget ? onSaveTarget : null,
              ),
            ),
            const SizedBox(width: NightshadeTokens.spaceSm),
            Expanded(
              child: NightshadeButton(
                icon: LucideIcons.download,
                label: 'Cache Image',
                variant: ButtonVariant.outline,
                size: ButtonSize.small,
                onPressed: hasSurveyImage ? onCacheImage : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: NightshadeTokens.spaceSm),
        SizedBox(
          width: double.infinity,
          child: NightshadeButton(
            icon: LucideIcons.refreshCw,
            label: 'Reload',
            variant: ButtonVariant.outline,
            size: ButtonSize.small,
            onPressed: hasTarget
                ? () => ref.read(framingProvider.notifier).loadSurveyImage()
                : null,
          ),
        ),
      ],
    );
  }
}
