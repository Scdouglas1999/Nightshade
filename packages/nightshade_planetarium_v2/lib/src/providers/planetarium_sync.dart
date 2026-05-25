import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/planetarium_driver.dart';
import 'planetarium_handle_provider.dart';

/// Pushes [action] to the active [PlanetariumDriver] when a handle is ready.
void pushToPlanetarium(Ref ref, void Function(PlanetariumDriver driver) action) {
  final driver = ref.read(planetariumHandleProvider).valueOrNull;
  if (driver != null) {
    action(driver);
  }
}

/// Wires [listenSource] and handle readiness to [push] on every change.
void bindPlanetariumSync<T>(
  Ref ref, {
  required ProviderListenable<T> listenSource,
  required void Function(PlanetariumDriver driver, T value) push,
}) {
  ref.listen(listenSource, (_, value) {
    pushToPlanetarium(ref, (driver) => push(driver, value));
  });
  ref.listen(planetariumHandleProvider, (_, handleAsync) {
    handleAsync.whenData((driver) {
      push(driver, ref.read(listenSource));
    });
  });
  pushToPlanetarium(ref, (driver) => push(driver, ref.read(listenSource)));
}
