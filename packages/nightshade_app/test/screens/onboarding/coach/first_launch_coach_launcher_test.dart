import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/onboarding/coach/first_launch_coach_launcher.dart';
import 'package:nightshade_app/screens/onboarding/coach/first_launch_coach_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_ui/nightshade_ui.dart';

/// A fresh-install readiness report: every item blocked. This is the state the
/// coach is built for, so when the launcher mounts the panel it renders the
/// in-progress checklist (and crucially never reaches `allComplete`, so the
/// panel's one-shot completion write does not fire during a gating smoke test).
const _blockedReport = ReadinessReport(
  items: [
    ReadinessItem(
      id: ReadinessItemId.criticalDevices,
      title: 'Critical devices',
      detail: 'No equipment profile is set up yet.',
      level: ReadinessLevel.blocked,
      fixRoute: '/equipment',
      fixLabel: 'Set up equipment',
    ),
    ReadinessItem(
      id: ReadinessItemId.location,
      title: 'Observing location',
      detail: 'No location is set.',
      level: ReadinessLevel.blocked,
      fixRoute: '/settings?section=location',
      fixLabel: 'Set location',
    ),
    ReadinessItem(
      id: ReadinessItemId.outputPath,
      title: 'Output folder',
      detail: 'No output folder is set.',
      level: ReadinessLevel.blocked,
      fixRoute: '/settings?section=file-paths',
      fixLabel: 'Set output folder',
    ),
    ReadinessItem(
      id: ReadinessItemId.plateSolver,
      title: 'Plate solver',
      detail: 'No plate solver is configured.',
      level: ReadinessLevel.blocked,
      fixRoute: '/settings?section=plate-solving',
      fixLabel: 'Set up solving',
    ),
    ReadinessItem(
      id: ReadinessItemId.darkLibrary,
      title: 'Dark library',
      detail: 'No master darks.',
      level: ReadinessLevel.blocked,
      fixRoute: '/settings?section=dark-library',
      fixLabel: 'Open dark library',
    ),
    ReadinessItem(
      id: ReadinessItemId.focusState,
      title: 'Focus',
      detail: 'Focus not established.',
      level: ReadinessLevel.blocked,
      fixRoute: '/equipment',
      fixLabel: 'Open equipment',
    ),
  ],
);

/// A fully-ready readiness report: every item green. This drives the panel into
/// its terminal celebration mode (the "Capture first light" hand-off), which is
/// the surface the launcher must keep mounted through the completion write.
const _readyReport = ReadinessReport(
  items: [
    ReadinessItem(
      id: ReadinessItemId.criticalDevices,
      title: 'Critical devices',
      detail: 'Camera and mount are connected.',
      level: ReadinessLevel.ready,
    ),
    ReadinessItem(
      id: ReadinessItemId.location,
      title: 'Observing location',
      detail: 'Location is set.',
      level: ReadinessLevel.ready,
    ),
    ReadinessItem(
      id: ReadinessItemId.outputPath,
      title: 'Output folder',
      detail: 'Output folder is set.',
      level: ReadinessLevel.ready,
    ),
    ReadinessItem(
      id: ReadinessItemId.plateSolver,
      title: 'Plate solver',
      detail: 'Plate solver ready.',
      level: ReadinessLevel.ready,
    ),
    ReadinessItem(
      id: ReadinessItemId.darkLibrary,
      title: 'Dark library',
      detail: 'Master darks present.',
      level: ReadinessLevel.ready,
    ),
    ReadinessItem(
      id: ReadinessItemId.focusState,
      title: 'Focus',
      detail: 'Focus established.',
      level: ReadinessLevel.ready,
    ),
  ],
);

