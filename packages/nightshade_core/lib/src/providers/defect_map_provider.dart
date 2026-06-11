import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/defect_map.dart';
import '../services/calibration/defect_map_service.dart';
import 'database_provider.dart';

/// Service provider for [DefectMapService]. Stateless wrapper.
final defectMapServiceProvider = Provider<DefectMapService>((ref) {
  return DefectMapService();
});

/// Query parameters for looking up a stored defect map.
class DefectMapQuery {
  final String cameraId;
  final int width;
  final int height;
  final double sensorTemperatureCelsius;

  const DefectMapQuery({
    required this.cameraId,
    required this.width,
    required this.height,
    required this.sensorTemperatureCelsius,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefectMapQuery &&
          runtimeType == other.runtimeType &&
          cameraId == other.cameraId &&
          width == other.width &&
          height == other.height &&
          sensorTemperatureCelsius == other.sensorTemperatureCelsius;

  @override
  int get hashCode =>
      Object.hash(cameraId, width, height, sensorTemperatureCelsius);
}

/// Status of the defect map for a given (camera, sensor, temperature)
/// tuple. Null means no map has been built yet for that combination.
final defectMapStatusProvider =
    FutureProvider.family<DefectMapStatus?, DefectMapQuery>((ref, query) async {
      final service = ref.watch(defectMapServiceProvider);
      return service.getStatus(
        cameraId: query.cameraId,
        width: query.width,
        height: query.height,
        sensorTemperatureCelsius: query.sensorTemperatureCelsius,
      );
    });

/// UI state for the imaging-screen calibration section.
///
/// Tracks the in-flight operation (build/clear) so the panel can disable
/// buttons and show progress, and any error from the most recent
/// operation. Errors are surfaced as state rather than swallowed.
class DefectMapUiState {
  final bool isBuilding;
  final bool isClearing;
  final String? statusMessage;
  final String? errorMessage;

  const DefectMapUiState({
    this.isBuilding = false,
    this.isClearing = false,
    this.statusMessage,
    this.errorMessage,
  });

  DefectMapUiState copyWith({
    bool? isBuilding,
    bool? isClearing,
    String? statusMessage,
    String? errorMessage,
  }) {
    return DefectMapUiState(
      isBuilding: isBuilding ?? this.isBuilding,
      isClearing: isClearing ?? this.isClearing,
      statusMessage: statusMessage,
      errorMessage: errorMessage,
    );
  }
}

class DefectMapNotifier extends StateNotifier<DefectMapUiState> {
  final Ref ref;

  DefectMapNotifier(this.ref) : super(const DefectMapUiState());

  DefectMapService get _service => ref.read(defectMapServiceProvider);

  /// Build a new defect map from the supplied dark-frame paths.
  Future<void> build({
    required String cameraId,
    required List<String> darkFramePaths,
    required double sensorTemperatureCelsius,
  }) async {
    state = state.copyWith(
      isBuilding: true,
      statusMessage:
          'Scanning ${darkFramePaths.length} dark frames for defective pixels...',
      errorMessage: null,
    );
    try {
      final status = await _service.build(
        cameraId: cameraId,
        darkFramePaths: darkFramePaths,
        sensorTemperatureCelsius: sensorTemperatureCelsius,
      );
      state = state.copyWith(
        isBuilding: false,
        statusMessage:
            'Defect map built: ${status.defectivePixelCount} defective pixels '
            'flagged at ${status.temperatureBucket.label}.',
      );
      ref.invalidate(defectMapStatusProvider);
    } catch (e) {
      state = state.copyWith(
        isBuilding: false,
        errorMessage: 'Failed to build defect map: $e',
      );
    }
  }

  /// Enable or disable defect-map application during capture.
  ///
  /// Persists the user preference AND, when the caller supplies the
  /// camera dimensions + temperature, pushes the live state into the
  /// running sequencer so per-frame correction starts (or stops) at
  /// the next exposure. Callers that don't have the dimensions yet
  /// (e.g. a settings-screen-level toggle with no camera connected)
  /// can omit those parameters; the sequencer is then updated on the
  /// next camera connect via [pushCurrentSettingsToSequencer].
  Future<void> setApplyDuringCapture({
    required String cameraId,
    required bool apply,
    int? width,
    int? height,
    double? sensorTemperatureCelsius,
  }) async {
    try {
      await _service.apply(cameraId: cameraId, applyDuringCapture: apply);
      // Push to sequencer if the caller knew the
      // dimensions + temp. Failure here is surfaced separately from
      // the persisted-preference success so the user sees what went
      // wrong (e.g. no map exists for the current temperature bucket).
      if (width != null && height != null && sensorTemperatureCelsius != null) {
        final settings = ref.read(defectMapSettingsProvider);
        await _service.applyToSequencer(
          cameraId: cameraId,
          width: width,
          height: height,
          sensorTemperatureCelsius: sensorTemperatureCelsius,
          enabled: apply,
          method: settings.method,
          kernel: settings.kernel,
          saveOriginal: settings.saveOriginal,
        );
      }
      state = state.copyWith(
        statusMessage: apply
            ? 'Defect map will be applied to lights at capture.'
            : 'Defect map will not be applied to lights at capture.',
        errorMessage: null,
      );
      ref.invalidate(defectMapStatusProvider);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to update defect-map toggle: $e',
      );
    }
  }

  /// Push the user's current defect-map settings to the running
  /// sequencer. Used by camera-connect notifiers and settings UI
  /// when the user changes kernel / method without flipping the
  /// apply switch — those changes still need to propagate down so
  /// the next captured frame uses the new replacement strategy.
  Future<void> pushCurrentSettingsToSequencer({
    required String cameraId,
    required int width,
    required int height,
    required double sensorTemperatureCelsius,
    required bool enabled,
  }) async {
    try {
      final settings = ref.read(defectMapSettingsProvider);
      await _service.applyToSequencer(
        cameraId: cameraId,
        width: width,
        height: height,
        sensorTemperatureCelsius: sensorTemperatureCelsius,
        enabled: enabled,
        method: settings.method,
        kernel: settings.kernel,
        saveOriginal: settings.saveOriginal,
      );
      state = state.copyWith(errorMessage: null);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Failed to push defect-map settings to sequencer: $e',
      );
    }
  }

