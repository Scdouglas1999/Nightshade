import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../celestial_object.dart';
import '../coordinate_system.dart';
import '../catalogs/star_catalog.dart';
import '../catalogs/constellation_data.dart';
import '../catalogs/catalog.dart';
import '../catalogs/spatial_index.dart';
import '../astronomy/astronomy_calculations.dart';
import '../astronomy/planetary_positions.dart';
import '../astronomy/milky_way_data.dart';
import '../rendering/sky_renderer.dart';
import '../rendering/render_quality.dart';
import '../services/survey_image_service.dart';
import '../services/mosaic_planner.dart';

/// Get display name for search matching
(String, String) _getDsoDisplayInfoForSearch(DeepSkyObject dso) {
  // If it's a Messier object, use Messier number as name
  if (dso.isMessier) {
    final messierNum = dso.messierNumber;
    if (messierNum != null) {
      return (messierNum, 'M');
    }
  }

  // For non-Messier objects, use NGC/IC designation as name
  final ngcIc = dso.ngcIcDesignation;
  if (ngcIc != null) {
    if (ngcIc.startsWith('NGC')) {
      return (ngcIc, 'NGC');
    } else if (ngcIc.startsWith('IC')) {
      return (ngcIc, 'IC');
    }
  }

  // Fallback to id and extract catalog prefix
  if (dso.id.startsWith('NGC')) {
    return (dso.id, 'NGC');
  } else if (dso.id.startsWith('IC')) {
    return (dso.id, 'IC');
  } else if (dso.id.startsWith('M')) {
    return (dso.id, 'M');
  }

  // Last resort: use name and id
  return (dso.name, dso.id);
}

// ============================================================================
// Location Provider
// ============================================================================

/// Observer location state
class PlanetariumObserver {
  final double latitude;
  final double longitude;
  final double elevation;
  final String? locationName;

  const PlanetariumObserver({
    this.latitude = 34.0522, // Los Angeles default
    this.longitude = -118.2437,
    this.elevation = 0,
    this.locationName,
  });

  PlanetariumObserver copyWith({
    double? latitude,
    double? longitude,
    double? elevation,
    String? locationName,
  }) {
    return PlanetariumObserver(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      elevation: elevation ?? this.elevation,
      locationName: locationName ?? this.locationName,
    );
  }
}

class PlanetariumObserverNotifier extends StateNotifier<PlanetariumObserver> {
  PlanetariumObserverNotifier() : super(const PlanetariumObserver());

  void setLocation({
    double? latitude,
    double? longitude,
    double? elevation,
    String? locationName,
  }) {
    state = state.copyWith(
      latitude: latitude,
      longitude: longitude,
      elevation: elevation,
      locationName: locationName,
    );

    // Settings sync will be handled at app level
  }
}

final observerLocationProvider =
    StateNotifierProvider<PlanetariumObserverNotifier, PlanetariumObserver>((ref) {
  return PlanetariumObserverNotifier();
});

// ============================================================================
// Observation Time Provider
// ============================================================================

/// Current observation time (can be simulated or real-time)
class ObservationTimeState {
  final DateTime time;
  final bool isRealTime;
  final double speedMultiplier;

  const ObservationTimeState({
    required this.time,
    this.isRealTime = true,
    this.speedMultiplier = 1.0,
  });

  ObservationTimeState copyWith({
    DateTime? time,
    bool? isRealTime,
    double? speedMultiplier,
  }) {
    return ObservationTimeState(
      time: time ?? this.time,
      isRealTime: isRealTime ?? this.isRealTime,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
    );
  }
}

class ObservationTimeNotifier extends StateNotifier<ObservationTimeState> {
  Timer? _timer;

