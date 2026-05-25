import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart';

import 'scene_snapshot_provider.dart';

/// Visible constellation art placements for the current frame.
///
/// Uses [`select`](Ref.watch) so layers rebuild only when the placement list
/// shape actually changes, not on every snapshot tick (pose, time, labels,
/// etc.) which would happen every Flutter frame during interaction.
final constellationArtPlacementsProvider =
    Provider<List<ConstellationArtPlacementDto>>((ref) {
  return ref.watch(
    sceneSnapshotProvider.select((s) => s.constellationArt),
  );
});
