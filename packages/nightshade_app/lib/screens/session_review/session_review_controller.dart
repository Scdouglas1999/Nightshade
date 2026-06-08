import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide BestNight;
// The controller exposes its own UI-facing [BestNight] (hours-based) to the
// panels; reach the core service type — also named `BestNight` — under a prefix
// so the two never collide.
import 'package:nightshade_core/nightshade_core.dart' as core
    show BestNight;
import 'package:path/path.dart' as p;

/// The core multi-night service's best-night value type, aliased so the
/// controller's UI-facing [BestNight] can shadow the bare name.
typedef CoreBestNight = core.BestNight;

/// Identifies which collection of subs the Session Review screen is reviewing:
/// a single imaging session, or every sub captured for a target (across nights).
class SessionReviewScope {
  /// Session id when scoped to one night, else null.
  final int? sessionId;

  /// Target id when scoped to all of a target's subs, else null.
  final int? targetId;

  const SessionReviewScope.session(int this.sessionId) : targetId = null;
  const SessionReviewScope.target(int this.targetId) : sessionId = null;

  bool get isSession => sessionId != null;

  @override
  bool operator ==(Object other) =>
      other is SessionReviewScope &&
      other.sessionId == sessionId &&
      other.targetId == targetId;

  @override
  int get hashCode => Object.hash(sessionId, targetId);
}

/// Which of the two renderings of the one [SessionReviewController] is showing:
/// the scrollable narrative (default) or the dense workbench. Held on
/// [SessionReviewState] so a single tap flips both views over the same model.
enum SessionReviewViewMode {
  /// The story view: hero → verdict → improvement curve → findings → growth.
  narrative,

  /// The dense panelled view: full sub table, field maps, mixer, A/B.
  workbench,
}

/// One point of a master's multi-night integration-time growth, projected for
/// the [GrowthCurvePanel]: cumulative integration *hours* as of a calendar
/// [date]. A thin UI mirror of the core [IntegrationGrowthPoint] (which carries
/// seconds + a running frame count) so the chart layer never touches the
/// service's wire model directly.
class GrowthPoint {
  /// Local calendar day (date-only; midnight UTC) the running total is as of.
  final DateTime date;

  /// Running cumulative integration time, in hours, through [date].
  final double cumulativeHours;

  /// Running accepted-frame count through [date].
  final int framesToDate;

  const GrowthPoint({
    required this.date,
    required this.cumulativeHours,
    required this.framesToDate,
  });

  /// Project a core [IntegrationGrowthPoint] (seconds) into UI hours.
  factory GrowthPoint.fromCore(IntegrationGrowthPoint p) => GrowthPoint(
        date: p.date,
        cumulativeHours: p.cumulativeIntegrationSeconds / 3600.0,
        framesToDate: p.framesToDate,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GrowthPoint &&
          other.date == date &&
          other.cumulativeHours == cumulativeHours &&
          other.framesToDate == framesToDate;

  @override
  int get hashCode => Object.hash(date, cumulativeHours, framesToDate);
}

/// The single best night folded into the reviewed master, for the
/// [GrowthCurvePanel] badge: the calendar [date] whose accepted subs carried
/// the highest mean integration weight, with its frame count and integration
/// time (hours). A thin UI mirror of the core [BestNight] service type
/// (which carries seconds) so the panels stay decoupled from the service model.
class BestNight {
  /// The night's local calendar day (date-only).
  final DateTime date;

  /// Mean integration weight over the night's accepted subs.
  final double meanWeight;

  /// Number of accepted subs folded that night.
  final int frameCount;

  /// Total integration time contributed that night, in hours.
  final double integrationHours;

  const BestNight({
    required this.date,
    required this.meanWeight,
    required this.frameCount,
    required this.integrationHours,
  });

  /// Project the core service [CoreBestNight] (seconds) into UI hours.
  factory BestNight.fromCore(CoreBestNight n) => BestNight(
        date: n.date,
        meanWeight: n.meanWeight,
        frameCount: n.frameCount,
        integrationHours: n.integrationSeconds / 3600.0,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BestNight &&
          other.date == date &&
          other.meanWeight == meanWeight &&
          other.frameCount == frameCount &&
          other.integrationHours == integrationHours;

  @override
  int get hashCode =>
      Object.hash(date, meanWeight, frameCount, integrationHours);
}

/// One single-channel narrowband master available to mix in the
/// [NarrowbandMixerPanel]: a labelled channel (e.g. `Ha`, `OIII`, `SII`) backed
/// by an on-disk linear FITS master.
class NarrowbandChannelRef {
  /// The persisted `integrated_masters` row id this channel comes from.
  final int masterId;

  /// Channel / filter label shown on the mixer row (e.g. `Ha`, `OIII`, `SII`).
  final String label;

  /// On-disk linear FITS master path the native combine consumes, or null when
  /// this master has not been finalized to a FITS yet.
  final String? fitsPath;

