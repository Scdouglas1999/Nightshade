import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('InteractiveSkyView quiesces on background and restores on resume',
      (tester) async {
    final fake = FakePlanetariumDriver();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const SizedBox(
              width: 400,
              height: 300,
              child: InteractiveSkyView(),
            );
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    final binding = WidgetsBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(fake.quiesceCallCount, 1);
    expect(
      fake.pushedGestures.any((e) => e.kind == GestureKindDto.cancel),
      isTrue,
    );
    expect(container.read(planetariumQuiescedProvider), isTrue);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(fake.restoreCallCount, 1);
    expect(container.read(planetariumQuiescedProvider), isFalse);
  });
}
