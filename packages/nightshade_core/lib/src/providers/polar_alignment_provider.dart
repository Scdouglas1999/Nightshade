import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart';
import '../models/backend/event_types.dart' show EventCategory;
import '../database/database.dart';
import '../models/polar_alignment_config.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'profiles_provider.dart';

// =============================================================================
// POLAR ALIGNMENT STATE PROVIDER
// =============================================================================

/// Main provider for polar alignment runtime state
final polarAlignmentStateProvider =
    StateNotifierProvider<PolarAlignmentStateNotifier, PolarAlignmentState>((
      ref,
    ) {
      return PolarAlignmentStateNotifier(ref);
    });

/// Notifier that manages polar alignment state and subscribes to backend events
class PolarAlignmentStateNotifier extends StateNotifier<PolarAlignmentState> {
  final Ref ref;
  StreamSubscription? _eventSub;

  /// Stores the initial error when entering adjustment phase
  PolarAlignmentError? _capturedInitialError;

  PolarAlignmentStateNotifier(this.ref) : super(const PolarAlignmentState()) {
    _init();
  }

  void _init() {
    _bindToBackend(ref.read(backendProvider));

    // The active backend can be swapped at runtime (local FFI <-> network).
    // Re-bind to the new backend's event stream on every swap so polar
    // alignment events keep flowing after a reconnect; the old subscription
    // is cancelled inside [_bindToBackend].
    ref.listen<NightshadeBackend>(backendProvider, (_, next) {
      _bindToBackend(next);
    });
  }

  void _bindToBackend(NightshadeBackend backend) {
    _eventSub?.cancel();

    // Subscribe to general event stream for polar alignment events
    _eventSub = backend.eventStream.listen((event) {
      if (!mounted) return; // Guard against updates after disposal

      if (event.category == EventCategory.polarAlignment) {
        _handlePolarAlignmentEvent(event.eventType, event.data);
      }
    });
  }

  void _handlePolarAlignmentEvent(String eventType, Map<String, dynamic> data) {
    if (!mounted) return;

    developer.log(
      '[PolarAlignmentStateNotifier] Received event: $eventType',
      name: 'PolarAlignmentStateNotifier',
      level: 500,
    );

    switch (eventType) {
      case 'PolarAlignment':
        _handleErrorUpdate(data);
        break;

      case 'PolarAlignmentStatus':
        _handleStatusUpdate(data);
        break;

      case 'PolarAlignmentImage':
        _handleImageUpdate(data);
        break;
    }
  }

  void _handleErrorUpdate(Map<String, dynamic> data) {
    final error = PolarAlignmentError.fromEventData(data);

    // Capture initial error when first entering adjustment phase
    if (state.phase == PolarAlignPhase.adjusting &&
        state.initialError == null) {
      _capturedInitialError = error;
      state = state.copyWith(currentError: error, initialError: error);
    } else {
      state = state.copyWith(currentError: error);
    }

    // Notify error history provider
    ref.read(polarAlignmentErrorHistoryProvider.notifier).addError(error);
  }

  void _handleStatusUpdate(Map<String, dynamic> data) {
    final statusStr = data['status'] as String? ?? '';
    final phaseStr = data['phase'] as String? ?? '';
    final point = data['point'] as int? ?? 0;

    final phase = _parsePhase(phaseStr);

    // When transitioning to adjusting phase, prepare to capture initial error
    if (phase == PolarAlignPhase.adjusting &&
        state.phase != PolarAlignPhase.adjusting) {
      // Reset initial error - it will be captured from next error event
      _capturedInitialError = null;
    }

    state = state.copyWith(
      phase: phase,
      currentPoint: point,
      statusMessage: statusStr,
      // Preserve initial error if we already have it
      initialError: _capturedInitialError ?? state.initialError,
    );
  }

  void _handleImageUpdate(Map<String, dynamic> data) {
    final imageData = data['image_data'];
    final width = data['width'] as int?;
    final height = data['height'] as int?;
    final solvedRa = data['solved_ra'] as double?;
    final solvedDec = data['solved_dec'] as double?;

    state = state.copyWith(
      imageData: imageData is List<int> ? Uint8List.fromList(imageData) : null,
      imageWidth: width,
      imageHeight: height,
      solvedRa: solvedRa,
      solvedDec: solvedDec,
    );
  }

