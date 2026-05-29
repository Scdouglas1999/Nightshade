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

  /// Submits a resize to the render thread and returns the currently-published
  /// texture id, **without blocking** for the new allocation.
  ///
  /// The first call after [create] usually returns `0` because the texture
  /// allocation is queued on the Flutter platform thread (irondash
  /// requirement) and only runs once the FFI-sync call returns and the Win32
  /// message pump resumes — see the Rust side's `planetarium_resize` for the
  /// deadlock this avoids. Callers must poll [pollTextureId] (or call [resize]
  /// again) until they get a positive id back.
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
    if (tex > 0) {
      _textureId = tex;
    }
    return tex;
  }

  /// Reads the latest published Flutter texture id without queuing a resize.
  /// Returns `0` if the render thread hasn't completed an allocation yet.
  int pollTextureId() {
    _ensureAlive();
    final tex = planetariumTextureId(handle: _handle);
    if (tex > 0) {
      _textureId = tex;
    }
    return tex;
  }

  /// Returns the last surface-allocate error from the render thread, or `null`
  /// if allocation is still pending or has succeeded.
  String? lastSurfaceError() {
    _ensureAlive();
    return planetariumLastSurfaceError(handle: _handle);
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

  @override
  void pushGesture(GestureEventDto event) {
    _ensureAlive();
    planetariumPushGesture(handle: _handle, evt: event);
  }

  @override
  SelectedObjectDto? hitTest({required double x, required double y}) {
    _ensureAlive();
    return planetariumHitTest(handle: _handle, x: x, y: y);
  }

  @override
  void setSelection(SelectedObjectDto? selected) {
    _ensureAlive();
    planetariumSetSelection(handle: _handle, selected: selected);
  }

  @override
  void quiesce() {
    // BACKGROUND/QUIESCE — Dart-side hook for the app-lifecycle observer in
    // [InteractiveSkyView]. The v2 design (§ 9.4) calls for the render
    // thread to drop GPU resources except resident catalog tiles and
    // release the texture surface here; that FFI surface is **not yet
    // implemented in the Rust bridge** (no `planetariumQuiesce` /
    // `planetariumRestore` exports as of `b3860c2d`). Until those land we
    // do the minimum that's actually safe and effective from Dart:
    //   1. Cancel any in-flight gesture so the render thread doesn't keep
    //      animating momentum while we're backgrounded.
    //   2. Flip `planetariumQuiescedProvider` (caller responsibility) so
    //      [SceneSnapshotNotifier] stops the post-frame poll loop —
    //      eliminates the FFI snapshot read per Flutter frame.
    // GPU resource release stays in Rust's domain; flagged in the v2 audit
    // report so a follow-up plan-task can wire the real quiesce FFI.
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
  void restore() {
    // FOREGROUND/RESTORE — paired with [quiesce]. Nothing to do on the Dart
    // side yet because [quiesce] only cancelled the gesture stream; the
    // snapshot poll resumes via [planetariumQuiescedProvider] flipping back
    // to `false` in [InteractiveSkyView.didChangeAppLifecycleState]. When
    // the Rust `planetariumQuiesce` FFI lands, mirror it here with
    // `planetariumRestore`.
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
