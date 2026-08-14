// WD-EQ-3: one failed connect of the built-in guider raised FOUR statements of
// one refusal — the same "Guider Error … requires an active profile with a
// guide focal length" toast TWICE (Dart connect path via ErrorService, plus the
// backend's error event via event_provider), an "Equipment disconnected" toast
// for a device that never connected, and the Connection help dialog behind all
// three.
//
// The overlay is the one place every producer converges, so that is where the
// repetition is collapsed. These tests reproduce the exact double toast.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/notification_toast_overlay.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../harness/mock_database.dart' show inMemoryDatabaseOverride;

const _guiderRefusal =
    'Built-in guider requires an active profile with a guide focal length';

Future<void> _pumpOverlay(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: Stack(children: [NotificationToastOverlay()]),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two producers of one refusal render as one toast', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [inMemoryDatabaseOverride()],
    );
    addTearDown(container.dispose);
    final notifier = container.read(uiNotificationProvider.notifier);

    // Verbatim from the Wave E repro: the identical toast twice, then the
    // (different) disconnect toast.
    notifier.showError(
      _guiderRefusal,
      title: 'Guider Error',
      duration: const Duration(minutes: 1),
    );
    notifier.showError(
      _guiderRefusal,
      title: 'Guider Error',
      duration: const Duration(minutes: 1),
    );
    notifier.showError(
      'Guider Built-in Multi-Star Guider disconnected.',
      title: 'Equipment disconnected',
      duration: const Duration(minutes: 1),
    );

    await _pumpOverlay(tester, container);

    // One row for the refusal, not two.
    expect(find.text(_guiderRefusal), findsOneWidget);
    // And it says it happened twice rather than hiding the repeat.
    expect(find.text('Guider Error (x2)'), findsOneWidget);
    expect(find.text('Guider Error'), findsNothing);
    // The genuinely different toast is still its own row.
    expect(find.text('Equipment disconnected'), findsOneWidget);
  });

  testWidgets('dismissing a collapsed toast retires every copy', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [inMemoryDatabaseOverride()],
    );
    addTearDown(container.dispose);
    final notifier = container.read(uiNotificationProvider.notifier);
    for (var i = 0; i < 3; i++) {
      notifier.showError(
        _guiderRefusal,
        title: 'Guider Error',
        duration: const Duration(minutes: 1),
      );
    }

    await _pumpOverlay(tester, container);
    expect(find.text('Guider Error (x3)'), findsOneWidget);

    await tester.tap(find.text(_guiderRefusal));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // If only the rendered copy were dismissed, its twins would pop straight
    // back up as a "(x2)" toast.
    expect(container.read(uiNotificationProvider), isEmpty);
    expect(find.text(_guiderRefusal), findsNothing);
  });

  testWidgets('distinct notifications are never merged', (tester) async {
    final container = ProviderContainer(
      overrides: [inMemoryDatabaseOverride()],
    );
    addTearDown(container.dispose);
    final notifier = container.read(uiNotificationProvider.notifier);
    notifier.showError('Mount disconnected.',
        title: 'Mount Error', duration: const Duration(minutes: 1));
    notifier.showError('Focuser disconnected.',
        title: 'Focuser Error', duration: const Duration(minutes: 1));

    await _pumpOverlay(tester, container);

    expect(find.text('Mount Error'), findsOneWidget);
    expect(find.text('Focuser Error'), findsOneWidget);
  });
}