  const NarrowbandChannelRef({
    required this.masterId,
    required this.label,
    required this.fitsPath,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NarrowbandChannelRef &&
          other.masterId == masterId &&
          other.label == label &&
          other.fitsPath == fitsPath;

  @override
  int get hashCode => Object.hash(masterId, label, fitsPath);
}

/// Immutable view-model for the Session Review surface.
class SessionReviewState {
  /// Every light sub in scope (accepted and rejected), capture-time ascending.
  final List<DbCapturedImage> subs;

  /// Resolved display name for the header (target name, else session label).
  final String title;

  /// Target id backing this review (for master accumulation), or null.
  final int? targetId;

  /// Target display name (used when persisting a master), or null.
  final String? targetName;

  /// The integration settings the next run / re-integrate will use.
  final IntegrationSettings settings;

  /// Persisted masters for this target (newest first); empty when none.
  final List<IntegratedMaster> masters;

  /// True while subs are loading.
  final bool loading;

  /// True while an integration / accumulation run is in flight.
  final bool integrating;

  /// Coarse 0..1 progress of the running integration, or null when unknown.
  final double? integrationProgress;

  /// The most-recent integration outcome (drives the "image ready" banner +
  /// master viewer), or null before any run this session.
  final PostSessionIntegrationOutcome? lastOutcome;

  /// A user-facing error from the last failed action, or null.
  final String? error;

  // --- Smart Morning Report (Pillar 5) data backbone ------------------------

  /// The Night Doctor's verdict for this scope (score + headline + findings),
  /// or null before [SessionReviewController.loadSmartData] has run / produced
  /// one. Read by `NightReportPanel`.
  final NightReport? nightReport;

  /// The marginal-SNR keep/cull curve for the reviewed master (decoded from the
  /// master's `improvement_curve_json`), or null when no analysed master is in
  /// scope. Read by `ImprovementCurvePanel` and the curve-linked sub cull.
  final IntegrationCurve? improvementCurve;

  /// The ordered sub on-disk paths the [improvementCurve] was computed over —
  /// the population the optimizer's `keptIndices` index into, persisted with the
  /// curve. Empty when the stored curve carried no population (legacy rows). The
  /// curve-linked cull maps `keptIndices` through this list onto the live
  /// accepted subs and bails out when the population no longer matches, so a
  /// stale curve never rejects arbitrary subs.
  final List<String> improvementCurvePopulation;

  /// The multi-night integration-time growth series for the reviewed master
  /// (ascending by date; empty when single-night / no fold log). Read by
  /// `GrowthCurvePanel`.
  final List<GrowthPoint> growthPoints;

  /// The highest-mean-weight night folded into the reviewed master, or null.
  /// Drives the `GrowthCurvePanel` best-night badge.
  final BestNight? bestNight;

  /// The catalog-powered annotation layer over the finished master, or null
  /// when the master is un-solved / annotation is unavailable. Read by
  /// `MasterOverlayView`.
  final AnnotationLayer? annotationLayer;

  /// Which of the two renderings is showing (narrative default ↔ workbench).
  final SessionReviewViewMode viewMode;

  /// Live integration progress `(phase, fraction)` bound from the post-session
  /// seam's `IntegrationProgress` event stream, or null when no run is in
  /// flight. Drives the `NightshadeProgressBar`.
  final ({String phase, double fraction})? progress;

  /// True while [SessionReviewController.loadSmartData] is loading the smart
  /// backbone (night report / curve / growth / annotations).
  final bool loadingSmartData;

  /// True while a catalog colour-calibration re-integration is in flight.
  final bool calibrating;

  /// True while a background-extraction re-integration is in flight.
  final bool extractingBackground;

  /// True while a narrowband palette combine is in flight.
  final bool combiningNarrowband;

  const SessionReviewState({
    this.subs = const [],
    this.title = 'Session Review',
    this.targetId,
    this.targetName,
    this.settings = IntegrationSettings.defaults,
    this.masters = const [],
    this.loading = true,
    this.integrating = false,
    this.integrationProgress,
    this.lastOutcome,
    this.error,
    this.nightReport,
    this.improvementCurve,
    this.improvementCurvePopulation = const [],
    this.growthPoints = const [],
    this.bestNight,
    this.annotationLayer,
    this.viewMode = SessionReviewViewMode.narrative,
    this.progress,
    this.loadingSmartData = false,
    this.calibrating = false,
    this.extractingBackground = false,
    this.combiningNarrowband = false,
  });

  /// The newest persisted master in scope — the one the smart panels analyse
  /// (improvement curve, growth, annotations). Null when no masters exist.
  IntegratedMaster? get reviewedMaster =>
      masters.isNotEmpty ? masters.first : null;

  /// On-disk coverage-map PNG for the reviewed master, when one was written by
  /// the integration pipeline — fed to `MasterOverlayView`'s coverage overlay.
  /// Null until a coverage map is surfaced on the master row (none today).
  String? get coverageMapPath => null;

  /// The single-channel narrowband masters available to the
  /// `NarrowbandMixerPanel`: in-scope masters whose filter reads as narrowband
  /// (Ha / OIII / SII / NII / Hb), labelled by filter. A derived view over
  /// [masters] so the mixer composes off [SessionReviewState] alone.
  List<NarrowbandChannelRef> get narrowbandChannels {
    const hints = ['ha', 'oiii', 'o3', 'sii', 's2', 'nii', 'n2', 'hb'];
    final out = <NarrowbandChannelRef>[];
    for (final m in masters) {
      final filter = (m.filter ?? '').trim();
      final norm = filter.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (norm.isEmpty || !hints.any(norm.contains)) continue;
      out.add(NarrowbandChannelRef(
        masterId: m.id,
        label: filter,
        fitsPath: m.masterFitsPath,
      ));
    }
    return out;
  }

  /// True when any long-running finishing / integration action is in flight —
  /// the views disable their action buttons while this holds.
  bool get busy =>
      integrating ||
      calibrating ||
      extractingBackground ||
      combiningNarrowband;

  /// Light subs only (the integration population is always lights).
  List<DbCapturedImage> get lights =>
      subs.where((s) => s.frameType == 'light').toList(growable: false);

  /// Accepted light subs — the population an integration run consumes.
  List<DbCapturedImage> get acceptedLights =>
      lights.where((s) => s.isAccepted).toList(growable: false);

  int get acceptedCount => acceptedLights.length;
  int get rejectedCount => lights.length - acceptedCount;

  SessionReviewState copyWith({
    List<DbCapturedImage>? subs,
    String? title,
    int? targetId,
    String? targetName,
    IntegrationSettings? settings,
    List<IntegratedMaster>? masters,
    bool? loading,
    bool? integrating,
    double? integrationProgress,
    bool clearProgress = false,
    PostSessionIntegrationOutcome? lastOutcome,
    String? error,
    bool clearError = false,
    NightReport? nightReport,
    bool clearNightReport = false,
    IntegrationCurve? improvementCurve,
    bool clearImprovementCurve = false,
    List<String>? improvementCurvePopulation,
    List<GrowthPoint>? growthPoints,
    BestNight? bestNight,
    bool clearBestNight = false,
    AnnotationLayer? annotationLayer,
    bool clearAnnotationLayer = false,
    SessionReviewViewMode? viewMode,
    ({String phase, double fraction})? progress,
    bool clearLiveProgress = false,
    bool? loadingSmartData,
    bool? calibrating,
    bool? extractingBackground,
    bool? combiningNarrowband,
  }) {
    return SessionReviewState(
      subs: subs ?? this.subs,
      title: title ?? this.title,
      targetId: targetId ?? this.targetId,
      targetName: targetName ?? this.targetName,
      settings: settings ?? this.settings,
      masters: masters ?? this.masters,
      loading: loading ?? this.loading,
      integrating: integrating ?? this.integrating,
      integrationProgress:
          clearProgress ? null : (integrationProgress ?? this.integrationProgress),
      lastOutcome: lastOutcome ?? this.lastOutcome,
      error: clearError ? null : (error ?? this.error),
      nightReport: clearNightReport ? null : (nightReport ?? this.nightReport),
      improvementCurve: clearImprovementCurve
          ? null
          : (improvementCurve ?? this.improvementCurve),
      improvementCurvePopulation: clearImprovementCurve
          ? const []
          : (improvementCurvePopulation ?? this.improvementCurvePopulation),
      growthPoints: growthPoints ?? this.growthPoints,
      bestNight: clearBestNight ? null : (bestNight ?? this.bestNight),
      annotationLayer: clearAnnotationLayer
          ? null
          : (annotationLayer ?? this.annotationLayer),
      viewMode: viewMode ?? this.viewMode,
      progress: clearLiveProgress ? null : (progress ?? this.progress),
      loadingSmartData: loadingSmartData ?? this.loadingSmartData,
      calibrating: calibrating ?? this.calibrating,
      extractingBackground: extractingBackground ?? this.extractingBackground,
      combiningNarrowband: combiningNarrowband ?? this.combiningNarrowband,
    );
  }
}

/// Drives the Session Review / Morning Report screen.
///
/// Owns sub loading + culling (delegating accept/reject to [ImagesDao]), the
/// editable [IntegrationSettings], the integration / re-integrate runs (through
/// [PostSessionIntegrationService]) and multi-night accumulation (through
/// [MasterAccumulationService]), and the persisted [IntegratedMaster] list.
class SessionReviewController extends StateNotifier<SessionReviewState> {
  SessionReviewController(this._ref, this._scope)
      : super(const SessionReviewState()) {
    _bindProgress();
    _load();
  }

  final Ref _ref;
  final SessionReviewScope _scope;

  /// Live integration-progress subscription bound from the post-session seam's
  /// `IntegrationProgress` event stream; cancelled in [dispose].
  StreamSubscription<({String phase, double fraction})>? _progressSub;

  /// App-settings key for the default integration settings used by the panel
  /// and the auto-process hook.
  static const String kDefaultSettingsKey = 'post_session.default_settings';

  ImagesDao get _images => _ref.read(imagesDaoProvider);
  IntegratedMastersDao get _mastersDao =>
      _ref.read(integratedMastersDaoProvider);

  /// Bind [SessionReviewState.progress] to the seam's live integration-progress
  /// stream. Each native `IntegrationProgress` event maps straight to the
  /// `(phase, fraction)` record the `NightshadeProgressBar` renders. The stream
  /// is long-lived (broadcast off the backend event channel) and only carries
  /// data while a run is in flight; the run completion / failure paths clear the
  /// field. Bound once for the controller's lifetime.
  void _bindProgress() {
    final seam = _ref.read(postSessionSeamProvider);
    _progressSub = seam.integrationProgress().listen(
      (event) {
        if (!mounted) return;
        // A terminal 1.0 fraction is left on screen until the action's own
        // completion handler clears it (so the bar lands full, not mid-way).
        state = state.copyWith(progress: event);
      },
      onError: (_) {
        // A progress-stream error must never sink the screen; just stop
        // reporting live progress.
        if (mounted) state = state.copyWith(clearLiveProgress: true);
      },
    );
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _loadDefaultSettings();
      final subs = await _loadSubs();
      final (targetId, targetName) = await _resolveTarget(subs);
      final title = await _resolveTitle(targetName);
      final masters = targetId != null
          ? await _mastersDao.getForTarget(targetId)
          : await _mastersDao.getAll();

      if (!mounted) return;
      state = state.copyWith(
        subs: subs,
        title: title,
        targetId: targetId,
        targetName: targetName,
        settings: settings,
        masters: masters,
        loading: false,
        clearError: true,
      );
      // The base list is on screen; populate the smart backbone in the
      // background so the panels fill in without blocking the first paint.
      unawaited(loadSmartData());
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: 'Failed to load: $e');
    }
  }

