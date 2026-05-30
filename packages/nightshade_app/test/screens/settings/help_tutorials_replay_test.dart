// Widget test for the Help & Tutorials "Open setup guide" replay control
// (Rich Progressive First-Launch Guide, C8).
//
// The progressive first-launch coach is replay-only after its single
// auto-launch: this row is its sole re-entry point. Tapping "Open" must
//   1. reset the coach's persistence row (FirstLaunchCoachDao.reset, which
//      flips the status back to FirstLaunchCoachStatus.pending), and
//   2. invalidate firstLaunchCoachStatusProvider so the shell launcher
//      (FirstLaunchCoachLauncher) re-resolves the gate and re-mounts the coach
//      immediately, with no app restart.
//
// We seed the coach to `completed` first so the reset is observable (a fresh
// row already reads pending). After the tap we assert the DAO reads back
// pending, proving the persistence write ran, and read the (invalidated)
// status provider's future to prove it re-resolves to pending.
//
// The screen calls context.go(...) on sibling rows, so — like the replay-hub
// test — it is pumped inside a MaterialApp.router with a /help route.

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

NightshadeDatabase _newInMemoryDb() =>
    NightshadeDatabase.forTesting(NativeDatabase.memory());

/// Pump [HelpTutorialsSettings] inside a MaterialApp.router. Returns the
/// container so the test can read the coach DAO / status provider after the tap.
Future<ProviderContainer> _pumpHelpScreen(
  WidgetTester tester, {
  required NightshadeDatabase db,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
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
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
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

  testWidgets('renders the "Open setup guide" coach replay row',
      (tester) async {
    final db = _newInMemoryDb();
    addTearDown(() async => db.close());

    await _pumpHelpScreen(tester, db: db);

    expect(find.text('Open setup guide'), findsOneWidget);
  });

  testWidgets(
      'tapping "Open" resets the coach DAO to pending and re-resolves the '
      'status provider', (tester) async {
    final db = _newInMemoryDb();
    addTearDown(() async => db.close());

    final container = await _pumpHelpScreen(tester, db: db);
    final dao = container.read(firstLaunchCoachDaoProvider);

    // Precondition: drive the coach to a terminal state so the reset is
    // observable. A pristine row already reads pending, which would make the
    // post-tap assertion pass vacuously.
    await dao.markCompleted();
    expect(
      await dao.getStatus(),
      FirstLaunchCoachStatus.completed,
      reason: 'precondition: the coach is completed before the reset',
    );

    // Target the "Open" button inside the "Open setup guide" SettingRow (the
    // "Generate Diagnostic Dump" row also has an "Open" button).
    final coachRow = find.ancestor(
      of: find.text('Open setup guide'),
      matching: find.byType(SettingRow),
    );
    expect(coachRow, findsOneWidget);
    final openButton = find.descendant(
      of: coachRow,
      matching: find.widgetWithText(NightshadeButton, 'Open'),
    );
    expect(openButton, findsOneWidget);

    await tester.tap(openButton);
    await tester.pumpAndSettle();

    // The persistence write ran: the DAO reads back pending.
    expect(
      await dao.getStatus(),
      FirstLaunchCoachStatus.pending,
      reason: 'tapping "Open" must reset the coach row back to pending',
    );

    // The status provider was invalidated and re-resolves to pending, which is
    // what FirstLaunchCoachLauncher watches to re-mount the coach.
    expect(
      await container.read(firstLaunchCoachStatusProvider.future),
      FirstLaunchCoachStatus.pending,
      reason:
          'the invalidated status provider must re-resolve to pending so the '
          'shell launcher re-mounts the coach without a restart',
    );
  });
}
