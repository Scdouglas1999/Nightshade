import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import '../../../utils/preview_transform.dart';
import '../../../widgets/catalog_overlay_widget.dart';
import '../../../widgets/tutorial_keys/imaging_keys.dart';
import 'annotation_widgets.dart';
import 'custom_annotation_drawing.dart';
import 'guiding_active_chip.dart';
import 'image_display.dart';
import 'overlay_painters.dart';
import 'overlay_widgets.dart';
import 'science_hud.dart';
import 'sub_quality_badge.dart';

class LivePreviewArea extends ConsumerWidget {
  final NightshadeColors colors;
  final double zoomLevel;
  final Offset panOffset;
  final bool showCrosshair;
  final bool showGrid;
  final bool showStarOverlay;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFitToWindow;
  final VoidCallback onZoom1to1;
  final VoidCallback onAbortCapture;
  final void Function(Offset delta) onPanUpdate;
  final VoidCallback onToggleCrosshair;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleStarOverlay;

  const LivePreviewArea({
    super.key,
    required this.colors,
    required this.zoomLevel,
    required this.panOffset,
    required this.showCrosshair,
    required this.showGrid,
    required this.showStarOverlay,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitToWindow,
    required this.onZoom1to1,
    required this.onAbortCapture,
    required this.onPanUpdate,
    required this.onToggleCrosshair,
    required this.onToggleGrid,
    required this.onToggleStarOverlay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentImage = ref.watch(currentImageProvider);
    final previewHistogram = ref.watch(previewDisplayHistogramProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final lastStats = ref.watch(lastImageStatsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final exposureSettings = ref.watch(exposureSettingsProvider);
    final starDetectionResult = ref.watch(starDetectionResultProvider);
    final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    final scienceVizPrefs =
        ref.watch(scienceVisualizationPrefsProvider).valueOrNull ??
            const ScienceVisualizationPrefs();
    final scienceMode = ref.watch(scienceModeStateProvider);
    final scienceOverlay = ref.watch(scienceOverlayStateProvider);
    final scienceSnapshot = ref.watch(currentScienceSnapshotProvider);
    final latestCalibration = scienceSnapshot.$1;
    final latestTransparency = scienceSnapshot.$2;
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    final sessionImages = ref.watch(sessionImagesProvider);
    final currentFrameImageId = _resolveCurrentFrameImageId(
      sessionImages: sessionImages,
      currentImage: currentImage,
    );

    final sessionPsfTiles = sessionId != null
        ? ref.watch(sessionPsfTilesProvider(sessionId)).valueOrNull ??
            const <PsfFieldTileRow>[]
        : ref.watch(sessionlessPsfTilesProvider).valueOrNull ??
            const <PsfFieldTileRow>[];
    final psfTiles = _selectCurrentFramePsfTiles(
      sessionTiles: sessionPsfTiles,
      capturedImageId: currentFrameImageId,
    );
    final sessionResidualVectors = sessionId != null
        ? ref.watch(sessionResidualVectorsProvider(sessionId)).valueOrNull ??
            const <AstrometryResidualVectorRow>[]
        : ref.watch(sessionlessResidualVectorsProvider).valueOrNull ??
            const <AstrometryResidualVectorRow>[];
    final residualVectors = _selectCurrentFrameResidualVectors(
      sessionVectors: sessionResidualVectors,
      capturedImageId: currentFrameImageId,
    );
    final sessionTileMetrics = sessionId != null
        ? ref.watch(sessionTileMetricsProvider(sessionId)).valueOrNull ??
            const <ScienceTileMetricRow>[]
        : ref.watch(sessionlessTileMetricsProvider).valueOrNull ??
            const <ScienceTileMetricRow>[];
    final currentFrameTileMetrics = _selectCurrentFrameTileMetrics(
      sessionTiles: sessionTileMetrics,
      capturedImageId: currentFrameImageId,
    );
    final uniformityTiles = currentFrameTileMetrics
        .where(
          (tile) => tile.layerType == ScienceLayerType.uniformity.dbValue,
        )
        .toList(growable: false);
    final clipHighTiles = currentFrameTileMetrics
        .where(
          (tile) => tile.layerType == ScienceLayerType.clipHigh.dbValue,
        )
        .toList(growable: false);
    final clipLowTiles = currentFrameTileMetrics
        .where(
          (tile) => tile.layerType == ScienceLayerType.clipLow.dbValue,
        )
        .toList(growable: false);
    // Representative per-frame eccentricity for the SubQualityBadge, derived
    // purely from the science tile metrics already watched above for
    // `currentFrameImageId`. Each eccentricity-layer tile carries its own
    // representative eccentricity in `value`; the median across tiles is a
    // robust single verdict that ignores a few hot corners. No new query or
    // analyzer is introduced — when no eccentricity tiles exist for the frame
    // this is null and the badge honestly renders `ECC —`.
    final frameEccentricity = _medianEccentricity(currentFrameTileMetrics);
    final sessionMovingCandidates = sessionId == null
        ? const <MovingObjectCandidateRow>[]
        : ref
                .watch(sessionMovingObjectCandidatesProvider(sessionId))
                .valueOrNull ??
            const <MovingObjectCandidateRow>[];
    final movingCandidates = _selectCurrentFrameMovingCandidates(
      sessionCandidates: sessionMovingCandidates,
      capturedImageId: currentFrameImageId,
    );
    final currentFrameWcs = currentFrameImageId == null
        ? null
        : ref.watch(capturedImageWcsProvider(currentFrameImageId)).valueOrNull;

    final annotationSettingsValue = ref.watch(annotationSettingsProvider);
    final annotationSettingsObj =
        annotationSettingsValue.valueOrNull ?? const AnnotationSettings();
    final gridType = annotationSettingsObj.gridType;
    final annotationShowResiduals = annotationSettingsObj.showSolveResiduals;
    final currentAnnotation = ref.watch(currentAnnotationProvider);
    final currentSkySolution = currentImage == null
        ? const _CurrentImageSkySolution()
        : _resolveCurrentImageSkySolution(
            wcs: currentFrameWcs,
            annotation: currentAnnotation,
            width: currentImage.width,
            height: currentImage.height,
          );

    final isConnected =
        cameraState.connectionState == DeviceConnectionState.connected;
    final isExposing =
        exposureProgress.percent > 0 || exposureProgress.isDownloading;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageOffset = currentImage != null
            ? computeImageOffset(
                viewportSize: viewportSize,
                imageSize: Size(currentImage.width.toDouble(),
                    currentImage.height.toDouble()),
                zoomLevel: zoomLevel,
                panOffset: panOffset,
              )
            : Offset.zero;
        final projectedMovingTracks = currentImage == null
            ? const <ProjectedMovingTrack>[]
            : _projectMovingTracks(
                candidates: movingCandidates,
                wcs: currentSkySolution.catalogWcs,
                imageWidth: currentImage.width.toDouble(),
                imageHeight: currentImage.height.toDouble(),
              );

        return Listener(
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              if (signal.scrollDelta.dy > 0) {
                onZoomOut();
              } else if (signal.scrollDelta.dy < 0) {
                onZoomIn();
              }
            }
          },
          child: GestureDetector(
            onPanUpdate: (details) => onPanUpdate(details.delta),
            child: Container(
              color: const Color(0xFF08080C),
              child: Stack(
                children: [
                  // Image display or empty state
                  if (currentImage != null)
                    Positioned.fill(
                      child: ImageDisplayWidget(
                        imageData: currentImage,
                        zoomLevel: zoomLevel,
                        panOffset: panOffset,
                      ),
                    )
                  else
                    // Star field background with empty-state message
                    Positioned.fill(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: StarFieldPainter(colors: colors),
                            ),
                          ),
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color:
                                        colors.surface.withValues(alpha: 0.8),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colors.border),
                                  ),
                                  child: Icon(
                                    LucideIcons.camera,
                                    size: 48,
                                    color: colors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  isConnected
                                      ? 'No Image'
                                      : 'No Camera Connected',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  isConnected
                                      ? 'Take a snapshot or start a capture loop'
                                      : 'Connect a camera in Equipment settings',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Crosshair overlay
                  if (showCrosshair && currentImage != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: CrosshairOverlayPainter(
                          color: colors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                    ),

                  // Pixel grid overlay
                  if (gridType == GridType.pixel && currentImage != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: GridOverlayPainter(
                          color: colors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                    ),

                  // Celestial RA/Dec grid overlay (requires plate solve)
                  if (gridType == GridType.celestial &&
                      currentImage != null &&
                      currentSkySolution.plateSolve != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: CelestialGridPainter(
                            plateSolve: currentSkySolution.plateSolve!,
                            zoomLevel: zoomLevel,
                            imageOffset: imageOffset,
                          ),
                        ),
                      ),
                    ),

                  // Star overlay
                  if (showStarOverlay &&
                      currentImage != null &&
                      starDetectionResult != null &&
                      starDetectionResult.stars.isNotEmpty)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: StarOverlayPainter(
                          stars: starDetectionResult.stars,
                          color: colors.accent.withValues(alpha: 0.8),
                          zoomLevel: zoomLevel,
                          imageOffset: imageOffset,
                        ),
                      ),
                    ),

                  // Annotation overlay with fade effects
                  if (currentImage != null)
                    Positioned.fill(
                      child: AnnotationOverlayWrapper(
                        zoomLevel: zoomLevel,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                        colors: colors,
                        previewViewportWidth: viewportSize.width,
                        onPanToObject: (imagePoint) {
                          // Calculate pan delta to center the image point on screen
                          final viewportSize = MediaQuery.sizeOf(context);
                          final screenCenter = Offset(
                            viewportSize.width / 2,
                            viewportSize.height / 2,
                          );
                          final currentScreenPos = imageToViewport(
                            imagePoint: imagePoint,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                          );
                          final delta = screenCenter - currentScreenPos;
                          onPanUpdate(delta);
                        },
                      ),
                    ),

                  // Catalog overlay (F5-CATALOG-OVERLAY): live projection of
                  // Messier / NGC / IC / bright stars from the planetarium
                  // catalog through the solved WCS. Independent of the
                  // existing annotation pipeline.
                  if (currentImage != null)
                    Positioned.fill(
                      child: CatalogOverlayWidget(
                        wcs: currentSkySolution.catalogWcs,
                        zoomLevel: zoomLevel,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                      ),
                    ),

                  // Custom user-drawn annotations (circles, arrows, text)
                  if (currentImage != null)
                    Positioned.fill(
                      child: CustomAnnotationDrawingLayer(
                        zoomLevel: zoomLevel,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                      ),
                    ),

                  // Compass and scale bar overlays (require plate solve data)
                  if (currentImage != null)
                    _CompassScaleBarOverlay(
                      zoomLevel: zoomLevel,
                      plateSolve: currentSkySolution.plateSolve,
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showPsfHeatmap &&
                      psfTiles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: SciencePsfOverlayPainter(
                            tiles: psfTiles,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      residualVectors.isNotEmpty &&
                      (annotationShowResiduals ||
                          (scienceSettings.advancedModeEnabled &&
                              scienceSettings.overlayEnabled &&
                              scienceOverlay.showResidualVectors)))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ScienceResidualOverlayPainter(
                            vectors: residualVectors,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showUniformityMap &&
                      uniformityTiles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ScienceUniformityOverlayPainter(
                            tiles: uniformityTiles,
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            opacity: scienceVizPrefs.overlayOpacity,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      (scienceOverlay.showClipHighMap ||
                          scienceOverlay.showClipLowMap))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ScienceClipOverlayPainter(
                            highTiles: scienceOverlay.showClipHighMap
                                ? clipHighTiles
                                : const <ScienceTileMetricRow>[],
                            lowTiles: scienceOverlay.showClipLowMap
                                ? clipLowTiles
                                : const <ScienceTileMetricRow>[],
                            imageOffset: imageOffset,
                            zoomLevel: zoomLevel,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            opacity: scienceVizPrefs.overlayOpacity,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceSettings.advancedModeEnabled &&
                      scienceSettings.overlayEnabled &&
                      scienceOverlay.showMovingObjectTracks &&
                      projectedMovingTracks.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: ScienceMovingTrackOverlayPainter(
                              tracks: projectedMovingTracks,
                              imageOffset: imageOffset,
                              zoomLevel: zoomLevel,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Exposure progress overlay
                  if (isExposing)
                    Positioned.fill(
                      child: ExposureProgressOverlay(
                        progress: exposureProgress,
                        colors: colors,
                      ),
                    ),

                  // Upper-right preview status badges: raw/HQ progress and
                  // calibration provenance. Both ride above the overlay bar
                  // chips so the user sees them even when zoomed in.
                  if (currentImage != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (currentImage.rawLoadStatus != RawLoadStatus.idle)
                            RawPreviewStatusBadge(
                              status: currentImage.rawLoadStatus,
                              colors: colors,
                            ),
                          if (currentImage.rawLoadStatus != RawLoadStatus.idle)
                            const SizedBox(width: 6),
                          // IMG-P1-4: surface whether the on-disk frame
                          // backing the current preview has actually been
                          // through the calibration pipeline. The provider
                          // only reports true when the saved file path
                          // ended up at `_cal.fits` — calibration failures
                          // leave the original path untouched, so this
                          // badge never lies about a frame that the
                          // pipeline couldn't calibrate.
                          _CalibratedBadge(colors: colors),
                        ],
                      ),
                    ),

                  // Top overlay bar - responsive layout
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Use compact layout on narrow screens
                        final isNarrow = constraints.maxWidth < 500;
                        final horizontalPadding = isNarrow ? 8.0 : 16.0;

                        return Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: horizontalPadding, vertical: 8),
                          child: isNarrow
                              // Compact mobile layout - stack chips on top, controls below
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Info chips - wrap to prevent overflow
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        OverlayChip(
                                          icon: LucideIcons.maximize2,
                                          label: currentImage != null
                                              ? '${currentImage.width}\u00d7${currentImage.height}'
                                              : '--\u00d7--',
                                          colors: colors,
                                        ),
                                        OverlayChip(
                                          icon: LucideIcons.search,
                                          label:
                                              '${(zoomLevel * 100).round()}%',
                                          colors: colors,
                                        ),
                                        if (scienceSettings.advancedModeEnabled)
                                          OverlayChip(
                                            icon: LucideIcons.gauge,
                                            label: latestCalibration
                                                        ?.zeroPoint ==
                                                    null
                                                ? 'ZP --'
                                                : 'ZP ${latestCalibration!.zeroPoint!.toStringAsFixed(2)}',
                                            colors: colors,
                                          ),
                                        if (scienceSettings.advancedModeEnabled)
                                          OverlayChip(
                                            icon: LucideIcons.cloud,
                                            label: latestTransparency == null
                                                ? 'Sky --'
                                                : 'Sky ${latestTransparency.qualityBucket}',
                                            colors: colors,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // Control buttons - wrap to prevent overflow
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Wrap(
                                            spacing: 2,
                                            runSpacing: 2,
                                            children: [
                                              OverlayIconButton(
                                                icon: LucideIcons.crosshair,
                                                tooltip: 'Crosshair',
                                                colors: colors,
                                                isActive: showCrosshair,
                                                onTap: onToggleCrosshair,
                                              ),
                                              OverlayIconButton(
                                                icon: gridType ==
                                                        GridType.celestial
                                                    ? LucideIcons.globe
                                                    : LucideIcons.grid,
                                                tooltip: switch (gridType) {
                                                  GridType.none => 'Grid: Off',
                                                  GridType.pixel =>
                                                    'Grid: Pixel',
                                                  GridType.celestial =>
                                                    'Grid: RA/Dec',
                                                },
                                                colors: colors,
                                                isActive:
                                                    gridType != GridType.none,
                                                onTap: () => ref
                                                    .read(
                                                        annotationSettingsProvider
                                                            .notifier)
                                                    .cycleGridType(),
                                              ),
                                              OverlayIconButton(
                                                icon: LucideIcons.sparkles,
                                                tooltip: 'Stars',
                                                colors: colors,
                                                isActive: showStarOverlay,
                                                onTap: onToggleStarOverlay,
                                              ),
                                              CatalogOverlayToolbarButton(
                                                  colors: colors),
                                              Consumer(
                                                builder: (context, ref, _) {
                                                  final isPanelVisible = ref.watch(
                                                      annotationPanelVisibleProvider);
                                                  return OverlayIconButton(
                                                    icon: LucideIcons.list,
                                                    tooltip: 'Objects',
                                                    colors: colors,
                                                    isActive: isPanelVisible,
                                                    onTap: () => ref
                                                        .read(
                                                            annotationPanelVisibleProvider
                                                                .notifier)
                                                        .state = !isPanelVisible,
                                                  );
                                                },
                                              ),
                                              if (scienceSettings
                                                  .advancedModeEnabled)
                                                OverlayIconButton(
                                                  icon:
                                                      LucideIcons.flaskConical,
                                                  tooltip: scienceMode
                                                          .scienceHudVisible
                                                      ? 'Hide science HUD'
                                                      : 'Show science HUD',
                                                  colors: colors,
                                                  isActive: scienceMode
                                                      .scienceHudVisible,
                                                  onTap: () => ref
                                                      .read(
                                                          scienceModeStateProvider
                                                              .notifier)
                                                      .state = scienceMode.copyWith(
                                                    scienceHudVisible:
                                                        !scienceMode
                                                            .scienceHudVisible,
                                                  ),
                                                ),
                                              Row(
                                                key: ImagingTutorialKeys
                                                    .zoomControls,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  OverlayIconButton(
                                                    icon: LucideIcons.zoomIn,
                                                    tooltip: 'Zoom in',
                                                    colors: colors,
                                                    onTap: onZoomIn,
                                                  ),
                                                  OverlayIconButton(
                                                    icon: LucideIcons.zoomOut,
                                                    tooltip: 'Zoom out',
                                                    colors: colors,
                                                    onTap: onZoomOut,
                                                  ),
                                                  OverlayIconButton(
                                                    icon: LucideIcons.maximize,
                                                    tooltip: 'Fit',
                                                    colors: colors,
                                                    onTap: onFitToWindow,
                                                  ),
                                                ],
                                              ),
                                              if (exposureProgress.percent >
                                                      0 &&
                                                  exposureProgress.percent <
                                                      1.0)
                                                OverlayIconButton(
                                                  key: ImagingTutorialKeys
                                                      .abortBtn,
                                                  icon: LucideIcons.x,
                                                  tooltip: 'Abort',
                                                  colors: colors,
                                                  onTap: onAbortCapture,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              // Standard desktop layout
                              : Row(
                                  children: [
                                    OverlayChip(
                                      icon: LucideIcons.maximize2,
                                      label: currentImage != null
                                          ? '${currentImage.width} \u00d7 ${currentImage.height}'
                                          : '--- \u00d7 ---',
                                      colors: colors,
                                    ),
                                    const SizedBox(width: 8),
                                    OverlayChip(
                                      icon: LucideIcons.grid,
                                      label:
                                          'Binning ${exposureSettings.binning}',
                                      colors: colors,
                                    ),
                                    const SizedBox(width: 8),
                                    OverlayChip(
                                      icon: LucideIcons.search,
                                      label: '${(zoomLevel * 100).round()}%',
                                      colors: colors,
                                    ),
                                    if (scienceSettings
                                        .advancedModeEnabled) ...[
                                      const SizedBox(width: 8),
                                      OverlayChip(
                                        icon: LucideIcons.gauge,
                                        label: latestCalibration?.zeroPoint ==
                                                null
                                            ? 'ZP --'
                                            : 'ZP ${latestCalibration!.zeroPoint!.toStringAsFixed(2)}',
                                        colors: colors,
                                      ),
                                      const SizedBox(width: 8),
                                      OverlayChip(
                                        icon: LucideIcons.cloud,
                                        label: latestTransparency == null
                                            ? 'Sky --'
                                            : 'Sky ${latestTransparency.qualityBucket}',
                                        colors: colors,
                                      ),
                                    ],
                                    const Spacer(),
                                    OverlayIconButton(
                                      icon: LucideIcons.crosshair,
                                      tooltip: 'Toggle crosshair',
                                      colors: colors,
                                      isActive: showCrosshair,
                                      onTap: onToggleCrosshair,
                                    ),
                                    OverlayIconButton(
                                      icon: gridType == GridType.celestial
                                          ? LucideIcons.globe
                                          : LucideIcons.grid,
                                      tooltip: switch (gridType) {
                                        GridType.none => 'Grid: Off',
                                        GridType.pixel => 'Grid: Pixel',
                                        GridType.celestial => 'Grid: RA/Dec',
                                      },
                                      colors: colors,
                                      isActive: gridType != GridType.none,
                                      onTap: () => ref
                                          .read(annotationSettingsProvider
                                              .notifier)
                                          .cycleGridType(),
                                    ),
                                    OverlayIconButton(
                                      icon: LucideIcons.sparkles,
                                      tooltip: 'Toggle star overlay',
                                      colors: colors,
                                      isActive: showStarOverlay,
                                      onTap: onToggleStarOverlay,
                                    ),
                                    CatalogOverlayToolbarButton(colors: colors),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final isPanelVisible = ref.watch(
                                            annotationPanelVisibleProvider);
                                        final annotation = ref
                                            .watch(currentAnnotationProvider);
                                        final objectCount =
                                            annotation?.objects.length ?? 0;
                                        return OverlayIconButton(
                                          icon: LucideIcons.list,
                                          tooltip:
                                              'Objects panel${objectCount > 0 ? ' ($objectCount)' : ''}',
                                          colors: colors,
                                          isActive: isPanelVisible,
                                          onTap: () => ref
                                              .read(
                                                  annotationPanelVisibleProvider
                                                      .notifier)
                                              .state = !isPanelVisible,
                                        );
                                      },
                                    ),
                                    if (scienceSettings.advancedModeEnabled)
                                      OverlayIconButton(
                                        icon: LucideIcons.flaskConical,
                                        tooltip: scienceMode.scienceHudVisible
                                            ? 'Hide science HUD'
                                            : 'Show science HUD',
                                        colors: colors,
                                        isActive: scienceMode.scienceHudVisible,
                                        onTap: () => ref
                                            .read(scienceModeStateProvider
                                                .notifier)
                                            .state = scienceMode.copyWith(
                                          scienceHudVisible:
                                              !scienceMode.scienceHudVisible,
                                        ),
                                      ),
                                    Row(
                                      key: ImagingTutorialKeys.zoomControls,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        OverlayIconButton(
                                          icon: LucideIcons.zoomIn,
                                          tooltip: 'Zoom in',
                                          colors: colors,
                                          onTap: onZoomIn,
                                        ),
                                        OverlayIconButton(
                                          icon: LucideIcons.zoomOut,
                                          tooltip: 'Zoom out',
                                          colors: colors,
                                          onTap: onZoomOut,
                                        ),
                                        OverlayIconButton(
                                          icon: LucideIcons.minimize2,
                                          tooltip: '1:1 zoom',
                                          colors: colors,
                                          onTap: onZoom1to1,
                                        ),
                                        OverlayIconButton(
                                          icon: LucideIcons.maximize,
                                          tooltip: 'Fit to window',
                                          colors: colors,
                                          onTap: onFitToWindow,
                                        ),
                                      ],
                                    ),
                                    if (exposureProgress.percent > 0 &&
                                        exposureProgress.percent < 1.0)
                                      OverlayIconButton(
                                        key: ImagingTutorialKeys.abortBtn,
                                        icon: LucideIcons.x,
                                        tooltip: 'Abort capture',
                                        colors: colors,
                                        onTap: onAbortCapture,
                                      ),
                                  ],
                                ),
                        );
                      },
                    ),
                  ),

