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
import '../providers/deep_star_providers.dart';
import '../providers/satellite_providers.dart';
import '../providers/variable_star_providers.dart';
import '../providers/minor_planet_providers.dart';

part 'interactive_sky_view/fov_overlay_painter.dart';
part 'interactive_sky_view/measurement_overlay_painter.dart';
part 'interactive_sky_view/sky_background_layer.dart';
part 'interactive_sky_view/toolbar.dart';

/// Interactive sky view widget with pan, zoom, and object selection
class InteractiveSkyView extends ConsumerStatefulWidget {
  /// Callback when an object is selected
  final ValueChanged<CelestialObject?>? onObjectSelected;

  /// Callback when coordinates are tapped
  final ValueChanged<CelestialCoordinate>? onCoordinateTapped;

  /// Callback when an object is tapped with position info for popup display.
  ///
  /// `coordinates` is the CATALOG position of `object` whenever the tap hit
  /// one; it falls back to the tapped sky coordinate only for empty sky.
  final void Function(
    CelestialObject? object,
    CelestialCoordinate coordinates,
    Offset screenPosition,
  )?
  onObjectTapped;

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

  /// Set of catalog IDs/names that are targets of the currently loaded
  /// sequence. A small cyan target ring is drawn on matching DSOs, so the sky
  /// shows what tonight's plan is actually pointed at.
  final Set<String> sequencedObjectIds;

  /// Bortle dark-sky scale (1-9). Controls light pollution dome intensity.
  final int bortleClass;

  /// Pre-computed horizon altitudes for each degree of azimuth (0-359).
  /// When non-null, the ground plane follows this custom horizon profile.
  final List<double>? horizonAltitudes;

  /// When true, click-drag measures the angular separation and position angle
  /// between two sky points (drawn as an overlay ruler) instead of panning.
  final bool measurementMode;

  /// An optional layer composited beneath the star field — real sky imagery,
  /// typically, for the narrow fields where the star catalogue runs out.
  ///
  /// See [SkyBackgroundLayer]: the host supplies the widget and states whether
  /// it is currently opaque, and the sky view stops painting its own background
  /// gradient while it is. Null (the default) is the plain star chart.
  final SkyBackgroundLayer? backgroundLayer;

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
    this.sequencedObjectIds = const {},
    this.bortleClass = 5,
    this.horizonAltitudes,
    this.measurementMode = false,
    this.backgroundLayer,
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

  // Smooth fly-to (animated re-center) for search/GoTo actions.
  late AnimationController _flyToController;
  Animation<double>? _flyToRaAnimation;
  Animation<double>? _flyToDecAnimation;
  int? _lastFlyToToken;

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

  /// Speed below which momentum is finished and the ticker stops, as a
  /// FRACTION OF THE VIEW'S SHORT SIDE per second.
  ///
  /// Expressed relatively because a fling's meaning is "how much of the sky did
  /// you throw", not "how many pixels did your finger cover": the same physical
  /// gesture covers 4x the pixels on a 5120-wide window as on a 1280-wide one.
  /// As a fixed px/s threshold this made flings refuse to glide on a large
  /// display and over-glide on a small one. Converted to px/s against the live
  /// canvas by [_momentumSpeedPx].
  static const double _momentumStopFraction = 0.011;

  /// Exponential velocity decay per second. At 4.0 the speed falls to ~1.8% of
  /// its initial value after one second — a natural, quick-settling glide.
  ///
  /// Unitless, so unlike the speed thresholds this is already resolution
  /// independent and deliberately stays a plain constant.
  static const double _momentumDecayPerSecond = 4.0;

  /// Minimum fling speed required to start a glide, as a fraction of the view's
  /// short side per second (see [_momentumStopFraction]).
  static const double _momentumMinLaunchFraction = 0.17;

