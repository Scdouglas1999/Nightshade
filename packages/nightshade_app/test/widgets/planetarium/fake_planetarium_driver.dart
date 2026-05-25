import 'package:nightshade_bridge/nightshade_bridge.dart';
import 'package:nightshade_planetarium_v2/src/bridge/planetarium_driver.dart';
import 'package:nightshade_planetarium_v2/src/models/scene_snapshot.dart';

/// In-memory [PlanetariumDriver] for nightshade_app widget tests.
class FakePlanetariumDriver implements PlanetariumDriver {
  FakePlanetariumDriver({
    this.nativeHandle = 42,
    this.textureId = 7,
  });

  @override
  final int nativeHandle;

  @override
  int textureId;

  @override
  int resize({
    required int width,
    required int height,
    required double devicePixelRatio,
  }) =>
      textureId;

  @override
  void setPose(ViewPoseDto pose) {}

  @override
  void setTime(AstroTimeDto time) {}

  @override
  void setObserver(ObserverDto observer) {}

  @override
  void setConfig(RenderConfigDto config) {}

  @override
  void pushGesture(GestureEventDto event) {}

  @override
  SelectedObjectDto? hitTest({required double x, required double y}) => null;

  @override
  void setSelection(SelectedObjectDto? selected) {}

  @override
  void quiesce() {}

  @override
  void restore() {}

  @override
  SceneSnapshotDto snapshot() => kEmptySceneSnapshot;
}
