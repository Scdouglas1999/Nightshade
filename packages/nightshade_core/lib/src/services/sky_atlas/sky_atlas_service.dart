import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../database/daos/sky_atlas_dao.dart';
import '../../database/database.dart';
import '../../database/tables/sky_atlas_tables.dart' show skyAtlasHealpixOrder;
import '../logging_service.dart';
import '../wcs/gnomonic_projection.dart';
import 'sky_atlas_models.dart';
import 'sky_atlas_seam.dart';

/// Orchestrates Pillar A ("Your Sky") — the personal sky atlas.
///
/// Folds plate-solved light frames into the fixed HEALPix tiling via the native
/// `api_sky_atlas` surface ([SkyAtlasSeam]) and mirrors every fold into the
/// Drift atlas tables ([SkyAtlasDao]): one [SkyTiles] row per touched tile
/// (running totals + sidecar pointer) and one [SkyAtlasFolds] row per fold (the
/// time-scrub timeline). Region grouping, coverage, growth, and shareable
/// cutouts are read straight back through the same seam.
///
/// The atlas state itself lives entirely on disk under [atlasRoot] (one `.nst`
/// accumulator per tile); the DB rows are the cheap index the UI renders from.
class SkyAtlasService {
  SkyAtlasService({
    required SkyAtlasDao dao,
    required SkyAtlasSeam seam,
    required LoggingService logger,
    required Future<String> Function() atlasRootResolver,
    int order = skyAtlasHealpixOrder,
  }) : _dao = dao,
       _seam = seam,
       _logger = logger,
       _atlasRootResolver = atlasRootResolver,
       _order = order;

  final SkyAtlasDao _dao;
  final SkyAtlasSeam _seam;
  final LoggingService _logger;
  final Future<String> Function() _atlasRootResolver;
  final int _order;

  static const _logSource = 'SkyAtlasService';

  String? _cachedAtlasRoot;

  /// Serializes every writer that touches a base/overlay `.nst` sidecar so two
  /// folds (or a fold and a swarm merge) never interleave on the same tile file.
  /// In-process is sufficient: the host is the single atlas authority — remote
  /// companions mirror but do not fold.
  Future<void> _foldChain = Future<void>.value();

  /// Run [body] after the prior queued sidecar writer completes, restoring the
  /// chain even when [body] throws so one failed fold cannot wedge the queue.
  Future<T> _serialized<T>(Future<T> Function() body) {
    final prior = _foldChain;
    final completer = Completer<void>();
    _foldChain = completer.future;
    return prior.then((_) => body()).whenComplete(completer.complete);
  }

  /// The on-disk atlas root, resolved (and the directory created) lazily once.
  Future<String> atlasRoot() async {
    final cached = _cachedAtlasRoot;
    if (cached != null) return cached;
    final root = await _atlasRootResolver();
    _cachedAtlasRoot = root;
    return root;
  }

  /// Fold a session's solved frames into the atlas and persist the result.
  ///
  /// Invertible-WCS frames are sent to the native fold in one batch; the
  /// per-tile post-fold state the bridge returns is upserted into [SkyTiles] and
  /// a [SkyAtlasFolds] timeline row is appended per touched tile. Frames with a
  /// degenerate WCS are dropped before the call (the native side would reject
  /// the whole batch otherwise) and noted in the log. Returns the decoded
  /// summary; an empty frame list short-circuits to [AtlasFoldSummary.empty].
  Future<AtlasFoldSummary> foldSession({
    required int sessionId,
    required List<SolvedFrameRef> frames,
    AtlasInterp interp = AtlasInterp.lanczos3,
    String label = '',
    String contributor = '',
  }) async {
    final usable = frames.where((f) => f.hasInvertibleWcs).toList();
    final dropped = frames.length - usable.length;
    if (dropped > 0) {
      _logger.warning(
        'foldSession($sessionId): dropped $dropped frame(s) with a '
        'degenerate WCS before folding.',
        source: _logSource,
      );
    }
    if (usable.isEmpty) {
      return AtlasFoldSummary.empty;
    }

    final root = await atlasRoot();
    final foldLabel = label.trim().isEmpty
        ? DateTime.now().toUtc().toIso8601String()
        : label.trim();

    final args = <String, dynamic>{
      'action': 'fold',
      'atlasRoot': root,
      'order': _order,
      'contributor': contributor,
      'interp': interp.wire,
      'label': foldLabel,
      'frames': usable.map((f) => f.toFoldFrameJson()).toList(),
    };

    final summary = await _serialized(() async {
      final result = await _seam.dispatch(args);
      final folded = AtlasFoldSummary.fromJson(result);
      await _persistFold(
        summary: folded,
        sessionId: sessionId,
        label: foldLabel,
        contributor: contributor,
        root: root,
      );
      return folded;
    });

    _logger.info(
      'foldSession($sessionId): folded ${summary.totalFramesFolded} frame(s) '
      'across ${summary.tilesTouched.length} tile(s); '
      '${summary.framesSkippedNoCoverage} off-sky.',
      source: _logSource,
    );
    return summary;
  }

