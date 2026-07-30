// Regression: the shared angle-filter sheet must not apply a value the user
// never chose.
//
// The moon chip read "Moon: any" (the filter was unset) while the sheet opened
// with its slider parked at 30° and its readout showing "30°" —
// `initial: value ?? 30.0`. Pressing Apply without touching anything therefore
// committed 30°: observed live, the chip flipped to "Moon ≥ 30" and the candidate
// count dropped from 1202 to 1174 on a limit nobody set. A filter that silently
// narrows results is the worst form of this defect, because the targets it removes
// look like they simply are not up tonight.
//
// The sheet keeps 30° as the slider's starting POSITION (a genuinely useful hint,
// and for the altitude chip it is derived from the horizon profile) but now reads
// "Any" and disables Apply until the slider moves, so a limit can only be
// committed deliberately. The altitude chip shares this sheet and had the same
// flaw, which is why the fix lives in the sheet rather than in one call site.
//
// Driven through the sheet directly rather than through PlannerScreen: the planner
// runs a 1 s periodic sky clock, so `pumpAndSettle` never returns there and a
// screen-level test of this is slow and flaky rather than trustworthy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  /// Host with a Navigator and a theme and nothing else — no providers, no
  /// timers, so every pump is deterministic.
  ///
  /// Returns the sheet's future so a case can assert on the committed value; the
  /// cases that only inspect the rendered dialog call `.ignore()` on it.
  Future<Future<double?>> openSheet(
    WidgetTester tester, {
    required bool isSet,
    double initial = 30.0,
  }) async {
    Future<double?>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                result = showAngleSliderForTest(
                  context: context,
                  colors: NightshadeColors.of(context),
                  title: 'Minimum moon separation',
                  unit: '°',
                  initial: initial,
                  min: 0,
                  max: 180,
                  isSet: isSet,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result!;
  }

  NightshadeButton applyButton(WidgetTester tester) =>
      tester.widget<NightshadeButton>(
        find.ancestor(
          of: find.text('Apply'),
          matching: find.byType(NightshadeButton),
        ),
      );

  testWidgets('an unset filter opens reporting "Any", with Apply disabled',
      (tester) async {
    (await openSheet(tester, isSet: false)).ignore();

    expect(
      find.text('Any'),
      findsOneWidget,
      reason: 'the sheet must not display a limit for a filter that has none',
    );
    expect(
      find.text('30°'),
      findsNothing,
      reason:
          'showing 30° makes an invented value look like the current setting',
    );
    expect(
      find.text('No limit is set. Drag the slider to choose one.'),
      findsOneWidget,
    );
    expect(
      applyButton(tester).onPressed,
      isNull,
      reason: 'an enabled Apply here is exactly what silently committed 30°',
    );
  });

  testWidgets('moving the slider enables Apply and reports the real value',
      (tester) async {
    (await openSheet(tester, isSet: false)).ignore();

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(
      find.text('Any'),
      findsNothing,
      reason: 'once touched the sheet reports the value it will apply',
    );
    expect(
      find.text('No limit is set. Drag the slider to choose one.'),
      findsNothing,
    );
    expect(
      applyButton(tester).onPressed,
      isNotNull,
      reason: 'a deliberate choice must still be applicable',
    );
  });

  testWidgets('an already-set filter is applicable immediately and unchanged',
      (tester) async {
    // Re-applying an existing limit unchanged is a harmless no-op, so an ACTIVE
    // filter must not be forced to touch the slider first.
    (await openSheet(tester, isSet: true, initial: 45.0)).ignore();

    expect(find.text('45°'), findsOneWidget);
    expect(find.text('Any'), findsNothing);
    expect(applyButton(tester).onPressed, isNotNull);
  });

  testWidgets('Clear stays reachable from an unset sheet', (tester) async {
    // Clear must work even while Apply is disabled, or an unset sheet is a dead
    // end the user can only dismiss.
    final future = await openSheet(tester, isSet: false);

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    final value = await future;
    expect(
      value?.isNaN,
      isTrue,
      reason: 'NaN is the sheet\'s documented "clear the filter" sentinel',
    );
  });
}
