part of '../planetarium_providers.dart';

// ============================================================================
// HUD Toggle Providers
// ============================================================================

/// Whether to show the compass HUD
final showCompassHudProvider = StateProvider<bool>((ref) => true);

/// Whether to show the mini-map
final showMinimapProvider = StateProvider<bool>((ref) => true);

/// Whether to show the ground plane
final showGroundPlaneProvider = StateProvider<bool>((ref) => true);

/// Whether to render the entire planetarium in night-vision (red) mode.
///
/// When enabled the screen content is wrapped in a luminance→red color filter
/// so the sky texture, overlays and HUD all go red, preserving dark adaptation
/// at the eyepiece. Off by default.
final nightVisionModeProvider = StateProvider<bool>((ref) => false);

/// Whether to show the FOV reference rings overlay (Telrad + optical finder)
/// centered on the view center for visual aiming / star-hopping. Off by
/// default.
final showFovRingsProvider = StateProvider<bool>((ref) => false);

/// Whether the angular-measurement tool is armed.
///
/// When enabled, a click-drag across the sky measures the angular separation
/// and position angle between the two endpoints instead of panning the view.
/// Off by default. The [InteractiveSkyView] reads this flag to switch its drag
/// handling and draw the measurement overlay.
final measurementModeProvider = StateProvider<bool>((ref) => false);

// ============================================================================
// Sky Render Config Provider
// ============================================================================

class SkyRenderConfigNotifier extends StateNotifier<SkyRenderConfig> {
  SkyRenderConfigNotifier() : super(const SkyRenderConfig());

  void toggleStars() {
    state = state.copyWith(showStars: !state.showStars);
  }

  void toggleConstellationLines() {
    state = state.copyWith(
      showConstellationLines: !state.showConstellationLines,
    );
  }

  void toggleConstellationLabels() {
    state = state.copyWith(
      showConstellationLabels: !state.showConstellationLabels,
    );
  }

  void toggleConstellationBoundaries() {
    state = state.copyWith(
      showConstellationBoundaries: !state.showConstellationBoundaries,
    );
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

  void togglePlanningOverlays() {
    state = state.copyWith(showPlanningOverlays: !state.showPlanningOverlays);
  }

  void toggleDsoLabels() {
    state = state.copyWith(showDSOLabels: !state.showDSOLabels);
  }

  void toggleCardinalDirections() {
    state = state.copyWith(
      showCardinalDirections: !state.showCardinalDirections,
    );
  }

  void toggleMeridian() {
    state = state.copyWith(showMeridian: !state.showMeridian);
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
        useGlowEffects:
            userQuality.quality != RenderQuality.performance &&
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
  // When stars are hidden the sky has no star clutter to declutter against, so
  // DSOs should be visible at any zoom rather than fading in as you zoom.
  final showStars = ref.watch(
    skyRenderConfigProvider.select((c) => c.showStars),
  );

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
  final fovFactor = (2.0 * math.log(120.0 / clampedFov) / math.ln2).clamp(
    0.0,
    7.0,
  );

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

  // Stars hidden -> use the maximum reveal factor for DSOs so they show at full
  // depth at any zoom level (no need to zoom in to "pop" them in).
  final dsoFovFactor = showStars ? fovFactor : 7.0;

  return (
    (baseStarLimit + fovFactor - starPenalty).clamp(2.0, 12.0),
    (baseDsoLimit + dsoFovFactor - dsoPenalty).clamp(4.0, 16.0),
  );
});