  Future<List<DbCapturedImage>> _loadSubs() async {
    if (_scope.isSession) {
      return _images.getImagesForSession(_scope.sessionId!);
    }
    return _images.getImagesForTarget(_scope.targetId!);
  }

  Future<(int?, String?)> _resolveTarget(List<DbCapturedImage> subs) async {
    if (_scope.targetId != null) {
      final t = await _ref.read(targetsDaoProvider).getTargetById(_scope.targetId!);
      return (_scope.targetId, t?.name);
    }
    // Session scope: derive the dominant target from the subs.
    final targetId =
        subs.map((s) => s.targetId).firstWhere((id) => id != null, orElse: () => null);
    if (targetId == null) return (null, null);
    final t = await _ref.read(targetsDaoProvider).getTargetById(targetId);
    return (targetId, t?.name);
  }

  Future<String> _resolveTitle(String? targetName) async {
    if (targetName != null && targetName.trim().isNotEmpty) return targetName.trim();
    if (_scope.isSession) {
      final session =
          await _ref.read(sessionsDaoProvider).getSessionById(_scope.sessionId!);
      if (session != null) {
        final d = session.startTime.toLocal();
        return 'Night of ${d.year}-${_two(d.month)}-${_two(d.day)}';
      }
    }
    return 'Session Review';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  Future<IntegrationSettings> _loadDefaultSettings() async {
    final raw =
        await _ref.read(settingsDaoProvider).getSetting(kDefaultSettingsKey);
    return IntegrationSettings.fromJsonStringOrDefault(raw);
  }

  /// Refresh the sub list + master list from the database (after an external
  /// change, e.g. another screen rejected a frame).
  Future<void> refresh() => _load();

  /// Replace the working integration settings (panel edits). Not persisted as
  /// the default unless [persistAsDefault] is set.
  Future<void> updateSettings(
    IntegrationSettings settings, {
    bool persistAsDefault = false,
  }) async {
    state = state.copyWith(settings: settings);
    if (persistAsDefault) {
      await _ref
          .read(settingsDaoProvider)
          .setSetting(kDefaultSettingsKey, settings.toJsonString());
    }
  }

  /// Flip the accept/reject flag for a single sub and refresh the list.
  Future<void> setAccepted(int imageId, bool accepted) async {
    if (accepted) {
      await _images.acceptImage(imageId);
    } else {
      await _images.rejectImage(imageId, 'Manual quality flag');
    }
    await _reloadSubs();
  }

  /// Reject every accepted light sub whose HFR exceeds [hfrThreshold] (when
  /// non-null) OR whose quality score is below [qualityThreshold] (when
  /// non-null). Returns the number of subs newly rejected.
  Future<int> bulkReject({
    double? hfrThreshold,
    double? qualityThreshold,
  }) async {
    var rejected = 0;
    for (final sub in state.acceptedLights) {
      final failHfr = hfrThreshold != null &&
          sub.hfr != null &&
          sub.hfr! > hfrThreshold;
      final failQuality = qualityThreshold != null &&
          sub.qualityScore != null &&
          sub.qualityScore! < qualityThreshold;
      if (failHfr || failQuality) {
        await _images.rejectImage(
          sub.id,
          failHfr
              ? 'Bulk cull: HFR ${sub.hfr!.toStringAsFixed(2)} > '
                  '${hfrThreshold.toStringAsFixed(2)}'
              : 'Bulk cull: quality ${sub.qualityScore!.toStringAsFixed(0)} < '
                  '${qualityThreshold!.toStringAsFixed(0)}',
        );
        rejected++;
      }
    }
    if (rejected > 0) await _reloadSubs();
    return rejected;
  }

  Future<void> _reloadSubs() async {
    final subs = await _loadSubs();
    if (!mounted) return;
    state = state.copyWith(subs: subs);
  }

  /// Run a one-shot batch integration of the current accepted subs with the
  /// current settings, producing a fresh master. Returns the outcome, or null
  /// on failure (with [SessionReviewState.error] set).
  Future<PostSessionIntegrationOutcome?> integrate() async {
    final accepted = state.acceptedLights;
    if (accepted.isEmpty) {
      state = state.copyWith(error: 'No accepted subs to integrate.');
      return null;
    }
    state = state.copyWith(
      integrating: true,
      integrationProgress: 0,
      clearError: true,
    );
    try {
      final service = _ref.read(postSessionIntegrationServiceProvider);
      final outDir = await _outputDir();
      final outcomes = await service.integrate(
        subs: accepted,
        settings: state.settings,
        targetId: state.targetId,
        targetName: state.targetName,
        outputFitsPathBuilder: (filterBucket) {
          final stamp = DateTime.now().millisecondsSinceEpoch;
          final base = _safeName(state.title);
          final filterTag = filterBucket == PostSessionIntegrationService
                  .noFilterBucket
              ? ''
              : '_${_safeName(filterBucket)}';
          return p.join(outDir, '$base${filterTag}_master_$stamp.fits');
        },
      );
      final masters = await _refreshMasters();
      final first = outcomes.isNotEmpty ? outcomes.first : null;
      if (!mounted) return first;
      state = state.copyWith(
        integrating: false,
        clearProgress: true,
        clearLiveProgress: true,
        lastOutcome: first,
        masters: masters,
      );
      // A fresh master invalidates the smart backbone — re-derive it.
      unawaited(loadSmartData());
      return first;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        integrating: false,
        clearProgress: true,
        clearLiveProgress: true,
        error: 'Integration failed: $e',
      );
      return null;
    }
  }