  /// Delete the stored defect map for this camera at this size and
  /// temperature bucket.
  Future<void> clear({
    required String cameraId,
    required int width,
    required int height,
    required double sensorTemperatureCelsius,
  }) async {
    state = state.copyWith(
      isClearing: true,
      statusMessage: 'Clearing defect map...',
      errorMessage: null,
    );
    try {
      await _service.clear(
        cameraId: cameraId,
        width: width,
        height: height,
        sensorTemperatureCelsius: sensorTemperatureCelsius,
      );
      state = state.copyWith(
        isClearing: false,
        statusMessage: 'Defect map cleared.',
      );
      ref.invalidate(defectMapStatusProvider);
    } catch (e) {
      state = state.copyWith(
        isClearing: false,
        errorMessage: 'Failed to clear defect map: $e',
      );
    }
  }

  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  void clearStatus() {
    state = state.copyWith(statusMessage: null);
  }
}

/// StateNotifier provider for the calibration section's transient UI
/// state (in-flight build/clear, status / error messages).
final defectMapNotifierProvider =
    StateNotifierProvider<DefectMapNotifier, DefectMapUiState>((ref) {
      return DefectMapNotifier(ref);
    });

// ===========================================================================
// Per-camera defect-map auto-apply settings.
//
// These are NOT part of the legacy app_settings freezed model because they
// don't need codegen — they're stored as plain key/value rows in the
// `app_settings` table via the same `settingsDaoProvider` the calibration
// section already uses. The dedicated provider centralises the keys + the
// load/save logic so the settings UI doesn't have to know about the storage
// layout.
// ===========================================================================

