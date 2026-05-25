import 'dart:math' as math;
import 'dart:ui';

import 'package:nightshade_bridge/nightshade_bridge.dart';

import '../models/celestial_coordinate.dart';

const double _deg2rad = math.pi / 180;
const double _rad2deg = 180 / math.pi;

/// Gnomonic/stereographic projection from celestial coordinates to screen space.
///
/// Ported from v1 [`SkyRenderer._celestialToScreen`] for constellation art overlays.
Offset? celestialToScreen({
  required CelestialCoordinate coord,
  required ViewPoseDto viewPose,
  required Offset center,
  required double scale,
}) {
  final raDeg = coord.ra * 15;
  final decDeg = coord.dec;

  final centerRaDeg = viewPose.raRad * 12 / math.pi;
  final centerDecDeg = viewPose.decRad * 180 / math.pi;

  final ra1 = centerRaDeg * _deg2rad;
  final dec1 = centerDecDeg * _deg2rad;
  final ra2 = raDeg * _deg2rad;
  final dec2 = decDeg * _deg2rad;

  final cosc = math.sin(dec1) * math.sin(dec2) +
      math.cos(dec1) * math.cos(dec2) * math.cos(ra2 - ra1);

  if (cosc < 0.01) {
    return null;
  }

  double x;
  double y;

  switch (viewPose.projection) {
    case SkyProjectionDto.stereographic:
      final k = 2 / (1 + cosc);
      x = k * math.cos(dec2) * math.sin(ra2 - ra1);
      y = k *
          (math.cos(dec1) * math.sin(dec2) -
              math.sin(dec1) * math.cos(dec2) * math.cos(ra2 - ra1));
    case SkyProjectionDto.orthographic:
      x = math.cos(dec2) * math.sin(ra2 - ra1);
      y = math.cos(dec1) * math.sin(dec2) -
          math.sin(dec1) * math.cos(dec2) * math.cos(ra2 - ra1);
    case SkyProjectionDto.azimuthalEquidistant:
      final c = math.acos(cosc);
      if (c < 0.0001) {
        x = 0;
        y = 0;
      } else {
        final k = c / math.sin(c);
        x = k * math.cos(dec2) * math.sin(ra2 - ra1);
        y = k *
            (math.cos(dec1) * math.sin(dec2) -
                math.sin(dec1) * math.cos(dec2) * math.cos(ra2 - ra1));
      }
  }

  final rotRad = viewPose.rollRad;
  final xRot = x * math.cos(rotRad) - y * math.sin(rotRad);
  final yRot = x * math.sin(rotRad) + y * math.cos(rotRad);

  return Offset(
    center.dx - xRot * scale * _rad2deg,
    center.dy - yRot * scale * _rad2deg,
  );
}

/// Whether [offset] is near the visible canvas (with margin).
bool isOffsetNearCanvas(Offset offset, Size size) {
  return offset.dx >= -50 &&
      offset.dx <= size.width + 50 &&
      offset.dy >= -50 &&
      offset.dy <= size.height + 50;
}

/// Scale factor matching v1 sky renderer: pixels per degree from FOV.
double skyProjectionScale(Size size, ViewPoseDto viewPose) {
  final fovDegrees = viewPose.fovRad * 180 / math.pi;
  return math.min(size.width, size.height) / 2 / (fovDegrees / 2);
}
