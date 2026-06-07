import 'dart:math' as math;
import 'dart:ui' show FrameTiming, FramePhase;
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../coordinate_system.dart';
import '../celestial_object.dart';
import '../catalogs/constellation_data.dart';
import '../catalogs/satellite_catalog.dart';
import '../catalogs/variable_star_catalog.dart';
import '../catalogs/minor_planet_catalog.dart';
import '../astronomy/astronomy_calculations.dart';
import '../astronomy/planetary_positions.dart';
import '../astronomy/milky_way_data.dart';
import '../rendering/sky_renderer.dart';
import '../rendering/render_quality.dart';
import '../providers/performance_providers.dart';
import '../providers/planetarium_providers.dart';
import '../providers/satellite_providers.dart';
import '../providers/variable_star_providers.dart';
import '../providers/minor_planet_providers.dart';

part 'interactive_sky_view/fov_overlay_painter.dart';
part 'interactive_sky_view/toolbar.dart';

/// Interactive sky view widget with pan, zoom, and object selection
class InteractiveSkyView extends ConsumerStatefulWidget {
  /// Callback when an object is selected
  final ValueChanged<CelestialObject?>? onObjectSelected;

  /// Callback when coordinates are tapped
  final ValueChanged<CelestialCoordinate>? onCoordinateTapped;

  /// Callback when an object is tapped with position info for popup display
  final void Function(CelestialObject? object, CelestialCoordinate coordinates,
      Offset screenPosition)? onObjectTapped;

  /// Whether to show the FOV indicator
  final bool showFOV;

  /// Custom FOV rectangle (if not using equipment provider)
  final (double width, double height)? customFOV;

  /// FOV center coordinate (if different from view center)
  final CelestialCoordinate? fovCenter;

  /// Set of catalog IDs/names for objects that have been observed.
  /// A small green indicator is drawn on matching DSOs in the sky view.
  final Set<String> observedObjectIds;

  /// Set of catalog IDs/names for objects in user observing lists.
  /// A small amber bookmark is drawn on matching DSOs in the sky view.
  final Set<String> listedObjectIds;

  /// Bortle dark-sky scale (1-9). Controls light pollution dome intensity.
  final int bortleClass;

  /// Pre-computed horizon altitudes for each degree of azimuth (0-359).
  /// When non-null, the ground plane follows this custom horizon profile.
  final List<double>? horizonAltitudes;

  const InteractiveSkyView({
    super.key,
    this.onObjectSelected,
    this.onCoordinateTapped,
    this.onObjectTapped,
    this.showFOV = false,
    this.customFOV,
    this.fovCenter,
    this.observedObjectIds = const {},
    this.listedObjectIds = const {},
    this.bortleClass = 5,
    this.horizonAltitudes,
  });

  @override
  ConsumerState<InteractiveSkyView> createState() => _InteractiveSkyViewState();
}

