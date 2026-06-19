import 'package:flutter/material.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    as planetarium_v1;

/// Renders the planetarium sky using the v1 `nightshade_planetarium` engine.
///
/// This is the single go-forward renderer. Subclasses ([TargetPickerSkyView],
/// [FullScreenSkyView]) and call sites ([MosaicPlannerSkyView]) inherit this
/// stable surface; the widget simply forwards to
/// [planetarium_v1.InteractiveSkyView].
class AdaptiveInteractiveSkyView extends StatelessWidget {
  const AdaptiveInteractiveSkyView({
    super.key,
    this.onObjectSelected,
    this.onCoordinateTapped,
    this.onObjectTapped,
    this.showFOV = false,
    this.customFOV,
    this.fovCenter,
    this.observedObjectIds = const {},
    this.listedObjectIds = const {},
    this.bortleClass = 5,
    this.horizonAltitudes,
    this.measurementMode = false,
    this.syncViewPoseFromV1 = false,
  });

  final ValueChanged<planetarium_v1.CelestialObject?>? onObjectSelected;
  final ValueChanged<planetarium_v1.CelestialCoordinate>? onCoordinateTapped;
  final void Function(
    planetarium_v1.CelestialObject? object,
    planetarium_v1.CelestialCoordinate coordinates,
    Offset screenPosition,
  )? onObjectTapped;

  final bool showFOV;
  final (double width, double height)? customFOV;
  final planetarium_v1.CelestialCoordinate? fovCenter;
  final Set<String> observedObjectIds;
  final Set<String> listedObjectIds;
  final int bortleClass;
  final List<double>? horizonAltitudes;

  /// When true, click-drag measures angular separation + position angle instead
  /// of panning. Forwarded to the v1 [planetarium_v1.InteractiveSkyView].
  final bool measurementMode;

  /// Retained for API compatibility with prior callers. No longer used: the
  /// v1 widget owns its own pose.
  final bool syncViewPoseFromV1;

  @override
  Widget build(BuildContext context) {
    return planetarium_v1.InteractiveSkyView(
      onObjectSelected: onObjectSelected,
      onCoordinateTapped: onCoordinateTapped,
      onObjectTapped: onObjectTapped,
      showFOV: showFOV,
      customFOV: customFOV,
      fovCenter: fovCenter,
      observedObjectIds: observedObjectIds,
      listedObjectIds: listedObjectIds,
      bortleClass: bortleClass,
      horizonAltitudes: horizonAltitudes,
      measurementMode: measurementMode,
    );
  }
}
