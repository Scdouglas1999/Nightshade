// Responsive widget tests for FlatWizardScreen.
//
// Verifies the flat-frame wizard lays out without RenderFlex overflow at the
// three reference phone sizes in BOTH orientations (per the mobile responsive
// standard) and that the screen identity ("Flat Frame Wizard") is present.
//
// On a phone the controls collapse into AdaptivePanelLayout (preview dominant,
// controls in a bottom sheet / landscape split) so the narrow controls column
// can no longer squish the sliders/inputs into overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nightshade_app/screens/flat_wizard/flat_wizard_screen.dart';

import '../../harness/harness.dart';

const _phonePortraitSizes = <Size>[
  Size(360, 640),
  Size(390, 844),
  Size(430, 932),
];

Future<void> _pumpAndCheck(WidgetTester tester, Size size) async {
  await pumpAppScreen(
    tester,
    const FlatWizardScreen(),
    size: size,
    settle: false,
  );
  // Drain the post-frame loadFiltersFromWheel() and any tab animation.
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }

  expect(
    tester.takeException(),
    isNull,
    reason:
        'FlatWizardScreen must not overflow at ${size.width}x${size.height}',
  );
  // The screen identity is asserted via the Semantics label on the header
  // icon, not via visible text: on a phone the title intentionally folds to
  // icon-only (the wide "Flat Frame Wizard" label is dropped so the tab strip
  // never overflows), so a `find.text` would be absent by design at these
  // narrow widths. The Semantics label rides the icon at every size.
  expect(find.bySemanticsLabel('Flat Frame Wizard'), findsOneWidget,
      reason: 'Flat wizard header identity must be present at '
          '${size.width}x${size.height}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in _phonePortraitSizes) {
    testWidgets(
      'FlatWizardScreen lays out without overflow at '
      '${size.width.toInt()}x${size.height.toInt()} (portrait)',
      (tester) async {
        await _pumpAndCheck(tester, size);
      },
    );

    final landscape = Size(size.height, size.width);
    testWidgets(
      'FlatWizardScreen lays out without overflow at '
      '${landscape.width.toInt()}x${landscape.height.toInt()} (landscape)',
      (tester) async {
        await _pumpAndCheck(tester, landscape);
      },
    );
  }
}
