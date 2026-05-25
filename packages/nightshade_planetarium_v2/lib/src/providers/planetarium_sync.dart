import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/planetarium_driver.dart';
import 'planetarium_handle_provider.dart';

/// Pushes [action] to the active [PlanetariumDriver] when a handle is ready.
///
/// Silently no-ops while the handle is still resolving — the
/// [bindPlanetariumSync] handle listener replays the latest source value as
/// soon as the Future completes so no edge is lost. Once the handle has
/// thrown (AsyncError), subsequent reads return null and pushes are
/// dropped; the AsyncError surfaces through `planetariumHandleProvider`
/// itself for the UI to display loudly.
void pushToPlanetarium(
  Ref ref,
  void Function(PlanetariumDriver driver) action,
) {
  final driver = ref.read(planetariumHandleProvider).valueOrNull;
  if (driver != null) {
    action(driver);
  }
}

/// Wires [listenSource] and handle readiness to [push] on every change.
///
/// After pushing, schedules a Flutter frame so the
/// [SceneSnapshotNotifier]'s chained post-frame poll observes the new
/// Rust-side state. Without this, idle UIs (no gestures, no widget
/// rebuilds) would miss snapshot updates that follow a sync-provider
/// push (e.g. observation-time ticks driving label re-projection).
void bindPlanetariumSync<T>(
  Ref ref, {
  required ProviderListenable<T> listenSource,
  required void Function(PlanetariumDriver driver, T value) push,
}) {
  void pushAndScheduleFrame(PlanetariumDriver driver, T value) {
    push(driver, value);
    SchedulerBinding.instance.scheduleFrame();
  }

  ref.listen(listenSource, (_, value) {
    pushToPlanetarium(ref, (driver) => pushAndScheduleFrame(driver, value));
  });
  ref.listen(planetariumHandleProvider, (_, handleAsync) {
    handleAsync.whenData((driver) {
      pushAndScheduleFrame(driver, ref.read(listenSource));
    });
  });
  pushToPlanetarium(
    ref,
    (driver) => pushAndScheduleFrame(driver, ref.read(listenSource)),
  );
}
