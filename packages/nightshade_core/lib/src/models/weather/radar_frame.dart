import 'package:freezed_annotation/freezed_annotation.dart';

part 'radar_frame.freezed.dart';
part 'radar_frame.g.dart';

/// Type of radar tile service
enum RadarTileType {
  /// Standard XYZ slippy map tiles (used by RainViewer, OpenStreetMap, etc.)
  /// URL format: .../256/{z}/{x}/{y}.png
  xyz,

  /// WMS (Web Map Service) tiles (used by NOAA NEXRAD, etc.)
  /// Uses bounding box parameters instead of tile coordinates
  wms,
}

/// Represents a single radar frame in the animation sequence
@freezed
class RadarFrame with _$RadarFrame {
  const factory RadarFrame({
    /// When this radar frame was captured
    required DateTime timestamp,

    /// URL template for map tiles
    /// - For XYZ: template with {z}/{x}/{y} tokens
    /// - For WMS: base URL (without bbox parameter)
    required String tileUrlTemplate,

    /// Geographic bounds - northern boundary
    required double north,

    /// Geographic bounds - southern boundary
    required double south,

    /// Geographic bounds - eastern boundary
    required double east,

    /// Geographic bounds - western boundary
    required double west,

    /// Opacity for animation blending (0.0-1.0)
    @Default(1.0) double opacity,

    /// True if this is a forecast frame vs historical
    @Default(false) bool isForecast,

    /// Type of tile service (XYZ or WMS)
    @Default(RadarTileType.xyz) RadarTileType tileType,

    /// WMS layer name(s) - only used when tileType is wms
    String? wmsLayers,

    /// Additional WMS parameters (e.g., time, styles) - only used when tileType is wms
    Map<String, String>? wmsAdditionalOptions,
  }) = _RadarFrame;

  factory RadarFrame.fromJson(Map<String, dynamic> json) =>
      _$RadarFrameFromJson(json);
}
