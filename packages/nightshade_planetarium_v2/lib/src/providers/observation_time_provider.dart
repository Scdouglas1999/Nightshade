import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/planetarium_astro_time.dart';
import 'core_observation_time_provider.dart';
import 'planetarium_sync.dart';

/// Simulated/observed astronomical time for planetarium v2.
///
/// Derived from [coreObservationTimeProvider] ([nightshade_core] clock).
/// Override [coreObservationTimeProvider] in the host shell for time scrubbing.
final observationTimeProvider = Provider<PlanetariumAstroTime>((ref) {
  final dateTime = ref.watch(coreObservationTimeProvider);
  return PlanetariumAstroTime.fromDateTime(dateTime);
});

/// Mirrors [observationTimeProvider] into Rust via [planetariumSetTime].
final planetariumObservationTimeSyncProvider = Provider<void>((ref) {
  bindPlanetariumSync(
    ref,
    listenSource: observationTimeProvider,
    push: (driver, time) => driver.setTime(time.toDto()),
  );
});
