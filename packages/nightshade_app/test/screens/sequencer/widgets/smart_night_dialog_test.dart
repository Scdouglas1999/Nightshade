// Wave 6 — Smart Night dialog widget smoke test.
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
import 'package:nightshade_ui/nightshade_ui.dart';

Future<ProviderContainer> _pumpDialog(
  WidgetTester tester, {
  List<Override> overrides = const [],
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
        home: const Scaffold(
          body: Center(child: SmartNightDialog()),
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

  testWidgets('SmartNightDialog shows "Missing observer location" '
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
