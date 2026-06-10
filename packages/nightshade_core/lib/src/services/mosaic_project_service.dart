import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/images_dao.dart';
import '../database/daos/integrated_masters_dao.dart';
import '../database/daos/mosaic_panels_dao.dart';
import '../database/daos/mosaic_projects_dao.dart';
import '../database/daos/targets_dao.dart';
import '../database/database.dart'
    show CapturedImage, NightshadeDatabase, TargetsCompanion;
import '../models/imaging/integrated_master.dart';
import '../models/imaging/integration_settings.dart';
import '../models/imaging/mosaic_project.dart';
import '../models/imaging/mosaic_stitch_result.dart';
import '../providers/database_provider.dart';
import 'mosaic_service.dart';
import 'post_session_integration_service.dart';
import 'post_session_seam.dart';

/// What [MosaicProjectService.startCapture] hands the app layer so it can build
/// the per-panel mosaic sequence and load it into the executor.
///
/// The service lives in `nightshade_core` and deliberately owns NO reference to
/// the app-layer `currentSequenceProvider` / `sequenceExecutorProvider`. Instead
/// it resolves the durable per-panel capture targets and the project geometry,
/// then hands them to this launcher — the app controller wires the real
/// [MosaicService.createMosaicSequence] (stamping each panel's
/// `TargetHeaderNode.catalogTargetId` from [panelTargetIds]) and starts the run.
typedef MosaicCaptureLauncher =
    Future<void> Function(MosaicCaptureRequest request);

/// The durable inputs [MosaicProjectService.startCapture] resolved for one
/// capture run — everything the launcher needs to build a per-panel-target
/// mosaic sequence without re-reading the DB.
class MosaicCaptureRequest {
  /// The project being launched.
  final MosaicProject project;

  /// The project's panels, ordered by `panel_index`.
  final List<MosaicProjectPanel> panels;

  /// Per-panel capture target ids keyed by 0-based `panel_index`. Every panel
  /// has a DISTINCT entry (the service guarantees this), so the launcher can
  /// stamp each panel's `TargetHeaderNode.catalogTargetId` and the subs each
  /// panel captures attribute to its own target.
  final Map<int, int> panelTargetIds;

  const MosaicCaptureRequest({
    required this.project,
    required this.panels,
    required this.panelTargetIds,
  });
}

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

/// One panel's outcome from [MosaicProjectService.stitchProject]'s contribution
/// gate — surfaced so the UI/report can explain a panel the stitcher SKIPPED
/// (no master, no FITS on disk, or no WCS) instead of silently dropping it.
class MosaicPanelStitchSkip {
  /// The skipped panel's 0-based grid index.
  final int panelIndex;

  /// The panel's `integrated_masters.id`, or null when it had no master at all.
  final int? integratedMasterId;

  /// Why the panel was not handed to the stitcher.
  final String reason;

  const MosaicPanelStitchSkip({
    required this.panelIndex,
    required this.integratedMasterId,
    required this.reason,
  });
}

