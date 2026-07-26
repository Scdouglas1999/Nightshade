import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../backend/network_backend.dart';
import '../models/backend/fits_header.dart' show FitsWriteHeader;
import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../models/flat_wizard/flat_capture_config.dart';
import '../models/flat_wizard/flat_wizard_state.dart';
import '../models/flat_wizard/flat_wizard_settings.dart';
import '../services/flat_exposure_calculator.dart';
import '../services/flat_wizard_service.dart';
import '../services/sky_brightness_tracker.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'equipment_provider.dart';
import 'profiles_provider.dart';

/// Provider for flat wizard state
final flatWizardProvider =
    StateNotifierProvider<FlatWizardNotifier, FlatWizardState>((ref) {
      return FlatWizardNotifier(ref);
    });

/// A filter queued for capture, paired with its STABLE index into
/// `FlatWizardState.filterSettings`. Carrying the original index (rather than a
/// subset-local loop index) is what keeps per-filter status/count updates
/// aligned with the correct row in quick mode and with disabled leading
/// filters.
class _QueuedFilter {
  final int originalIndex;
  final FlatFilterSettings settings;

  const _QueuedFilter(this.originalIndex, this.settings);
}

/// Creates an output directory only when this process owns the filesystem.
/// A remote controller sends the path to the imaging host, which creates the
/// parent tree immediately before writing the FITS file.
@visibleForTesting
Future<void> prepareFlatOutputDirectory(
  String path, {
  required bool createLocally,
}) async {
  if (!createLocally) return;
  await Directory(path).create(recursive: true);
}

/// Validates a controller-supplied output directory against the host's
/// allow-listed, writable roots and returns the normalized host path.
@visibleForTesting
Future<String> validateRemoteFlatOutputDirectory(
  NetworkBackend backend,
  String path,
) async {
  final validation = await backend.validateRemoteDirectory(
    path,
    mustExist: true,
    mustBeWritable: true,
  );
  if (validation['valid'] != true) {
    final detail =
        validation['error'] ??
        (validation['exists'] == false
            ? 'the directory does not exist on the host'
            : 'the directory is not writable on the host');
    throw StateError('Invalid host flat-frame folder: $detail');
  }
  final normalized = validation['normalizedPath'];
  return normalized is String && normalized.isNotEmpty ? normalized : path;
}

/// Provider for sky brightness tracker (sky flats mode)
final skyBrightnessTrackerProvider = Provider<SkyBrightnessTracker>((ref) {
  return SkyBrightnessTracker();
});

/// The effective, capability-resolved camera config for the flat wizard.
///
/// The UI watches this to show the target as an absolute ADU and a percentage
/// of the DETECTED full-scale range, and to keep controls truthful. It is
/// resolved from the CONNECTED camera — host-authoritative on a
/// [NetworkBackend], where the capability probes route to the master — so the
/// phone never invents a range. [FlatWizardNotifier.runCapture] re-resolves it
/// at run start and publishes the run's config here, so the UI preview, the
/// backend command, the FITS header, and the DB record all use ONE config.
final flatCameraConfigProvider =
    StateNotifierProvider<FlatCameraConfigNotifier, FlatCaptureConfig>((ref) {
      return FlatCameraConfigNotifier(ref);
    });

class FlatCameraConfigNotifier extends StateNotifier<FlatCaptureConfig> {
  final Ref ref;
  int _resolveGeneration = 0;

  FlatCameraConfigNotifier(this.ref) : super(const FlatCaptureConfig()) {
    // Re-resolve whenever the connected camera changes (connect/disconnect or a
    // different device) so the detected range appears as soon as a camera is
    // available and never lingers stale after a swap.
    ref.listen(cameraStateProvider, (prev, next) {
      if (prev?.deviceId != next.deviceId ||
          prev?.connectionState != next.connectionState) {
        // Fire-and-forget; resolve() is self-contained and never throws.
        resolve();
      }
    });
    ref.listen(activeEquipmentProfileProvider, (prev, next) {
      if (!_sameProfileCaptureInputs(prev, next)) {
        resolve();
      }
    });
    // Resolve immediately for a camera that is ALREADY connected when the
    // provider is first read (the listener above only fires on later changes).
    resolve();
  }

  /// Resolve the effective config from the connected camera + active profile
  /// and publish it. Returns the resolved config. When no camera is connected,
  /// publishes a generic 16-bit display fallback so the UI remains legible;
  /// its `rangeKnown` is false, so capture callers must not automate against
  /// that guessed range.
  Future<FlatCaptureConfig> resolve({
    int? fallbackBinX,
    int? fallbackBinY,
    bool failIfStale = false,
  }) async {
    final generation = ++_resolveGeneration;
    final camera = ref.read(cameraStateProvider);
    if (camera.connectionState != DeviceConnectionState.connected ||
        camera.deviceId == null) {
      const fallback = FlatCaptureConfig();
      if (mounted && generation == _resolveGeneration) state = fallback;
      return fallback;
    }
    final backend = ref.read(backendProvider);
    final profile = ref.read(activeEquipmentProfileProvider);
    final config = await FlatWizardService.resolveCaptureConfig(
      backend: backend,
      deviceId: camera.deviceId!,
      profileDefaultGain: profile?.defaultGain,
      profileDefaultOffset: profile?.defaultOffset,
      profileBinX: profile?.defaultBinX,
      profileBinY: profile?.defaultBinY,
      currentGain: camera.gain,
      currentOffset: camera.offset,
      fallbackBinX: fallbackBinX,
      fallbackBinY: fallbackBinY,
    );
    final liveCamera = ref.read(cameraStateProvider);
    final liveProfile = ref.read(activeEquipmentProfileProvider);
    final stale =
        generation != _resolveGeneration ||
        liveCamera.connectionState != DeviceConnectionState.connected ||
        liveCamera.deviceId != camera.deviceId ||
        !_sameProfileCaptureInputs(profile, liveProfile);
    if (stale) {
      if (failIfStale) {
        throw StateError(
          'Camera or equipment profile changed while resolving flat-capture '
          'capabilities',
        );
      }
      return state;
    }
    if (mounted) state = config;
    return config;
  }