/// Pumps [FirstLaunchCoachLauncher] wrapping a trivial child, with the coach
/// status overridden to [status] and the readiness report overridden to the
/// fresh-install blocked report. The DAO is backed by an in-memory DB so the
/// panel's completion path (unused here) has a real store if it ever runs.
Future<void> _pumpLauncher(
  WidgetTester tester, {
  required db.NightshadeDatabase database,
  required FirstLaunchCoachStatus status,
}) async {
  // The full fresh-install checklist is tall; give the test surface enough
  // height that the panel renders without an overflow artifact (in the real
  // app the shell provides ample vertical room beneath the title bar).
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        readinessReportProvider.overrideWithValue(_blockedReport),
        firstLaunchCoachStatusProvider
            .overrideWith((ref) async => status),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: FirstLaunchCoachLauncher(
            child: Center(child: Text('shell-content')),
          ),
        ),
      ),
    ),
  );
  // The status FutureProvider resolves on a microtask; pump frames to let the
  // launcher react. We avoid `pumpAndSettle` because the blocked checklist
  // renders a forever-pulsing urgent StatusDot (an unbounded animation), which
  // would make `pumpAndSettle` time out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.NightshadeDatabase database;

  setUp(() {
    database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('always renders the wrapped child', (tester) async {
    await _pumpLauncher(
      tester,
      database: database,
      status: FirstLaunchCoachStatus.pending,
    );

    expect(find.text('shell-content'), findsOneWidget);
  });

  testWidgets('status pending → coach panel is mounted over the shell',
      (tester) async {
    await _pumpLauncher(
      tester,
      database: database,
      status: FirstLaunchCoachStatus.pending,
    );

    expect(find.byType(FirstLaunchCoachPanel), findsOneWidget);
    // The child stays in the tree underneath the overlay.
    expect(find.text('shell-content'), findsOneWidget);
  });

  testWidgets('status completed → coach panel is absent', (tester) async {
    await _pumpLauncher(
      tester,
      database: database,
      status: FirstLaunchCoachStatus.completed,
    );

    expect(find.byType(FirstLaunchCoachPanel), findsNothing);
    expect(find.text('shell-content'), findsOneWidget);
  });

  testWidgets('status dismissed → coach panel is absent', (tester) async {
    await _pumpLauncher(
      tester,
      database: database,
      status: FirstLaunchCoachStatus.dismissed,
    );

    expect(find.byType(FirstLaunchCoachPanel), findsNothing);
    expect(find.text('shell-content'), findsOneWidget);
  });

  testWidgets(
      'status unknown / still loading → coach panel is absent (fails closed)',
      (tester) async {
    // Override with a future that never completes, so the provider stays in its
    // loading state and `valueOrNull` is null — the launcher must not mount the
    // coach on an unresolved read.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          readinessReportProvider.overrideWithValue(_blockedReport),
          firstLaunchCoachStatusProvider.overrideWith(
            (ref) => Completer<FirstLaunchCoachStatus>().future,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FirstLaunchCoachLauncher(
              child: Center(child: Text('shell-content')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FirstLaunchCoachPanel), findsNothing);
    expect(find.text('shell-content'), findsOneWidget);
  });

  testWidgets(
      'all-ready completion keeps the celebration + "Capture first light" CTA '
      'mounted under the launcher, and does not re-appear next launch',
      (tester) async {
    // This is the integration regression for the completion path: the launcher
    // gate (which only shows on `pending`) and the panel's self-completion write
    // are exercised together against a real DB-backed status provider. The
    // status provider is intentionally NOT overridden, so it resolves `pending`
    // from the empty store, the launcher mounts the panel, and the panel's
    // listener persists `completed`. If completion invalidated the status
    // provider, the gate would flip to `completed` and unmount the panel — this
    // test asserts it does not.
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final navigated = <String>[];
    Widget routeProbe(GoRouterState s) {
      navigated.add(s.uri.toString());
      return const Scaffold(body: SizedBox.shrink());
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          readinessReportProvider.overrideWithValue(_readyReport),
        ],
        child: MaterialApp.router(
          theme: NightshadeTheme.dark,
          routerConfig: GoRouter(
            initialLocation: '/home',
            routes: [
              GoRoute(
                path: '/home',
                builder: (_, __) => const Scaffold(
                  body: FirstLaunchCoachLauncher(
                    child: Center(child: Text('shell-content')),
                  ),
                ),
              ),
              GoRoute(path: '/imaging', builder: (_, s) => routeProbe(s)),
            ],
          ),
        ),
      ),
    );
    // Resolve the status FutureProvider and let the completion listener fire.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The launcher mounted the panel, and the panel is showing the celebration.
    expect(find.byType(FirstLaunchCoachPanel), findsOneWidget);
    expect(find.text("You're ready for first light"), findsOneWidget);

    // Completion was persisted by the listener...
    final dao = TutorialProgressDao(database);
    expect(await dao.isCategoryCompleted(firstLaunchCoachCategory), isTrue);

    // ...yet the panel — and its CTA — stayed mounted (the no-invalidate
    // contract). Pump more frames to prove it is not just a one-frame flash.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(FirstLaunchCoachPanel), findsOneWidget);

    final cta = find.widgetWithText(NightshadeButton, 'Capture first light');
    expect(cta, findsOneWidget);

    // The hand-off is actually tappable and routes to the first-light flow.
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(navigated, contains('/imaging?firstLight=1'));

    // Next launch: a fresh ProviderContainer reading the same persisted DB must
    // resolve `completed` — which is exactly what closes the launcher's
    // `pending`-only auto-launch gate, so the coach never re-appears. We assert
    // this against a clean container (a true "cold start" against the persisted
    // store) rather than a widget re-pump, which would only re-diff the existing
    // element tree.
    final coldStart = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
    addTearDown(coldStart.dispose);
    final nextLaunchStatus =
        await coldStart.read(firstLaunchCoachStatusProvider.future);
    expect(nextLaunchStatus, FirstLaunchCoachStatus.completed);
  });
}