  // ===========================================================================
  // Smart Morning Report (Pillar 5) — data backbone + finishing actions
  // ===========================================================================

  /// Load (or refresh) the smart-report backbone the narrative + workbench
  /// panels read: the Night Doctor [NightReport], the reviewed master's
  /// marginal-SNR [IntegrationCurve], its multi-night [GrowthPoint] growth
  /// series + [BestNight], and the catalog [AnnotationLayer].
  ///
  /// Every source is loaded fail-soft and independently: a failure in any one
  /// leaves that field null/empty rather than sinking the whole load, so a
  /// single-night session (no master, no growth) still gets its night report,
  /// and a master with no persisted curve still gets growth + annotations.
  Future<void> loadSmartData() async {
    if (!mounted) return;
    state = state.copyWith(loadingSmartData: true);

    final report = await _loadNightReport();
    final master = state.reviewedMaster;
    final (curve, population) = master != null
        ? await _loadImprovementCurve(master.id)
        : (null, const <String>[]);
    final (growth, best) =
        master != null ? await _loadGrowthAndBestNight(master.id) : (const <GrowthPoint>[], null);
    final annotations =
        master != null ? await _loadAnnotationLayer(master) : null;

    if (!mounted) return;
    state = state.copyWith(
      loadingSmartData: false,
      nightReport: report,
      clearNightReport: report == null,
      improvementCurve: curve,
      clearImprovementCurve: curve == null,
      improvementCurvePopulation: population,
      growthPoints: growth,
      bestNight: best,
      clearBestNight: best == null,
      annotationLayer: annotations,
      clearAnnotationLayer: annotations == null,
    );
  }