                  // Bottom histogram overlay
                  if (scienceSettings.advancedModeEnabled &&
                      scienceMode.scienceHudVisible)
                    Positioned(
                      top: 56,
                      right: 16,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: Responsive.previewOverlayMaxWidth(
                            viewportSize.width,
                          ),
                          maxHeight: (viewportSize.height - 72)
                              .clamp(120.0, viewportSize.height),
                        ),
                        child: SingleChildScrollView(
                          child: ScienceHudPanel(colors: colors),
                        ),
                      ),
                    ),

                  // Bottom histogram overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: HistogramWidget(
                      key: ImagingTutorialKeys.histogram,
                      colors: colors,
                      histogram: previewHistogram,
                    ),
                  ),

                  // Right side stats
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: ImageStatsOverlay(
                      key: ImagingTutorialKeys.statsPanel,
                      colors: colors,
                      stats: lastStats,
                    ),
                  ),

                  // Bottom-left at-a-glance quality stack: live "Guiding"
                  // indicator over a per-sub quality verdict badge. Sits above
                  // the bottom-left histogram (which occupies bottom:16 + 80px
                  // height) rather than at bottom:12 so it never overlaps it;
                  // the detailed ImageStatsOverlay continues to own the
                  // bottom-right corner. Both children self-gate on their own
                  // providers (GuidingActiveChip collapses when not guiding,
                  // SubQualityBadge collapses with no captured frame), so this
                  // region is empty until there is something honest to show.
                  //
                  // Deliberately NOT wrapped in IgnorePointer: both children
                  // expose hover tooltips (GuidingActiveChip's RMS-units note
                  // and SubQualityBadge's reject-reason) that an IgnorePointer
                  // would silently kill. Like the bottom-right ImageStatsOverlay
                  // these are small, non-gesture corner widgets; they absorb the
                  // pointer only within their own compact footprint, matching
                  // that overlay's established pointer behaviour, and the rest
                  // of the canvas keeps its pan/zoom gestures.
                  if (currentImage != null)
                    Positioned(
                      bottom: 104,
                      left: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const GuidingActiveChip(),
                          const SizedBox(height: NightshadeTokens.spaceXs),
                          SubQualityBadge(eccentricity: frameEccentricity),
                        ],
                      ),
                    ),

                  // Mini annotation object chips (top, below overlay bar)
                  if (currentImage != null)
                    Positioned(
                      top: 44,
                      left: 8,
                      right: 8,
                      child: AnnotationMiniChips(colors: colors),
                    ),

                  // Annotation status indicator (top left, below the overlay bar + chips)
                  if (currentImage != null)
                    Positioned(
                      top: 72,
                      left: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnnotationStatusIndicator(colors: colors),
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: Responsive.previewOverlayMaxWidth(
                                viewportSize.width,
                                maxAbsolute: 380,
                              ),
                            ),
                            child: ReAnnotateSuggestionBanner(colors: colors),
                          ),
                        ],
                      ),
                    ),

                  // Custom annotation drawing toolbar
                  if (currentImage != null)
                    Positioned(
                      bottom: 110,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: CustomAnnotationToolbar(colors: colors),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<PsfFieldTileRow> _selectCurrentFramePsfTiles({
    required List<PsfFieldTileRow> sessionTiles,
    required int? capturedImageId,
  }) {
    if (sessionTiles.isEmpty) {
      return const <PsfFieldTileRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionTiles
          .where((tile) => tile.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionTiles
        .where((tile) => tile.capturedImageId != null)
        .map((tile) => tile.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == latest)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == id)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionTiles;
    }
    return sessionTiles
        .where((tile) => tile.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  int? _resolveCurrentFrameImageId({
    required List<CapturedImage> sessionImages,
    required CapturedImageData? currentImage,
  }) {
    final filePath = currentImage?.filePath;
    if (filePath == null || filePath.isEmpty) {
      return null;
    }
    final normalizedCurrent = _normalizeImagePath(filePath);
    for (final image in sessionImages) {
      if (_normalizeImagePath(image.filePath) == normalizedCurrent) {
        final parsed = int.tryParse(image.id);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    final currentBasename = _normalizeImagePath(p.basename(filePath));
    final basenameMatches = sessionImages.where((image) {
      return _normalizeImagePath(p.basename(image.filePath)) == currentBasename;
    }).toList(growable: false);
    if (basenameMatches.length == 1) {
      return int.tryParse(basenameMatches.single.id);
    }
    return null;
  }

  String _normalizeImagePath(String value) {
    return value
        .trim()
        .replaceAll('\\', '/')
        .replaceAll(RegExp(r'/+'), '/')
        .toLowerCase();
  }

  List<AstrometryResidualVectorRow> _selectCurrentFrameResidualVectors({
    required List<AstrometryResidualVectorRow> sessionVectors,
    required int? capturedImageId,
  }) {
    if (sessionVectors.isEmpty) {
      return const <AstrometryResidualVectorRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionVectors
          .where((vector) => vector.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionVectors
        .where((vector) => vector.capturedImageId != null)
        .map((vector) => vector.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionVectors
          .where((vector) => vector.capturedImageId == latest)
          .map((vector) => vector.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionVectors
          .where((vector) => vector.capturedImageId == id)
          .map((vector) => vector.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionVectors;
    }
    return sessionVectors
        .where((vector) => vector.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  List<ScienceTileMetricRow> _selectCurrentFrameTileMetrics({
    required List<ScienceTileMetricRow> sessionTiles,
    required int? capturedImageId,
  }) {
    if (sessionTiles.isEmpty) {
      return const <ScienceTileMetricRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionTiles
          .where((tile) => tile.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionTiles
        .where((tile) => tile.capturedImageId != null)
        .map((tile) => tile.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == latest)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionTiles
          .where((tile) => tile.capturedImageId == id)
          .map((tile) => tile.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionTiles;
    }
    return sessionTiles
        .where((tile) => tile.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  List<MovingObjectCandidateRow> _selectCurrentFrameMovingCandidates({
    required List<MovingObjectCandidateRow> sessionCandidates,
    required int? capturedImageId,
  }) {
    if (sessionCandidates.isEmpty) {
      return const <MovingObjectCandidateRow>[];
    }
    if (capturedImageId != null) {
      final matched = sessionCandidates
          .where((candidate) => candidate.capturedImageId == capturedImageId)
          .toList(growable: false);
      if (matched.isNotEmpty) {
        return matched;
      }
    }
    final latestImageId = sessionCandidates
        .where((candidate) => candidate.capturedImageId != null)
        .map((candidate) => candidate.capturedImageId!)
        .fold<int?>(null, (latest, id) {
      if (latest == null) {
        return id;
      }
      final latestTimestamp = sessionCandidates
          .where((candidate) => candidate.capturedImageId == latest)
          .map((candidate) => candidate.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      final idTimestamp = sessionCandidates
          .where((candidate) => candidate.capturedImageId == id)
          .map((candidate) => candidate.timestamp)
          .fold<DateTime>(DateTime.fromMillisecondsSinceEpoch(0),
              (a, b) => a.isAfter(b) ? a : b);
      return idTimestamp.isAfter(latestTimestamp) ? id : latest;
    });
    if (latestImageId == null) {
      return sessionCandidates;
    }
    return sessionCandidates
        .where((candidate) => candidate.capturedImageId == latestImageId)
        .toList(growable: false);
  }

  /// Median eccentricity across the current frame's eccentricity-layer tile
  /// metrics, or `null` when no such tiles exist for the frame.
  ///
  /// Consumes only the per-frame [ScienceTileMetricRow]s already watched in
  /// [build] (no extra query / analyzer). Each eccentricity tile reports its
  /// representative eccentricity in [ScienceTileMetricRow.value] — the same
  /// field the science overlay painters render — and the median across tiles
  /// yields a robust single frame verdict that ignores a few hot corners. Only
  /// finite values are considered so a malformed tile can never poison the
  /// result; if none remain, the badge honestly shows `ECC —`.
  double? _medianEccentricity(List<ScienceTileMetricRow> frameTileMetrics) {
    final values = <double>[];
    for (final tile in frameTileMetrics) {
      if (tile.layerType != ScienceLayerType.eccentricity.dbValue) {
        continue;
      }
      if (tile.value.isFinite) {
        values.add(tile.value);
      }
    }
    if (values.isEmpty) {
      return null;
    }
    values.sort();
    final mid = values.length ~/ 2;
    if (values.length.isOdd) {
      return values[mid];
    }
    return (values[mid - 1] + values[mid]) / 2.0;
  }

  List<ProjectedMovingTrack> _projectMovingTracks({
    required List<MovingObjectCandidateRow> candidates,
    required SolvedWcs? wcs,
    required double imageWidth,
    required double imageHeight,
  }) {
    if (candidates.isEmpty || wcs == null) {
      return const <ProjectedMovingTrack>[];
    }
    if (!wcs.isValid) {
      return const <ProjectedMovingTrack>[];
    }

    final tracks = <ProjectedMovingTrack>[];
    final centerRaDeg = wcs.raHours * 15.0;
    for (final candidate in candidates.take(200)) {
      final projected = _skyToPixel(
        raDegrees: candidate.raDegrees,
        decDegrees: candidate.decDegrees,
        centerRaDegrees: centerRaDeg,
        centerDecDegrees: wcs.decDegrees,
        rotationDegrees: wcs.rotationDeg,
        pixelScaleArcsecPerPixel: wcs.pixelScaleArcsec,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );
      if (projected == null) {
        continue;
      }
      tracks.add(
        ProjectedMovingTrack(
          imageX: projected.dx,
          imageY: projected.dy,
          positionAngleDegrees: candidate.positionAngleDegrees,
          motionArcsecPerMinute: candidate.motionArcsecPerMinute,
          confidence: candidate.confidence,
        ),
      );
    }
    return tracks;
  }

  Offset? _skyToPixel({
    required double raDegrees,
    required double decDegrees,
    required double centerRaDegrees,
    required double centerDecDegrees,
    required double rotationDegrees,
    required double pixelScaleArcsecPerPixel,
    required double imageWidth,
    required double imageHeight,
  }) {
    final raRad = raDegrees * math.pi / 180.0;
    final decRad = decDegrees * math.pi / 180.0;
    final centerRaRad = centerRaDegrees * math.pi / 180.0;
    final centerDecRad = centerDecDegrees * math.pi / 180.0;

    var dRa = raRad - centerRaRad;
    while (dRa > math.pi) {
      dRa -= 2 * math.pi;
    }
    while (dRa < -math.pi) {
      dRa += 2 * math.pi;
    }

    final cosDec = math.cos(decRad);
    final sinDec = math.sin(decRad);
    final cosCenterDec = math.cos(centerDecRad);
    final sinCenterDec = math.sin(centerDecRad);
    final denom = sinCenterDec * sinDec + cosCenterDec * cosDec * math.cos(dRa);
    if (denom <= 0) {
      return null;
    }

    final xi = cosDec * math.sin(dRa) / denom;
    final eta =
        (cosCenterDec * sinDec - sinCenterDec * cosDec * math.cos(dRa)) / denom;
    final xiDeg = xi * 180.0 / math.pi;
    final etaDeg = eta * 180.0 / math.pi;
    final rot = rotationDegrees * math.pi / 180.0;
    final xr = xiDeg * math.cos(rot) - etaDeg * math.sin(rot);
    final yr = xiDeg * math.sin(rot) + etaDeg * math.cos(rot);
    final x = xr * 3600.0 / pixelScaleArcsecPerPixel + imageWidth / 2.0;
    final y = imageHeight / 2.0 - yr * 3600.0 / pixelScaleArcsecPerPixel;
    if (!x.isFinite || !y.isFinite) {
      return null;
    }
    return Offset(x, y);
  }
}

/// Small success-coloured chip that announces the displayed frame has
/// been auto-calibrated. Watches `currentImageIsCalibratedProvider` and
/// collapses to nothing when the answer is false, so it costs zero
/// pixels for raw / failed-calibration frames.
///
/// Why a separate widget instead of inlining a `ref.watch` next to the
/// `RawPreviewStatusBadge` row: keeping the watch local to this widget
/// means a calibration-state flip only rebuilds the badge, not the
/// whole preview area (which paints the image, overlays, histograms,
/// etc.). The cost saved per swap is small but it lines up with how
/// the other preview badges are scoped.
class _CalibratedBadge extends ConsumerWidget {
  final NightshadeColors colors;

  const _CalibratedBadge({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCalibrated = ref.watch(currentImageIsCalibratedProvider);
    if (!isCalibrated) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.checkCircle2,
              size: 12,
              color: colors.onPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              'Calibrated',
              style: TextStyle(
                color: colors.onPrimary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Composite overlay widget that shows compass and scale bar when plate solve
/// data is available and the respective settings are enabled.
class _CompassScaleBarOverlay extends ConsumerWidget {
  final double zoomLevel;
  final PlateSolveData? plateSolve;

  const _CompassScaleBarOverlay({
    required this.zoomLevel,
    required this.plateSolve,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(annotationSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? const AnnotationSettings();

    final solve = plateSolve;
    if (solve == null) return const SizedBox.shrink();

    final showCompass = settings.compassEnabled;
    final showScaleBar = settings.scaleBarEnabled;
    if (!showCompass && !showScaleBar) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CompassScaleBarCombinedPainter(
            plateSolve: solve,
            showCompass: showCompass,
            showScaleBar: showScaleBar,
            zoomLevel: zoomLevel,
          ),
        ),
      ),
    );
  }
}

/// Combined painter that delegates to CompassOverlayPainter and ScaleBarPainter
/// to avoid multiple CustomPaint layers when both are visible.
class _CompassScaleBarCombinedPainter extends CustomPainter {
  final PlateSolveData plateSolve;
  final bool showCompass;
  final bool showScaleBar;
  final double zoomLevel;

  _CompassScaleBarCombinedPainter({
    required this.plateSolve,
    required this.showCompass,
    required this.showScaleBar,
    required this.zoomLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showCompass) {
      CompassOverlayPainter(
        rotationDegrees: plateSolve.rotation,
      ).paint(canvas, size);
    }
    if (showScaleBar) {
      ScaleBarPainter(
        pixelScaleArcsecPerPixel: plateSolve.pixelScale,
        imageWidthPixels: plateSolve.imageWidth.toDouble(),
        zoomLevel: zoomLevel,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _CompassScaleBarCombinedPainter oldDelegate) {
    return oldDelegate.plateSolve != plateSolve ||
        oldDelegate.showCompass != showCompass ||
        oldDelegate.showScaleBar != showScaleBar ||
        oldDelegate.zoomLevel != zoomLevel;
  }
}

/// Translate the database WCS row + image dimensions into the form the
/// catalog overlay expects. Returns null when the row is missing or the
/// frame wasn't plate-solved — the overlay widget renders an explanatory
/// banner in that case (per the project's "errors are a feature" rule).
class _CurrentImageSkySolution {
  final SolvedWcs? catalogWcs;
  final PlateSolveData? plateSolve;

  const _CurrentImageSkySolution({
    this.catalogWcs,
    this.plateSolve,
  });
}

_CurrentImageSkySolution _resolveCurrentImageSkySolution({
  required CapturedImageWcsData? wcs,
  required ImageAnnotation? annotation,
  required int width,
  required int height,
}) {
  final catalogWcs = _solvedWcsFromImage(
    wcs: wcs,
    width: width,
    height: height,
  );
  if (catalogWcs != null) {
    return _CurrentImageSkySolution(
      catalogWcs: catalogWcs,
      plateSolve: _plateSolveFromSolvedWcs(catalogWcs),
    );
  }

  final annotationSolve = annotation?.plateSolve;
  final annotationWcs = annotationSolve == null
      ? null
      : _solvedWcsFromPlateSolve(annotationSolve);
  return _CurrentImageSkySolution(
    catalogWcs: annotationWcs,
    plateSolve: annotationSolve,
  );
}

SolvedWcs? _solvedWcsFromImage({
  required CapturedImageWcsData? wcs,
  required int width,
  required int height,
}) {
  if (wcs == null || !wcs.isPlateSolved) return null;
  final ra = wcs.solvedRaHours;
  final dec = wcs.solvedDecDegrees;
  final rot = wcs.solvedRotationDegrees;
  final scale = wcs.solvedPixelScaleArcsecPerPixel;
  if (ra == null || dec == null || rot == null || scale == null) {
    return null;
  }
  return SolvedWcs(
    raHours: ra,
    decDegrees: dec,
    rotationDeg: rot,
    pixelScaleArcsec: scale,
    imageWidth: width,
    imageHeight: height,
  );
}

SolvedWcs? _solvedWcsFromPlateSolve(PlateSolveData plateSolve) {
  final solved = SolvedWcs(
    raHours: plateSolve.ra,
    decDegrees: plateSolve.dec,
    rotationDeg: plateSolve.rotation,
    pixelScaleArcsec: plateSolve.pixelScale,
    imageWidth: plateSolve.imageWidth,
    imageHeight: plateSolve.imageHeight,
  );
  return solved.isValid ? solved : null;
}

PlateSolveData _plateSolveFromSolvedWcs(SolvedWcs wcs) {
  return PlateSolveData(
    ra: wcs.raHours,
    dec: wcs.decDegrees,
    pixelScale: wcs.pixelScaleArcsec,
    rotation: wcs.rotationDeg,
    fieldWidth: wcs.imageWidth * wcs.pixelScaleArcsec / 3600.0,
    fieldHeight: wcs.imageHeight * wcs.pixelScaleArcsec / 3600.0,
    imageWidth: wcs.imageWidth,
    imageHeight: wcs.imageHeight,
  );
}

/// Toolbar button for the catalog overlay. Tapping toggles the overlay
/// on/off; the dropdown caret to the right opens the magnitude / kind
/// popover. Kept as a top-level widget so both desktop and mobile
/// toolbar layouts can drop it in without duplicating state plumbing.
class CatalogOverlayToolbarButton extends ConsumerWidget {
  final NightshadeColors colors;
  const CatalogOverlayToolbarButton({super.key, required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(catalogOverlayEnabledProvider);
    final magnitudeLimit = ref.watch(catalogOverlayMagnitudeLimitProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OverlayIconButton(
          icon: LucideIcons.target,
          tooltip:
              'Catalog overlay [Mag ≤ ${magnitudeLimit.toStringAsFixed(0)}]',
          colors: colors,
          isActive: enabled,
          onTap: () =>
              ref.read(catalogOverlayEnabledProvider.notifier).state = !enabled,
        ),
        // Why a separate dropdown trigger: a tap on the main icon must
        // toggle visibility (matches user expectation from the other
        // overlay buttons); the dropdown holds the configuration so it
        // doesn't accidentally fire when the user just wanted to flip
        // the overlay off.
        PopupMenuButton<String>(
          tooltip: 'Catalog overlay settings',
          position: PopupMenuPosition.under,
          offset: const Offset(0, 6),
          color: colors.surfaceElevated,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusMd),
            side: BorderSide(color: colors.border),
          ),
          onSelected: (_) {},
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              enabled: false,
              padding: EdgeInsets.zero,
              height: 0,
              child: CatalogOverlayPopover(colors: colors),
            ),
          ],
          icon: Icon(
            LucideIcons.chevronDown,
            color: colors.textMuted,
            size: 14,
          ),
          splashRadius: 14,
          padding: const EdgeInsets.symmetric(horizontal: 2),
        ),
      ],
    );
  }
}
