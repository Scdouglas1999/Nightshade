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
  final List<GestureEventDto> pushedGestures = [];
  SelectedObjectDto? lastHitTestResult;
  double? lastHitTestX;
  double? lastHitTestY;
  SelectedObjectDto? lastSelection;
  int quiesceCallCount = 0;
  int restoreCallCount = 0;
  SceneSnapshotDto snapshotResult = kEmptySceneSnapshot;
  int snapshotCallCount = 0;

  /// When set, [hitTest] returns this value.
  SelectedObjectDto? hitTestStub;

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
  void pushGesture(GestureEventDto event) => pushedGestures.add(event);

  @override
  SelectedObjectDto? hitTest({required double x, required double y}) {
    lastHitTestX = x;
    lastHitTestY = y;
    return hitTestStub ?? lastHitTestResult;
  }

  @override
  void setSelection(SelectedObjectDto? selected) => lastSelection = selected;

  @override
  void quiesce() {
    quiesceCallCount++;
    pushGesture(
      const GestureEventDto(
        kind: GestureKindDto.cancel,
        x: 0,
        y: 0,
        dx: 0,
        dy: 0,
        vx: 0,
        vy: 0,
        factor: 1,
        radians: 0,
      ),
    );
  }

  @override
  void restore() => restoreCallCount++;

  @override
  SceneSnapshotDto snapshot() {
    snapshotCallCount++;
    return snapshotResult;
  }
}