/// Orchestrates a **durable mosaic project** end-to-end (Mosaic M2): lay out the
/// grid into per-panel rows each with its OWN capture target, launch capture of
/// the per-panel-target sequence, integrate each panel's captured subs into a
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
///  * **Per-panel targets** — [TargetsDao]: each panel is a DISTINCT capture
///    target row centered on the panel's RA/Dec, so the subs a panel captures
///    attribute to *that* panel (and [integratePanels] folds exactly that
///    panel's subs, never the whole region's).
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
    required NightshadeDatabase db,
    required MosaicProjectsDao projectsDao,
    required MosaicPanelsDao panelsDao,
    required TargetsDao targetsDao,
    required ImagesDao imagesDao,
    required IntegratedMastersDao mastersDao,
    required PostSessionIntegrationService integrationService,
    required PostSessionSeam seam,
    MosaicService geometry = const MosaicService(),
  }) : _db = db,
       _projectsDao = projectsDao,
       _panelsDao = panelsDao,
       _targetsDao = targetsDao,
       _imagesDao = imagesDao,
       _mastersDao = mastersDao,
       _integration = integrationService,
       _seam = seam,
       _geometry = geometry;

  final NightshadeDatabase _db;
  final MosaicProjectsDao _projectsDao;
  final MosaicPanelsDao _panelsDao;
  final TargetsDao _targetsDao;
  final ImagesDao _imagesDao;
  final IntegratedMastersDao _mastersDao;
  final PostSessionIntegrationService _integration;
  final PostSessionSeam _seam;
  final MosaicService _geometry;

  // ---------------------------------------------------------------------------
  // 1. Plan — lay the grid out into a durable project + per-panel rows, each
  //    with its OWN distinct capture target.
  // ---------------------------------------------------------------------------

  /// Create a durable mosaic project: persist a `mosaic_projects` row, compute
  /// each panel's center RA/Dec from the grid geometry, create one DISTINCT
  /// per-panel capture `targets` row centered on that panel, and persist one
  /// `mosaic_panels` row per `rows × cols` panel (0-based [MosaicProjectPanel]
  /// index, row-major) carrying its per-panel `target_id`.
  ///
  /// The per-panel centers are computed by [MosaicService.generatePanels] — the
  /// existing spherical-grid math — NOT re-derived here. The panel dimensions it
  /// needs are derived from the rig field of view: pass either an explicit
  /// [panelWidthArcmin]/[panelHeightArcmin], or [fovWidthDeg]/[fovHeightDeg]
  /// (degrees, e.g. `FramingEquipment.fovWidthDeg`) which are converted to
  /// arcmin.
  ///
  /// [centerRa] is in RA hours, [centerDec] in degrees — matching
  /// [MosaicConfig] and the [MosaicProjectPanel] units.
  ///
  /// Each panel gets its OWN capture target so its subs are isolated for
  /// [integratePanels]. By default the service CREATES one `targets` row per
  /// panel (named `"<project> Panel N"`, centered on the panel's RA/Dec); pass
  /// [panelTargetId] to override — return an existing `targets.id` for a panel
  /// to reuse it (e.g. a resumed project), or null to fall back to a freshly
  /// created per-panel target. Two panels resolving to the same id is rejected
  /// later by [integratePanels]/[startCapture] (panels must not share subs).
  ///
  /// The whole insert (project + per-panel targets + panels) runs in ONE
  /// transaction: a failure midway leaves no half-built project.
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
      throw ArgumentError(
        'mosaic grid must be at least 1x1 (got ${rows}x$cols)',
      );
    }
    final widthArcmin =
        panelWidthArcmin ?? (fovWidthDeg != null ? fovWidthDeg * 60.0 : null);
    final heightArcmin =
        panelHeightArcmin ??
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

    // The whole layout — project row, per-panel target rows, panel rows — is a
    // single unit. If anything throws midway, the transaction rolls back so we
    // never leave a project with a partial panel/target set.
    return _db.transaction(() async {
      final projectId = await _projectsDao.create(
        targetId: targetId,
        name: name,
        rows: rows,
        cols: cols,
        overlapPct: overlapPct,
        positionAngleDeg: positionAngleDeg,
      );

      for (final panel in panels) {
        // Each panel is a DISTINCT capture target. Honor a caller override when
        // it returns a non-null id; otherwise create a fresh per-panel target
        // centered on the panel so its subs are isolated for integration.
        final overrideId = panelTargetId?.call(panel.panelIndex);
        final panelTarget =
            overrideId ??
            await _createPanelTarget(projectName: name, panel: panel);
        await _panelsDao.upsert(
          projectId: projectId,
          panelIndex: panel.panelIndex,
          centerRa: panel.raHours,
          centerDec: panel.decDegrees,
          targetId: panelTarget,
        );
      }

      return projectId;
    });
  }

  /// Create a `targets` row for one panel, centered on the panel's RA/Dec, and
  /// return its id. The panel target is what subsequent capture + integration
  /// attribute to, so each panel folds only its own frames.
  Future<int> _createPanelTarget({
    required String projectName,
    required MosaicPanel panel,
  }) {
    final baseName = projectName.trim().isEmpty ? 'Mosaic' : projectName.trim();
    return _targetsDao.createTarget(
      TargetsCompanion.insert(
        name: '$baseName Panel ${panel.panelIndex + 1}',
        ra: panel.raHours,
        dec: panel.decDegrees,
        objectType: const Value('mosaic-panel'),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Capture — launch the per-panel-target mosaic sequence into the executor.
  // ---------------------------------------------------------------------------

  /// LAUNCH capture for [projectId]: resolve each panel's distinct capture
  /// target, hand the app layer a [MosaicCaptureRequest] so it can build the
  /// per-panel-target mosaic sequence (via
  /// [MosaicService.createMosaicSequence], stamping each panel's
  /// `TargetHeaderNode.catalogTargetId`) and load it into the executor, then
  /// drive the project + panels into the capturing state.
  ///
  /// The per-panel target map is REQUIRED to be fully populated and DISTINCT —
  /// every panel must carry its own `target_id` (so a panel's subs attribute to
  /// that panel and only that panel). A missing per-panel target, or two panels
  /// sharing one, is a [StateError]: it would silently make several panels fold
  /// the SAME subs and is exactly the bug this durable project exists to avoid.
  ///
  /// Returns the resolved [MosaicCaptureRequest] (after the launcher accepts the
  /// run) so callers can inspect/log the per-panel target map.
  Future<MosaicCaptureRequest> startCapture(
    int projectId, {
    required MosaicCaptureLauncher launcher,
  }) async {
    final project = await _projectsDao.getById(projectId);
    if (project == null) {
      throw ArgumentError('no mosaic project with id $projectId');
    }
    final panels = await _panelsDao.getForProject(projectId);
    if (panels.isEmpty) {
      throw StateError('mosaic project $projectId has no panels to capture');
    }

    // Resolve + validate the per-panel target map: every panel distinct.
    final panelTargetIds = _resolveDistinctPanelTargets(projectId, panels);

    final request = MosaicCaptureRequest(
      project: project,
      panels: panels,
      panelTargetIds: panelTargetIds,
    );

    // Hand the per-panel sequence off to the launcher (app layer builds the
    // sequence + loads the executor). Only AFTER it accepts do we flip state —
    // a launcher throw leaves the project untouched.
    await launcher(request);

    await _projectsDao.updateStatus(projectId, MosaicProjectStatus.capturing);
    for (final panel in panels) {
      final panelId = panel.id;
      if (panelId == null) continue;
      // Already-integrated panels keep their terminal state; the rest are now
      // actively capturing.
      if (panel.status == MosaicPanelStatus.integrated) continue;
      await _panelsDao.updateStatus(panelId, MosaicPanelStatus.capturing);
    }

    return request;
  }

  /// Build the `panel_index -> target_id` map for a project and assert every
  /// panel carries a DISTINCT capture target. A missing or shared target is a
  /// [StateError] — several panels folding the same subs is the precise bug the
  /// durable per-panel-target model prevents.
  Map<int, int> _resolveDistinctPanelTargets(
    int projectId,
    List<MosaicProjectPanel> panels,
  ) {
    final byIndex = <int, int>{};
    final seen = <int, int>{}; // targetId -> first panelIndex that used it.
    for (final panel in panels) {
      final targetId = panel.targetId;
      if (targetId == null) {
        throw StateError(
          'mosaic project $projectId panel ${panel.panelIndex} has no capture '
          'target — every panel must carry its own target_id',
        );
      }
      final priorPanel = seen[targetId];
      if (priorPanel != null) {
        throw StateError(
          'mosaic project $projectId panels $priorPanel and ${panel.panelIndex} '
          'resolve to the SAME capture target ($targetId); panels must not '
          'share a target or they would fold each other\'s subs',
        );
      }
      seen[targetId] = panel.panelIndex;
      byIndex[panel.panelIndex] = targetId;
    }
    return byIndex;
  }

  // ---------------------------------------------------------------------------
  // 3. Integrate — turn each panel's captured subs into a per-panel master.
  // ---------------------------------------------------------------------------

  /// Integrate every panel of [projectId]: for each panel, gather its accepted
  /// captured subs (by the panel's `target_id`), run the existing
  /// [PostSessionIntegrationService.integrate], and link the produced per-panel
  /// master onto `mosaic_panels.integrated_master_id`.
  ///
  /// **Distinct-target guard.** Before integrating, the panels' targets are
  /// validated to be distinct (every panel has its own `target_id`, none
  /// shared) — two panels resolving to the same target would fold identical
  /// subs into "different" panels, which is never correct.
  ///
  /// **Fail-soft per panel.** A panel with no captured subs is left
  /// [MosaicPanelStatus.pending] (nothing to do yet); a panel whose integration
  /// throws is marked [MosaicPanelStatus.failed], has its
  /// `integrated_master_id` cleared, and the loop moves on. One bad panel never
  /// aborts the rest.
  ///
  /// **Re-integration is idempotent.** When a panel already carried a master,
  /// its previous `integrated_masters` row AND its on-disk FITS/preview/rejmap
  /// are superseded (deleted) before the fresh master is linked, so a re-run
  /// never leaves an orphan master/file behind, and `captured_count` is SET to
  /// the fresh accepted population (not accumulated).
  ///
  /// The project is moved to [MosaicProjectStatus.integrating] for the run.
  /// [outputFitsPathBuilder] maps a panel to that panel's master FITS base path
  /// (the preview / rejection map are derived by extension swap inside the
  /// integration service). Returns one outcome per panel.
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

    // Guard: panels must not share a capture target (would fold identical subs).
    // A panel that legitimately has no target yet is tolerated (left pending in
    // _integratePanel); only an ACTUAL collision among set targets is fatal.
    _assertNoSharedPanelTargets(projectId, panels);

    await _projectsDao.updateStatus(projectId, MosaicProjectStatus.integrating);

    final outcomes = <MosaicPanelIntegrationOutcome>[];
    for (final panel in panels) {
      outcomes.add(
        await _integratePanel(
          project: project,
          panel: panel,
          settings: settings,
          outputFitsPathBuilder: outputFitsPathBuilder,
        ),
      );
    }
    return outcomes;
  }

  /// Assert no two panels with a SET `target_id` resolve to the same target.
  /// Panels with a null target (project target also null) are tolerated — they
  /// are simply left pending. Falls back to the project target for the
  /// collision check so two panels inheriting one project target are caught too.
  void _assertNoSharedPanelTargets(
    int projectId,
    List<MosaicProjectPanel> panels,
  ) {
    final seen = <int, int>{}; // resolvedTargetId -> first panelIndex.
    for (final panel in panels) {
      // Per-panel target only: the project-region target is intentionally NOT a
      // capture target. A panel without its own target is "no subs yet", not a
      // collision.
      final targetId = panel.targetId;
      if (targetId == null) continue;
      final prior = seen[targetId];
      if (prior != null) {
        throw StateError(
          'mosaic project $projectId panels $prior and ${panel.panelIndex} '
          'share capture target $targetId; each panel must isolate its own '
          'subs — refusing to integrate identical subs into different panels',
        );
      }
      seen[targetId] = panel.panelIndex;
    }
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

    // Each panel is a distinct capture target. The per-panel target_id is the
    // ONLY capture target (the project-region target is not a capture target).
    final captureTargetId = panel.targetId;
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
      // pixels are the ones the stitcher will project.
      final masterId = _representativeMasterId(outcomes);

      // RE-INTEGRATION: supersede the panel's previous master (DB row + on-disk
      // FITS/preview/rejmap) before linking the new one, so a re-run never
      // leaves an orphan. Skip if the panel happens to re-link the same id.
      //
      // Remediation 2026-06-09 (findings #1/#3): supersession must be PATH-AWARE,
      // not just id-aware. The per-panel master FITS is written to a DURABLE
      // DETERMINISTIC path (`project_<id>/panel_<i>[_<filter>].fits`) that is
      // IDENTICAL across re-runs, so the freshly-written master and the prior
      // master share a path. An id-only skip guard would then delete the prior
      // master's `masterFitsPath` — which is the SAME file the new master was
      // just written to — leaving the panel linked to a live DB row whose FITS
      // is gone, and aborting the whole stitch. Collect every on-disk path
      // OWNED by the freshly-produced per-filter masters for this panel and pass
      // it to supersession so any prior path that equals a new path is NEVER
      // deleted.
      final keepPaths = await _ownedOnDiskPaths(outcomes);
      await _supersedePreviousMaster(
        panel,
        keepMasterId: masterId,
        keepPaths: keepPaths,
      );

      await _panelsDao.setMaster(panelId, masterId);
      // SET (not +=) so a re-integration with the same/refreshed accepted set
      // lands the count at the current population, never doubling it.
      await _panelsDao.setCaptured(panelId, subs.length);

      return MosaicPanelIntegrationOutcome(
        panelId: panelId,
        panelIndex: panel.panelIndex,
        integratedMasterId: masterId,
        status: MosaicPanelStatus.integrated,
        subCount: subs.length,
      );
    } catch (e, st) {
      _logSoftFailure('integratePanel[${panel.panelIndex}]', e, st);
      // On a failed integrate, clear any stale link so the panel does not
      // appear "integrated" with a master that no longer reflects a good run.
      await _panelsDao.updateStatus(panelId, MosaicPanelStatus.failed);
      await _clearPanelMaster(panelId);
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

  /// Collect the set of on-disk artifact paths OWNED by the freshly-produced
  /// per-filter masters for a panel (FITS / preview / rejection map / sidecar
  /// across EVERY outcome, not just the representative). Supersession must never
  /// delete a path in this set — on the durable deterministic path the prior
  /// and new masters share a FITS path, so deleting the prior's path would
  /// destroy the file the new master was just written to.
  Future<Set<String>> _ownedOnDiskPaths(
    List<PostSessionIntegrationOutcome> outcomes,
  ) async {
    final owned = <String>{};
    for (final outcome in outcomes) {
      final master = await _mastersDao.getById(outcome.masterId);
      if (master == null) continue;
      for (final path in <String?>[
        master.masterFitsPath,
        master.previewPngPath,
        master.rejectionMapPath,
        master.sidecarPath,
      ]) {
        if (path != null && path.trim().isNotEmpty) owned.add(path);
      }
    }
    return owned;
  }

  /// Delete the panel's previously-linked master row + its on-disk artifacts so
  /// a re-integration never orphans the old master/files. No-op when the panel
  /// had no prior master, or when the prior master IS the freshly-produced one
  /// ([keepMasterId]) — the per-filter integration may reuse a master row.
  ///
  /// PATH-AWARE (remediation 2026-06-09, findings #1/#3): [keepPaths] holds the
  /// on-disk paths owned by the freshly-produced master(s). Any prior path that
  /// equals a kept path is NOT deleted — on the durable deterministic path the
  /// new master FITS shares the prior master's path, and an id-only guard would
  /// otherwise delete the live, just-written file.
  Future<void> _supersedePreviousMaster(
    MosaicProjectPanel panel, {
    required int keepMasterId,
    required Set<String> keepPaths,
  }) async {
    final priorId = panel.integratedMasterId;
    if (priorId == null || priorId == keepMasterId) return;
    final prior = await _mastersDao.getById(priorId);
    if (prior == null) return;
    await _deleteMasterArtifactsOnDisk(prior, keepPaths: keepPaths);
    await _mastersDao.deleteMaster(priorId);
  }

  /// Best-effort delete a master's on-disk FITS / preview / rejection map /
  /// sidecar. A missing file is fine (already gone); a delete error is logged
  /// but never aborts the integration — the DB row supersession is what matters.
  ///
  /// Any path in [keepPaths] is SKIPPED — it belongs to the freshly-produced
  /// master(s) (same durable deterministic path), so deleting it would destroy
  /// a live, just-written file (remediation 2026-06-09, findings #1/#3).
  Future<void> _deleteMasterArtifactsOnDisk(
    IntegratedMaster master, {
    Set<String> keepPaths = const <String>{},
  }) async {
    for (final path in <String?>[
      master.masterFitsPath,
      master.previewPngPath,
      master.rejectionMapPath,
      master.sidecarPath,
    ]) {
      if (path == null || path.trim().isEmpty) continue;
      if (keepPaths.contains(path)) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e, st) {
        _logSoftFailure('deleteMasterArtifact($path)', e, st);
      }
    }
  }

  /// Clear a panel's `integrated_master_id` link (without deleting the master),
  /// returning it to pending — used when a panel's integration throws so it
  /// does not masquerade as integrated.
  Future<void> _clearPanelMaster(int panelId) async {
    await _panelsDao.clearMaster(panelId);
  }

  // ---------------------------------------------------------------------------
  // 4. Stitch — project the panel masters onto one shared canvas.
  // ---------------------------------------------------------------------------

  /// Stitch [projectId]'s integrated panels into one mosaic master.
  ///
  /// Gathers every panel that carries a per-panel master with a FITS path on
  /// disk AND a usable WCS (persisted v44 CD-matrix `wcs`, or one the native
  /// side can read from the FITS header), builds the `api_stitch_mosaic`
  /// request, calls [PostSessionSeam.stitchMosaic], persists the stitched output
  /// as a NEW `integrated_masters` row (with the returned canvas geometry),
  /// links it onto `mosaic_projects.output_master_id`, and marks the project
  /// [MosaicProjectStatus.complete].
  ///
  /// **WCS gate.** A panel master with NO WCS (neither a persisted CD-matrix nor
  /// a WCS-bearing FITS header) would make the native stitcher abort the WHOLE
  /// mosaic. Such a panel is SKIPPED and reported in [MosaicStitchOutcome.skips]
  /// rather than handed to the stitcher. The `>= 2` gate then applies to the
  /// panels that ACTUALLY have WCS: a mosaic of one WCS panel is not a mosaic.
  ///
  /// Output artifacts land under the project folder via [outputDirectory]
  /// (`<dir>/<project>_mosaic.fits` + `_coverage.fits` + `.png`).
  ///
  /// If the stitch throws, the project status is reverted off `stitching`
  /// (back to `integrating`) so a failed run never leaves the project pinned in
  /// a stuck `stitching` state.
  Future<MosaicStitchOutcome> stitchProject(
    int projectId, {
    required String outputDirectory,
    Map<String, dynamic>? stitchConfig,
    Future<bool> Function(String fitsPath)? fitsHasWcs,
  }) async {
    final project = await _projectsDao.getById(projectId);
    if (project == null) {
      throw ArgumentError('no mosaic project with id $projectId');
    }

    final panels = await _panelsDao.getForProject(projectId);
    final panelArgs = <Map<String, dynamic>>[];
    final skips = <MosaicPanelStitchSkip>[];
    for (final panel in panels) {
      final masterId = panel.integratedMasterId;
      if (masterId == null) {
        // No master is not a "skip to report" — the panel simply was not
        // integrated. Only count panels that HAD a master but lacked WCS/FITS.
        continue;
      }
      final master = await _mastersDao.getById(masterId);
      final fitsPath = master?.masterFitsPath;
      if (master == null || fitsPath == null || fitsPath.trim().isEmpty) {
        skips.add(
          MosaicPanelStitchSkip(
            panelIndex: panel.panelIndex,
            integratedMasterId: masterId,
            reason: 'panel master has no FITS path on disk',
          ),
        );
        continue;
      }

      // FITS-existence gate (remediation 2026-06-09, finding #4): a non-empty
      // path is NOT proof the file is on disk. A master FITS removed by a temp
      // sweep on legacy data, a manual cleanup, or a supersession bug would be
      // handed to the native stitcher, which fails to read it and ABORTS THE
      // WHOLE MOSAIC — defeating the per-panel skip-gate. Probe existence
      // (best-effort, like the WCS probe) and degrade a missing file to a
      // skipped panel so one bad panel never poisons the stitch.
      if (!await _safeFitsExists(fitsPath)) {
        skips.add(
          MosaicPanelStitchSkip(
            panelIndex: panel.panelIndex,
            integratedMasterId: masterId,
            reason:
                'panel master FITS missing on disk — skipped so it does not '
                'abort the whole mosaic',
          ),
        );
        continue;
      }

      // WCS gate: a WCS-less panel aborts the whole native stitch. Prefer the
      // persisted CD-matrix; otherwise allow the panel only when the FITS header
      // itself carries a WCS (probed via [fitsHasWcs] when supplied). Without
      // either, skip + report instead of poisoning the mosaic.
      final wcs = _wcsArgs(master);
      if (wcs == null) {
        final headerHasWcs = fitsHasWcs == null
            ? false
            : await _safeFitsHasWcs(fitsHasWcs, fitsPath);
        if (!headerHasWcs) {
          skips.add(
            MosaicPanelStitchSkip(
              panelIndex: panel.panelIndex,
              integratedMasterId: masterId,
              reason:
                  'panel master has no WCS (no persisted CD-matrix and no '
                  'WCS in the FITS header) — skipped so it does not abort the '
                  'whole mosaic',
            ),
          );
          continue;
        }
      }

      panelArgs.add(<String, dynamic>{
        'fitsPath': fitsPath,
        if (wcs != null) 'wcs': wcs,
      });
    }

    final contributingMasters = panelArgs.length;
    if (contributingMasters < 2) {
      throw StateError(
        'mosaic project $projectId needs >= 2 panels with integrated masters '
        'AND a usable WCS to stitch (found $contributingMasters'
        '${skips.isEmpty ? '' : '; skipped ${skips.length} WCS-less/'
                  'pathless panel(s)'})',
      );
    }

    await _projectsDao.updateStatus(projectId, MosaicProjectStatus.stitching);

    try {
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

      // Persist the stitched mosaic as a first-class integrated master so it
      // lands in the master library + morning report unchanged, then link it.
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
        skips: skips,
      );
    } catch (e, st) {
      // A stitch throw must not pin the project in `stitching`. Revert to
      // `integrating` (the panels are integrated; the stitch can be retried)
      // so the project never sticks in a dead phase.
      _logSoftFailure('stitchProject[$projectId]', e, st);
      try {
        await _projectsDao.updateStatus(
          projectId,
          MosaicProjectStatus.integrating,
        );
      } catch (revertError, revertSt) {
        _logSoftFailure(
          'stitchProject[$projectId] status revert',
          revertError,
          revertSt,
        );
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers.
  // ---------------------------------------------------------------------------

  Future<bool> _safeFitsHasWcs(
    Future<bool> Function(String fitsPath) probe,
    String fitsPath,
  ) async {
    try {
      return await probe(fitsPath);
    } catch (e, st) {
      _logSoftFailure('fitsHasWcs($fitsPath)', e, st);
      return false;
    }
  }

  /// Best-effort probe that a panel master FITS still exists on disk
  /// (remediation 2026-06-09, finding #4). A probe error degrades to `false`
  /// (treat as missing -> skip the panel) rather than aborting the whole
  /// stitch — a missing file must never poison the mosaic.
  Future<bool> _safeFitsExists(String fitsPath) async {
    try {
      return await File(fitsPath).exists();
    } catch (e, st) {
      _logSoftFailure('fitsExists($fitsPath)', e, st);
      return false;
    }
  }

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
/// master id, how many panels contributed, the raw native stitch result, and
/// any panels the WCS gate SKIPPED.
class MosaicStitchOutcome {
  /// The new `integrated_masters.id` for the stitched mosaic master (also set as
  /// the project's `output_master_id`).
  final int outputMasterId;

  /// How many panel masters were projected onto the canvas.
  final int panelCount;

  /// The decoded native stitch result (canvas geometry + diagnostics).
  final MosaicStitchResult result;

  /// Panels that carried a master but were SKIPPED (no FITS / no WCS) so they
  /// did not abort the whole mosaic. Empty when every panel-with-master
  /// contributed.
  final List<MosaicPanelStitchSkip> skips;

  const MosaicStitchOutcome({
    required this.outputMasterId,
    required this.panelCount,
    required this.result,
    this.skips = const [],
  });
}

/// Provider for [MosaicProjectService], wiring the v45 mosaic DAOs, the targets
/// DAO (per-panel capture targets), the images DAO, the integrated-masters DAO,
/// the post-session integration service, and the post-session seam (which
/// carries `stitchMosaic`).
final mosaicProjectServiceProvider = Provider<MosaicProjectService>((ref) {
  return MosaicProjectService(
    db: ref.watch(databaseProvider),
    projectsDao: ref.watch(mosaicProjectsDaoProvider),
    panelsDao: ref.watch(mosaicPanelsDaoProvider),
    targetsDao: ref.watch(targetsDaoProvider),
    imagesDao: ref.watch(imagesDaoProvider),
    mastersDao: ref.watch(integratedMastersDaoProvider),
    integrationService: ref.watch(postSessionIntegrationServiceProvider),
    seam: ref.watch(postSessionSeamProvider),
  );
});
