// Regression: flipping the "Coordinate grid" master must actually draw a grid.
//
// The renderer needs the master AND a frame flag — `paint_lifecycle.dart` gates
// on `showCoordinateGrid && (showEquatorialGrid || showAltAzGrid)` — and all
// three default to `false` in `const SkyRenderConfig()`. Nothing in the app ever
// seeded one, so on a stock install the first action in that group (turn on
// "Coordinate grid") moved the switch and changed the sky by 99 pixels out of
// 712,800, all of them a single marker glyph.
//
// An earlier fix reorganised the panel so the master reads first with the frame
// switches indented and disabled beneath it. That made the hierarchy legible but
// relocated the defect onto the master, on the default path — the control still
// reported success and did nothing.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  /// A frame flag is what the renderer actually requires; the master alone is
  /// not sufficient. This mirrors the renderer's own gate so the test fails for
  /// the same reason the screen was blank.
  bool wouldDrawGrid(SkyRenderConfig c) =>
      c.showCoordinateGrid && (c.showEquatorialGrid || c.showAltAzGrid);

  test('turning the master on from defaults draws a grid', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final before = container.read(skyRenderConfigProvider);
    expect(
      wouldDrawGrid(before),
      isFalse,
      reason: 'sanity: the stock config draws no grid',
    );

    container.read(skyRenderConfigProvider.notifier).toggleGrid();
    final after = container.read(skyRenderConfigProvider);

    expect(after.showCoordinateGrid, isTrue);
    expect(
      wouldDrawGrid(after),
      isTrue,
      reason:
          'the master went on but no frame was selected, so the renderer '
          'still draws nothing — the switch reports success and does nothing',
    );
  });

  test('the frame chosen matches the view the user is looking at', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(skyViewStateProvider.notifier)
        .setViewMode(
          SkyViewMode.horizontal,
          observer: container.read(observerLocationProvider),
          instant: DateTime.utc(2026, 7, 29, 15, 52),
        );
    container.read(skyRenderConfigProvider.notifier).toggleGrid();

    final config = container.read(skyRenderConfigProvider);
    expect(
      config.showAltAzGrid,
      isTrue,
      reason: 'in the horizontal frame the alt/az grid is the one that belongs',
    );
    expect(config.showEquatorialGrid, isFalse);
    expect(wouldDrawGrid(config), isTrue);
  });

  test('an existing frame choice is respected, not overwritten', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(skyRenderConfigProvider.notifier);
    notifier.toggleEquatorialGrid();
    notifier.toggleGrid();

    final config = container.read(skyRenderConfigProvider);
    expect(config.showEquatorialGrid, isTrue);
    expect(
      config.showAltAzGrid,
      isFalse,
      reason:
          'the user had already picked a frame; the master must not add '
          'another one on top of it',
    );
  });

  test('toggling the master off and on remembers the frame', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(skyRenderConfigProvider.notifier);
    notifier.toggleGrid();
    final chosen = container.read(skyRenderConfigProvider);

    notifier.toggleGrid();
    final off = container.read(skyRenderConfigProvider);
    expect(off.showCoordinateGrid, isFalse);
    expect(
      wouldDrawGrid(off),
      isFalse,
      reason: 'the master is off, so nothing draws regardless of the frame',
    );
    expect(
      off.showEquatorialGrid,
      chosen.showEquatorialGrid,
      reason: 'turning the master off must not discard the frame selection',
    );
    expect(off.showAltAzGrid, chosen.showAltAzGrid);

    notifier.toggleGrid();
    expect(wouldDrawGrid(container.read(skyRenderConfigProvider)), isTrue);
  });
}
