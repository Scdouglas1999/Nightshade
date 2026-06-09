import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/images_dao.dart';
import '../database/daos/integrated_masters_dao.dart';
import '../database/daos/mosaic_panels_dao.dart';
import '../database/daos/mosaic_projects_dao.dart';
import '../database/database.dart' show CapturedImage;
import '../models/imaging/integrated_master.dart';
import '../models/imaging/integration_settings.dart';
import '../models/imaging/mosaic_project.dart';
import '../models/imaging/mosaic_stitch_result.dart';
import '../providers/database_provider.dart';
import 'mosaic_service.dart';
import 'post_session_integration_service.dart';
import 'post_session_seam.dart';

/// One panel's outcome from [MosaicProjectService.integratePanels] — what the
/// caller (and the morning-report UI) needs to show per-panel progress without
/// re-reading the DB.
class MosaicPanelIntegrationOutcome {
  /// The `mosaic_panels.id` this outcome describes.
  final int panelId;

  /// The panel's 0-based grid index (matches the FITS `NS-PIDX` provenance).
  final int panelIndex;

  /// The per-panel `integrated_masters.id` produced, or null when the panel was
  /// skipped (no subs) or failed.
  final int? integratedMasterId;

  /// The panel's terminal status after this run
  /// ([MosaicPanelStatus.integrated] / [MosaicPanelStatus.failed] /
  /// [MosaicPanelStatus.pending] when skipped for want of subs).
  final MosaicPanelStatus status;

  /// Number of accepted subs that fed the panel's integration.
  final int subCount;

  /// A human-readable note when the panel was skipped or failed (null on
  /// success). Surfaced so the report can explain a weak/missing panel.
  final String? note;

  const MosaicPanelIntegrationOutcome({
    required this.panelId,
    required this.panelIndex,
    required this.integratedMasterId,
    required this.status,
    required this.subCount,
    this.note,
  });

  /// True when the panel produced a per-panel master this run.
  bool get integrated => integratedMasterId != null;
}

/// Orchestrates a **durable mosaic project** end-to-end (Mosaic M2): lay out the
/// grid into per-panel rows, integrate each panel's captured subs into a
/// per-panel master, then stitch those masters into one mosaic master.
///
/// This service is the durable spine that ties together pieces that already
/// exist — it deliberately reuses, never reimplements:
///
///  * **Geometry** — the per-panel center RA/Dec come straight from
///    [MosaicService.generatePanels] (the canonical spherical grid math with
///    cos(dec) RA compression + position-angle rotation). The panel dimensions
///    are derived once from the rig FOV (arcmin) and handed to that generator.
///  * **Persistence** — [MosaicProjectsDao] / [MosaicPanelsDao] (raw-DDL v45).
///  * **Per-panel integration** — [PostSessionIntegrationService.integrate],
///    which groups a panel's accepted subs by filter into per-filter masters,
///    each carrying its own plate-solved v44 WCS. (Because each panel is a real
///    target, its WCS rides on `integrated_masters` for free — exactly what the
///    stitcher consumes.)
///  * **Stitching** — [PostSessionSeam.stitchMosaic] (the `api_stitch_mosaic`
///    FFI), which projects the panel masters onto a shared gnomonic canvas and
///    feather-blends them into one master.
///
/// [integratePanels] is fail-soft per panel: one bad panel (no subs, an
/// integration throw) is recorded as [MosaicPanelStatus.failed] and the run
/// continues to the next panel, so a single weak panel never sinks the project.
class MosaicProjectService {
  MosaicProjectService({
    required MosaicProjectsDao projectsDao,
    required MosaicPanelsDao panelsDao,
    required ImagesDao imagesDao,
    required IntegratedMastersDao mastersDao,
    required PostSessionIntegrationService integrationService,
    required PostSessionSeam seam,
    MosaicService geometry = const MosaicService(),
  })  : _projectsDao = projectsDao,
        _panelsDao = panelsDao,
        _imagesDao = imagesDao,
        _mastersDao = mastersDao,
        _integration = integrationService,
        _seam = seam,
        _geometry = geometry;

