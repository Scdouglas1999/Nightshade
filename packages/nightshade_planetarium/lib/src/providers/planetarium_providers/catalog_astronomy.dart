part of '../planetarium_providers.dart';

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
  final maxStars = ref.watch(fovAdaptiveQualityProvider).maxStarsToRender;

  return indexAsync.whenData((index) {
    // Return only the brightest [maxStars] in view — the exact set the renderer
    // draws (it caps to maxStarsToRender). At wide fields this avoids gathering
    // and full-sorting tens of thousands of stars every pan frame.
    return index.queryBrightestInViewport(
      viewState.centerRA,
      viewState.centerDec,
      viewState.fieldOfView,
      maxMagnitude: starMagLimit,
      maxResults: maxStars,
    );
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
  final maxDsos = ref.watch(fovAdaptiveQualityProvider).maxDsosToRender;

  return indexAsync.whenData((index) {
    return index.queryBrightestInViewport(
      viewState.centerRA,
      viewState.centerDec,
      viewState.fieldOfView,
      maxMagnitude: dsoMagLimit,
      maxResults: maxDsos,
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
