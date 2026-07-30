import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;

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

  /// True while [MosaicProjectController.publishToHub] is running (WS2).
  final bool isPublishing;

  /// True while a claim action is running (WS2).
  final bool isClaiming;

  /// True while a panel-master upload is running (WS2).
  final bool isUploading;

  /// True while [MosaicProjectController.assembleFromHub] is running (WS2).
  final bool isAssembling;

  /// True while [MosaicProjectController.joinAsParticipant] is running (WS2).
  final bool isJoining;

  /// True while [MosaicProjectController.refreshStatus] is running (WS2).
  final bool isRefreshing;

  /// True while [MosaicProjectController.downloadOutput] is running (WS2).
  final bool isDownloading;

  /// When the claims this rig currently holds expire on the hub (WS2), or null
  /// when nothing is held. Taken from the hub's own claim grant rather than a
  /// client-side copy of the TTL, so what the operator is shown is the time the
  /// hub will actually re-open their panels.
  final DateTime? claimExpiresAt;

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
    this.isPublishing = false,
    this.isClaiming = false,
    this.isUploading = false,
    this.isAssembling = false,
    this.isJoining = false,
    this.isRefreshing = false,
    this.isDownloading = false,
    this.claimExpiresAt,
    this.error,
  });

  /// True while any long-running action (start-capture, integrate, stitch, or a
  /// collaborative publish/claim/upload/assemble) is in flight.
  bool get isBusy =>
      isStartingCapture ||
      isIntegrating ||
      isStitching ||
      isPublishing ||
      isClaiming ||
      isUploading ||
      isAssembling ||
      isJoining ||
      isRefreshing ||
      isDownloading;

  /// The hub mosaic id once this project has been published (WS2), or null.
  String? get hubMosaicId => project?.hubMosaicId;

  /// True once this project has been published to the hub as a collaborative
  /// mosaic (WS2).
  bool get isPublished => project?.isPublished ?? false;

  /// The hub-side collaborative lifecycle (published|assembling|complete), or
  /// null when not a collaborative mosaic (WS2).
  String? get collabStatus => project?.collabStatus;

  /// Panels not yet claimed for distributed capture (WS2) — the claim-all set.
  List<MosaicProjectPanel> get unclaimedPanels =>
      panels.where((p) => !p.isClaimed).toList(growable: false);

  /// True when this device owns the collaborative mosaic (as opposed to having
  /// joined a peer's as a participant).
  bool get isOwner => project?.collabRole == 'owner';

  /// Integrated panels not yet uploaded to the hub (WS2) — the upload-all set.
  List<MosaicProjectPanel> get integratedNotUploaded => panels
      .where((p) => p.integratedMasterId != null && !p.isUploaded)
      .toList(growable: false);

  /// Count of panels whose master has been uploaded to the hub (WS2).
  int get panelsUploaded => panels.where((p) => p.isUploaded).length;

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
    bool? isPublishing,
    bool? isClaiming,
    bool? isUploading,
    bool? isAssembling,
    bool? isJoining,
    bool? isRefreshing,
    bool? isDownloading,
    DateTime? claimExpiresAt,
    bool clearClaimExpiresAt = false,
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
      isPublishing: isPublishing ?? this.isPublishing,
      isClaiming: isClaiming ?? this.isClaiming,
      isUploading: isUploading ?? this.isUploading,
      isAssembling: isAssembling ?? this.isAssembling,
      isJoining: isJoining ?? this.isJoining,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isDownloading: isDownloading ?? this.isDownloading,
      claimExpiresAt:
          clearClaimExpiresAt ? null : (claimExpiresAt ?? this.claimExpiresAt),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// One database read of everything [MosaicProjectController.load] renders. A
/// null [project] means "no such project" (not an error).
class _MosaicProjectSnapshot {
  final MosaicProject? project;
  final List<MosaicProjectPanel> panels;
  final Map<int, IntegratedMaster> panelMasters;
  final IntegratedMaster? stitchedMaster;

