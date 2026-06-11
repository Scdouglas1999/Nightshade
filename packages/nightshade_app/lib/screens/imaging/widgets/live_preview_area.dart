import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import '../../../widgets/raw_preview_status_badge.dart';
import '../../../utils/preview_transform.dart';
import '../../../widgets/catalog_overlay_widget.dart';
import '../../../widgets/tutorial_keys/imaging_keys.dart';
import 'annotation_widgets.dart';
import 'custom_annotation_drawing.dart';
import 'fullscreen_image_viewer.dart';
import 'guiding_active_chip.dart';
import 'image_display.dart';
import 'narrator_ticker.dart';
import 'overlay_painters.dart';
import 'overlay_widgets.dart';
import 'science_hud.dart';
import 'sub_quality_badge.dart';

part 'live_preview_area/frame_selection.dart';
part 'live_preview_area/preview_overlays.dart';

class LivePreviewArea extends ConsumerStatefulWidget {
  final NightshadeColors colors;
  final double zoomLevel;
  final Offset panOffset;
  final bool showCrosshair;
  final bool showStarOverlay;

  /// Scroll-wheel zoom handlers. The discrete zoom/fit/1:1 buttons and overlay
  /// toggles now live in the off-canvas [ImagingPreviewToolbar] above the
  /// preview, so the canvas itself only needs the wheel handlers to keep
  /// scroll-to-zoom working over the image.
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final void Function(Offset delta) onPanUpdate;

  const LivePreviewArea({
    super.key,
    required this.colors,
    required this.zoomLevel,
    required this.panOffset,
    required this.showCrosshair,
    required this.showStarOverlay,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onPanUpdate,
  });

  @override
  ConsumerState<LivePreviewArea> createState() => _LivePreviewAreaState();
}

class _LivePreviewAreaState extends ConsumerState<LivePreviewArea> {
  /// How long the pointer can sit still over the image before the corner
  /// readout chrome (histogram / stats / quality / annotation status) fades
  /// out, leaving a clean captured frame.
  static const Duration _idleHideDelay =
      Duration(seconds: 2, milliseconds: 500);

