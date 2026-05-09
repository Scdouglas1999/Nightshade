import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import '../../../services/finder_chart_service.dart';
import '../../../utils/coordinate_format_utils.dart';
import '../../../widgets/tutorial_keys/planetarium_keys.dart';

class ViewControls extends ConsumerWidget {
  final NightshadeColors colors;
  final bool showFOV;
  final VoidCallback onToggleFOV;

  const ViewControls({
    super.key,
    required this.colors,
    required this.showFOV,
    required this.onToggleFOV,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(skyViewStateProvider);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ViewControlButton(
            icon: LucideIcons.plus,
            onTap: ref.read(skyViewStateProvider.notifier).zoomIn,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              CoordinateFormatUtils.formatFOVCompact(viewState.fieldOfView),
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white70,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          ViewControlButton(
            icon: LucideIcons.minus,
            onTap: ref.read(skyViewStateProvider.notifier).zoomOut,
          ),
          const Divider(height: 16, color: Colors.white24),
          ViewControlButton(
            icon: LucideIcons.home,
            onTap: () {
              ref.read(skyViewStateProvider.notifier).setCenter(0, 0);
              ref.read(skyViewStateProvider.notifier).setFieldOfView(60);
            },
          ),
          const SizedBox(height: 4),
          ViewControlButton(
            key: PlanetariumTutorialKeys.fovToggle,
            icon: LucideIcons.frame,
            isActive: showFOV,
            onTap: onToggleFOV,
            tooltip: 'Toggle FOV indicator',
          ),
          const Divider(height: 16, color: Colors.white24),
          // Compass HUD toggle - wrapped in Consumer to scope rebuilds
          Consumer(
            builder: (context, ref, _) {
              return ViewControlButton(
                icon: LucideIcons.compass,
                isActive: ref.watch(showCompassHudProvider),
                onTap: () {
                  final notifier = ref.read(showCompassHudProvider.notifier);
                  notifier.state = !notifier.state;
                },
                tooltip: 'Toggle Compass',
              );
            },
          ),
          const SizedBox(height: 4),
          // Mini-map toggle - wrapped in Consumer to scope rebuilds
          Consumer(
            builder: (context, ref, _) {
              return ViewControlButton(
                icon: LucideIcons.map,
                isActive: ref.watch(showMinimapProvider),
                onTap: () {
                  final notifier = ref.read(showMinimapProvider.notifier);
                  notifier.state = !notifier.state;
                },
                tooltip: 'Toggle Mini-map',
              );
            },
          ),
          const SizedBox(height: 4),
          // Satellite toggle - wrapped in Consumer to scope rebuilds
          Consumer(
            builder: (context, ref, _) {
              return ViewControlButton(
                icon: LucideIcons.satellite,
                isActive: ref.watch(showSatellitesProvider),
                onTap: () {
                  final notifier = ref.read(showSatellitesProvider.notifier);
                  notifier.state = !notifier.state;
                  // Also toggle in render config
                  ref.read(skyRenderConfigProvider.notifier).toggleSatellites();
                },
                tooltip: 'Toggle Satellites',
              );
            },
          ),
          const SizedBox(height: 4),
          // Variable stars toggle
          Consumer(
            builder: (context, ref, _) {
              return ViewControlButton(
                icon: LucideIcons.sparkles,
                isActive: ref.watch(showVariableStarsProvider),
                onTap: () {
                  final notifier = ref.read(showVariableStarsProvider.notifier);
                  notifier.state = !notifier.state;
                  ref.read(skyRenderConfigProvider.notifier).toggleVariableStars();
                },
                tooltip: 'Toggle Variable Stars',
              );
            },
          ),
          const SizedBox(height: 4),
          // Minor planets (asteroids/comets) toggle
          Consumer(
            builder: (context, ref, _) {
              return ViewControlButton(
                icon: LucideIcons.diamond,
                isActive: ref.watch(showMinorPlanetsProvider),
                onTap: () {
                  final notifier = ref.read(showMinorPlanetsProvider.notifier);
                  notifier.state = !notifier.state;
                  ref.read(skyRenderConfigProvider.notifier).toggleMinorPlanets();
                },
                tooltip: 'Toggle Asteroids & Comets',
              );
            },
          ),
          const SizedBox(height: 4),
          QualitySettingsButton(colors: colors),
          const Divider(height: 16, color: Colors.white24),
          ProjectionSelectorButton(colors: colors),
          const Divider(height: 16, color: Colors.white24),
          ExportChartButton(colors: colors),
        ],
      ),
    );
  }
}

/// Export finder chart as PDF
class ExportChartButton extends ConsumerStatefulWidget {
  final NightshadeColors colors;

