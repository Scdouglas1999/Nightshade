import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'settings_widgets.dart';

class AnnotationSettingsPage extends ConsumerWidget {
  final NightshadeColors colors;
  final bool isMobile;

  const AnnotationSettingsPage({super.key, required this.colors, this.isMobile = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(annotationSettingsProvider);
    final markerStyleAsync = ref.watch(annotationMarkerStyleProvider);
    final settingsNotifier = ref.read(annotationSettingsProvider.notifier);
    final markerNotifier = ref.read(annotationMarkerStyleProvider.notifier);

    final settings = settingsAsync.valueOrNull ?? const AnnotationSettings();
    final markerStyle =
        markerStyleAsync.valueOrNull ?? const AnnotationMarkerStyle();

    return SettingsPage(
      title: 'Annotations',
      description: 'Configure object annotations on captured images',
      colors: colors,
      isMobile: isMobile,
      hideHeader: isMobile,
      children: [
        // Display Settings
        SettingsSection(
          title: 'Display',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.eye,
              title: 'Enable annotations',
              subtitle: 'Show object annotations on images',
              trailing: SettingsSwitch(
                value: settings.enabled,
                onChanged: (value) => settingsNotifier.setEnabled(value),
                colors: colors,
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.tag,
              title: 'Show labels',
              subtitle: 'Display object names next to markers',
              trailing: SettingsSwitch(
                value: settings.showLabels,
                onChanged: (value) => settingsNotifier.setShowLabels(value),
                colors: colors,
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.hash,
              title: 'Show magnitudes',
              subtitle: 'Display magnitude values with labels',
              trailing: SettingsSwitch(
                value: settings.showMagnitudes,
                onChanged: (value) => settingsNotifier.setShowMagnitudes(value),
                colors: colors,
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.listTree,
              title: 'Max objects to display',
              subtitle: 'Limit number of annotations for performance',
              trailing: SettingsCompactSlider(
                value: settings.maxObjectsToDisplay.toDouble(),
                min: 50,
                max: 2000,
                divisions: 39,
                label: settings.maxObjectsToDisplay.toString(),
                onChanged: (value) =>
                    settingsNotifier.setMaxObjectsToDisplay(value.toInt()),
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.grid,
              title: 'Grid overlay',
              subtitle: 'Grid type: pixel, celestial RA/Dec, or off',
              trailing: SettingsDropdown(
                value: switch (settings.gridType) {
                  GridType.none => 'Off',
                  GridType.pixel => 'Pixel',
                  GridType.celestial => 'RA/Dec',
                },
                items: const ['Off', 'Pixel', 'RA/Dec'],
                onChanged: (value) {
                  final type = switch (value) {
                    'Pixel' => GridType.pixel,
                    'RA/Dec' => GridType.celestial,
                    _ => GridType.none,
                  };
                  settingsNotifier.setGridType(type);
                },
                colors: colors,
                isMobile: isMobile,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 20),

        // Magnitude Filtering
        SettingsSection(
          title: 'Magnitude Filter',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.sunDim,
              title: 'Minimum magnitude',
              subtitle: 'Brightest objects to show (lower = brighter)',
              trailing: SettingsCompactSlider(
                value: settings.minMagnitude,
                min: -5,
                max: 10,
                divisions: 30,
                label: settings.minMagnitude.toStringAsFixed(1),
                onChanged: (value) => settingsNotifier.setMinMagnitude(value),
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.sunMedium,
              title: 'Maximum magnitude',
              subtitle: 'Faintest objects to show (higher = fainter)',
              trailing: SettingsCompactSlider(
                value: settings.magnitudeCutoff,
                min: 8,
                max: 22,
                divisions: 28,
                label: settings.magnitudeCutoff.toStringAsFixed(1),
                onChanged: (value) =>
                    settingsNotifier.setMagnitudeCutoff(value),
                colors: colors,
                isMobile: isMobile,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 20),

        // Object Types
        SettingsSection(
          title: 'Object Types',
          colors: colors,
          isMobile: isMobile,
          children: [
            ObjectTypeToggle(
              title: 'Galaxies',
              icon: LucideIcons.circle,
              color: Color(markerStyle.galaxyColor),
              isEnabled: settings.visibleTypes
                  .contains(AnnotationObjectFilter.galaxies),
              onChanged: (value) => settingsNotifier
                  .toggleObjectType(AnnotationObjectFilter.galaxies),
              colors: colors,
              isMobile: isMobile,
            ),
            ObjectTypeToggle(
              title: 'Nebulae',
              icon: LucideIcons.cloud,
              color: Color(markerStyle.nebulaColor),
              isEnabled: settings.visibleTypes
                  .contains(AnnotationObjectFilter.nebulae),
              onChanged: (value) => settingsNotifier
                  .toggleObjectType(AnnotationObjectFilter.nebulae),
              colors: colors,
              isMobile: isMobile,
            ),
            ObjectTypeToggle(
              title: 'Star Clusters',
              icon: LucideIcons.sparkles,
              color: Color(markerStyle.clusterColor),
              isEnabled: settings.visibleTypes
                  .contains(AnnotationObjectFilter.starClusters),
              onChanged: (value) => settingsNotifier
                  .toggleObjectType(AnnotationObjectFilter.starClusters),
              colors: colors,
              isMobile: isMobile,
            ),
            ObjectTypeToggle(
              title: 'Planetary Nebulae',
              icon: LucideIcons.target,
              color: Color(markerStyle.planetaryNebulaColor),
              isEnabled: settings.visibleTypes
                  .contains(AnnotationObjectFilter.planetaryNebulae),
              onChanged: (value) => settingsNotifier
                  .toggleObjectType(AnnotationObjectFilter.planetaryNebulae),
              colors: colors,
              isMobile: isMobile,
            ),
            ObjectTypeToggle(
              title: 'Stars',
              icon: LucideIcons.star,
              color: Color(markerStyle.starColor),
              isEnabled:
                  settings.visibleTypes.contains(AnnotationObjectFilter.stars),
              onChanged: (value) => settingsNotifier
                  .toggleObjectType(AnnotationObjectFilter.stars),
              colors: colors,
              isMobile: isMobile,
            ),
            ObjectTypeToggle(
              title: 'Other Objects',
              icon: LucideIcons.helpCircle,
              color: Color(markerStyle.otherColor),
              isEnabled:
                  settings.visibleTypes.contains(AnnotationObjectFilter.other),
              onChanged: (value) => settingsNotifier
                  .toggleObjectType(AnnotationObjectFilter.other),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 20),

        // Fade Effects
        SettingsSection(
          title: 'Fade Effects',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.mousePointer,
              title: 'Fade when not hovering',
              subtitle: 'Dim annotations when mouse leaves image',
              trailing: SettingsSwitch(
                value: settings.fadeWhenNotHovering,
                onChanged: (value) =>
                    settingsNotifier.setFadeWhenNotHovering(value),
                colors: colors,
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.sun,
              title: 'Hover opacity',
              subtitle: 'Brightness when mouse is over image',
              trailing: SettingsCompactSlider(
                value: settings.hoverOpacity,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                label: '${(settings.hoverOpacity * 100).toInt()}%',
                onChanged: (value) => settingsNotifier.setHoverOpacity(value),
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.moon,
              title: 'Idle opacity',
              subtitle: 'Brightness when mouse leaves image',
              trailing: SettingsCompactSlider(
                value: settings.idleOpacity,
                min: 0.0,
                max: 0.5,
                divisions: 10,
                label: '${(settings.idleOpacity * 100).toInt()}%',
                onChanged: (value) => settingsNotifier.setIdleOpacity(value),
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.timer,
              title: 'Fade duration',
              subtitle: 'Animation speed in milliseconds',
              trailing: SettingsCompactSlider(
                value: settings.fadeAnimationMs.toDouble(),
                min: 100,
                max: 1000,
                divisions: 9,
                label: '${settings.fadeAnimationMs}ms',
                onChanged: (value) =>
                    settingsNotifier.setFadeAnimationMs(value.toInt()),
                colors: colors,
                isMobile: isMobile,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 20),

        // Click to Identify
        SettingsSection(
          title: 'Click to Identify',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.mousePointerClick,
              title: 'Enable click to identify',
              subtitle: 'Click on image to identify objects',
              trailing: SettingsSwitch(
                value: settings.clickToIdentify,
                onChanged: (value) =>
                    settingsNotifier.setClickToIdentify(value),
                colors: colors,
              ),
              colors: colors,
              isMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.crosshair,
              title: 'Search radius',
              subtitle: 'Distance to search for objects (arcseconds)',
              trailing: SettingsCompactSlider(
                value: settings.clickSearchRadiusArcsec,
                min: 5,
                max: 120,
                divisions: 23,
                label: '${settings.clickSearchRadiusArcsec.toInt()}"',
                onChanged: (value) =>
                    settingsNotifier.setClickSearchRadius(value),
                colors: colors,
                isMobile: isMobile,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 20),

        // Marker Styles
        SettingsSection(
          title: 'Marker Styles',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.pencil,
              title: 'Stroke width',
              subtitle: 'Thickness of marker outlines',
              trailing: SettingsCompactSlider(
                value: markerStyle.strokeWidth,
                min: 0.5,
                max: 4.0,
                divisions: 7,
                label: markerStyle.strokeWidth.toStringAsFixed(1),
                onChanged: (value) => markerNotifier.setStrokeWidth(value),
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.type,
              title: 'Label font size',
              subtitle: 'Size of text labels',
              trailing: SettingsCompactSlider(
                value: markerStyle.labelFontSize,
                min: 8,
                max: 18,
                divisions: 10,
                label: '${markerStyle.labelFontSize.toInt()}px',
                onChanged: (value) => markerNotifier.setLabelFontSize(value),
                colors: colors,
                isMobile: isMobile,
              ),
              colors: colors,
              isMobile: isMobile,
              stackOnMobile: isMobile,
            ),
            SettingRow(
              icon: LucideIcons.scaling,
              title: 'Scale by object size',
              subtitle: 'Larger objects get larger markers',
              trailing: SettingsSwitch(
                value: markerStyle.scaleBySize,
                onChanged: (value) => markerNotifier.setScaleBySize(value),
                colors: colors,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 16 : 20),

        // Automation
        SettingsSection(
          title: 'Automation',
          colors: colors,
          isMobile: isMobile,
          children: [
            SettingRow(
              icon: LucideIcons.zap,
              title: 'Auto-annotate images',
              subtitle: 'Automatically annotate plate-solved images',
              trailing: SettingsSwitch(
                value: settings.autoAnnotate,
                onChanged: (value) => settingsNotifier.setAutoAnnotate(value),
                colors: colors,
              ),
              isLast: true,
              colors: colors,
              isMobile: isMobile,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Reset Button
        Center(
          child: NightshadeButton(
            label: 'Reset to Defaults',
            icon: LucideIcons.rotateCcw,
            variant: ButtonVariant.ghost,
            size: ButtonSize.small,
            onPressed: () {
              settingsNotifier.reset();
              markerNotifier.reset();
            },
          ),
        ),
      ],
    );
  }
}
