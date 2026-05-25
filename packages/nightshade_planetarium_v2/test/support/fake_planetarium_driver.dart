import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/src/bridge/planetarium_driver.dart';

/// In-memory [PlanetariumDriver] for widget/provider tests without Rust.
class FakePlanetariumDriver implements PlanetariumDriver {
  FakePlanetariumDriver({this.nativeHandle = 42});

  @override
  final int nativeHandle;

  ViewPoseDto? lastPose;
  AstroTimeDto? lastTime;
  ObserverDto? lastObserver;

  @override
  void setPose(ViewPoseDto pose) => lastPose = pose;

  @override
  void setTime(AstroTimeDto time) => lastTime = time;

  @override
  void setObserver(ObserverDto observer) => lastObserver = observer;
}
