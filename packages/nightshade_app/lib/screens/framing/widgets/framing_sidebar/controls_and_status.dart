part of '../framing_sidebar.dart';

/// "Frame" section: rotation slider, equipment FOV summary (or hint when no
/// equipment), preview FOV slider, equipment-overlay controls, survey-source
/// dropdown, and display toggles (Grid / Labels / Directions).
class FramingControlsSection extends ConsumerWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final AsyncValue<FramingEquipmentResult> equipmentAsync;

  const FramingControlsSection({
    super.key,
    required this.colors,
    required this.framingState,
    required this.equipmentAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = equipmentAsync.valueOrNull;
    final equipment = result?.equipment;
    final hasEquipment = result?.isReady ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frame',
          style: NightshadeTypography.h6.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 12),

        // Rotation slider (only useful with equipment)
        FramingSliderField(
          key: FramingTutorialKeys.rotation,
          label: 'Rotation',
          value: framingState.rotation,
          min: -180,
          max: 180,
          suffix: '°',
          colors: colors,
          onChanged: hasEquipment
              ? (value) => ref.read(framingProvider.notifier).setRotation(value)
              : (_) {},
        ),
        const SizedBox(height: 12),

        // FOV display (only show when equipment is ready)
        if (hasEquipment && equipment != null) ...[
          FramingInfoRow(
            label: 'FOV',
            value:
                '${equipment.fovWidthDeg.toStringAsFixed(2)}° × ${equipment.fovHeightDeg.toStringAsFixed(2)}°',
            colors: colors,
            highlight: true,
          ),
          const SizedBox(height: 8),
          FramingInfoRow(
            label: 'Resolution',
            value: '${equipment.imageScale.toStringAsFixed(2)} arcsec/px',
            colors: colors,
          ),
          const SizedBox(height: 8),
          FramingInfoRow(
            label: 'Sensor',
            value: '${equipment.pixelsX} × ${equipment.pixelsY}',
            colors: colors,
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: NightshadeTokens.borderRadiusInline8,
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(NightshadeIcons.frame, size: 16, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure equipment to see FOV overlay',
                    style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Preview FOV control (always available for browsing)
        Text(
          'Preview Field of View',
          style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        FramingPreviewFovSlider(
          colors: colors,
          value: framingState.previewFovDegrees,
          hasEquipment: hasEquipment,
          equipmentFov: equipment?.fovWidthDeg,
          onChanged: (value) {
            ref.read(framingProvider.notifier).setPreviewFov(value);
          },
        ),

        // Equipment FOV overlay controls (only when equipment is configured and preview FOV > equipment FOV)
        if (hasEquipment &&
            equipment != null &&
            framingState.previewFovDegrees > equipment.fovWidthDeg) ...[
          const SizedBox(height: 16),
          FramingEquipmentFovOverlayControls(
            colors: colors,
            showOverlay: framingState.showEquipmentFovOverlay,
            opacity: framingState.equipmentFovOverlayOpacity,
            onToggle: () {
              ref.read(framingProvider.notifier).toggleEquipmentFovOverlay();
            },
            onOpacityChanged: (value) {
              ref
                  .read(framingProvider.notifier)
                  .setEquipmentFovOverlayOpacity(value);
            },
          ),
        ],

        const SizedBox(height: 16),

        // Survey source dropdown (always available - can browse sky without FOV)
        Text(
          'Survey Source',
          style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: colors.border),
          ),
          child: DropdownButton<SurveySource>(
            value: framingState.surveySource,
            isExpanded: true,
            underline: const SizedBox(),
            style: TextStyle(fontSize: NightshadeTypography.fontSize11, color: colors.textPrimary),
            dropdownColor: colors.surfaceAlt,
            items: SurveySource.values.map((source) {
              return DropdownMenuItem(
                value: source,
                child: Text(source.displayName),
              );
            }).toList(),
            onChanged: (source) {
              if (source != null) {
                ref.read(framingProvider.notifier).setSurveySource(source);
              }
            },
          ),
        ),

        const SizedBox(height: 16),

        // Display toggles
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FramingToggleChip(
              label: 'Grid',
              isActive: framingState.showGrid,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleGrid(),
            ),
            FramingToggleChip(
              label: 'Labels',
              isActive: framingState.showLabels,
              colors: colors,
              onTap: () => ref.read(framingProvider.notifier).toggleLabels(),
            ),
            if (hasEquipment)
              FramingToggleChip(
                label: 'Directions',
                isActive: framingState.showCardinalDirections,
                colors: colors,
                onTap: () => ref
                    .read(framingProvider.notifier)
                    .toggleCardinalDirections(),
              ),
          ],
        ),
      ],
    );
  }
}

