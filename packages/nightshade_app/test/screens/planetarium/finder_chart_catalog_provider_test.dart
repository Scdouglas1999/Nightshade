import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/providers/finder_chart_catalog_provider.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  test('catalog failure is preserved instead of becoming an empty chart',
      () async {
    final container = ProviderContainer(
      overrides: [
        fovFilteredStarsProvider.overrideWithValue(
          AsyncValue<List<Star>>.error(
            StateError('star index unavailable'),
            StackTrace.current,
          ),
        ),
        fovFilteredDsosProvider.overrideWithValue(
          const AsyncValue<List<DeepSkyObject>>.data([]),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(finderChartCatalogSnapshotProvider.future),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('star index unavailable'),
        ),
      ),
    );
  });

  test('authoritative empty viewport remains a valid export snapshot',
      () async {
    final container = ProviderContainer(
      overrides: [
        fovFilteredStarsProvider.overrideWithValue(
          const AsyncValue<List<Star>>.data([]),
        ),
        fovFilteredDsosProvider.overrideWithValue(
          const AsyncValue<List<DeepSkyObject>>.data([]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final snapshot =
        await container.read(finderChartCatalogSnapshotProvider.future);

    expect(snapshot.stars, isEmpty);
    expect(snapshot.dsos, isEmpty);
  });
}
