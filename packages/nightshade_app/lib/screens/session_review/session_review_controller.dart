import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;

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
  });

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
    _load();
  }

  final Ref _ref;
  final SessionReviewScope _scope;

  /// App-settings key for the default integration settings used by the panel
  /// and the auto-process hook.
  static const String kDefaultSettingsKey = 'post_session.default_settings';

  ImagesDao get _images => _ref.read(imagesDaoProvider);
  IntegratedMastersDao get _mastersDao =>
      _ref.read(integratedMastersDaoProvider);

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
        lastOutcome: first,
        masters: masters,
      );
      return first;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        integrating: false,
        clearProgress: true,
        error: 'Integration failed: $e',
      );
      return null;
    }
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