  PolarAlignPhase _parsePhase(String phaseStr) {
    switch (phaseStr.toLowerCase()) {
      case 'measuring':
        return PolarAlignPhase.measuring;
      case 'adjusting':
        return PolarAlignPhase.adjusting;
      case 'complete':
        return PolarAlignPhase.complete;
      case 'error':
        return PolarAlignPhase.error;
      default:
        return PolarAlignPhase.idle;
    }
  }

  /// Start polar alignment with the given configuration
  Future<void> startAlignment(PolarAlignmentConfig config) async {
    final validationErrors = config.validate();
    if (validationErrors.isNotEmpty) {
      state = state.copyWith(
        phase: PolarAlignPhase.error,
        errorMessage: validationErrors.join(', '),
      );
      return;
    }

    // Reset state for new alignment
    _capturedInitialError = null;
    state = PolarAlignmentState(
      phase: PolarAlignPhase.measuring,
      statusMessage: 'Starting polar alignment...',
      config: config,
      startedAt: DateTime.now(),
    );

    try {
      final backend = ref.read(backendProvider);
      await backend.startPolarAlignment(
        exposureTime: config.exposureTime,
        stepSize: config.stepSize,
        binning: config.binning,
        isNorth: config.isNorth,
        manualRotation: config.manualRotation,
        rotateEast: config.rotateEast,
        gain: config.gain,
        offset: config.offset,
        solveTimeout: config.solveTimeout,
        startFromCurrent: config.startFromCurrent,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        phase: PolarAlignPhase.error,
        errorMessage: e.toString(),
        statusMessage: 'Failed to start polar alignment',
      );
    }
  }

  /// Start all-sky (Sharpcap-style) polar alignment.
  ///
  /// Unlike `startAlignment` (TPPA), this routine streams drift-based error
  /// updates directly into the adjusting phase — there is no measurement
  /// phase. We transition straight from `idle` to `adjusting` and the
  /// backend handles the rest. Errors arrive through the same
  /// `PolarAlignment` event stream.
  Future<void> startAllSkyAlignment(PolarAlignmentConfig config) async {
    final validationErrors = config.validate();
    if (validationErrors.isNotEmpty) {
      state = state.copyWith(
        phase: PolarAlignPhase.error,
        errorMessage: validationErrors.join(', '),
      );
      return;
    }

    _capturedInitialError = null;
    state = PolarAlignmentState(
      phase: PolarAlignPhase.adjusting,
      statusMessage: 'Starting all-sky polar alignment...',
      config: config,
      startedAt: DateTime.now(),
    );
  }

  /// Stop the polar alignment process
  Future<void> stopAlignment() async {
    if (!state.isRunning) return;

    try {
      final backend = ref.read(backendProvider);
      await backend.stopPolarAlignment();

      // If we have valid initial and current errors, save to history
      if (state.initialError != null && state.currentError != null) {
        await _saveResult();
      }

      if (!mounted) return;
      state = state.copyWith(
        phase: PolarAlignPhase.idle,
        statusMessage: 'Polar alignment stopped',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        phase: PolarAlignPhase.error,
        errorMessage: e.toString(),
        statusMessage: 'Failed to stop polar alignment',
      );
    }
  }

  /// Mark alignment as complete and save result
  Future<void> completeAlignment({bool autoCompleted = false}) async {
    if (state.initialError == null || state.currentError == null) {
      developer.log(
        '[PolarAlignmentStateNotifier] Cannot complete - missing error data',
        name: 'PolarAlignmentStateNotifier',
        level: 900,
      );
      return;
    }

    try {
      final backend = ref.read(backendProvider);
      await backend.stopPolarAlignment();
    } catch (e) {
      developer.log(
        '[PolarAlignmentStateNotifier] Error stopping alignment: $e',
        name: 'PolarAlignmentStateNotifier',
        level: 1000,
        error: e,
      );
    }

    await _saveResult(autoCompleted: autoCompleted);

    if (!mounted) return;
    state = state.copyWith(
      phase: PolarAlignPhase.complete,
      statusMessage: autoCompleted
          ? 'Polar alignment complete - threshold reached!'
          : 'Polar alignment complete',
    );
  }