  const _MosaicProjectSnapshot({
    this.project,
    this.panels = const [],
    this.panelMasters = const {},
    this.stitchedMaster,
  });
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
    CollaborativeMosaicService? collaborativeService,
    bool hubConfigured = true,
    MosaicCaptureLauncher? captureLauncher,
    IntegrationSettings integrationSettings = IntegrationSettings.defaults,
  })  : _projectId = projectId,
        _projectsDao = projectsDao,
        _panelsDao = panelsDao,
        _mastersDao = mastersDao,
        _service = service,
        _collaborative = collaborativeService,
        _hubConfigured = hubConfigured,
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

  /// WS2 collaborative-mosaic orchestration. Null when no hub-aware service was
  /// wired (the local-only review path); the collaborative actions then report a
  /// clear error rather than crashing.
  final CollaborativeMosaicService? _collaborative;

  /// Whether a Constellation hub is actually configured/signed-in (resolved from
  /// [constellationConfiguredProvider]). A hub-aware service is always wired, so
  /// this — not merely `_collaborative != null` — is what gates the collaborative
  /// affordances: with no hub the publish/claim/force-release actions would fail
  /// at the tap with an auth error, so they are hidden/disabled up front instead.
  final bool _hubConfigured;
  final String Function(MosaicProjectPanel panel) _panelOutputPathBuilder;
  final String Function(MosaicProject project) _stitchOutputDirectory;

  /// Builds the per-panel-target mosaic sequence and loads it into the executor.
  /// Null when the screen was constructed without a launcher (capture is then
  /// unavailable — the integrate/stitch review actions still work). Injected so
  /// tests can drive [startCapture] without the real sequencer/executor.
  final MosaicCaptureLauncher? _captureLauncher;
  final IntegrationSettings _integrationSettings;

  /// How long the project read may take before the screen stops waiting on it.
  /// A wedged/locked database must surface an actionable error rather than an
  /// indefinite spinner the operator cannot interpret.
  static const Duration loadTimeout = Duration(seconds: 20);

  /// Load (or reload) the project, its panels, the per-panel masters, and the
  /// stitched output. Errors are captured onto [MosaicProjectState.error]; the
  /// previously-loaded chrome is left intact so a transient read failure does
  /// not blank the screen. The whole read is bounded by [loadTimeout], so
  /// `isLoading` always resolves.
  Future<void> load() async {
    if (!mounted) return;
    state = state.copyWith(isLoading: state.project == null, clearError: true);
    try {
      final snapshot = await _readSnapshot().timeout(loadTimeout);
      final project = snapshot.project;
      if (project == null) {
        if (!mounted) return;
        state = state.copyWith(
          isLoading: false,
          error: 'No mosaic project with id $_projectId',
        );
        return;
      }
      final panels = snapshot.panels;

      if (!mounted) return;
      state = MosaicProjectState(
        project: project,
        panels: panels,
        panelMasters: snapshot.panelMasters,
        stitchedMaster: snapshot.stitchedMaster,
        isLoading: false,
        isStartingCapture: state.isStartingCapture,
        isIntegrating: state.isIntegrating,
        isStitching: state.isStitching,
        isPublishing: state.isPublishing,
        isClaiming: state.isClaiming,
        isUploading: state.isUploading,
        isAssembling: state.isAssembling,
        isJoining: state.isJoining,
        isRefreshing: state.isRefreshing,
        isDownloading: state.isDownloading,
        // The held-claim expiry is only meaningful while this rig still holds
        // one; releasing the last panel drops it rather than leaving a stale
        // deadline on screen.
        claimExpiresAt: panels.any((p) => p.isClaimed && !p.isUploaded)
            ? state.claimExpiresAt
            : null,
      );
    } on TimeoutException {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: 'Timed out reading mosaic project $_projectId after '
            '${loadTimeout.inSeconds}s — the project database did not respond. '
            'Close any other Nightshade instance using it and try again.',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: 'Failed to load: $e');
    }
  }

  /// One consistent read of everything the screen renders. Split out of [load]
  /// so the whole read can be bounded by a single timeout.
  Future<_MosaicProjectSnapshot> _readSnapshot() async {
    final project = await _projectsDao.getById(_projectId);
    if (project == null) return const _MosaicProjectSnapshot();

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

    return _MosaicProjectSnapshot(
      project: project,
      panels: panels,
      panelMasters: masters,
      stitchedMaster: stitched,
    );
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
      final outcomes = await _service.integratePanels(
        _projectId,
        settings: _integrationSettings,
        outputFitsPathBuilder: _panelOutputPathBuilder,
      );
      await load();
      if (!mounted) return;
      final failed = outcomes
          .where((o) => o.status == MosaicPanelStatus.failed)
          .toList(growable: false);
      if (failed.isEmpty) {
        state = state.copyWith(isIntegrating: false);
      } else {
        final detail = failed
            .map((o) => o.note == null
                ? 'panel ${o.panelIndex + 1}'
                : 'panel ${o.panelIndex + 1}: ${o.note}')
            .join('; ');
        state = state.copyWith(
          isIntegrating: false,
          error: 'Integrated ${outcomes.length - failed.length} of '
              '${outcomes.length} panels; ${failed.length} failed — $detail',
        );
      }
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

  // ---------------------------------------------------------------------------
  // Collaborative mosaics (WS2) — publish / claim / upload / assemble over the
  // hub. Each mirrors the integrate/stitch shape: set the right busy flag, call
  // the collaborative service, reload, and surface errors WITHOUT rethrowing.
  // ---------------------------------------------------------------------------

  /// Whether the collaborative actions are available: a hub-aware service was
  /// wired AND a Constellation hub is actually configured/signed-in. The screen
  /// hides/disables the collaborative affordances when false, so the buttons are
  /// never enabled-then-failing-at-the-tap on a rig with no hub.
  bool get canCollaborate => _collaborative != null && _hubConfigured;

  /// Publish this project to the hub as a collaborative mosaic, then reload so
  /// the header reflects the published state.
  Future<void> publishToHub() async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isPublishing: true, clearError: true);
    try {
      await collaborative.publishProject(_projectId);
      await load();
      if (mounted) state = state.copyWith(isPublishing: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isPublishing: false, error: 'Publish failed: $e');
    }
  }

  /// The most panels a NON-OWNER may take in a single bulk claim.
  ///
  /// A hub claim is held for hours and only its holder (or the owner, one panel
  /// at a time) can give it back, so an unbounded "claim everything" on a mosaic
  /// this rig does not own is a one-tap lockout of its owner. A participant gets
  /// a batch worth a night's work instead and can claim further panels
  /// individually from the grid.
  static const int participantBulkClaimLimit = 4;

  /// How many panels the bulk-claim action will actually take: everything still
  /// pending for the OWNER of the mosaic, and for a participant at most
  /// [participantBulkClaimLimit] and never more than half the grid, so one
  /// contributor can never swallow a shared mosaic in a single tap.
  int get bulkClaimCount {
    final pending = state.unclaimedPanels.length;
    if (state.isOwner) return pending;
    final halfGrid = state.panels.length ~/ 2;
    var limit = participantBulkClaimLimit;
    if (halfGrid < limit) limit = halfGrid;
    if (limit < 1) limit = 1;
    return pending < limit ? pending : limit;
  }

  /// Claim one panel of the published mosaic via the hub baton, then reload.
  Future<void> claimPanel(int panelIndex) async {
    await _runClaim(
        () => _collaborative!.claimPanels(_projectId, [panelIndex]));
  }

  /// Claim a batch of not-yet-claimed panels of the published mosaic, then
  /// reload. Bounded by [bulkClaimCount] — unlimited for the mosaic's owner,
  /// capped for a participant.
  Future<void> claimPendingBatch() async {
    final indices = state.unclaimedPanels
        .take(bulkClaimCount)
        .map((p) => p.panelIndex)
        .toList(growable: false);
    if (indices.isEmpty) return;
    await _runClaim(() => _collaborative!.claimPanels(_projectId, indices));
  }

  Future<void> _runClaim(
    Future<List<MosaicPanelClaim>> Function() action,
  ) async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isClaiming: true, clearError: true);
    try {
      final claims = await action();
      await load();
      if (!mounted) return;
      // Surface the hub's OWN deadline for what was just granted, so the person
      // taking a panel can see how long they are holding it for.
      final expiries = claims
          .map((c) => c.expiresAt)
          .whereType<DateTime>()
          .toList(growable: false);
      state = state.copyWith(
        isClaiming: false,
        claimExpiresAt: expiries.isEmpty
            ? null
            : expiries.reduce((a, b) => a.isBefore(b) ? a : b),
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isClaiming: false, error: 'Claim failed: $e');
    }
  }

  /// Hand THIS rig's own claim on [panelIndex] back to the pool, then reload.
  ///
  /// The counterpart to [claimPanel] and the only way a contributor can undo a
  /// claim themselves: the hub accepts it from the account holding the baton,
  /// where [forceReleasePanel] is owner/admin-only. Reuses the claim busy flag
  /// since it is claim-baton management.
  Future<void> releasePanel(int panelIndex) async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isClaiming: true, clearError: true);
    try {
      final released = await collaborative.releasePanel(_projectId, panelIndex);
      await load();
      if (!mounted) return;
      if (released) {
        state = state.copyWith(isClaiming: false);
      } else {
        state = state.copyWith(
          isClaiming: false,
          error: 'Panel ${panelIndex + 1} was not released — the hub no longer '
              'holds a claim for this device.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isClaiming: false, error: 'Release failed: $e');
    }
  }

  /// Owner/admin recovery: force-release one panel of the published mosaic —
  /// evicting a squatting claim or a poisoned upload that the per-account
  /// release cannot recover — then reload. The hub enforces owner/admin
  /// ownership; a non-owner sees the surfaced auth error. Reuses the claim busy
  /// flag since it is a claim-baton management action.
  Future<void> forceReleasePanel(int panelIndex) async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isClaiming: true, clearError: true);
    try {
      await collaborative.forceReleasePanel(_projectId, panelIndex);
      await load();
      if (mounted) state = state.copyWith(isClaiming: false);
    } catch (e) {
      if (!mounted) return;
      state =
          state.copyWith(isClaiming: false, error: 'Force-release failed: $e');
    }
  }

  /// Upload one integrated panel's master to the hub under the user's chosen
  /// sharing [license] + [attributionConsent] (WS4 consent contract — the
  /// caller presents the contribute sheet first), then reload.
  Future<void> uploadPanelMaster(
    int panelIndex, {
    required ContributionLicense license,
    required bool attributionConsent,
  }) async {
    await _runUpload(
      () => _collaborative!.uploadPanelMaster(
        _projectId,
        panelIndex,
        license: license,
        attributionConsent: attributionConsent,
      ),
    );
  }

  /// Upload every integrated-but-not-yet-uploaded panel master under the user's
  /// chosen sharing [license] + [attributionConsent], then reload.
  Future<void> uploadAllIntegrated({
    required ContributionLicense license,
    required bool attributionConsent,
  }) async {
    final indices = state.integratedNotUploaded
        .map((p) => p.panelIndex)
        .toList(growable: false);
    if (indices.isEmpty) return;
    await _runUpload(() async {
      for (final index in indices) {
        await _collaborative!.uploadPanelMaster(
          _projectId,
          index,
          license: license,
          attributionConsent: attributionConsent,
        );
      }
    });
  }

  Future<void> _runUpload(Future<void> Function() action) async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isUploading: true, clearError: true);
    try {
      await action();
      await load();
      if (mounted) state = state.copyWith(isUploading: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isUploading: false, error: 'Upload failed: $e');
    }
  }

  /// Owner-only central assembly: pull every panel master, stitch, and push the
  /// finished mosaic back to the hub, then reload.
  Future<void> assembleFromHub() async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isAssembling: true, clearError: true);
    try {
      await collaborative.assembleMosaic(_projectId);
      await load();
      if (mounted) state = state.copyWith(isAssembling: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isAssembling: false, error: 'Assemble failed: $e');
    }
  }

  /// Discover open/claimable collaborative mosaics on the configured hub — the
  /// participant-side counterpart to [publishToHub], so a rig can pick a mosaic
  /// to JOIN before claiming panels. Returns the listing (empty + a surfaced
  /// error when no hub is wired); never throws into the widget tree.
  Future<List<CollabMosaic>> discoverMosaics() async {
    final collaborative = _collaborative;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return const [];
    }
    try {
      return await collaborative.listMosaics();
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Discover failed: $e');
      return const [];
    }
  }

  /// JOIN [hubMosaicId] as a participant: link this local project to the hub
  /// mosaic with `collab_role = participant` so its claim/upload/download calls
  /// resolve the hub mosaic. Prerequisite for a non-owner rig to contribute —
  /// without it, claim/upload 400 with "not published to a hub". Then reload.
  Future<void> joinAsParticipant(String hubMosaicId) async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    if (hubMosaicId.trim().isEmpty) {
      state =
          state.copyWith(error: 'Join failed: a hub mosaic id is required.');
      return;
    }
    state = state.copyWith(isJoining: true, clearError: true);
    try {
      await collaborative.joinAsParticipant(_projectId, hubMosaicId);
      await load();
      if (mounted) state = state.copyWith(isJoining: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isJoining: false, error: 'Join failed: $e');
    }
  }

  /// Refresh this project's `collab_status` from the hub (the owner polling for
  /// `assembling`, or a participant polling for `complete`), then reload so the
  /// header reflects the live lifecycle.
  Future<void> refreshStatus() async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isRefreshing: true, clearError: true);
    try {
      await collaborative.refreshStatus(_projectId);
      await load();
      if (mounted) state = state.copyWith(isRefreshing: false);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isRefreshing: false, error: 'Refresh failed: $e');
    }
  }

  /// Download the finished collaborative mosaic the owner assembled + published
  /// back to the swarm — the participant end of the "publish the finished mosaic
  /// to every participant" loop. Persists it as this project's output master,
  /// then reload so the stitched hero appears.
  Future<void> downloadOutput() async {
    final collaborative = _collaborative;
    final project = state.project;
    if (project == null || state.isBusy) return;
    if (collaborative == null) {
      state = state.copyWith(
          error: 'Collaborative mosaics are unavailable: no '
              'hub is configured for this screen.');
      return;
    }
    state = state.copyWith(isDownloading: true, clearError: true);
    try {
      await collaborative.downloadOutput(_projectId);
      await load();
      if (mounted) state = state.copyWith(isDownloading: false);
    } catch (e) {
      if (!mounted) return;
      state =
          state.copyWith(isDownloading: false, error: 'Download failed: $e');
    }
  }

  /// Dismiss the current error banner.
  void clearError() {
    if (state.error != null) state = state.copyWith(clearError: true);
  }
}

