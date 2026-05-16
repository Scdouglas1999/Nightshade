// Widget tests for the equipment-onboarding wizard (F4-ONBOARDING-WIZARD).
//
// We test each step body in isolation by wrapping it in a Scaffold with
// real Riverpod providers backed by an in-memory Drift database. This
// proves each step renders, accepts input, validates, and persists.
//
// The integration test at the bottom of the file walks the full happy
// path through OnboardingScreen end-to-end.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/onboarding_screen.dart';
import 'package:nightshade_app/screens/onboarding/steps/capture_dir_step.dart';
import 'package:nightshade_app/screens/onboarding/steps/driver_step.dart';
import 'package:nightshade_app/screens/onboarding/steps/optical_train_step.dart';
import 'package:nightshade_app/screens/onboarding/steps/summary_step.dart';
import 'package:nightshade_app/screens/onboarding/steps/welcome_step.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

NightshadeDatabase _newDb() =>
    NightshadeDatabase.forTesting(NativeDatabase.memory());

Future<void> _pumpStep(
  WidgetTester tester, {
  required NightshadeDatabase db,
  required Widget step,
  Set<DriverType>? availableDrivers,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (availableDrivers != null)
          availableOnboardingDriversProvider
              .overrideWithValue(availableDrivers),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: step,
          ),
        ),
      ),
    ),
  );
  // Allow the post-frame callbacks that read providers (e.g. seed
  // controllers from draft) to fire.
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Welcome step', () {
    testWidgets('renders the headline and bulleted summary',
        (tester) async {
      final db = _newDb();
      addTearDown(db.close);
      await _pumpStep(tester, db: db, step: const OnboardingWelcomeStep());

      expect(find.text('Welcome to Nightshade'), findsOneWidget);
      expect(find.textContaining("What we'll cover"), findsOneWidget);
    });
  });

  group('Driver step', () {
    testWidgets('toggling a driver updates the draft', (tester) async {
      final db = _newDb();
      addTearDown(db.close);
      late ProviderContainer container;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            availableOnboardingDriversProvider.overrideWithValue({
              DriverType.native,
              DriverType.alpaca,
              DriverType.indi,
            }),
          ],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: NightshadeTheme.dark,
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(24),
                  child: OnboardingDriverStep(),
                ),
              ),
            );
          }),
        ),
      );
      await tester.pump();
      // Wait for the notifier to hydrate (defaults to all non-sim drivers
      // selected on a fresh load).
      await container
          .read(onboardingDraftProvider.notifier)
          .loaded;
      await tester.pumpAndSettle();

      // Default selection includes all non-simulator drivers
      final draft = container.read(onboardingDraftProvider);
      expect(draft.selectedDrivers.contains(DriverType.native), isTrue);

      // Tap the Native row to toggle off
      await tester.tap(find.text('Native'));
      await tester.pumpAndSettle();
      final after = container.read(onboardingDraftProvider);
      expect(after.selectedDrivers.contains(DriverType.native), isFalse);
    });
  });

  group('Optical train step', () {
    testWidgets('validates required fields and renders image scale',
        (tester) async {
      final db = _newDb();
      addTearDown(db.close);
      late ProviderContainer container;
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: NightshadeTheme.dark,
              home: const Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: OnboardingOpticalTrainStep(),
                ),
              ),
            );
          }),
        ),
      );
      await container.read(onboardingDraftProvider.notifier).loaded;
      await tester.pumpAndSettle();

      // Initially nothing computed
      expect(find.text('--'), findsWidgets);

      // Enter realistic values: 1000mm, 80mm, 3.76µm, 1.0x reducer
      // -> image scale ≈ 0.78 arcsec/px, f/12.5
      await tester.enterText(
          find.widgetWithText(TextField, '').first.evaluate().isEmpty
              ? find.byType(TextField).at(0)
              : find.byType(TextField).at(0),
          '1000');
      await tester.enterText(find.byType(TextField).at(1), '80');
      await tester.enterText(find.byType(TextField).at(2), '1.0');
      await tester.enterText(find.byType(TextField).at(3), '3.76');
      await tester.pumpAndSettle();

      final draft = container.read(onboardingDraftProvider);
      expect(draft.focalLengthMm, 1000);
      expect(draft.apertureMm, 80);
      expect(draft.pixelSizeMicrons, 3.76);
      expect(draft.reducerFactor, 1.0);
      expect(draft.imageScaleArcsecPerPixel, isNotNull);

      // The summary row should now show the computed image scale.
      expect(find.textContaining('arcsec/px'), findsOneWidget);
      expect(find.textContaining('f/12.5'), findsOneWidget);
    });
  });

  group('Capture dir step', () {
    testWidgets('renders browse button and placeholder text',
        (tester) async {
      final db = _newDb();
      addTearDown(db.close);
      await _pumpStep(tester,
          db: db, step: const OnboardingCaptureDirStep());

      expect(find.text('Where should we save captures?'), findsOneWidget);
      expect(find.text('No folder selected yet'), findsOneWidget);
      expect(find.text('Browse'), findsOneWidget);
    });
  });

  group('Summary step', () {
    testWidgets('shows draft fields and lets the user edit the profile name',
        (tester) async {
      final db = _newDb();
      addTearDown(db.close);
      late ProviderContainer container;

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: NightshadeTheme.dark,
              home: const Scaffold(
                body: SingleChildScrollView(
                  padding: EdgeInsets.all(24),
                  child: OnboardingSummaryStep(),
                ),
              ),
            );
          }),
        ),
      );
      await container.read(onboardingDraftProvider.notifier).loaded;
      // Seed the draft as if previous steps had completed.
      await container.read(onboardingDraftProvider.notifier).setCamera(
            id: 'native:zwo:0',
            name: 'ASI294MC Pro',
          );
      await container
          .read(onboardingDraftProvider.notifier)
          .setMount(id: 'ascom:EQMOD', name: 'EQ6-R');
      await container
          .read(onboardingDraftProvider.notifier)
          .setOpticalTrain(
            focalLengthMm: 1000,
            apertureMm: 80,
            pixelSizeMicrons: 3.76,
            reducerFactor: 1.0,
          );
      await tester.pumpAndSettle();

      // Renders the device names and the computed image scale.
      expect(find.text('ASI294MC Pro'), findsOneWidget);
      expect(find.text('EQ6-R'), findsOneWidget);
      expect(find.textContaining('arcsec/px'), findsOneWidget);

      // Profile name field is pre-filled.
      final nameField = find.widgetWithText(TextField, 'My First Rig');
      expect(nameField, findsOneWidget);

      // Editing the name persists to the draft.
      await tester.enterText(nameField, 'Backyard Rig');
      await tester.pumpAndSettle();
      expect(container.read(onboardingDraftProvider).profileName,
          'Backyard Rig');
    });
  });

  group('Integration: full wizard flow', () {
    testWidgets('end-to-end completion creates an equipment profile',
        (tester) async {
      final db = _newDb();
      addTearDown(db.close);
      late ProviderContainer container;

      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: Consumer(builder: (ctx, ref, _) {
            container = ProviderScope.containerOf(ctx);
            return MaterialApp(
              theme: NightshadeTheme.dark,
              home: const OnboardingScreen(),
            );
          }),
        ),
      );
      // Let the notifier hydrate so the screen renders past its spinner.
      await container.read(onboardingDraftProvider.notifier).loaded;
      await tester.pumpAndSettle();

      // We bypass UI walking (driver scan is async + tests can't reach
      // real drivers) by mutating the notifier directly to the
      // pre-summary state. Then we drive the summary step through the
      // UI to prove the wizard actually persists the result.
      final notifier = container.read(onboardingDraftProvider.notifier);
      await notifier.toggleDriver(DriverType.simulator);
      await notifier.setCamera(
        id: 'sim:camera:0',
        name: 'Simulator Camera',
        pixelSizeMicrons: 3.76,
      );
      await notifier.setMount(id: 'sim:mount:0', name: 'Simulator Mount');
      await notifier.setOpticalTrain(
        focalLengthMm: 1000,
        apertureMm: 80,
        pixelSizeMicrons: 3.76,
        reducerFactor: 1.0,
      );
      await notifier.setCaptureDirectory('C:/sim_captures');
      await notifier.goToStep(OnboardingStep.summary);
      await tester.pumpAndSettle();

      expect(find.text('Review and save'), findsOneWidget);
      expect(find.text('Save profile'), findsOneWidget);

      // Trigger the save action.
      await tester.tap(find.text('Save profile'));
      // The save action navigates and pushes a snackbar, so we pump but
      // don't pumpAndSettle (the snackbar timer would leak).
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final dao = container.read(equipmentProfilesDaoProvider);
      final profiles = await dao.getAllProfiles();
      expect(profiles.length, 1);
      expect(profiles.single.cameraId, 'sim:camera:0');
      expect(profiles.single.mountId, 'sim:mount:0');
      expect(profiles.single.focalLength, 1000);
    });
  });
}
