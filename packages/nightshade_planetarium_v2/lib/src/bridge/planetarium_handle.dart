import 'package:nightshade_bridge/nightshade_bridge.dart';

import 'planetarium_driver.dart';

/// Typed Dart wrapper around the planetarium v2 FFI handle registry.
///
/// Holds an opaque Rust handle id from [planetariumCreate]. Call [dispose] when
/// the host widget is torn down so the render thread and surface are released.
class Planetarium implements PlanetariumDriver {
  Planetarium._(this._handle, {int textureId = 0}) : _textureId = textureId;

  final int _handle;
  int _textureId;
  bool _disposed = false;

  /// Opaque registry id forwarded to every `planetarium*` FFI call.
  @override
  int get nativeHandle => _handle;

  /// Flutter [Texture] widget id after a successful [resize].
  ///
  /// Remains `0` until [resize] completes on a live engine texture registry.
  @override
  int get textureId => _textureId;

  /// Creates a planetarium bound to [engineHandle].
  ///
  /// Pass `0` in widget/unit tests without a live Flutter texture registry
  /// (matches `packages/nightshade_bridge/test/planetarium_handle_test.dart`).
  /// Production embedders should pass the Irondash engine id from the host app.
  factory Planetarium.create({required int engineHandle}) {
    final id = planetariumCreate(engineHandle: engineHandle);
    if (id <= 0) {
      throw StateError(
        'planetariumCreate returned invalid handle for engine $engineHandle',
      );
    }
    return Planetarium._(id);
  }

  /// Resizes the render target and stores the allocated Flutter texture id.
  @override
  int resize({
    required int width,
    required int height,
    required double devicePixelRatio,
  }) {
    _ensureAlive();
    final tex = planetariumResize(
      handle: _handle,
      w: width,
      h: height,
      dpr: devicePixelRatio,
    );
    if (tex <= 0) {
      throw StateError(
        'planetariumResize returned invalid texture id '
        '(${width}x$height @ $devicePixelRatio dpr)',
      );
    }
    _textureId = tex;
    return _textureId;
  }

  @override
  void setPose(ViewPoseDto pose) {
    _ensureAlive();
    planetariumSetPose(handle: _handle, pose: pose);
  }

  @override
  void setTime(AstroTimeDto time) {
    _ensureAlive();
    planetariumSetTime(handle: _handle, time: time);
  }

  @override
  void setObserver(ObserverDto observer) {
    _ensureAlive();
    planetariumSetObserver(handle: _handle, observer: observer);
  }

  @override
  void setConfig(RenderConfigDto config) {
    _ensureAlive();
    planetariumSetConfig(handle: _handle, config: config);
  }

  void pushGesture(GestureEventDto event) {
    _ensureAlive();
    planetariumPushGesture(handle: _handle, evt: event);
  }

  SelectedObjectDto? hitTest({required double x, required double y}) {
    _ensureAlive();
    return planetariumHitTest(handle: _handle, x: x, y: y);
  }

  void setSelection(SelectedObjectDto? selected) {
    _ensureAlive();
    planetariumSetSelection(handle: _handle, selected: selected);
  }

  @override
  SceneSnapshotDto snapshot() {
    _ensureAlive();
    return planetariumSnapshot(handle: _handle);
  }

  /// Stops the render thread and removes this handle from the Rust registry.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    planetariumDispose(handle: _handle);
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('Planetarium handle already disposed');
    }
  }
}
