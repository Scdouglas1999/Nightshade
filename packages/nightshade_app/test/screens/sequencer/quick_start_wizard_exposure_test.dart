import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_app/screens/sequencer/widgets/quick_start_wizard_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses Smart Night exposure recommendations for light filters',
      (tester) async {
    const exposureContext = SmartNightExposureContext(
      camera: CameraExposureSpec(
        readNoiseE: 1.4,
        fullWellE: 50000,
        qePeak: 0.85,
      ),
      bortleClass: 8,
      focalLengthMm: 384,
      apertureMm: 80,
      pixelSizeMicrons: 3.76,
      availableFilterNames: ['L', 'Ha', 'OIII'],
      userCapSeconds: 240,
      floorSeconds: 30,
    );
    const calculator = SmartNightExposureCalculator();
    final expectedL = calculator
        .recommend(
          ExposureCalculatorInput(
            camera: exposureContext.camera,
            filter: FilterExposureSpec.fromName('L'),
            bortleClass: exposureContext.bortleClass,
            focalLengthMm: exposureContext.focalLengthMm,
            apertureMm: exposureContext.apertureMm,
            pixelSizeMicrons: exposureContext.pixelSizeMicrons,
            userCapSeconds: exposureContext.userCapSeconds,
            floorSeconds: exposureContext.floorSeconds,
          ),
        )
        .seconds
        .round()
        .toString();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileFiltersProvider.overrideWithValue(['L', 'Ha', 'OIII']),
          smartNightExposureContextProvider
              .overrideWith((ref) async => exposureContext),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: QuickStartWizardDialog()),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
        find.widgetWithText(TextField, 'Target Name'), 'M42');
    await tester.enterText(
        find.widgetWithText(TextField, 'Right Ascension'), '5.5');
    await tester.enterText(
        find.widgetWithText(TextField, 'Declination'), '-5.4');
    await tester.pump();
    await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
    await tester.pumpAndSettle();

    expect(_textFieldWithText(expectedL), findsNWidgets(3));
    expect(_textFieldWithText('120'), findsNothing);
    expect(_textFieldWithText('300'), findsNothing);
  });

  testWidgets(
    'preloads cooling temperature from the active equipment profile',
    (tester) async {
      // The wizard's `_applyUserDefaults` reads
      // `activeEquipmentProfileProvider` in initState and seeds
      // `_coolingTemp` from `profile.defaultCoolingTemp`. The cooling
      // target lives on the equipment profile rather than in app settings,
      // so this is an isolated override that doesn't require the
      // sequencer-defaults DAO to be wired up.
      const profile = EquipmentProfileModel(
        id: 1,
        name: 'Test Rig',
        isActive: true,
        filterNames: ['L', 'R', 'G', 'B'],
        defaultCoolingTemp: -15.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileFiltersProvider
                .overrideWithValue(const ['L', 'R', 'G', 'B']),
            activeEquipmentProfileProvider.overrideWithValue(profile),
            smartNightExposureContextProvider
                .overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: NightshadeTheme.dark,
            home: const Scaffold(body: QuickStartWizardDialog()),
          ),
        ),
      );
      await tester.pump();

      // Drive the wizard from Step 1 -> Step 4 (Safety) where the
      // cooling-temperature input is rendered.
      await tester.enterText(
          find.widgetWithText(TextField, 'Target Name'), 'M42');
      await tester.enterText(
          find.widgetWithText(TextField, 'Right Ascension'), '5.5');
      await tester.enterText(
          find.widgetWithText(TextField, 'Declination'), '-5.4');
      await tester.pump();
      // Step 1 -> Step 2
      await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
      await tester.pumpAndSettle();
      // Step 2 -> Step 3
      await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
      await tester.pumpAndSettle();
      // Step 3 -> Step 4 (Safety)
      await tester.tap(find.widgetWithText(NightshadeButton, 'Next'));
      await tester.pumpAndSettle();

      // Cooling target reflects the active profile's -15 C, not the
      // wizard's historical -10 C fallback constant.
      expect(_textFieldWithText('-15'), findsOneWidget);
      expect(_textFieldWithText('-10'), findsNothing);

      // The "Using your saved defaults" hint is shown because the
      // profile's cooling temp diverged from the wizard's fallback.
      expect(
          find.textContaining('Using your saved defaults'), findsOneWidget);
    },
  );
}

Finder _textFieldWithText(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.controller?.text == value,
    description: 'TextField with controller text "$value"',
  );
}
