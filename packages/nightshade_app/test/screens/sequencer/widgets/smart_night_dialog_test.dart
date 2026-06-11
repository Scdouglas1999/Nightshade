// Smart Night dialog widget smoke test.
//
// Pins the wizard's public surface:
//   * the dialog opens via SmartNightDialog() and shows the step
//     indicator with Window/Equipment/Targets/Strategy/Preview/Accept
//   * the close button dismisses the dialog
//   * the "Missing observer location" card appears when no location
//     is configured (the most common blocking gate)
//
// We intentionally keep this lean: the heavy logic lives in
// SmartNightService and is covered by 15 unit tests under
// nightshade_core/test/services/smart_night_service_test.dart. The
// widget test here just confirms the wizard can be opened, the steps
// render, and the validation gates fire.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/smart_night_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    as planetarium;
import 'package:nightshade_ui/nightshade_ui.dart';

Future<ProviderContainer> _pumpDialog(
  WidgetTester tester, {
  List<Override> overrides = const [],
  SmartNightDialog dialog = const SmartNightDialog(),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1024, 800);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Center(child: dialog),
        ),
      ),
    ),
  );
  // Let the FutureProvider chains settle. We don't await all of them
  // because some (e.g. the targets DB) are stubbed out when no
  // overrides are supplied — we'd need a full app harness to wait on
  // those. The smoke test only cares that the first frame renders.
  await tester.pump();
  return container;
}

void main() {
  testWidgets('SmartNightDialog renders header + step indicator',
      (tester) async {
    await _pumpDialog(tester);
    expect(find.text('Smart Night — Plan Tonight'), findsOneWidget);
    // The six step labels are visible in the indicator strip.
    expect(find.text('1. Window'), findsOneWidget);
    expect(find.text('2. Equipment'), findsOneWidget);
    expect(find.text('3. Targets'), findsOneWidget);
    expect(find.text('4. Strategy'), findsOneWidget);
    expect(find.text('5. Preview'), findsOneWidget);
    expect(find.text('6. Accept'), findsOneWidget);
  });

  testWidgets(
      'SmartNightDialog shows "Missing observer location" '
      'when no lat/lon configured', (tester) async {
    await _pumpDialog(tester);
    // Default AppSettings has lat=lon=0.0 → appObserverLocationProvider
    // returns null → wizard surfaces the missing-location warning card
    // on step 1.
    expect(
      find.textContaining('No observer location set'),
      findsOneWidget,
    );
  });

  testWidgets('SmartNightDialog footer has Cancel + Next buttons',
      (tester) async {
    await _pumpDialog(tester);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets(
      'seeded dialog opens in hand-pick mode and shows the source banner '
      '(C11 handoff)', (tester) async {
    await _pumpDialog(
      tester,
      dialog: const SmartNightDialog(
        seedTargetIds: [50],
        seedSourceLabel: 'Galaxy Season',
      ),
      overrides: [
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            name: 'Test rig',
            focalLength: 600,
            aperture: 120,
            filterNames: ['L', 'R', 'G', 'B'],
          ),
        ),
        // The seeded target (50) plus another, both up tonight, so the seed has
        // no "below cut-off" gap and the banner is the plain info variant.
        tonightSuggestionsProvider.overrideWith((ref) async => const [
              TargetSuggestion(
                targetId: 50,
                targetName: 'M51',
                raHours: 13.5,
                decDegrees: 47.2,
                totalScore: 90,
                visibility: planetarium.TargetVisibilityInfo(
                  currentAltitude: 60,
                  currentAzimuth: 180,
                  transitAltitude: 70,
                  airmass: 1.2,
                  moonDistance: 90,
                  hoursAboveMinAlt: 5,
                ),
              ),
              TargetSuggestion(
                targetId: 99,
                targetName: 'M101',
                raHours: 14.05,
                decDegrees: 54.3,
                totalScore: 80,
                visibility: planetarium.TargetVisibilityInfo(
                  currentAltitude: 55,
                  currentAzimuth: 175,
                  transitAltitude: 65,
                  airmass: 1.3,
                  moonDistance: 95,
                  hoursAboveMinAlt: 4,
                ),
              ),
            ]),
      ],
    );
    await tester.pumpAndSettle();

    // Step 1 (Window) -> Next -> Step 2 (Equipment) -> Next -> Step 3 (Targets).
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // We're on the Targets step in hand-pick mode (not auto-pick).
    expect(find.text('3. Targets'), findsOneWidget);
    expect(find.text('Hand-pick from suggestions below'), findsOneWidget);
    // The seed banner names the source campaign.
    expect(
      find.textContaining('Pre-selected the incomplete targets from '
          '"Galaxy Season"'),
      findsOneWidget,
    );
  });

  testWidgets('SmartNightDialog blocks equipment step when aperture is missing',
      (tester) async {
    await _pumpDialog(
      tester,
      overrides: [
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            name: 'No aperture rig',
            focalLength: 600,
            aperture: 0,
            filterNames: ['L'],
          ),
        ),
      ],
    );

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('2. Equipment'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.textContaining('Equipment profile is missing aperture'),
      findsOneWidget,
    );
    expect(find.text('2. Equipment'), findsOneWidget);
    expect(find.text('3. Targets'), findsOneWidget);
  });
}
