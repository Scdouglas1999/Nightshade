// Regression: the Object types dialog must not move its action row when a
// chip is toggled.
//
// The 7 type chips live in a Wrap. Selecting one used to add a leading
// checkmark, which widened that chip, pushed the Wrap from 2 rows to 3, and
// slid the Clear/Apply row ~20 px down — live, a click aimed at Apply landed
// on empty space and the button had to be hunted for again. Selection is
// carried by the chip's fill and outline, so the checkmark bought nothing and
// cost the dialog its stable geometry.
//
// Driven through the sheet directly rather than through PlannerScreen: the
// planner runs a 1 s periodic sky clock, so `pumpAndSettle` never returns
// there and a screen-level test of this is slow and flaky rather than
// trustworthy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                showObjectTypeDialogForTest(
                  context: context,
                  colors: NightshadeColors.of(context),
                  selected: const <String>{},
                ).ignore();
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('selecting a type chip does not move the Apply button',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await openDialog(tester);

    final applyFinder = find.widgetWithText(NightshadeButton, 'Apply');
    final applyBefore = tester.getRect(applyFinder);
    final nebulaBefore =
        tester.getRect(find.widgetWithText(FilterChip, 'Nebula'));

    await tester.tap(find.widgetWithText(FilterChip, 'Nebula'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.widgetWithText(FilterChip, 'Nebula')),
      nebulaBefore,
      reason: 'a selected chip must keep the width it had unselected',
    );
    expect(
      tester.getRect(applyFinder),
      applyBefore,
      reason: 'the action row moved out from under the pointer',
    );
  });

  testWidgets('every chip keeps its geometry when the whole set is selected',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await openDialog(tester);

    final labels = <String>[
      'Galaxy',
      'Nebula',
      'Cluster',
      'Planetary',
      'Supernova Remnant',
      'Comet',
      'Asteroid',
    ];
    final before = {
      for (final label in labels)
        label: tester.getRect(find.widgetWithText(FilterChip, label)),
    };
    final applyBefore = tester.getRect(
      find.widgetWithText(NightshadeButton, 'Apply'),
    );

    for (final label in labels) {
      await tester.tap(find.widgetWithText(FilterChip, label));
      await tester.pumpAndSettle();
    }

    for (final label in labels) {
      expect(
        tester.getRect(find.widgetWithText(FilterChip, label)),
        before[label],
        reason: '$label moved or resized once selected',
      );
    }
    expect(
      tester.getRect(find.widgetWithText(NightshadeButton, 'Apply')),
      applyBefore,
    );
  });
}
