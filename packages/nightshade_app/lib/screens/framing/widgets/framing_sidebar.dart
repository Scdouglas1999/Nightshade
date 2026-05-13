import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart'
    hide TargetSearchState, targetSearchProvider;

import 'package:nightshade_app/utils/snackbar_helper.dart';
import 'package:nightshade_app/widgets/slew_dropdown_button.dart';
import '../../../widgets/tutorial_keys/framing_keys.dart';
import '../altitude_chart.dart';
import '../framing_search_provider.dart';
import 'framing_controls.dart';
import 'framing_overlays.dart';

/// Target search section: SIMBAD-backed name search, results dropdown, and
/// manual RA/Dec entry fields. The controllers are owned by the parent screen
/// so navigating away and back preserves the input state.
class FramingTargetSearch extends ConsumerWidget {
  final NightshadeColors colors;
  final TargetSearchState searchState;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final TextEditingController raController;
  final TextEditingController decController;
  final ValueChanged<FramingTarget> onTargetSelected;
  final ValueChanged<String> onResolveByName;
  final VoidCallback onGoToManualCoordinates;

  const FramingTargetSearch({
    super.key,
    required this.colors,
    required this.searchState,
    required this.searchController,
    required this.searchFocusNode,
    required this.raController,
    required this.decController,
    required this.onTargetSelected,
    required this.onResolveByName,
    required this.onGoToManualCoordinates,
  });

  IconData _iconForType(TargetType? type) {
    switch (type) {
      case TargetType.galaxy:
        return LucideIcons.circle;
      case TargetType.nebula:
        return LucideIcons.cloud;
      case TargetType.cluster:
        return LucideIcons.sparkles;
      case TargetType.star:
        return LucideIcons.star;
      case TargetType.planet:
        return LucideIcons.globe;
      default:
        return LucideIcons.target;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: FramingTutorialKeys.targetSearch,
            controller: searchController,
            focusNode: searchFocusNode,
            style: TextStyle(fontSize: 12, color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by name (M42, NGC7000, Orion)',
              hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
              prefixIcon:
                  Icon(LucideIcons.search, size: 14, color: colors.textMuted),
              suffixIcon: searchState.isSearching
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(LucideIcons.x,
                              size: 14, color: colors.textMuted),
                          onPressed: () {
                            searchController.clear();
                            ref.read(targetSearchProvider.notifier).clear();
                          },
                        )
                      : null,
              filled: true,
              fillColor: colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.primary),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (value) {
              ref.read(targetSearchProvider.notifier).search(value);
            },
            onSubmitted: (value) {
              if (searchState.results.isNotEmpty) {
                onTargetSelected(searchState.results.first);
              } else if (value.isNotEmpty) {
                onResolveByName(value);
              }
            },
          ),

