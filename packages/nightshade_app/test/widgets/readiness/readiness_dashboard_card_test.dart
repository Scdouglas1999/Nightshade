import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/dashboard/widgets/readiness_dashboard_card.dart';
import 'package:nightshade_app/screens/dashboard/widgets/readiness_dashboard_overlay.dart';
import 'package:nightshade_app/widgets/readiness/readiness_status_chip.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A blocked report: one blocking critical-devices item plus a caution item.
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
      id: ReadinessItemId.plateSolver,
      title: 'Plate solver',
      detail: 'No plate solver is configured.',
      level: ReadinessLevel.caution,
      fixRoute: '/settings/plate-solving',
      fixLabel: 'Set up plate solving',
    ),
  ],
);

/// A fully-ready report — every item green.
const _readyReport = ReadinessReport(
  items: [
    ReadinessItem(
      id: ReadinessItemId.criticalDevices,
      title: 'Critical devices',
      detail: 'Camera and mount are connected.',
      level: ReadinessLevel.ready,
    ),
  ],
);

Widget _harness({
  required ReadinessReport report,
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      readinessReportProvider.overrideWithValue(report),
    ],
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(body: child),
    ),
  );
}

Widget _routerHarness({
  required ReadinessReport report,
  required Widget body,
}) {
  return ProviderScope(
    overrides: [
      readinessReportProvider.overrideWithValue(report),
    ],
    child: MaterialApp.router(
      theme: NightshadeTheme.dark,
      routerConfig: GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => Scaffold(body: body),
          ),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReadinessDashboardCard', () {
    testWidgets('renders the chip + top outstanding item when not ready',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          report: _blockedReport,
          child: const ReadinessDashboardCard(),
        ),
      );
      // The blocked item renders a forever-pulsing urgent dot; pump frames.
      await tester.pump();

      expect(find.byType(ReadinessStatusChip), findsOneWidget);
      // The single most-important outstanding item is the blocked one.
      expect(find.text('Critical devices'), findsOneWidget);
      expect(
        find.text('No equipment profile is set up yet.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(NightshadeButton, 'View all'), findsOneWidget);
    });

    testWidgets('collapses to nothing when the rig is fully ready',
        (tester) async {
      await tester.pumpWidget(
        _harness(
          report: _readyReport,
          child: const ReadinessDashboardCard(),
        ),
      );
      await tester.pumpAndSettle();

      // Ready -> SizedBox.shrink: no chip, no card content.
      expect(find.byType(ReadinessStatusChip), findsNothing);
      expect(find.widgetWithText(NightshadeButton, 'View all'), findsNothing);
    });
  });

  group('ReadinessDashboardOverlay', () {
    testWidgets('mounts the card overlay when not ready', (tester) async {
      await tester.pumpWidget(
        _routerHarness(
          report: _blockedReport,
          body: const Stack(
            children: [
              Center(child: Text('DASHBOARD-BODY')),
              ReadinessDashboardOverlay(),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.text('DASHBOARD-BODY'), findsOneWidget);
      expect(find.byType(ReadinessDashboardCard), findsOneWidget);
      expect(find.text('Critical devices'), findsOneWidget);
    });

    testWidgets('adds no visual weight when the rig is ready', (tester) async {
      await tester.pumpWidget(
        _routerHarness(
          report: _readyReport,
          body: const Stack(
            children: [
              Center(child: Text('DASHBOARD-BODY')),
              ReadinessDashboardOverlay(),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD-BODY'), findsOneWidget);
      // The overlay short-circuits before mounting the card.
      expect(find.byType(ReadinessDashboardCard), findsNothing);
    });
  });
}