  /// The Night Doctor verdict for this scope. Prefers the most-recent persisted
  /// report (cheap read); computes + persists one on first view. Fail-soft to
  /// null so the panel shows its "analysis pending" state rather than an error.
  Future<NightReport?> _loadNightReport() async {
    try {
      final reports = _ref.read(nightReportsDaoProvider);
      if (_scope.isSession) {
        final stored = await reports.latestForSession(_scope.sessionId!);
        if (stored != null) return stored;
      } else if (_scope.targetId != null) {
        final stored = await reports.getForTarget(_scope.targetId!);
        if (stored.isNotEmpty) return stored.first;
      }
      // No stored report yet — compute (and persist) one.
      return _ref.read(nightAnalysisServiceProvider).computeReport(
            sessionId: _scope.sessionId,
            targetId: _scope.targetId ?? state.targetId,
          );
    } catch (_) {
      return null;
    }
  }

  /// Decode the reviewed master's persisted marginal-SNR curve from its
  /// `improvement_curve_json` column (not surfaced on the typed model, so read
  /// directly), together with the ordered sub-path population the curve was
  /// computed over (stored as a sibling `population` key). Returns
  /// `(null, [])` when absent / corrupt — the panel placeholders.
  Future<(IntegrationCurve?, List<String>)> _loadImprovementCurve(
    int masterId,
  ) async {
    try {
      final rows = await _ref.read(databaseProvider).customSelect(
        'SELECT improvement_curve_json FROM integrated_masters '
        'WHERE id = ? LIMIT 1',
        variables: [Variable<int>(masterId)],
      ).get();
      if (rows.isEmpty) return (null, const <String>[]);
      final json = rows.first.readNullable<String>('improvement_curve_json');
      if (json == null || json.trim().isEmpty) return (null, const <String>[]);
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        final rawPopulation = decoded['population'];
        final population = <String>[
          if (rawPopulation is List)
            for (final e in rawPopulation)
              if (e is String) e,
        ];
        return (IntegrationCurve.fromJson(decoded), population);
      }
      return (null, const <String>[]);
    } catch (_) {
      return (null, const <String>[]);
    }
  }

