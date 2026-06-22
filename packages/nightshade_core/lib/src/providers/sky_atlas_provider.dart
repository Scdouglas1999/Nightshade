import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/sky_atlas_dao.dart';
import '../database/database.dart';
import '../services/logging_service.dart';
import '../services/sky_atlas/sky_atlas_models.dart';
import '../services/sky_atlas/sky_atlas_service.dart';
import '../services/sky_atlas/sky_atlas_seam.dart';
import 'backend_provider.dart';

/// Riverpod surface for Pillar A ("Your Sky") — the personal sky atlas.
///
/// [skyAtlasServiceProvider] builds the orchestrator from the atlas DAO + FFI
/// seam; the read providers ([skyAtlasCoverageProvider], [skyAtlasRegionsProvider],
/// [skyTileProvider]) expose the region list, growth/coverage, and a per-tile
/// PNG cutout fetch the atlas browser renders.
///
/// On a [NetworkBackend] companion the local atlas store is empty (the host owns
/// the imaging pipeline that folds frames in), so the region + coverage readers
/// branch to the host's `/api/atlas/*` routes — mirroring the First Light
/// remote path — and fall back to the local DAO/seam in host mode.

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
/// Remote (companion) mode reads the host's coverage over REST, refreshed when
/// a backend event arrives (a fold is exactly what changes coverage); host mode
/// queries the native bridge directly.
final skyAtlasCoverageProvider = StreamProvider<List<AtlasTileCoverage>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _remoteAtlasSnapshotStream<AtlasTileCoverage>(
      ref,
      backend,
      backend.getAtlasCoverage,
      AtlasTileCoverage.fromJson,
    );
  }
  return Stream.fromFuture(ref.watch(skyAtlasServiceProvider).coverage());
});

/// Reactive list of persisted atlas regions for the browser. Remote (companion)
/// mode reads the host's regions over REST (event-refreshed); host mode watches
/// the local atlas DB live.
final skyAtlasRegionsProvider = StreamProvider<List<SkyAtlasRegionRow>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _remoteAtlasSnapshotStream<SkyAtlasRegionRow>(
      ref,
      backend,
      backend.getAtlasRegions,
      skyAtlasRegionFromWireJson,
    );
  }
  return ref.watch(skyAtlasServiceProvider).watchRegions();
});

/// Reconstruct a [SkyAtlasRegionRow] from the wire JSON the appliance's
/// `/api/atlas/regions` endpoint emits (see `AtlasHandlers._regionToJson`).
/// Mirrors the DB row so the remote browser renders identically to the local
/// one; `createdAt` is the ISO-8601 string the handler serializes (not the
/// epoch-millis the Drift default serializer would expect), so it is parsed
/// here explicitly.
SkyAtlasRegionRow skyAtlasRegionFromWireJson(Map<String, dynamic> json) {
  return SkyAtlasRegionRow(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    kind: json['kind'] as String,
    centerRaDeg: (json['centerRaDeg'] as num).toDouble(),
    centerDecDeg: (json['centerDecDeg'] as num).toDouble(),
    radiusDeg: (json['radiusDeg'] as num).toDouble(),
    targetId: (json['targetId'] as num?)?.toInt(),
    tileCount: (json['tileCount'] as num?)?.toInt() ?? 0,
    integrationSeconds: (json['integrationSeconds'] as num?)?.toDouble() ?? 0.0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// REST snapshot stream for a remote atlas read: fetch once, then re-fetch
/// (debounced) whenever a backend event arrives. Keeps the last good snapshot on
/// a transient fetch failure rather than flashing empty — the same shape the
/// remote First Light feed uses (`_remoteFirstLightStream`).
Stream<List<T>> _remoteAtlasSnapshotStream<T>(
  Ref ref,
  NetworkBackend backend,
  Future<List<Map<String, dynamic>>> Function() fetch,
  T Function(Map<String, dynamic>) fromJson,
) {
  final controller = StreamController<List<T>>();
  Timer? debounce;

  Future<void> refetch() async {
    try {
      final raw = await fetch();
      final rows = raw.map(fromJson).toList(growable: false);
      if (!controller.isClosed) controller.add(rows);
    } catch (_) {
      // Transient (reconnect / host busy): keep the last good snapshot.
    }
  }

  refetch();
  final sub = backend.eventStream.listen((_) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 750), refetch);
  });
  ref.onDispose(() {
    debounce?.cancel();
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
}

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