/// User-facing settings for per-frame defect-map application during
/// capture. Independent of whether a map exists on disk — those are
/// authoritative state queried via [defectMapStatusProvider].
class DefectMapSettings {
  /// When true, the sequencer will apply the defect map to every
  /// captured light frame automatically (assuming one exists for the
  /// connected camera at the current temperature bucket). Default
  /// false — opt-in to avoid surprise corrections.
  final bool autoApply;

  /// Replacement method used to fill defective pixels.
  final DefectMapMethod method;

  /// Kernel diameter for the neighbour search.
  final DefectMapKernelSize kernel;

  /// When true, the original uncorrected frame is also saved to a
  /// `Raw/` sibling directory next to the canonical save. Default
  /// false (the corrected frame replaces the raw one).
  final bool saveOriginal;

  const DefectMapSettings({
    this.autoApply = false,
    this.method = DefectMapMethod.median,
    this.kernel = DefectMapKernelSize.k3,
    this.saveOriginal = false,
  });

  DefectMapSettings copyWith({
    bool? autoApply,
    DefectMapMethod? method,
    DefectMapKernelSize? kernel,
    bool? saveOriginal,
  }) {
    return DefectMapSettings(
      autoApply: autoApply ?? this.autoApply,
      method: method ?? this.method,
      kernel: kernel ?? this.kernel,
      saveOriginal: saveOriginal ?? this.saveOriginal,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefectMapSettings &&
          runtimeType == other.runtimeType &&
          autoApply == other.autoApply &&
          method == other.method &&
          kernel == other.kernel &&
          saveOriginal == other.saveOriginal;

  @override
  int get hashCode => Object.hash(autoApply, method, kernel, saveOriginal);
}

/// Settings keys used by the defect-map subsystem. Centralised here so
/// the test suite + the bridge can match against the same strings.
class DefectMapSettingsKeys {
  static const String autoApply = 'defectMap.autoApply';
  static const String method = 'defectMap.method';
  static const String kernel = 'defectMap.kernelDiameter';
  static const String saveOriginal = 'defectMap.saveOriginal';

  DefectMapSettingsKeys._();
}

/// StateNotifier managing [DefectMapSettings]. Loads from the
/// `app_settings` table on construction; persists each setter.
class DefectMapSettingsNotifier extends StateNotifier<DefectMapSettings> {
  final Ref _ref;
  ProviderSubscription? _settingsSub;

  DefectMapSettingsNotifier(this._ref) : super(const DefectMapSettings()) {
    _settingsSub = _ref.listen<AsyncValue<Map<String, String>>>(
      allSettingsProvider,
      (_, next) => next.whenData(_applyLoaded),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _settingsSub?.close();
    super.dispose();
  }

  void _applyLoaded(Map<String, String> kv) {
    state = DefectMapSettings(
      autoApply: kv[DefectMapSettingsKeys.autoApply] == 'true',
      method: DefectMapMethod.fromWire(kv[DefectMapSettingsKeys.method]),
      kernel: DefectMapKernelSize.fromDiameter(
        int.tryParse(kv[DefectMapSettingsKeys.kernel] ?? '') ?? 3,
      ),
      saveOriginal: kv[DefectMapSettingsKeys.saveOriginal] == 'true',
    );
  }

  Future<void> setAutoApply(bool value) async {
    state = state.copyWith(autoApply: value);
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(DefectMapSettingsKeys.autoApply, value.toString());
  }

  Future<void> setMethod(DefectMapMethod value) async {
    state = state.copyWith(method: value);
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(DefectMapSettingsKeys.method, value.wireValue);
  }

  Future<void> setKernel(DefectMapKernelSize value) async {
    state = state.copyWith(kernel: value);
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(
      DefectMapSettingsKeys.kernel,
      value.diameter.toString(),
    );
  }

  Future<void> setSaveOriginal(bool value) async {
    state = state.copyWith(saveOriginal: value);
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(DefectMapSettingsKeys.saveOriginal, value.toString());
  }
}

/// Provider for the defect-map settings notifier.
final defectMapSettingsProvider =
    StateNotifierProvider<DefectMapSettingsNotifier, DefectMapSettings>((ref) {
      return DefectMapSettingsNotifier(ref);
    });
