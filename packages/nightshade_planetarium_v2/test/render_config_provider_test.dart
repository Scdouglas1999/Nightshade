import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('renderConfigProvider pushes config to planetariumSetConfig',
      (tester) async {
    final fake = FakePlanetariumDriver();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const _RenderConfigSyncProbe(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_RenderConfigSyncProbe)),
    );
    container.read(renderConfigProvider.notifier).toggleStars();
    container.read(renderConfigProvider.notifier).toggleEcliptic();
    container.read(renderConfigProvider.notifier).setMagnitudeLimit(8.5);
    container.read(renderConfigProvider.notifier).setQuality(2);
    container.read(renderConfigProvider.notifier).setBortleClass(6);

    await tester.pump();

    expect(fake.lastConfig, isNotNull);
    expect(fake.lastConfig!.showStars, isFalse);
    expect(fake.lastConfig!.showEcliptic, isFalse);
    expect(fake.lastConfig!.magnitudeLimit, closeTo(8.5, 1e-9));
    expect(fake.lastConfig!.quality, 2);
    expect(fake.lastConfig!.bortleClass, 6);
    expect(fake.lastConfig!.showMilkyWay, isTrue);
    expect(fake.lastConfig!.twinkle, isTrue);
  });
}

class _RenderConfigSyncProbe extends ConsumerWidget {
  const _RenderConfigSyncProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(planetariumRenderConfigSyncProvider);
    return const SizedBox.shrink();
  }
}