  Future<void> _saveResult({bool autoCompleted = false}) async {
    if (state.initialError == null ||
        state.currentError == null ||
        state.config == null ||
        state.startedAt == null) {
      return;
    }

    // Get current equipment profile ID
    final profileId = ref.read(activeEquipmentProfileProvider)?.id;

    final result = PolarAlignmentResult(
      initialError: state.initialError!,
      finalError: state.currentError!,
      startedAt: state.startedAt!,
      completedAt: DateTime.now(),
      config: state.config!,
      autoCompleted: autoCompleted,
      equipmentProfileId: profileId,
    );

    // Save to database
    try {
      final db = ref.read(databaseProvider);
      await db.polarAlignmentHistoryDao.insertResult(result);
      developer.log(
        '[PolarAlignmentStateNotifier] Saved alignment result',
        name: 'PolarAlignmentStateNotifier',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[PolarAlignmentStateNotifier] Failed to save result: $e',
        name: 'PolarAlignmentStateNotifier',
        level: 1000,
        error: e,
      );
    }
  }

  /// Reset state to initial
  void reset() {
    _capturedInitialError = null;
    state = const PolarAlignmentState();
    ref.read(polarAlignmentErrorHistoryProvider.notifier).clear();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}

// =============================================================================
// POLAR ALIGNMENT CONFIGURATION PROVIDER (Persisted)
// =============================================================================

/// Provider for persisted polar alignment configuration
final polarAlignmentConfigProvider =
    StateNotifierProvider<PolarAlignmentConfigNotifier, PolarAlignmentConfig>((
      ref,
    ) {
      return PolarAlignmentConfigNotifier(ref);
    });

/// Notifier that persists polar alignment configuration to database
class PolarAlignmentConfigNotifier extends StateNotifier<PolarAlignmentConfig> {
  final Ref ref;
  static const String _settingsKey = 'polar_alignment_config';

  PolarAlignmentConfigNotifier(this.ref) : super(const PolarAlignmentConfig()) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final db = ref.read(databaseProvider);
      final setting = await db.settingsDao.getSetting(_settingsKey);
      if (setting != null && setting.isNotEmpty) {
        final json = jsonDecode(setting) as Map<String, dynamic>;
        state = PolarAlignmentConfig.fromJson(json);
        developer.log(
          '[PolarAlignmentConfigNotifier] Loaded config from DB',
          name: 'PolarAlignmentConfigNotifier',
          level: 800,
        );
      }
    } catch (e) {
      developer.log(
        '[PolarAlignmentConfigNotifier] Failed to load config: $e',
        name: 'PolarAlignmentConfigNotifier',
        level: 1000,
        error: e,
      );
    }
  }

  Future<void> updateConfig(PolarAlignmentConfig config) async {
    state = config;
    await _saveConfig();
  }

  Future<void> _saveConfig() async {
    try {
      final db = ref.read(databaseProvider);
      final json = jsonEncode(state.toJson());
      await db.settingsDao.setSetting(_settingsKey, json);
      developer.log(
        '[PolarAlignmentConfigNotifier] Saved config to DB',
        name: 'PolarAlignmentConfigNotifier',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[PolarAlignmentConfigNotifier] Failed to save config: $e',
        name: 'PolarAlignmentConfigNotifier',
        level: 1000,
        error: e,
      );
    }
  }

  /// Update a single field
  Future<void> setExposureTime(double value) async {
    await updateConfig(state.copyWith(exposureTime: value));
  }

  Future<void> setStepSize(double value) async {
    await updateConfig(state.copyWith(stepSize: value));
  }

  Future<void> setBinning(int value) async {
    await updateConfig(state.copyWith(binning: value));
  }

  Future<void> setIsNorth(bool value) async {
    await updateConfig(state.copyWith(isNorth: value));
  }

  Future<void> setManualRotation(bool value) async {
    await updateConfig(state.copyWith(manualRotation: value));
  }

  Future<void> setRotateEast(bool value) async {
    await updateConfig(state.copyWith(rotateEast: value));
  }

  Future<void> setSolveTimeout(double value) async {
    await updateConfig(state.copyWith(solveTimeout: value));
  }

  Future<void> setAutoCompleteThreshold(double value) async {
    await updateConfig(state.copyWith(autoCompleteThreshold: value));
  }

  Future<void> setStartFromCurrent(bool value) async {
    await updateConfig(state.copyWith(startFromCurrent: value));
  }

  Future<void> setGain(int? value) async {
    await updateConfig(state.copyWith(gain: value));
  }

  Future<void> setOffset(int? value) async {
    await updateConfig(state.copyWith(offset: value));
  }

  /// Reset to defaults
  Future<void> resetToDefaults() async {
    await updateConfig(const PolarAlignmentConfig());
  }

  /// Apply quick start preset
  Future<void> applyQuickStart() async {
    await updateConfig(PolarAlignmentConfig.quickStart());
  }

  /// Apply high precision preset
  Future<void> applyHighPrecision() async {
    await updateConfig(PolarAlignmentConfig.highPrecision());
  }
}

