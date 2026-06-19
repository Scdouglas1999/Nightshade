import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart' hide BestNight;
// The controller exposes its own UI-facing [BestNight] (hours-based) to the
// panels; reach the core service type — also named `BestNight` — under a prefix
// so the two never collide.
import 'package:nightshade_core/nightshade_core.dart' as core show BestNight;
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

  /// True while a background-extraction finishing pass is in flight.
  final bool extractingBackground;

  /// True while a deconvolution-preview finishing pass is in flight.
  final bool deconvolving;

  /// True while a star-reduction-preview finishing pass is in flight.
  final bool reducingStars;

  /// True while a narrowband palette combine is in flight.
  final bool combiningNarrowband;

  /// The most-recently applied narrowband palette composite (the persisted
  /// `narrowband_composites` row written by [SessionReviewController.runNarrowband]),
  /// or null when none has been produced this session. Drives the workbench's
  /// composite result card.
  final NarrowbandComposite? narrowbandComposite;

  /// Every persisted narrowband composite in scope, newest first — the
  /// "composites" list read from [NarrowbandCompositesDao]. Empty until loaded.
  final List<NarrowbandComposite> narrowbandComposites;

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
    this.deconvolving = false,
    this.reducingStars = false,
    this.combiningNarrowband = false,
    this.narrowbandComposite,
    this.narrowbandComposites = const [],
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
      deconvolving ||
      reducingStars ||
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
    bool? deconvolving,
    bool? reducingStars,
    bool? combiningNarrowband,
    NarrowbandComposite? narrowbandComposite,
    bool clearNarrowbandComposite = false,
    List<NarrowbandComposite>? narrowbandComposites,
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
      integrationProgress: clearProgress
          ? null
          : (integrationProgress ?? this.integrationProgress),
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
      deconvolving: deconvolving ?? this.deconvolving,
      reducingStars: reducingStars ?? this.reducingStars,
      combiningNarrowband: combiningNarrowband ?? this.combiningNarrowband,
      narrowbandComposite: clearNarrowbandComposite
          ? null
          : (narrowbandComposite ?? this.narrowbandComposite),
      narrowbandComposites: narrowbandComposites ?? this.narrowbandComposites,
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
  NarrowbandCompositesDao get _compositesDao =>
      _ref.read(narrowbandCompositesDaoProvider);

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
      final t =
          await _ref.read(targetsDaoProvider).getTargetById(_scope.targetId!);
      return (_scope.targetId, t?.name);
    }
    // Session scope: derive the dominant target from the subs.
    final targetId = subs
        .map((s) => s.targetId)
        .firstWhere((id) => id != null, orElse: () => null);
    if (targetId == null) return (null, null);
    final t = await _ref.read(targetsDaoProvider).getTargetById(targetId);
    return (targetId, t?.name);
  }

  /// The reviewed target's catalog coordinates (RA in decimal hours, Dec in
  /// decimal degrees) for hinting the master plate-solve, or `(null, null)` when
  /// no target / coordinates are known (the solve then runs blind).
  Future<(double?, double?)> _resolveTargetHint() async {
    final id = state.targetId;
    if (id == null) return (null, null);
    final t = await _ref.read(targetsDaoProvider).getTargetById(id);
    if (t == null) return (null, null);
    return (t.ra, t.dec);
  }

  Future<String> _resolveTitle(String? targetName) async {
    if (targetName != null && targetName.trim().isNotEmpty) {
      return targetName.trim();
    }
    if (_scope.isSession) {
      final session = await _ref
          .read(sessionsDaoProvider)
          .getSessionById(_scope.sessionId!);
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
      final failHfr =
          hfrThreshold != null && sub.hfr != null && sub.hfr! > hfrThreshold;
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
      // Catalog coordinates (RA hours / Dec degrees) hint the master plate-solve
      // so the WCS persist is fast/robust; null falls back to a blind solve.
      final (hintRaHours, hintDecDegrees) = await _resolveTargetHint();
      final outcomes = await service.integrate(
        subs: accepted,
        settings: state.settings,
        targetId: state.targetId,
        targetName: state.targetName,
        hintRaHours: hintRaHours,
        hintDecDegrees: hintDecDegrees,
        outputFitsPathBuilder: (filterBucket) {
          final stamp = DateTime.now().millisecondsSinceEpoch;
          final base = _safeName(state.title);
          final filterTag =
              filterBucket == PostSessionIntegrationService.noFilterBucket
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
    final (growth, best) = master != null
        ? await _loadGrowthAndBestNight(master.id)
        : (const <GrowthPoint>[], null);
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

  /// Resolve the reviewed master's solved WCS, or null when none is persisted.
  ///
  /// The master row now carries its plate-solved WCS as the eight CD-matrix
  /// scalars (v44), written by the post-session integration's fail-soft
  /// plate-solve step. `WcsOverlay` consumes the cdelt/crota form, so this
  /// derives them from the CD matrix using the inverse of the native sign
  /// convention (`WcsInfo::from_plate_solve`, `imaging/src/fits.rs`):
  /// `cd1_1 = -scale·cosθ`, `cd2_1 = scale·sinθ`, `cd2_2 = scale·cosθ`, hence
  /// `cdelt1 = -‖(cd1_1, cd2_1)‖` (RA negative), `cdelt2 = ‖(cd1_2, cd2_2)‖`,
  /// and `crota2 = atan2(cd2_1, cd2_2)`. Returns null (the honest fail-soft)
  /// until a WCS is persisted, which keeps the annotation overlay + colour
  /// calibration cleanly un-lit.
  WcsOverlay? _resolveMasterWcs(IntegratedMaster master) {
    if (!master.hasWcs) return null;
    final cd11 = master.wcsCd1_1;
    final cd12 = master.wcsCd1_2;
    final cd21 = master.wcsCd2_1;
    final cd22 = master.wcsCd2_2;
    if (cd11 == null || cd12 == null || cd21 == null || cd22 == null) {
      return null;
    }

    final cdelt1 = -math.sqrt(cd11 * cd11 + cd21 * cd21); // RA: negative.
    final cdelt2 = math.sqrt(cd12 * cd12 + cd22 * cd22);
    final crota2 = math.atan2(cd21, cd22) * 180.0 / math.pi;

    return WcsOverlay(
      crpix1: master.wcsCrpix1 ?? master.width / 2,
      crpix2: master.wcsCrpix2 ?? master.height / 2,
      crval1: master.wcsCrval1!,
      crval2: master.wcsCrval2!,
      cdelt1: cdelt1,
      cdelt2: cdelt2,
      crota2: crota2,
    );
  }

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

  /// Catalog colour-calibrate the **current reviewed master** as a
  /// non-destructive post-step on its finished FITS — the narrative / workbench
  /// "Calibrate color" action. Unlike a re-integration this never re-runs the
  /// stack: it detects + photometers stars on the master, cross-matches them to
  /// the catalog using the master's persisted WCS, solves the per-channel white
  /// balance via [ColorCalibrationService], writes `<master>_color.fits`, renders
  /// a sibling preview PNG, persists the path via the v42 `color_calibrated_path`
  /// column, and refreshes the master list so the result survives reload.
  ///
  /// Needs a master with a solved WCS: without one the cross-match cannot place
  /// detections on the sky, so the action surfaces an error rather than silently
  /// producing an unchanged master. A solved-but-sparse field (too few catalog
  /// cross-matches) also surfaces a "could not calibrate" message. Returns the
  /// written calibrated FITS path, or null when there is no master / no WCS / the
  /// pass skipped or failed.
  Future<String?> runColorCalibration() async {
    final master = state.reviewedMaster;
    final inputFits = master?.masterFitsPath;
    if (master == null || inputFits == null || inputFits.trim().isEmpty) {
      state = state.copyWith(
        error: 'Color calibration needs a finished master FITS — integrate '
            'first.',
      );
      return null;
    }
    final wcs = _resolveMasterWcs(master);
    if (wcs == null) {
      state = state.copyWith(
        error: 'Color calibration needs a plate-solved master (WCS) to match '
            'catalog stars — none is available for this master.',
      );
      return null;
    }
    state = state.copyWith(calibrating: true, clearError: true);
    try {
      final service = _ref.read(colorCalibrationServiceProvider);
      final output =
          SessionReviewController._suffixBeforeExtension(inputFits, '_color');
      final result = await service.calibrate(
        masterFits: inputFits,
        outputFits: output,
        wcs: wcs,
        channels: master.channels,
        whiteRefBv: state.settings.whiteRefBv,
      );
      if (ColorCalibrationService.wasSkipped(result)) {
        if (mounted) {
          state = state.copyWith(
            error: 'Color calibration found too few catalog cross-matches in '
                'this field to solve a white balance.',
          );
        }
        return null;
      }
      // Render a sibling preview PNG so the calibrated result is viewable;
      // fail-soft so a render failure never sinks the written FITS or its path.
      final previewPng =
          SessionReviewController._swapExtension(result.outputPath, '.png');
      try {
        await _ref.read(finishingPreviewRendererProvider)(
            result.outputPath, previewPng);
      } catch (_) {
        // Leave the FITS path persisted; the overlay simply shows no preview.
      }
      await _mastersDao.updateSmartFields(
        master.id,
        colorCalibratedPath: result.outputPath,
      );
      final masters = await _refreshMasters();
      if (!mounted) return result.outputPath;
      state = state.copyWith(masters: masters);
      return result.outputPath;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: 'Color calibration failed: $e');
      }
      return null;
    } finally {
      if (mounted) state = state.copyWith(calibrating: false);
    }
  }

  /// Background-extract (gradient-flatten) the **current reviewed master** as a
  /// non-destructive post-step on its finished FITS — the workbench "Background
  /// extract" action. Unlike a re-integration this never re-runs the stack: it
  /// flattens the existing master FITS via the post-session seam
  /// (`extractBackground`), writes `<master>_bgx.fits`, renders a sibling preview
  /// PNG, persists the path via [IntegratedMastersDao.updateFinishingPaths] (the
  /// v44 `background_extracted_path` column), and refreshes the master list so
  /// the result round-trips on reload. Returns the written FITS path, or null
  /// when there is no master / the pass fails.
  Future<String?> runBackgroundExtraction() async {
    return _runFinishingStep(
      busy: (v) => state.copyWith(extractingBackground: v),
      suffix: '_bgx',
      label: 'Background extraction',
      invoke: (seam, master, output) =>
          seam.extractBackground(<String, dynamic>{
        'inputFits': master.masterFitsPath,
        'outputFits': output,
        'config': <String, dynamic>{
          'polyDegree': state.settings.backgroundPolyDegree,
          'preserveMean': state.settings.backgroundPreserveMean,
        },
      }),
      persist: (id, path) => _mastersDao.updateFinishingPaths(
        id,
        backgroundExtractedPath: path,
      ),
      alsoMark: (id) =>
          _mastersDao.updateSmartFields(id, backgroundExtracted: true),
    );
  }

  /// Deconvolve (Richardson–Lucy preview) the **current reviewed master** as a
  /// non-destructive post-step on its finished FITS — the workbench "Deconvolve"
  /// action. Writes `<master>_decon.fits`, renders a sibling preview PNG,
  /// persists the path via the v44 `deconvolved_path` column, and refreshes so
  /// the result survives reload. Returns the written FITS path, or null when
  /// there is no master / the pass fails.
  Future<String?> runDeconvolve() async {
    return _runFinishingStep(
      busy: (v) => state.copyWith(deconvolving: v),
      suffix: '_decon',
      label: 'Deconvolution',
      invoke: (seam, master, output) =>
          seam.deconvolvePreview(<String, dynamic>{
        'inputFits': master.masterFitsPath,
        'outputFits': output,
        'config': <String, dynamic>{
          'iterations': state.settings.deconIterations,
          'regularization': state.settings.deconRegularization,
        },
      }),
      persist: (id, path) =>
          _mastersDao.updateFinishingPaths(id, deconvolvedPath: path),
    );
  }

  /// Reduce stars (mask-confined preview) on the **current reviewed master** as
  /// a non-destructive post-step on its finished FITS — the workbench "Reduce
  /// stars" action. Writes `<master>_starred.fits`, renders a sibling preview
  /// PNG, persists the path via the v44 `star_reduced_path` column, and
  /// refreshes so the result survives reload. Returns the written FITS path, or
  /// null when there is no master / the pass fails.
  Future<String?> runStarReduction() async {
    return _runFinishingStep(
      busy: (v) => state.copyWith(reducingStars: v),
      suffix: '_starred',
      label: 'Star reduction',
      invoke: (seam, master, output) =>
          seam.reduceStarsPreview(<String, dynamic>{
        'inputFits': master.masterFitsPath,
        'outputFits': output,
        'config': <String, dynamic>{
          'strength': state.settings.starReductionStrength,
          'method': state.settings.starReduceMethod.wire,
        },
      }),
      persist: (id, path) =>
          _mastersDao.updateFinishingPaths(id, starReducedPath: path),
    );
  }

  /// Shared engine for the three workbench finishing actions (background
  /// extraction / deconvolution / star reduction). Each operates on the current
  /// reviewed master's finished FITS, never re-running the stack:
  ///
  ///  1. Guard a reviewed master that carries a `masterFitsPath` on disk.
  ///  2. Flip the action's [busy] flag (via [SessionReviewController.state]).
  ///  3. [invoke] the post-session seam, writing `<master><suffix>.fits`.
  ///  4. Render a sibling preview PNG (`<master><suffix>.png`) via the injected
  ///     [finishingPreviewRendererProvider] so `MasterOverlayView` can show the
  ///     before/after — fail-soft: a render failure still keeps the FITS path.
  ///  5. [persist] the written FITS path onto the row (and [alsoMark] any extra
  ///     bookkeeping column, e.g. `background_extracted`).
  ///  6. Refresh the master list so the new artifact path round-trips on reload.
  ///
  /// Returns the written FITS path, or null when no master is in scope or the
  /// pass throws (the error surfaces on [SessionReviewState.error]).
  Future<String?> _runFinishingStep({
    required SessionReviewState Function(bool busy) busy,
    required String suffix,
    required String label,
    required Future<String> Function(
      PostSessionSeam seam,
      IntegratedMaster master,
      String output,
    ) invoke,
    required Future<void> Function(int masterId, String path) persist,
    Future<void> Function(int masterId)? alsoMark,
  }) async {
    final master = state.reviewedMaster;
    final inputFits = master?.masterFitsPath;
    if (master == null || inputFits == null || inputFits.trim().isEmpty) {
      state = state.copyWith(
        error: '$label needs a finished master FITS — integrate first.',
      );
      return null;
    }
    state = busy(true).copyWith(clearError: true);
    try {
      final seam = _ref.read(postSessionSeamProvider);
      final output =
          SessionReviewController._suffixBeforeExtension(inputFits, suffix);
      final written = await invoke(seam, master, output);
      // Render a sibling preview PNG so the result is viewable; fail-soft so a
      // render failure (no native lib in a test, missing FITS) never sinks the
      // already-written finishing FITS or its persisted path.
      final previewPng =
          SessionReviewController._swapExtension(written, '.png');
      try {
        await _ref.read(finishingPreviewRendererProvider)(written, previewPng);
      } catch (_) {
        // Leave the FITS path persisted; the overlay simply shows no preview.
      }
      await persist(master.id, written);
      if (alsoMark != null) await alsoMark(master.id);
      final masters = await _refreshMasters();
      if (!mounted) return written;
      state = state.copyWith(masters: masters);
      return written;
    } catch (e) {
      if (mounted) state = state.copyWith(error: '$label failed: $e');
      return null;
    } finally {
      if (mounted) state = busy(false);
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
    // Only the channels that resolve to an on-disk master FITS feed the combine;
    // keep their master ids in lock-step so the persisted row records exactly the
    // component masters the composite was built from, in channel order.
    final fed = [
      for (final c in refs)
        if (c.fitsPath != null) c,
    ];
    final inputs = [for (final c in fed) c.fitsPath!];
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
      final output = p.join(outDir,
          '${_safeName(state.title)}_${_safeName(palette)}_$stamp.fits');
      final isCustom = palette.toLowerCase() == 'custom';
      final outputPath = await seam.combineChannels(<String, dynamic>{
        'inputs': inputs,
        'palette': palette,
        if (isCustom) 'weights': weights,
        'output': output,
      });

      // Persist the composite as a `narrowband_composites` row so the SHO/HOO
      // output survives the session and can be surfaced rather than orphaned on
      // disk. Composite dimensions track the component masters (the combine is a
      // per-pixel mix of identically-sized channels), so read them off the first
      // fed master when available.
      final firstMaster = _masterById(fed.first.masterId);
      final id = await _compositesDao.insertComposite(
        targetId: state.targetId,
        palette: palette,
        componentMasterIds: [for (final c in fed) c.masterId],
        outputPath: outputPath,
        width: firstMaster?.width ?? 0,
        height: firstMaster?.height ?? 0,
      );
      final composite = NarrowbandComposite(
        id: id,
        targetId: state.targetId,
        palette: palette,
        componentMasterIds: [for (final c in fed) c.masterId],
        outputPath: outputPath,
        width: firstMaster?.width ?? 0,
        height: firstMaster?.height ?? 0,
        createdAt: DateTime.now().toUtc(),
      );
      if (mounted) {
        state = state.copyWith(
          narrowbandComposite: composite,
          narrowbandComposites: [composite, ...state.narrowbandComposites],
        );
      }
      return outputPath;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(error: 'Narrowband combine failed: $e');
      }
      return null;
    } finally {
      if (mounted) state = state.copyWith(combiningNarrowband: false);
    }
  }

  /// Load the persisted narrowband composites in scope (target-scoped when a
  /// target is resolved, otherwise all), newest first, onto
  /// [SessionReviewState.narrowbandComposites] — the workbench "composites" list.
  Future<void> loadComposites() async {
    final tid = state.targetId;
    final composites = tid != null
        ? await _compositesDao.getForTarget(tid)
        : await _compositesDao.getAll();
    if (!mounted) return;
    state = state.copyWith(
      narrowbandComposites: composites,
      narrowbandComposite: state.narrowbandComposite ??
          (composites.isNotEmpty ? composites.first : null),
    );
  }

  /// The in-scope master with [id], or null when not loaded.
  IntegratedMaster? _masterById(int id) {
    for (final m in state.masters) {
      if (m.id == id) return m;
    }
    return null;
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
        if ((s.hfr ?? double.infinity) < (best.hfr ?? double.infinity)) {
          best = s;
        }
      }
    }
    return best;
  }

  Future<List<IntegratedMaster>> _refreshMasters() {
    final tid = state.targetId;
    return tid != null ? _mastersDao.getForTarget(tid) : _mastersDao.getAll();
  }

  Future<String> _outputDir() async {
    final configured = await _ref
        .read(settingsDaoProvider)
        .getSetting('default_image_directory');
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

  /// Insert [suffix] before the extension (`master.fits` →
  /// `master_bgx.fits`). Mirrors the post-session service's path discipline so
  /// the finishing artifacts land beside the master FITS with the same
  /// `_bgx`/`_decon`/`_starred` tags the gated integration passes use.
  static String _suffixBeforeExtension(String path, String suffix) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path$suffix';
    return '${path.substring(0, dot)}$suffix${path.substring(dot)}';
  }

  /// Replace the path's extension (`master_bgx.fits` → `master_bgx.png`). If the
  /// file segment carries no `.`, the new extension is appended. Used to derive
  /// the sibling preview PNG a finishing artifact renders into.
  static String _swapExtension(String path, String newExt) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path$newExt';
    return '${path.substring(0, dot)}$newExt';
  }
}

