import 'dart:typed_data';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'phd2_models.freezed.dart';
part 'phd2_models.g.dart';

/// PHD2 guiding state
enum Phd2GuidingState {
  disconnected,
  connected,
  calibrating,
  guiding,
  looping,
  paused,
  settling,
  lostLock,
}

/// Extension for Phd2GuidingState display
extension Phd2GuidingStateExtension on Phd2GuidingState {
  String get displayName {
    switch (this) {
      case Phd2GuidingState.disconnected:
        return 'Disconnected';
      case Phd2GuidingState.connected:
        return 'Connected';
      case Phd2GuidingState.calibrating:
        return 'Calibrating';
      case Phd2GuidingState.guiding:
        return 'Guiding';
      case Phd2GuidingState.looping:
        return 'Looping';
      case Phd2GuidingState.paused:
        return 'Paused';
      case Phd2GuidingState.settling:
        return 'Settling';
      case Phd2GuidingState.lostLock:
        return 'Lost Lock';
    }
  }

  bool get isActive =>
      this == Phd2GuidingState.guiding ||
      this == Phd2GuidingState.calibrating ||
      this == Phd2GuidingState.looping ||
      this == Phd2GuidingState.settling;
}

/// Star image data from PHD2's get_star_image API
@freezed
class Phd2StarImage with _$Phd2StarImage {
  const factory Phd2StarImage({
    /// Frame number
    required int frame,

    /// Image width in pixels
    required int width,

    /// Image height in pixels
    required int height,

    /// Star centroid X position within the subframe
    required double starX,

    /// Star centroid Y position within the subframe
    required double starY,

    /// Raw pixel data (16-bit grayscale, row-major order)
    /// Note: This is stored as Uint8List but represents 16-bit values
    @Uint8ListConverter() required Uint8List pixels,
  }) = _Phd2StarImage;

  factory Phd2StarImage.fromJson(Map<String, dynamic> json) =>
      _$Phd2StarImageFromJson(json);

  /// Create an empty/placeholder star image
  factory Phd2StarImage.empty() => Phd2StarImage(
        frame: 0,
        width: 0,
        height: 0,
        starX: 0,
        starY: 0,
        pixels: Uint8List(0),
      );
}

/// PHD2 Brain algorithm parameter
@freezed
class Phd2AlgoParam with _$Phd2AlgoParam {
  const factory Phd2AlgoParam({
    /// Parameter name (e.g., "Aggressiveness", "Hysteresis")
    required String name,

    /// Parameter value
    required double value,
  }) = _Phd2AlgoParam;

  factory Phd2AlgoParam.fromJson(Map<String, dynamic> json) =>
      _$Phd2AlgoParamFromJson(json);
}

/// Collection of PHD2 Brain parameters for both axes
@freezed
class Phd2BrainParams with _$Phd2BrainParams {
  const factory Phd2BrainParams({
    /// RA axis parameter names
    required List<String> raParamNames,

    /// Dec axis parameter names
    required List<String> decParamNames,

    /// RA axis parameters (name -> value)
    required Map<String, double> raParams,

    /// Dec axis parameters (name -> value)
    required Map<String, double> decParams,
  }) = _Phd2BrainParams;

  factory Phd2BrainParams.fromJson(Map<String, dynamic> json) =>
      _$Phd2BrainParamsFromJson(json);

  /// Create empty brain params
  factory Phd2BrainParams.empty() => const Phd2BrainParams(
        raParamNames: [],
        decParamNames: [],
        raParams: {},
        decParams: {},
      );
}

/// Guide error point for target display history
@freezed
class GuideErrorPoint with _$GuideErrorPoint {
  const factory GuideErrorPoint({
    /// RA error in arcseconds
    required double raError,

    /// Dec error in arcseconds
    required double decError,

    /// Timestamp when this error was recorded
    required DateTime timestamp,
  }) = _GuideErrorPoint;

  factory GuideErrorPoint.fromJson(Map<String, dynamic> json) =>
      _$GuideErrorPointFromJson(json);
}

/// PHD2 guide statistics snapshot
@freezed
class Phd2GuideStats with _$Phd2GuideStats {
  const factory Phd2GuideStats({
    /// RMS error in RA (arcseconds)
    @Default(0.0) double rmsRa,

    /// RMS error in Dec (arcseconds)
    @Default(0.0) double rmsDec,

    /// Total RMS error (arcseconds)
    @Default(0.0) double rmsTotal,

    /// Peak RA error (arcseconds)
    @Default(0.0) double peakRa,

    /// Peak Dec error (arcseconds)
    @Default(0.0) double peakDec,

    /// SNR of guide star
    @Default(0.0) double snr,

    /// Star mass (brightness)
    @Default(0.0) double starMass,

    /// HFD (Half Flux Diameter)
    @Default(0.0) double hfd,

    /// Guide star X position
    @Default(0.0) double starX,

    /// Guide star Y position
    @Default(0.0) double starY,

    /// Pixel scale (arcsec/pixel)
    @Default(0.0) double pixelScale,

    /// Number of guide frames
    @Default(0) int frameCount,
  }) = _Phd2GuideStats;

  factory Phd2GuideStats.fromJson(Map<String, dynamic> json) =>
      _$Phd2GuideStatsFromJson(json);
}

/// PHD2 calibration data
@freezed
class Phd2CalibrationData with _$Phd2CalibrationData {
  const factory Phd2CalibrationData({
    /// Whether calibration is complete
    @Default(false) bool isCalibrated,

    /// Calibration timestamp
    DateTime? calibratedAt,

    /// RA calibration rate (pixels/ms)
    double? raRate,

    /// Dec calibration rate (pixels/ms)
    double? decRate,

    /// Camera rotation angle (degrees)
    double? rotationAngle,

    /// Dec guide mode ("Auto", "North", "South", "Off")
    String? decGuideMode,
  }) = _Phd2CalibrationData;

  factory Phd2CalibrationData.fromJson(Map<String, dynamic> json) =>
      _$Phd2CalibrationDataFromJson(json);
}

/// Custom JSON converter for Uint8List
class Uint8ListConverter implements JsonConverter<Uint8List, List<int>> {
  const Uint8ListConverter();

  @override
  Uint8List fromJson(List<int> json) => Uint8List.fromList(json);

  @override
  List<int> toJson(Uint8List object) => object.toList();
}
