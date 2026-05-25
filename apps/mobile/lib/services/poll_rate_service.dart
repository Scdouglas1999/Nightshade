// Wave 6D / P2-14 — Mobile poll-rate computation.
//
// Combines the BatteryService snapshot with NetworkService's connectivity
// state into a single "what cadence should background pollers run at?"
// answer. Live-preview, catalog-sync, and dashboard hydrate pollers all
// read [effectivePollIntervalProvider] (constructed via
// [pollIntervalFor]) and use the returned Duration directly in their
// Timer.periodic, so a single source of truth governs every periodic
// network hit on cellular or low-power state.
//
// The rule is intentionally simple:
//   * No throttling on WiFi at >= 20% battery (or charging).
//   * Divide the base interval by [throttledPollMultiplier] reciprocally
//     (i.e. multiply by 3) on low-power OR cellular.
//
// We do NOT try to be clever (e.g. throttle harder at 5% battery) because
// the operator already has explicit affordances for that case
// (PowerService notification, foreground-service pause). One simple rule
// is testable; a tiered rule would be argued-about and never tuned.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/battery_service.dart';
import '../services/network_service.dart';

/// Computed effective polling cadence given [base] and the current
/// {battery, connectivity} state. Pure function so the unit test can pin
/// the multiplier without spinning up Riverpod.
Duration pollIntervalFor({
  required Duration base,
  required PhoneBatteryState battery,
  required bool onCellular,
}) {
  if (shouldThrottlePolling(battery: battery, onCellular: onCellular)) {
    return base * throttledPollMultiplier;
  }
  return base;
}

/// Riverpod-friendly version. Pass the [base] interval and the family
/// resolves to the throttled value:
///
///     final interval = ref.watch(effectivePollIntervalProvider(
///       const Duration(seconds: 10),
///     ));
final effectivePollIntervalProvider =
    Provider.family<Duration, Duration>((ref, base) {
  final battery = ref.watch(batteryStateProvider).valueOrNull ??
      PhoneBatteryState.unknown;
  // NetworkService is a singleton-style service exposing currentState
  // synchronously; reading it directly here keeps the provider pure
  // even though the underlying state is mutable (the watch above ticks
  // when battery changes; consumers that need cellular changes too can
  // listen to NetworkService.stateStream and ref.invalidate this
  // provider themselves).
  final onCellular = NetworkService().currentState.hasMobile &&
      !NetworkService().currentState.hasWifi;
  return pollIntervalFor(
    base: base,
    battery: battery,
    onCellular: onCellular,
  );
});
