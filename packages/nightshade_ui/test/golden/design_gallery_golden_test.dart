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

  // The three boards above render `NightshadeDesignReferenceBoard`, which is
  // the PRE-overhaul component library. 05 §18 asks for the Observatory kit to
  // be in a golden too, and it lives in `NightshadeDesignSystemGallery`, so it
  // gets three captures of its own rather than displacing the existing ones.
  //
  // Captured at pixelRatio 1 because the sheet is ~5,000 logical pixels tall;
  // at 2 the PNG is 20 MB and no reviewer thanks you for it.
  const observatorySize = Size(1280, 5400);

  for (final entry in <String, ThemeData>{
    'dark': NightshadeTheme.dark,
    'light': NightshadeTheme.light,
    'rednight': NightshadeTheme.redNight,
  }.entries) {
    testWidgets('observatory component sheet — ${entry.key} theme', (
      tester,
    ) async {
      final file = await GoldenHarness.capture(
        tester,
        fileName: 'gallery-observatory-${entry.key}.png',
        theme: entry.value,
        size: observatorySize,
        pixelRatio: 1,
        child: const NightshadeDesignSystemGallery(),
      );
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1024));
      expect(tester.takeException(), isNull);
    });
  }
}
