import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/backend/device_types.dart';
import '../models/onboarding/onboarding_state.dart';
import '../providers/database_provider.dart';
import '../providers/profiles_provider.dart';
import '../providers/tutorial_provider.dart';

/// Riverpod plumbing for the equipment-onboarding wizard (F4).
///
/// Splits responsibilities:
///   * [shouldRunEquipmentOnboardingProvider] — bootstrap gate read by the
///     `EquipmentOnboardingLauncher` widget on app launch. Resolves true
///     only when there are zero equipment profiles AND the
///     `equipmentOnboarding` row is absent or unfinished. We do not want
///     to nag users with profiles — those are returning users.
///   * [onboardingDraftProvider] — current draft state. The notifier
///     hydrates from the JSON blob in `app_settings`, mutates in memory
///     via copyWith, and writes back on every commit so the user can
///     close the wizard mid-step and resume on next launch.
///   * [OnboardingNotifier] — methods used by the UI to advance, skip,
///     persist device picks, and finalize (write the EquipmentProfile,
///     mark tutorial_progress, clear the draft).
final shouldRunEquipmentOnboardingProvider = FutureProvider<bool>((ref) async {
  // Don't nag returning users — any existing profile means they already
  // got past onboarding (either through this wizard or the original
  // equipment screen). The wizard is reachable from settings for those
  // users.
  final profilesDao = ref.read(equipmentProfilesDaoProvider);
  final profiles = await profilesDao.getAllProfiles();
  if (profiles.isNotEmpty) return false;

  final tutorialDao = ref.read(tutorialProgressDaoProvider);
  final progress =
      await tutorialDao.getProgress(OnboardingDraft.persistenceCategory);
  if (progress != null && (progress.completed || progress.dismissed)) {
    // The user explicitly finished or skipped the wizard; trust that
    // even though they have no profile yet.
    return false;
  }
  return true;
});

/// State notifier owning the live draft + persistence.
final onboardingDraftProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingDraft>((ref) {
  final notifier = OnboardingNotifier(ref);
  // Kick off the async hydrate immediately — the UI shows a small
  // spinner until `isLoaded` flips true via [OnboardingNotifier.isLoaded].
  notifier._loadDraft();
  return notifier;
});

/// Set of drivers available on the current platform. ASCOM is Windows-only;
/// the other backends work everywhere. Exposed as a provider so widget
/// tests can override the platform check.
final availableOnboardingDriversProvider = Provider<Set<DriverType>>((ref) {
  final drivers = <DriverType>{
    DriverType.native,
    DriverType.alpaca,
    DriverType.indi,
    DriverType.simulator,
  };
  if (Platform.isWindows) {
    drivers.add(DriverType.ascom);
  }
  return drivers;
});

class OnboardingNotifier extends StateNotifier<OnboardingDraft> {
  OnboardingNotifier(this._ref) : super(const OnboardingDraft());

  final Ref _ref;
  bool _isLoaded = false;
  Completer<void>? _loadCompleter;

  /// True once the persisted draft (if any) has been read into [state].
  /// The wizard widget waits for this before rendering its first frame so
  /// the user doesn't see a flash of step 0 before being restored to
  /// (say) the optical train step.
  bool get isLoaded => _isLoaded;

  /// Future that resolves when the initial draft load is done. Awaited by
  /// tests that need to be certain of the hydrated state before pumping
  /// the widget tree.
  Future<void> get loaded {
    if (_isLoaded) return Future.value();
    _loadCompleter ??= Completer<void>();
    return _loadCompleter!.future;
  }

  Future<void> _loadDraft() async {
    try {
      final settingsDao = _ref.read(settingsDaoProvider);
      final raw = await settingsDao.getSetting(OnboardingDraft.draftSettingsKey);
      final draft = OnboardingDraft.fromJsonStringOrEmpty(raw);
      // If the user has not selected any drivers yet (truly fresh start),
      // seed sensible defaults so the discovery step doesn't show an
      // empty multi-select.
      if (draft.selectedDrivers.isEmpty) {
        final available = _ref.read(availableOnboardingDriversProvider);
        // Default to everything except the simulator — the simulator is
        // useful for development but new users want real devices.
        final defaults = available
            .where((d) => d != DriverType.simulator)
            .toSet();
        state = draft.copyWith(selectedDrivers: defaults);
      } else if (mounted) {
        state = draft;
      }
    } finally {
      _isLoaded = true;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }
  }

