import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;

import '../../models/defect_map.dart';

/// Service for the defect-map / bad-pixel cosmetic correction pipeline.
///
/// Wraps the native bridge calls. The service is stateless except for
/// the wrapped bridge instance, so it is cheap to construct from a
/// Riverpod provider.
class DefectMapService {
  /// Build a defect map for `cameraId` from the supplied dark / bias
  /// frame paths. At least
  /// [minRequiredDarkFrames] frames are required for the consistency
  /// check; supplying fewer is an error rather than a silent fall-back.
  Future<DefectMapStatus> build({
    required String cameraId,
    required List<String> darkFramePaths,
    required double sensorTemperatureCelsius,
  }) async {
    final result = await bridge.apiDefectMapBuild(
      cameraId: cameraId,
      darkFramePaths: darkFramePaths,
      sensorTemperatureCelsius: sensorTemperatureCelsius,
    );
    return _fromBridge(result);
  }

  /// Toggle whether the defect map for `cameraId` is applied to lights
  /// at capture time.
  Future<void> apply({
    required String cameraId,
    required bool applyDuringCapture,
  }) {
    return bridge.apiDefectMapApply(
      cameraId: cameraId,
      applyDuringCapture: applyDuringCapture,
    );
  }

  /// Remove the stored defect map for `cameraId` at the sensor size and
  /// temperature bucket implied by the inputs, and reset the apply flag.
  Future<void> clear({
    required String cameraId,
    required int width,
    required int height,
    required double sensorTemperatureCelsius,
  }) {
    return bridge.apiDefectMapClear(
      cameraId: cameraId,
      width: width,
      height: height,
      sensorTemperatureCelsius: sensorTemperatureCelsius,
    );
  }

  /// Look up the status of the stored defect map. Returns null if no
  /// map has been built yet for the supplied camera/size/bucket.
  Future<DefectMapStatus?> getStatus({
    required String cameraId,
    required int width,
    required int height,
    required double sensorTemperatureCelsius,
  }) async {
    final raw = await bridge.apiDefectMapGetStatus(
      cameraId: cameraId,
      width: width,
      height: height,
      sensorTemperatureCelsius: sensorTemperatureCelsius,
    );
    if (raw == null) return null;
    return _fromBridge(raw);
  }

  /// Minimum dark frame count the bridge requires before it will run
  /// the defect detection. Mirrored from the Rust constant.
  static const int minRequiredDarkFrames = 5;

  DefectMapStatus _fromBridge(bridge.ApiDefectMapStatus s) => DefectMapStatus(
        cameraId: s.cameraId,
        width: s.width,
        height: s.height,
        temperatureBucket:
            DefectMapTemperatureBucket(s.temperatureBucketDecicelsius),
        defectivePixelCount: s.defectivePixelCount,
        lastRebuiltUnixSeconds: s.lastRebuiltUnixSeconds,
        applyDuringCapture: s.applyDuringCapture,
        storedOnDisk: s.storedOnDisk,
      );
}