  /// Convert a view-relative speed [fraction] (short-sides per second) into the
  /// px/s the gesture velocities are measured in.
  double _momentumSpeedPx(double fraction) {
    final size = _lastViewSize;
    final shortSide = size == null
        ? 720.0 // pre-layout fallback; the reference these were tuned at
        : math.min(size.width, size.height);
    return fraction * shortSide;
  }

  // Star pop-in animation (tracks previous magnitude threshold)
  double _previousMagLimit = 6.0;
  late AnimationController _popinController;

  // DSO pop-in animation (tracks previous DSO magnitude threshold)
  double _previousDsoMagLimit = 10.0;
  late AnimationController _dsoPopinController;

  // Parallax effect - tracks current pan delta for dim star offset
  Offset _currentPanDelta = Offset.zero;

  /// Last laid-out canvas size, captured in the [LayoutBuilder] so gesture
  /// handlers that run outside the build (the momentum ticker) can convert
  /// pixels to sky angle with the same scale the painter uses.
  Size? _lastViewSize;

  /// Translate a screen-pixel drag into a view-center move.
  ///
  /// The painter's scale is `min(w, h) / fov` pixels per degree
  /// (see `SkyCanvasPainter._paint`), so degrees-per-pixel is its reciprocal.
  /// This previously used a hardcoded `fov / 500`, which made the sky move at
  /// the wrong speed on every canvas that is not 500px on its short side — the
  /// sky visibly failed to track the pointer.
  ///
  /// The horizontal component is additionally divided by the cosine of the
  /// center's latitude (declination, or altitude in the horizontal frame),
  /// because a degree of longitude subtends `cos(lat)` degrees on the sky.
  /// Without it a horizontal drag crawls near the poles and does nothing at all
  /// at the alt/az zenith, which is where the horizontal frame opens.
  void _panByPixels(Offset deltaPixels, Size size) {
    final viewState = ref.read(skyViewStateProvider);
    final shortSide = math.min(size.width, size.height);
    if (shortSide <= 0) return;
    final degreesPerPixel = viewState.fieldOfView / shortSide;

    final centerLatDeg = viewState.viewMode == SkyViewMode.horizontal
        ? viewState.centerAltitude
        : viewState.centerDec;
    // Clamped so the pole is a fast pivot rather than a division by zero.
    final cosLat = math
        .cos(centerLatDeg * math.pi / 180)
        .abs()
        .clamp(0.05, 1.0);

    ref
        .read(skyViewStateProvider.notifier)
        .pan(
          -deltaPixels.dx * degreesPerPixel / cosLat / 15, // degrees -> hours
          deltaPixels.dy * degreesPerPixel,
        );
  }

  // Angular-measurement tool. Endpoints are stored as celestial coordinates so
  // the ruler stays pinned to the sky under pan/zoom; the overlay re-projects
  // them every paint. Both null when no measurement is active. Driven by
  // setState because the ruler lives on the overlay layer, which rebuilds at
  // animation cadence anyway — the extra setState only marks it dirty.
  CelestialCoordinate? _measureStart;
  CelestialCoordinate? _measureEnd;

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

    // Smooth fly-to glide from search/GoTo. 600ms easeInOutCubic feels like a
    // deliberate camera move rather than a teleport.
    _flyToController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(_onFlyToAnimation);

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

