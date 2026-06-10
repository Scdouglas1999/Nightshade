part of '../planetarium_providers.dart';

// ============================================================================
// Mosaic Plan Provider
// ============================================================================

/// Current mosaic plan state
class MosaicPlanState {
  final MosaicPlan? plan;
  final PlanetariumMosaicConfig? config;
  final bool isEditing;

  const MosaicPlanState({this.plan, this.config, this.isEditing = false});

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

    state = MosaicPlanState(plan: plan, config: config, isEditing: true);
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

    state = MosaicPlanState(plan: plan, config: plan.config, isEditing: true);
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
final bestTargetsProvider = FutureProvider<List<(DeepSkyObject, ObjectVisibility)>>((
  ref,
) async {
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
  final imagingTime =
      twilight.astronomicalDusk ??
      DateTime(currentDate.year, currentDate.month, currentDate.day, 21, 0);

  // Computing visibility (iterative rise/transit/set) for the full ~12k-DSO
  // catalog is heavy; run it in an isolate so the first read (e.g. the first
  // time the side panel opens) doesn't block/freeze the UI thread. Only the
  // coordinate arrays are sent across (cheap) — not the DSO objects.
  final args = _BestTargetsArgs(
    raDeg: [for (final d in dsos) d.coordinates.raDegrees],
    decDeg: [for (final d in dsos) d.coordinates.dec],
    latitudeDeg: location.latitude,
    longitudeDeg: location.longitude,
    imagingTime: imagingTime,
  );
  final ranked = await compute(_computeBestTargetIndices, args);
  return [for (final (i, v) in ranked) (dsos[i], v)];
});

/// Inputs for the off-thread best-targets computation. Only primitives + plain
/// coordinate lists so the payload is cheap to send to the isolate.
class _BestTargetsArgs {
  final List<double> raDeg;
  final List<double> decDeg;
  final double latitudeDeg;
  final double longitudeDeg;
  final DateTime imagingTime;

  const _BestTargetsArgs({
    required this.raDeg,
    required this.decDeg,
    required this.latitudeDeg,
    required this.longitudeDeg,
    required this.imagingTime,
  });
}

/// Isolate entry point: rank DSOs (by index) by transit altitude, keeping only
/// those that rise above 30°. Returns the top 20 as (originalIndex, visibility).
List<(int, ObjectVisibility)> _computeBestTargetIndices(_BestTargetsArgs a) {
  final ranked = <(int, ObjectVisibility)>[];
  for (var i = 0; i < a.raDeg.length; i++) {
    final v = AstronomyCalculations.calculateObjectVisibility(
      raDeg: a.raDeg[i],
      decDeg: a.decDeg[i],
      date: a.imagingTime,
      latitudeDeg: a.latitudeDeg,
      longitudeDeg: a.longitudeDeg,
      minAltitude: 30,
    );
    if (!v.neverRises && (v.transitAltitude ?? 0) > 30) {
      ranked.add((i, v));
    }
  }
  ranked.sort(
    (x, y) => (y.$2.transitAltitude ?? 0).compareTo(x.$2.transitAltitude ?? 0),
  );
  return ranked.take(20).toList();
}
