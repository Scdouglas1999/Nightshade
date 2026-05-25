import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import 'planetarium_sync.dart';

class SelectionNotifier extends StateNotifier<SelectedObjectDto?> {
  SelectionNotifier() : super(null);

  void select(SelectedObjectDto object) {
    state = object;
  }

  void clear() {
    state = null;
  }
}

/// Currently selected celestial object for planetarium v2.
final selectionProvider =
    StateNotifierProvider<SelectionNotifier, SelectedObjectDto?>((ref) {
  return SelectionNotifier();
});

/// Mirrors [selectionProvider] into Rust via [planetariumSetSelection].
final planetariumSelectionSyncProvider = Provider<void>((ref) {
  bindPlanetariumSync(
    ref,
    listenSource: selectionProvider,
    push: (driver, selected) => driver.setSelection(selected),
  );
});
