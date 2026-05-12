import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/calibration_section.dart';
import 'package:nightshade_app/screens/imaging/widgets/panel_widgets.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets(
    'CalibrationSection disables all controls when no camera is connected',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: NightshadeTheme.dark,
            home: Builder(
              builder: (context) {
                final colors =
                    Theme.of(context).extension<NightshadeColors>()!;
                return Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: CalibrationSection(colors: colors),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Image Calibration'), findsOneWidget);

      // Status block surfaces the disabled-reason copy.
      expect(
        find.textContaining('Connect a camera to manage its defect map.'),
        findsWidgets,
      );

      // The Build button is rendered, but disabled.
      final buildButton = tester.widget<SmallButton>(
        find.widgetWithText(SmallButton, 'Build defect map from current darks'),
      );
      expect(
        buildButton.isEnabled,
        isFalse,
        reason: 'Build button must be disabled when no camera is connected',
      );

      // The Clear button is rendered, but disabled.
      final clearButton = tester.widget<SmallButton>(
        find.widgetWithText(SmallButton,
            'Clear defect map for this camera at this temperature'),
      );
      expect(
        clearButton.isEnabled,
        isFalse,
        reason: 'Clear button must be disabled when no camera is connected',
      );

      // The "Apply during capture" toggle is rendered, but disabled.
      expect(find.text('Apply during capture'), findsOneWidget);
      final applySwitch = tester.widget<Switch>(find.byType(Switch));
      expect(applySwitch.onChanged, isNull,
          reason: 'Apply toggle must be disabled when no camera is connected');
      expect(applySwitch.value, isFalse,
          reason:
              'Apply toggle defaults to off when no defect map status is known');

      // The disabled state surfaces a Tooltip explaining the reason.
      final tooltipFinder = find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            (w.message ?? '')
                .contains('Connect a camera to manage its defect map.'),
      );
      expect(
        tooltipFinder,
        findsWidgets,
        reason:
            'Each disabled control must surface a Tooltip explaining why it '
            'is disabled.',
      );

      expect(tester.takeException(), isNull);
    },
  );
}
