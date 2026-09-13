import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import 'golden/golden_harness.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(body: child),
  );

  testWidgets('exposes keyboard privacy controls', (tester) async {
    await tester.pumpWidget(
      wrap(
        const NightshadeTextField(autocorrect: false, enableSuggestions: false),
      ),
    );

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('obscured fields disable correction and suggestions by default', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const NightshadeTextField(obscureText: true)));

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets(
    'a 32px well centres its value with a sibling button and a FormRow label',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    NightshadeButton(label: 'Snapshot', onPressed: null),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: NightshadeTextField(
                        initialValue: '2.0',
                        prefixIcon: LucideIcons.clock,
                        suffix: 's',
                        mono: true,
                      ),
                    ),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 92,
                      child: NightshadeTextField(
                        initialValue: '100',
                        prefixIcon: LucideIcons.sliders,
                        mono: true,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                FormRow(
                  label: 'Exposure',
                  child: NightshadeTextField(
                    initialValue: '2.0',
                    suffix: 's',
                    mono: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final button = tester.getRect(find.byType(NightshadeButton));
      final fields = tester
          .widgetList<NightshadeTextField>(find.byType(NightshadeTextField))
          .toList();
      expect(fields, hasLength(3));

      final hudExposure = tester.getRect(
        find.byType(NightshadeTextField).at(0),
      );
      final hudGain = tester.getRect(find.byType(NightshadeTextField).at(1));
      expect(hudExposure.height, fieldHeight);
      expect(hudGain.height, fieldHeight);
      expect(hudExposure.center.dy, closeTo(button.center.dy, 0.5));
      expect(hudGain.center.dy, closeTo(button.center.dy, 0.5));

      final prefix = tester.getRect(find.byIcon(LucideIcons.clock));
      expect(prefix.center.dy, closeTo(hudExposure.center.dy, 0.5));

      final label = tester.getRect(find.text('Exposure'));
      final formField = tester.getRect(find.byType(NightshadeTextField).at(2));
      expect(formField.height, fieldHeight);
      expect(label.center.dy, closeTo(formField.center.dy, 0.5));
    },
  );

  testWidgets('the typed value sits on the well centre, with the unit', (
    tester,
  ) async {
    await GoldenHarness.ensureFonts();
    await tester.pumpWidget(
      wrap(
        const SizedBox(
          width: 160,
          child: NightshadeTextField(
            initialValue: '2.0',
            suffix: 's',
            mono: true,
          ),
        ),
      ),
    );

    final field = tester.getRect(find.byType(NightshadeTextField));
    final unit = tester.getRect(find.text('s'));
    final editable = tester.getRect(find.byType(EditableText));

    expect(
      editable.center.dy,
      closeTo(field.center.dy + fieldInkOffset.dy, 0.5),
      reason: 'ink is lifted $fieldInkOffset so caps sit on the well centre',
    );
    expect(unit.center.dy, closeTo(editable.center.dy, 0.5));
  });
}