  /// The reviewed master's multi-night growth series + best night, projected
  /// from the core [SmartProjectService] into the UI hour-based types. Both fail
  /// soft (empty / null) so a single-night master simply has no growth panel.
  Future<(List<GrowthPoint>, BestNight?)> _loadGrowthAndBestNight(
    int masterId,
  ) async {
    try {
      final smart = _ref.read(smartProjectServiceProvider);
      final corePoints = await smart.growthCurve(masterId);
      final coreBest = await smart.bestNight(masterId);
      return (
        corePoints.map(GrowthPoint.fromCore).toList(growable: false),
        coreBest != null ? BestNight.fromCore(coreBest) : null,
      );
    } catch (_) {
      return (const <GrowthPoint>[], null);
    }
  }

  /// The catalog-powered annotation layer over the finished master.
  ///
  /// Building it needs the master's solved WCS (RA/Dec reference + pixel scale),
  /// which is not plumbed onto the [IntegratedMaster] row at this layer yet —
  /// so without a WCS source this fail-softs to null and the overlay simply
  /// shows no annotation toggle. The [MasterAnnotationService] seam is wired
  /// here so the layer fills in automatically once a master WCS is surfaced.
  Future<AnnotationLayer?> _loadAnnotationLayer(IntegratedMaster master) async {
    final wcs = _resolveMasterWcs(master);
    if (wcs == null) return null;
    try {
      final service = _ref.read(masterAnnotationServiceProvider);
      final (fovW, fovH) = wcs.fieldOfView(master.width, master.height);
      final layer = await service.annotate(
        wcs: wcs,
        width: master.width,
        height: master.height,
        fovDeg: fovW > fovH ? fovW : fovH,
      );
      return layer.items.isEmpty ? null : layer;
    } catch (_) {
      return null;
    }
  }

  /// Resolve the reviewed master's solved WCS, or null when none is available.
  ///
  /// The post-session master row carries no solved WCS today; returning null is
  /// the honest fail-soft until a per-master WCS is persisted. Centralised here
  /// so the wiring is a one-line change when that source lands.
  WcsOverlay? _resolveMasterWcs(IntegratedMaster master) => null;

  /// Re-run the integration of the current accepted subs with [settings],
  /// producing a fresh master. The narrative/workbench finishing actions
  /// (`runColorCalibration`, `runBackgroundExtraction`, `runNarrowband`) and the
  /// integration-settings A/B panel all funnel through this so they share the
  /// one progress binding + smart-data refresh. [settings] also becomes the
  /// working settings. Returns the first outcome, or null on failure.
  Future<PostSessionIntegrationOutcome?> reIntegrate(
    IntegrationSettings settings,
  ) async {
    state = state.copyWith(settings: settings);
    return integrate();
  }

  /// Run a **throwaway, non-persisting** integration of the current accepted
  /// subs with [settings] and return the outcome, for exploratory comparison
  /// (the A/B recipe panel). Unlike [reIntegrate] this does **not** mutate the
  /// working `state.settings`, does not persist an `integrated_masters` row,
  /// does not refresh the master list / `lastOutcome`, and does not re-derive
  /// the smart backbone — so an A/B comparison never changes what "Re-integrate"
  /// or the narrative finishing actions use, and never pollutes the master
  /// library or the hero/growth/annotation state. Returns null on failure (with
  /// no error surfaced on state, since this is a side panel's concern).
  ///
  /// The returned outcome carries a sentinel `masterId` of `-1` — it is a
  /// preview, not a persisted master.
  Future<PostSessionIntegrationOutcome?> reIntegratePreview(
    IntegrationSettings settings,
  ) async {
    final accepted = state.acceptedLights;
    if (accepted.isEmpty) return null;
    try {
      final service = _ref.read(postSessionIntegrationServiceProvider);
      final result = await service.previewIntegrate(
        subs: accepted,
        settings: settings,
      );
      if (result == null) return null;
      return PostSessionIntegrationOutcome(
        masterId: -1,
        filter: accepted.first.filter,
        result: result,
      );
    } catch (_) {
      return null;
    }
  }

  /// Re-integrate with catalog colour calibration enabled — the narrative
  /// "calibrate colour" action. A no-op-safe wrapper over [reIntegrate].
  Future<PostSessionIntegrationOutcome?> runColorCalibration() async {
    state = state.copyWith(calibrating: true, clearError: true);
    try {
      return await reIntegrate(state.settings.copyWith(colorCalibrate: true));
    } finally {
      if (mounted) state = state.copyWith(calibrating: false);
    }
  }

  /// Re-integrate with background extraction enabled — the "flatten gradient"
  /// action.
  Future<PostSessionIntegrationOutcome?> runBackgroundExtraction() async {
    state = state.copyWith(extractingBackground: true, clearError: true);
    try {
      return await reIntegrate(state.settings.copyWith(extractBackground: true));
    } finally {
      if (mounted) state = state.copyWith(extractingBackground: false);
    }
  }

