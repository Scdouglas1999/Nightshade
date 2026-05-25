import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Minimal planetarium command surface used by Riverpod sync providers.
///
/// [Planetarium] implements this type; widget tests substitute a
/// [FakePlanetariumDriver] via [planetariumHandleProvider] overrides.
abstract class PlanetariumDriver {
  /// Opaque registry id (positive when backed by Rust).
  int get nativeHandle;

  /// Flutter [Texture] widget id after a successful [resize].
  ///
  /// Remains `0` until [resize] completes on a live engine texture registry.
  int get textureId;

  /// Resizes the render target and returns the allocated Flutter texture id.
  int resize({
    required int width,
    required int height,
    required double devicePixelRatio,
  });

  void setPose(ViewPoseDto pose);

  void setTime(AstroTimeDto time);

  void setObserver(ObserverDto observer);
}
