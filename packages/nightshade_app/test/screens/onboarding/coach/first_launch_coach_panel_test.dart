import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/onboarding/coach/first_launch_coach_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_ui/nightshade_ui.dart';

/// A blocked report: critical-devices blocked (no profile), everything else
/// blocked too — this is the fresh-install state the coach is built for. Six
/// items, all blocked, so the panel shows "0 of 6 complete" and a button per
/// step.
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

/// A fully-ready report — every readiness item green, which drives the coach
/// into its celebration mode.
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

/// Records the routes navigated through the test GoRouter so a test can assert
/// where a "Do it now" / "Capture first light" button took the user.
class _RouteLog {
  final List<String> routes = <String>[];
}

/// Pumps [FirstLaunchCoachPanel] under a real GoRouter and an in-memory
/// DB-backed [firstLaunchCoachDaoProvider]. Every settings/equipment/imaging
/// route the coach can deep-link to is registered and records its location to
/// [log] so navigation assertions read the literal route string.
Future<void> _pumpCoach(
  WidgetTester tester, {
  required db.NightshadeDatabase database,
  required ReadinessReport report,
  required _RouteLog log,
}) async {
  Widget page(String location) => Builder(
        builder: (_) {
          log.routes.add(location);
          return const Scaffold(body: SizedBox.shrink());
        },
      );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        readinessReportProvider.overrideWithValue(report),
      ],
      child: MaterialApp.router(
        theme: NightshadeTheme.dark,
        routerConfig: GoRouter(
          initialLocation: '/coach',
          routes: [
            GoRoute(
              path: '/coach',
              // The panel renders content only; its host (C7) owns scrolling.
              // Wrap it in a scroll view here so a tall checklist does not
              // overflow the fixed test viewport.
              builder: (_, __) => const Scaffold(
                body: SingleChildScrollView(child: FirstLaunchCoachPanel()),
              ),
            ),
            GoRoute(path: '/equipment', builder: (_, s) => page(s.uri.toString())),
            GoRoute(path: '/settings', builder: (_, s) => page(s.uri.toString())),
            GoRoute(path: '/imaging', builder: (_, s) => page(s.uri.toString())),
          ],
        ),
      ),
    ),
  );
  // The status FutureProvider resolves on a microtask; pump a couple of frames
  // to let the panel swap from SizedBox.shrink to its real content. We avoid
  // `pumpAndSettle` because a blocked step renders a forever-pulsing urgent
  // StatusDot (an unbounded animation), which would make `pumpAndSettle` time
  // out — the same reason ReadinessPanel's own tests pump explicit frames.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late db.NightshadeDatabase database;
  late _RouteLog log;

  setUp(() {
    database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    log = _RouteLog();
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets(
      'blocked report renders a "Set location" button that deep-links to '
      '/settings?section=location', (tester) async {
    await _pumpCoach(
      tester,
      database: database,
      report: _blockedReport,
      log: log,
    );

    final setLocation =
        find.widgetWithText(NightshadeButton, 'Set location');
    expect(setLocation, findsOneWidget);

    await tester.tap(setLocation);
    await tester.pumpAndSettle();

    expect(log.routes, contains('/settings?section=location'));
  });

  testWidgets('progress caption shows "N of 6 complete" matching the report',
      (tester) async {
    await _pumpCoach(
      tester,
      database: database,
      report: _blockedReport,
      log: log,
    );

    // Six steps, none ready -> 0 of 6 complete.
    expect(find.text('0 of 6 complete'), findsOneWidget);
  });

  testWidgets('tapping dismiss persists markDismissed', (tester) async {
    await _pumpCoach(
      tester,
      database: database,
      report: _blockedReport,
      log: log,
    );

    final dao = TutorialProgressDao(database);
    expect(await dao.isCategoryDismissed(firstLaunchCoachCategory), isFalse);

    await tester.tap(find.byTooltip('Dismiss — reopen from Settings → Help'));
    await tester.pumpAndSettle();

    expect(await dao.isCategoryDismissed(firstLaunchCoachCategory), isTrue);
  });

  testWidgets(
      'all-ready report shows the celebration with a "Capture first light" '
      'CTA, persists markCompleted, and routes to /imaging?firstLight=1',
      (tester) async {
    await _pumpCoach(
      tester,
      database: database,
      report: _readyReport,
      log: log,
    );

    expect(find.text("You're ready for first light"), findsOneWidget);

    // The listener fires markCompleted on the first transition to allComplete.
    final dao = TutorialProgressDao(database);
    expect(await dao.isCategoryCompleted(firstLaunchCoachCategory), isTrue);

    final cta =
        find.widgetWithText(NightshadeButton, 'Capture first light');
    expect(cta, findsOneWidget);

    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(log.routes, contains('/imaging?firstLight=1'));
  });
}