// =============================================================================
// POLAR ALIGNMENT UI STATE (Persisted — survives navigation & app restart)
// =============================================================================

/// Non-runtime UI preferences for the polar alignment screen.
///
/// Alignment phase and measurements live in [polarAlignmentStateProvider];
/// this holds mode, panel expansion, compact tab index, etc.
class PolarAlignmentUiState {
  const PolarAlignmentUiState({
    this.mode = PolarAlignmentMode.threePoint,
    this.showCommonSettings = false,
    this.showAdvancedSettings = false,
    this.showHistoryPanel = false,
    this.compactTabIndex = 1,
  });

  final PolarAlignmentMode mode;
  final bool showCommonSettings;
  final bool showAdvancedSettings;
  final bool showHistoryPanel;

  /// Selected tab in compact layout ([PolarAlignmentBodyLayout] < 700px).
  final int compactTabIndex;

  PolarAlignmentUiState copyWith({
    PolarAlignmentMode? mode,
    bool? showCommonSettings,
    bool? showAdvancedSettings,
    bool? showHistoryPanel,
    int? compactTabIndex,
  }) {
    return PolarAlignmentUiState(
      mode: mode ?? this.mode,
      showCommonSettings: showCommonSettings ?? this.showCommonSettings,
      showAdvancedSettings: showAdvancedSettings ?? this.showAdvancedSettings,
      showHistoryPanel: showHistoryPanel ?? this.showHistoryPanel,
      compactTabIndex: compactTabIndex ?? this.compactTabIndex,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'showCommonSettings': showCommonSettings,
    'showAdvancedSettings': showAdvancedSettings,
    'showHistoryPanel': showHistoryPanel,
    'compactTabIndex': compactTabIndex,
  };

  factory PolarAlignmentUiState.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    var mode = PolarAlignmentMode.threePoint;
    if (modeName != null) {
      for (final candidate in PolarAlignmentMode.values) {
        if (candidate.name == modeName) {
          mode = candidate;
          break;
        }
      }
    }

    final tabIndex = json['compactTabIndex'];
    return PolarAlignmentUiState(
      mode: mode,
      showCommonSettings: json['showCommonSettings'] as bool? ?? false,
      showAdvancedSettings: json['showAdvancedSettings'] as bool? ?? false,
      showHistoryPanel: json['showHistoryPanel'] as bool? ?? false,
      compactTabIndex: tabIndex is int ? tabIndex.clamp(0, 2) : 1,
    );
  }
}

/// Persisted UI state for the polar alignment screen.
final polarAlignmentUiStateProvider =
    StateNotifierProvider<PolarAlignmentUiStateNotifier, PolarAlignmentUiState>(
      (ref) {
        return PolarAlignmentUiStateNotifier(ref);
      },
    );