  /// Combine the supplied single-channel narrowband [channels] into an RGB
  /// composite under [palette] (`'sho'` / `'hoo'` / `'custom'`) with the given
  /// per-input `[r,g,b]` [weights], writing the composite FITS. Routes through
  /// the post-session seam's `combineChannels`. Returns the written composite
  /// path, or null when the inputs are insufficient / the combine fails.
  ///
  /// [palette] mirrors the `NarrowbandMixerPanel`'s preset-or-custom token; when
  /// it is `'custom'` the explicit [weights] matrix is sent, otherwise the
  /// native canonical palette table is used.
  Future<String?> runNarrowband(
    String palette,
    List<List<double>> weights, {
    List<NarrowbandChannelRef>? channels,
  }) async {
    final refs = channels ?? state.narrowbandChannels;
    final inputs = [
      for (final c in refs)
        if (c.fitsPath != null) c.fitsPath!,
    ];
    if (inputs.length < 2) {
      state = state.copyWith(
        error: 'Need at least two finalized narrowband masters to combine.',
      );
      return null;
    }
    state = state.copyWith(combiningNarrowband: true, clearError: true);
    try {
      final seam = _ref.read(postSessionSeamProvider);
      final outDir = await _outputDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final output =
          p.join(outDir, '${_safeName(state.title)}_${_safeName(palette)}_$stamp.fits');
      final isCustom = palette.toLowerCase() == 'custom';
      final outputPath = await seam.combineChannels(<String, dynamic>{
        'inputs': inputs,
        'palette': palette,
        if (isCustom) 'weights': weights,
        'output': output,
      });
      return outputPath;
    } catch (e) {
      if (mounted) state = state.copyWith(error: 'Narrowband combine failed: $e');
      return null;
    } finally {
      if (mounted) state = state.copyWith(combiningNarrowband: false);
    }
  }

  /// The single-channel narrowband masters available to the mixer — a
  /// controller-method alias of [SessionReviewState.narrowbandChannels] so a
  /// view holding only the controller (not the state snapshot) can list them.
  List<NarrowbandChannelRef> narrowbandChannels() => state.narrowbandChannels;

  /// Flip the active rendering between the narrative and the workbench. With no
  /// argument it toggles; pass [mode] to set it directly.
  void setViewMode([SessionReviewViewMode? mode]) {
    final next = mode ??
        (state.viewMode == SessionReviewViewMode.narrative
            ? SessionReviewViewMode.workbench
            : SessionReviewViewMode.narrative);
    if (next == state.viewMode) return;
    state = state.copyWith(viewMode: next);
  }

  /// Cull the accepted light subs down to the improvement curve's recommended
  /// keep-set: reject every accepted sub *not* in the optimizer's kept indices,
  /// leaving exactly `keepN` accepted. The "drop to recommended {keepN}" action
  /// the `SubCullRail` wires to the curve. No-op (returns 0) when no curve /
  /// recommendation is loaded. Returns the number of subs newly rejected.
  Future<int> cullToRecommended() async {
    final curve = state.improvementCurve;
    if (curve == null) return 0;
    final rec = curve.recommendation;
    if (rec.keepN <= 0) return 0;

    // The optimizer's `keptIndices` are positions into the *population the curve
    // was computed over* — `improvementCurvePopulation`, the ordered sub paths
    // recorded when the master was built. They are NOT raw positions into the
    // live `acceptedLights`, which may have changed (subs accepted/rejected
    // since, or a different ordering) and whose `SubsetRecommendation` documents
    // the indices as weight-ranked, not capture-ranked. So resolve `keptIndices`
    // → population paths → live subs, and bail out unless the population still
    // matches the live accepted set exactly. A stale/mismatched curve must never
    // reject arbitrary subs.
    final population = state.improvementCurvePopulation;
    final accepted = state.acceptedLights;
    if (accepted.isEmpty) return 0;

    // Guard: the curve must carry a population, and that population must be the
    // same set of subs (by path) that is currently accepted — otherwise the
    // index space no longer maps to these subs.
    if (population.length != accepted.length) return 0;
    final acceptedByPath = <String, DbCapturedImage>{
      for (final s in accepted) s.filePath: s,
    };
    if (acceptedByPath.length != accepted.length) return 0; // duplicate paths
    for (final path in population) {
      if (!acceptedByPath.containsKey(path)) return 0; // population diverged
    }

    if (rec.keepN >= population.length) return 0;

    // Map the kept indices through the population's paths to the live subs to
    // keep; everything accepted but not in that keep-set is culled.
    final keepPaths = <String>{
      for (final idx in rec.keptIndices)
        if (idx >= 0 && idx < population.length) population[idx],
    };
    var rejected = 0;
    for (final sub in accepted) {
      if (keepPaths.contains(sub.filePath)) continue;
      await _images.rejectImage(
        sub.id,
        'Curve cull: outside recommended best ${rec.keepN} of ${population.length}',
      );
      rejected++;
    }
    if (rejected > 0) {
      await _reloadSubs();
      // The kept population changed; the curve recommendation no longer maps to
      // the same indices, so re-derive the backbone.
      unawaited(loadSmartData());
    }
    return rejected;
  }