  /// Fold a single solved frame — the per-capture hook the imaging/live-stacking
  /// path calls as each light is solved. Thin wrapper over [foldSession].
  Future<AtlasFoldSummary> foldFrame({
    required int? sessionId,
    required SolvedFrameRef frame,
    AtlasInterp interp = AtlasInterp.lanczos3,
    String label = '',
    String contributor = '',
  }) {
    return foldSession(
      sessionId: sessionId ?? 0,
      frames: [frame],
      interp: interp,
      label: label,
      contributor: contributor,
    );
  }

  /// Fold an already-persisted, plate-solved captured-image row into the atlas.
  ///
  /// This is the auto-fold entry point the solve-persist hook calls: it gates on
  /// the row being a light frame with a usable solve, builds the [SolvedFrameRef]
  /// from the stored WCS (CD matrix + SIP when present, else scale+rotation), and
  /// folds it under the image's session label. Returns null (folding nothing)
  /// when the row is not a foldable light or lacks an invertible WCS — never
  /// throws for those expected cases. [imageWidth]/[imageHeight] are the frame's
  /// pixel dimensions (the FITS dims), needed for the reference pixel.
  Future<AtlasFoldSummary?> autoFoldCapturedImage({
    required CapturedImage image,
    required int imageWidth,
    required int imageHeight,
    SolvedWcsDistortion distortion = const SolvedWcsDistortion(),
    AtlasInterp interp = AtlasInterp.lanczos3,
  }) async {
    if (image.frameType.toLowerCase() != 'light') return null;
    if (!image.isPlateSolved ||
        image.solvedRa == null ||
        image.solvedDec == null) {
      return null;
    }
    if (image.filePath.trim().isEmpty) return null;
    if (imageWidth <= 0 || imageHeight <= 0) return null;

    final solvedWcs = SolvedWcs(
      raHours: image.solvedRa!,
      decDegrees: image.solvedDec!,
      rotationDeg: image.solvedRotation ?? 0.0,
      pixelScaleArcsec: image.solvedPixelScale ?? 0.0,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      cd1_1: distortion.cd1_1,
      cd1_2: distortion.cd1_2,
      cd2_1: distortion.cd2_1,
      cd2_2: distortion.cd2_2,
      aOrder: distortion.aOrder,
      bOrder: distortion.bOrder,
      aCoeffs: distortion.aCoeffs,
      bCoeffs: distortion.bCoeffs,
      apOrder: distortion.apOrder,
      bpOrder: distortion.bpOrder,
      apCoeffs: distortion.apCoeffs,
      bpCoeffs: distortion.bpCoeffs,
    );
    // A solve with neither a CD matrix nor a positive pixel scale cannot yield
    // an invertible geometry; skip rather than feeding the native fold garbage.
    if (!solvedWcs.hasCdMatrix && solvedWcs.pixelScaleArcsec <= 0) return null;

    final frame = SolvedFrameRef.fromSolvedWcs(
      framePath: image.filePath,
      wcs: solvedWcs,
      exposureSec: image.exposureDuration,
    );
    if (!frame.hasInvertibleWcs) return null;

    return foldSession(
      sessionId: image.sessionId ?? 0,
      frames: [frame],
      interp: interp,
      label: _foldLabelFor(image),
    );
  }