class _InteractiveSkyViewState extends ConsumerState<InteractiveSkyView>
    with TickerProviderStateMixin {
  Offset? _lastFocalPoint;
  double? _lastScale;

  // Smooth zoom animation
  late AnimationController _zoomController;
  Animation<double>? _zoomAnimation;
  double _targetFOV = 60.0;
  double _startFOV = 60.0;

  // Star twinkle animation
  AnimationController? _twinkleController;

  // Selection pulse animation
  late AnimationController _selectionController;
  CelestialCoordinate? _lastSelection;

  // Panning momentum.
  //
  // Momentum is integrated by a per-frame ticker rather than a fixed-duration
  // AnimationController curve: on each tick the live velocity (px/s) is applied
  // for the real elapsed dt and then exponentially decayed. This avoids the
  // stutter of the old approach (which multiplied a constant velocity by a
  // 1-t ramp on a fixed 800ms timeline, giving uneven motion at low frame
  // rates and an abrupt stop at the end).
  late final Ticker _momentumTicker;
  Offset _panVelocity = Offset.zero;
  Duration _lastMomentumElapsed = Duration.zero;
  final List<_PanSample> _panSamples = [];

  /// Velocity (px/s) below which momentum is considered finished and the ticker
  /// stops. Keeps the glide from creeping indefinitely.
  static const double _momentumStopSpeed = 8.0;

  /// Exponential velocity decay per second. At 4.0 the speed falls to ~1.8% of
  /// its initial value after one second — a natural, quick-settling glide.
  static const double _momentumDecayPerSecond = 4.0;

  /// Minimum fling speed (px/s) required to start a momentum glide at all.
  static const double _momentumMinLaunchSpeed = 120.0;

  // Star pop-in animation (tracks previous magnitude threshold)
  double _previousMagLimit = 6.0;
  late AnimationController _popinController;

  // DSO pop-in animation (tracks previous DSO magnitude threshold)
  double _previousDsoMagLimit = 10.0;
  late AnimationController _dsoPopinController;

  // Parallax effect - tracks current pan delta for dim star offset
  Offset _currentPanDelta = Offset.zero;

  // Listenable driving ONLY the animated overlay layer (bright-star twinkle +
  // selection pulse). The static base layer is never a descendant of this, so
  // twinkle/selection ticks repaint only the cheap overlay, never the base.
  late Listenable _overlayAnimations;

  @override
  void initState() {
    super.initState();
    _zoomController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_onZoomAnimation);

    // Twinkle animation cycles every 3 seconds
    // NOTE: We don't start the animation here - it will be started in build
    // if the quality config enables it. This prevents constant repaints when
    // star twinkle is disabled.
    _twinkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    // No setState listener - value read directly via ListenableBuilder

    // Selection pulse animation (cycles every 1.5 seconds)
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    // No setState listener - value read directly via ListenableBuilder

    // Momentum glide ticker — integrates velocity per real frame (see
    // _onMomentumTick). Started on a fling, stopped when the speed decays
    // below _momentumStopSpeed or a new touch cancels it.
    _momentumTicker = createTicker(_onMomentumTick);

    // Star pop-in animation (600ms with elastic out)
    _popinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // No setState listener - value read directly via ListenableBuilder

    // DSO pop-in animation (300ms smooth fade/scale)
    _dsoPopinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // No setState listener - value read directly via ListenableBuilder

    // The overlay layer animates the bright-star twinkle (continuous, ~20Hz
    // effective after quantization) and the selection pulse (transient). Both
    // drive ONLY the overlay's ListenableBuilder.
    _overlayAnimations = Listenable.merge([
      _twinkleController,
      _selectionController,
    ]);

    // Record frame timings for FPS/quality diagnostics.
    SchedulerBinding.instance.addTimingsCallback(_handleFrameTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _zoomController.dispose();
    _twinkleController?.dispose();
    _selectionController.dispose();
    _momentumTicker.dispose();
    _popinController.dispose();
    _dsoPopinController.dispose();
    super.dispose();
  }

  void _handleFrameTimings(List<FrameTiming> timings) {
    final monitor = ref.read(performanceMonitorProvider);
    for (final timing in timings) {
      final buildMs = timing.buildDuration.inMicroseconds / 1000;
      final rasterMs = timing.rasterDuration.inMicroseconds / 1000;
      final vsyncStart = timing.timestampInMicroseconds(FramePhase.vsyncStart);
      final rasterFinish =
          timing.timestampInMicroseconds(FramePhase.rasterFinish);
      final totalMs = rasterFinish > vsyncStart
          ? (rasterFinish - vsyncStart) / 1000
          : buildMs + rasterMs;
      monitor.recordFrameTimings(
        buildMs: buildMs,
        rasterMs: rasterMs,
        totalMs: totalMs,
      );
    }
  }

  void _onZoomAnimation() {
    if (_zoomAnimation != null) {
      final newFOV = _zoomAnimation!.value;
      ref.read(skyViewStateProvider.notifier).setFieldOfView(newFOV);

      // Trigger star pop-in animation when zooming reveals fainter stars
      final qualityConfig = ref.read(fovAdaptiveQualityProvider);
      if (qualityConfig.enableStarPopin) {
        // Estimate new magnitude limit based on FOV
        // Wider FOV = lower mag limit, narrower FOV = higher mag limit
        final newMagLimit = 6.0 + (60.0 - newFOV).clamp(0.0, 54.0) / 6.0;
        if (newMagLimit > _previousMagLimit + 0.5) {
          // Zooming in revealed fainter stars - trigger pop-in
          _popinController.forward(from: 0.0);
        }
        _previousMagLimit = newMagLimit;
      }

      // Trigger DSO pop-in animation when zooming reveals fainter DSOs
      if (qualityConfig.enableDsoPopin) {
        // DSOs have a different magnitude range, typically visible to mag ~14
        // Estimate new DSO mag limit based on FOV
        final newDsoMagLimit = 10.0 + (60.0 - newFOV).clamp(0.0, 54.0) / 12.0;
        if (newDsoMagLimit > _previousDsoMagLimit + 0.3) {
          // Zooming in revealed fainter DSOs - trigger pop-in
          _dsoPopinController.forward(from: 0.0);
        }
        _previousDsoMagLimit = newDsoMagLimit;
      }
    }
  }

  /// Per-frame momentum integration.
  ///
  /// [elapsed] is the total time the ticker has run. We derive the real frame
  /// dt from it, translate the view by `velocity * dt` (same px→RA/Dec
  /// conversion the live drag uses), then exponentially decay the velocity by
  /// `dt`. Integrating against the true dt makes the glide frame-rate
  /// independent and smooth; decaying continuously (rather than ramping over a
  /// fixed timeline) removes the abrupt end-of-animation stop.
  void _onMomentumTick(Duration elapsed) {
    if (!mounted) {
      _momentumTicker.stop();
      return;
    }

    final dtMicros =
        elapsed.inMicroseconds - _lastMomentumElapsed.inMicroseconds;
    _lastMomentumElapsed = elapsed;
    if (dtMicros <= 0) return;
    final dt = dtMicros / 1e6;

    final viewState = ref.read(skyViewStateProvider);
    final panScale = viewState.fieldOfView / 500;

    // Pixel translation this frame from the current velocity (px/s).
    final pixelDelta = _panVelocity * dt;
    ref.read(skyViewStateProvider.notifier).pan(
          -pixelDelta.dx * panScale / 15,
          pixelDelta.dy * panScale,
        );

    // Exponential decay: v *= e^(-decay * dt).
    final decay = math.exp(-_momentumDecayPerSecond * dt);
    _panVelocity = _panVelocity * decay;

    if (_panVelocity.distance < _momentumStopSpeed) {
      _stopMomentum();
    }
  }

  /// Stop and reset the momentum glide.
  void _stopMomentum() {
    if (_momentumTicker.isActive) {
      _momentumTicker.stop();
    }
    _panVelocity = Offset.zero;
    _lastMomentumElapsed = Duration.zero;
  }

  /// Calculate pan velocity from recent samples
  Offset _calculatePanVelocity() {
    if (_panSamples.length < 2) return Offset.zero;

    // Use last few samples for velocity calculation
    final recent = _panSamples.length > 5
        ? _panSamples.sublist(_panSamples.length - 5)
        : _panSamples;

    if (recent.length < 2) return Offset.zero;

    // Calculate average velocity from recent samples
    var totalVelocity = Offset.zero;
    for (var i = 1; i < recent.length; i++) {
      final dt = recent[i]
          .time
          .difference(recent[i - 1].time)
          .inMilliseconds
          .toDouble();
      if (dt > 0) {
        final delta = recent[i].position - recent[i - 1].position;
        totalVelocity += delta / dt * 1000; // pixels per second
      }
    }

    return totalVelocity / (recent.length - 1).toDouble();
  }

  /// Animate FOV to a new target value
  void _animateZoom(double newFOV) {
    final currentFOV = ref.read(skyViewStateProvider).fieldOfView;
    _startFOV = currentFOV;
    _targetFOV = newFOV.clamp(1.0, 180.0);

    _zoomAnimation = Tween<double>(
      begin: _startFOV,
      end: _targetFOV,
    ).animate(CurvedAnimation(
      parent: _zoomController,
      curve: Curves.easeOutCubic,
    ));

    _zoomController.forward(from: 0.0);
  }

  /// Map provider mount status to renderer mount status
  MountRenderStatus _mapMountStatus(MountTrackingStatus status) {
    return switch (status) {
      MountTrackingStatus.disconnected => MountRenderStatus.disconnected,
      MountTrackingStatus.parked => MountRenderStatus.parked,
      MountTrackingStatus.slewing => MountRenderStatus.slewing,
      MountTrackingStatus.tracking => MountRenderStatus.tracking,
      MountTrackingStatus.stopped => MountRenderStatus.stopped,
    };
  }

  @override
  Widget build(BuildContext context) {
    final viewState = ref.watch(skyViewStateProvider);
    final renderConfig = ref.watch(effectiveSkyRenderConfigProvider);
    final location = ref.watch(observerLocationProvider);
    // Use minute-precision time for rendering to avoid rebuilds every second
    // The sky doesn't visibly change in one second, but rebuilding 60x/min hurts performance
    final observationMinute = ref.watch(observationMinuteProvider);
    final selectedObject = ref.watch(selectedObjectProvider);
    final stars = ref.watch(fovFilteredStarsProvider);
    final dsos = ref.watch(fovFilteredDsosProvider);
    final constellations = ref.watch(constellationDataProvider);
    final equipmentFOV = ref.watch(equipmentFOVProvider);
    final mountPosition = ref.watch(mountPositionProvider);
    final sunPos = ref.watch(sunPositionProvider);
    final moonPos = ref.watch(moonPositionProvider);
    final moonIllumination = ref.watch(moonInfoProvider);
    final planets = ref.watch(planetPositionsProvider);
    final milkyWayPoints = ref.watch(milkyWayPointsProvider);
    final qualityConfig = ref.watch(fovAdaptiveQualityProvider);
    final densityHotspots = ref.watch(densityHotspotsProvider);
    final satellites = ref.watch(currentSatellitesProvider);
    final variableStars = ref.watch(variableStarDataProvider);
    final minorPlanets = ref.watch(currentMinorPlanetsProvider);

    // Handle selection animation
    if (qualityConfig.enableSelectionAnimation) {
      if (selectedObject.coordinates != _lastSelection) {
        _lastSelection = selectedObject.coordinates;
        if (selectedObject.coordinates != null) {
          // Start pulsing animation for new selection
          _selectionController.repeat();
        } else {
          // Stop animation when deselected
          _selectionController.stop();
          _selectionController.reset();
        }
      }
    }

    // Handle star twinkle animation - only run when enabled in quality config
    if (qualityConfig.animateStarTwinkle) {
      if (!_twinkleController!.isAnimating) {
        _twinkleController!.repeat();
      }
    } else {
      if (_twinkleController!.isAnimating) {
        _twinkleController!.stop();
        _twinkleController!.reset();
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              final currentFOV = ref.read(skyViewStateProvider).fieldOfView;
              // Determine zoom factor (faster at wide FOV, finer at narrow FOV)
              final zoomFactor = currentFOV > 30 ? 1.2 : 1.15;

              if (event.scrollDelta.dy > 0) {
                // Zoom out
                _animateZoom(currentFOV * zoomFactor);
              } else {
                // Zoom in
                _animateZoom(currentFOV / zoomFactor);
              }
            }
          },
          child: GestureDetector(
            onScaleStart: (details) {
              // A new touch always cancels any in-flight momentum glide.
              _stopMomentum();
              _lastFocalPoint = details.focalPoint;
              _lastScale = 1.0;
              _panSamples.clear();
              _panSamples.add(_PanSample(details.focalPoint, DateTime.now()));
            },
            onScaleUpdate: (details) {
              final viewNotifier = ref.read(skyViewStateProvider.notifier);

              // Distinguish a pinch-zoom from a one-finger drag.
              //
              // On a touchpad the focal point drifts during a pinch, so
              // treating the focal-point delta as a pan (as v1 did) drags the
              // sky around while zooming. We therefore PAN only for a genuine
              // single-pointer drag, and ZOOM-ONLY for a pinch — identified by
              // either a second pointer being down OR the scale meaningfully
              // departing from 1.0 (covers touchpads that report pointerCount
              // == 1 for a two-finger pinch).
              const double pinchScaleEpsilon = 0.01;
              final isPinch = details.pointerCount >= 2 ||
                  (details.scale - 1.0).abs() > pinchScaleEpsilon;

              // Pan — single-finger drag only.
              if (!isPinch && _lastFocalPoint != null) {
                final delta = details.focalPoint - _lastFocalPoint!;
                final panScale = viewState.fieldOfView / 500;
                viewNotifier.pan(
                  -delta.dx * panScale / 15, // Convert to hours
                  delta.dy * panScale,
                );

                // Track pan delta for parallax effect (decays over time).
                // No setState needed: the viewState change from pan() above
                // already triggers a rebuild via ref.watch(skyViewStateProvider).
                _currentPanDelta = delta;

                // Track pan samples for momentum (fling) velocity.
                _panSamples.add(_PanSample(details.focalPoint, DateTime.now()));
                if (_panSamples.length > 10) {
                  _panSamples.removeAt(0);
                }
              } else if (isPinch) {
                // During a pinch the focal point is unreliable; do NOT carry it
                // into a pan and do NOT feed it to the momentum sampler. We keep
                // _lastFocalPoint tracking the focal point so that if the user
                // lifts one finger and continues a one-finger drag, the next pan
                // delta is measured from the current focal point (no jump), but
                // we clear the fling samples so a pinch never launches momentum.
                _panSamples.clear();
              }
              // Always advance the focal-point reference so a drag resuming
              // after a pinch measures from the correct anchor.
              _lastFocalPoint = details.focalPoint;

              // Zoom — apply for any real scale change (pinch). Zoom about the
              // focal point is left to the projection's view center; we only
              // change the field of view here so a pinch zooms in place without
              // translating the sky.
              if (_lastScale != null && details.scale != 1.0) {
                final scaleDelta = _lastScale! / details.scale;
                final newFOV =
                    (viewState.fieldOfView * scaleDelta).clamp(1.0, 180.0);
                viewNotifier.setFieldOfView(newFOV);
                _lastScale = details.scale;
              }
            },
            onScaleEnd: (_) {
              // Launch a momentum glide only for a real one-finger fling. The
              // pinch path clears _panSamples, so a pinch-release yields zero
              // velocity here and never glides.
              _panVelocity = _calculatePanVelocity();
              if (_panVelocity.distance > _momentumMinLaunchSpeed) {
                _lastMomentumElapsed = Duration.zero;
                _momentumTicker.start();
              } else {
                _panVelocity = Offset.zero;
              }

              // Reset parallax delta. No setState needed: momentum animation
              // or next user interaction will trigger rebuilds.
              _currentPanDelta = Offset.zero;

              _lastFocalPoint = null;
              _lastScale = null;
              _panSamples.clear();
            },
            onTapDown: (_) {
              // A tap is a new touch — cancel any in-flight momentum glide so
              // the view holds still under the finger.
              _stopMomentum();
            },
            onDoubleTapDown: (details) {
              // Zoom in 2x centered on the double-tap position
              _stopMomentum();
              _handleDoubleTapZoom(details.localPosition,
                  Size(constraints.maxWidth, constraints.maxHeight));
            },
            onTapUp: (details) {
              _handleTap(details.localPosition,
                  Size(constraints.maxWidth, constraints.maxHeight));
            },
            // Two RepaintBoundary-isolated layers in a Stack:
            //
            // - BASE layer (bottom): the expensive, non-animated content —
            //   background, Milky Way, grids, constellations, DSOs, dim+medium
            //   stars, solar-system bodies, satellites, labels and the static
            //   mount marker, plus the FOV foreground overlay. It is built
            //   directly in this `build()` and is NOT a descendant of the
            //   twinkle/selection ListenableBuilder, so animation ticks never
            //   rebuild or repaint it. Its painter's shouldRepaint returns
            //   false for twinkle/selection/pop-in and true only for real
            //   changes (pose, minute, config, catalog, mount).
            //
            // - OVERLAY layer (top): only the cheap animated bits — the
            //   bright-star (twinkle) pass and the selection pulse ring. It is
            //   wrapped in a ListenableBuilder driven by the twinkle and
            //   selection controllers so ONLY this layer rebuilds at animation
            //   cadence. A static view therefore paints the base once and then
            //   idles, with just a handful of bright stars + the selection ring
            //   repainting at ~20Hz.
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  // The base layer is driven only by the DSO pop-in controller
                  // (a brief ~300ms transient after a zoom reveals fainter
                  // DSOs, which scale on the base layer). It is NOT driven by
                  // the twinkle/selection controllers, so those animations
                  // never rebuild or repaint the base. When idle the pop-in
                  // controller is stopped (value pinned at 1.0) so it issues no
                  // ticks and the base stays static.
                  child: ListenableBuilder(
                    listenable: _dsoPopinController,
                    builder: (context, child) {
                      return ClipRect(
                        child: CustomPaint(
                          painter: _buildSkyPainter(
                            scope: SkyRenderScope.base,
                            viewState: viewState,
                            renderConfig: renderConfig,
                            qualityConfig: qualityConfig,
                            stars: stars.valueOrNull ?? const [],
                            dsos: dsos.valueOrNull ?? const [],
                            constellations: constellations,
                            observationMinute: observationMinute,
                            location: location,
                            selectedObject: selectedObject,
                            mountPosition: mountPosition,
                            sunPos: sunPos,
                            moonPos: moonPos,
                            moonIllumination: moonIllumination,
                            planets: planets,
                            satellites: satellites,
                            variableStars: variableStars,
                            minorPlanets: minorPlanets,
                            milkyWayPoints: milkyWayPoints,
                            densityHotspots: densityHotspots,
                          ),
                          foregroundPainter: widget.showFOV
                              ? _FOVOverlayPainter(
                                  viewState: viewState,
                                  fovWidth: widget.customFOV?.$1 ??
                                      equipmentFOV.fov?.$1,
                                  fovHeight: widget.customFOV?.$2 ??
                                      equipmentFOV.fov?.$2,
                                  fovCenter: widget.fovCenter,
                                  rotation: equipmentFOV.rotation,
                                )
                              : null,
                          size: Size.infinite,
                        ),
                      );
                    },
                  ),
                ),
                RepaintBoundary(
                  child: ListenableBuilder(
                    listenable: _overlayAnimations,
                    builder: (context, child) {
                      return ClipRect(
                        child: CustomPaint(
                          painter: _buildSkyPainter(
                            scope: SkyRenderScope.overlay,
                            viewState: viewState,
                            renderConfig: renderConfig,
                            qualityConfig: qualityConfig,
                            stars: stars.valueOrNull ?? const [],
                            dsos: dsos.valueOrNull ?? const [],
                            constellations: constellations,
                            observationMinute: observationMinute,
                            location: location,
                            selectedObject: selectedObject,
                            mountPosition: mountPosition,
                            sunPos: sunPos,
                            moonPos: moonPos,
                            moonIllumination: moonIllumination,
                            planets: planets,
                            satellites: satellites,
                            variableStars: variableStars,
                            minorPlanets: minorPlanets,
                            milkyWayPoints: milkyWayPoints,
                            densityHotspots: densityHotspots,
                          ),
                          size: Size.infinite,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build a [SkyCanvasPainter] for one render layer (base or overlay).
  ///
  /// Animation phases are read live from the controllers and routed by scope so
  /// each layer only carries the phases it actually renders:
  /// * twinkle phase — only the overlay (it owns the bright-star pass);
  /// * selection pulse phase — only the overlay (it owns the selection ring);
  /// * DSO pop-in phase — only the base (DSOs scale on the base layer);
  /// * parallax pan delta — only the base (dim stars live on the base layer).
  SkyCanvasPainter _buildSkyPainter({
    required SkyRenderScope scope,
    required SkyViewState viewState,
    required SkyRenderConfig renderConfig,
    required RenderQualityConfig qualityConfig,
    required List<Star> stars,
    required List<DeepSkyObject> dsos,
    required List<ConstellationData> constellations,
    required DateTime observationMinute,
    required PlanetariumObserver location,
    required SelectedObjectState selectedObject,
    required MountPositionState mountPosition,
    required (double, double) sunPos,
    required (double, double, double) moonPos,
    required MoonTimes moonIllumination,
    required List<PlanetData> planets,
    required List<SatelliteData> satellites,
    required List<VariableStarData> variableStars,
    required List<MinorBodyData> minorPlanets,
    required List<MilkyWayPoint>? milkyWayPoints,
    required List<(double, double, int, int)> densityHotspots,
  }) {
    final isOverlay = scope == SkyRenderScope.overlay;
    final isBase = scope == SkyRenderScope.base;
    return SkyCanvasPainter(
      renderScope: scope,
      viewState: viewState,
      config: renderConfig,
      qualityConfig: qualityConfig,
      stars: stars,
      dsos: dsos,
      constellations: constellations,
      observationTime: observationMinute,
      latitude: location.latitude,
      longitude: location.longitude,
      selectedObject: selectedObject.coordinates,
      mountPosition: mountPosition.coordinates,
      mountStatus: _mapMountStatus(mountPosition.status),
      sunPosition: sunPos,
      moonPosition: (
        moonPos.$1,
        moonPos.$2,
        moonIllumination.illumination,
      ),
      planets: planets,
      satellites: satellites,
      variableStars: variableStars,
      minorPlanets: minorPlanets,
      milkyWayPoints: milkyWayPoints,
      // Twinkle + selection drive the overlay only.
      animationPhase: (isOverlay && qualityConfig.animateStarTwinkle)
          ? _twinkleController?.value
          : null,
      selectionAnimationPhase:
          (isOverlay && qualityConfig.enableSelectionAnimation)
              ? _selectionController.value
              : null,
      // DSO pop-in + parallax drive the base only.
      popinAnimationPhase: (isBase && qualityConfig.enableStarPopin)
          ? _popinController.value
          : null,
      dsoPopinAnimationPhase: (isBase && qualityConfig.enableDsoPopin)
          ? _dsoPopinController.value
          : null,
      parallaxPanDelta:
          (isBase && qualityConfig.enableParallax) ? _currentPanDelta : null,
      densityHotspots: densityHotspots,
      observedObjectIds: widget.observedObjectIds,
      listedObjectIds: widget.listedObjectIds,
      bortleClass: widget.bortleClass,
      horizonAltitudes: widget.horizonAltitudes,
    );
  }

  /// Handle double-tap: reset the view to the default 60 degree field of view.
  void _handleDoubleTapZoom(Offset position, Size size) {
    final viewState = ref.read(skyViewStateProvider);

    // Convert tap position to celestial coordinates
    final coord = _screenToCelestial(position, size, viewState);
    if (coord == null) return;

    // Re-center the view on the tapped coordinate
    ref.read(skyViewStateProvider.notifier).setCenter(coord.ra, coord.dec);

    _animateZoom(60.0);
  }

  void _handleTap(Offset position, Size size) {
    final viewState = ref.read(skyViewStateProvider);

    // Convert screen position to celestial coordinates
    final coord = _screenToCelestial(position, size, viewState);
    if (coord == null) return;

    // Notify coordinate tap
    widget.onCoordinateTapped?.call(coord);

    // Try to find a nearby object using FOV-filtered objects (same as rendering)
    final stars = ref.read(fovFilteredStarsProvider).valueOrNull ?? [];
    final dsos = ref.read(fovFilteredDsosProvider).valueOrNull ?? [];

    CelestialObject? nearestObject;
    double nearestDistance = double.infinity;

    // Minimum hit radius in screen pixels - ensures all objects are tappable
    const double minHitRadiusPixels = 8.0;

    // Calculate scale factor for converting degrees to screen pixels
    final scale =
        math.min(size.width, size.height) / 2 / (viewState.fieldOfView / 2);

    // Convert min hit radius from pixels to degrees for angular comparison
    final minHitRadiusDegrees = minHitRadiusPixels / scale;

    for (final star in stars) {
      final distance = _angularDistance(coord, star.coordinates);

      // Calculate hit radius based on magnitude
      // Brighter stars (lower magnitude) get larger hit targets
      final starMag = star.magnitude ?? 6.0;

      // Base radius scales with brightness: mag -1 = 3x, mag 0 = 2.5x, mag 2 = 2x, mag 6 = 1x
      final brightnessMultiplier = math.max(1.0, 2.5 - (starMag / 4.0));
      final hitRadiusDegrees = math.max(
          minHitRadiusDegrees, minHitRadiusDegrees * brightnessMultiplier);

      if (distance < hitRadiusDegrees && distance < nearestDistance) {
        nearestDistance = distance;
        nearestObject = star;
      }
    }

    for (final dso in dsos) {
      final distance = _angularDistance(coord, dso.coordinates);

      // DSOs get hitbox based on their actual angular size
      final dsoSizeDeg = (dso.sizeArcMin ?? 5.0) / 60.0;

      // Brighter DSOs (lower magnitude) get larger hit targets
      final dsoMag = dso.magnitude ?? 10.0;
      final brightnessMultiplier = math.max(1.0, 2.0 - (dsoMag / 10.0));

      // Use at least minHitRadius, or half the object's angular size (whichever is larger)
      // Then apply brightness multiplier
      final baseRadius = math.max(minHitRadiusDegrees, dsoSizeDeg * 0.5);
      final hitRadiusDegrees = baseRadius * brightnessMultiplier;

      if (distance < hitRadiusDegrees && distance < nearestDistance) {
        nearestDistance = distance;
        nearestObject = dso;
      }
    }

    // Hit-test satellites: check if the tap landed near a rendered satellite
    final satellites = ref.read(currentSatellitesProvider);
    // Satellites are rendered as small dots (radius ~2.5-4px), use generous hit area
    const double satelliteHitRadiusPixels = 12.0;
    final satelliteHitRadiusDegrees = satelliteHitRadiusPixels / scale;

    for (final sat in satellites) {
      final satCoord = CelestialCoordinate(ra: sat.ra, dec: sat.dec);
      final distance = _angularDistance(coord, satCoord);

      if (distance < satelliteHitRadiusDegrees && distance < nearestDistance) {
        nearestDistance = distance;
        // Create a CelestialObject for the satellite so it can be displayed
        // in the popup. We use a Star object as the closest match since satellites
        // are point sources. The name, coordinates, and magnitude are the key fields.
        nearestObject = Star(
          id: 'SAT_${sat.catalogNumber}',
          name: sat.name,
          coordinates: satCoord,
          magnitude: null, // Satellites don't have a fixed magnitude
          spectralType: null,
        );
      }
    }

    // Hit-test planets: check if the tap landed near a rendered planet
    final planets = ref.read(planetPositionsProvider);
    const double planetHitRadiusPixels = 14.0;
    final planetHitRadiusDegrees = planetHitRadiusPixels / scale;

    for (final planet in planets) {
      final planetCoord = CelestialCoordinate(ra: planet.ra, dec: planet.dec);
      final distance = _angularDistance(coord, planetCoord);

      if (distance < planetHitRadiusDegrees && distance < nearestDistance) {
        nearestDistance = distance;
        nearestObject = Star(
          id: 'PLANET_${planet.name}',
          name: planet.name,
          coordinates: planetCoord,
          magnitude: planet.magnitude,
          spectralType: null,
        );
      }
    }

    if (nearestObject != null) {
      ref.read(selectedObjectProvider.notifier).selectObject(nearestObject);
      widget.onObjectSelected?.call(nearestObject);
    } else {
      ref.read(selectedObjectProvider.notifier).selectCoordinates(coord);
      widget.onObjectSelected?.call(null);
    }

    // Always call the position callback for popup handling
    widget.onObjectTapped?.call(nearestObject, coord, position);
  }

  CelestialCoordinate? _screenToCelestial(
      Offset position, Size size, SkyViewState viewState) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale =
        math.min(size.width, size.height) / 2 / (viewState.fieldOfView / 2);

    // Offset from center in screen pixels
    final dx = -(position.dx - center.dx) / scale;
    final dy = -(position.dy - center.dy) / scale;

    // Reverse rotation
    final rotRad = -viewState.rotation * math.pi / 180;
    final x = dx * math.cos(rotRad) - dy * math.sin(rotRad);
    final y = dx * math.sin(rotRad) + dy * math.cos(rotRad);

    if (viewState.viewMode == SkyViewMode.horizontal) {
      // Invert the horizontal-mode projection: the forward path maps
      // (-azimuth, altitude) through the stereographic projector, so undo it to
      // (alt, az) then convert back to equatorial RA/Dec for the caller.
      final location = ref.read(observerLocationProvider);
      final time = ref.read(observationTimeProvider).time;
      final lst =
          AstronomyCalculations.localSiderealTime(time, location.longitude);
      final (lon, lat) = _inverseStereographic(
        x: x,
        y: y,
        centerLonDeg: -viewState.centerAz,
        centerLatDeg: viewState.centerAltitude,
      );
      final az = -lon;
      final (ra, dec) = AstronomyCalculations.horizontalToEquatorial(
        altDeg: lat,
        azDeg: az,
        latitudeDeg: location.latitude,
        lstHours: lst,
      );
      var raHours = ra / 15;
      if (raHours < 0) raHours += 24;
      if (raHours >= 24) raHours -= 24;
      return CelestialCoordinate(ra: raHours, dec: dec.clamp(-90, 90));
    }

    // Convert to RA/Dec (inverse of stereographic projection)
    final (raDeg, decDeg) = _inverseStereographic(
      x: x,
      y: y,
      centerLonDeg: viewState.centerRA * 15,
      centerLatDeg: viewState.centerDec,
    );

    var raHours = raDeg / 15;
    if (raHours < 0) raHours += 24;
    if (raHours >= 24) raHours -= 24;

    return CelestialCoordinate(ra: raHours, dec: decDeg.clamp(-90, 90));
  }

  /// Inverse stereographic projection: screen-space offset ([x], [y], in the
  /// same scaled degree units the forward projector emits) back to a sphere
  /// point (longitude, latitude in degrees) about the projection center.
  ///
  /// Shared by both view modes — equatorial passes RA/Dec as the center,
  /// horizontal passes (-azimuth, altitude) — so the inverse geometry, like the
  /// forward geometry, lives in exactly one place.
  (double lonDeg, double latDeg) _inverseStereographic({
    required double x,
    required double y,
    required double centerLonDeg,
    required double centerLatDeg,
  }) {
    final xRad = x * math.pi / 180;
    final yRad = y * math.pi / 180;
    final centerLonRad = centerLonDeg * math.pi / 180;
    final centerLatRad = centerLatDeg * math.pi / 180;

    final rho = math.sqrt(xRad * xRad + yRad * yRad);
    if (rho < 0.0001) {
      return (centerLonDeg, centerLatDeg);
    }

    final c = 2 * math.atan(rho / 2);
    final sinc = math.sin(c);
    final cosc = math.cos(c);

    final lat = math.asin(cosc * math.sin(centerLatRad) +
        yRad * sinc * math.cos(centerLatRad) / rho);
    final lon = centerLonRad +
        math.atan2(
          xRad * sinc,
          rho * math.cos(centerLatRad) * cosc -
              yRad * math.sin(centerLatRad) * sinc,
        );

    return (lon * 180 / math.pi, lat * 180 / math.pi);
  }

  double _angularDistance(CelestialCoordinate a, CelestialCoordinate b) {
    final ra1 = a.ra * 15 * math.pi / 180;
    final dec1 = a.dec * math.pi / 180;
    final ra2 = b.ra * 15 * math.pi / 180;
    final dec2 = b.dec * math.pi / 180;

    final cosSep = math.sin(dec1) * math.sin(dec2) +
        math.cos(dec1) * math.cos(dec2) * math.cos(ra1 - ra2);

    return math.acos(cosSep.clamp(-1.0, 1.0)) * 180 / math.pi;
  }
}

/// Helper class for tracking pan velocity samples
class _PanSample {
  final Offset position;
  final DateTime time;

  _PanSample(this.position, this.time);
}