  Future<void> _persistDraft() async {
    final settingsDao = _ref.read(settingsDaoProvider);
    await settingsDao.setSetting(
      OnboardingDraft.draftSettingsKey,
      state.toJsonString(),
    );
  }

  /// Move to a specific step. Used by the side-bar "jump to step" affordance.
  Future<void> goToStep(OnboardingStep step) async {
    if (!mounted) return;
    state = state.copyWith(currentStep: step);
    await _persistDraft();
  }

  /// Advance to the next non-skipped step. Honors the user's optional-step
  /// choices: if the user did not select a focuser at the focuser step,
  /// the next-step call from the focuser step still proceeds — it's the
  /// caller's job to decide whether to skip; this method just moves
  /// forward by one in OnboardingStep.values order.
  Future<void> next() async {
    final idx = state.currentStep.order;
    if (idx >= OnboardingStep.values.length - 1) return;
    final nextStep = OnboardingStep.values[idx + 1];
    state = state.copyWith(currentStep: nextStep);
    await _persistDraft();
  }

  /// Step backward. No-op on the welcome step.
  Future<void> back() async {
    final idx = state.currentStep.order;
    if (idx == 0) return;
    final prevStep = OnboardingStep.values[idx - 1];
    state = state.copyWith(currentStep: prevStep);
    await _persistDraft();
  }

  /// Toggle a driver on/off. Discovery is keyed off this set.
  Future<void> toggleDriver(DriverType driver) async {
    final next = Set<DriverType>.from(state.selectedDrivers);
    if (next.contains(driver)) {
      next.remove(driver);
    } else {
      next.add(driver);
    }
    state = state.copyWith(selectedDrivers: next);
    await _persistDraft();
  }

  Future<void> setCamera({
    String? id,
    String? name,
    double? pixelSizeMicrons,
  }) async {
    if (id == null || id.isEmpty) {
      state = state.copyWith(clearCamera: true);
    } else {
      state = state.copyWith(
        cameraId: id,
        cameraName: name,
        pixelSizeMicrons: pixelSizeMicrons ?? state.pixelSizeMicrons,
      );
    }
    await _persistDraft();
  }

  Future<void> setMount({String? id, String? name}) async {
    if (id == null || id.isEmpty) {
      state = state.copyWith(clearMount: true);
    } else {
      state = state.copyWith(mountId: id, mountName: name);
    }
    await _persistDraft();
  }

  Future<void> setFocuser({String? id, String? name}) async {
    if (id == null || id.isEmpty) {
      state = state.copyWith(clearFocuser: true);
    } else {
      state = state.copyWith(focuserId: id, focuserName: name);
    }
    await _persistDraft();
  }

  Future<void> setFilterWheel({
    String? id,
    String? name,
    List<String>? filterNames,
  }) async {
    if (id == null || id.isEmpty) {
      state = state.copyWith(clearFilterWheel: true, filterNames: const []);
    } else {
      state = state.copyWith(
        filterWheelId: id,
        filterWheelName: name,
        filterNames: filterNames ?? state.filterNames,
      );
    }
    await _persistDraft();
  }

  Future<void> setFilterNames(List<String> names) async {
    state = state.copyWith(filterNames: names);
    await _persistDraft();
  }

  Future<void> setGuider({String? id, String? name}) async {
    if (id == null || id.isEmpty) {
      state = state.copyWith(clearGuider: true);
    } else {
      state = state.copyWith(guiderId: id, guiderName: name);
    }
    await _persistDraft();
  }