  /// A stable, sortable ISO date label for a captured image's fold, derived from
  /// its capture time (UTC) so the time-scrub timeline orders by acquisition.
  String _foldLabelFor(CapturedImage image) {
    return image.capturedAt.toUtc().toIso8601String();
  }

  /// Render a finalized tile to a PNG under the atlas cache and return its path.
  /// [asOf] requests a time-scrubbed render (only honoured by the native side
  /// when every fold is at/before the anchor; otherwise it raises).
  Future<String> finalizeTilePng(int tileId, {DateTime? asOf}) async {
    final root = await atlasRoot();
    final outPath = p.join(_cacheDir(root), 'tile_$tileId.png');
    final args = <String, dynamic>{
      'action': 'tilePng',
      'atlasRoot': root,
      'order': _order,
      'tileId': tileId,
      'outPath': outPath,
      if (asOf != null) 'asOfIso': asOf.toUtc().toIso8601String(),
    };
    final result = await _seam.dispatch(args);
    return result['outPath'] as String? ?? outPath;
  }

  /// Co-add a cone of the atlas into a shareable cutout (FITS + PNG) and return
  /// the result map (`fitsPath`, `pngPath`, coverage stats). The cutout is
  /// written under the atlas cache, keyed by the cone geometry.
  Future<Map<String, dynamic>> cutout({
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
    int channels = 1,
    int outPixels = 2048,
    AtlasInterp interp = AtlasInterp.lanczos3,
    bool withPng = true,
    bool includeSwarm = false,
  }) async {
    final root = await atlasRoot();
    final stem =
        'cutout_${centerRaDeg.toStringAsFixed(3)}_'
        '${centerDecDeg.toStringAsFixed(3)}_${radiusDeg.toStringAsFixed(3)}';
    final fitsPath = p.join(_cacheDir(root), '$stem.fits');
    final pngPath = p.join(_cacheDir(root), '$stem.png');
    final args = <String, dynamic>{
      'atlasRoot': root,
      'order': _order,
      'centerRa': centerRaDeg,
      'centerDec': centerDecDeg,
      'radiusDeg': radiusDeg,
      'channels': channels,
      'outPixels': outPixels,
      'interp': interp.wire,
      'fitsPath': fitsPath,
      if (withPng) 'pngPath': pngPath,
      // VIEW co-add: composite the swarm overlay on top of own-light for DISPLAY
      // only. Never set by the contribute/export path — exportDelta never reads
      // the overlay tree at all, so a community photon cannot leak into a push.
      'includeOverlay': includeSwarm,
    };
    return _seam.queryCutout(args);
  }

