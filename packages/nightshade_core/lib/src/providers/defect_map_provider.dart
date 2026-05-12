import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/defect_map.dart';
import '../services/calibration/defect_map_service.dart';

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
  int get hashCode => Object.hash(
        cameraId,
        width,
        height,
        sensorTemperatureCelsius,
      );
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
  Future<void> setApplyDuringCapture({
    required String cameraId,
    required bool apply,
  }) async {
    try {
      await _service.apply(
        cameraId: cameraId,
        applyDuringCapture: apply,
      );
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