/// Coordinates panel: RA/Dec readout for the current target, plus computed
/// Alt/Az with horizon warning. Copy-to-clipboard icon for the target's
/// RA/Dec string.
class FramingCoordinatesPanel extends StatelessWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final (double, double)? currentAltAz;

  const FramingCoordinatesPanel({
    super.key,
    required this.colors,
    required this.framingState,
    required this.currentAltAz,
  });

  @override
  Widget build(BuildContext context) {
    final target = framingState.target;

    return Container(
      key: FramingTutorialKeys.coordinates,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Coordinates',
                style: NightshadeTypography.labelStrongSm.copyWith(color: colors.textPrimary),
              ),
              if (target != null)
                IconButton(
                  icon:
                      Icon(NightshadeIcons.copy, size: 12, color: colors.textMuted),
                  tooltip: 'Copy coordinates',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: '${target.raFormatted}, ${target.decFormatted}',
                    ));
                    context.showInfoSnackBar('Coordinates copied');
                  },
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
          const SizedBox(height: 12),
          FramingCoordRow(
            label: 'RA',
            value: target?.raFormatted ?? '--',
            colors: colors,
          ),
          const SizedBox(height: 6),
          FramingCoordRow(
            label: 'Dec',
            value: target?.decFormatted ?? '--',
            colors: colors,
          ),
          const Divider(height: 20),
          FramingCoordRow(
            label: 'Alt',
            value: currentAltAz != null
                ? '${currentAltAz!.$1.toStringAsFixed(1)}°'
                : '--',
            colors: colors,
            isGood: currentAltAz != null && currentAltAz!.$1 > 30,
            isBad: currentAltAz != null && currentAltAz!.$1 < 15,
          ),
          const SizedBox(height: 6),
          FramingCoordRow(
            label: 'Az',
            value: currentAltAz != null
                ? '${currentAltAz!.$2.toStringAsFixed(1)}°'
                : '--',
            colors: colors,
          ),
          if (currentAltAz != null && currentAltAz!.$1 < 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(NightshadeIcons.warning,
                      size: 12, color: colors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Target below horizon',
                    style: TextStyle(fontSize: NightshadeTypography.fontSize10, color: colors.warning),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Altitude chart panel: shows tonight's altitude curve for the current
/// target, or a placeholder card when no target is selected.
class FramingAltitudePanel extends StatelessWidget {
  final NightshadeColors colors;
  final FramingState framingState;

  const FramingAltitudePanel({
    super.key,
    required this.colors,
    required this.framingState,
  });

  @override
  Widget build(BuildContext context) {
    final target = framingState.target;

    if (target == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: NightshadeTokens.borderRadiusLg,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.trendingUp, size: 14, color: colors.textMuted),
                const SizedBox(width: 8),
                Text(
                  'Altitude',
                  style: NightshadeTypography.labelStrongSm.copyWith(color: colors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Select a target to view altitude chart',
                style: TextStyle(fontSize: NightshadeTypography.fontSize10, color: colors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: NightshadeTokens.borderRadiusLg,
        border: Border.all(color: colors.border),
      ),
      child: AltitudeChart(
        key: FramingTutorialKeys.altitudeChart,
        raHours: target.raHours,
        decDegrees: target.decDegrees,
        targetName: target.name,
      ),
    );
  }
}
