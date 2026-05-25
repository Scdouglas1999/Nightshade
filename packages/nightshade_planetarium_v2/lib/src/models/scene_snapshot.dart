import 'package:nightshade_bridge/nightshade_bridge.dart';

import 'constellation_art_placement.dart';

/// Empty snapshot before the native renderer publishes its first frame.
final SceneSnapshotDto kEmptySceneSnapshot = SceneSnapshotDto(
  frameId: BigInt.zero,
  viewPose: const ViewPoseDto(
    raRad: 0,
    decRad: 1.5707963267948966,
    fovRad: 1.5707963267948966,
    rollRad: 0,
    projection: SkyProjectionDto.stereographic,
  ),
  labels: const [],
);

/// Constellation art placements from a scene snapshot.
///
/// Returns an empty list until Task 74 adds `constellationArt` to
/// [`SceneSnapshotDto`]; then wire this getter to that field.
extension SceneSnapshotConstellationArt on SceneSnapshotDto {
  List<ConstellationArtPlacementDto> get constellationArtPlacements {
    // Task 74: return constellationArt mapped from FFI DTOs.
    return const [];
  }
}
