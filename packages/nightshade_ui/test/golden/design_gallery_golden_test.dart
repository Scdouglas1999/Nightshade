// Golden-screenshot harness for the Nightshade design language.
//
// Renders the full design-system reference board (semantic palette, domain
// palettes, the complete named typography scale, and the component library) in
// each shipped theme and writes the captured frame to docs/design/goldens/ for
// visual review. The PNGs are the deliverable; the assertions guard that the
// capture pipeline produced a real, non-empty image.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'golden_harness.dart';

void main() {
  // The reference board is tall — give the capture a generous logical canvas so
  // the whole board is in-frame (no scroll clipping in the rasterised PNG).
  const boardSize = Size(1360, 2600);

  testWidgets('design gallery — light theme', (tester) async {
    final file = await GoldenHarness.capture(
      tester,
      fileName: 'gallery-light.png',
      theme: NightshadeTheme.light,
      size: boardSize,
      child: const NightshadeDesignReferenceBoard(themeLabel: 'Light'),
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1024));
    expect(tester.takeException(), isNull);
  });

  testWidgets('design gallery — dark theme', (tester) async {
    final file = await GoldenHarness.capture(
      tester,
      fileName: 'gallery-dark.png',
      theme: NightshadeTheme.dark,
      size: boardSize,
      child: const NightshadeDesignReferenceBoard(themeLabel: 'Dark'),
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1024));
    expect(tester.takeException(), isNull);
  });

  testWidgets('design gallery — red night theme', (tester) async {
    final file = await GoldenHarness.capture(
      tester,
      fileName: 'gallery-rednight.png',
      theme: NightshadeTheme.redNight,
      size: boardSize,
      child: const NightshadeDesignReferenceBoard(themeLabel: 'Red Night'),
    );
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(1024));
    expect(tester.takeException(), isNull);
  });
}