          // Search results dropdown
          if (searchState.results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.border),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: searchState.results.length,
                itemBuilder: (context, index) {
                  final target = searchState.results[index];
                  return InkWell(
                    onTap: () => onTargetSelected(target),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _iconForType(target.type),
                            size: 14,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  target.name,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (target.catalogId != null &&
                                    target.catalogId != target.name)
                                  Text(
                                    target.catalogId!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (target.magnitude != null)
                            Text(
                              'mag ${target.magnitude!.toStringAsFixed(1)}',
                              style: TextStyle(
                                fontSize: 10,
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

          // Manual coordinate entry
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: raController,
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'RA',
                    labelStyle:
                        TextStyle(fontSize: 10, color: colors.textMuted),
                    hintText: '05h 35m 17s',
                    hintStyle: TextStyle(fontSize: 10, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: decController,
                  style: TextStyle(fontSize: 11, color: colors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Dec',
                    labelStyle:
                        TextStyle(fontSize: 10, color: colors.textMuted),
                    hintText: '-05° 23\' 28"',
                    hintStyle: TextStyle(fontSize: 10, color: colors.textMuted),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FramingSmallIconButton(
                icon: LucideIcons.arrowRight,
                tooltip: 'Go to coordinates',
                colors: colors,
                onTap: onGoToManualCoordinates,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Equipment summary section in the sidebar: status badge plus a context card
/// for the current `EquipmentStatus` (noProfile / noFocalLength /
/// noCameraSpecs / ready) and a warning for default sensor specs.
class FramingEquipmentSection extends StatelessWidget {
  final NightshadeColors colors;
  final AsyncValue<FramingEquipmentResult> equipmentAsync;

  const FramingEquipmentSection({
    super.key,
    required this.colors,
    required this.equipmentAsync,
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
              'Equipment',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            equipmentAsync.when(
              data: (result) {
                if (result.isReady) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.checkCircle,
                          size: 12, color: colors.success),
                      const SizedBox(width: 4),
                      Text(
                        result.profileName ?? 'Ready',
                        style: TextStyle(fontSize: 10, color: colors.success),
                      ),
                    ],
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.alertCircle,
                        size: 12, color: colors.warning),
                    const SizedBox(width: 4),
                    Text(
                      'Not Configured',
                      style: TextStyle(fontSize: 10, color: colors.warning),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(),
              error: (error, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.alertCircle, size: 12, color: colors.error),
                  const SizedBox(width: 4),
                  Text(
                    'Error',
                    style: TextStyle(fontSize: 10, color: colors.error),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        equipmentAsync.when(
          data: (result) {
            switch (result.status) {
              case EquipmentStatus.noProfile:
                return FramingEquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.settings,
                  title: 'No Equipment Profile',
                  message:
                      'Create and activate an equipment profile in Settings → Equipment to enable framing preview.',
                  actionLabel: 'Open Settings',
                  onAction: () {
                    // Navigate to settings
                  },
                );

              case EquipmentStatus.noFocalLength:
                return FramingEquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.focus,
                  title: 'Optical Specs Missing',
                  message:
                      'Set the focal length in profile "${result.profileName}" to enable FOV preview.',
                  actionLabel: 'Edit Profile',
                  onAction: () {
                    // Navigate to profile editor
                  },
                );

              case EquipmentStatus.noCameraSpecs:
                return FramingEquipmentWarningCard(
                  colors: colors,
                  icon: LucideIcons.camera,
                  title: 'Camera Not Configured',
                  message:
                      'Connect a camera or configure camera specs to enable accurate FOV preview.',
                  actionLabel: null,
                  onAction: null,
                );

              case EquipmentStatus.ready:
                final equipment = result.equipment!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FramingInfoRow(
                      label: 'Camera',
                      value: equipment.cameraName,
                      colors: colors,
                    ),
                    const SizedBox(height: 6),
                    FramingInfoRow(
                      label: 'Telescope',
                      value:
                          '${equipment.effectiveFocalLength.round()}mm f/${equipment.focalRatio.toStringAsFixed(1)}',
                      colors: colors,
                    ),
                    if (result.message != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: colors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: colors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(LucideIcons.info,
                                size: 12, color: colors.warning),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                result.message!,
                                style: TextStyle(
                                    fontSize: 10, color: colors.warning),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
            }
          },
          loading: () => const SizedBox(
            height: 60,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (e, _) => FramingEquipmentWarningCard(
            colors: colors,
            icon: LucideIcons.alertTriangle,
            title: 'Error Loading Equipment',
            message: e.toString(),
            actionLabel: null,
            onAction: null,
          ),
        ),
      ],
    );
  }
}

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
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
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
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.border),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.frame, size: 16, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Configure equipment to see FOV overlay',
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
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
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
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
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.border),
          ),
          child: DropdownButton<SurveySource>(
            value: framingState.surveySource,
            isExpanded: true,
            underline: const SizedBox(),
            style: TextStyle(fontSize: 11, color: colors.textPrimary),
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
        borderRadius: BorderRadius.circular(10),
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
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              if (target != null)
                IconButton(
                  icon:
                      Icon(LucideIcons.copy, size: 12, color: colors.textMuted),
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
                  Icon(LucideIcons.alertTriangle,
                      size: 12, color: colors.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Target below horizon',
                    style: TextStyle(fontSize: 10, color: colors.warning),
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
          borderRadius: BorderRadius.circular(10),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Select a target to view altitude chart',
                style: TextStyle(fontSize: 10, color: colors.textMuted),
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
        borderRadius: BorderRadius.circular(10),
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

/// Mosaic planning panel: enable switch, columns/rows spinners, overlap
/// slider, capture pattern (serpentine/numbers), start-corner selector, panel
/// list, and export-to-targets button.
class FramingMosaicPanel extends ConsumerWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final AsyncValue<FramingEquipmentResult> equipmentAsync;

  const FramingMosaicPanel({
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
            Switch(
              value: framingState.mosaicEnabled,
              onChanged:
                  hasEquipment ? (v) => notifier.setMosaicEnabled(v) : null,
              activeTrackColor: colors.primary,
              thumbColor: WidgetStateProperty.all(Colors.white),
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

/// Actions panel at the bottom of the sidebar: Slew, Add to Sequence, Save
/// Target, Cache Image, Reload. Slew uses the SlewDropdownButton when both a
/// target and a connected mount are available.
class FramingActionsPanel extends ConsumerWidget {
  final NightshadeColors colors;
  final FramingState framingState;
  final VoidCallback onAddToSequence;
  final VoidCallback onSaveTarget;
  final VoidCallback onCacheImage;

  const FramingActionsPanel({
    super.key,
    required this.colors,
    required this.framingState,
    required this.onAddToSequence,
    required this.onSaveTarget,
    required this.onCacheImage,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasTarget = framingState.target != null;
    final mountState = ref.watch(mountStateProvider);
    final hasMountConnected =
        mountState.connectionState == DeviceConnectionState.connected;

    // Slew requires a target and a connected mount (FOV/equipment profile is optional)
    final canSlew = hasTarget && hasMountConnected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: hasTarget
              ? SlewDropdownButton(
                  key: FramingTutorialKeys.slewBtn,
                  ra: framingState.target!.raHours,
                  dec: framingState.target!.decDegrees,
                  targetName: framingState.target!.name,
                  targetRotation:
                      framingState.rotation != 0 ? framingState.rotation : null,
                  isEnabled: canSlew,
                  icon: LucideIcons.compass,
                  label: 'Slew to Target',
                )
              : FramingActionButton(
                  key: FramingTutorialKeys.slewBtn,
                  icon: LucideIcons.compass,
                  label: 'Slew to Target',
                  isPrimary: true,
                  colors: colors,
                  isEnabled: false,
                  onTap: null,
                ),
        ),

        // Show hint if slew is disabled
        if (hasTarget && !hasMountConnected)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Connect a mount to enable slewing',
              style: TextStyle(fontSize: 10, color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FramingActionButton(
                icon: LucideIcons.plus,
                label: 'Add to Sequence',
                colors: colors,
                isEnabled: hasTarget,
                onTap: hasTarget ? onAddToSequence : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FramingActionButton(
                icon: LucideIcons.bookmark,
                label: 'Save Target',
                colors: colors,
                isEnabled: hasTarget,
                onTap: hasTarget ? onSaveTarget : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FramingActionButton(
                icon: LucideIcons.download,
                label: 'Cache Image',
                colors: colors,
                isEnabled: framingState.surveyImageBytes != null,
                onTap:
                    framingState.surveyImageBytes != null ? onCacheImage : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FramingActionButton(
                icon: LucideIcons.refreshCw,
                label: 'Reload',
                colors: colors,
                isEnabled: hasTarget,
                onTap: hasTarget
                    ? () => ref.read(framingProvider.notifier).loadSurveyImage()
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
