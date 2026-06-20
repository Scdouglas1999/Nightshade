import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/sky_atlas_dao.dart';
import '../database/database.dart';
import '../services/logging_service.dart';
import '../services/sky_atlas/sky_atlas_models.dart';
import '../services/sky_atlas/sky_atlas_service.dart';
import '../services/sky_atlas/sky_atlas_seam.dart';

/// Riverpod surface for Pillar A ("Your Sky") — the personal sky atlas.
///
/// [skyAtlasServiceProvider] builds the orchestrator from the atlas DAO + FFI
/// seam; the read providers ([skyAtlasCoverageProvider], [skyAtlasRegionsProvider],
/// [skyTileProvider]) expose the region list, growth/coverage, and a per-tile
/// PNG cutout fetch the atlas browser renders. They are the same surface
/// [NetworkBackend] companions reach via the headless `/api/atlas/*` routes.

/// The sky-atlas orchestration service.
final skyAtlasServiceProvider = Provider<SkyAtlasService>((ref) {
  return SkyAtlasService(
    dao: ref.watch(skyAtlasDaoProvider),
    seam: ref.watch(skyAtlasSeamProvider),
    logger: ref.watch(loggingServiceProvider),
    atlasRootResolver: defaultAtlasRoot,
  );
});

/// Per-tile coverage rows (deepest first) for the heat overlay / gallery.
final skyAtlasCoverageProvider = FutureProvider<List<AtlasTileCoverage>>((ref) {
  return ref.watch(skyAtlasServiceProvider).coverage();
});

/// Reactive list of persisted atlas regions for the browser.
final skyAtlasRegionsProvider = StreamProvider<List<SkyAtlasRegionRow>>((ref) {
  return ref.watch(skyAtlasServiceProvider).watchRegions();
});

/// Query key for [skyTileProvider]: a tile id plus an optional time-scrub
/// anchor. Value-equal so the same query reuses one cached cutout future.
class SkyTileQuery {
  final int tileId;
  final DateTime? asOf;

  const SkyTileQuery(this.tileId, {this.asOf});

  @override
  bool operator ==(Object other) =>
      other is SkyTileQuery && other.tileId == tileId && other.asOf == asOf;

  @override
  int get hashCode => Object.hash(tileId, asOf);
}

/// Render (and cache) a finalized tile to a PNG, returning its on-disk path.
/// Optionally time-scrubbed via [SkyTileQuery.asOf].
final skyTileProvider = FutureProvider.family<String, SkyTileQuery>((
  ref,
  query,
) {
  return ref
      .watch(skyAtlasServiceProvider)
      .finalizeTilePng(query.tileId, asOf: query.asOf);
});

/// Provenance (contributors + fold log) for one tile.
final skyTileInfoProvider = FutureProvider.family<TileProvenanceView, int>((
  ref,
  tileId,
) {
  return ref.watch(skyAtlasServiceProvider).tileInfo(tileId);
});

/// Deepening growth curve for a region cone (raw bridge map).
final skyAtlasGrowthProvider =
    FutureProvider.family<
      Map<String, dynamic>,
      ({double ra, double dec, double radius})
    >((ref, cone) {
      return ref
          .watch(skyAtlasServiceProvider)
          .growth(
            centerRaDeg: cone.ra,
            centerDecDeg: cone.dec,
            radiusDeg: cone.radius,
          );
    });
