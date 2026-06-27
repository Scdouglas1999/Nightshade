import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for the Pillar A ("Your Sky") personal sky-atlas surface.
///
/// Exposes the atlas region list + per-region detail, a co-added cutout image,
/// and the per-region fold timeline so a [NetworkBackend] mobile companion can
/// browse the host's atlas over REST. Reads go through [SkyAtlasService] (region
/// rows from the Drift DAO; coverage / cutout from the native bridge) — the same
/// service the desktop UI uses, so the host stays the single source of truth.
class AtlasHandlers {
  final ProviderContainer container;

  AtlasHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);
  SkyAtlasService get _service => container.read(skyAtlasServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'AtlasHandlers');

  // ===========================================================================
  // GET /api/atlas/regions
  // ===========================================================================

  Future<Response> handleGetRegions(Request request) async {
    _logInfo('[API] GET /api/atlas/regions');
    final regions = await _service.regions();
    return jsonOk({
      'regions': regions.map(_regionToJson).toList(),
      'count': regions.length,
    });
  }

  // ===========================================================================
  // GET /api/atlas/coverage
  // ===========================================================================
  //
  // Per-tile coverage rows (deepest first), the heat-overlay / gallery data the
  // companion's "Your Sky" browser renders and the "your contribution" bar sums.
  // The native coverage query runs on the host, so a remote client reads it here
  // instead of its (empty) local atlas store.

  Future<Response> handleGetCoverage(Request request) async {
    _logInfo('[API] GET /api/atlas/coverage');
    // Served from the SkyTiles DB index (same scalars, no `.nst` sidecar scan)
    // so a companion's coverage poll never thrashes the host's disk.
    final tiles = await _service.coverageFromIndex();
    return jsonOk({
      'tiles': tiles.map(_coverageToJson).toList(),
      'count': tiles.length,
    });
  }

  // ===========================================================================
  // GET /api/atlas/region/<id>
  // ===========================================================================

  Future<Response> handleGetRegion(Request request, String id) async {
    _logInfo('[API] GET /api/atlas/region/$id');
    final regionId = int.tryParse(id);
    if (regionId == null) {
      return jsonError(
        code: 'invalid_region_id',
        message: 'region id must be an integer',
        statusCode: 400,
      );
    }
    final region = await _findRegion(regionId);
    if (region == null) {
      return jsonError(
        code: 'region_not_found',
        message: 'region $regionId not found',
        statusCode: 404,
      );
    }

    // Live native coverage for the region cone augments the denormalized DB
    // rollups so the companion sees the true integration depth without a
    // second round-trip.
    final coverage = await _service.regionCoverage(
      centerRaDeg: region.centerRaDeg,
      centerDecDeg: region.centerDecDeg,
      radiusDeg: region.radiusDeg,
    );

    // The region's tiles (deepest first) so the companion's detail screen can
    // pick a preview tile + render the depth/provenance rollups without a
    // per-tile route. Additive to the same response — the contract is unchanged.
    final tiles = await _service.tilesForRegion(regionId);

    return jsonOk({
      'region': _regionToJson(region),
      'coverage': coverage,
      'tiles': tiles.map(_tileToJson).toList(),
    });
  }

  // ===========================================================================
  // GET /api/atlas/region/<id>/cutout
  // ===========================================================================
  //
  // Returns the co-added PNG of the region cone as image bytes. Optional query
  // params: outPixels (default 2048), interp (bilinear|catmullRom|lanczos3).

  Future<Response> handleGetRegionCutout(Request request, String id) async {
    _logInfo('[API] GET /api/atlas/region/$id/cutout');
    final regionId = int.tryParse(id);
    if (regionId == null) {
      return jsonError(
        code: 'invalid_region_id',
        message: 'region id must be an integer',
        statusCode: 400,
      );
    }
    final region = await _findRegion(regionId);
    if (region == null) {
      return jsonError(
        code: 'region_not_found',
        message: 'region $regionId not found',
        statusCode: 404,
      );
    }

    final qp = request.url.queryParameters;
    final outPixels = int.tryParse(qp['outPixels'] ?? '') ?? 2048;
    final interp = _parseInterp(qp['interp']);

    final result = await _service.cutout(
      centerRaDeg: region.centerRaDeg,
      centerDecDeg: region.centerDecDeg,
      radiusDeg: region.radiusDeg,
      outPixels: outPixels,
      interp: interp,
    );

    final pngPath = result['pngPath'] as String?;
    if (pngPath == null || pngPath.trim().isEmpty) {
      return jsonError(
        code: 'cutout_failed',
        message: 'cutout did not produce a PNG for region $regionId',
        statusCode: 500,
      );
    }
    final file = File(pngPath);
    if (!await file.exists()) {
      return jsonError(
        code: 'cutout_missing',
        message: 'cutout PNG missing on disk for region $regionId',
        statusCode: 500,
      );
    }
    final bytes = await file.readAsBytes();
    return contentResponse(
      bytes,
      contentType: 'image/png',
      contentLength: bytes.length,
      headers: {
        'cache-control': 'no-cache',
        'x-covered-fraction':
            (result['coveredFraction'] as num?)?.toString() ?? '0',
        'x-tiles-used': (result['tilesUsed'] as num?)?.toString() ?? '0',
      },
    );
  }

  // ===========================================================================
  // GET /api/atlas/region/<id>/timeline
  // ===========================================================================

  Future<Response> handleGetRegionTimeline(Request request, String id) async {
    _logInfo('[API] GET /api/atlas/region/$id/timeline');
    final regionId = int.tryParse(id);
    if (regionId == null) {
      return jsonError(
        code: 'invalid_region_id',
        message: 'region id must be an integer',
        statusCode: 400,
      );
    }
    final region = await _findRegion(regionId);
    if (region == null) {
      return jsonError(
        code: 'region_not_found',
        message: 'region $regionId not found',
        statusCode: 404,
      );
    }

    final folds = await _service.regionTimeline(regionId);

    // The deepening growth curve for the cone (cumulative frames / seconds per
    // fold) — the companion plots this as the "your sky is getting deeper" line.
    final growth = await _service.growth(
      centerRaDeg: region.centerRaDeg,
      centerDecDeg: region.centerDecDeg,
      radiusDeg: region.radiusDeg,
    );

    return jsonOk({
      'regionId': regionId,
      'folds': folds.map(_foldToJson).toList(),
      'growth': growth,
    });
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  Future<SkyAtlasRegionRow?> _findRegion(int regionId) async {
    final regions = await _service.regions();
    for (final region in regions) {
      if (region.id == regionId) return region;
    }
    return null;
  }

  AtlasInterp _parseInterp(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final interp in AtlasInterp.values) {
      if (interp.wire.toLowerCase() == normalized) return interp;
    }
    return AtlasInterp.lanczos3;
  }

  /// Serialize a coverage row using the bridge-native key names
  /// [AtlasTileCoverage.fromJson] consumes (`centerRa` / `centerDec`), so the
  /// companion reconstructs rows with the same decoder the local path uses.
  Map<String, dynamic> _coverageToJson(AtlasTileCoverage tile) => {
    'tileId': tile.tileId,
    'centerRa': tile.centerRaDeg,
    'centerDec': tile.centerDecDeg,
    'coverageMean': tile.coverageMean,
    'totalFrames': tile.totalFrames,
    'integrationSeconds': tile.integrationSeconds,
    'lastFoldIso': tile.lastFoldIso,
    'channels': tile.channels,
  };

  /// Serialize a tile row for the companion's region detail. Carries the
  /// `(tileId, healpixOrder)` identity, centre + own-light totals, and the
  /// blended swarm-overlay depth so the slave renders the same rollups the host
  /// computes locally.
  Map<String, dynamic> _tileToJson(SkyTileRow tile) => {
    'id': tile.id,
    'tileId': tile.tileId,
    'healpixOrder': tile.healpixOrder,
    'channels': tile.channels,
    'centerRaDeg': tile.centerRaDeg,
    'centerDecDeg': tile.centerDecDeg,
    'coverageMean': tile.coverageMean,
    'totalFrames': tile.totalFrames,
    'integrationSeconds': tile.integrationSeconds,
    'swarmOverlayFrames': tile.swarmOverlayFrames,
    'swarmOverlayIntegrationSeconds': tile.swarmOverlayIntegrationSeconds,
    'regionId': tile.regionId,
  };

  Map<String, dynamic> _regionToJson(SkyAtlasRegionRow region) => {
    'id': region.id,
    'name': region.name,
    'kind': region.kind,
    'centerRaDeg': region.centerRaDeg,
    'centerDecDeg': region.centerDecDeg,
    'radiusDeg': region.radiusDeg,
    'targetId': region.targetId,
    'tileCount': region.tileCount,
    'integrationSeconds': region.integrationSeconds,
    'createdAt': region.createdAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _foldToJson(SkyAtlasFoldRow fold) => {
    'id': fold.id,
    'tileId': fold.tileId,
    'healpixOrder': fold.healpixOrder,
    'sessionId': fold.sessionId,
    'foldedAt': fold.foldedAt.toUtc().toIso8601String(),
    'framesAdded': fold.framesAdded,
    'weightAdded': fold.weightAdded,
    'integrationSecondsAdded': fold.integrationSecondsAdded,
    'rejected': fold.rejected,
    'contributor': fold.contributor,
    'label': fold.label,
  };
}