  /// Fold the current accepted subs into an accumulating master for this
  /// target+filter, creating one on first use. Used by the multi-night
  /// "add tonight's data" action.
  Future<MasterAccumulateResult?> addToAccumulatingMaster({
    required IntegratedMaster master,
  }) async {
    final accepted = state.acceptedLights
        .where((s) => _filterMatches(s.filter, master.filter))
        .toList();
    if (accepted.isEmpty) {
      state = state.copyWith(error: 'No accepted subs match this master.');
      return null;
    }
    state = state.copyWith(integrating: true, clearError: true);
    try {
      final service = _ref.read(masterAccumulationServiceProvider);
      final label = DateTime.now().toIso8601String().split('T').first;
      final result = await service.addNight(
        masterId: master.id,
        subs: accepted,
        label: label,
        settings: state.settings,
      );
      final masters = await _refreshMasters();
      if (!mounted) return result;
      state = state.copyWith(
        integrating: false,
        masters: masters,
      );
      return result;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        integrating: false,
        error: 'Add to master failed: $e',
      );
      return null;
    }
  }

  /// Create a brand-new accumulating master for this target+filter from the
  /// best accepted sub as the reference.
  Future<int?> createAccumulatingMaster({String? filter}) async {
    final accepted = state.acceptedLights
        .where((s) => filter == null || _filterMatches(s.filter, filter))
        .toList();
    if (accepted.isEmpty) {
      state = state.copyWith(error: 'No accepted subs to seed a master.');
      return null;
    }
    state = state.copyWith(integrating: true, clearError: true);
    try {
      final service = _ref.read(masterAccumulationServiceProvider);
      final outDir = await _outputDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final sidecar = p.join(
        outDir,
        '${_safeName(state.title)}_${_safeName(filter ?? 'master')}_$stamp.nsmaster',
      );
      final reference = _bestReference(accepted);
      final masterId = await service.createMaster(
        referenceSub: reference,
        sidecarPath: sidecar,
        settings: state.settings,
        targetId: state.targetId,
        targetName: state.targetName,
        filter: filter,
      );
      // Immediately fold the night's subs in.
      final master = await _mastersDao.getById(masterId);
      if (master != null) {
        await service.addNight(
          masterId: masterId,
          subs: accepted,
          label: DateTime.now().toIso8601String().split('T').first,
          settings: state.settings,
        );
      }
      final masters = await _refreshMasters();
      if (!mounted) return masterId;
      state = state.copyWith(integrating: false, masters: masters);
      return masterId;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        integrating: false,
        error: 'Create master failed: $e',
      );
      return null;
    }
  }

  /// Finalize an accumulating master to a shareable FITS + preview.
  Future<void> finalizeMaster(IntegratedMaster master) async {
    state = state.copyWith(integrating: true, clearError: true);
    try {
      final service = _ref.read(masterAccumulationServiceProvider);
      final outDir = await _outputDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fits =
          p.join(outDir, '${_safeName(master.name)}_final_$stamp.fits');
      final preview =
          p.join(outDir, '${_safeName(master.name)}_final_$stamp.png');
      await service.finalizeMaster(
        masterId: master.id,
        masterFitsPath: fits,
        previewPngPath: preview,
      );
      final masters = await _refreshMasters();
      if (!mounted) return;
      state = state.copyWith(integrating: false, masters: masters);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        integrating: false,
        error: 'Finalize failed: $e',
      );
    }
  }

  /// Delete a master row (its fold records cascade in the DB).
  Future<void> deleteMaster(IntegratedMaster master) async {
    await _mastersDao.deleteMaster(master.id);
    final masters = await _refreshMasters();
    if (!mounted) return;
    state = state.copyWith(masters: masters);
  }

  DbCapturedImage _bestReference(List<DbCapturedImage> subs) {
    DbCapturedImage best = subs.first;
    for (final s in subs.skip(1)) {
      final bq = best.qualityScore, sq = s.qualityScore;
      if (sq != null && (bq == null || sq > bq)) {
        best = s;
      } else if (sq != null && bq != null && sq == bq) {
        if ((s.hfr ?? double.infinity) < (best.hfr ?? double.infinity)) best = s;
      }
    }
    return best;
  }

  Future<List<IntegratedMaster>> _refreshMasters() {
    final tid = state.targetId;
    return tid != null ? _mastersDao.getForTarget(tid) : _mastersDao.getAll();
  }

  Future<String> _outputDir() async {
    final configured =
        await _ref.read(settingsDaoProvider).getSetting('default_image_directory');
    if (configured != null && configured.trim().isNotEmpty) {
      return p.join(configured.trim(), 'masters');
    }
    // Fall back to the documents dir under a masters subfolder.
    return p.join('.', 'masters');
  }

  static bool _filterMatches(String? subFilter, String? masterFilter) {
    final s = (subFilter ?? '').trim();
    final m = (masterFilter ?? '').trim();
    return s == m;
  }

  static String _safeName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'session' : cleaned;
  }
}

/// Family provider keyed by the review scope so a session view and a target
/// view are independent controllers.
final sessionReviewControllerProvider = StateNotifierProvider.family<
    SessionReviewController, SessionReviewState, SessionReviewScope>(
  (ref, scope) => SessionReviewController(ref, scope),
);
