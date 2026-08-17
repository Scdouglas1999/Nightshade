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
import 'frame_science_chip.dart';
import 'fullscreen_image_viewer.dart';
import 'guiding_active_chip.dart';
import 'image_display.dart';
import 'narrator_ticker.dart';
import 'overlay_painters.dart';
import 'overlay_widgets.dart';
import 'preview_display_scale.dart';
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

  /// A manual capture has been asked to stop and the abort has not settled yet.
  /// The progress overlay drops its countdown while this is true — see
  /// [ExposureProgressOverlay.isAborting].
  final bool isStoppingCapture;

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
    required this.isStoppingCapture,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onPanUpdate,
  });

  @override
  ConsumerState<LivePreviewArea> createState() => _LivePreviewAreaState();
}

/// Vertical band at the bottom of the preview canvas owned by the corner
/// readouts (histogram bottom-left, image stats bottom-right). Content centred
/// in the canvas must keep clear of it.
const double _cornerReadoutBandHeight = 120.0;

/// Whether the on-canvas measurement readouts — the histogram, the HFR / ECC /
/// star-count chip and the image-stats panel — are drawn.
///
/// Visibility is explicit and user-owned (Overlays → Readouts), defaulting on:
/// nothing on this canvas disappears because of a timer. A pointer-idle fade
/// would hide these permanently for an unattended run or a remote operator
/// watching over a screen share, who has no local pointer at all.
final previewReadoutsVisibleProvider = StateProvider<bool>((ref) => true);

