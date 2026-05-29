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
/// Sourced from [appObserverLocationProvider]. Falls back to a 0°/0°/0 m
/// observer when the location is unset so the v2 renderer can still draw
/// stars in equatorial coordinates instead of blacking out the whole host
/// subtree. Throwing here used to bubble through
/// [planetariumObserverSyncProvider]'s `ref.watch` and kill every other
/// provider in the host wiring — including the render-config and
/// scene-snapshot listeners, masquerading as "v2 doesn't render".
final observerProvider = Provider<ObserverDto>((ref) {
  final location = ref.watch(appObserverLocationProvider);
  if (location == null) {
    return const ObserverDto(
      latitudeRad: 0,
      longitudeRad: 0,
      elevationM: 0,
      pressureHpa: kDefaultObserverPressureHpa,
      temperatureC: kDefaultObserverTemperatureC,
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
