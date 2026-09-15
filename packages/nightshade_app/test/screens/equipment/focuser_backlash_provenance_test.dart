// The precedence story, on the surface where the operator types a number.
//
// A value somebody typed always wins. The measurement alongside it must be
// visible AND be visibly inactive — never silently replaced, never implied to
// be in force.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/focuser_backlash/effective_backlash_readout.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';
import '../../widgets/focuser_backlash/backlash_fixtures.dart';

Future<List<int>> _pump(
  WidgetTester tester, {
  required EffectiveFocuserBacklash effective,
  FocuserBacklashCalibrationRecord? saved,
}) async {
  final adopted = <int>[];
  await pumpAppScreen(
    tester,
    EffectiveBacklashReadout(onUseMeasured: adopted.add),
    size: const Size(600, 500),
    extraOverrides: [
      effectiveFocuserBacklashProvider.overrideWithValue(effective),
      savedFocuserBacklashProvider.overrideWith((ref) => saved),
    ],
  );
  return adopted;
}

void main() {
  testWidgets('a measured figure is quoted with where it came from', (
    tester,
  ) async {
    await _pump(
      tester,
      effective: EffectiveFocuserBacklash(
        steps: 105,
        origin: FocuserBacklashOrigin.measured,
        provenance: 'measured on 2026-09-14 at position 6620, 14.5 °C',
        record: record105(),
      ),
      saved: record105(),
    );

    expect(
      find.text(
        '105 steps, measured on 2026-09-14 at position 6620, 14.5 °C.',
      ),
      findsOneWidget,
    );
    // The single most important caveat about any backlash figure.
    expect(find.textContaining('varies along the travel'), findsOneWidget);
    expect(
      find.widgetWithText(NightshadeButton, 'Measure again'),
      findsOneWidget,
    );
  });

  testWidgets('says plainly when nothing is in force', (tester) async {
    await _pump(
      tester,
      effective: const EffectiveFocuserBacklash(
        steps: 0,
        origin: FocuserBacklashOrigin.none,
        provenance: 'this focuser has not been measured and you have not '
            'entered a figure',
      ),
    );

    expect(
      find.text(
        'Backlash compensation is off: this focuser has not been measured '
        'and you have not entered a figure.',
      ),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(NightshadeButton, 'Calibrate backlash'),
      findsOneWidget,
    );
  });

  group('a typed value outranks a measurement', () {
    testWidgets('states which one is in force and which is only on record', (
      tester,
    ) async {
      await _pump(
        tester,
        effective: const EffectiveFocuserBacklash(
          steps: 60,
          origin: FocuserBacklashOrigin.operatorEntered,
          provenance: 'the value you entered',
        ),
        saved: record105(),
      );

      expect(find.text('60 steps, the value you entered.'), findsOneWidget);
      expect(
        find.textContaining('Your value is the one in force'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'A measurement of 105 steps (measured on 14 Sep 2026 at position '
          '6620) is on record and is NOT being used.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('adopting the measurement is an explicit act', (tester) async {
      final adopted = await _pump(
        tester,
        effective: const EffectiveFocuserBacklash(
          steps: 60,
          origin: FocuserBacklashOrigin.operatorEntered,
          provenance: 'the value you entered',
        ),
        saved: record105(),
      );

      expect(adopted, isEmpty);
      await tester.tap(
        find.widgetWithText(NightshadeButton, 'Use the measured 105'),
      );
      await tester.pump();
      expect(adopted, [105]);
    });

    testWidgets('does not nag when the typed value matches the measurement', (
      tester,
    ) async {
      await _pump(
        tester,
        effective: const EffectiveFocuserBacklash(
          steps: 105,
          origin: FocuserBacklashOrigin.operatorEntered,
          provenance: 'the value you entered',
        ),
        saved: record105(),
      );

      expect(
        find.textContaining('Your value matches the measurement on record'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(NightshadeButton, 'Use the measured 105'),
        findsNothing,
      );
    });

    testWidgets(
      'a no-measurable-backlash record is described as a finding, not as zero',
      (tester) async {
        await _pump(
          tester,
          effective: const EffectiveFocuserBacklash(
            steps: 60,
            origin: FocuserBacklashOrigin.operatorEntered,
            provenance: 'the value you entered',
          ),
          saved: FocuserBacklashCalibrationRecord(
            steps: 0,
            measurable: false,
            resolutionLimitSteps: 15,
            measuredAtPosition: 6620,
            temperatureCelsius: 14.5,
            measuredAt: takenAt,
            confidence: FocuserBacklashConfidence.high,
            confidenceReason: 'Both fits are tight.',
            appVersion: '7.0.0+28',
          ),
        );

        expect(
          find.textContaining('found no backlash larger than 15 steps'),
          findsOneWidget,
        );
        // Never "a measurement of 0 steps" — that reads as a failed run.
        expect(find.textContaining('measurement of 0 steps'), findsNothing);
        expect(
          find.widgetWithText(NightshadeButton, 'Use the measured 0'),
          findsNothing,
        );
      },
    );
  });
}