/// Per-panel master FITS base path under the DURABLE [artifactsBaseDir]:
/// `<base>/project_<id>/panel_<index>.fits`. The integration service derives the
/// preview `.png` + rejection map from it by extension swap.
String mosaicPanelOutputPath(
    String artifactsBaseDir, MosaicProjectPanel panel) {
  return p.join(
    artifactsBaseDir,
    'project_${panel.projectId}',
    'panel_${panel.panelIndex}.fits',
  );
}

/// Per-project stitched-mosaic artifacts directory under the DURABLE
/// [artifactsBaseDir]: `<base>/project_<id>`.
String mosaicStitchOutputDirectory(
  String artifactsBaseDir,
  MosaicProject project,
) {
  return p.join(artifactsBaseDir, 'project_${project.id}');
}

/// Arguments to construct a [MosaicProjectController] via its family provider —
/// the project id plus the DURABLE artifacts base directory the on-disk paths
/// are derived from (the app resolves `<applicationSupport>/nightshade_mosaic`;
/// tests pass a temp dir).
///
/// SHIP-BLOCKER CONTRACT — every field here must be VALUE-comparable. These args
/// are the family key: Riverpod caches one controller per distinct key, and the
/// screen rebuilds these args on every `build`. This used to carry the two path
/// BUILDER CLOSURES; a closure is only ever equal to itself, so every frame
/// minted a new key → a new controller → a new `load()` → a rebuild → an
/// unbounded loop that pinned the CPU and left the screen spinning forever.
/// Never put a closure (or any identity-compared object) on these args.
class MosaicProjectControllerArgs {
  /// The `mosaic_projects.id` to review.
  final int projectId;

