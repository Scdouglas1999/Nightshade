import 'package:nightshade_bridge/nightshade_bridge.dart';

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