  static bool _sameProfileCaptureInputs(
    EquipmentProfileModel? a,
    EquipmentProfileModel? b,
  ) =>
      a?.id == b?.id &&
      a?.defaultGain == b?.defaultGain &&
      a?.defaultOffset == b?.defaultOffset &&
      a?.defaultBinX == b?.defaultBinX &&
      a?.defaultBinY == b?.defaultBinY;
}

class FlatWizardNotifier extends StateNotifier<FlatWizardState> {
  final Ref ref;

  /// Cancellation token for the in-flight capture run. Non-null only while a
  /// run holds the busy latch. [requestCancel] cancels it; the run polls and
  /// races it so a cancel that lands mid-exposure aborts the hardware.
  FlatCancelToken? _cancelToken;

  /// Busy latch. Held for the whole duration of [runCapture] so a second
  /// start cannot race in (double-start) and the filter list cannot be
  /// reordered/toggled out from under the stable capture indices.
  bool _running = false;

  /// Test-only diagnostic sink. When set, the remote flat-history fault path
  /// invokes this with the caught error IN ADDITION to `developer.log`, so a
  /// test can prove a transport fault was distinguished from an empty host
  /// history (it fires on the fault path and stays silent on empty history).
  /// Null in production — behaviour is unchanged.
  @visibleForTesting
  void Function(Object error)? debugRemoteFaultSink;

  /// Settings key the persisted global-settings JSON blob lives under (the six
  /// user-facing fields — save path, targets, frame count, subfolder toggles).
  static const String _globalSettingsKey = 'flat_wizard_global_settings';

  /// Bumped on every user settings edit. The async hydrate captures this before
  /// its DB read and re-checks it afterward; a hydrate that resolves AFTER the
  /// user (or a run) has already touched the settings is discarded so it cannot
  /// clobber a live edit — mirrors PolarAlignmentConfigNotifier's load guard.
  int _settingsRevision = 0;

  FlatWizardNotifier(this.ref) : super(const FlatWizardState()) {
    unawaited(_hydrateGlobalSettings());
  }

  // --- Mode Management ---

