// Regression: SKY-5 — the planetarium's clock rewrote the Dashboard's.
//
// Found live. Stepping the planetarium transport ~20 h forward and returning
// to the Dashboard left its header reading 17:43 (Aug 14) labelled "Local"
// against a real 09:20 (Aug 13), LST 14:21:12 against 05:52, "Dark in 3h 54m"
// against 12h 19m and a 6% moon against 1% — with the app's status bar showing
// the true clock two inches away. Pressing NOW in the planetarium restored
// every value, which is what named the cause. "Dark in" is the number a user
// plans the evening around, and nothing said it was fictional.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  testWidgets('leaving the planetarium returns the app clock to now', (
    tester,
  ) async {
    final container = ProviderContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SimulatedTimeScope(child: SizedBox.shrink()),
        ),
      ),
    );

    container
        .read(observationTimeProvider.notifier)
        .setTime(DateTime(2030, 1, 1, 3, 30));
    expect(container.read(observationTimeProvider).isRealTime, isFalse);

    // The planetarium goes away; every other surface still reads this clock.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();

    final state = container.read(observationTimeProvider);
    expect(state.isRealTime, isTrue);
    expect(
      state.time.difference(DateTime.now()).abs(),
      lessThan(const Duration(minutes: 1)),
      reason: 'a simulated instant must not outlive the screen that made it',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