    // Star pop-in animation (600ms with elastic out).
    //
    // Seeded at 1.0 — see the DSO controller below for why the resting value
    // matters.
    _popinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0,
    );
    // No setState listener - value read directly via ListenableBuilder

    // DSO pop-in animation (300ms smooth fade/scale).
    //
    // The resting value MUST be 1.0, not the AnimationController default of
    // `lowerBound` (0.0). The painter reads this controller as "how far
    // through the pop-in are we", and 0.0 means "just started fading in", i.e.
    // every DSO glyph is tinted at alpha 0 and every DSO label is drawn fully
    // transparent. This controller is only ever driven by `forward(from: 0)`
    // when an animated zoom reveals fainter DSOs, so a controller left at its
    // default sat at 0.0 from launch and the entire deep-sky layer — glyphs
    // AND labels — was invisible until (and only until) such a zoom happened.
    _dsoPopinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
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
  void didUpdateWidget(InteractiveSkyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Leaving measurement mode discards any drawn ruler so it doesn't linger
    // over the normal interactive view.
    if (oldWidget.measurementMode &&
        !widget.measurementMode &&
        (_measureStart != null || _measureEnd != null)) {
      _measureStart = null;
      _measureEnd = null;
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_handleFrameTimings);
    _zoomController.dispose();
    _flyToController.dispose();
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
      final rasterFinish = timing.timestampInMicroseconds(
        FramePhase.rasterFinish,
      );
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

    final size = _lastViewSize;
    if (size == null) {
      _stopMomentum();
      return;
    }

    // Pixel translation this frame from the current velocity (px/s).
    _panByPixels(_panVelocity * dt, size);

    // Exponential decay: v *= e^(-decay * dt).
    final decay = math.exp(-_momentumDecayPerSecond * dt);
    _panVelocity = _panVelocity * decay;

    if (_panVelocity.distance < _momentumSpeedPx(_momentumStopFraction)) {
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
      final dt = recent[i].time
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

  /// Field of view the view is *heading for*: the in-flight zoom target while
  /// the 300 ms glide is running, otherwise the live value.
  ///
  /// Relative zoom steps must compound onto this, never onto the live FOV. The
  /// glide only covers a fraction of the distance in the ~50 ms between two
  /// wheel notches, so basing the next notch on the live (barely-moved) value
  /// silently discarded every notch that arrived mid-glide — measured live, 20
  /// fast notches moved the FOV by exactly one notch and it took 172 notches to
  /// get from 60 deg to 29 deg.
  double get _pendingFOV => _zoomController.isAnimating
      ? _targetFOV
      : ref.read(skyViewStateProvider).fieldOfView;

  /// Compound one relative zoom step onto the pending target.
  ///
  /// [factor] > 1 zooms out (widens the field), < 1 zooms in. The step size is
  /// picked from the pending FOV too, so a burst of notches crossing the
  /// coarse/fine boundary steps the same way it would one notch at a time.
  void _zoomByStep({required bool zoomOut}) {
    final baseFOV = _pendingFOV;
    final zoomFactor = baseFOV > 30 ? 1.2 : 1.15;
    _animateZoom(zoomOut ? baseFOV * zoomFactor : baseFOV / zoomFactor);
  }

  /// Animate FOV to a new target value
  void _animateZoom(double newFOV) {
    // The tween BEGINS at the live FOV so the glide stays visually continuous
    // when a new step lands mid-animation; only the END accumulates.
    final currentFOV = ref.read(skyViewStateProvider).fieldOfView;
    _startFOV = currentFOV;
    _targetFOV = newFOV.clamp(1.0, 180.0);

    _zoomAnimation = Tween<double>(begin: _startFOV, end: _targetFOV).animate(
      CurvedAnimation(parent: _zoomController, curve: Curves.easeOutCubic),
    );

    _zoomController.forward(from: 0.0);
  }

  void _onFlyToAnimation() {
    final raAnim = _flyToRaAnimation;
    final decAnim = _flyToDecAnimation;
    if (raAnim == null || decAnim == null) return;

    // RA is animated in an unwrapped (possibly out-of-[0,24)) space so the
    // glide takes the shortest path across the 0h/24h seam; setCenter wraps it
    // back into range.
    var ra = raAnim.value % 24;
    if (ra < 0) ra += 24;
    ref.read(skyViewStateProvider.notifier).setCenter(ra, decAnim.value);
  }

  /// Smoothly animate the view center to [target] (used by search/GoTo).
  ///
  /// Equatorial frame glides via the RA/Dec tween below. The horizontal frame's
  /// center is alt/az, so there the target RA/Dec is converted to the local
  /// alt/az for "now" and the view jumps to it instantly (the horizontal center
  /// is not on the animated path, so an instant re-center is the honest result
  /// rather than a no-op).
  void _startFlyTo(CelestialCoordinate target) {
    final viewState = ref.read(skyViewStateProvider);
    if (viewState.viewMode == SkyViewMode.horizontal) {
      final location = ref.read(observerLocationProvider);
      final time = ref.read(observationTimeProvider).time;
      final lst = AstronomyCalculations.localSiderealTime(
        time,
        location.longitude,
      );
      final (alt, az) = AstronomyCalculations.equatorialToHorizontal(
        raDeg: target.ra * 15,
        decDeg: target.dec,
        latitudeDeg: location.latitude,
        lstHours: lst,
      );
      ref.read(skyViewStateProvider.notifier).setHorizontalCenter(az, alt);
      return;
    }

    final startRa = viewState.centerRA;
    final startDec = viewState.centerDec;

    // Choose the shortest RA direction across the 0h/24h wraparound.
    var deltaRa = target.ra - startRa;
    if (deltaRa > 12) deltaRa -= 24;
    if (deltaRa < -12) deltaRa += 24;
    final endRa = startRa + deltaRa;

    final curve = CurvedAnimation(
      parent: _flyToController,
      curve: Curves.easeInOutCubic,
    );
    _flyToRaAnimation = Tween<double>(
      begin: startRa,
      end: endRa,
    ).animate(curve);
    _flyToDecAnimation = Tween<double>(
      begin: startDec,
      end: target.dec,
    ).animate(curve);

    _flyToController.forward(from: 0.0);
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
    final stars = ref.watch(combinedStarsProvider);
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
    final satellites = ref.watch(currentSatellitesProvider);
    final variableStars = ref.watch(variableStarDataProvider);
    final minorPlanets = ref.watch(currentMinorPlanetsProvider);

    // React to fly-to (GoTo) requests by smoothly animating the view center.
    // Tokens dedupe so a request only fires its glide once, even across the
    // many rebuilds this widget performs.
    ref.listen<FlyToRequest?>(flyToRequestProvider, (prev, next) {
      if (next == null || next.token == _lastFlyToToken) return;
      _lastFlyToToken = next.token;
      _startFlyTo(next.target);
    });

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

    // The overlay layer exists only to animate cheaply on top of a static
    // base. When nothing on it actually animates, the split is pure cost: a
    // SECOND full-canvas offscreen texture to allocate, rasterize and
    // composite every frame. On a large window that is the dominant GPU cost —
    // measured at 5120x1440, rasterizing the sky is the whole frame budget, so
    // halving the number of full-screen targets is the single biggest lever.
    //
    // Collapse to one `full`-scope painter unless something on the overlay is
    // genuinely moving. `full` draws the bright-star pass too, so nothing is
    // lost visually.
    final overlayAnimates =
        qualityConfig.animateStarTwinkle ||
        selectedObject.coordinates != null ||
        renderConfig.showPlanningOverlays;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Cached so the momentum ticker, which runs outside build, converts
        // pixels to sky angle at the same scale the painter uses.
        _lastViewSize = Size(constraints.maxWidth, constraints.maxHeight);
        // Publish the canvas shape so the catalogue queries fetch a region that
        // actually covers the window. They take a SHORT-AXIS field of view, so
        // without this a wide window's outer columns have no star data at all.
        // Deferred: providers must not be written during a build.
        final aspect = constraints.maxHeight > 0
            ? constraints.maxWidth / constraints.maxHeight
            : 1.0;
        if ((ref.read(skyViewAspectRatioProvider) - aspect).abs() > 0.01) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(skyViewAspectRatioProvider.notifier).state = aspect;
          });
        }
        return Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) {
              _zoomByStep(zoomOut: event.scrollDelta.dy > 0);
            }
          },
          child: GestureDetector(
            onScaleStart: (details) {
              // A new touch always cancels any in-flight momentum glide.
              _stopMomentum();

              // Measurement mode: begin a ruler at the touch point instead of
              // panning. The endpoint coincides with the start until the drag
              // moves.
              if (widget.measurementMode) {
                final coord = _screenToCelestial(
                  details.localFocalPoint,
                  Size(constraints.maxWidth, constraints.maxHeight),
                  viewState,
                );
                setState(() {
                  _measureStart = coord;
                  _measureEnd = coord;
                });
                return;
              }

              _lastFocalPoint = details.focalPoint;
              _lastScale = 1.0;
              _panSamples.clear();
              _panSamples.add(_PanSample(details.focalPoint, DateTime.now()));
            },
            onScaleUpdate: (details) {
              // Measurement mode: drag drives the ruler end point; the view
              // pose is held still so the two sky anchors stay fixed.
              if (widget.measurementMode) {
                if (_measureStart == null) return;
                final coord = _screenToCelestial(
                  details.localFocalPoint,
                  Size(constraints.maxWidth, constraints.maxHeight),
                  viewState,
                );
                if (coord != null) {
                  setState(() => _measureEnd = coord);
                }
                return;
              }

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
              final isPinch =
                  details.pointerCount >= 2 ||
                  (details.scale - 1.0).abs() > pinchScaleEpsilon;

              // Pan — single-finger drag only.
              if (!isPinch && _lastFocalPoint != null) {
                final delta = details.focalPoint - _lastFocalPoint!;
                _panByPixels(
                  delta,
                  Size(constraints.maxWidth, constraints.maxHeight),
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
                final newFOV = (viewState.fieldOfView * scaleDelta).clamp(
                  1.0,
                  180.0,
                );
                viewNotifier.setFieldOfView(newFOV);
                _lastScale = details.scale;
              }
            },
            onScaleEnd: (_) {
              // Measurement mode never glides — the drag only positioned the
              // ruler; the result stays on screen until cleared or remeasured.
              if (widget.measurementMode) return;

              // Launch a momentum glide only for a real one-finger fling. The
              // pinch path clears _panSamples, so a pinch-release yields zero
              // velocity here and never glides.
              _panVelocity = _calculatePanVelocity();
              if (_panVelocity.distance >
                  _momentumSpeedPx(_momentumMinLaunchFraction)) {
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
              _handleDoubleTapZoom(
                details.localPosition,
                Size(constraints.maxWidth, constraints.maxHeight),
              );
            },
            onTapUp: (details) {
              // In measurement mode a single tap clears the current ruler so
              // the user can start a fresh measurement; it never selects an
              // object.
              if (widget.measurementMode) {
                if (_measureStart != null || _measureEnd != null) {
                  setState(() {
                    _measureStart = null;
                    _measureEnd = null;
                  });
                }
                return;
              }
              _handleTap(
                details.localPosition,
                Size(constraints.maxWidth, constraints.maxHeight),
              );
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
                // BACKGROUND slot (bottom, optional): a host-supplied imagery
                // layer. It is only visible while it reports itself opaque,
                // because that is also what stops the base layer's painter
                // filling the canvas with the twilight gradient on top of it.
                if (widget.backgroundLayer != null)
                  widget.backgroundLayer!.child,
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
                            scope: overlayAnimates
                                ? SkyRenderScope.base
                                : SkyRenderScope.full,
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
                          ),
                          foregroundPainter: widget.showFOV
                              ? _FOVOverlayPainter(
                                  viewState: viewState,
                                  fovWidth:
                                      widget.customFOV?.$1 ??
                                      equipmentFOV.fov?.$1,
                                  fovHeight:
                                      widget.customFOV?.$2 ??
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
                if (overlayAnimates)
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
                            ),
                            // The angular-measurement ruler rides the overlay
                            // layer's foreground so drawing/clearing it never
                            // repaints the static base.
                            foregroundPainter:
                                (_measureStart != null && _measureEnd != null)
                                ? _MeasurementOverlayPainter(
                                    viewState: viewState,
                                    start: _measureStart!,
                                    end: _measureEnd!,
                                    latitude: location.latitude,
                                    lstHours:
                                        viewState.viewMode ==
                                            SkyViewMode.horizontal
                                        ? AstronomyCalculations.localSiderealTime(
                                            observationMinute,
                                            location.longitude,
                                          )
                                        : null,
                                  )
                                : null,
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
  }) {
    final isOverlay = scope == SkyRenderScope.overlay;
    // "Base" here means "this painter owns the static, non-animated content" —
    // which is true both for the split base layer AND for the single
    // full-scope painter the view collapses to when nothing on the overlay
    // animates. Testing `== base` alone silently dropped the background
    // suppression (and the pop-in phases) in the collapsed case.
    final isBase = scope != SkyRenderScope.overlay;
    final painter = SkyCanvasPainter(
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
      moonPosition: (moonPos.$1, moonPos.$2, moonIllumination.illumination),
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
      //
      // A pop-in phase is only meaningful while the pop-in is actually
      // running: the painter reads it as "how far through the fade/scale-in
      // are we" and a phase below 1 dims the layer. Passing it only while the
      // controller animates makes the resting state unambiguous (null = draw
      // at full strength) instead of depending on where the controller happens
      // to be parked.
      popinAnimationPhase:
          (isBase &&
              qualityConfig.enableStarPopin &&
              _popinController.isAnimating)
          ? _popinController.value
          : null,
      dsoPopinAnimationPhase:
          (isBase &&
              qualityConfig.enableDsoPopin &&
              _dsoPopinController.isAnimating)
          ? _dsoPopinController.value
          : null,
      parallaxPanDelta: (isBase && qualityConfig.enableParallax)
          ? _currentPanDelta
          : null,
      observedObjectIds: widget.observedObjectIds,
      listedObjectIds: widget.listedObjectIds,
      sequencedObjectIds: widget.sequencedObjectIds,
      bortleClass: widget.bortleClass,
      horizonAltitudes: widget.horizonAltitudes,
      // The gradient is drawn by the base layer only, so only the base painter
      // needs to skip it. The host promises, via
      // [SkyBackgroundLayer.occludesSkyGradient], that its layer is covering
      // the canvas right now; if it is not, the gradient stays and the sky
      // chart is unchanged.
      paintsOpaqueBackground:
          !isBase || widget.backgroundLayer?.occludesSkyGradient != true,
    );

    return painter;
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
    final stars = ref.read(combinedStarsProvider).valueOrNull ?? [];
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

    Star? nearestStar;
    for (final star in stars) {
      final distance = _angularDistance(coord, star.coordinates);

      // Calculate hit radius based on magnitude
      // Brighter stars (lower magnitude) get larger hit targets
      final starMag = star.magnitude ?? 6.0;

      // Base radius scales with brightness: mag -1 = 3x, mag 0 = 2.5x, mag 2 = 2x, mag 6 = 1x
      final brightnessMultiplier = math.max(1.0, 2.5 - (starMag / 4.0));
      final hitRadiusDegrees = math.max(
        minHitRadiusDegrees,
        minHitRadiusDegrees * brightnessMultiplier,
      );

      if (distance < hitRadiusDegrees && distance < nearestDistance) {
        nearestDistance = distance;
        nearestStar = star;
      }
    }
    if (nearestStar != null) {
      nearestObject = _resolveCoincidentStar(nearestStar, stars, scale);
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
        // Carried as a SolarSystemBody: it renders and hit-tests like the point
        // sources Star covers, but the popup and the observation log need to be
        // able to say what it actually is.
        nearestObject = SolarSystemBody(
          id: 'SAT_${sat.catalogNumber}',
          name: sat.name,
          coordinates: satCoord,
          kind: SolarSystemBodyKind.satellite,
          magnitude: null, // Satellites don't have a fixed magnitude
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
        nearestObject = SolarSystemBody(
          id: 'PLANET_${planet.name}',
          name: planet.name,
          coordinates: planetCoord,
          kind: SolarSystemBodyKind.planet,
          magnitude: planet.magnitude,
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

    // Always call the position callback for popup handling. A hit object
    // reports its OWN catalog coordinate, never the tap coordinate: the tap is
    // a screen-space guess that lands anywhere inside the glyph's hit radius,
    // and this coordinate is what the popup shows and what Slew / Framing /
    // Sequencer act on.
    widget.onObjectTapped?.call(
      nearestObject,
      nearestObject?.coordinates ?? coord,
      position,
    );
  }

  /// Pixels within which two catalogue rows are drawn as ONE star.
  ///
  /// Below the pointer's own addressable resolution: at this separation no user
  /// can aim at one row rather than the other, and the renderer has already
  /// drawn a single glyph with a single label.
  static const double _coincidentStarPixels = 2.0;

  /// Resolve a star hit that landed on a cluster of coincident catalogue rows
  /// to the one the chart actually labelled — the brightest.
  ///
  /// HYG lists the components of a multiple star as separate rows. Capella's
  /// Aa (mag 0.08, named "Capella") and Ab (mag 0.96, no name, no HIP) sit
  /// 9 arcsec apart, which at any field wider than a fraction of a degree is
  /// well under one pixel. Taking the strictly nearest row therefore made the
  /// pick a coin flip: clicking the star the chart labels "Capella" opened a
  /// panel headed "HYG118360" reporting magnitude 1.0, contradicting both the
  /// label and the glyph size drawn from mag 0.08.
  CelestialObject _resolveCoincidentStar(
    Star nearest,
    List<Star> stars,
    double scale,
  ) {
    final mergeDegrees = _coincidentStarPixels / scale;
    var best = nearest;
    var bestMag = nearest.magnitude ?? 99.0;
    for (final star in stars) {
      if (identical(star, nearest)) continue;
      final mag = star.magnitude ?? 99.0;
      if (mag >= bestMag) continue;
      if (_angularDistance(nearest.coordinates, star.coordinates) >
          mergeDegrees) {
        continue;
      }
      best = star;
      bestMag = mag;
    }
    return best;
  }

  CelestialCoordinate? _screenToCelestial(
    Offset position,
    Size size,
    SkyViewState viewState,
  ) {
    // Delegate to the shared projector so the inverse can never drift from the
    // forward projection the painter uses. The old code here hardcoded the
    // STEREOGRAPHIC inverse while the painter has three projection branches, so
    // in orthographic or azimuthal-equidistant mode a tap resolved to the wrong
    // sky coordinate — increasingly wrong away from the view centre — and
    // selected the wrong object or empty sky.
    final projector = SkyFovProjector.forSize(
      viewState,
      size,
      latitude: ref.read(observerLocationProvider).latitude,
      lstHours: viewState.viewMode == SkyViewMode.horizontal
          ? AstronomyCalculations.localSiderealTime(
              ref.read(observationTimeProvider).time,
              ref.read(observerLocationProvider).longitude,
            )
          : null,
    );
    return projector.unproject(position);
  }

  double _angularDistance(CelestialCoordinate a, CelestialCoordinate b) {
    final ra1 = a.ra * 15 * math.pi / 180;
    final dec1 = a.dec * math.pi / 180;
    final ra2 = b.ra * 15 * math.pi / 180;
    final dec2 = b.dec * math.pi / 180;

    final cosSep =
        math.sin(dec1) * math.sin(dec2) +
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
