import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/models/equipment_profile.dart'
    as remote_profile;

/// Mock NetworkBackend so we can exercise the remote (host-authoritative)
/// branch of [OnboardingNotifier.complete] without a live headless server.
class _MockNetworkBackend extends Mock implements NetworkBackend {}

/// Backend notifier seeded with a fixed backend so `backendProvider` resolves
/// to our mock — mirrors the wiring in `equipment_remote_parity_test.dart`.
class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// End-to-end provider test for the onboarding wizard.
///
/// We override `databaseProvider` to point at an in-memory Drift
/// instance so the equipment-profile and tutorial-progress writes hit a
/// real schema (no mocks), then drive the notifier through the full
/// happy path: pick devices, set optical-train, pick capture dir, save.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const remote_profile.EquipmentProfile(id: '0', name: 'fallback'),
    );
    registerFallbackValue(const Stream<NightshadeEvent>.empty());
  });

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
      const EquipmentProfileModel(name: 'existing').toCompanion(),
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

  test(
      'complete() creates a profile (gain/offset/bin/cooling), persists '
      'capture dir, but does NOT yet mark the tutorial done', () async {
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
    // Camera acquisition defaults captured at the camera-defaults step.
    await notifier.setCameraDefaults(
      gain: 120,
      offset: 30,
      binX: 2,
      binY: 2,
      coolingTempC: -10,
    );
    await notifier.setCaptureDirectory('C:/captures');
    await notifier.setProfileName('Backyard rig');

    final profileId = await notifier.complete();
    expect(profileId, isNonZero);

    // Equipment profile row exists with our values, including the camera
    // acquisition defaults threaded through from the draft.
    final dao = container.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    expect(profile, isNotNull);
    expect(profile!.name, 'Backyard rig');
    expect(profile.cameraId, 'native:zwo:0');
    expect(profile.cameraName, 'ASI294MC Pro');
    expect(profile.mountId, 'ascom:EQMOD');
    expect(profile.focalLength, 1000);
    expect(profile.aperture, 80);
    expect(profile.defaultGain, 120);
    expect(profile.defaultOffset, 30);
    expect(profile.defaultBinX, 2);
    expect(profile.defaultBinY, 2);
    expect(profile.defaultCoolingTemp, -10);
    // A cooling set-point implies cool-on-connect.
    expect(profile.coolOnConnect, isTrue);
    expect(profile.isActive, isTrue);
    expect(profile.isDefault, isTrue);

    // Default image directory persisted.
    final settingsDao = container.read(settingsDaoProvider);
    final captureDir = await settingsDao.getDefaultImageDirectory();
    expect(captureDir, 'C:/captures');

    // Tutorial progress is NOT yet completed — that waits for finishNextSteps.
    final tutorialDao = container.read(tutorialProgressDaoProvider);
    final progress =
        await tutorialDao.getProgress(OnboardingDraft.persistenceCategory);
    expect(
      progress == null || (!progress.completed && !progress.dismissed),
      isTrue,
      reason: 'complete() must not retire onboarding before nextSteps',
    );

    // Draft blob is still present (not wiped until finishNextSteps).
    final draftRow =
        await settingsDao.getSetting(OnboardingDraft.draftSettingsKey);
    expect(draftRow, isNotNull);
  });

  test(
      'complete() threads telescopeName + leaves cooling null for a DSLR-style '
      'preset (no cool-on-connect)', () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    await notifier.applyTelescopePreset(
      builtInTelescopePresets.firstWhere(
        (p) => p.id == 'tel.williamoptics.redcat51',
      ),
    );
    await notifier.applyCameraPreset(
      builtInCameraDefaultsPresets.firstWhere(
        (p) => p.id == 'cam.canon.eosra',
      ),
    );
    await notifier.setProfileName('Wide-field rig');

    final profileId = await notifier.complete();
    final dao = container.read(equipmentProfilesDaoProvider);
    final profile = await dao.getProfileById(profileId);
    expect(profile, isNotNull);
    expect(profile!.telescopeName, 'William Optics RedCat 51');
    expect(profile.focalLength, 250);
    expect(profile.aperture, 51);
    // The Canon EOS Ra preset has no regulated cooling.
    expect(profile.defaultCoolingTemp, isNull);
    expect(profile.coolOnConnect, isFalse);
    expect(profile.defaultGain, 0);
  });

  test(
      'finishNextSteps marks completed, wipes the draft, and flips the gate',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;
    await notifier.setCamera(
      id: 'native:zwo:0',
      name: 'ASI294MC Pro',
      pixelSizeMicrons: 4.63,
    );
    await notifier.setProfileName('Backyard rig');
    await notifier.complete();

    // Profile exists -> the gate would already read false, so to prove
    // finishNextSteps is what flips it via tutorial_progress we assert the
    // progress + draft state directly.
    await notifier.finishNextSteps();

    final tutorialDao = container.read(tutorialProgressDaoProvider);
    final progress =
        await tutorialDao.getProgress(OnboardingDraft.persistenceCategory);
    expect(progress, isNotNull);
    expect(progress!.completed, isTrue);

    final settingsDao = container.read(settingsDaoProvider);
    final draftRow =
        await settingsDao.getSetting(OnboardingDraft.draftSettingsKey);
    expect(draftRow, isNull);

    container.invalidate(shouldRunEquipmentOnboardingProvider);
    final shouldRun =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(shouldRun, isFalse);
  });

  test(
      'finishNextSteps flips the gate to false even with no profile (tutorial '
      'completion alone)', () async {
    // A no-profile container so the gate is driven purely by tutorial_progress.
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    final before =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(before, isTrue);

    await notifier.finishNextSteps();

    container.invalidate(shouldRunEquipmentOnboardingProvider);
    final after =
        await container.read(shouldRunEquipmentOnboardingProvider.future);
    expect(after, isFalse);
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

    // Walk to the last step and verify next is a no-op there. The terminal
    // step is now `nextSteps` (summary is followed by the what's-next screen).
    for (var i = 0; i < OnboardingStep.values.length - 1; i++) {
      await notifier.next();
    }
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.nextSteps);
    await notifier.next();
    expect(container.read(onboardingDraftProvider).currentStep,
        OnboardingStep.nextSteps);
  });

  test('cameraDefaults is optional; nextSteps is the non-skippable terminal',
      () {
    expect(OnboardingStep.cameraDefaults.isOptional, isTrue);
    expect(OnboardingStep.nextSteps.isOptional, isFalse);
    // Ordering contract: cameraDefaults sits between opticalTrain and
    // captureDir; nextSteps is last.
    expect(
      OnboardingStep.cameraDefaults.order,
      greaterThan(OnboardingStep.opticalTrain.order),
    );
    expect(
      OnboardingStep.cameraDefaults.order,
      lessThan(OnboardingStep.captureDir.order),
    );
    expect(OnboardingStep.nextSteps.order, OnboardingStep.values.length - 1);
    expect(
      OnboardingStep.nextSteps.order,
      greaterThan(OnboardingStep.summary.order),
    );
  });

  test(
      'applyTelescopePreset / applyCameraPreset populate the draft and persist',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    final scope = builtInTelescopePresets
        .firstWhere((p) => p.id == 'tel.skywatcher.esprit100ed');
    await notifier.applyTelescopePreset(scope);
    final cam = builtInCameraDefaultsPresets
        .firstWhere((p) => p.id == 'cam.zwo.asi294mc');
    await notifier.applyCameraPreset(cam);

    final draft = container.read(onboardingDraftProvider);
    expect(draft.telescopePresetId, scope.id);
    expect(draft.telescopeName, 'Sky-Watcher Esprit 100ED');
    expect(draft.focalLengthMm, 550);
    expect(draft.apertureMm, 100);

    expect(draft.cameraPresetId, cam.id);
    expect(draft.pixelSizeMicrons, 4.63);
    expect(draft.defaultGain, 120);
    expect(draft.defaultOffset, 30);
    expect(draft.defaultBinX, 1);
    expect(draft.defaultBinY, 1);
    expect(draft.defaultCoolingTempC, -10);

    // Persisted: a fresh notifier over the same DB hydrates the same picks.
    final secondContainer = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    try {
      final reloaded = secondContainer.read(onboardingDraftProvider.notifier);
      await reloaded.loaded;
      final restored = secondContainer.read(onboardingDraftProvider);
      expect(restored.telescopePresetId, scope.id);
      expect(restored.cameraPresetId, cam.id);
      expect(restored.defaultGain, 120);
      expect(restored.defaultCoolingTempC, -10);
      expect(restored.focalLengthMm, 550);
    } finally {
      secondContainer.dispose();
    }
  });

  test('applyCameraPreset clears the cooling set-point for a DSLR preset',
      () async {
    final notifier = container.read(onboardingDraftProvider.notifier);
    await notifier.loaded;

    // Seed a cooled-CMOS preset first so cooling is non-null...
    await notifier.applyCameraPreset(
      builtInCameraDefaultsPresets
          .firstWhere((p) => p.id == 'cam.zwo.asi294mc'),
    );
    expect(container.read(onboardingDraftProvider).defaultCoolingTempC, -10);

    // ...then apply the DSLR preset, which must null the cooling set-point
    // rather than leaving the stale -10.
    await notifier.applyCameraPreset(
      builtInCameraDefaultsPresets.firstWhere((p) => p.id == 'cam.canon.eosra'),
    );
    expect(container.read(onboardingDraftProvider).defaultCoolingTempC, isNull);
  });

  test('OnboardingDraft JSON round-trip preserves the new fields', () {
    const draft = OnboardingDraft(
      currentStep: OnboardingStep.cameraDefaults,
      telescopePresetId: 'tel.askar.fra400',
      telescopeName: 'Askar FRA400',
      cameraPresetId: 'cam.zwo.asi2600mm',
      pixelSizeMicrons: 3.76,
      focalLengthMm: 400,
      apertureMm: 72,
      defaultGain: 100,
      defaultOffset: 50,
      defaultBinX: 1,
      defaultBinY: 1,
      defaultCoolingTempC: -10,
    );

    final restored =
        OnboardingDraft.fromJsonStringOrEmpty(draft.toJsonString());
    expect(restored, draft);
    expect(restored.hashCode, draft.hashCode);
    expect(restored.currentStep, OnboardingStep.cameraDefaults);
    expect(restored.telescopePresetId, 'tel.askar.fra400');
    expect(restored.telescopeName, 'Askar FRA400');
    expect(restored.cameraPresetId, 'cam.zwo.asi2600mm');
    expect(restored.defaultGain, 100);
    expect(restored.defaultOffset, 50);
    expect(restored.defaultBinX, 1);
    expect(restored.defaultBinY, 1);
    expect(restored.defaultCoolingTempC, -10);
  });

  test('complete() on a NetworkBackend resolves the host-created profile id',
      () async {
    final backend = _MockNetworkBackend();
    when(() => backend.eventStream)
        .thenAnswer((_) => const Stream<NightshadeEvent>.empty());
    when(() => backend.saveProfile(any())).thenAnswer((_) async {});
    when(() => backend.loadProfile(any())).thenAnswer((_) async {});
    // The host echoes back the saved profile with a server-assigned id.
    when(() => backend.getProfiles()).thenAnswer(
      (_) async => [
        const remote_profile.EquipmentProfile(
          id: '42',
          name: 'Remote rig',
        ),
      ],
    );

    final remoteContainer = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        backendProvider.overrideWith(
          (ref) => _FixedBackendNotifier(ref, backend),
        ),
      ],
    );
    try {
      final notifier = remoteContainer.read(onboardingDraftProvider.notifier);
      await notifier.loaded;
      await notifier.setCamera(
        id: 'native:zwo:0',
        name: 'ASI294MC Pro',
        pixelSizeMicrons: 4.63,
      );
      await notifier.setProfileName('Remote rig');

      final id = await notifier.complete();
      expect(id, 42);
      verify(() => backend.saveProfile(any())).called(1);
      verify(() => backend.loadProfile('42')).called(1);
    } finally {
      remoteContainer.dispose();
    }
  });
}
