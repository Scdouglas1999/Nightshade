import 'dart:math' as math;

import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Sky projection mode for planetarium v2 (maps to [SkyProjectionDto]).
enum PlanetariumSkyProjection {
  stereographic,
  orthographic,
  azimuthalEquidistant,
}

/// Dart-side view pose (RA hours, Dec/FOV/roll degrees) for UI and providers.
class ViewPoseState {
  const ViewPoseState({
    this.centerRaHours = 0,
    this.centerDecDegrees = 90,
    this.fieldOfViewDegrees = 90,
    this.rotationDegrees = 0,
    this.projection = PlanetariumSkyProjection.stereographic,
  });

  /// Right ascension of the view center in hours (0–24).
  final double centerRaHours;

  /// Declination of the view center in degrees (−90–90).
  final double centerDecDegrees;

  /// Field of view across the shorter axis in degrees.
  final double fieldOfViewDegrees;

  /// Roll about the view axis in degrees.
  final double rotationDegrees;

  final PlanetariumSkyProjection projection;

  ViewPoseState copyWith({
    double? centerRaHours,
    double? centerDecDegrees,
    double? fieldOfViewDegrees,
    double? rotationDegrees,
    PlanetariumSkyProjection? projection,
  }) {
    return ViewPoseState(
      centerRaHours: centerRaHours ?? this.centerRaHours,
      centerDecDegrees: centerDecDegrees ?? this.centerDecDegrees,
      fieldOfViewDegrees: fieldOfViewDegrees ?? this.fieldOfViewDegrees,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      projection: projection ?? this.projection,
    );
  }

  ViewPoseDto toDto() {
    return ViewPoseDto(
      raRad: centerRaHours * math.pi / 12,
      decRad: centerDecDegrees * math.pi / 180,
      fovRad: fieldOfViewDegrees * math.pi / 180,
      rollRad: rotationDegrees * math.pi / 180,
      projection: switch (projection) {
        PlanetariumSkyProjection.stereographic =>
          SkyProjectionDto.stereographic,
        PlanetariumSkyProjection.orthographic => SkyProjectionDto.orthographic,
        PlanetariumSkyProjection.azimuthalEquidistant =>
          SkyProjectionDto.azimuthalEquidistant,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewPoseState &&
          centerRaHours == other.centerRaHours &&
          centerDecDegrees == other.centerDecDegrees &&
          fieldOfViewDegrees == other.fieldOfViewDegrees &&
          rotationDegrees == other.rotationDegrees &&
          projection == other.projection;

  @override
  int get hashCode => Object.hash(
        centerRaHours,
        centerDecDegrees,
        fieldOfViewDegrees,
        rotationDegrees,
        projection,
      );
}
