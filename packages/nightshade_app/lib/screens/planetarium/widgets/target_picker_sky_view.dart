import '../../../widgets/planetarium/adaptive_interactive_sky_view.dart';

/// Embedded sky for target selection flows (add-target dialog, search pickers).
class TargetPickerSkyView extends AdaptiveInteractiveSkyView {
  const TargetPickerSkyView({
    super.key,
    super.onObjectTapped,
    super.onObjectSelected,
    super.showFOV = false,
    super.bortleClass = 5,
    super.horizonAltitudes,
  }) : super(syncViewPoseFromV1: true);
}