  /// Whether the fade-able corner chrome is currently visible. Starts visible;
  /// the first idle period hides it. Any pointer movement reveals it again.
  bool _chromeVisible = true;
  Timer? _idleTimer;

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  /// Reveal the corner chrome and restart the idle countdown. Called on any
  /// pointer movement over the canvas.
  void _onPointerActivity() {
    _idleTimer?.cancel();
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
    }
    _idleTimer = Timer(_idleHideDelay, () {
      if (!mounted) return;
      setState(() => _chromeVisible = false);
    });
  }

  /// Wrap a corner readout overlay so it fades out on idle and back in on
  /// pointer activity. Faded-out chrome is also made non-interactive via
  /// [IgnorePointer] so it can't swallow pan/annotation pointer events while
  /// invisible — but the underlying [MouseRegion] still receives hover, so the
  /// next mouse move re-reveals it.
  Widget _fadeChrome(Widget child) {
    return IgnorePointer(
      ignoring: !_chromeVisible,
      child: AnimatedOpacity(
        opacity: _chromeVisible ? 1.0 : 0.0,
        duration: NightshadeTokens.durationNormal,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final zoomLevel = widget.zoomLevel;
    final panOffset = widget.panOffset;
    final showCrosshair = widget.showCrosshair;
    final showStarOverlay = widget.showStarOverlay;
    final onZoomIn = widget.onZoomIn;
    final onZoomOut = widget.onZoomOut;
    final onPanUpdate = widget.onPanUpdate;
    final currentImage = ref.watch(currentImageProvider);
    final previewHistogram = ref.watch(previewDisplayHistogramProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final lastStats = ref.watch(lastImageStatsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final starDetectionResult = ref.watch(starDetectionResultProvider);
    final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull ??
        const ScienceSettings();
    final scienceVizPrefs =
        ref.watch(scienceVisualizationPrefsProvider).valueOrNull ??
            const ScienceVisualizationPrefs();
    final scienceMode = ref.watch(scienceModeStateProvider);
    final scienceOverlay = ref.watch(scienceOverlayStateProvider);
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
          // MouseRegion drives the idle auto-hide: any movement/enter reveals
          // the corner readout chrome and restarts the hide countdown. It is
          // hit-test transparent for gestures, so panning and the on-image
          // annotation drawing layer keep working underneath it.
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => _onPointerActivity(),
            onHover: (_) => _onPointerActivity(),
            child: GestureDetector(
              onPanUpdate: (details) => onPanUpdate(details.delta),
              // Tap the frame on a phone to inspect it fullscreen (pinch-zoom +
              // pan), since the in-place preview shares the short cover-screen
              // height with the controls. No-op when empty or on desktop, where
              // the preview already has room and a tap shouldn't hijack.
              onTap: (currentImage != null && Responsive.isPhone(context))
                  ? () => FullscreenImageViewer.show(context, currentImage)
                  : null,
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
                            // Centered when there's room; on very short preview
                            // heights (e.g. a phone held in landscape) the
                            // message scrolls instead of overflowing the canvas.
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: colors.surface
                                                .withValues(alpha: 0.8),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: colors.border),
                                          ),
                                          child: Icon(
                                            NightshadeIcons.camera,
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
                                            fontSize:
                                                NightshadeTypography.fontSize18,
                                            fontWeight: FontWeight.w600,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          isConnected
                                              ? 'Take a snapshot or start a capture loop'
                                              : 'Connect a camera in Equipment settings',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize:
                                                NightshadeTypography.fontSize13,
                                            color: colors.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
                            if (currentImage.rawLoadStatus !=
                                RawLoadStatus.idle)
                              RawPreviewStatusBadge(
                                status: currentImage.rawLoadStatus,
                                colors: colors,
                              ),
                            if (currentImage.rawLoadStatus !=
                                RawLoadStatus.idle)
                              const SizedBox(width: 6),
                            // Surface whether the on-disk frame
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

                    // Top-right science chrome column: the Night Narrator
                    // ticker (surface #2) over the Science HUD panel. Both fade
                    // with the rest of the corner readouts on idle. The ticker
                    // self-gates (hidden when sessionless or the feed is empty)
                    // and the HUD self-gates on advanced mode, so this column
                    // occupies zero height until there is something to show and
                    // the two stack without overlapping when both are present.
                    Positioned(
                      top: 56,
                      right: 16,
                      child: _fadeChrome(
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: Responsive.previewOverlayMaxWidth(
                              viewportSize.width,
                            ),
                            maxHeight: (viewportSize.height - 72)
                                .clamp(120.0, viewportSize.height),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const NarratorTicker(),
                              if (scienceSettings.advancedModeEnabled &&
                                  scienceMode.scienceHudVisible) ...[
                                const SizedBox(
                                    height: NightshadeTokens.spaceSm),
                                Flexible(
                                  child: SingleChildScrollView(
                                    child: ScienceHudPanel(colors: colors),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom-left histogram overlay
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: _fadeChrome(
                        HistogramWidget(
                          key: ImagingTutorialKeys.histogram,
                          colors: colors,
                          histogram: previewHistogram,
                        ),
                      ),
                    ),

                    // Bottom-right stats readout
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: _fadeChrome(
                        ImageStatsOverlay(
                          key: ImagingTutorialKeys.statsPanel,
                          colors: colors,
                          stats: lastStats,
                        ),
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
                        child: _fadeChrome(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const GuidingActiveChip(),
                              const SizedBox(height: NightshadeTokens.spaceXs),
                              SubQualityBadge(eccentricity: frameEccentricity),
                            ],
                          ),
                        ),
                      ),

                    // Mini annotation object chips (top, below overlay bar)
                    if (currentImage != null)
                      Positioned(
                        top: 44,
                        left: 8,
                        right: 8,
                        child: _fadeChrome(AnnotationMiniChips(colors: colors)),
                      ),

                    // Annotation status indicator (top left, below the overlay bar + chips)
                    if (currentImage != null)
                      Positioned(
                        top: 72,
                        left: 16,
                        child: _fadeChrome(
                          Column(
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
                                child:
                                    ReAnnotateSuggestionBanner(colors: colors),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Custom annotation drawing palette — docked bottom-centre
                    // just above the bottom histogram/stats strip, and shown
                    // ONLY while annotate/draw mode is active so it never floats
                    // over an idle frame. Opened via the off-canvas toolbar's
                    // "Annotate" toggle.
                    if (currentImage != null &&
                        ref.watch(customAnnotationDrawModeActiveProvider))
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
          ),
        );
      },
    );
  }
}