  /// Per-tile coverage rows for the heat overlay / gallery, deepest first.
  ///
  /// [includeSwarm] composites the pulled community overlay depth for DISPLAY
  /// only (threaded as `includeOverlay`); it never affects the export path.
  Future<List<AtlasTileCoverage>> coverage({bool includeSwarm = false}) async {
    final root = await atlasRoot();
    final result = await _seam.dispatch({
      'action': 'coverage',
      'atlasRoot': root,
      'order': _order,
      'includeOverlay': includeSwarm,
    });
    final tiles =
        (result['tiles'] as List? ?? const [])
            .map((e) => AtlasTileCoverage.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort(
            (a, b) => b.integrationSeconds.compareTo(a.integrationSeconds),
          );
    return tiles;
  }

  /// Provenance for one tile (contributors + fold log).
  Future<TileProvenanceView> tileInfo(int tileId) async {
    final root = await atlasRoot();
    final result = await _seam.dispatch({
      'action': 'info',
      'atlasRoot': root,
      'order': _order,
      'tileId': tileId,
    });
    return TileProvenanceView.fromJson(tileId, result);
  }

  /// Export the accumulator state for the LOCAL folds since [since] to a `.nst`
  /// delta under the atlas cache (the federation contribution payload).
  ///
  /// Returns the delta path together with the post-anchor own-light tally the
  /// native side carved out ([AtlasDeltaExport.framesInDelta] /
  /// [AtlasDeltaExport.integrationSeconds]) — these are the TRUE delta the
  /// high-water contribute flow ships, never the whole accumulator and never
  /// pulled (foreign) community depth. The native side rejects a tile that mixes
  /// pre-anchor own folds with new own folds (an inseparable pixel-exact delta).
  Future<AtlasDeltaExport> exportDelta(
    int tileId, {
    required DateTime since,
  }) async {
    final root = await atlasRoot();
    final outPath = p.join(_cacheDir(root), 'delta_$tileId.nst');
    final result = await _seam.dispatch({
      'action': 'exportDelta',
      'atlasRoot': root,
      'order': _order,
      'tileId': tileId,
      'sinceIso': since.toUtc().toIso8601String(),
      'outPath': outPath,
    });
    return AtlasDeltaExport(
      path: result['outPath'] as String? ?? outPath,
      framesInDelta: (result['framesInDelta'] as num?)?.toInt() ?? 0,
      integrationSeconds:
          (result['integrationSeconds'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// The deepening growth curve for a region cone (raw bridge result map).
  Future<Map<String, dynamic>> growth({
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
  }) async {
    final root = await atlasRoot();
    return _seam.growth({
      'atlasRoot': root,
      'order': _order,
      'centerRa': centerRaDeg,
      'centerDec': centerDecDeg,
      'radiusDeg': radiusDeg,
    });
  }

  /// Native coverage summary for a region cone (raw bridge result map).
  Future<Map<String, dynamic>> regionCoverage({
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
  }) async {
    final root = await atlasRoot();
    return _seam.regionInfo({
      'atlasRoot': root,
      'order': _order,
      'centerRa': centerRaDeg,
      'centerDec': centerDecDeg,
      'radiusDeg': radiusDeg,
    });
  }

  // --- Regions ------------------------------------------------------------

  /// All persisted regions (newest first).
  Future<List<SkyAtlasRegionRow>> regions() => _dao.getAllRegions();

  /// Reactive region list for the atlas browser.
  Stream<List<SkyAtlasRegionRow>> watchRegions() => _dao.watchAllRegions();

  /// Insert-or-update a named region and refresh its denormalized rollups.
  /// Returns the region row id.
  Future<int> ensureRegion({
    required String name,
    required double centerRaDeg,
    required double centerDecDeg,
    required double radiusDeg,
    String kind = 'custom',
    int? targetId,
  }) async {
    final id = await _dao.upsertRegion(
      name: name,
      kind: kind,
      centerRaDeg: centerRaDeg,
      centerDecDeg: centerDecDeg,
      radiusDeg: radiusDeg,
      targetId: targetId,
    );
    await _dao.refreshRegionRollups(id);
    return id;
  }

  /// The fold timeline for a region, oldest first — backs the time scrubber.
  Future<List<SkyAtlasFoldRow>> regionTimeline(int regionId) =>
      _dao.listFoldsForRegionOverTime(regionId);

  /// Reactive region timeline for a live scrubber.
  Stream<List<SkyAtlasFoldRow>> watchRegionTimeline(int regionId) =>
      _dao.watchFoldsForRegionOverTime(regionId);

  // --- Internals ----------------------------------------------------------

  /// Mirror a native fold result into the atlas tables.
  ///
  /// For each touched tile we upsert the [SkyTiles] index row (running totals +
  /// the on-disk sidecar pointer the native side owns) and append a
  /// [SkyAtlasFolds] timeline row carrying what that tile gained. The
  /// region a tile already belongs to is preserved by the DAO upsert; folds
  /// link back to [sessionId] so the timeline replays per session.
  /// Blend a pulled community `.nst` accumulator into the swarm OVERLAY tree so
  /// its depth can surface in "Your Sky" — without ever touching the user's
  /// contributable base tile.
  ///
  /// The overlay is a SEPARATE sidecar tree (`swarm_overlay/<order>/<tileId>.nst`)
  /// that [exportDelta] never reads, so pulled community photons can never be
  /// re-shipped as the user's own contribution. Each pull is a fresh full-tile
  /// community snapshot, so the merge is REPLACE-not-add: the existing overlay
  /// sidecar is removed first and the snapshot merged into an empty accumulator,
  /// leaving the overlay equal to exactly one copy of the current community
  /// depth (N pulls == 1 pull). The base [SkyTiles] index row keeps its
  /// own-light `totalFrames`/`integrationSeconds`; the blended community depth is
  /// written to the dedicated overlay columns so the contribution bar stays
  /// honest after a pull.
  ///
  /// Returns the overlay's (community) frame total for the tile.
  Future<int> mergeSwarmDelta({
    required int tileId,
    required String deltaPath,
    double trust = 1.0,
  }) {
    return _serialized(() async {
      final root = await atlasRoot();
      final basePath = p.join(_tilesDir(root), '$tileId.nst');
      final overlayPath = p.join(_overlayDir(root), '$tileId.nst');

      // REPLACE-not-add: drop any prior overlay so the merge folds the freshly
      // pulled community snapshot into a zeroed accumulator — the overlay always
      // equals exactly one copy of the current community depth.
      final overlayFile = File(overlayPath);
      if (overlayFile.existsSync()) {
        try {
          overlayFile.deleteSync();
        } on FileSystemException catch (e) {
          _logger.warning(
            'mergeSwarmDelta(tile $tileId): could not clear prior overlay '
            '($e); blend may double-count this pull.',
            source: _logSource,
          );
        }
      }

      final result = await _seam.mergeDelta({
        'basePath': overlayPath,
        'deltaPath': deltaPath,
        'trust': trust,
        'subtract': false,
        'outPath': overlayPath,
      });
      final overlayFrames = (result['totalFramesAfter'] as num?)?.toInt() ?? 0;
      final overlaySeconds =
          (result['integrationSecondsAfter'] as num?)?.toDouble() ?? 0.0;
      final contributors = (result['contributorsAfter'] as num?)?.toInt() ?? 0;

      // Refresh ONLY the overlay columns on the base index row; own-light
      // totals + the base sidecar pointer are preserved. If the user has never
      // imaged this tile there is no base row yet, so we seed one from the
      // overlay's geometry (centre/channels via tileInfo on the overlay), but
      // still with zero own-light totals.
      try {
        final existing = await _dao.getTile(tileId, healpixOrder: _order);
        if (existing != null) {
          await _dao.upsertTile(
            tileId: tileId,
            healpixOrder: _order,
            channels: existing.channels,
            centerRaDeg: existing.centerRaDeg,
            centerDecDeg: existing.centerDecDeg,
            coverageMean: existing.coverageMean,
            totalFrames: existing.totalFrames,
            integrationSeconds: existing.integrationSeconds,
            sidecarPath: existing.sidecarPath,
            lastFoldSessionId: existing.lastFoldSessionId,
            lastFoldAt: existing.lastFoldAt,
            regionId: existing.regionId,
            swarmOverlayFrames: overlayFrames,
            swarmOverlayIntegrationSeconds: overlaySeconds,
          );
        } else {
          final info = await _overlayTileInfo(tileId);
          await _dao.upsertTile(
            tileId: tileId,
            healpixOrder: _order,
            channels: info.channels,
            centerRaDeg: info.centerRaDeg,
            centerDecDeg: info.centerDecDeg,
            coverageMean: info.coverageMean,
            // No own-light yet — keep base totals at zero so the contribution
            // bar reads "nothing to contribute" until the user images here.
            totalFrames: 0,
            integrationSeconds: 0,
            sidecarPath: basePath,
            lastFoldSessionId: null,
            lastFoldAt: null,
            swarmOverlayFrames: overlayFrames,
            swarmOverlayIntegrationSeconds: overlaySeconds,
          );
        }
      } catch (e) {
        _logger.warning(
          'mergeSwarmDelta(tile $tileId): overlay index refresh failed: $e '
          '(overlay persisted, $contributors contributor(s)).',
          source: _logSource,
        );
      }
      return overlayFrames;
    });
  }

  /// Provenance for the overlay sidecar at [overlayPath] (geometry/coverage only,
  /// used to seed a base index row for a never-imaged-locally pulled tile).
  Future<TileProvenanceView> _overlayTileInfo(int tileId) async {
    final root = await atlasRoot();
    final result = await _seam.dispatch({
      'action': 'info',
      'atlasRoot': _overlayRoot(root),
      'order': _order,
      'tileId': tileId,
    });
    return TileProvenanceView.fromJson(tileId, result);
  }

  Future<void> _persistFold({
    required AtlasFoldSummary summary,
    required int sessionId,
    required String label,
    required String contributor,
    required String root,
  }) async {
    final foldedAt = DateTime.now();
    final tilesDir = _tilesDir(root);
    final linkedSession = sessionId > 0 ? sessionId : null;
    for (final tile in summary.tiles) {
      final sidecarPath = p.join(tilesDir, '${tile.tileId}.nst');
      await _dao.upsertTile(
        tileId: tile.tileId,
        healpixOrder: _order,
        channels: tile.channels,
        centerRaDeg: tile.centerRaDeg,
        centerDecDeg: tile.centerDecDeg,
        coverageMean: tile.coverageMean,
        totalFrames: tile.totalFrames,
        integrationSeconds: tile.integrationSeconds,
        sidecarPath: sidecarPath,
        lastFoldSessionId: linkedSession,
        lastFoldAt: foldedAt,
      );
      await _dao.recordFold(
        tileId: tile.tileId,
        healpixOrder: _order,
        sessionId: linkedSession,
        framesAdded: tile.framesAdded,
        weightAdded: tile.weightAdded,
        integrationSecondsAdded: _integrationDeltaFor(tile),
        rejected: tile.rejected,
        contributor: contributor,
        label: label,
        foldedAt: foldedAt,
      );
    }
  }

  /// Per-fold integration delta. The bridge's per-tile summary reports the
  /// post-fold cumulative `integrationSeconds`; the timeline wants the increment
  /// this fold added. We derive it from the prior tile total when available,
  /// falling back to the cumulative value for a tile's very first fold.
  double _integrationDeltaFor(AtlasFoldTile tile) {
    // The native running total includes this fold; for the first fold of a tile
    // that equals the increment. For subsequent folds we do not have the prior
    // total in the summary, so we attribute the proportional share by frame
    // count when frames are known, else the full cumulative (first-fold case).
    if (tile.totalFrames <= 0 || tile.framesAdded >= tile.totalFrames) {
      return tile.integrationSeconds;
    }
    final perFrame = tile.integrationSeconds / tile.totalFrames;
    return perFrame * tile.framesAdded;
  }

  String _tilesDir(String root) => p.join(root, 'tiles', '$_order');

  /// The swarm OVERLAY sidecar directory. A SEPARATE tree from the own-light
  /// base ([_tilesDir]) that [exportDelta] never reads, so pulled community
  /// depth can never re-upload as the user's contribution. It mirrors the base
  /// `tiles/<order>` layout under a `swarm_overlay` root so the native
  /// `open_atlas` read path (`info`) resolves an overlay sidecar when handed
  /// `<root>/swarm_overlay` as its atlas root.
  String _overlayDir(String root) =>
      p.join(_overlayRoot(root), 'tiles', '$_order');

  /// The atlas root the overlay tree presents to the native `open_atlas`.
  String _overlayRoot(String root) => p.join(root, 'swarm_overlay');

  String _cacheDir(String root) => p.join(root, 'cache');
}

/// The result of [SkyAtlasService.exportDelta]: the written `.nst` delta path
/// plus the post-anchor own-light tally carved out for the federation push.
class AtlasDeltaExport {
  /// On-disk path of the exported `.nst` delta accumulator.
  final String path;

  /// Frames attributable to LOCAL folds strictly after the export anchor — the
  /// true delta to advertise to the hub (0 when nothing new has been imaged).
  final int framesInDelta;

  /// Integration seconds attributable to those same post-anchor own folds.
  final double integrationSeconds;

  const AtlasDeltaExport({
    required this.path,
    required this.framesInDelta,
    required this.integrationSeconds,
  });

  /// Whether this export carries new own-light to contribute.
  bool get isEmpty => framesInDelta <= 0;
}

/// Default atlas root: `<app support>/sky_atlas`. The native fold creates the
/// per-tile sidecar directories on demand, so we only need the root to exist.
Future<String> defaultAtlasRoot() async {
  final support = await getApplicationSupportDirectory();
  return p.join(support.path, 'sky_atlas');
}