class PolarAlignmentUiStateNotifier
    extends StateNotifier<PolarAlignmentUiState> {
  PolarAlignmentUiStateNotifier(this.ref)
    : super(const PolarAlignmentUiState()) {
    _load();
  }

  final Ref ref;
  static const String _settingsKey = 'polar_alignment_ui';

  Future<void> _load() async {
    try {
      final db = ref.read(databaseProvider);
      final setting = await db.settingsDao.getSetting(_settingsKey);
      if (setting != null && setting.isNotEmpty) {
        final json = jsonDecode(setting) as Map<String, dynamic>;
        state = PolarAlignmentUiState.fromJson(json);
      }
    } catch (e) {
      developer.log(
        '[PolarAlignmentUiStateNotifier] Failed to load UI state: $e',
        name: 'PolarAlignmentUiStateNotifier',
        level: 1000,
        error: e,
      );
    }
  }

  Future<void> _persist() async {
    try {
      final db = ref.read(databaseProvider);
      await db.settingsDao.setSetting(_settingsKey, jsonEncode(state.toJson()));
    } catch (e) {
      developer.log(
        '[PolarAlignmentUiStateNotifier] Failed to save UI state: $e',
        name: 'PolarAlignmentUiStateNotifier',
        level: 1000,
        error: e,
      );
    }
  }

  Future<void> setMode(PolarAlignmentMode mode) async {
    state = state.copyWith(mode: mode);
    await _persist();
  }

  Future<void> setShowCommonSettings(bool value) async {
    state = state.copyWith(showCommonSettings: value);
    await _persist();
  }

  Future<void> setShowAdvancedSettings(bool value) async {
    state = state.copyWith(showAdvancedSettings: value);
    await _persist();
  }

  Future<void> toggleHistoryPanel() async {
    state = state.copyWith(showHistoryPanel: !state.showHistoryPanel);
    await _persist();
  }

  Future<void> setCompactTabIndex(int index) async {
    state = state.copyWith(compactTabIndex: index.clamp(0, 2));
    await _persist();
  }
}

// =============================================================================
// POLAR ALIGNMENT ERROR HISTORY PROVIDER (For Trend Visualization)
// =============================================================================

/// Maximum number of error samples to keep for visualization
const int _maxErrorHistorySamples = 60;

/// Provider for polar alignment error history (for real-time trend graph)
final polarAlignmentErrorHistoryProvider =
    StateNotifierProvider<
      PolarAlignmentErrorHistoryNotifier,
      List<PolarAlignmentError>
    >((ref) {
      return PolarAlignmentErrorHistoryNotifier();
    });

/// Notifier that maintains a rolling buffer of error measurements
class PolarAlignmentErrorHistoryNotifier
    extends StateNotifier<List<PolarAlignmentError>> {
  final Queue<PolarAlignmentError> _buffer = Queue<PolarAlignmentError>();

  PolarAlignmentErrorHistoryNotifier() : super([]);

  void addError(PolarAlignmentError error) {
    _buffer.add(error);
    if (_buffer.length > _maxErrorHistorySamples) {
      _buffer.removeFirst();
    }
    state = _buffer.toList();
  }

  void clear() {
    _buffer.clear();
    state = [];
  }
}

// =============================================================================
// POLAR ALIGNMENT HISTORY PROVIDER (Database History)
// =============================================================================

/// Provider for polar alignment history from database.
///
/// On a remote client (`NetworkBackend`) the slave never runs the local
/// alignment loop, so its `polar_alignment_history` table is always empty.
/// We branch to the host's `GET /api/polar-alignment-history`
/// (`fetchPolarAlignmentHistory()`) and map each
/// [RemotePolarAlignmentHistoryEntry] onto the local entry shape. The local
/// DAO path is unchanged for the host backend.
final polarAlignmentHistoryProvider =
    FutureProvider.family<List<PolarAlignmentHistoryEntry>, int?>((
      ref,
      profileId,
    ) async {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        final entries = await _fetchRemotePolarHistory(backend, profileId);
        return entries.take(20).toList();
      }
      final db = ref.watch(databaseProvider);
      return db.polarAlignmentHistoryDao.getHistoryForProfile(
        profileId,
        limit: 20,
      );
    });

/// Provider for the last alignment result
final lastPolarAlignmentProvider =
    FutureProvider.family<PolarAlignmentHistoryEntry?, int?>((
      ref,
      profileId,
    ) async {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        final entries = await _fetchRemotePolarHistory(backend, profileId);
        return entries.isEmpty ? null : entries.first;
      }
      final db = ref.watch(databaseProvider);
      return db.polarAlignmentHistoryDao.getLastAlignment(profileId);
    });