  final MosaicProjectsDao _projectsDao;
  final MosaicPanelsDao _panelsDao;
  final ImagesDao _imagesDao;
  final IntegratedMastersDao _mastersDao;
  final PostSessionIntegrationService _integration;
  final PostSessionSeam _seam;
  final MosaicService _geometry;

  // ---------------------------------------------------------------------------
  // 1. Plan — lay the grid out into a durable project + per-panel rows.
  // ---------------------------------------------------------------------------

  /// Create a durable mosaic project: persist a `mosaic_projects` row, compute
  /// each panel's center RA/Dec from the grid geometry, and persist one
  /// `mosaic_panels` row per `rows × cols` panel (0-based [MosaicProjectPanel]
  /// index, row-major).
  ///
  /// The per-panel centers are computed by [MosaicService.generatePanels] — the
  /// existing spherical-grid math — NOT re-derived here. The panel dimensions it
  /// needs are derived from the rig field of view: pass either an explicit
  /// [panelWidthArcmin]/[panelHeightArcmin], or [fovWidthDeg]/[fovHeightDeg]
  /// (degrees, e.g. `FramingEquipment.fovWidthDeg`) which are converted to
  /// arcmin.
  ///
  /// [centerRa] is in RA hours, [centerDec] in degrees — matching
  /// [MosaicConfig] and the [MosaicProjectPanel] units. Each panel can carry a
  /// per-panel capture [panelTargetId] (so the existing campaigns / integration
  /// goals attach to it); when omitted it inherits the project's [targetId].
  ///
  /// Returns the new `mosaic_projects.id`.
  Future<int> createProject({
    required String name,
    required int rows,
    required int cols,
    required double centerRa,
    required double centerDec,
    int? targetId,
    double overlapPct = 15.0,
    double positionAngleDeg = 0.0,
    double? panelWidthArcmin,
    double? panelHeightArcmin,
    double? fovWidthDeg,
    double? fovHeightDeg,
    int? Function(int panelIndex)? panelTargetId,
  }) async {
    if (rows < 1 || cols < 1) {
      throw ArgumentError('mosaic grid must be at least 1x1 (got ${rows}x$cols)');
    }
    final widthArcmin = panelWidthArcmin ??
        (fovWidthDeg != null ? fovWidthDeg * 60.0 : null);
    final heightArcmin = panelHeightArcmin ??
        (fovHeightDeg != null ? fovHeightDeg * 60.0 : null);
    if (widthArcmin == null || heightArcmin == null) {
      throw ArgumentError(
        'panel dimensions are required: pass panelWidthArcmin/'
        'panelHeightArcmin or fovWidthDeg/fovHeightDeg',
      );
    }
    if (widthArcmin <= 0 || heightArcmin <= 0) {
      throw ArgumentError('panel dimensions must be positive');
    }

    // Reuse the canonical spherical grid math (cos(dec) RA compression + PA
    // rotation). `MosaicConfig` uses `panelsHorizontal = cols`, `panelsVertical
    // = rows`; its generated `MosaicPanel.panelIndex` is row-major 0-based,
    // exactly the durable panel index.
    final config = MosaicConfig(
      centerRa: centerRa,
      centerDec: centerDec,
      panelWidthArcmin: widthArcmin,
      panelHeightArcmin: heightArcmin,
      overlapPercent: overlapPct,
      rotation: positionAngleDeg,
      panelsHorizontal: cols,
      panelsVertical: rows,
    );
    final panels = _geometry.generatePanels(config);

    final projectId = await _projectsDao.create(
      targetId: targetId,
      name: name,
      rows: rows,
      cols: cols,
      overlapPct: overlapPct,
      positionAngleDeg: positionAngleDeg,
    );

    for (final panel in panels) {
      await _panelsDao.upsert(
        projectId: projectId,
        panelIndex: panel.panelIndex,
        centerRa: panel.raHours,
        centerDec: panel.decDegrees,
        targetId: panelTargetId?.call(panel.panelIndex) ?? targetId,
      );
    }

    return projectId;
  }

