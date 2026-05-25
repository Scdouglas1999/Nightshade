import 'package:nightshade_bridge/nightshade_bridge.dart';

/// Minimal planetarium command surface used by Riverpod sync providers.
///
/// [Planetarium] implements this type; widget tests substitute a
/// [FakePlanetariumDriver] via [planetariumHandleProvider] overrides.
abstract class PlanetariumDriver {
  /// Opaque registry id (positive when backed by Rust).
  int get nativeHandle;

  void setPose(ViewPoseDto pose);

  void setTime(AstroTimeDto time);

  void setObserver(ObserverDto observer);
}
