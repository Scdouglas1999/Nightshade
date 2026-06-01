part of '../planetarium_providers.dart';

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

/// The user-configured effective horizon in degrees, as observed by the
/// planetarium widgets.
///
/// 0° = mathematical horizon. A non-zero value (e.g. 20°) accounts for
/// trees / buildings / hills the user cannot see through. Rise/transit/set
/// times and the altitude card's shading both read from this provider so
/// the planetarium agrees with the Run Dashboard's time-to-set stat to
/// the second.
///
/// Why a planetarium-local provider with a default: `nightshade_core`
/// (which owns the persisted setting via its own
/// `effectiveHorizonDegProvider`) already depends on
/// `nightshade_planetarium` for catalog access, so adding the reverse
/// dependency would create a cycle. The app layer syncs the two
/// providers (`nightshade_app/lib/services/location_sync_service.dart`).
/// In standalone-planetarium scenarios (tests, demos) the default of
/// `0.0` keeps the math identical to pre-Pack-D behaviour.
///
/// Name distinct from core's `effectiveHorizonDegProvider` to avoid
/// `ambiguous_import` at app-layer call sites that already pull in both
/// packages via the umbrella exports.
final planetariumEffectiveHorizonDegProvider =
    StateProvider<double>((ref) => 0.0);

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