  ObservationTimeNotifier()
      : super(ObservationTimeState(time: DateTime.now())) {
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isRealTime) {
        state = state.copyWith(time: DateTime.now());
      } else if (state.speedMultiplier != 0) {
        final delta = Duration(seconds: state.speedMultiplier.round());
        state = state.copyWith(time: state.time.add(delta));
      }
    });
  }

  void setTime(DateTime time) {
    state = state.copyWith(time: time, isRealTime: false);
  }

  void setRealTime(bool realTime) {
    state = state.copyWith(
      isRealTime: realTime,
      time: realTime ? DateTime.now() : state.time,
    );
  }

  void setSpeedMultiplier(double multiplier) {
    state = state.copyWith(speedMultiplier: multiplier, isRealTime: false);
  }

  void fastForward(Duration duration) {
    state = state.copyWith(
      time: state.time.add(duration),
      isRealTime: false,
    );
  }

  void rewind(Duration duration) {
    state = state.copyWith(
      time: state.time.subtract(duration),
      isRealTime: false,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final observationTimeProvider =
    StateNotifierProvider<ObservationTimeNotifier, ObservationTimeState>((ref) {
  return ObservationTimeNotifier();
});

// ============================================================================
// Sky View State Provider
// ============================================================================

class SkyViewNotifier extends StateNotifier<SkyViewState> {
  SkyViewNotifier()
      : super(const SkyViewState(
          centerRA: 0,
          centerDec: 0,
          fieldOfView: 60,
        ));

  void setCenter(double ra, double dec) {
    state = state.copyWith(
      centerRA: ra.clamp(0, 24),
      centerDec: dec.clamp(-90, 90),
    );
  }

  void setFieldOfView(double fov) {
    state = state.copyWith(fieldOfView: fov.clamp(1, 180));
  }

  void setRotation(double rotation) {
    state = state.copyWith(rotation: rotation % 360);
  }

  void setProjection(SkyProjection projection) {
    state = state.copyWith(projection: projection);
  }

  void zoomIn({Offset? mousePosition, Size? viewSize}) {
    if (mousePosition != null && viewSize != null) {
      _zoomAtPosition(mousePosition, viewSize, 1.5);
    } else {
      state =
          state.copyWith(fieldOfView: (state.fieldOfView / 1.5).clamp(1, 180));
    }
  }

  void zoomOut({Offset? mousePosition, Size? viewSize}) {
    if (mousePosition != null && viewSize != null) {
      _zoomAtPosition(mousePosition, viewSize, 1 / 1.5);
    } else {
      state =
          state.copyWith(fieldOfView: (state.fieldOfView * 1.5).clamp(1, 180));
    }
  }

  /// Zoom at a specific screen position, keeping that position fixed
  void _zoomAtPosition(Offset mousePosition, Size viewSize, double zoomFactor) {
    // Get the celestial coordinate at the mouse position before zoom
    final coordBefore = _screenToCelestial(mousePosition, viewSize);
    if (coordBefore == null) {
      // Fallback to center zoom if conversion fails
      state = state.copyWith(
          fieldOfView: (state.fieldOfView / zoomFactor).clamp(1, 180));
      return;
    }

    // Apply zoom
    final oldFOV = state.fieldOfView;
    final newFOV = (oldFOV / zoomFactor).clamp(1.0, 180.0);
    state = state.copyWith(fieldOfView: newFOV);

    // Get the celestial coordinate at the same screen position after zoom
    final coordAfter = _screenToCelestial(mousePosition, viewSize);
    if (coordAfter == null) return;

    // Calculate the offset needed to keep the mouse position pointing at the same celestial coordinate
    final dRA = coordBefore.ra - coordAfter.ra;
    final dDec = coordBefore.dec - coordAfter.dec;

    // Adjust center to compensate
    var newRA = state.centerRA + dRA;
    if (newRA < 0) newRA += 24;
    if (newRA >= 24) newRA -= 24;

    state = state.copyWith(
      centerRA: newRA,
      centerDec: (state.centerDec + dDec).clamp(-90, 90),
    );
  }

  /// Convert screen position to celestial coordinates
  CelestialCoordinate? _screenToCelestial(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale =
        math.min(size.width, size.height) / 2 / (state.fieldOfView / 2);

    // Offset from center in screen pixels
    final dx = -(position.dx - center.dx) / scale;
    final dy = -(position.dy - center.dy) / scale;

    // Reverse rotation
    final rotRad = -state.rotation * math.pi / 180;
    final x = dx * math.cos(rotRad) - dy * math.sin(rotRad);
    final y = dx * math.sin(rotRad) + dy * math.cos(rotRad);

    // Convert to RA/Dec (inverse of stereographic projection)
    final centerRaDeg = state.centerRA * 15;
    final centerDecDeg = state.centerDec;

    final xRad = x * math.pi / 180;
    final yRad = y * math.pi / 180;
    final centerRaRad = centerRaDeg * math.pi / 180;
    final centerDecRad = centerDecDeg * math.pi / 180;

    final rho = math.sqrt(xRad * xRad + yRad * yRad);
    if (rho < 0.0001) {
      return CelestialCoordinate(ra: state.centerRA, dec: state.centerDec);
    }

    final c = 2 * math.atan(rho / 2);
    final sinc = math.sin(c);
    final cosc = math.cos(c);

    final dec = math.asin(cosc * math.sin(centerDecRad) +
        yRad * sinc * math.cos(centerDecRad) / rho);
    final ra = centerRaRad +
        math.atan2(
          xRad * sinc,
          rho * math.cos(centerDecRad) * cosc -
              yRad * math.sin(centerDecRad) * sinc,
        );

    var raHours = (ra * 180 / math.pi / 15).toDouble();
    if (raHours < 0) raHours += 24;
    if (raHours >= 24) raHours -= 24;

    final decDeg = (dec * 180 / math.pi).toDouble();

    return CelestialCoordinate(ra: raHours, dec: decDeg.clamp(-90, 90));
  }

  void pan(double dRA, double dDec) {
    var newRA = state.centerRA + dRA;
    if (newRA < 0) newRA += 24;
    if (newRA >= 24) newRA -= 24;

    state = state.copyWith(
      centerRA: newRA,
      centerDec: (state.centerDec + dDec).clamp(-90, 90),
    );
  }

  void lookAt(CelestialCoordinate coord) {
    state = state.copyWith(centerRA: coord.ra, centerDec: coord.dec);
  }
}

final skyViewStateProvider =
    StateNotifierProvider<SkyViewNotifier, SkyViewState>((ref) {
  return SkyViewNotifier();
});

/// Computed provider for current view center in horizontal coordinates
/// Returns (azimuth, altitude) in degrees
/// Uses minute precision to avoid excessive rebuilds from per-second time updates.
final viewCenterAltAzProvider = Provider<(double, double)>((ref) {
  final viewState = ref.watch(skyViewStateProvider);
  final location = ref.watch(observerLocationProvider);
  final time =
      ref.watch(_currentMinuteProvider); // Use minute precision instead

  // Convert view center (RA/Dec) to Alt/Az
  final lst = AstronomyCalculations.localSiderealTime(time, location.longitude);

  final (alt, az) = AstronomyCalculations.equatorialToHorizontal(
    raDeg: viewState.centerRA * 15, // Convert hours to degrees
    decDeg: viewState.centerDec,
    latitudeDeg: location.latitude,
    lstHours: lst,
  );

  return (az, alt);
});

// ============================================================================
// HUD Toggle Providers
// ============================================================================

/// Whether to show the compass HUD
final showCompassHudProvider = StateProvider<bool>((ref) => true);

/// Whether to show the mini-map
final showMinimapProvider = StateProvider<bool>((ref) => true);

/// Whether to show the ground plane
final showGroundPlaneProvider = StateProvider<bool>((ref) => true);

// ============================================================================
// Sky Render Config Provider
// ============================================================================

class SkyRenderConfigNotifier extends StateNotifier<SkyRenderConfig> {
  SkyRenderConfigNotifier() : super(const SkyRenderConfig());

  void toggleStars() {
    state = state.copyWith(showStars: !state.showStars);
  }

  void toggleConstellationLines() {
    state =
        state.copyWith(showConstellationLines: !state.showConstellationLines);
  }

  void toggleConstellationLabels() {
    state =
        state.copyWith(showConstellationLabels: !state.showConstellationLabels);
  }

  void toggleConstellationBoundaries() {
    state = state.copyWith(
        showConstellationBoundaries: !state.showConstellationBoundaries);
  }

  void toggleDSOs() {
    state = state.copyWith(showDSOs: !state.showDSOs);
  }

  void toggleGrid() {
    state = state.copyWith(showCoordinateGrid: !state.showCoordinateGrid);
  }

  void toggleEquatorialGrid() {
    state = state.copyWith(showEquatorialGrid: !state.showEquatorialGrid);
  }

  void toggleAltAzGrid() {
    state = state.copyWith(showAltAzGrid: !state.showAltAzGrid);
  }

  void toggleEcliptic() {
    state = state.copyWith(showEcliptic: !state.showEcliptic);
  }

  void toggleGalacticPlane() {
    state = state.copyWith(showGalacticPlane: !state.showGalacticPlane);
  }

  void toggleHorizon() {
    state = state.copyWith(showHorizon: !state.showHorizon);
  }

  void setStarMagnitudeLimit(double limit) {
    state = state.copyWith(starMagnitudeLimit: limit);
  }

  void setDsoMagnitudeLimit(double limit) {
    state = state.copyWith(dsoMagnitudeLimit: limit);
  }

  void toggleMountPosition() {
    state = state.copyWith(showMountPosition: !state.showMountPosition);
  }

  void toggleMilkyWay() {
    state = state.copyWith(showMilkyWay: !state.showMilkyWay);
  }

  void toggleSun() {
    state = state.copyWith(showSun: !state.showSun);
  }

  void toggleMoon() {
    state = state.copyWith(showMoon: !state.showMoon);
  }

  void togglePlanets() {
    state = state.copyWith(showPlanets: !state.showPlanets);
  }

  void toggleGroundPlane() {
    state = state.copyWith(showGroundPlane: !state.showGroundPlane);
  }

  void toggleSatellites() {
    state = state.copyWith(showSatellites: !state.showSatellites);
  }

  void toggleVariableStars() {
    state = state.copyWith(showVariableStars: !state.showVariableStars);
  }

  void toggleMinorPlanets() {
    state = state.copyWith(showMinorPlanets: !state.showMinorPlanets);
  }

  void toggleConstellationArt() {
    state = state.copyWith(showConstellationArt: !state.showConstellationArt);
  }
}

final skyRenderConfigProvider =
    StateNotifierProvider<SkyRenderConfigNotifier, SkyRenderConfig>((ref) {
  return SkyRenderConfigNotifier();
});

/// Computed render config that combines the base config with the ground plane toggle
/// This is the provider that should be used for actual rendering to ensure
/// the ground plane visibility respects the HUD toggle.
final effectiveSkyRenderConfigProvider = Provider<SkyRenderConfig>((ref) {
  final config = ref.watch(skyRenderConfigProvider);
  final showGroundPlane = ref.watch(showGroundPlaneProvider);
  return config.copyWith(showGroundPlane: showGroundPlane);
});

// ============================================================================
// Render Quality Provider
// ============================================================================

/// Notifier for managing render quality settings
class RenderQualityNotifier extends StateNotifier<RenderQualityConfig> {
  RenderQualityNotifier() : super(const RenderQualityConfig.balanced());

  /// Set the quality tier
  void setQuality(RenderQuality quality) {
    state = RenderQualityConfig.fromQuality(quality);
  }

  /// Set a custom configuration
  void setConfig(RenderQualityConfig config) {
    state = config;
  }

  /// Toggle a specific setting
  void toggleBlurEffects() {
    state = state.copyWith(useBlurEffects: !state.useBlurEffects);
  }

  void toggleGlowEffects() {
    state = state.copyWith(useGlowEffects: !state.useGlowEffects);
  }

  void toggleStarTwinkle() {
    state = state.copyWith(animateStarTwinkle: !state.animateStarTwinkle);
  }

  void toggleSmoothZoom() {
    state = state.copyWith(smoothZoomAnimation: !state.smoothZoomAnimation);
  }

  void setMilkyWayDetail(double detail) {
    state = state.copyWith(milkyWayDetail: detail.clamp(0.0, 1.0));
  }

  void setStarMagnitudeLimit(double limit) {
    state = state.copyWith(starMagnitudeLimit: limit);
  }

  void setDsoMagnitudeLimit(double limit) {
    state = state.copyWith(dsoMagnitudeLimit: limit);
  }
}

/// Provider for render quality configuration (user's manual selection)
final renderQualityProvider =
    StateNotifierProvider<RenderQualityNotifier, RenderQualityConfig>((ref) {
  return RenderQualityNotifier();
});

/// LOD quality tier based on current field of view
enum LodTier {
  /// Wide FOV (>60 degrees): reduce quality for performance
  wide,
  /// Medium-wide FOV (30-60 degrees): moderate quality
  mediumWide,
  /// Medium FOV (10-30 degrees): balanced rendering
  medium,
  /// Narrow FOV (<10 degrees): full quality, show maximum detail
  narrow,
}

/// Determines the current LOD tier based on FOV
final lodTierProvider = Provider<LodTier>((ref) {
  final fov = ref.watch(skyViewStateProvider.select((s) => s.fieldOfView));
  if (fov > 60) return LodTier.wide;
  if (fov > 30) return LodTier.mediumWide;
  if (fov > 10) return LodTier.medium;
  return LodTier.narrow;
});

/// FOV-adaptive render quality that overrides the user's manual quality setting
/// based on the current zoom level. This ensures good performance at wide FOV
/// and maximum detail when zoomed in, regardless of the user's manual tier.
///
/// - Wide FOV (>60 deg): Downgrades glow quality, limits star count, disables
///   enhanced DSO symbols, reduces PSF quality
/// - Medium FOV (10-60 deg): Uses the user's chosen quality tier as-is
/// - Narrow FOV (<10 deg): Upgrades to full quality effects and higher limits
final fovAdaptiveQualityProvider = Provider<RenderQualityConfig>((ref) {
  final userQuality = ref.watch(renderQualityProvider);
  final lodTier = ref.watch(lodTierProvider);

  switch (lodTier) {
    case LodTier.wide:
      // Wide FOV (>60 deg): reduce quality for performance regardless of user setting.
      // DSO limit is generous because faint DSOs are batched as drawRawPoints
      // (near-zero cost). The dynamic magnitude provider already limits which
      // DSOs are passed based on FOV, so this cap is just a safeguard.
      return userQuality.copyWith(
        useBlurEffects: false,
        useGlowEffects: userQuality.quality != RenderQuality.performance &&
            userQuality.quality != RenderQuality.minimal,
        enableEnhancedDsoSymbols: false,
        enablePlanetDetails: false,
        enableParallax: false,
        animateStarTwinkle: false,
        starPsfQuality: (userQuality.starPsfQuality).clamp(0.0, 0.3),
        maxStarsToRender: userQuality.maxStarsToRender.clamp(0, 3000),
        maxDsosToRender: userQuality.maxDsosToRender.clamp(0, 3000),
        milkyWayDetail: (userQuality.milkyWayDetail).clamp(0.0, 0.3),
        groundPlaneDetail: (userQuality.groundPlaneDetail).clamp(0.0, 0.5),
      );

    case LodTier.mediumWide:
      // Medium-wide FOV (30-60 deg): slightly reduced quality, more objects than wide.
      // Faint DSOs are batched as points so the count limit can be generous.
      return userQuality.copyWith(
        useBlurEffects: false,
        enableParallax: false,
        animateStarTwinkle: false,
        starPsfQuality: (userQuality.starPsfQuality).clamp(0.0, 0.5),
        maxStarsToRender: userQuality.maxStarsToRender.clamp(0, 8000),
        maxDsosToRender: userQuality.maxDsosToRender.clamp(0, 5000),
      );

    case LodTier.medium:
      // Medium FOV (10-30 deg): use user's quality tier as-is
      return userQuality;

    case LodTier.narrow:
      // Narrow FOV (<10 deg): upgrade to full quality for maximum detail
      return userQuality.copyWith(
        useGlowEffects: true,
        useBlurEffects: userQuality.quality == RenderQuality.quality,
        enableEnhancedDsoSymbols: true,
        enablePlanetDetails: true,
        enableSelectionAnimation: true,
        starPsfQuality: (userQuality.starPsfQuality).clamp(0.5, 1.0),
        maxStarsToRender: userQuality.maxStarsToRender.clamp(5000, 20000),
        maxDsosToRender: userQuality.maxDsosToRender.clamp(2000, 8000),
      );
  }
});

/// Computed magnitude limits based on current FOV and sky brightness.
/// Returns (starMagLimit, dsoMagLimit)
///
/// As the user zooms in (narrower FOV), fainter objects become visible.
/// When the sun is above the horizon (daylight) or in twilight, the limiting
/// magnitude is reduced to reflect sky brightness — but conservatively,
/// because the planetarium is a PLANNING TOOL, not a live view. Users need
/// to see Messier objects during the day to plan tonight's session.
///
/// Sky brightness penalty (based on sun altitude):
///   Sun above 0 deg (daylight): penalty = 6.0 mag (Messier objects visible to ~mag 6-8)
///   Sun at  -6 deg (civil twilight): penalty = 3.0 mag
///   Sun at -12 deg (nautical twilight): penalty = 1.5 mag
///   Sun at -18 deg (astronomical twilight): penalty = 0.5 mag
///   Below -18 deg (full dark): penalty = 0
final dynamicMagnitudeLimitsProvider = Provider<(double, double)>((ref) {
  final viewState = ref.watch(skyViewStateProvider);
  final quality = ref.watch(fovAdaptiveQualityProvider);
  final location = ref.watch(observerLocationProvider);
  final time = ref.watch(_currentMinuteProvider);
  final fov = viewState.fieldOfView;

  // Base limits from quality tier
  final baseStarLimit = quality.starMagnitudeLimit;
  final baseDsoLimit = quality.dsoMagnitudeLimit;

  // Continuous logarithmic scaling: narrower FOV reveals fainter objects smoothly.
  // At FOV 120 deg: fovFactor = 0.0 (just base)
  // At FOV  60 deg: fovFactor ~ 1.0
  // At FOV  30 deg: fovFactor ~ 2.0
  // At FOV  10 deg: fovFactor ~ 3.6
  // At FOV   5 deg: fovFactor ~ 4.6
  // At FOV   1 deg: fovFactor ~ 6.9
  //
  // Formula: fovFactor = 2.0 * log2(120 / clampedFov) - capped so we don't exceed catalog depth.
  // Using log2 gives a smooth ramp that increases ~2 magnitudes per halving of FOV.
  final clampedFov = fov.clamp(1.0, 120.0);
  final fovFactor = (2.0 * math.log(120.0 / clampedFov) / math.ln2).clamp(0.0, 7.0);

  // Sky brightness penalty: reduce limiting magnitude when the sky is bright.
  // Penalties are intentionally modest because the planetarium is a planning
  // tool — users want to see Messier/NGC objects during the day to plan their
  // imaging session tonight. A penalty of 6 during daylight means DSOs up to
  // about magnitude 6-8 remain visible (all 110 Messier objects plus bright
  // NGCs). This is NOT meant to simulate naked-eye visibility.
  //
  // Sun altitude thresholds (standard astronomical definitions):
  //   > 0 deg: daylight — penalty 6.0 (bright Messier/NGC objects visible)
  //  -6 to 0: civil twilight — penalty 3.0
  // -12 to -6: nautical twilight — penalty 1.5
  // -18 to -12: astronomical twilight — penalty 0.5
  //   < -18: full darkness — no penalty
  final sunAlt = AstronomyCalculations.sunAltitude(
    dt: time,
    latitudeDeg: location.latitude,
    longitudeDeg: location.longitude,
  );

  double skyBrightnessPenalty;
  if (sunAlt >= 0) {
    // Daylight: moderate penalty. Messier objects (mag ~3-9) still visible
    // for planning. Users can see M31, M42, M45, M13, M51, etc.
    skyBrightnessPenalty = 6.0;
  } else if (sunAlt >= -6) {
    // Civil twilight: sun between -6 and 0. Linear ramp from 3.0 to 6.0.
    // At -6: penalty=3.0, at 0: penalty=6.0
    skyBrightnessPenalty = 3.0 + (-sunAlt / 6.0) * -3.0;
    // Simplify: penalty = 6 + sunAlt (sunAlt is negative, so this increases as sun rises)
    skyBrightnessPenalty = 6.0 + sunAlt; // sunAlt=-6 -> 3.0, sunAlt=0 -> 6.0
  } else if (sunAlt >= -12) {
    // Nautical twilight: sun between -12 and -6. Linear ramp from 1.5 to 3.0.
    // At -12: penalty=1.5, at -6: penalty=3.0
    skyBrightnessPenalty = 1.5 + (sunAlt + 12.0) / 6.0 * 1.5;
  } else if (sunAlt >= -18) {
    // Astronomical twilight: sun between -18 and -12. Linear ramp from 0 to 0.5.
    // At -18: penalty=0, at -12: penalty=0.5
    skyBrightnessPenalty = (sunAlt + 18.0) / 6.0 * 0.5;
  } else {
    // Full darkness: no penalty
    skyBrightnessPenalty = 0.0;
  }

  // Apply penalty: stars are less affected than DSOs because point sources
  // remain visible longer than extended objects in bright skies.
  // Stars get half the penalty of DSOs.
  final starPenalty = skyBrightnessPenalty * 0.5;
  final dsoPenalty = skyBrightnessPenalty;

  return (
    (baseStarLimit + fovFactor - starPenalty).clamp(2.0, 12.0),
    (baseDsoLimit + fovFactor - dsoPenalty).clamp(4.0, 16.0),
  );
});

// ============================================================================
// Catalog Providers
// ============================================================================

final loadedStarsProvider = FutureProvider<List<Star>>((ref) async {
  // Load stars up to magnitude 12.0 to allow deep viewing when zoomed in.
  // The HYG catalog contains ~120,000 stars to this depth. The dynamic
  // magnitude limit provider filters them per-frame based on FOV so only
  // a fraction is rendered at wide zoom.
  return HygStarCatalog(magnitudeLimit: 12.0).loadObjects();
});

final loadedDsosProvider = FutureProvider<List<DeepSkyObject>>((ref) async {
  // Load DSOs up to magnitude 16.0 to include faint imaging targets when zoomed in.
  // The dynamic magnitude limit provider filters them per-frame based on FOV.
  return OpenNgcDsoCatalog(magnitudeLimit: 16.0).loadObjects();
});

/// Spatial index for stars to avoid scanning full catalogs per frame.
final starSpatialIndexProvider = FutureProvider<StarSpatialIndex>((ref) async {
  final stars = await ref.watch(loadedStarsProvider.future);
  final index = StarSpatialIndex();
  index.addAll(stars);
  return index;
});

/// Spatial index for DSOs to avoid scanning full catalogs per frame.
final dsoSpatialIndexProvider = FutureProvider<DsoSpatialIndex>((ref) async {
  final dsos = await ref.watch(loadedDsosProvider.future);
  final index = DsoSpatialIndex();
  index.addAll(dsos);
  return index;
});

/// Stars filtered by dynamic magnitude limit based on current FOV
/// As the user zooms in (narrower FOV), fainter stars become visible.
/// This provider should be used by the sky renderer for FOV-aware star display.
final fovFilteredStarsProvider = Provider<AsyncValue<List<Star>>>((ref) {
  final indexAsync = ref.watch(starSpatialIndexProvider);
  final (starMagLimit, _) = ref.watch(dynamicMagnitudeLimitsProvider);
  final viewState = ref.watch(skyViewStateProvider);

  return indexAsync.whenData((index) {
    final result = index.queryViewportFiltered(
      viewState.centerRA,
      viewState.centerDec,
      viewState.fieldOfView,
      maxMagnitude: starMagLimit,
    );
    return result;
  });
});

/// DSOs filtered by dynamic magnitude limit based on current FOV
/// As the user zooms in (narrower FOV), fainter DSOs become visible.
/// This provider should be used by the sky renderer for FOV-aware DSO display.
final fovFilteredDsosProvider =
    Provider<AsyncValue<List<DeepSkyObject>>>((ref) {
  final indexAsync = ref.watch(dsoSpatialIndexProvider);
  final (_, dsoMagLimit) = ref.watch(dynamicMagnitudeLimitsProvider);
  final viewState = ref.watch(skyViewStateProvider);

  return indexAsync.whenData((index) {
    return index.queryViewportFiltered(
      viewState.centerRA,
      viewState.centerDec,
      viewState.fieldOfView,
      maxMagnitude: dsoMagLimit,
    );
  });
});

final constellationDataProvider = Provider<List<ConstellationData>>((ref) {
  return Constellations.all;
});

// ============================================================================
// Computed Astronomy Data Providers
// ============================================================================

/// Provider that only updates when the date changes (not every second)
/// This prevents unnecessary recalculations of date-dependent values like twilight.
final _currentDateProvider = Provider<DateTime>((ref) {
  final time = ref.watch(observationTimeProvider);
  // Return only the date portion, so it only changes at midnight
  return DateTime(time.time.year, time.time.month, time.time.day);
});

/// Provider that only updates when the minute changes (not every second)
/// This prevents unnecessary recalculations of astronomical positions
/// which don't need per-second precision for sky rendering.
final _currentMinuteProvider = Provider<DateTime>((ref) {
  final time = ref.watch(observationTimeProvider);
  // Return only up to minute precision, ignoring seconds
  return DateTime(
    time.time.year,
    time.time.month,
    time.time.day,
    time.time.hour,
    time.time.minute,
  );
});

/// Public provider for observation time at minute precision.
/// Use this for sky rendering to avoid rebuilds every second.
/// The sky doesn't visibly change in one second, but rebuilding every second hurts performance.
final observationMinuteProvider = Provider<DateTime>((ref) {
  return ref.watch(_currentMinuteProvider);
});

/// Twilight times for current date and location
/// Uses date-level precision since twilight only changes once per day.
final twilightTimesProvider = Provider<TwilightTimes>((ref) {
  final location = ref.watch(observerLocationProvider);
  final currentDate = ref.watch(_currentDateProvider);

  return AstronomyCalculations.calculateTwilightTimes(
    date: currentDate,
    latitudeDeg: location.latitude,
    longitudeDeg: location.longitude,
  );
});

/// Moon information for current time and location
/// Uses date precision for rise/set, minute precision for illumination.
final moonInfoProvider = Provider<MoonTimes>((ref) {
  final location = ref.watch(observerLocationProvider);
  final currentDate = ref.watch(_currentDateProvider);
  final currentMinute = ref.watch(_currentMinuteProvider);

  // Calculate rise/set times for the date
  final moonTimes = AstronomyCalculations.calculateMoonTimes(
    date: currentDate,
    latitudeDeg: location.latitude,
    longitudeDeg: location.longitude,
  );

  // Calculate phase and illumination - minute precision is sufficient
  final illumination = AstronomyCalculations.moonIllumination(currentMinute);
  final phaseName = AstronomyCalculations.moonPhaseName(currentMinute);

  // Return combined data
  return MoonTimes(
    moonrise: moonTimes.moonrise,
    moonset: moonTimes.moonset,
    illumination: illumination,
    phaseName: phaseName,
  );
});

/// Current Local Sidereal Time
/// Needs per-second precision for accurate clock display.
final localSiderealTimeProvider = Provider<double>((ref) {
  final location = ref.watch(observerLocationProvider);
  final time = ref.watch(observationTimeProvider);

  return AstronomyCalculations.localSiderealTime(time.time, location.longitude);
});

/// Sun position for current time
/// Uses minute precision - sun moves ~0.25 degrees per minute which is fine for rendering.
final sunPositionProvider = Provider<(double ra, double dec)>((ref) {
  final time = ref.watch(_currentMinuteProvider);
  return AstronomyCalculations.sunPosition(time);
});

/// Moon position for current time
/// Uses minute precision - moon moves ~0.5 arcmin per minute which is fine for rendering.
final moonPositionProvider =
    Provider<(double ra, double dec, double distance)>((ref) {
  final time = ref.watch(_currentMinuteProvider);
  return AstronomyCalculations.moonPosition(time);
});

/// Planet positions for current time
/// Uses minute precision - planets move very slowly, minute precision is more than enough.
final planetPositionsProvider = Provider<List<PlanetData>>((ref) {
  final time = ref.watch(_currentMinuteProvider);
  return PlanetaryPositions.getAllPlanetPositions(time);
});

/// Milky Way points for rendering (static, only needs to be generated once)
final milkyWayPointsProvider = Provider<List<MilkyWayPoint>>((ref) {
  return MilkyWayData.generateMilkyWayPoints();
});

// ============================================================================
// Mount Position Provider
// ============================================================================

/// Tracking status for the mount
enum MountTrackingStatus {
  disconnected,
  parked,
  slewing,
  tracking,
  stopped,
}

/// Mount position state for displaying on planetarium
class MountPositionState {
  final double? raHours;
  final double? decDegrees;
  final MountTrackingStatus status;
  final bool isConnected;

  const MountPositionState({
    this.raHours,
    this.decDegrees,
    this.status = MountTrackingStatus.disconnected,
    this.isConnected = false,
  });

  /// Get the mount position as celestial coordinates
  CelestialCoordinate? get coordinates {
    if (raHours == null || decDegrees == null) return null;
    return CelestialCoordinate(ra: raHours!, dec: decDegrees!);
  }

  MountPositionState copyWith({
    double? raHours,
    double? decDegrees,
    MountTrackingStatus? status,
    bool? isConnected,
  }) {
    return MountPositionState(
      raHours: raHours ?? this.raHours,
      decDegrees: decDegrees ?? this.decDegrees,
      status: status ?? this.status,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class MountPositionNotifier extends StateNotifier<MountPositionState> {
  MountPositionNotifier() : super(const MountPositionState());

  /// Update the mount position from external source (e.g., equipment provider)
  void updatePosition({
    required double? raHours,
    required double? decDegrees,
    required MountTrackingStatus status,
    required bool isConnected,
  }) {
    state = MountPositionState(
      raHours: raHours,
      decDegrees: decDegrees,
      status: status,
      isConnected: isConnected,
    );
  }

  void setDisconnected() {
    state = const MountPositionState();
  }
}

final mountPositionProvider =
    StateNotifierProvider<MountPositionNotifier, MountPositionState>((ref) {
  return MountPositionNotifier();
});

// ============================================================================
// Selected Object Provider
// ============================================================================

/// Currently selected celestial object
class SelectedObjectState {
  final CelestialObject? object;
  final CelestialCoordinate? coordinates;
  final ObjectVisibility? visibility;
  final (double alt, double az)? currentAltAz;

  const SelectedObjectState({
    this.object,
    this.coordinates,
    this.visibility,
    this.currentAltAz,
  });
}

class SelectedObjectNotifier extends StateNotifier<SelectedObjectState> {
  final Ref _ref;

  SelectedObjectNotifier(this._ref) : super(const SelectedObjectState());

  void selectObject(CelestialObject object) {
    final location = _ref.read(observerLocationProvider);
    final time = _ref.read(observationTimeProvider);

    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: object.coordinates.raDegrees,
      decDeg: object.coordinates.dec,
      date: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    final altAz = AstronomyCalculations.objectAltAz(
      raDeg: object.coordinates.raDegrees,
      decDeg: object.coordinates.dec,
      dt: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    state = SelectedObjectState(
      object: object,
      coordinates: object.coordinates,
      visibility: visibility,
      currentAltAz: altAz,
    );
  }

  void selectCoordinates(CelestialCoordinate coord) {
    final location = _ref.read(observerLocationProvider);
    final time = _ref.read(observationTimeProvider);

    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: coord.raDegrees,
      decDeg: coord.dec,
      date: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    final altAz = AstronomyCalculations.objectAltAz(
      raDeg: coord.raDegrees,
      decDeg: coord.dec,
      dt: time.time,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
    );

    state = SelectedObjectState(
      coordinates: coord,
      visibility: visibility,
      currentAltAz: altAz,
    );
  }

  void clearSelection() {
    state = const SelectedObjectState();
  }
}

final selectedObjectProvider =
    StateNotifierProvider<SelectedObjectNotifier, SelectedObjectState>((ref) {
  return SelectedObjectNotifier(ref);
});

// ============================================================================
// Equipment FOV Provider
// ============================================================================

/// Equipment configuration for FOV display
class EquipmentFOVState {
  final CameraSensorSpecs? camera;
  final TelescopeSpecs? telescope;
  final double focalReducer;
  final double rotation;

  const EquipmentFOVState({
    this.camera,
    this.telescope,
    this.focalReducer = 1.0,
    this.rotation = 0,
  });

  /// Get effective focal length
  double? get effectiveFocalLength {
    if (telescope == null) return null;
    return telescope!.focalLengthMm * focalReducer;
  }

  /// Get calculated FOV
  (double width, double height)? get fov {
    if (camera == null || effectiveFocalLength == null) return null;

    return FOVCalculator.calculateFOV(
      sensorWidthMm: camera!.widthMm,
      sensorHeightMm: camera!.heightMm,
      focalLengthMm: effectiveFocalLength!,
    );
  }

  /// Get image scale in arcsec/pixel
  double? get imageScale {
    if (camera == null || effectiveFocalLength == null) return null;

    return FOVCalculator.calculateImageScale(
      pixelSizeMicrons: camera!.pixelSizeMicrons,
      focalLengthMm: effectiveFocalLength!,
    );
  }

  EquipmentFOVState copyWith({
    CameraSensorSpecs? camera,
    TelescopeSpecs? telescope,
    double? focalReducer,
    double? rotation,
  }) {
    return EquipmentFOVState(
      camera: camera ?? this.camera,
      telescope: telescope ?? this.telescope,
      focalReducer: focalReducer ?? this.focalReducer,
      rotation: rotation ?? this.rotation,
    );
  }
}

class EquipmentFOVNotifier extends StateNotifier<EquipmentFOVState> {
  EquipmentFOVNotifier() : super(const EquipmentFOVState());

  void setCamera(CameraSensorSpecs camera) {
    state = state.copyWith(camera: camera);
  }

  void setTelescope(TelescopeSpecs telescope) {
    state = state.copyWith(telescope: telescope);
  }

  void setFocalReducer(double multiplier) {
    state = state.copyWith(focalReducer: multiplier);
  }

  void setRotation(double rotation) {
    state = state.copyWith(rotation: rotation % 360);
  }
}

final equipmentFOVProvider =
    StateNotifierProvider<EquipmentFOVNotifier, EquipmentFOVState>((ref) {
  return EquipmentFOVNotifier();
});

// ============================================================================
// Mosaic Plan Provider
// ============================================================================

/// Current mosaic plan state
class MosaicPlanState {
  final MosaicPlan? plan;
  final PlanetariumMosaicConfig? config;
  final bool isEditing;

  const MosaicPlanState({
    this.plan,
    this.config,
    this.isEditing = false,
  });

  MosaicPlanState copyWith({
    MosaicPlan? plan,
    PlanetariumMosaicConfig? config,
    bool? isEditing,
  }) {
    return MosaicPlanState(
      plan: plan ?? this.plan,
      config: config ?? this.config,
      isEditing: isEditing ?? this.isEditing,
    );
  }
}

class MosaicPlanNotifier extends StateNotifier<MosaicPlanState> {
  final Ref _ref;

  MosaicPlanNotifier(this._ref) : super(const MosaicPlanState());

  void createMosaic({
    required CelestialCoordinate center,
    required double totalWidth,
    required double totalHeight,
  }) {
    final equipment = _ref.read(equipmentFOVProvider);
    final fov = equipment.fov;

    if (fov == null) return;

    final config = PlanetariumMosaicConfig(
      center: center,
      totalWidth: totalWidth,
      totalHeight: totalHeight,
      panelFovWidth: fov.$1,
      panelFovHeight: fov.$2,
      rotation: equipment.rotation,
    );

    final plan = MosaicPlanner.generateMosaic(config);

    state = MosaicPlanState(
      plan: plan,
      config: config,
      isEditing: true,
    );
  }

  void createRectangularMosaic({
    required CelestialCoordinate center,
    required int rows,
    required int columns,
  }) {
    final equipment = _ref.read(equipmentFOVProvider);
    final fov = equipment.fov;

    if (fov == null) return;

    final plan = MosaicPlanner.generateRectangularMosaic(
      center: center,
      rows: rows,
      columns: columns,
      panelFovWidth: fov.$1,
      panelFovHeight: fov.$2,
      rotation: equipment.rotation,
    );

    state = MosaicPlanState(
      plan: plan,
      config: plan.config,
      isEditing: true,
    );
  }

  void updateOverlap(double horizontal, double vertical) {
    if (state.config == null) return;

    final newConfig = state.config!.copyWith(
      overlap: MosaicOverlap(horizontal: horizontal, vertical: vertical),
    );

    final plan = MosaicPlanner.generateMosaic(newConfig);

    state = state.copyWith(plan: plan, config: newConfig);
  }

  void updateRotation(double rotation) {
    if (state.config == null) return;

    final newConfig = state.config!.copyWith(rotation: rotation);
    final plan = MosaicPlanner.generateMosaic(newConfig);

    state = state.copyWith(plan: plan, config: newConfig);
  }

  void optimizeCaptureOrder({bool snakePattern = true}) {
    state.plan?.optimizeCaptureOrder(snakePattern: snakePattern);
    state = state.copyWith(plan: state.plan);
  }

  void clearMosaic() {
    state = const MosaicPlanState();
  }

  String exportToJson() {
    if (state.plan == null) return '{}';
    return MosaicExporter.toJson(state.plan!);
  }

  String exportToCsv() {
    if (state.plan == null) return '';
    return MosaicExporter.toCsv(state.plan!);
  }
}

final mosaicPlanProvider =
    StateNotifierProvider<MosaicPlanNotifier, MosaicPlanState>((ref) {
  return MosaicPlanNotifier(ref);
});

// ============================================================================
// Best Targets Provider
// ============================================================================

/// Find best imaging targets for tonight
/// Uses cached date to avoid flickering from second-by-second updates
final bestTargetsProvider =
    FutureProvider<List<(DeepSkyObject, ObjectVisibility)>>((ref) async {
  final dsos = await ref.watch(loadedDsosProvider.future);
  final location = ref.watch(observerLocationProvider);
  final currentDate = ref.watch(_currentDateProvider);

  // Calculate twilight times for the current date (not watching the time provider directly)
  final twilight = AstronomyCalculations.calculateTwilightTimes(
    date: currentDate,
    latitudeDeg: location.latitude,
    longitudeDeg: location.longitude,
  );

  // Use astronomical twilight as imaging time, or 9 PM if not available
  final imagingTime = twilight.astronomicalDusk ??
      DateTime(currentDate.year, currentDate.month, currentDate.day, 21, 0);

  final targetsWithVisibility = <(DeepSkyObject, ObjectVisibility)>[];

  for (final dso in dsos) {
    final visibility = AstronomyCalculations.calculateObjectVisibility(
      raDeg: dso.coordinates.raDegrees,
      decDeg: dso.coordinates.dec,
      date: imagingTime,
      latitudeDeg: location.latitude,
      longitudeDeg: location.longitude,
      minAltitude: 30, // Only consider objects above 30°
    );

    if (!visibility.neverRises && (visibility.transitAltitude ?? 0) > 30) {
      targetsWithVisibility.add((dso, visibility));
    }
  }

  // Sort by transit altitude (highest first)
  targetsWithVisibility.sort((a, b) =>
      (b.$2.transitAltitude ?? 0).compareTo(a.$2.transitAltitude ?? 0));

  return targetsWithVisibility.take(20).toList();
});

// ============================================================================
// Search Provider
// ============================================================================

/// Object type filter for search
enum SearchObjectTypeFilter {
  all,
  stars,
  galaxies,
  nebulae,
  clusters,
}

/// Search filter configuration
class SearchFilters {
  final SearchObjectTypeFilter typeFilter;
  final double? minMagnitude;
  final double? maxMagnitude;
  final bool observableNow;
  final String? constellationFilter;

  const SearchFilters({
    this.typeFilter = SearchObjectTypeFilter.all,
    this.minMagnitude,
    this.maxMagnitude,
    this.observableNow = false,
    this.constellationFilter,
  });

  SearchFilters copyWith({
    SearchObjectTypeFilter? typeFilter,
    double? minMagnitude,
    double? maxMagnitude,
    bool? observableNow,
    String? constellationFilter,
    bool clearMinMagnitude = false,
    bool clearMaxMagnitude = false,
    bool clearConstellation = false,
  }) {
    return SearchFilters(
      typeFilter: typeFilter ?? this.typeFilter,
      minMagnitude: clearMinMagnitude ? null : (minMagnitude ?? this.minMagnitude),
      maxMagnitude: clearMaxMagnitude ? null : (maxMagnitude ?? this.maxMagnitude),
      observableNow: observableNow ?? this.observableNow,
      constellationFilter: clearConstellation ? null : (constellationFilter ?? this.constellationFilter),
    );
  }

  bool get hasActiveFilters =>
      typeFilter != SearchObjectTypeFilter.all ||
      minMagnitude != null ||
      maxMagnitude != null ||
      observableNow ||
      constellationFilter != null;
}

/// A scored search result with match quality information
class ScoredSearchResult {
  final CelestialObject object;
  /// 0 = best (exact match), higher = worse match quality
  final int score;
  /// Which field matched (for display purposes)
  final String matchSource;

  const ScoredSearchResult({
    required this.object,
    required this.score,
    required this.matchSource,
  });
}

/// Object search state
class ObjectSearchState {
  final String query;
  final List<CelestialObject> results;
  final bool isSearching;
  final SearchFilters filters;

  const ObjectSearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.filters = const SearchFilters(),
  });

  ObjectSearchState copyWith({
    String? query,
    List<CelestialObject>? results,
    bool? isSearching,
    SearchFilters? filters,
  }) {
    return ObjectSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      filters: filters ?? this.filters,
    );
  }
}

/// Compute Levenshtein distance between two strings.
/// Used for fuzzy matching in search.
int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Use two-row optimization to save memory
  var prevRow = List<int>.generate(b.length + 1, (i) => i);
  var currRow = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    currRow[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      currRow[j] = [
        currRow[j - 1] + 1, // insertion
        prevRow[j] + 1, // deletion
        prevRow[j - 1] + cost, // substitution
      ].reduce(math.min);
    }
    final temp = prevRow;
    prevRow = currRow;
    currRow = temp;
  }
  return prevRow[b.length];
}

/// Score a query match against a target string.
/// Returns null if no match, or a score (lower = better).
/// 0 = exact match, 1 = starts with, 2 = contains, 3+ = fuzzy match
int? _scoreMatch(String query, String target) {
  final q = query.toLowerCase();
  final t = target.toLowerCase();
  final qNorm = q.replaceAll(RegExp(r'\s+'), '');
  final tNorm = t.replaceAll(RegExp(r'\s+'), '');

  // Exact match
  if (t == q || tNorm == qNorm) return 0;

  // Starts with
  if (t.startsWith(q) || tNorm.startsWith(qNorm)) return 1;

  // Contains
  if (t.contains(q) || tNorm.contains(qNorm)) return 2;

  // Fuzzy match: only if query is >= 3 chars to avoid too many false positives
  if (q.length >= 3) {
    // For short targets, compare directly
    if (tNorm.length <= qNorm.length + 3) {
      final dist = _levenshteinDistance(qNorm, tNorm);
      // Allow edit distance up to ~30% of query length, minimum 1
      final maxDist = math.max(1, (qNorm.length * 0.35).floor());
      if (dist <= maxDist) return 3 + dist;
    }

    // For longer targets, check each word
    final words = t.split(RegExp(r'\s+'));
    for (final word in words) {
      if (word.length >= q.length - 2) {
        final dist = _levenshteinDistance(q, word);
        final maxDist = math.max(1, (q.length * 0.35).floor());
        if (dist <= maxDist) return 3 + dist;
      }
    }
  }

  return null; // No match
}

/// Map of well-known DSO common names to their catalog IDs
/// Used as a supplemental lookup for objects whose common names
/// may not be in the catalog data
const Map<String, List<String>> _wellKnownDsoNames = {
  'andromeda galaxy': ['M31', 'NGC224'],
  'orion nebula': ['M42', 'NGC1976'],
  'great orion nebula': ['M42', 'NGC1976'],
  'ring nebula': ['M57', 'NGC6720'],
  'crab nebula': ['M1', 'NGC1952'],
  'whirlpool galaxy': ['M51', 'NGC5194'],
  'sombrero galaxy': ['M104', 'NGC4594'],
  'pinwheel galaxy': ['M101', 'NGC5457'],
  'triangulum galaxy': ['M33', 'NGC598'],
  'lagoon nebula': ['M8', 'NGC6523'],
  'eagle nebula': ['M16', 'NGC6611'],
  'pillars of creation': ['M16', 'NGC6611'],
  'omega nebula': ['M17', 'NGC6618'],
  'swan nebula': ['M17', 'NGC6618'],
  'trifid nebula': ['M20', 'NGC6514'],
  'dumbbell nebula': ['M27', 'NGC6853'],
  'hercules cluster': ['M13', 'NGC6205'],
  'great hercules cluster': ['M13', 'NGC6205'],
  'wild duck cluster': ['M11', 'NGC6705'],
  'pleiades': ['M45'],
  'seven sisters': ['M45'],
  'beehive cluster': ['M44', 'NGC2632'],
  'praesepe': ['M44', 'NGC2632'],
  'horsehead nebula': ['IC434'],
  'flame nebula': ['NGC2024'],
  'rosette nebula': ['NGC2237'],
  'north america nebula': ['NGC7000'],
  'pelican nebula': ['IC5070'],
  'veil nebula': ['NGC6960', 'NGC6992'],
  'owl nebula': ['M97', 'NGC3587'],
  'cat eye nebula': ['NGC6543'],
  'helix nebula': ['NGC7293'],
  'double cluster': ['NGC869', 'NGC884'],
  'bode galaxy': ['M81', 'NGC3031'],
  'cigar galaxy': ['M82', 'NGC3034'],
  'sunflower galaxy': ['M63', 'NGC5055'],
  'black eye galaxy': ['M64', 'NGC4826'],
  'sculptor galaxy': ['NGC253'],
  'centaurus a': ['NGC5128'],
  'southern pinwheel': ['M83', 'NGC5236'],
  'antennae galaxies': ['NGC4038', 'NGC4039'],
  'leo triplet': ['M65', 'M66', 'NGC3628'],
  'hamburger galaxy': ['NGC3628'],
  'needle galaxy': ['NGC4565'],
  'cocoon nebula': ['IC5146'],
  'bubble nebula': ['NGC7635'],
  'elephant trunk nebula': ['IC1396'],
  'barnard loop': ['Sh2-276'],
  'soul nebula': ['IC1848'],
  'heart nebula': ['IC1805'],
  'running man nebula': ['NGC1977'],
  'california nebula': ['NGC1499'],
  'pacman nebula': ['NGC281'],
  'flaming star nebula': ['IC405'],
  'cone nebula': ['NGC2264'],
  'christmas tree cluster': ['NGC2264'],
  'blinking planetary': ['NGC6826'],
  'blue snowball': ['NGC7662'],
  'saturn nebula': ['NGC7009'],
  'eskimo nebula': ['NGC2392'],
  'little dumbbell': ['M76', 'NGC650'],
  'phantom galaxy': ['M74', 'NGC628'],
  'butterfly cluster': ['M6', 'NGC6405'],
  'ptolemy cluster': ['M7', 'NGC6475'],
  'starfish cluster': ['M38', 'NGC1912'],
};

/// Map of well-known star proper names to their common designations
const Map<String, String> _wellKnownStarNames = {
  'north star': 'Polaris',
  'pole star': 'Polaris',
  'dog star': 'Sirius',
  'evening star': 'Vega',
  'summer triangle': 'Vega',
  'barnard\'s star': 'Barnard\'s Star',
};

class ObjectSearchNotifier extends StateNotifier<ObjectSearchState> {
  final Ref _ref;

  ObjectSearchNotifier(this._ref) : super(const ObjectSearchState());

  void updateFilters(SearchFilters filters) {
    state = state.copyWith(filters: filters);
    // Re-run search with new filters if there's an active query
    if (state.query.isNotEmpty) {
      search(state.query);
    }
  }

  Future<void> search(String query) async {
    if (query.isEmpty) {
      state = ObjectSearchState(filters: state.filters);
      return;
    }

    state = state.copyWith(query: query, isSearching: true);

    final qLower = query.toLowerCase().trim();
    final filters = state.filters;

    try {
      final scored = <ScoredSearchResult>[];

      // Check well-known name mappings first for DSO names
      final wellKnownIds = <String>{};
      for (final entry in _wellKnownDsoNames.entries) {
        final score = _scoreMatch(qLower, entry.key);
        if (score != null) {
          wellKnownIds.addAll(entry.value.map((v) => v.toLowerCase().replaceAll(' ', '')));
        }
      }

      // Check well-known star name aliases
      String? starNameAlias;
      for (final entry in _wellKnownStarNames.entries) {
        final score = _scoreMatch(qLower, entry.key);
        if (score != null) {
          starNameAlias = entry.value.toLowerCase();
          break;
        }
      }

      // Search stars
      if (filters.typeFilter == SearchObjectTypeFilter.all ||
          filters.typeFilter == SearchObjectTypeFilter.stars) {
        try {
          final loadedStars = await _ref.read(loadedStarsProvider.future);
          for (final star in loadedStars) {
            if (!_passesFilters(star, filters)) continue;

            // Check proper name
            final nameScore = _scoreMatch(qLower, star.name);
            if (nameScore != null) {
              scored.add(ScoredSearchResult(
                object: star,
                score: nameScore,
                matchSource: 'name',
              ));
              continue;
            }

            // Check star name alias
            if (starNameAlias != null &&
                star.name.toLowerCase().contains(starNameAlias)) {
              scored.add(ScoredSearchResult(
                object: star,
                score: 2,
                matchSource: 'alias',
              ));
              continue;
            }

            // Check catalog IDs (HIP, HD, HR)
            final idScore = _scoreMatch(qLower, star.id);
            if (idScore != null) {
              scored.add(ScoredSearchResult(
                object: star,
                score: idScore + 1, // Slightly lower priority than name
                matchSource: 'id',
              ));
              continue;
            }

            for (final catId in star.catalogIds) {
              final catScore = _scoreMatch(qLower, catId);
              if (catScore != null) {
                scored.add(ScoredSearchResult(
                  object: star,
                  score: catScore + 1,
                  matchSource: 'catalog',
                ));
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('[Planetarium] Star search error: $e');
        }
      }

      // Search DSOs
      if (filters.typeFilter == SearchObjectTypeFilter.all ||
          filters.typeFilter != SearchObjectTypeFilter.stars) {
        try {
          final loadedDsos = await _ref.read(loadedDsosProvider.future);

          for (final dso in loadedDsos) {
            // Apply type filter
            if (!_passesDsoTypeFilter(dso, filters.typeFilter)) continue;
            if (!_passesFilters(dso, filters)) continue;

            int? bestScore;
            String matchSource = 'id';

            // Check well-known ID match
            final normalizedId = dso.id.toLowerCase().replaceAll(' ', '');
            if (wellKnownIds.contains(normalizedId)) {
              bestScore = 1; // Good match via well-known name
              matchSource = 'common name';
            }

            // Also check if any catalog IDs match well-known
            if (bestScore == null) {
              for (final catId in dso.catalogIds) {
                final normalizedCat = catId.toLowerCase().replaceAll(' ', '');
                if (wellKnownIds.contains(normalizedCat)) {
                  bestScore = 1;
                  matchSource = 'common name';
                  break;
                }
              }
            }

            // Check common names from catalog data
            final commonNames = dso.commonNames;
            if (commonNames != null && commonNames.isNotEmpty) {
              for (final cn in commonNames.split(',')) {
                final trimmed = cn.trim();
                if (trimmed.isEmpty) continue;
                final cnScore = _scoreMatch(qLower, trimmed);
                if (cnScore != null && (bestScore == null || cnScore < bestScore)) {
                  bestScore = cnScore;
                  matchSource = 'common name';
                }
              }
            }

            // Check display name
            final (displayName, _) = _getDsoDisplayInfoForSearch(dso);
            final displayScore = _scoreMatch(qLower, displayName);
            if (displayScore != null && (bestScore == null || displayScore < bestScore)) {
              bestScore = displayScore;
              matchSource = 'name';
            }

            // Check id
            final idScore = _scoreMatch(qLower, dso.id);
            if (idScore != null && (bestScore == null || idScore < bestScore)) {
              bestScore = idScore;
              matchSource = 'id';
            }

            // Check catalog IDs
            for (final catId in dso.catalogIds) {
              final catScore = _scoreMatch(qLower, catId);
              if (catScore != null && (bestScore == null || catScore < bestScore)) {
                bestScore = catScore;
                matchSource = 'catalog';
              }
            }

            // Check constellation
            final constellation = dso.constellation;
            if (constellation != null) {
              final conScore = _scoreMatch(qLower, constellation);
              if (conScore != null && conScore <= 1 &&
                  (bestScore == null || conScore + 5 < bestScore)) {
                bestScore = conScore + 5; // Lower priority for constellation matches
                matchSource = 'constellation';
              }
            }

            if (bestScore != null) {
              scored.add(ScoredSearchResult(
                object: dso,
                score: bestScore,
                matchSource: matchSource,
              ));
            }
          }
        } catch (e) {
          debugPrint('[Planetarium] DSO search error: $e');
        }
      }

      // Sort by score (lower = better), then by magnitude (brighter first)
      scored.sort((a, b) {
        final scoreCmp = a.score.compareTo(b.score);
        if (scoreCmp != 0) return scoreCmp;
        return (a.object.magnitude ?? 99).compareTo(b.object.magnitude ?? 99);
      });

      // No hardcoded limit - return all scored results (UI can paginate)
      state = ObjectSearchState(
        query: query,
        results: scored.map((s) => s.object).toList(),
        isSearching: false,
        filters: filters,
      );
    } catch (e) {
      state = ObjectSearchState(
        query: query,
        results: [],
        isSearching: false,
        filters: filters,
      );
    }
  }

  bool _passesFilters(CelestialObject obj, SearchFilters filters) {
    // Magnitude filter
    if (filters.minMagnitude != null && obj.magnitude != null) {
      if (obj.magnitude! < filters.minMagnitude!) return false;
    }
    if (filters.maxMagnitude != null && obj.magnitude != null) {
      if (obj.magnitude! > filters.maxMagnitude!) return false;
    }

    // Constellation filter
    if (filters.constellationFilter != null) {
      String? objConstellation;
      if (obj is Star) {
        objConstellation = obj.constellation;
      } else if (obj is DeepSkyObject) {
        objConstellation = obj.constellation;
      }
      if (objConstellation == null) return false;
      if (!objConstellation.toLowerCase().contains(
          filters.constellationFilter!.toLowerCase())) {
        return false;
      }
    }

    // Observable now filter
    if (filters.observableNow) {
      final location = _ref.read(observerLocationProvider);
      final obsTime = _ref.read(observationTimeProvider);
      final (alt, _) = AstronomyCalculations.objectAltAz(
        raDeg: obj.coordinates.ra * 15,
        decDeg: obj.coordinates.dec,
        dt: obsTime.time,
        latitudeDeg: location.latitude,
        longitudeDeg: location.longitude,
      );
      if (alt < 10) return false; // Must be at least 10° above horizon
    }

    return true;
  }

  bool _passesDsoTypeFilter(DeepSkyObject dso, SearchObjectTypeFilter filter) {
    switch (filter) {
      case SearchObjectTypeFilter.all:
        return true;
      case SearchObjectTypeFilter.stars:
        return false; // Stars are handled separately
      case SearchObjectTypeFilter.galaxies:
        return dso.type.isGalaxy;
      case SearchObjectTypeFilter.nebulae:
        return dso.type.isNebula;
      case SearchObjectTypeFilter.clusters:
        return dso.type.isCluster;
    }
  }

  void clear() {
    state = ObjectSearchState(filters: state.filters);
  }
}

final objectSearchProvider =
    StateNotifierProvider<ObjectSearchNotifier, ObjectSearchState>((ref) {
  return ObjectSearchNotifier(ref);
});

// ============================================================================
// Density Hotspots Provider
// ============================================================================

/// Calculates density hotspots for crowded regions when zoomed out.
/// Returns list of (ra, dec, visibleCount, hiddenCount) for areas with many hidden objects.
/// This helps users know when to zoom in to reveal more objects.
final densityHotspotsDataProvider =
    Provider<List<(double, double, int, int)>>((ref) {
  final (starMagLimit, _) = ref.watch(dynamicMagnitudeLimitsProvider);

  // Get all loaded stars (not the filtered ones - we need the full set to count hidden)
  final starsAsync = ref.watch(loadedStarsProvider);
  final stars = starsAsync.valueOrNull ?? [];

  if (stars.isEmpty) return [];

  // Grid the sky into cells and count objects
  const cellSize = 15.0; // degrees
  final Map<String, (int, int)> cells = {}; // visible, hidden counts

  for (final star in stars) {
    // Calculate cell key from RA (hours to degrees) and Dec
    final raDegs = star.coordinates.ra * 15; // Convert hours to degrees
    final decDegs = star.coordinates.dec;

    // Normalize RA to 0-360 range before gridding
    final normalizedRA =
        raDegs < 0 ? raDegs + 360 : (raDegs >= 360 ? raDegs - 360 : raDegs);
    final cellKey =
        '${(normalizedRA ~/ cellSize)}_${((decDegs + 90) ~/ cellSize)}';

    final current = cells[cellKey] ?? (0, 0);
    final starMag = star.magnitude ?? 99;

    if (starMag <= starMagLimit) {
      cells[cellKey] = (current.$1 + 1, current.$2);
    } else {
      cells[cellKey] = (current.$1, current.$2 + 1);
    }
  }

  // Return cells with significant hidden objects (> 30)
  return cells.entries.where((e) => e.value.$2 > 30).map((e) {
    final parts = e.key.split('_');
    final raCellIndex = double.parse(parts[0]);
    final decCellIndex = double.parse(parts[1]);
    // Convert back to center of cell in RA (hours) and Dec (degrees)
    final ra = (raCellIndex * cellSize + cellSize / 2) / 15; // Convert to hours
    final dec = decCellIndex * cellSize -
        90 +
        cellSize / 2; // Convert from shifted index
    return (ra, dec, e.value.$1, e.value.$2);
  }).toList();
});

final densityHotspotsProvider =
    Provider<List<(double, double, int, int)>>((ref) {
  final fieldOfView =
      ref.watch(skyViewStateProvider.select((state) => state.fieldOfView));

  // Only show density indicators when zoomed out (FOV > 30 degrees)
  if (fieldOfView < 30) return [];

  return ref.watch(densityHotspotsDataProvider);
});
