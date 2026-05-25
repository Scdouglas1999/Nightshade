import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_core/nightshade_core.dart';

import 'planetarium_sync.dart';

/// Standard sea-level pressure (hPa) when weather telemetry is unavailable.
const double kDefaultObserverPressureHpa = 1013.25;

/// Default temperature (°C) for refraction when weather telemetry is unavailable.
const double kDefaultObserverTemperatureC = 10.0;

ObserverDto observerDtoFromLocation(LocationSettings location) {
  return ObserverDto(
    latitudeRad: location.latitude * math.pi / 180,
    longitudeRad: location.longitude * math.pi / 180,
    elevationM: location.elevation,
    pressureHpa: kDefaultObserverPressureHpa,
    temperatureC: kDefaultObserverTemperatureC,
  );
}

/// Observer site for planetarium v2 (lat/lon/elev + atmosphere defaults).
///
/// Sourced from [appObserverLocationProvider]. Fails loud when location is unset.
final observerProvider = Provider<ObserverDto>((ref) {
  final location = ref.watch(appObserverLocationProvider);
  if (location == null) {
    throw StateError(
      'appObserverLocationProvider returned null — configure observer '
      'latitude/longitude in Settings before opening planetarium v2',
    );
  }
  return observerDtoFromLocation(location);
});

/// Mirrors [observerProvider] into Rust via [planetariumSetObserver].
final planetariumObserverSyncProvider = Provider<void>((ref) {
  bindPlanetariumSync(
    ref,
    listenSource: observerProvider,
    push: (driver, observer) => driver.setObserver(observer),
  );
});