  /// The durable directory panel masters and stitched artifacts live under.
  final String artifactsBaseDir;

  /// Integration settings the per-panel integration runs with.
  final IntegrationSettings integrationSettings;

  const MosaicProjectControllerArgs({
    required this.projectId,
    required this.artifactsBaseDir,
    this.integrationSettings = IntegrationSettings.defaults,
  });

  @override
  bool operator ==(Object other) =>
      other is MosaicProjectControllerArgs &&
      other.projectId == projectId &&
      other.artifactsBaseDir == artifactsBaseDir &&
      other.integrationSettings == integrationSettings;

  @override
  int get hashCode => Object.hash(
        projectId,
        artifactsBaseDir,
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
      collaborativeService: ref.watch(collaborativeMosaicServiceProvider),
      // The hub-aware service is always wired, so gate the collaborative
      // affordances on whether a hub is actually configured/signed-in. Reuses
      // the same signal the Constellation screens use; unknown-while-loading
      // resolves false so the actions fail closed rather than enabled-then-fail.
      hubConfigured:
          ref.watch(constellationConfiguredProvider).valueOrNull ?? false,
      // Derived from the value-comparable base dir on the args, NOT taken as
      // closures on the args themselves (see the contract note there).
      panelOutputPathBuilder: (panel) =>
          mosaicPanelOutputPath(args.artifactsBaseDir, panel),
      stitchOutputDirectory: (project) =>
          mosaicStitchOutputDirectory(args.artifactsBaseDir, project),
      captureLauncher: buildMosaicCaptureLauncher(ref),
      integrationSettings: args.integrationSettings,
    );
  },
);

/// Lists every durable mosaic project (newest first) for the projects list
/// screen. An `autoDispose` `FutureProvider` over [MosaicProjectsDao] so it
/// re-reads whenever the list screen is re-opened (a project created elsewhere
/// then shows on revisit); the screen also invalidates it on pull-to-refresh.
final mosaicProjectsListProvider =
    FutureProvider.autoDispose<List<MosaicProject>>((ref) async {
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

    // Hand the editor slot to the mosaic owner instead of clobbering unsaved
    // manual work: takeOwnership stashes the operator's sequence and flips the
    // owner so a later stop restores it.
    ref
        .read(currentSequenceProvider.notifier)
        .takeOwnership(sequence, ActivePlanOwner.mosaic);
    await ref.read(sequenceExecutorProvider).start();
  };
}