/// Renders a finishing-artifact FITS at [inputFits] into a viewable PNG at
/// [outputPng] so the workbench can show a before/after of the
/// background-extraction / deconvolution / star-reduction passes (those native
/// passes write a linear FITS only — no preview). Injected via
/// [finishingPreviewRendererProvider] so the controller stays testable without
/// the native bridge: the production renderer auto-stretches the FITS exactly
/// like every other on-disk master preview, while tests substitute a fake.
typedef FinishingPreviewRenderer = Future<void> Function(
  String inputFits,
  String outputPng,
);

/// Production [FinishingPreviewRenderer] — delegates to
/// [ImagingBackend.renderFinishingPreview], which reads the finishing FITS,
/// computes its auto-stretch (the same MAD/STF stretch the integration preview
/// uses), applies it to an 8-bit RGBA display buffer, and writes the sibling
/// PNG. The controller's finishing actions wrap this in a fail-soft `try` so a
/// render failure never drops the (already written + persisted) finishing FITS.
final finishingPreviewRendererProvider =
    Provider<FinishingPreviewRenderer>((ref) {
  final imaging = ref.watch(imagingBackendProvider);
  return (String inputFits, String outputPng) {
    return imaging.renderFinishingPreview(
      inputFits: inputFits,
      outputPng: outputPng,
    );
  };
});

/// Family provider keyed by the review scope so a session view and a target
/// view are independent controllers.
final sessionReviewControllerProvider = StateNotifierProvider.family<
    SessionReviewController, SessionReviewState, SessionReviewScope>(
  (ref, scope) => SessionReviewController(ref, scope),
);
