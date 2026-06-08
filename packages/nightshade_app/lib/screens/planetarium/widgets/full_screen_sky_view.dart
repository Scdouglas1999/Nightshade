import '../../../widgets/planetarium/adaptive_interactive_sky_view.dart';

/// Full-screen planetarium sky (main `/planetarium` route).
class FullScreenSkyView extends AdaptiveInteractiveSkyView {
  const FullScreenSkyView({
    super.key,
    super.onObjectSelected,
    super.onCoordinateTapped,
    super.onObjectTapped,
    super.showFOV,
    super.customFOV,
    super.fovCenter,
    super.observedObjectIds,
    super.listedObjectIds,
    super.bortleClass,
    super.horizonAltitudes,
    super.measurementMode,
  }) : super(syncViewPoseFromV1: true);
}
