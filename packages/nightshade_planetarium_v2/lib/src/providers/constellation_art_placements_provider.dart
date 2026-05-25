import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/constellation_art_placement.dart';
import '../models/scene_snapshot.dart';
import 'scene_snapshot_provider.dart';

/// Visible constellation art placements for the current frame.
final constellationArtPlacementsProvider =
    Provider<List<ConstellationArtPlacementDto>>((ref) {
  return ref.watch(sceneSnapshotProvider).constellationArtPlacements;
});
