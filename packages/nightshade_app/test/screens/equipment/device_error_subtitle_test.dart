// DEV-P3-4: widget test for the device-card subtitle line.
//
// When the owning device is in `DeviceConnectionState.error` and a raw
// driver message is available, the subtitle must surface the message
// (pretty-printed and truncated) with the full text in a tooltip — not
// fall back to the descriptive "Main imaging camera" blurb that the
// card normally shows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/utils/device_error_subtitle.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

NightshadeColors _testColors() {
  // Use the canonical theme so the widget under test gets every color
  // it reads. Fabricating partial NightshadeColors instances is brittle
  // — pull the real one for the dark theme.
  return NightshadeColors.dark;
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        // Bound the width so the Flexible inside the widget has a
        // concrete constraint; otherwise Flutter throws in tests.
        width: 240,
        child: child,
      ),
    ),
  );
}

void main() {
  group('DeviceErrorSubtitle — DEV-P3-4', () {
    testWidgets('renders descriptive subtitle when not in error', (tester) async {
      await tester.pumpWidget(_wrap(
        DeviceErrorSubtitle(
          descriptiveSubtitle: 'Main imaging camera',
          isError: false,
          errorMessage: null,
          colors: _testColors(),
        ),
      ));

      expect(find.text('Main imaging camera'), findsOneWidget);
      // No tooltip surface when we're not in error mode.
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('renders pretty-printed error subtitle when in error',
        (tester) async {
      await tester.pumpWidget(_wrap(
        DeviceErrorSubtitle(
          descriptiveSubtitle: 'Main imaging camera',
          isError: true,
          errorMessage:
              'Slew refused: ASCOM error 0x80040403 - device offline',
          colors: _testColors(),
        ),
      ));

      // Descriptive subtitle must be replaced.
      expect(find.text('Main imaging camera'), findsNothing);

      // Pretty-printed label is rendered — confirms the
      // PrettyError pipeline ran end-to-end.
      expect(find.textContaining('NotConnectedException'), findsOneWidget);

      // Tooltip wrapping must be present for the full message.
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('NotConnectedException'));
      expect(
        tooltip.message,
        contains('device offline'),
        reason: 'The full untouched raw message must be reachable via tooltip',
      );
    });

    testWidgets('falls back to descriptive subtitle when errorMessage is empty',
        (tester) async {
      // Defensive: if the state notifier reports error state but the
      // message slot is empty (e.g. a fail-open path we missed), the
      // widget must NOT render a misleading "isError UI" with no
      // content; it falls back to the descriptive subtitle.
      await tester.pumpWidget(_wrap(
        DeviceErrorSubtitle(
          descriptiveSubtitle: 'Main imaging camera',
          isError: true,
          errorMessage: '   ',
          colors: _testColors(),
        ),
      ));

      expect(find.text('Main imaging camera'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('unknown driver error passes through verbatim',
        (tester) async {
      // An error we cannot pretty-print must still surface, untouched.
      // This is the "errors are a feature" guarantee from CLAUDE.md.
      const raw = 'Touptek SDK: device not responding to ping';
      await tester.pumpWidget(_wrap(
        DeviceErrorSubtitle(
          descriptiveSubtitle: 'Main imaging camera',
          isError: true,
          errorMessage: raw,
          colors: _testColors(),
        ),
      ));

      // The raw message should appear in the subtitle as-is (no
      // prepended label).
      expect(find.text(raw), findsOneWidget);

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, raw);
    });
  });
}
