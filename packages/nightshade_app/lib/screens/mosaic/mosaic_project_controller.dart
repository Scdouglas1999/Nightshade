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
    this.isIntegrating = false,
    this.isStitching = false,
    this.error,
  });

  /// True while any long-running action (integrate or stitch) is in flight.
  bool get isBusy => isIntegrating || isStitching;

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
    IntegrationSettings integrationSettings = IntegrationSettings.defaults,
  })  : _projectId = projectId,
        _projectsDao = projectsDao,
        _panelsDao = panelsDao,
        _mastersDao = mastersDao,
        _service = service,
        _panelOutputPathBuilder = panelOutputPathBuilder,
        _stitchOutputDirectory = stitchOutputDirectory,
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
        isIntegrating: state.isIntegrating,
        isStitching: state.isStitching,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: 'Failed to load: $e');
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