/// Provider for watching history changes (stream)
final polarAlignmentHistoryStreamProvider =
    StreamProvider.family<List<PolarAlignmentHistoryEntry>, int?>((
      ref,
      profileId,
    ) {
      final backend = ref.watch(backendProvider);
      if (backend is NetworkBackend) {
        return _pollRemotePolarHistory(backend, profileId);
      }
      final db = ref.watch(databaseProvider);
      return db.polarAlignmentHistoryDao.watchHistory(profileId);
    });

/// Polls the host's polar-alignment history, emitting only on change (mirrors
/// the `_pollRemote` change-guard in `database_provider.dart`).
Stream<List<PolarAlignmentHistoryEntry>> _pollRemotePolarHistory(
  NetworkBackend backend,
  int? profileId, {
  Duration interval = const Duration(seconds: 10),
}) async* {
  var last = await _fetchRemotePolarHistory(backend, profileId);
  yield last;
  while (true) {
    await Future<void>.delayed(interval);
    final next = await _fetchRemotePolarHistory(backend, profileId);
    if (!listEquals(last, next)) {
      last = next;
      yield next;
    }
  }
}

Future<List<PolarAlignmentHistoryEntry>> _fetchRemotePolarHistory(
  NetworkBackend backend,
  int? profileId,
) async {
  final page = await backend.fetchPolarAlignmentHistory(
    equipmentProfileId: profileId,
  );
  final mapped = page.items.map(_polarEntryFromRemote).toList()
    // Newest-first so `.first` is the most recent alignment.
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  return mapped;
}

PolarAlignmentHistoryEntry _polarEntryFromRemote(
  RemotePolarAlignmentHistoryEntry row,
) {
  return PolarAlignmentHistoryEntry(
    id: row.id,
    equipmentProfileId: row.equipmentProfileId,
    initialAzimuthError: row.initialAzimuthError ?? 0.0,
    initialAltitudeError: row.initialAltitudeError ?? 0.0,
    initialTotalError: row.initialTotalError ?? 0.0,
    finalAzimuthError: row.finalAzimuthError ?? 0.0,
    finalAltitudeError: row.finalAltitudeError ?? 0.0,
    finalTotalError: row.finalTotalError ?? 0.0,
    startedAt: row.startedAt,
    completedAt: row.completedAt,
    autoCompleted: row.autoCompleted,
    isNorth: row.isNorth,
    configJson: row.configJson ?? '{}',
  );
}

// =============================================================================
// POLAR ALIGNMENT CONTROLLER (Actions)
// =============================================================================

/// Controller provider for polar alignment actions
final polarAlignmentControllerProvider = Provider<PolarAlignmentController>((
  ref,
) {
  return PolarAlignmentController(ref);
});

/// Controller for polar alignment actions
class PolarAlignmentController {
  final Ref ref;

  PolarAlignmentController(this.ref);

  /// Start polar alignment with current configuration
  Future<void> start() async {
    final config = ref.read(polarAlignmentConfigProvider);
    await ref.read(polarAlignmentStateProvider.notifier).startAlignment(config);
  }

  /// Start polar alignment with a specific configuration
  Future<void> startWithConfig(PolarAlignmentConfig config) async {
    await ref.read(polarAlignmentStateProvider.notifier).startAlignment(config);
  }

  /// Stop polar alignment
  Future<void> stop() async {
    await ref.read(polarAlignmentStateProvider.notifier).stopAlignment();
  }

  /// Complete polar alignment (manual completion)
  Future<void> complete() async {
    await ref
        .read(polarAlignmentStateProvider.notifier)
        .completeAlignment(autoCompleted: false);
  }

  /// Reset state
  void reset() {
    ref.read(polarAlignmentStateProvider.notifier).reset();
  }

  /// Check if auto-complete threshold is reached and complete if so
  void checkAutoComplete() {
    final state = ref.read(polarAlignmentStateProvider);
    final config = ref.read(polarAlignmentConfigProvider);

    if (state.phase == PolarAlignPhase.adjusting &&
        state.currentError != null &&
        state.currentError!.totalError <= config.autoCompleteThreshold) {
      ref
          .read(polarAlignmentStateProvider.notifier)
          .completeAlignment(autoCompleted: true);
    }
  }
}