  Future<void> setOpticalTrain({
    double? pixelSizeMicrons,
    double? focalLengthMm,
    double? apertureMm,
    double? reducerFactor,
  }) async {
    state = state.copyWith(
      pixelSizeMicrons: pixelSizeMicrons ?? state.pixelSizeMicrons,
      focalLengthMm: focalLengthMm ?? state.focalLengthMm,
      apertureMm: apertureMm ?? state.apertureMm,
      reducerFactor: reducerFactor ?? state.reducerFactor,
    );
    await _persistDraft();
  }

  Future<void> setCaptureDirectory(String path) async {
    state = state.copyWith(captureDirectory: path);
    await _persistDraft();
  }

  Future<void> setProfileName(String name) async {
    state = state.copyWith(profileName: name);
    await _persistDraft();
  }

  /// Result of completing the wizard: returns the created profile id so
  /// the launcher can immediately activate it.
  Future<int> complete() async {
    final draft = state;
    // Persist the new equipment profile. The DAO marks the first profile
    // as default+active on insert so the user lands on the dashboard
    // already pointed at their new rig.
    final dao = _ref.read(equipmentProfilesDaoProvider);
    final focalRatio = (draft.focalLengthMm != null &&
            draft.apertureMm != null &&
            draft.apertureMm! > 0)
        ? (draft.focalLengthMm! * draft.reducerFactor) / draft.apertureMm!
        : null;

    final profile = EquipmentProfileModel(
      name: (draft.profileName ?? '').trim().isNotEmpty
          ? draft.profileName!.trim()
          : 'My First Rig',
      description: 'Created by the first-run setup wizard',
      cameraId: draft.cameraId,
      cameraName: draft.cameraName,
      mountId: draft.mountId,
      mountName: draft.mountName,
      focuserId: draft.focuserId,
      focuserName: draft.focuserName,
      filterWheelId: draft.filterWheelId,
      filterWheelName: draft.filterWheelName,
      guiderId: draft.guiderId,
      guiderName: draft.guiderName,
      focalLength:
          draft.focalLengthMm != null ? draft.focalLengthMm! * draft.reducerFactor : 0.0,
      aperture: draft.apertureMm ?? 0.0,
      focalRatio: focalRatio,
      telescopeFocalLength: draft.focalLengthMm,
      telescopeAperture: draft.apertureMm,
      filterNames: draft.filterNames,
    );
    final id = await dao.createProfile(profile.toCompanion());

    // Persist the capture directory selection at the app-settings level so
    // the imaging service picks it up from day one.
    if (draft.captureDirectory != null &&
        draft.captureDirectory!.trim().isNotEmpty) {
      final settingsDao = _ref.read(settingsDaoProvider);
      await settingsDao.setDefaultImageDirectory(draft.captureDirectory!.trim());
    }

    // Mark onboarding done in tutorial_progress + wipe the draft blob.
    final tutorialDao = _ref.read(tutorialProgressDaoProvider);
    await tutorialDao.markCompleted(OnboardingDraft.persistenceCategory);
    final settingsDao = _ref.read(settingsDaoProvider);
    await settingsDao.deleteSetting(OnboardingDraft.draftSettingsKey);

    // Invalidate the bootstrap gate so the next launch reads `false`.
    _ref.invalidate(shouldRunEquipmentOnboardingProvider);

    return id;
  }

  /// User pressed "Skip onboarding". We mark the wizard dismissed in
  /// tutorial_progress so it stops auto-launching, but we keep the draft
  /// around in case the user reopens the wizard later from Settings.
  Future<void> skip() async {
    final tutorialDao = _ref.read(tutorialProgressDaoProvider);
    await tutorialDao.markDismissed(OnboardingDraft.persistenceCategory);
    _ref.invalidate(shouldRunEquipmentOnboardingProvider);
  }

  /// Reset the wizard to a pristine state. Used by the "Start over" button
  /// on the welcome step (and by tests).
  Future<void> reset() async {
    final available = _ref.read(availableOnboardingDriversProvider);
    final defaults =
        available.where((d) => d != DriverType.simulator).toSet();
    state = OnboardingDraft(selectedDrivers: defaults);
    await _persistDraft();
  }
}