  // ---------------------------------------------------------------------------
  // 2. Integrate — turn each panel's captured subs into a per-panel master.
  // ---------------------------------------------------------------------------

  /// Integrate every panel of [projectId]: for each panel, gather its accepted
  /// captured subs (by the panel's `target_id`), run the existing
  /// [PostSessionIntegrationService.integrate], and link the produced per-panel
  /// master onto `mosaic_panels.integrated_master_id`.
  ///
  /// **Fail-soft per panel.** A panel with no captured subs is left
  /// [MosaicPanelStatus.pending] (nothing to do yet); a panel whose integration
  /// throws is marked [MosaicPanelStatus.failed] and the loop moves on. One bad
  /// panel never aborts the rest.
  ///
  /// The project is moved to [MosaicProjectStatus.integrating] for the run and,
  /// when at least one panel integrated, on to a status reflecting completion of
  /// this phase. [outputFitsPathBuilder] maps a panel index to that panel's
  /// master FITS base path (the preview / rejection map are derived by extension
  /// swap inside the integration service). Returns one outcome per panel.
  Future<List<MosaicPanelIntegrationOutcome>> integratePanels(
    int projectId, {
    required IntegrationSettings settings,
    required String Function(MosaicProjectPanel panel) outputFitsPathBuilder,
  }) async {
    final project = await _projectsDao.getById(projectId);
    if (project == null) {
      throw ArgumentError('no mosaic project with id $projectId');
    }
    final panels = await _panelsDao.getForProject(projectId);
    if (panels.isEmpty) {
      throw StateError('mosaic project $projectId has no panels to integrate');
    }

    await _projectsDao.updateStatus(
        projectId, MosaicProjectStatus.integrating);

    final outcomes = <MosaicPanelIntegrationOutcome>[];
    for (final panel in panels) {
      outcomes.add(await _integratePanel(
        project: project,
        panel: panel,
        settings: settings,
        outputFitsPathBuilder: outputFitsPathBuilder,
      ));
    }
    return outcomes;
  }

