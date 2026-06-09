import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// Immutable snapshot the [MosaicProjectScreen] renders: the durable project, its
/// panels (ordered by index), the per-panel masters (so the grid can show a
/// thumbnail when a panel is integrated), and — once the project is complete —
/// the stitched output master.
///
/// Loading/busy/error are explicit fields rather than an `AsyncValue` so the
/// screen can show the project chrome immediately while an action (integrate /
/// stitch) runs, and surface a non-blocking error banner without tearing the
/// whole screen down.
class MosaicProjectState {
  /// The durable `mosaic_projects` row, or null before the first load resolves
  /// (or when the id does not exist).
  final MosaicProject? project;

  /// The project's panels, ordered by `panel_index`.
  final List<MosaicProjectPanel> panels;

  /// Per-panel integrated masters keyed by `mosaic_panels.integrated_master_id`,
  /// so the grid can render a panel's master thumbnail without re-querying.
  final Map<int, IntegratedMaster> panelMasters;

  /// The stitched mosaic master (the project's `output_master_id`), or null
  /// until the project is complete.
  final IntegratedMaster? stitchedMaster;

  /// True during the initial load (no project resolved yet).
  final bool isLoading;

  /// True while [MosaicProjectController.startCapture] is running.
  final bool isStartingCapture;

  /// True while [MosaicProjectController.integratePanels] is running.
  final bool isIntegrating;

  /// True while [MosaicProjectController.stitchProject] is running.
  final bool isStitching;

  /// A human-readable error from the last load or action, or null. Surfaced as
  /// a dismissible banner; it never tears down the already-loaded chrome.
  final String? error;

  const MosaicProjectState({
    this.project,
    this.panels = const [],
    this.panelMasters = const {},
    this.stitchedMaster,
    this.isLoading = true,
    this.isStartingCapture = false,
    this.isIntegrating = false,
    this.isStitching = false,
    this.error,
  });

  /// True while any long-running action (start-capture, integrate, or stitch)
  /// is in flight.
  bool get isBusy => isStartingCapture || isIntegrating || isStitching;

  /// Number of panels that carry an integrated per-panel master — the
  /// population the stitcher consumes. Stitch is gated until this is >= 2 (one
  /// panel is not a mosaic).
  int get panelsWithMasters =>
      panels.where((p) => p.integratedMasterId != null).length;

  /// True once at least two panels have masters, so a mosaic can be stitched.
  bool get canStitch => panelsWithMasters >= 2;

  /// True when the stitched output master has been produced and is on hand.
  bool get isComplete =>
      (project?.isComplete ?? false) && stitchedMaster != null;

  /// Count of panels by [MosaicPanelStatus] — feeds the header status summary.
  int countWithStatus(MosaicPanelStatus status) =>
      panels.where((p) => p.status == status).length;

