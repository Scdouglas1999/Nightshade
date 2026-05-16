import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart';

/// End-to-end provider test for the onboarding wizard.
///
/// We override `databaseProvider` to point at an in-memory Drift
/// instance so the equipment-profile and tutorial-progress writes hit a
/// real schema (no mocks), then drive the notifier through the full
/// happy path: pick devices, set optical-train, pick capture dir, save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('shouldRunEquipmentOnboardingProvider returns true on fresh install',
      () async {
    final shouldRun =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(shouldRun, isTrue);
  });

  test('shouldRunEquipmentOnboardingProvider returns false once a profile exists',
      () async {
    // Insert a profile through the DAO so the bootstrap gate flips false
    // — mirrors what the rest of the codebase does when a user creates a
    // profile outside the wizard.
    final dao = container.read(equipmentProfilesDaoProvider);
    await dao.createProfile(
      EquipmentProfileModel(name: 'existing').toCompanion(),
    );

    // Invalidate so the future re-resolves against the new DB state.
    container.invalidate(shouldRunEquipmentOnboardingProvider);
    final shouldRun =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(shouldRun, isFalse);
  });

  test(
      'OnboardingNotifier persists draft across reads via app_settings JSON',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;
    await notifier.setCamera(
      id: 'native:zwo:0',
      name: 'ASI294MC Pro',
      pixelSizeMicrons: 4.63,
    );
    await notifier.next();

    // Re-create the notifier from a fresh container backed by the same
    // database. The persisted JSON blob in app_settings should hydrate
    // the camera selection.
    final secondContainer = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    try {
      final loaded =
          secondContainer.read(onboardingDraftProvider.notifier);
      await loaded.loaded;
      final draft = secondContainer.read(onboardingDraftProvider);
      expect(draft.cameraId, 'native:zwo:0');
      expect(draft.pixelSizeMicrons, 4.63);
      expect(draft.currentStep, OnboardingStep.drivers);
    } finally {
      secondContainer.dispose();
    }
  });

  test('complete() creates a profile, marks tutorial done, clears draft',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    // Walk through enough of the wizard to have a valid draft.
    await notifier.toggleDriver(DriverType.native);
    await notifier.setCamera(
      id: 'native:zwo:0',
      name: 'ASI294MC Pro',
      pixelSizeMicrons: 4.63,
    );
    await notifier.setMount(id: 'ascom:EQMOD', name: 'EQ6-R');
    await notifier.setOpticalTrain(
      focalLengthMm: 1000,
      apertureMm: 80,
      pixelSizeMicrons: 4.63,
      reducerFactor: 1.0,
    );
    await notifier.setCaptureDirectory('C:/captures');
    await notifier.setProfileName('Backyard rig');

    final profileId = await notifier.complete();
    expect(profileId, isNonZero);

    // Equipment profile row exists with our values
    final dao = container.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    expect(profile, isNotNull);
    expect(profile!.name, 'Backyard rig');
    expect(profile.cameraId, 'native:zwo:0');
    expect(profile.cameraName, 'ASI294MC Pro');
    expect(profile.mountId, 'ascom:EQMOD');
    expect(profile.focalLength, 1000);
    expect(profile.aperture, 80);
    expect(profile.isActive, isTrue);
    expect(profile.isDefault, isTrue);

    // Tutorial progress row marked completed
    final tutorialDao = container.read(tutorialProgressDaoProvider);
    final progress = await tutorialDao
        .getProgress(OnboardingDraft.persistenceCategory);
    expect(progress, isNotNull);
    expect(progress!.completed, isTrue);

    // Default image directory persisted
    final settingsDao = container.read(settingsDaoProvider);
    final captureDir = await settingsDao.getDefaultImageDirectory();
    expect(captureDir, 'C:/captures');

    // Draft blob is wiped
    final draftRow = await settingsDao
        .getSetting(OnboardingDraft.draftSettingsKey);
    expect(draftRow, isNull);

    // Bootstrap gate flips false
    container.invalidate(shouldRunEquipmentOnboardingProvider);
    final shouldRun =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(shouldRun, isFalse);
  });

  test('skip() marks tutorial dismissed and gates further launches',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;
    await notifier.skip();

    final tutorialDao = container.read(tutorialProgressDaoProvider);
    final progress = await tutorialDao
        .getProgress(OnboardingDraft.persistenceCategory);
    expect(progress, isNotNull);
    expect(progress!.dismissed, isTrue);

    container.invalidate(shouldRunEquipmentOnboardingProvider);
    final shouldRun =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(shouldRun, isFalse);
  });

  test('toggleDriver round-trips a driver in/out of the selection set',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    final initial = container.read(onboardingDraftProvider).selectedDrivers;
    final hadAscom = initial.contains(DriverType.ascom);

    await notifier.toggleDriver(DriverType.ascom);
    final afterFirst =
        container.read(onboardingDraftProvider).selectedDrivers;
    expect(afterFirst.contains(DriverType.ascom), !hadAscom);

    await notifier.toggleDriver(DriverType.ascom);
    final afterSecond =
        container.read(onboardingDraftProvider).selectedDrivers;
    expect(afterSecond.contains(DriverType.ascom), hadAscom);
  });

  test('back/next stay within step bounds', () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    // Back on welcome is a no-op
    await notifier.back();
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.welcome);

    await notifier.next();
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.drivers);

    await notifier.back();
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.welcome);

    // Walk to the last step and verify next is a no-op there
    for (var i = 0; i < OnboardingStep.values.length - 1; i++) {
      await notifier.next();
    }
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.summary);
    await notifier.next();
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.summary);
  });
}