  Future<MosaicPanelIntegrationOutcome> _integratePanel({
    required MosaicProject project,
    required MosaicProjectPanel panel,
    required IntegrationSettings settings,
    required String Function(MosaicProjectPanel panel) outputFitsPathBuilder,
  }) async {
    final panelId = panel.id;
    if (panelId == null) {
      // An unsaved panel cannot be linked — should never happen for a row read
      // back from the DAO, but stays honest rather than crashing the loop.
      return MosaicPanelIntegrationOutcome(
        panelId: -1,
        panelIndex: panel.panelIndex,
        integratedMasterId: null,
        status: MosaicPanelStatus.failed,
        subCount: 0,
        note: 'panel row has no id',
      );
    }

    // Each panel is a distinct capture target; fall back to the project target
    // when the panel did not carry its own.
    final captureTargetId = panel.targetId ?? project.targetId;
    if (captureTargetId == null) {
      await _panelsDao.updateStatus(panelId, MosaicPanelStatus.pending);
      return MosaicPanelIntegrationOutcome(
        panelId: panelId,
        panelIndex: panel.panelIndex,
        integratedMasterId: null,
        status: MosaicPanelStatus.pending,
        subCount: 0,
        note: 'panel has no capture target',
      );
    }

    try {
      final subs = await _acceptedSubsForTarget(captureTargetId);
      if (subs.isEmpty) {
        await _panelsDao.updateStatus(panelId, MosaicPanelStatus.pending);
        return MosaicPanelIntegrationOutcome(
          panelId: panelId,
          panelIndex: panel.panelIndex,
          integratedMasterId: null,
          status: MosaicPanelStatus.pending,
          subCount: 0,
          note: 'no accepted subs captured yet',
        );
      }

      final panelBase = outputFitsPathBuilder(panel);
      final outcomes = await _integration.integrate(
        subs: subs,
        settings: settings,
        targetId: captureTargetId,
        targetName: project.name.isEmpty
            ? 'Panel ${panel.panelIndex + 1}'
            : '${project.name} Panel ${panel.panelIndex + 1}',
        // Each per-filter master MUST get a distinct file: the integration
        // service derives the preview/.png + rejection map from this path and
        // overwrites the FITS in place, so handing every filter group the same
        // base path would have each filter clobber the previous filter's
        // artifacts on disk. Suffix the bucket (e.g. `panel_0_R.fits`) so an
        // L+R+G+B panel yields four distinct masters; the unfiltered bucket
        // keeps the bare base path so the single-filter path is unchanged.
        outputFitsPathBuilder: (bucket) =>
            bucket == PostSessionIntegrationService.noFilterBucket
                ? panelBase
                : _suffixBeforeExtension(panelBase, '_$bucket'),
        hintRaHours: panel.centerRa,
        hintDecDegrees: panel.centerDec,
      );

      // A panel is one sky region; the stitcher consumes a single master per
      // panel. When several filters were captured, pick a deliberate
      // representative (luminance if present, else the highest frame-count
      // outcome) rather than relying on filter-group iteration order, which is
      // merely the order of the first accepted sub per filter. The per-filter
      // masters all share the panel's WCS, so the representative's on-disk
      // pixels are the ones the stitcher will project. Link it and credit the
      // full accepted-sub count for the panel.
      final masterId = _representativeMasterId(outcomes);
      await _panelsDao.setMaster(panelId, masterId);
      await _panelsDao.incrementCaptured(panelId, delta: subs.length);

      return MosaicPanelIntegrationOutcome(
        panelId: panelId,
        panelIndex: panel.panelIndex,
        integratedMasterId: masterId,
        status: MosaicPanelStatus.integrated,
        subCount: subs.length,
      );
    } catch (e, st) {
      _logSoftFailure('integratePanel[${panel.panelIndex}]', e, st);
      await _panelsDao.updateStatus(panelId, MosaicPanelStatus.failed);
      return MosaicPanelIntegrationOutcome(
        panelId: panelId,
        panelIndex: panel.panelIndex,
        integratedMasterId: null,
        status: MosaicPanelStatus.failed,
        subCount: 0,
        note: 'integration failed: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Stitch — project the panel masters onto one shared canvas.
  // ---------------------------------------------------------------------------

  /// Stitch [projectId]'s integrated panels into one mosaic master.
  ///
  /// Gathers every panel that carries a per-panel master with a FITS path on
  /// disk, builds the `api_stitch_mosaic` request (each panel's `fitsPath` plus
  /// its persisted v44 CD-matrix `wcs` when present), calls
  /// [PostSessionSeam.stitchMosaic], persists the stitched output as a NEW
  /// `integrated_masters` row (with the returned canvas geometry), links it onto
  /// `mosaic_projects.output_master_id`, and marks the project
  /// [MosaicProjectStatus.complete].
  ///
  /// Output artifacts land under the project folder via [outputDirectory]
  /// (`<dir>/<project>_mosaic.fits` + `_coverage.fits` + `.png`). Requires at
  /// least two panels with masters; otherwise throws a clear [StateError]
  /// (one panel is not a mosaic).
  Future<MosaicStitchOutcome> stitchProject(
    int projectId, {
    required String outputDirectory,
    Map<String, dynamic>? stitchConfig,
  }) async {
    final project = await _projectsDao.getById(projectId);
    if (project == null) {
      throw ArgumentError('no mosaic project with id $projectId');
    }

    final panels = await _panelsDao.getForProject(projectId);
    final panelArgs = <Map<String, dynamic>>[];
    var contributingMasters = 0;
    for (final panel in panels) {
      final masterId = panel.integratedMasterId;
      if (masterId == null) continue;
      final master = await _mastersDao.getById(masterId);
      final fitsPath = master?.masterFitsPath;
      if (master == null || fitsPath == null || fitsPath.trim().isEmpty) {
        continue;
      }
      contributingMasters++;
      panelArgs.add(<String, dynamic>{
        'fitsPath': fitsPath,
        if (_wcsArgs(master) case final wcs?) 'wcs': wcs,
      });
    }

    if (contributingMasters < 2) {
      throw StateError(
        'mosaic project $projectId needs >= 2 panels with integrated masters '
        'to stitch (found $contributingMasters)',
      );
    }

    await _projectsDao.updateStatus(projectId, MosaicProjectStatus.stitching);

    final base = _join(outputDirectory, '${_slug(project.name)}_mosaic');
    final args = <String, dynamic>{
      'panels': panelArgs,
      if (stitchConfig != null) 'config': stitchConfig,
      'output': <String, dynamic>{
        'mosaicFitsPath': '$base.fits',
        'coverageFitsPath': '${base}_coverage.fits',
        'previewPngPath': '$base.png',
      },
    };

    final stitch = await _seam.stitchMosaic(args);

    // Persist the stitched mosaic as a first-class integrated master so it lands
    // in the master library + morning report unchanged, then link it.
    final masterId = await _mastersDao.insertMaster(
      targetId: project.targetId,
      name: '${project.name} · Mosaic',
      masterFitsPath: stitch.outputPath,
      previewPngPath: stitch.previewPath,
      sidecarPath: null,
      rejectionMapPath: null,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      width: stitch.outWidth,
      height: stitch.outHeight,
      frameCount: contributingMasters,
      statsJson: _stitchStatsJson(stitch, contributingMasters),
    );

    // The stitcher stamps the output-canvas WCS into the mosaic FITS header
    // (`api_stitch_mosaic`) but does not surface it in the JSON result, so the
    // mosaic master's DB WCS columns are populated later by the same
    // plate-solve/header-read path every other master uses — not from here.

    // setOutputMaster also flips status -> complete + bumps updated_at.
    await _projectsDao.setOutputMaster(projectId, masterId);

    return MosaicStitchOutcome(
      outputMasterId: masterId,
      panelCount: contributingMasters,
      result: stitch,
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers.
  // ---------------------------------------------------------------------------

  /// Choose the single per-panel master the stitcher will consume from the
  /// per-filter [outcomes] of one panel's integration.
  ///
  /// A panel is one sky region but may have been captured across several
  /// filters; the stitcher takes exactly one master per panel. The pick is
  /// deliberate (NOT iteration order, which is just the first-accepted-sub order
  /// of the filter groups): prefer luminance ('L', case-insensitive) when
  /// present — it is the broadest-band, highest-SNR frame and the natural
  /// stitch base — else the outcome with the most integrated frames (deepest,
  /// most reliable registration), tie-broken by the first such outcome.
  ///
  /// [outcomes] is always non-empty here: [PostSessionIntegrationService.integrate]
  /// throws on empty subs and yields one outcome per non-empty filter group.
  static int _representativeMasterId(
    List<PostSessionIntegrationOutcome> outcomes,
  ) {
    for (final outcome in outcomes) {
      if (outcome.filter?.trim().toUpperCase() == 'L') {
        return outcome.masterId;
      }
    }
    var best = outcomes.first;
    for (final outcome in outcomes.skip(1)) {
      if (outcome.result.framesIntegrated > best.result.framesIntegrated) {
        best = outcome;
      }
    }
    return best.masterId;
  }

  /// Accepted light subs for a capture target (the population the per-panel
  /// integration folds). Non-accepted subs are excluded so a panel's master is
  /// built only from frames that passed grading.
  Future<List<CapturedImage>> _acceptedSubsForTarget(int targetId) async {
    final all = await _imagesDao.getImagesForTarget(targetId);
    return all.where((s) => s.isAccepted).toList(growable: false);
  }

  /// The eight CD-matrix scalars as the `StitchMosaicArgs` `wcs` block, or null
  /// when the master has no persisted WCS (the native side then parses the FITS
  /// header instead). Mirrors the documented request shape.
  Map<String, dynamic>? _wcsArgs(IntegratedMaster master) {
    if (!master.hasWcs) return null;
    return <String, dynamic>{
      'crval1': master.wcsCrval1,
      'crval2': master.wcsCrval2,
      'crpix1': master.wcsCrpix1,
      'crpix2': master.wcsCrpix2,
      'cd1_1': master.wcsCd1_1,
      'cd1_2': master.wcsCd1_2,
      'cd2_1': master.wcsCd2_1,
      'cd2_2': master.wcsCd2_2,
    };
  }

  String _stitchStatsJson(MosaicStitchResult stitch, int panelCount) {
    return '{'
        '"panelCount":$panelCount,'
        '"overlapPairs":${stitch.overlapPairs},'
        '"meanPanelGain":${stitch.meanPanelGain},'
        '"outWidth":${stitch.outWidth},'
        '"outHeight":${stitch.outHeight}'
        '}';
  }

  /// A filesystem-safe slug of a project name for the output file stem.
  static String _slug(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'mosaic';
    return trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  }

  /// Insert [suffix] before the path's extension (`panel_0.fits` →
  /// `panel_0_R.fits`). If the file segment has no `.`, the suffix is appended.
  /// Mirrors `PostSessionIntegrationService`'s own derivation so the per-filter
  /// master base path lines up with the preview/.png + rejection-map siblings
  /// the integration service derives from it.
  static String _suffixBeforeExtension(String path, String suffix) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path$suffix';
    return '${path.substring(0, dot)}$suffix${path.substring(dot)}';
  }

  /// Join a directory and a file stem with a single separator, tolerating a
  /// trailing slash on the directory.
  static String _join(String dir, String name) {
    if (dir.isEmpty) return name;
    final trimmed = dir.endsWith('/') || dir.endsWith('\\')
        ? dir.substring(0, dir.length - 1)
        : dir;
    return '$trimmed/$name';
  }

  void _logSoftFailure(String step, Object error, StackTrace stackTrace) {
    developer.log(
      'mosaic project step "$step" failed (continuing)',
      name: 'MosaicProjectService',
      error: error,
      stackTrace: stackTrace,
      level: 900, // WARNING
    );
  }
}

/// The result of [MosaicProjectService.stitchProject] — the persisted mosaic
/// master id, how many panels contributed, and the raw native stitch result.
class MosaicStitchOutcome {
  /// The new `integrated_masters.id` for the stitched mosaic master (also set as
  /// the project's `output_master_id`).
  final int outputMasterId;

  /// How many panel masters were projected onto the canvas.
  final int panelCount;

  /// The decoded native stitch result (canvas geometry + diagnostics).
  final MosaicStitchResult result;

  const MosaicStitchOutcome({
    required this.outputMasterId,
    required this.panelCount,
    required this.result,
  });
}

/// Provider for [MosaicProjectService], wiring the v45 mosaic DAOs, the images
/// DAO, the integrated-masters DAO, the post-session integration service, and
/// the post-session seam (which carries `stitchMosaic`).
final mosaicProjectServiceProvider = Provider<MosaicProjectService>((ref) {
  return MosaicProjectService(
    projectsDao: ref.watch(mosaicProjectsDaoProvider),
    panelsDao: ref.watch(mosaicPanelsDaoProvider),
    imagesDao: ref.watch(imagesDaoProvider),
    mastersDao: ref.watch(integratedMastersDaoProvider),
    integrationService: ref.watch(postSessionIntegrationServiceProvider),
    seam: ref.watch(postSessionSeamProvider),
  );
});
