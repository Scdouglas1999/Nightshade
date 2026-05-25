import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/nightshade_planetarium_v2.dart';

import 'support/fake_planetarium_driver.dart';

void main() {
  testWidgets('selectionProvider pushes selection to planetariumSetSelection',
      (tester) async {
    final fake = FakePlanetariumDriver();
    final vega = SelectedObjectDto(
      objectId: BigInt.from(42),
      screenX: 640,
      screenY: 360,
      raRad: 1.5,
      decRad: 0.61,
      category: LabelCategoryDto.star,
      displayName: 'Vega',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planetariumHandleProvider.overrideWith((ref) async => fake),
        ],
        child: const _SelectionSyncProbe(),
      ),
    );

    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(_SelectionSyncProbe)),
    );
    container.read(selectionProvider.notifier).select(vega);

    await tester.pump();

    expect(fake.lastSelection, vega);

    container.read(selectionProvider.notifier).clear();

    await tester.pump();

    expect(fake.lastSelection, isNull);
  });
}

class _SelectionSyncProbe extends ConsumerWidget {
  const _SelectionSyncProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(planetariumSelectionSyncProvider);
    return const SizedBox.shrink();
  }
}
