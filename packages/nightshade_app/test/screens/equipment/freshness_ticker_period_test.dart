// Regression: the "Last checked … ago" age label must tick FASTER than the poll
// whose age it reports.
//
// The equipment card's freshness ticker used `Duration(seconds: 5)` — the same
// period as `DeviceService.environmentPollInterval` — reasoned as "advance the
// label at the same cadence the reading can change". That reasoning is what broke
// it. Sampling an age at exactly the period of the thing being aged yields a
// CONSTANT: the fixed phase offset between the two timers, not elapsed time. Both
// timers also start from the same event (connect calls
// `_ensureEnvironmentPolling()`; the card's `initState` starts the ticker
// milliseconds later), so the offset was ~0 and the label read "0s ago"
// permanently — 42 consecutive live samples over ~50 s on a real rig never showed
// any other value. It changed only when the card was re-mounted at a different
// tick phase, which is the proof it was a phase artifact rather than an age.
//
// This asserts the RELATIONSHIP, not the literal 1 s, because the relationship is
// what was wrong: any future edit that sets the ticker back to the poll period
// (or slower) reintroduces the exact defect and fails here. A widget test cannot
// substitute: the ticker samples the real `DateTime.now()`, so `tester.pump`
// advances Flutter's fake timer clock without moving the value being displayed.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/widgets/connected_device_card.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  test('the freshness ticker samples faster than the environmental poll', () {
    expect(
      ConnectedDeviceCard.freshnessTick,
      lessThan(DeviceService.environmentPollInterval),
      reason:
          'an age label that ticks at the poll period displays the constant '
          'phase offset between the two timers, not the elapsed time — this is '
          'the "0s ago" forever defect',
    );
  });

  test('the ticker is fine-grained enough to render every age it can show', () {
    // The label prints whole seconds and the age it describes spans
    // 0..environmentPollInterval. To be capable of rendering each of those
    // values the clock has to advance at most one second at a time; a 2 s tick
    // would skip half of them.
    expect(
      ConnectedDeviceCard.freshnessTick,
      lessThanOrEqualTo(const Duration(seconds: 1)),
      reason: 'the label is second-granular, so a coarser tick silently skips '
          'values it claims to display',
    );
    expect(
      ConnectedDeviceCard.freshnessTick,
      greaterThan(Duration.zero),
      reason: 'a zero/negative period would spin the UI thread',
    );
  });
}
