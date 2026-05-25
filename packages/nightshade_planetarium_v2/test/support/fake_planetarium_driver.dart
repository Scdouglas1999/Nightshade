import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/src/bridge/planetarium_driver.dart';
import 'package:nightshade_planetarium_v2/src/models/scene_snapshot.dart';

/// In-memory [PlanetariumDriver] for widget/provider tests without Rust.
class FakePlanetariumDriver implements PlanetariumDriver {
  FakePlanetariumDriver({
    this.nativeHandle = 42,
    this.textureId = 7,
  });

  @override
  final int nativeHandle;

  @override
  int textureId;

  int? lastResizeWidth;
  int? lastResizeHeight;
  double? lastResizeDevicePixelRatio;

  ViewPoseDto? lastPose;
  AstroTimeDto? lastTime;
  ObserverDto? lastObserver;
  RenderConfigDto? lastConfig;
  SceneSnapshotDto snapshotResult = kEmptySceneSnapshot;
  int snapshotCallCount = 0;

  @override
  int resize({
    required int width,
    required int height,
    required double devicePixelRatio,
  }) {
    lastResizeWidth = width;
    lastResizeHeight = height;
    lastResizeDevicePixelRatio = devicePixelRatio;
    return textureId;
  }

  @override
  void setPose(ViewPoseDto pose) => lastPose = pose;

  @override
  void setTime(AstroTimeDto time) => lastTime = time;

  @override
  void setObserver(ObserverDto observer) => lastObserver = observer;

  @override
  void setConfig(RenderConfigDto config) => lastConfig = config;

  @override
  SceneSnapshotDto snapshot() {
    snapshotCallCount++;
    return snapshotResult;
  }
}
