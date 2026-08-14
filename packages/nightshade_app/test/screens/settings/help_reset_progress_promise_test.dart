// WD-N8: "Reset All Progress" promised a tour it did not bring back.
//
// Live on 2026-08-13: Settings → Help & Tutorials → Reset All Progress →
// confirm ("This will clear all tutorial progress and you will see the welcome
// tour again."). Returning to the Dashboard in the same session showed no tour
// and no nudge — a grep of the accessibility tree for "tour|tutorial" came
// back empty.
//
// The rows ARE deleted from the database. What was not done is telling the
// running app: the dismissed coach-mark set is held in memory, and the
// first-launch tour's status is a cached future, so both still said "already
// seen" for the rest of the session.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/settings/widgets/help_tutorials_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/settings_widgets.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

Future<ProviderContainer> _pumpHelp(
  WidgetTester tester,
  NightshadeDatabase db,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 1600);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      backendProvider.overrideWith(
        (ref) => TestBackendNotifier(ref, mockBackend()),
      ),
      databaseProvider.overrideWithValue(db),
      appVersionProvider.overrideWithValue(
        const AppVersionInfo(version: '0.0.0-test', buildNumber: 0),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/help',
    routes: [
      GoRoute(
        path: '/help',
        builder: (context, state) =>
            const Scaffold(body: HelpTutorialsSettings()),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: NightshadeTheme.dark,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resetting progress really does bring the welcome tour back',
      (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());

    final container = await _pumpHelp(tester, db);

    // The operator has been through the app once: a coach mark was dismissed
    // on the dashboard and the welcome tour was completed.
    final dismissed = container.read(dismissedTourPromptsProvider.notifier);
    await dismissed.ready;
    await dismissed.dismissPrompt('dashboard');
    await container.read(onboardingTourProvider.notifier).complete();
    await tester.pumpAndSettle();

    expect(container.read(dismissedTourPromptsProvider), contains('dashboard'));
    expect(
      await container.read(firstLaunchTourStatusProvider.future),
      isNot(FirstLaunchTourStatus.pending),
      reason: 'precondition: the welcome tour is not waiting to run',
    );

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Reset all progress'),
          matching: find.byType(SettingRow),
        ),
        matching: find.widgetWithText(NightshadeButton, 'Reset'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(NightshadeButton, 'Reset'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(dismissedTourPromptsProvider),
      isEmpty,
      reason: 'a dismissed coach mark that survives the reset is a nudge the '
          'operator was told they would see again',
    );
    expect(
      await container.read(firstLaunchTourStatusProvider.future),
      FirstLaunchTourStatus.pending,
      reason: 'the dialog says "you will see the welcome tour again"',
    );
  });
}