  const ExportChartButton({super.key, required this.colors});

  @override
  ConsumerState<ExportChartButton> createState() => _ExportChartButtonState();
}

class _ExportChartButtonState extends ConsumerState<ExportChartButton> {
  bool _isExporting = false;

  Future<void> _exportChart({required bool printMode}) async {
    if (_isExporting) return;

    final viewState = ref.read(skyViewStateProvider);
    final renderConfig = ref.read(skyRenderConfigProvider);
    final location = ref.read(observerLocationProvider);
    final time = ref.read(observationTimeProvider);
    final stars = ref.read(fovFilteredStarsProvider).valueOrNull ?? [];
    final dsos = ref.read(fovFilteredDsosProvider).valueOrNull ?? [];
    final constellations = ref.read(constellationDataProvider);
    final selectedState = ref.read(selectedObjectProvider);
    final sunPos = ref.read(sunPositionProvider);
    final moonPos = ref.read(moonPositionProvider);
    final moonInfo = ref.read(moonInfoProvider);
    final planets = ref.read(planetPositionsProvider);
    final milkyWayPoints = ref.read(milkyWayPointsProvider);

    // Determine object name from selection
    String? objectName;
    String? objectType;
    double? objectMagnitude;
    String? objectSize;
    if (selectedState.object != null) {
      final obj = selectedState.object!;
      if (obj is DeepSkyObject) {
        final (displayName, _) = _getDsoDisplayInfo(obj);
        objectName = displayName;
        objectType = obj.type.displayName;
        objectMagnitude = obj.magnitude;
        objectSize = obj.sizeString;
      } else {
        objectName = obj.name;
        objectMagnitude = obj.magnitude;
        if (obj is Star) {
          objectType = obj.spectralType != null
              ? 'Star (${obj.spectralType})'
              : 'Star';
        }
      }
    }

    final suggestedName = FinderChartService.suggestedFilename(
      objectName: objectName,
    );

    final location2 = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF files', extensions: ['pdf']),
      ],
    );

    if (location2 == null) return;

    setState(() => _isExporting = true);

    try {
      await FinderChartService.generateChart(
        outputPath: location2.path,
        viewState: viewState,
        renderConfig: renderConfig,
        stars: stars,
        dsos: dsos,
        constellations: constellations,
        observationTime: time.time,
        latitude: location.latitude,
        longitude: location.longitude,
        chartConfig: FinderChartConfig(
          printMode: printMode,
          chartResolution: 2048,
          objectName: objectName,
          objectType: objectType,
          objectMagnitude: objectMagnitude,
          objectSize: objectSize,
          includeDetailsPage: objectName != null,
        ),
        selectedObject: selectedState.coordinates,
        sunPosition: sunPos,
        moonPosition: (moonPos.$1, moonPos.$2, moonInfo.illumination),
        planets: planets,
        milkyWayPoints: milkyWayPoints,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Finder chart saved to ${location2.path}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export chart: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isExporting) {
      return const SizedBox(
        width: 28,
        height: 28,
        child: Padding(
          padding: EdgeInsets.all(6),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white70,
          ),
        ),
      );
    }

    return PopupMenuButton<bool>(
      icon: const Icon(
        LucideIcons.fileDown,
        size: 18,
        color: Colors.white70,
      ),
      tooltip: 'Export finder chart',
      color: widget.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(-160, 0),
      onSelected: (printMode) => _exportChart(printMode: printMode),
      itemBuilder: (context) => [
        PopupMenuItem<bool>(
          value: false,
          child: Row(
            children: [
              Icon(LucideIcons.fileDown, size: 16, color: widget.colors.textPrimary),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Export Chart (Dark)',
                    style: TextStyle(color: widget.colors.textPrimary),
                  ),
                  Text(
                    'Dark sky background',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        PopupMenuItem<bool>(
          value: true,
          child: Row(
            children: [
              Icon(LucideIcons.printer, size: 16, color: widget.colors.textPrimary),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Export Chart (Print)',
                    style: TextStyle(color: widget.colors.textPrimary),
                  ),
                  Text(
                    'White background, black stars',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// DSO display name helper (same logic as planetarium_screen.dart)
  static (String, String) _getDsoDisplayInfo(DeepSkyObject dso) {
    if (dso.isMessier) {
      final messierNum = dso.messierNumber;
      if (messierNum != null) return (messierNum, 'M');
    }
    final ngcIc = dso.ngcIcDesignation;
    if (ngcIc != null) {
      if (ngcIc.startsWith('NGC')) return (ngcIc, 'NGC');
      if (ngcIc.startsWith('IC')) return (ngcIc, 'IC');
    }
    if (dso.id.startsWith('NGC')) return (dso.id, 'NGC');
    if (dso.id.startsWith('IC')) return (dso.id, 'IC');
    if (dso.id.startsWith('M')) return (dso.id, 'M');
    return (dso.name, dso.id);
  }
}

/// Quality settings popup button
class QualitySettingsButton extends ConsumerWidget {
  final NightshadeColors colors;

  const QualitySettingsButton({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quality = ref.watch(renderQualityProvider);

    return PopupMenuButton<RenderQuality>(
      icon: const Icon(
        LucideIcons.settings2,
        size: 18,
        color: Colors.white70,
      ),
      tooltip: 'Render quality',
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(-120, 0),
      onSelected: (tier) {
        ref.read(renderQualityProvider.notifier).setQuality(tier);
      },
      itemBuilder: (context) => [
        _buildQualityMenuItem(
          context,
          RenderQuality.minimal,
          'Minimal',
          'Raspberry Pi / low-power',
          quality.quality,
        ),
        _buildQualityMenuItem(
          context,
          RenderQuality.performance,
          'Performance',
          'Low-end devices',
          quality.quality,
        ),
        _buildQualityMenuItem(
          context,
          RenderQuality.balanced,
          'Balanced',
          'Recommended',
          quality.quality,
        ),
        _buildQualityMenuItem(
          context,
          RenderQuality.quality,
          'Quality',
          'Best visuals',
          quality.quality,
        ),
      ],
    );
  }

  PopupMenuItem<RenderQuality> _buildQualityMenuItem(
    BuildContext context,
    RenderQuality tier,
    String title,
    String subtitle,
    RenderQuality current,
  ) {
    final isSelected = tier == current;
    return PopupMenuItem<RenderQuality>(
      value: tier,
      child: Row(
        children: [
          Icon(
            isSelected ? LucideIcons.checkCircle : LucideIcons.circle,
            size: 16,
            color: isSelected ? colors.accent : colors.textSecondary,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Projection selector popup button
class ProjectionSelectorButton extends ConsumerWidget {
  final NightshadeColors colors;

  const ProjectionSelectorButton({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewState = ref.watch(skyViewStateProvider);
    final currentProjection = viewState.projection;

    return PopupMenuButton<SkyProjection>(
      icon: Icon(
        _projectionIcon(currentProjection),
        size: 18,
        color: Colors.white70,
      ),
      tooltip: 'Projection: ${_projectionName(currentProjection)}',
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(-140, 0),
      onSelected: (projection) {
        ref.read(skyViewStateProvider.notifier).setProjection(projection);
      },
      itemBuilder: (context) => SkyProjection.values.map((projection) {
        final isSelected = projection == currentProjection;
        return PopupMenuItem<SkyProjection>(
          value: projection,
          child: Row(
            children: [
              Icon(
                isSelected ? LucideIcons.checkCircle : LucideIcons.circle,
                size: 16,
                color: isSelected ? colors.accent : colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _projectionName(projection),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    _projectionDescription(projection),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static String _projectionName(SkyProjection projection) {
    switch (projection) {
      case SkyProjection.stereographic:
        return 'Stereographic';
      case SkyProjection.orthographic:
        return 'Orthographic';
      case SkyProjection.azimuthalEquidistant:
        return 'Equidistant';
    }
  }

  static String _projectionDescription(SkyProjection projection) {
    switch (projection) {
      case SkyProjection.stereographic:
        return 'Conformal, preserves angles';
      case SkyProjection.orthographic:
        return 'Perspective from infinity';
      case SkyProjection.azimuthalEquidistant:
        return 'Preserves distances from center';
    }
  }

  static IconData _projectionIcon(SkyProjection projection) {
    switch (projection) {
      case SkyProjection.stereographic:
        return LucideIcons.globe;
      case SkyProjection.orthographic:
        return LucideIcons.circle;
      case SkyProjection.azimuthalEquidistant:
        return LucideIcons.target;
    }
  }
}

class ViewControlButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final String? tooltip;

  const ViewControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.tooltip,
  });

  @override
  State<ViewControlButton> createState() => _ViewControlButtonState();
}

class _ViewControlButtonState extends State<ViewControlButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: widget.isActive
                ? const Color(0xFF00E676).withValues(alpha: 0.3)
                : (_isHovered
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(4),
            border: widget.isActive
                ? Border.all(color: const Color(0xFF00E676), width: 1)
                : null,
          ),
          child: Icon(
            widget.icon,
            size: 14,
            color: widget.isActive ? const Color(0xFF00E676) : Colors.white70,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(
        message: widget.tooltip!,
        child: button,
      );
    }
    return button;
  }
}
