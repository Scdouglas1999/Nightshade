import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/equipment/widgets/equipment_readiness_panel.dart';
import 'package:nightshade_app/widgets/readiness/readiness_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

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

Widget _harness(ReadinessReport report) {
  return ProviderScope(
    overrides: [
      readinessReportProvider.overrideWithValue(report),
    ],
    child: MaterialApp.router(
      theme: NightshadeTheme.dark,
      routerConfig: GoRouter(
        initialLocation: '/equipment',
        routes: [
          GoRoute(
            path: '/equipment',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: EquipmentReadinessPanel()),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders the section header + itemized checklist when not ready',
      (tester) async {
    await tester.pumpWidget(_harness(_blockedReport));
    // Blocked item has a forever-pulsing urgent dot; pump frames.
    await tester.pump();

    expect(find.text('Ready to image'), findsOneWidget);
    expect(find.byType(ReadinessPanel), findsOneWidget);
    // The blocking item drives the "items are blocking" subtitle.
    expect(
      find.textContaining('blocking'),
      findsWidgets,
    );
    // Per-item rows and their Fix actions render.
    expect(find.text('Critical devices'), findsOneWidget);
    expect(find.text('Set up equipment'), findsOneWidget);
  });

  testWidgets('summarises an all-ready rig', (tester) async {
    await tester.pumpWidget(_harness(_readyReport));
    await tester.pumpAndSettle();

    expect(find.text('Ready to image'), findsOneWidget);
    expect(
      find.text('Everything required for first light is in place.'),
      findsOneWidget,
    );
    // Outstanding-only mode shows the compact "all set" confirmation row
    // instead of repeating every green check.
    expect(find.text('Ready for first light'), findsOneWidget);
  });

  testWidgets('caps inline rows and offers "View all" when many are outstanding',
      (tester) async {
    // Five outstanding items (> maxItems: 3): the inline panel shows 3 and
    // collapses the remaining 2 into a "View all (2 more)" button.
    const manyReport = ReadinessReport(
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
          title: 'Location',
          detail: 'Set your observing location.',
          level: ReadinessLevel.blocked,
          fixRoute: '/settings',
          fixLabel: 'Set location',
        ),
        ReadinessItem(
          id: ReadinessItemId.outputPath,
          title: 'Capture folder',
          detail: 'Pick where captures are saved.',
          level: ReadinessLevel.blocked,
          fixRoute: '/settings',
          fixLabel: 'Choose folder',
        ),
        ReadinessItem(
          id: ReadinessItemId.plateSolver,
          title: 'Plate solver',
          detail: 'No plate solver is configured.',
          level: ReadinessLevel.caution,
          fixRoute: '/settings/plate-solving',
          fixLabel: 'Set up plate solving',
        ),
        ReadinessItem(
          id: ReadinessItemId.darkLibrary,
          title: 'Dark library',
          detail: 'No master darks yet.',
          level: ReadinessLevel.caution,
          fixRoute: '/imaging',
          fixLabel: 'Build darks',
        ),
      ],
    );

    await tester.pumpWidget(_harness(manyReport));
    await tester.pump();

    // First three (blocked first) are inline; the 4th/5th are collapsed.
    expect(find.text('Critical devices'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Capture folder'), findsOneWidget);
    expect(find.text('Plate solver'), findsNothing);
    expect(
      find.widgetWithText(NightshadeButton, 'View all (2 more)'),
      findsOneWidget,
    );
  });
}