class _LivePreviewAreaState extends ConsumerState<LivePreviewArea> {
  /// Hand the measured display scale to readers outside this subtree (the
  /// preview toolbar's zoom readout), which cannot see the preview viewport.
  ///
  /// Deferred to a post-frame callback because it is computed inside `build`
  /// and mutating a provider during a build is illegal. The value is a pure
  /// function of the viewport, the frame size and the zoom multiplier, so the
  /// equality guard makes this converge in one extra frame rather than looping.
  void _publishDisplayScale(double scale) {
    if (ref.read(previewDisplayScaleProvider) == scale) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(previewDisplayScaleProvider.notifier).state = scale;
    });
  }

  /// Same contract as [_publishDisplayScale], for the zoom-multiplier-free fit
  /// scale the zoom mutators need to express "1:1" and the absolute zoom
  /// ceiling.
  void _publishFitScale(double scale) {
    if (ref.read(previewFitScaleProvider) == scale) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(previewFitScaleProvider.notifier).state = scale;
    });
  }

  /// Gate a measurement readout on [previewReadoutsVisibleProvider].
  ///
  /// Hidden readouts are removed from the tree rather than made transparent so
  /// they cannot swallow pan / annotation pointer events while invisible.
  Widget _readout(Widget child, {required bool visible}) {
    if (!visible) return const SizedBox.shrink();
    return child;
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
    final readoutsVisible = ref.watch(previewReadoutsVisibleProvider);
    final previewHistogram = ref.watch(previewDisplayHistogramProvider);
    final exposureProgress = ref.watch(exposureProgressProvider);
    final lastStats = ref.watch(lastImageStatsProvider);
    final cameraState = ref.watch(cameraStateProvider);
    final starDetectionResult = ref.watch(starDetectionResultProvider);
    final scienceSettings = ref.watch(scienceSettingsProvider).valueOrNull;
    final scienceVizPrefs =
        ref.watch(scienceVisualizationPrefsProvider).valueOrNull;
    final scienceOverlaysEnabled =
        scienceSettings?.overlayEnabled == true && scienceVizPrefs != null;
    final scienceMode = ref.watch(scienceModeStateProvider);
    final scienceOverlay = ref.watch(scienceOverlayStateProvider);
    final sessionId = ref.watch(sessionStateProvider).dbSessionId;
    final sessionImages = ref.watch(recentSessionFramesProvider);
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
    final annotationSettingsObj = annotationSettingsValue.valueOrNull;
    final gridType = annotationSettingsObj?.gridType ?? GridType.none;
    final annotationShowResiduals =
        annotationSettingsObj?.showSolveResiduals ?? false;
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
        // Screen pixels per IMAGE pixel. `zoomLevel` is only a multiplier on
        // top of fit-to-window, so it is meaningful to [ImageDisplayWidget]
        // (which re-derives fit itself) and to nothing else. Every overlay
        // below maps image coordinates onto this canvas via
        // `computeImageOffset` / `imageToViewport`, whose
        // `scaledSize = imageSize * zoomLevel` is native-scale arithmetic —
        // handing them the raw multiplier spread every marker over
        // `1 / fitScale` times the frame's real footprint (4.2x on a 4144 px
        // sensor in a 990 px viewport), so overlays only landed on their
        // targets at the exact centre of the frame.
        final fitScale = currentImage == null
            ? 1.0
            : previewFitScale(
                viewportSize: viewportSize,
                imageSize: Size(currentImage.width.toDouble(),
                    currentImage.height.toDouble()),
              );
        final displayScale =
            currentImage == null ? zoomLevel : fitScale * zoomLevel;
        _publishDisplayScale(displayScale);
        _publishFitScale(fitScale);
        final imageOffset = currentImage != null
            ? computeImageOffset(
                viewportSize: viewportSize,
                imageSize: Size(currentImage.width.toDouble(),
                    currentImage.height.toDouble()),
                zoomLevel: displayScale,
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
                          // While an exposure is in flight the progress
                          // overlay owns the centre of the canvas, so the
                          // empty state stands down. Drawing both stacked
                          // "32%" on top of "No Image" and told the operator
                          // to "take a snapshot or start a capture loop"
                          // directly above a countdown for the capture already
                          // running.
                          //
                          // Centered when there's room; on very short preview
                          // heights (e.g. a phone held in landscape) the
                          // message scrolls instead of overflowing the canvas.
                          if (!isExposing)
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Center(
                                  child: Padding(
                                    // The bottom corners of this same canvas
                                    // are permanently occupied by the
                                    // histogram and the HFR/Stars/Median/Mean
                                    // readout (both `Positioned(bottom: 16)`).
                                    // Centring the empty state in the FULL
                                    // canvas ran "Take a snapshot or start a
                                    // capture loop" straight through both
                                    // cards — legible neither as prompt nor as
                                    // readout, and worse at a 1.3 system font
                                    // scale where the sentence is wider.
                                    // Reserve the readout band so the prompt
                                    // centres in the space actually free.
                                    padding: const EdgeInsets.fromLTRB(
                                      NightshadeTokens.spaceLg,
                                      NightshadeTokens.spaceLg,
                                      NightshadeTokens.spaceLg,
                                      NightshadeTokens.spaceLg +
                                          _cornerReadoutBandHeight,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(
                                              NightshadeTokens.space2xl),
                                          decoration: BoxDecoration(
                                            color: colors.surface
                                                .withValues(alpha: 0.8),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: colors.border),
                                          ),
                                          child: Icon(
                                            NightshadeIcons.camera,
                                            size: NightshadeTokens.icon2xl,
                                            color: colors.textMuted,
                                          ),
                                        ),
                                        const SizedBox(
                                            height: NightshadeTokens.spaceXl),
                                        Text(
                                          isConnected
                                              ? 'No Image'
                                              : 'No Camera Connected',
                                          style:
                                              NightshadeTypography.h4.copyWith(
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(
                                            height: NightshadeTokens.spaceSm),
                                        Text(
                                          isConnected
                                              ? 'Take a snapshot or start a capture loop'
                                              : 'Connect a camera in Equipment settings',
                                          textAlign: TextAlign.center,
                                          style: NightshadeTypography.bodySm
                                              .copyWith(
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
                            zoomLevel: displayScale,
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
                          zoomLevel: displayScale,
                          imageOffset: imageOffset,
                        ),
                      ),
                    ),

                  // Annotation overlay with fade effects
                  if (currentImage != null)
                    Positioned.fill(
                      child: AnnotationOverlayWrapper(
                        zoomLevel: displayScale,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                        colors: colors,
                        previewViewportWidth: viewportSize.width,
                        onPanToObject: (imagePoint) {
                          // Pan delta that centres the image point in the
                          // PREVIEW, not on the screen: imageToViewport works
                          // in preview-local coordinates, so measuring the
                          // centre off MediaQuery threw the object off by
                          // half the surrounding chrome — the wider the
                          // window, the further the miss.
                          final previewCenter = Offset(
                            viewportSize.width / 2,
                            viewportSize.height / 2,
                          );
                          final currentScreenPos = imageToViewport(
                            imagePoint: imagePoint,
                            imageOffset: imageOffset,
                            zoomLevel: displayScale,
                          );
                          final delta = previewCenter - currentScreenPos;
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
                        zoomLevel: displayScale,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                      ),
                    ),

                  // Custom user-drawn annotations (circles, arrows, text)
                  if (currentImage != null)
                    Positioned.fill(
                      child: CustomAnnotationDrawingLayer(
                        zoomLevel: displayScale,
                        imageOffset: imageOffset,
                        imageSize: Size(currentImage.width.toDouble(),
                            currentImage.height.toDouble()),
                      ),
                    ),

                  // Compass and scale bar overlays (require plate solve data)
                  if (currentImage != null)
                    _CompassScaleBarOverlay(
                      zoomLevel: displayScale,
                      plateSolve: currentSkySolution.plateSolve,
                      readoutsVisible: readoutsVisible,
                    ),

                  if (currentImage != null &&
                      scienceOverlaysEnabled &&
                      scienceOverlay.showPsfHeatmap &&
                      psfTiles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: SciencePsfOverlayPainter(
                            tiles: psfTiles,
                            imageOffset: imageOffset,
                            zoomLevel: displayScale,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            colors: colors,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      residualVectors.isNotEmpty &&
                      (annotationShowResiduals ||
                          (scienceOverlaysEnabled &&
                              scienceOverlay.showResidualVectors)))
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ScienceResidualOverlayPainter(
                            vectors: residualVectors,
                            imageOffset: imageOffset,
                            zoomLevel: displayScale,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceOverlaysEnabled &&
                      scienceOverlay.showUniformityMap &&
                      uniformityTiles.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ScienceUniformityOverlayPainter(
                            tiles: uniformityTiles,
                            imageOffset: imageOffset,
                            zoomLevel: displayScale,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            opacity: scienceVizPrefs.overlayOpacity,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceOverlaysEnabled &&
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
                            zoomLevel: displayScale,
                            imageWidth: currentImage.width.toDouble(),
                            imageHeight: currentImage.height.toDouble(),
                            opacity: scienceVizPrefs.overlayOpacity,
                            colors: colors,
                          ),
                        ),
                      ),
                    ),

                  if (currentImage != null &&
                      scienceOverlaysEnabled &&
                      scienceOverlay.showMovingObjectTracks &&
                      projectedMovingTracks.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: ScienceMovingTrackOverlayPainter(
                              tracks: projectedMovingTracks,
                              imageOffset: imageOffset,
                              zoomLevel: displayScale,
                              colors: colors,
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
                        isAborting: widget.isStoppingCapture,
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
                          // Surface whether the on-disk frame
                          // backing the current preview has actually been
                          // through the calibration pipeline. The provider
                          // only reports true when the saved file path
                          // ended up at `_cal.fits` — calibration failures
                          // leave the original path untouched, so an
                          // uncalibrated frame never wears the badge.
                          _CalibratedBadge(colors: colors),
                        ],
                      ),
                    ),

                  // Top-right science chrome column: the Night Narrator
                  // ticker (surface #2) over the Science HUD panel. Both fade
                  // with the rest of the corner readouts on idle. The ticker
                  // self-gates (hidden when its feed has nothing recent to
                  // say — sessionless manual captures read the sessionless
                  // bucket rather than going dark)
                  // and the HUD self-gates on advanced mode, so this column
                  // occupies zero height until there is something to show and
                  // the two stack without overlapping when both are present.
                  if (viewportSize.height > 120)
                    Positioned(
                      top: 56,
                      right: 16,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: Responsive.previewOverlayMaxWidth(
                            viewportSize.width,
                          ),
                          maxHeight: viewportSize.height - 72,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const NarratorTicker(),
                            if (scienceMode.scienceHudVisible) ...[
                              const SizedBox(height: NightshadeTokens.spaceSm),
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

                  // Bottom-left histogram overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: _readout(
                      HistogramWidget(
                        key: ImagingTutorialKeys.histogram,
                        colors: colors,
                        histogram: previewHistogram,
                      ),
                      visible: readoutsVisible,
                    ),
                  ),

                  // Bottom-right stats readout
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: _readout(
                      ImageStatsOverlay(
                        key: ImagingTutorialKeys.statsPanel,
                        colors: colors,
                        stats: lastStats,
                      ),
                      visible: readoutsVisible,
                    ),
                  ),

                  // Bottom-left at-a-glance quality stack: the tappable
                  // FrameScienceChip over a per-sub quality verdict badge and
                  // a live "Guiding" indicator. The chip leads so its touch
                  // target sits furthest from the bottom-left histogram (which
                  // occupies bottom:16 + 80px height); the whole stack is
                  // anchored a full spaceLg above the histogram top so a long
                  // REJECT verdict never crowds it, and constrained to the same
                  // previewOverlayMaxWidth as the sibling overlays so it can't
                  // run over the bottom-right ImageStatsOverlay. The detailed
                  // ImageStatsOverlay continues to own the bottom-right corner.
                  // All children self-gate on their own providers, so this
                  // region is empty until there is something honest to show.
                  //
                  // Deliberately NOT wrapped in IgnorePointer: the children
                  // expose hover tooltips (GuidingActiveChip's RMS-units note
                  // and SubQualityBadge's reject-reason) that an IgnorePointer
                  // would silently kill. Like the bottom-right ImageStatsOverlay
                  // these are small, non-gesture corner widgets; they absorb the
                  // pointer only within their own compact footprint, matching
                  // that overlay's established pointer behaviour, and the rest
                  // of the canvas keeps its pan/zoom gestures.
                  if (currentImage != null)
                    Positioned(
                      bottom: 112,
                      left: 12,
                      child: _readout(
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: Responsive.previewOverlayMaxWidth(
                              viewportSize.width,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FrameScienceChip(),
                              const SizedBox(height: NightshadeTokens.spaceXs),
                              SubQualityBadge(eccentricity: frameEccentricity),
                              const SizedBox(height: NightshadeTokens.spaceXs),
                              const GuidingActiveChip(),
                            ],
                          ),
                        ),
                        visible: readoutsVisible,
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
                          // Bounded like its sibling banner below: this
                          // Positioned has no `right`, so without a max width
                          // the status card is laid out unconstrained and a
                          // long hint ("install ASTAP or set its path in
                          // Settings to label objects") runs off the viewport
                          // and is clipped mid-word by the Stack.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: Responsive.previewOverlayMaxWidth(
                                viewportSize.width,
                                maxAbsolute: 380,
                              ),
                            ),
                            child: AnnotationStatusIndicator(colors: colors),
                          ),
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
        );
      },
    );
  }
}