  void setMode(FlatWizardMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setTwilightMode(TwilightMode mode) {
    state = state.copyWith(twilightMode: mode);
  }

  // --- Global Settings ---

  void updateGlobalSettings(FlatWizardGlobalSettings settings) {
    _settingsRevision++;
    state = state.copyWith(globalSettings: settings);
    _persistGlobalSettings();
  }

  void setHistogramTarget(double percent) {
    _settingsRevision++;
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        histogramTarget: percent.clamp(0, 100),
      ),
    );
    _persistGlobalSettings();
  }

  void setTolerance(double percent) {
    _settingsRevision++;
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        tolerancePercent: percent.clamp(1, 25),
      ),
    );
    _persistGlobalSettings();
  }

  void setFrameCount(int count) {
    _settingsRevision++;
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(
        frameCount: count.clamp(1, 999),
      ),
    );
    _persistGlobalSettings();
  }

  void setSavePath(String? path) {
    _settingsRevision++;
    state = state.copyWith(
      globalSettings: state.globalSettings.copyWith(savePath: path),
    );
    _persistGlobalSettings();
  }

  /// Restore the six persisted user-facing global-settings fields so the
  /// operator does not re-pick the flat folder (and re-tune targets) every
  /// launch. Applies the stored values onto the current defaults and no-ops on
  /// a missing/malformed record (falling back to defaults, logged like the
  /// file's other fault paths) or once a run or a user edit already owns the
  /// settings (the revision + [_running] guards). A store failure must never
  /// surface to the UI, so it is swallowed after logging.
  Future<void> _hydrateGlobalSettings() async {
    final revisionAtStart = _settingsRevision;
    try {
      final db = ref.read(databaseProvider);
      final raw = await db.settingsDao.getSetting(_globalSettingsKey);
      if (raw == null || raw.isEmpty) return;
      // A run in flight or an eager user edit owns the live settings — never
      // clobber it with the stale on-disk value.
      if (_running || _settingsRevision != revisionAtStart) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final current = state.globalSettings;
      state = state.copyWith(
        globalSettings: current.copyWith(
          savePath: decoded['savePath'] as String?,
          histogramTarget:
              (decoded['histogramTarget'] as num?)?.toDouble() ??
              current.histogramTarget,
          tolerancePercent:
              (decoded['tolerancePercent'] as num?)?.toDouble() ??
              current.tolerancePercent,
          frameCount:
              (decoded['frameCount'] as num?)?.toInt() ?? current.frameCount,
          createDateSubfolder:
              decoded['createDateSubfolder'] as bool? ??
              current.createDateSubfolder,
          createFilterSubfolders:
              decoded['createFilterSubfolders'] as bool? ??
              current.createFilterSubfolders,
        ),
      );
    } catch (e) {
      developer.log(
        'FlatWizard: could not restore persisted global settings (using '
        'defaults): $e',
        name: 'FlatWizardNotifier',
        level: 900,
        error: e,
      );
    }
  }

  /// Persist the six user-facing global-settings fields so they survive an app
  /// restart. Fire-and-forget: a settings-store failure must NEVER block or
  /// fail the UI, so it is surfaced only to the logs (`developer.log` survives
  /// release, unlike a stripped `debugPrint`), mirroring [_recordFlatHistory]'s
  /// non-fatal fault handling. `savePath` is the ACTIVE backend's path;
  /// [runCapture] re-validates a remote path at start, so a stale last-used
  /// value fails closed rather than writing to the wrong host.
  void _persistGlobalSettings() {
    final s = state.globalSettings;
    final payload = jsonEncode(<String, Object?>{
      'savePath': s.savePath,
      'histogramTarget': s.histogramTarget,
      'tolerancePercent': s.tolerancePercent,
      'frameCount': s.frameCount,
      'createDateSubfolder': s.createDateSubfolder,
      'createFilterSubfolders': s.createFilterSubfolders,
    });
    unawaited(
      ref
          .read(databaseProvider)
          .settingsDao
          .setSetting(_globalSettingsKey, payload)
          .catchError((Object e) {
            developer.log(
              'FlatWizard: failed to persist global settings: $e',
              name: 'FlatWizardNotifier',
              level: 900,
              error: e,
            );
          }),
    );
  }

  // --- Filter Management ---

  /// Load filters from connected filter wheel
  Future<void> loadFiltersFromWheel() async {
    // No-op while a capture run holds the busy latch. This rebuilds
    // `filterSettings` from scratch (statuses reset to pending, capturedCount to
    // 0), and the screen re-invokes it on every init (postFrameCallback); doing
    // so mid-run would wipe the live per-filter bookkeeping the truthful final
    // summary is computed from.
    if (_running) return;

    final fwState = ref.read(filterWheelStateProvider);
    if (fwState.filterNames.isEmpty) return;

    final backend = ref.read(backendProvider);
    final db = ref.read(databaseProvider);
    final profileId = ref.read(activeEquipmentProfileProvider)?.id;

    final filterSettings = <FlatFilterSettings>[];
    for (int i = 0; i < fwState.filterNames.length; i++) {
      final filterName = fwState.filterNames[i];

      // Get suggested exposure from history. On a remote client the local
      // `flat_history` table is empty (the master owns it), so derive the
      // suggestion from the host's flat history via `listFlats` — mirroring
      // `getSuggestedExposure`'s last-N-average logic — instead of the
      // always-null local DAO read.
      final double? suggested;
      if (backend is NetworkBackend) {
        suggested = await _remoteSuggestedExposure(
          backend,
          filterName: filterName,
          profileId: profileId,
        );
      } else {
        suggested = await db.flatHistoryDao.getSuggestedExposure(
          filterName: filterName,
          equipmentProfileId: profileId,
        );
      }

      filterSettings.add(
        FlatFilterSettings(
          filterName: filterName,
          filterPosition: i,
          suggestedExposure: suggested,
        ),
      );
    }

    // Point the quick-capture selection at the wheel's PHYSICAL position so a
    // fresh screen shoots the loaded filter, not row 0. `currentFilterIndex` is
    // otherwise only ever written by the run loop; nothing else syncs it to the
    // wheel. Fall back to 0 when the position is unknown or has no matching row.
    // Guaranteed not-running here (guard at the top), so this cannot disturb an
    // active run's progress index.
    var initialFilterIndex = 0;
    final currentPosition = fwState.currentPosition;
    if (currentPosition != null) {
      final match = filterSettings.indexWhere(
        (f) => f.filterPosition == currentPosition,
      );
      if (match >= 0) initialFilterIndex = match;
    }

    state = state.copyWith(
      filterSettings: filterSettings,
      currentFilterIndex: initialFilterIndex,
    );
  }

  /// Average of the last few host flat-history exposures for [filterName],
  /// mirroring `FlatHistoryDao.getSuggestedExposure` (last-N average) but
  /// sourced from the master via `GET /api/calibration/flats`. Returns null
  /// when the host has no history for this filter.
  Future<double?> _remoteSuggestedExposure(
    NetworkBackend backend, {
    required String filterName,
    int? profileId,
  }) async {
    try {
      final entries = await backend.listFlats(
        filter: filterName,
        equipmentProfileId: profileId,
        limit: 5,
      );
      if (entries.isEmpty) return null;
      final sum = entries.fold<double>(0, (s, e) => s + e.exposureDuration);
      return sum / entries.length;
    } catch (e) {
      // A transport/host fault must not block the wizard from loading; the
      // user can still enter exposures manually (same outcome as a null DAO
      // read on the local path). But unlike an empty history, a fault is a
      // diagnosable condition — record it instead of silently conflating the
      // two so a misconfigured/offline host is visible in the logs.
      developer.log(
        'FlatWizard: remote flat-history fetch failed for $filterName: $e',
        name: 'FlatWizardNotifier',
        level: 900,
        error: e,
      );
      debugRemoteFaultSink?.call(e);
      return null;
    }
  }

  /// Toggle filter enabled state.
  ///
  /// No-op while a capture run holds the busy latch: the run captured its
  /// filter list (with stable original indices) at start, so enabling/disabling
  /// a filter mid-run would desynchronize those indices from the live list.
  void toggleFilter(int index, bool enabled) {
    if (_running) return;
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(enabled: enabled);
    state = state.copyWith(filterSettings: updated);
  }

  /// Update per-filter settings. No-op while capturing (see [toggleFilter]).
  void updateFilterSettings(int index, FlatFilterSettings settings) {
    if (_running) return;
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = settings;
    state = state.copyWith(filterSettings: updated);
  }

  /// Reorder filters. No-op while capturing so the run's stable indices stay
  /// valid (reordering mid-run would repoint them at the wrong rows).
  void reorderFilters(int oldIndex, int newIndex) {
    if (_running) return;
    final updated = [...state.filterSettings];
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex < oldIndex ? newIndex : newIndex - 1, item);
    state = state.copyWith(filterSettings: updated);
  }

  /// Auto-order filters for twilight. No-op while capturing (reorder guard).
  void autoOrderForTwilight() {
    if (_running) return;
    if (state.filterSettings.isEmpty) return;

    // Define filter restrictiveness (higher = more restrictive = less light)
    const restrictiveness = {
      'Ha': 100,
      'H-alpha': 100,
      'Halpha': 100,
      'SII': 95,
      'S-II': 95,
      'S2': 95,
      'OIII': 90,
      'O-III': 90,
      'O3': 90,
      'NII': 85,
      'N-II': 85,
      'R': 50,
      'Red': 50,
      'G': 45,
      'Green': 45,
      'B': 40,
      'Blue': 40,
      'L': 10,
      'Lum': 10,
      'Luminance': 10,
      'Clear': 10,
    };

    int getRestrictiveness(String filter) {
      for (final entry in restrictiveness.entries) {
        if (filter.toLowerCase().contains(entry.key.toLowerCase())) {
          return entry.value;
        }
      }
      return 50; // Default middle value
    }

    final sorted = [...state.filterSettings];
    sorted.sort((a, b) {
      final aVal = getRestrictiveness(a.filterName);
      final bVal = getRestrictiveness(b.filterName);

      if (state.twilightMode == TwilightMode.dusk) {
        // Dusk (darkening): most restrictive first
        return bVal.compareTo(aVal);
      } else {
        // Dawn (brightening): least restrictive first
        return aVal.compareTo(bVal);
      }
    });

    state = state.copyWith(filterSettings: sorted);
  }

  // --- Visualization Toggles ---

  void toggleAduGraph(bool show) {
    state = state.copyWith(showAduGraph: show);
  }

  void toggleExposureTimeline(bool show) {
    state = state.copyWith(showExposureTimeline: show);
  }

  void toggleSkyBrightness(bool show) {
    state = state.copyWith(showSkyBrightness: show);
  }

  void toggleFilterCards(bool show) {
    state = state.copyWith(showFilterCards: show);
  }

  void toggleHistogramOverlay(bool show) {
    state = state.copyWith(showHistogramOverlay: show);
  }

  // --- Capture Control ---

  bool _startPromptReserved = false;

  /// Whether capture startup or a capture run currently owns the wizard.
  bool get isBusy => _running || _startPromptReserved;

  /// Reserve startup before the UI awaits a save-location dialog. The capture
  /// run's own latch cannot engage until that dialog returns, so this prevents
  /// a second tab/button from opening another dialog in the meantime.
  bool reserveStartPrompt() {
    if (isBusy) return false;
    _startPromptReserved = true;
    return true;
  }

  void releaseStartPrompt() {
    _startPromptReserved = false;
  }

  void requestCancel() {
    // Cooperative: flip the active run's token. The run's calibration and
    // frame loops poll it and race [FlatCancelToken.whenCancelled], so an
    // in-flight exposure is aborted rather than waited out.
    _cancelToken?.cancel();
    if (_running) {
      state = state.copyWith(statusMessage: 'Cancelling...');
    }
  }

  bool get cancelRequested => _cancelToken?.isCancelled ?? false;

  void clearCancelRequest() {
    if (!_running) _cancelToken = null;
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearWarning() {
    state = state.copyWith(warningMessage: null);
  }

  void setStatusMessage(String? message) {
    state = state.copyWith(statusMessage: message);
  }

  void setErrorMessage(String? message) {
    state = state.copyWith(errorMessage: message);
  }

  void setWarningMessage(String? message) {
    state = state.copyWith(warningMessage: message);
  }

  void setCapturing(bool capturing) {
    state = state.copyWith(isCapturing: capturing);
  }

  void setExposing(bool exposing, {DateTime? startTime, double? duration}) {
    state = state.copyWith(
      isExposing: exposing,
      exposureStartTime: startTime,
      currentExposureDuration: duration,
    );
  }

  // --- ADU History ---

  void addAduMeasurement(double exposure, double adu) {
    final measurement = AduMeasurement(
      exposure: exposure,
      adu: adu,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(aduHistory: [...state.aduHistory, measurement]);
  }

  void clearAduHistory() {
    state = state.copyWith(aduHistory: []);
  }

  // --- Image Preview ---

  void setLastImage(String? path, dynamic imageData) {
    state = state.copyWith(lastImagePath: path, lastImageData: imageData);
  }

  // --- Filter Progress ---

  /// Internal run-progress update: advances the "current filter" as the run
  /// loop walks its queue. Unguarded on purpose — the run OWNS this while it
  /// holds the busy latch. User-facing selection goes through [selectQuickFilter]
  /// instead, so guarding one does not stall the other.
  void setCurrentFilterIndex(int index) {
    state = state.copyWith(currentFilterIndex: index);
  }

  /// User-facing quick-capture filter selection (the Quick tab dropdown).
  ///
  /// No-op while a capture run holds the busy latch: the run captured its target
  /// filter at start and drives [setCurrentFilterIndex] itself for progress, so
  /// a user change mid-run would repoint the capture. Mirrors [toggleFilter]'s
  /// guard.
  void selectQuickFilter(int index) {
    if (_running) return;
    if (index < 0 || index >= state.filterSettings.length) return;
    state = state.copyWith(currentFilterIndex: index);
  }

  void setCurrentFrameIndex(int index) {
    state = state.copyWith(currentFrameIndex: index);
  }

  void updateFilterStatus(int index, FilterCalibrationStatus status) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(status: status);
    state = state.copyWith(filterSettings: updated);
  }

  void updateFilterCalibration(int index, double exposure, double adu) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(
      calibratedExposure: exposure,
      currentAdu: adu,
    );
    state = state.copyWith(filterSettings: updated);
  }

  void incrementFilterCapturedCount(int index) {
    if (index < 0 || index >= state.filterSettings.length) return;

    final updated = [...state.filterSettings];
    updated[index] = updated[index].copyWith(
      capturedCount: updated[index].capturedCount + 1,
    );
    state = state.copyWith(filterSettings: updated);
  }

  // --- Capture Lifecycle ---

  /// Run the full flat-capture lifecycle for the current mode: per-filter
  /// calibration, frame capture, FITS save, and history recording.
  ///
  /// This is the single authoritative entry point. The screen only resolves
  /// the save path (dialog) and calls this; all validation, cancellation, and
  /// truthful outcome reporting live here so the UI cannot drift from reality.
  ///
  /// Contract:
  ///   * Rejected (no-op) if a run already holds the busy latch — no double
  ///     start, no overlapping camera ownership.
  ///   * `isCapturing` is set ONLY after validation passes, so a failed
  ///     precondition never flashes the "Capturing" badge.
  ///   * Per-filter state updates use the STABLE original index into
  ///     `filterSettings`, so quick-mode (current filter != row 0) and disabled
  ///     leading filters update the correct rows.
  ///   * Cancellation is cooperative and aborts the in-flight exposure exactly
  ///     once (see [FlatWizardService.exposeAndAwait]); no further frame or
  ///     filter is started afterward.
  ///   * A frame counts as saved ONLY after its FITS write succeeds; a save
  ///     failure is a capture failure. History is recorded ONLY when at least
  ///     one real file landed on disk; a filter is marked complete/partial/
  ///     failed truthfully from the saved count.
  ///   * The final status message is PERSISTED — it is not cleared on exit.
  Future<void> runCapture() async {
    // Busy latch FIRST (synchronous, before any await) so a second start is
    // rejected even while the async validation below is in flight.
    if (_running) {
      developer.log(
        'FlatWizard: runCapture ignored — a run is already active',
        name: 'FlatWizardNotifier',
        level: 900,
      );
      return;
    }
    _running = true;
    final cancelToken = FlatCancelToken();
    _cancelToken = cancelToken;

    try {
      final backend = ref.read(backendProvider);
      final cameraState = ref.read(cameraStateProvider);
      // Build the service inline from the current backend + settings rather
      // than `ref.read(flatWizardServiceProvider)`: that provider `ref.watch`es
      // THIS provider's state, so reading it from our own notifier would form a
      // circular provider dependency.
      final flatService = FlatWizardService.fromSettings(
        backend,
        state.globalSettings,
      );
      final db = ref.read(databaseProvider);
      final activeProfile = ref.read(activeEquipmentProfileProvider);
      final profileId = activeProfile?.id;
      final brightnessTracker = ref.read(skyBrightnessTrackerProvider);

      // ---- Validation (BEFORE isCapturing is set) ----
      if (cameraState.connectionState != DeviceConnectionState.connected ||
          cameraState.deviceId == null) {
        setErrorMessage('Camera not connected');
        return;
      }
      final cameraId = cameraState.deviceId!;

      // Global camera/hardware ownership: refuse to start if the camera is
      // already mid-exposure for another operation (imaging/sequence). Prevents
      // two owners driving the same camera into a fault.
      if (cameraState.isExposing) {
        setErrorMessage('Camera is busy with another exposure');
        return;
      }

      var savePath = state.globalSettings.savePath;
      if (savePath == null || savePath.isEmpty) {
        setErrorMessage('No save path set');
        return;
      }
      if (backend is NetworkBackend) {
        try {
          savePath = await validateRemoteFlatOutputDirectory(backend, savePath);
        } catch (error) {
          setErrorMessage(
            'Flat-frame save path is not usable on the imaging host: $error',
          );
          setStatusMessage('Failed — choose a writable host folder.');
          return;
        }
      }

      final queue = _buildFilterQueue();
      if (queue.isEmpty) {
        setErrorMessage('No filters selected');
        return;
      }

      // Snapshot the run's algorithm mode ONCE, right where the filter queue is
      // latched. runCapture otherwise reads `state.mode`/`state.twilightMode`
      // LIVE deep in the per-filter loop (sky-flats rate tracking at the
      // calibrate step and the recorded twilight phase). The tab bar stays
      // intentionally tappable mid-run so the operator can browse, which flips
      // `state.mode` live — without this snapshot, peeking at the Sky Flats tab
      // during a Batch run would silently switch the algorithm for the
      // remaining filters.
      final runMode = state.mode;
      final runTwilightMode = state.twilightMode;

      // Resolve ONE effective capture configuration from the connected camera
      // (host-authoritative on a NetworkBackend) + active profile, and publish
      // it so the UI preview, this capture command, the FITS header, and the DB
      // record all agree. maxAdu drives the target so a 12/14-bit camera does
      // not chase an impossible ADU; gain/offset are `null` (camera default)
      // rather than a stale zero when unset; binning honours the profile and
      // camera capability.
      final config = await ref
          .read(flatCameraConfigProvider.notifier)
          .resolve(
            fallbackBinX: state.globalSettings.binning,
            fallbackBinY: state.globalSettings.binning,
            failIfStale: true,
          );
      if (!config.rangeKnown) {
        setErrorMessage(
          'Could not determine the connected camera\'s ADU range. '
          'Reconnect the camera or refresh its capabilities before starting '
          'automatic flat calibration.',
        );
        setStatusMessage('Failed — camera ADU range is unknown.');
        return;
      }
      final liveCameraAfterResolve = ref.read(cameraStateProvider);
      if (liveCameraAfterResolve.connectionState !=
              DeviceConnectionState.connected ||
          liveCameraAfterResolve.deviceId != cameraId ||
          liveCameraAfterResolve.isExposing) {
        setErrorMessage(
          'Camera changed state while preparing flat capture. Try again once '
          'the camera is connected and idle.',
        );
        setStatusMessage('Failed — camera changed while preparing.');
        return;
      }

      // ---- Committed: from here we are truly capturing ----
      _prepareFiltersForRun(queue);
      state = state.copyWith(
        isCapturing: true,
        errorMessage: null,
        warningMessage: null,
        statusMessage: 'Initializing...',
        aduHistory: const [],
        currentFrameIndex: 0,
      );
      final historyGain = config.gain ?? cameraState.gain ?? 0;

      // Base save path with optional date subfolder.
      var baseSavePath = savePath;
      if (state.globalSettings.createDateSubfolder) {
        baseSavePath = p.join(baseSavePath, _fmtDate(DateTime.now()));
      }
      final createOutputLocally = backend is! NetworkBackend;
      await prepareFlatOutputDirectory(
        baseSavePath,
        createLocally: createOutputLocally,
      );

      var cancelled = false;
      // Set when a timeout / uncertain-camera outcome forces a fail-safe STOP of
      // the whole run (distinct from a user cancel). Carries the actionable
      // message surfaced to the operator.
      String? haltError;

      for (final queued in queue) {
        if (cancelToken.isCancelled) {
          cancelled = true;
          break;
        }

        // Fast-fail on a mid-run camera disconnect instead of waiting out a
        // full exposure timeout on the next frame. The exposure's own timeout
        // remains the ultimate guard for a disconnect that lands mid-exposure.
        final liveCamera = ref.read(cameraStateProvider);
        if (liveCamera.connectionState != DeviceConnectionState.connected ||
            liveCamera.deviceId == null) {
          haltError = 'Camera disconnected — run stopped.';
          break;
        }

        final idx = queued.originalIndex;
        final filterSetting = queued.settings;
        setCurrentFilterIndex(idx);
        updateFilterStatus(idx, FilterCalibrationStatus.calibrating);
        setStatusMessage('Calibrating ${filterSetting.filterName}...');

        final moveError = await moveFilterWheelAndWait(
          filterSetting.filterPosition,
          cancelToken,
        );
        if (cancelToken.isCancelled) {
          updateFilterStatus(idx, FilterCalibrationStatus.skipped);
          cancelled = true;
          break;
        }
        if (moveError != null) {
          // Fail-safe: an uncertain filter position taints every remaining
          // filter, so stop the whole run rather than capture the wrong flat.
          updateFilterStatus(idx, FilterCalibrationStatus.failed);
          haltError = '${filterSetting.filterName}: $moveError — run stopped.';
          break;
        }

        // ---- Calibrate exposure ----
        // Target ADU is an absolute value against the DETECTED full scale, so a
        // 12/14-bit camera targets e.g. 50% of 4095/16383 — never an impossible
        // 32768.
        final targetAdu = FlatExposureCalculator.histogramPercentToAdu(
          filterSetting.histogramTargetOverride ??
              state.globalSettings.histogramTarget,
          maxAdu: config.maxAdu,
        ).toDouble();
        final tolerance =
            filterSetting.toleranceOverride ??
            state.globalSettings.tolerancePercent;
        final minExp =
            filterSetting.minExposureOverride ??
            state.globalSettings.minExposure;
        final maxExp =
            filterSetting.maxExposureOverride ??
            state.globalSettings.maxExposure;

        final FlatResult calibration;
        if (runMode == FlatWizardMode.skyFlats) {
          calibration = await flatService.calibrateFilterWithRateTracking(
            deviceId: cameraId,
            filter: filterSetting.filterName,
            gain: config.gain,
            offset: config.offset,
            targetAdu: targetAdu,
            tolerance: tolerance,
            minExposure: minExp,
            maxExposure: maxExp,
            binX: config.binX,
            binY: config.binY,
            brightnessTracker: brightnessTracker,
            historicalExposure: filterSetting.suggestedExposure,
            cancelToken: cancelToken,
            onProgress: (iteration, exposure, adu, status) {
              addAduMeasurement(exposure, adu);
              updateFilterCalibration(idx, exposure, adu);
              setStatusMessage(
                '${filterSetting.filterName}: $status '
                '(${exposure.toStringAsFixed(2)}s, ADU: ${adu.toStringAsFixed(0)})',
              );
            },
          );
        } else {
          calibration = await flatService.calibrateFilter(
            deviceId: cameraId,
            filter: filterSetting.filterName,
            gain: config.gain,
            offset: config.offset,
            targetAdu: targetAdu,
            tolerance: tolerance,
            minExposure: minExp,
            maxExposure: maxExp,
            binX: config.binX,
            binY: config.binY,
            cancelToken: cancelToken,
            onProgress: (iteration, exposure, adu) {
              addAduMeasurement(exposure, adu);
              updateFilterCalibration(idx, exposure, adu);
              setStatusMessage(
                '${filterSetting.filterName}: Iteration $iteration '
                '(${exposure.toStringAsFixed(2)}s, ADU: ${adu.toStringAsFixed(0)})',
              );
            },
          );
        }

        if (calibration.cancelled) {
          // Calibration never completed for this filter — it is skipped, not
          // failed.
          updateFilterStatus(idx, FilterCalibrationStatus.skipped);
          cancelled = true;
          break;
        }
        if (calibration.haltRun) {
          // Fail-safe: a calibration exposure timed out or the camera's idle
          // state is uncertain — stop the WHOLE run rather than risk overlapping
          // exposures. Surface an actionable error.
          updateFilterStatus(idx, FilterCalibrationStatus.failed);
          haltError = calibration.cameraStateUnknown
              ? '${filterSetting.filterName}: '
                    '${calibration.errorMessage ?? "camera state unknown"} — '
                    'run stopped; check the camera.'
              : '${filterSetting.filterName}: '
                    '${calibration.errorMessage ?? "exposure timed out"} — '
                    'run stopped.';
          break;
        }
        if (!calibration.success) {
          updateFilterStatus(idx, FilterCalibrationStatus.failed);
          setWarningMessage(
            '${filterSetting.filterName}: '
            '${calibration.errorMessage ?? "Calibration failed"}',
          );
          continue; // move on to the next filter
        }

        updateFilterCalibration(idx, calibration.exposure, calibration.adu);
        updateFilterStatus(idx, FilterCalibrationStatus.capturing);

        // ---- Frame capture ----
        var filterSavePath = baseSavePath;
        if (state.globalSettings.createFilterSubfolders) {
          filterSavePath = p.join(
            baseSavePath,
            _sanitizeComponent(filterSetting.filterName),
          );
          await prepareFlatOutputDirectory(
            filterSavePath,
            createLocally: createOutputLocally,
          );
        }

        final frameCount =
            filterSetting.frameCountOverride ?? state.globalSettings.frameCount;
        var savedCount = 0;
        var frameCancelled = false;
        var frameHalted = false;

        for (int frameNum = 1; frameNum <= frameCount; frameNum++) {
          if (cancelToken.isCancelled) {
            frameCancelled = true;
            break;
          }

          // Fast-fail if the camera dropped between frames rather than waiting
          // out this frame's exposure timeout.
          final frameCamera = ref.read(cameraStateProvider);
          if (frameCamera.connectionState != DeviceConnectionState.connected ||
              frameCamera.deviceId == null) {
            frameHalted = true;
            haltError = 'Camera disconnected — run stopped.';
            break;
          }

          setCurrentFrameIndex(frameNum);
          setStatusMessage(
            '${filterSetting.filterName}: Capturing frame $frameNum/$frameCount',
          );
          setExposing(
            true,
            startTime: DateTime.now(),
            duration: calibration.exposure,
          );

          // Authoritative capture: waits for the real completion event (no
          // fixed delay), aborts the hardware on cancel/timeout, and uses the
          // one resolved effective config (gain/offset/binning).
          final capture = await flatService.exposeAndAwait(
            deviceId: cameraId,
            exposureTime: calibration.exposure,
            gain: config.gain,
            offset: config.offset,
            binX: config.binX,
            binY: config.binY,
            cancelToken: cancelToken,
          );
          setExposing(false);

          if (capture.isCancelled) {
            // A cancelled exposure is never saved or counted.
            frameCancelled = true;
            break;
          }

          if (capture.isTimedOut) {
            // Fail-safe: the exposure timed out. Never read a stale image and
            // never start the next frame while the prior may still be active —
            // stop the run. When the camera could not be confirmed idle the
            // operator must check the hardware.
            frameHalted = true;
            haltError = capture.cameraQuiescent
                ? '${filterSetting.filterName} frame $frameNum timed out — '
                      'run stopped.'
                : '${filterSetting.filterName} frame $frameNum timed out and '
                      'the camera could not be confirmed idle — run stopped; '
                      'check the camera.';
            break;
          }

          if (capture.outcome != FlatFrameOutcome.completed) {
            // Per-frame error is surfaced, not swallowed. It is NOT counted as
            // a saved frame.
            setWarningMessage(
              '${filterSetting.filterName} frame $frameNum failed: '
              '${capture.error ?? "capture failed"}',
            );
            continue;
          }

          // Save the frame. A save failure IS a capture failure: the frame is
          // surfaced as failed and NOT counted.
          final captureTime = DateTime.now();
          final filename =
              '${_sanitizeComponent('Flat_${filterSetting.filterName}_'
              '${_fmtStamp(captureTime)}_$frameNum')}.fits';
          final filePath = p.join(filterSavePath, filename);
          try {
            await backend.saveFitsFromLastCapture(
              deviceId: cameraId,
              filePath: filePath,
              headerData: FitsWriteHeader(
                frameType: 'FLAT',
                filter: filterSetting.filterName,
                exposureTime: calibration.exposure,
                captureTimestamp: captureTime.toIso8601String(),
                gain: config.gain,
                offset: config.offset,
                binX: config.binX,
                binY: config.binY,
              ),
            );
          } catch (e) {
            setWarningMessage(
              '${filterSetting.filterName} frame $frameNum save failed: $e',
            );
            continue;
          }

          // Only NOW is the frame real on disk. Update counters + preview.
          savedCount++;
          incrementFilterCapturedCount(idx);
          final image = capture.image;
          if (image != null) {
            setLastImage(filePath, image.displayData);
            addAduMeasurement(calibration.exposure, image.stats.mean);
          }
        }

        // ---- Truthful per-filter status from the REAL saved count ----
        final FilterCalibrationStatus finalStatus;
        if (savedCount == 0) {
          finalStatus = frameCancelled
              ? FilterCalibrationStatus.skipped
              : FilterCalibrationStatus.failed;
        } else if (savedCount < frameCount) {
          finalStatus = FilterCalibrationStatus.partial;
        } else {
          finalStatus = FilterCalibrationStatus.complete;
        }
        updateFilterStatus(idx, finalStatus);

        // Record history ONLY when at least one real file landed on disk. Any
        // frames written before a halt are real and still learned from.
        if (savedCount > 0) {
          await _recordFlatHistory(
            backend: backend,
            db: db,
            profileId: profileId,
            filterName: filterSetting.filterName,
            exposure: calibration.exposure,
            adu: calibration.adu,
            gain: historyGain,
            brightnessTracker: brightnessTracker,
            runMode: runMode,
            runTwilightMode: runTwilightMode,
          );
        }

        // Fail-safe stop: a timed-out / uncertain-camera frame stops the whole
        // run, never just this filter.
        if (frameHalted) break;

        if (frameCancelled || cancelToken.isCancelled) {
          cancelled = true;
          break;
        }
      }

      if (haltError != null) {
        // A fail-safe stop: surface the actionable message and persist it as
        // both the status and an error so the operator is not left guessing.
        setStatusMessage(haltError);
        setErrorMessage(haltError);
      } else {
        _setFinalStatus(queue: queue, cancelled: cancelled);
      }
    } catch (e, st) {
      developer.log(
        'FlatWizard: capture run failed: $e',
        name: 'FlatWizardNotifier',
        level: 1000,
        error: e,
        stackTrace: st,
      );
      setErrorMessage('Capture failed: $e');
      setStatusMessage('Capture failed.');
    } finally {
      // Persist the final status message (do NOT clear it) — the run's outcome
      // stays visible until a deliberate next start or reset. Only the
      // transient capture/exposing flags are cleared and the latch released.
      state = state.copyWith(isCapturing: false, isExposing: false);
      _running = false;
    }
  }

  /// Build the ordered list of filters to capture, each paired with its STABLE
  /// index into `filterSettings`.
  ///
  /// Quick mode captures ONLY the currently-selected filter, carrying its real
  /// row index (not 0) so its status/count updates hit the right row. Batch/sky
  /// modes capture every enabled filter, each carrying its true row index so a
  /// disabled leading filter does not shift the mapping.
  List<_QueuedFilter> _buildFilterQueue() {
    final filters = state.filterSettings;
    if (state.mode == FlatWizardMode.quick) {
      final idx = state.currentFilterIndex;
      if (filters.isNotEmpty && idx >= 0 && idx < filters.length) {
        return [_QueuedFilter(idx, filters[idx])];
      }
      return const [];
    }
    final queue = <_QueuedFilter>[];
    for (var i = 0; i < filters.length; i++) {
      if (filters[i].enabled) queue.add(_QueuedFilter(i, filters[i]));
    }
    return queue;
  }

  /// Reset the queued filters to a clean per-run state (pending, zero saved
  /// count) so the final summary and progress reflect THIS run, not a prior
  /// one. Filters not in the queue keep their state.
  void _prepareFiltersForRun(List<_QueuedFilter> queue) {
    final updated = [...state.filterSettings];
    for (final q in queue) {
      if (q.originalIndex < 0 || q.originalIndex >= updated.length) continue;
      updated[q.originalIndex] = updated[q.originalIndex].copyWith(
        status: FilterCalibrationStatus.pending,
        capturedCount: 0,
      );
    }
    state = state.copyWith(filterSettings: updated);
  }

  /// Compute and persist a truthful final status from the LIVE filter rows
  /// (never an immutable snapshot captured at loop start).
  void _setFinalStatus({
    required List<_QueuedFilter> queue,
    required bool cancelled,
  }) {
    var complete = 0;
    var partial = 0;
    var failed = 0;
    var framesSaved = 0;
    for (final q in queue) {
      if (q.originalIndex < 0 ||
          q.originalIndex >= state.filterSettings.length) {
        continue;
      }
      final f = state.filterSettings[q.originalIndex];
      switch (f.status) {
        case FilterCalibrationStatus.complete:
          complete++;
          break;
        case FilterCalibrationStatus.partial:
          partial++;
          break;
        case FilterCalibrationStatus.failed:
          failed++;
          break;
        default:
          break;
      }
      framesSaved += f.capturedCount;
    }

    if (cancelled) {
      setStatusMessage(
        'Cancelled — saved $framesSaved frame(s); '
        '$complete complete, $partial partial.',
      );
      return;
    }
    if (complete == queue.length && partial == 0 && failed == 0) {
      setStatusMessage(
        'Complete — ${queue.length} filter(s), $framesSaved frame(s) saved.',
      );
      return;
    }
    if (complete == 0 && partial == 0) {
      setStatusMessage('Failed — no frames saved.');
      setErrorMessage('Flat capture failed — no frames were saved.');
      return;
    }
    setStatusMessage(
      'Finished with issues — $complete complete, $partial partial, '
      '$failed failed; $framesSaved frame(s) saved.',
    );
  }

  /// Move the filter wheel to [position] and wait for it to actually settle.
  ///
  /// Returns `null` on success (or when there is no wheel / it is already
  /// there). Returns an actionable error string when the move itself FAILS (the
  /// driver threw) — the caller must then STOP the run rather than capture a
  /// flat through an unknown filter.
  ///
  /// Settle is STATE-DRIVEN, not a blind fixed delay: after a short floor (to
  /// bridge the gap before a just-started move is reflected in the polled wheel
  /// state), it waits until the wheel reports it is no longer moving AND has
  /// reached [position]. A backend that does not report a position is not
  /// considered settled: after [maxWait] the move fails closed so a flat is
  /// never captured through an unknown filter. A cooperative cancel
  /// short-circuits the wait promptly.
  Future<String?> moveFilterWheelAndWait(
    int position,
    FlatCancelToken cancelToken, {
    Duration maxWait = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration settleFloor = const Duration(milliseconds: 150),
  }) async {
    final fwState = ref.read(filterWheelStateProvider);
    if (fwState.connectionState != DeviceConnectionState.connected ||
        fwState.deviceId == null) {
      return null; // no wheel to drive
    }
    if (!fwState.isMoving && fwState.currentPosition == position) {
      return null; // already settled at the target
    }

    final deviceBackend = ref.read(deviceBackendProvider);
    try {
      await deviceBackend.filterWheelSetPosition(fwState.deviceId!, position);
    } catch (e) {
      developer.log(
        'FlatWizard: filter wheel move to $position failed: $e',
        name: 'FlatWizardNotifier',
        level: 1000,
        error: e,
      );
      return 'filter wheel failed to move ($e)';
    }

    // Floor: give the driver/state a moment to register that the move started
    // so an async wheel that reports `isMoving` a beat late is not mistaken for
    // already-settled (which would expose mid-move). Skipped on cancel.
    if (!cancelToken.isCancelled) {
      await Future<void>.delayed(settleFloor);
    }

    // Wait for the wheel to report it has stopped moving AND reached the target.
    var waited = Duration.zero;
    while (waited < maxWait) {
      if (cancelToken.isCancelled) return null; // caller handles the cancel
      final s = ref.read(filterWheelStateProvider);
      if (s.connectionState != DeviceConnectionState.connected ||
          s.deviceId != fwState.deviceId) {
        return 'filter wheel disconnected before reaching position $position';
      }
      final reachedTarget = s.currentPosition == position;
      if (!s.isMoving && reachedTarget) return null; // truly settled
      await Future<void>.delayed(pollInterval);
      waited += pollInterval;
    }
    // A named-filter exposure is unsafe while position is unverified. Stop
    // rather than silently photographing through whichever filter happens to
    // be in the optical path.
    developer.log(
      'FlatWizard: filter wheel settle not confirmed within '
      '${maxWait.inSeconds}s (stopping fail-safe)',
      name: 'FlatWizardNotifier',
      level: 900,
    );
    return 'filter wheel did not confirm position $position within '
        '${maxWait.inSeconds}s';
  }

  /// Record a completed filter's calibration to flat history. Preserves the
  /// remote-vs-local routing exactly: on a [NetworkBackend] the record is
  /// posted to the master (so its library learns from the remote session);
  /// otherwise it is written to the local DAO. Never throws — a history-write
  /// failure must not fail the capture (the frames are already on disk).
  Future<void> _recordFlatHistory({
    required dynamic backend,
    required dynamic db,
    required int? profileId,
    required String filterName,
    required double exposure,
    required double adu,
    required int gain,
    required SkyBrightnessTracker brightnessTracker,
    required FlatWizardMode runMode,
    required TwilightMode runTwilightMode,
  }) async {
    try {
      // Use the run's snapshotted mode/twilight, not `state.mode`/
      // `state.twilightMode`: browsing to another tab mid-run flips those live
      // and would misrecord the sky-flats rate / twilight phase for the
      // remaining filters.
      final skyAduRate = runMode == FlatWizardMode.skyFlats
          ? brightnessTracker.calculateRate()
          : null;
      final twilightPhase = runMode == FlatWizardMode.skyFlats
          ? (runTwilightMode == TwilightMode.dawn ? 'dawn' : 'dusk')
          : null;
      if (backend is NetworkBackend) {
        await backend.recordFlat(
          filter: filterName,
          exposureDuration: exposure,
          adu: adu.toInt(),
          histogramTarget: state.globalSettings.histogramTarget,
          gain: gain,
          skyAduRate: skyAduRate,
          twilightPhase: twilightPhase,
          equipmentProfileId: profileId,
        );
      } else {
        await db.flatHistoryDao.recordCalibration(
          filterName: filterName,
          exposureTime: exposure,
          histogramTarget: state.globalSettings.histogramTarget,
          actualAdu: adu.toInt(),
          equipmentProfileId: profileId,
          skyAduRate: skyAduRate,
          twilightPhase: twilightPhase,
        );
      }
    } catch (e, st) {
      // A history-write failure must NOT fail the capture (the frames are
      // already on disk), but it must not vanish either: `debugPrint` is
      // stripped in release, so a persistently-failing library write would be
      // invisible on the appliance. Log at warning level AND surface a
      // non-fatal warning so the operator knows the flat LIBRARY did not learn
      // this exposure (their frames are still saved).
      developer.log(
        'FlatWizard: failed to record calibration to flat history for '
        '$filterName: $e',
        name: 'FlatWizardNotifier',
        level: 900,
        error: e,
        stackTrace: st,
      );
      setWarningMessage(
        '$filterName: frames saved, but the flat library did not record this '
        'calibration ($e).',
      );
    }
  }

  /// Strip path separators and characters illegal on common filesystems from a
  /// filename/subfolder component built from user/hardware-supplied filter
  /// names (which can contain `/`, `:`, etc.). Never returns empty.
  String _sanitizeComponent(String raw) {
    var s = raw.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Trim leading/trailing dots and spaces (Windows rejects trailing dots).
    s = s.replaceAll(RegExp(r'^[.\s]+'), '').replaceAll(RegExp(r'[.\s]+$'), '');
    return s.isEmpty ? 'unnamed' : s;
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _fmtDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  String _fmtStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}'
      '_${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

  // --- Reset ---

  void reset() {
    // Refuse to wipe state out from under an active run; cancel it instead.
    if (_running) {
      requestCancel();
      return;
    }
    _cancelToken = null;
    state = const FlatWizardState();
  }
}
