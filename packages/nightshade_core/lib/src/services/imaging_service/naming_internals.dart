part of '../imaging_service.dart';

extension _ImagingServiceNamingInternals on ImagingService {
  /// Build the substitution map used by [expandNamingPattern]. Pulled out of
  /// [_generateImageFilePath] so the provider-bound pieces (camera/mount
  /// name, sensor temperature) are read in one place. Delegates the pure
  /// timestamp/exposure formatting to [buildTimestampSubstitutions] so unit
  /// tests can exercise the date convention without a `ProviderContainer`.
  Map<String, String> _buildPatternSubstitutions({
    required ExposureSettings exposureSettings,
    String? targetName,
    required int frameNumber,
    required DateTime timestamp,
  }) {
    // $TEMP, $CAMERA, $TELESCOPE are best-effort: equipment may not be
    // connected when this runs (e.g. headless tests). Fall back to the
    // documented defaults from the Rust naming.rs so cross-language users see
    // consistent path strings.
    String camera = 'Camera';
    String tempStr = '0C';
    try {
      final cameraState = _ref.read(cameraStateProvider);
      if (cameraState.deviceName != null &&
          cameraState.deviceName!.isNotEmpty) {
        camera = cameraState.deviceName!;
      }
      final temp = cameraState.temperature;
      if (temp != null) {
        tempStr = '${temp.toStringAsFixed(0)}C';
      }
    } catch (_) {
      // Provider not available (e.g. minimal test container) — use defaults.
    }

    String telescope = 'Telescope';
    try {
      final mountState = _ref.read(mountStateProvider);
      if (mountState.deviceName != null && mountState.deviceName!.isNotEmpty) {
        telescope = mountState.deviceName!;
      }
    } catch (_) {
      // Provider not available — use default.
    }

    return ImagingService.buildTimestampSubstitutions(
      exposureSettings: exposureSettings,
      targetName: targetName,
      frameNumber: frameNumber,
      timestamp: timestamp,
      camera: camera,
      telescope: telescope,
      tempStr: tempStr,
    );
  }
}
