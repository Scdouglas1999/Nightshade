import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// UTC observation instant from [nightshade_core] clock + shared tick stream.
///
/// Override in the host shell when a simulated clock is active (for example
/// wire to planetarium v1 `observationTimeProvider.time`).
final coreObservationTimeProvider = Provider<DateTime>((ref) {
  ref.watch(tickerProvider(TickerCadence.oneSecond));
  return ref.watch(clockProvider).now().toUtc();
});
