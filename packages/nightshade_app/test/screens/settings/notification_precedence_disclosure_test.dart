// SET-28: the Notifications leaf shipped three overlapping systems at once and
// offered three near-identically named controls for "a sequence finished" —
// Notification Events › Sequence complete, Push to Mobile › Sequence completed,
// and Per-event routing › Sequence Completed — with nothing telling the
// operator which one decides whether their phone buzzes. The first of the three
// is worse than ambiguous: no delivery path reads it at all, so it was an
// armed-looking guarantee for an unattended night that could never fire.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/notification_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/settings_widgets.dart';

import '../../harness/harness.dart';

Future<void> _pump(WidgetTester tester) async {
  await pumpAppScreen(
    tester,
    const NotificationSettings(),
    size: const Size(1000, 1600),
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the leaf says which system actually delivers', (tester) async {
    await _pump(tester);

    expect(
      find.textContaining('Per-event routing (Settings → Notification Routing) '
          'maps each event to its transports and is what actually delivers'),
      findsOneWidget,
    );
  });

  testWidgets('the unwired event switches are inoperable and say why',
      (tester) async {
    await _pump(tester);

    final row = find.ancestor(
      of: find.text('Sequence complete'),
      matching: find.byType(SettingRow),
    );
    expect(row, findsOneWidget);

    final toggle = tester.widget<SettingsSwitch>(
      find.descendant(of: row, matching: find.byType(SettingsSwitch)),
    );
    expect(
      toggle.enabled,
      isFalse,
      reason: 'a switch nothing reads must not look armed',
    );
    expect(
      find.descendant(
        of: row,
        matching: find.textContaining('no longer sends anything'),
      ),
      findsOneWidget,
    );
  });
}