  MosaicProjectState copyWith({
    MosaicProject? project,
    List<MosaicProjectPanel>? panels,
    Map<int, IntegratedMaster>? panelMasters,
    IntegratedMaster? stitchedMaster,
    bool clearStitchedMaster = false,
    bool? isLoading,
    bool? isStartingCapture,
    bool? isIntegrating,
    bool? isStitching,
    String? error,
    bool clearError = false,
  }) {
    return MosaicProjectState(
      project: project ?? this.project,
      panels: panels ?? this.panels,
      panelMasters: panelMasters ?? this.panelMasters,
      stitchedMaster:
          clearStitchedMaster ? null : (stitchedMaster ?? this.stitchedMaster),
      isLoading: isLoading ?? this.isLoading,
      isStartingCapture: isStartingCapture ?? this.isStartingCapture,
      isIntegrating: isIntegrating ?? this.isIntegrating,
      isStitching: isStitching ?? this.isStitching,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Riverpod controller for one mosaic project's review experience.
///
/// It is design-system pure: it holds only data (project + panels + masters +
/// busy/error flags) and drives the two durable actions through the committed
/// [MosaicProjectService] — it owns no widgets and no native calls of its own.
///
///  * [load] reads the project + panels via the DAOs and resolves each panel's
///    master (and the stitched output) from [IntegratedMastersDao].
///  * [integratePanels] runs [MosaicProjectService.integratePanels] and reloads.
///  * [stitchProject] runs [MosaicProjectService.stitchProject] and reloads;
///    it refuses (without touching the service) when fewer than two panels have
///    masters, mirroring the service's own >= 2 guard so the UI never makes a
///    doomed call.
class MosaicProjectController extends StateNotifier<MosaicProjectState> {
  MosaicProjectController({
    required int projectId,
    required MosaicProjectsDao projectsDao,
    required MosaicPanelsDao panelsDao,
    required IntegratedMastersDao mastersDao,
    required MosaicProjectService service,
    required String Function(MosaicProjectPanel panel) panelOutputPathBuilder,
    required String Function(MosaicProject project) stitchOutputDirectory,
    MosaicCaptureLauncher? captureLauncher,
    IntegrationSettings integrationSettings = IntegrationSettings.defaults,
  })  : _projectId = projectId,
        _projectsDao = projectsDao,
        _panelsDao = panelsDao,
        _mastersDao = mastersDao,
        _service = service,
        _panelOutputPathBuilder = panelOutputPathBuilder,
        _stitchOutputDirectory = stitchOutputDirectory,
        _captureLauncher = captureLauncher,
        _integrationSettings = integrationSettings,
        super(const MosaicProjectState()) {
    // Kick the first load; errors land on state.error rather than throwing into
    // the constructor.
    unawaited(load());
  }

  final int _projectId;
  final MosaicProjectsDao _projectsDao;
  final MosaicPanelsDao _panelsDao;
  final IntegratedMastersDao _mastersDao;
  final MosaicProjectService _service;
  final String Function(MosaicProjectPanel panel) _panelOutputPathBuilder;
  final String Function(MosaicProject project) _stitchOutputDirectory;

  /// Builds the per-panel-target mosaic sequence and loads it into the executor.
  /// Null when the screen was constructed without a launcher (capture is then
  /// unavailable — the integrate/stitch review actions still work). Injected so
  /// tests can drive [startCapture] without the real sequencer/executor.
  final MosaicCaptureLauncher? _captureLauncher;
  final IntegrationSettings _integrationSettings;

  /// Load (or reload) the project, its panels, the per-panel masters, and the
  /// stitched output. Errors are captured onto [MosaicProjectState.error]; the
  /// previously-loaded chrome is left intact so a transient read failure does
  /// not blank the screen.
  Future<void> load() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: state.project == null, clearError: true);
    try {
      final project = await _projectsDao.getById(_projectId);
      if (project == null) {
        if (!mounted) return;
        state = state.copyWith(
          isLoading: false,
          error: 'No mosaic project with id $_projectId',
        );
        return;
      }

      final panels = await _panelsDao.getForProject(_projectId);

      // Resolve each panel's per-panel master once, de-duplicated by master id
      // (several panels never share a master, but the map keeps the lookup
      // O(1) for the grid and tolerates a missing/deleted master row).
      final masters = <int, IntegratedMaster>{};
      for (final panel in panels) {
        final masterId = panel.integratedMasterId;
        if (masterId == null || masters.containsKey(masterId)) continue;
        final master = await _mastersDao.getById(masterId);
        if (master != null) masters[masterId] = master;
      }

      final outputMasterId = project.outputMasterId;
      final stitched = outputMasterId == null
          ? null
          : await _mastersDao.getById(outputMasterId);

      if (!mounted) return;
      state = MosaicProjectState(
        project: project,
        panels: panels,
        panelMasters: masters,
        stitchedMaster: stitched,
        isLoading: false,
        isStartingCapture: state.isStartingCapture,
        isIntegrating: state.isIntegrating,
        isStitching: state.isStitching,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: 'Failed to load: $e');
    }
  }

  /// Whether this controller can launch capture (a [MosaicCaptureLauncher] was
  /// supplied). The screen hides/disables the "Start capture" action when false.
  bool get canStartCapture => _captureLauncher != null;

  /// LAUNCH capture of the durable project via
  /// [MosaicProjectService.startCapture]: the service resolves each panel's
  /// distinct capture target, the injected [MosaicCaptureLauncher] builds the
  /// per-panel-target mosaic sequence and loads it into the executor, and the
  /// project + panels move into the capturing state. Then reload so the header
  /// reflects the new lifecycle.
  ///
  /// No-op (with a clear error) when no launcher was supplied. Busy/error are
  /// reported on state; a thrown service/launcher error is caught and surfaced,
  /// never rethrown into the widget tree.
  Future<void> startCapture() async {
    final project = state.project;
    if (project == null || state.isBusy) return;
    final launcher = _captureLauncher;
    if (launcher == null) {
      state = state.copyWith(
        error: 'Capture is unavailable: no sequencer/executor wired for this '
            'screen.',
      );
      return;
    }
    state = state.copyWith(isStartingCapture: true, clearError: true);
    try {
      await _service.startCapture(_projectId, launcher: launcher);
      await load();
      if (mounted) state = state.copyWith(isStartingCapture: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isStartingCapture: false,
        error: 'Start capture failed: $e',
      );
    }
  }

  /// Integrate every panel of this project via [MosaicProjectService], then
  /// reload so the grid reflects the new per-panel masters. Busy/error are
  /// reported on state; a thrown service error is caught and surfaced, never
  /// rethrown into the widget tree.
  Future<void> integratePanels() async {
    final project = state.project;
    if (project == null || state.isBusy) return;
    state = state.copyWith(isIntegrating: true, clearError: true);
    try {
      await _service.integratePanels(
        _projectId,
        settings: _integrationSettings,
        outputFitsPathBuilder: _panelOutputPathBuilder,
      );
      await load();
      if (mounted) state = state.copyWith(isIntegrating: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isIntegrating: false,
        error: 'Integration failed: $e',
      );
    }
  }

  /// Stitch the integrated panels into one mosaic master via
  /// [MosaicProjectService], then reload so the stitched hero appears.
  ///
  /// Gated on [MosaicProjectState.canStitch] (>= 2 panels with masters): when
  /// fewer than two panels carry a master this records a clear error WITHOUT
  /// calling the service, mirroring the service's own guard so the UI never
  /// makes a doomed FFI round-trip.
  Future<void> stitchProject() async {
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (!state.canStitch) {
      state = state.copyWith(
        error: 'Stitch needs at least 2 integrated panels '
            '(have ${state.panelsWithMasters}).',
      );
      return;
    }
    state = state.copyWith(isStitching: true, clearError: true);
    try {
      await _service.stitchProject(
        _projectId,
        outputDirectory: _stitchOutputDirectory(project),
      );
      await load();
      if (mounted) state = state.copyWith(isStitching: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isStitching: false, error: 'Stitch failed: $e');
    }
  }

  /// Dismiss the current error banner.
  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

/// Arguments to construct a [MosaicProjectController] via its family provider —
/// the project id plus the path builders the durable actions need (kept on the
/// args, not hard-coded in the controller, so the screen/app supplies real
/// on-disk locations while tests supply temp paths).
class MosaicProjectControllerArgs {
  /// The `mosaic_projects.id` to review.
  final int projectId;

  /// Maps a panel to its per-panel master FITS base path (the integration
  /// service derives the preview/.png + rejection map by extension swap).
  final String Function(MosaicProjectPanel panel) panelOutputPathBuilder;

  /// Maps a project to the directory the stitched mosaic artifacts land in.
  final String Function(MosaicProject project) stitchOutputDirectory;

  /// Integration settings the per-panel integration runs with.
  final IntegrationSettings integrationSettings;

  const MosaicProjectControllerArgs({
    required this.projectId,
    required this.panelOutputPathBuilder,
    required this.stitchOutputDirectory,
    this.integrationSettings = IntegrationSettings.defaults,
  });

  @override
  bool operator ==(Object other) =>
      other is MosaicProjectControllerArgs &&
      other.projectId == projectId &&
      other.panelOutputPathBuilder == panelOutputPathBuilder &&
      other.stitchOutputDirectory == stitchOutputDirectory &&
      other.integrationSettings == integrationSettings;

  @override
  int get hashCode => Object.hash(
        projectId,
        panelOutputPathBuilder,
        stitchOutputDirectory,
        integrationSettings,
      );
}

/// Family provider for the per-project controller. Keyed on
/// [MosaicProjectControllerArgs] so two screens reviewing different projects get
/// independent controllers; the path builders ride on the args.
final mosaicProjectControllerProvider = StateNotifierProvider.family<
    MosaicProjectController, MosaicProjectState, MosaicProjectControllerArgs>(
  (ref, args) {
    return MosaicProjectController(
      projectId: args.projectId,
      projectsDao: ref.watch(mosaicProjectsDaoProvider),
      panelsDao: ref.watch(mosaicPanelsDaoProvider),
      mastersDao: ref.watch(integratedMastersDaoProvider),
      service: ref.watch(mosaicProjectServiceProvider),
      panelOutputPathBuilder: args.panelOutputPathBuilder,
      stitchOutputDirectory: args.stitchOutputDirectory,
      captureLauncher: buildMosaicCaptureLauncher(ref),
      integrationSettings: args.integrationSettings,
    );
  },
);

/// Lists every durable mosaic project (newest first) for the projects list
/// screen. A plain `FutureProvider` over [MosaicProjectsDao]; the list screen
/// invalidates it on pull-to-refresh.
final mosaicProjectsListProvider =
    FutureProvider<List<MosaicProject>>((ref) async {
  return ref.watch(mosaicProjectsDaoProvider).listAll();
});

/// Build the real [MosaicCaptureLauncher] that
/// [MosaicProjectService.startCapture] hands the resolved
/// [MosaicCaptureRequest]: it rebuilds the project's mosaic sequence via the
/// canonical [MosaicService.createMosaicSequence] (so per-panel FITS provenance
/// matches the wizard / framing entry points), stamps each panel
/// `TargetHeaderNode.catalogTargetId` from the request's per-panel target map
/// (so a panel's subs attribute to that panel's distinct target), loads it into
/// the editor, and starts the executor.
///
/// Returns null when no equipment FOV is resolvable — capture cannot be planned
/// without the rig footprint, and surfacing "unavailable" beats building a
/// geometrically wrong mosaic. The controller then reports a clear error rather
/// than silently launching a bad run.
MosaicCaptureLauncher buildMosaicCaptureLauncher(Ref ref) {
  return (MosaicCaptureRequest request) async {
    final panels = request.panels;
    if (panels.isEmpty) {
      throw StateError('mosaic capture has no panels');
    }

    // Per-panel rig footprint (arcmin) from the active equipment profile (or
    // custom framing equipment). Without it the panel geometry is undefined.
    final fov = await ref.read(framingFOVProvider.future);
    final equipment = fov.equipment;
    if (equipment == null) {
      throw StateError(
        'cannot launch mosaic capture: no equipment FOV available — configure '
        'a camera + focal length in your active profile and try again',
      );
    }

    // Project center = mean of the stored panel centers (the same point the
    // grid was generated about), so regenerating the panels reproduces the
    // exact per-panel centers already persisted.
    var ra = 0.0;
    var dec = 0.0;
    for (final panel in panels) {
      ra += panel.centerRa;
      dec += panel.centerDec;
    }
    ra /= panels.length;
    dec /= panels.length;

    final project = request.project;
    final config = MosaicConfig(
      centerRa: ra,
      centerDec: dec,
      panelWidthArcmin: equipment.fovWidthDeg * 60.0,
      panelHeightArcmin: equipment.fovHeightDeg * 60.0,
      overlapPercent: project.overlapPct,
      rotation: project.positionAngleDeg,
      panelsHorizontal: project.cols,
      panelsVertical: project.rows,
    );

    final exposure = smartNightMosaicExposureSettings(
      ref.read(smartNightExposureContextProvider).valueOrNull,
    );

    final options = MosaicSequenceOptions(
      serpentineOrdering: true,
      centerAfterSlew: true,
      autofocusPerPanel: false,
      // W1 STRENGTHEN (never weaken): default each panel's minAltitude to the
      // Smart Night floor so every panel TargetHeader carries an altitude gate
      // — matching the wizard / headless mosaic paths. This ADDS the
      // no-daylight/altitude gate to the durable-project capture sequence; it
      // does not touch the live Dart Sun gate (W1) or the fail-closed weather
      // gate (W5).
      minAltitude: const SmartNightSettings().minAltitudeDeg,
    );

    final mosaicName = project.name.isEmpty
        ? 'Mosaic ${ra.toStringAsFixed(2)}h ${dec.toStringAsFixed(1)}deg'
        : project.name;

    const service = MosaicService();
    final nodes = service.createMosaicSequence(
      mosaicName: mosaicName,
      config: config,
      exposure: exposure,
      options: options,
      // CONTRACT (capture-wiring <-> project-service): pass the per-panel target
      // map so each panel's TargetHeaderNode is stamped with its DISTINCT
      // catalogTargetId — a panel's captured subs then attribute to that panel's
      // own target (the precise isolation per-panel integration relies on).
      panelTargetId: (panelIndex) => request.panelTargetIds[panelIndex],
    );

    // Reuse the canonical "wrap nodes + load into editor" path so the durable
    // project capture is byte-identical to the wizard/framing sequence shape.
    final rootNode = nodes.values.firstWhere(
      (n) => n is InstructionSetNode && n.parentId == null,
      orElse: () => throw StateError(
        'MosaicService.createMosaicSequence did not produce a root '
        'InstructionSetNode — refusing to launch a malformed mosaic.',
      ),
    );
    final sequence = Sequence.create(
      name: mosaicName,
      nodes: nodes,
      rootNodeId: rootNode.id,
    );

    ref
        .read(currentSequenceProvider.notifier)
        .loadSequence(sequence, discardUnsaved: true);
    await ref.read(sequenceExecutorProvider).start();
  };
}
