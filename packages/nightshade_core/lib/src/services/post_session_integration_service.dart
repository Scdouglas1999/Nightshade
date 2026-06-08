import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/integrated_masters_dao.dart';
import '../database/database.dart';
import '../models/imaging/integrated_master.dart';
import '../models/imaging/integration_curve.dart';
import '../models/imaging/integration_settings.dart';
import '../providers/dark_library_provider.dart';
import 'dark_library_service.dart';
import 'flat_library_service.dart';
import 'post_session_seam.dart';

/// Resolved calibration master paths for one filter group (the inputs to the
/// native `calibration` JSON block).
class ResolvedCalibration {
  final String? darkPath;
  final String? flatPath;
  final String? biasPath;
  final bool cosmeticCorrection;

  const ResolvedCalibration({
    this.darkPath,
    this.flatPath,
    this.biasPath,
    this.cosmeticCorrection = true,
  });

  Map<String, dynamic> toBridgeJson() => {
        if (darkPath != null) 'dark': darkPath,
        if (flatPath != null) 'flat': flatPath,
        if (biasPath != null) 'bias': biasPath,
        'cosmeticCorrection': cosmeticCorrection,
      };
}

/// The outcome of one post-session integration run for a single filter group.
class PostSessionIntegrationOutcome {
  /// The persisted `integrated_masters` row id.
  final int masterId;

  /// The filter this group integrated (null/`'(none)'` for unfiltered).
  final String? filter;

  /// The decoded native integration result.
  final IntegrateSessionResult result;

  const PostSessionIntegrationOutcome({
    required this.masterId,
    required this.filter,
    required this.result,
  });
}

/// Orchestrates the **batch, offline** post-session integration pipeline that
/// produces an archival-quality linear FITS master from a collection of
/// captured subs (one session, one target, possibly across nights).
///
/// This is the *finishing* path — deliberately distinct from the *live*
/// `StackAndShareService` / `LiveStacker` singleton. It is stateless per call
/// (no process-wide engine), routes through the [PostSessionSeam] (native
/// `api_integrate_session`), and is safe to run while a live session is active.
///
/// Pipeline per filter group:
///  1. **Select** accepted light subs (the caller passes pre-selected
///     [CapturedImage]s — typically from `StackLightSelector`).
///  2. **Resolve calibration** masters: dark via [DarkLibraryService], flat via
///     [FlatLibraryService], bias via the supplied [ResolvedCalibration]
///     override.
///  3. **Build the native args** (sub paths + calibration + settings + output
///     paths) and invoke the seam.
///  4. **Persist** an `integrated_masters` row (status `finalized`, mode
///     `batch`) plus an `integrated_master_frames` fold record per sub.
///
/// The native side writes the 16-bit/float linear FITS master and stretched
/// preview PNG directly (no lossy float→u16 round-trip through Dart).
class PostSessionIntegrationService {
  PostSessionIntegrationService({
    required IntegratedMastersDao mastersDao,
    required DarkLibraryService darkLibrary,
    required FlatLibraryService flatLibrary,
    required PostSessionSeam seam,
  })  : _mastersDao = mastersDao,
        _darkLibrary = darkLibrary,
        _flatLibrary = flatLibrary,
        _seam = seam;

  final IntegratedMastersDao _mastersDao;
  final DarkLibraryService _darkLibrary;
  final FlatLibraryService _flatLibrary;
  final PostSessionSeam _seam;

  /// Filter-bucket name used for subs captured without a filter recorded. Kept
  /// in lock-step with `StackLightSelector.noFilterBucket`.
  static const String noFilterBucket = '(none)';

  /// Integrate the accepted light [subs], grouped by filter, into one master per
  /// filter.
  ///
  /// [subs] must be the *accepted* light frames (the caller applies the
  /// `StackLightSelector` gates). [outputPathBuilder] maps a filter bucket to
  /// the output FITS / preview / rejection-map base path: it returns the master
  /// FITS path; the preview and rejection map are derived by extension swap.
  /// [biasPath] is the optional master-bias override applied to every group.
  ///
  /// Returns one [PostSessionIntegrationOutcome] per non-empty filter group.
  /// Throws [ArgumentError] when [subs] is empty.
  Future<List<PostSessionIntegrationOutcome>> integrate({
    required List<CapturedImage> subs,
    required IntegrationSettings settings,
    required String Function(String filterBucket) outputFitsPathBuilder,
    int? targetId,
    String? targetName,
    String? biasPath,
    bool generatePreview = true,
  }) async {
    if (subs.isEmpty) {
      throw ArgumentError.value(subs, 'subs', 'must not be empty');
    }

    final groups = _groupByFilter(subs);
    final outcomes = <PostSessionIntegrationOutcome>[];

    for (final entry in groups.entries) {
      final filterBucket = entry.key;
      final groupSubs = entry.value;
      final filterValue =
          filterBucket == noFilterBucket ? null : filterBucket;

      final calibration = await _resolveCalibration(
        subs: groupSubs,
        biasPath: biasPath,
        cosmeticCorrection: settings.cosmeticCorrection,
      );

      final masterFitsPath = outputFitsPathBuilder(filterBucket);
      final previewPath =
          generatePreview ? _swapExtension(masterFitsPath, '.png') : null;
      final rejectionMapPath = settings.generateRejectionMap
          ? _suffixBeforeExtension(masterFitsPath, '_rejmap')
          : null;

      final reference = _chooseReferencePath(groupSubs);
      final exposures =
          groupSubs.map((s) => s.exposureDuration).toList(growable: false);

      final args = <String, dynamic>{
        'lightPaths': groupSubs.map((s) => s.filePath).toList(),
        if (reference != null) 'reference': reference,
        'exposuresSec': exposures,
        'calibration': calibration.toBridgeJson(),
        'settings': settings.toBridgeSettings(),
        'output': {
          'masterFitsPath': masterFitsPath,
          if (previewPath != null) 'previewPngPath': previewPath,
          if (rejectionMapPath != null) 'rejectionMapPath': rejectionMapPath,
        },
      };

      final result = await _seam.integrateSession(args);

      final masterId = await _persist(
        targetId: targetId,
        targetName: targetName,
        filter: filterValue,
        settings: settings,
        result: result,
        subs: groupSubs,
      );

      // Smart Morning Report extensions: the marginal-SNR improvement curve and
      // the optional catalog/finishing passes. Both are best-effort and never
      // abort the (already-committed) master persist — a curve/finishing
      // failure leaves a perfectly good master row, just without the extras.
      await _analyzeAndStoreCurve(
        masterId: masterId,
        result: result,
        settings: settings,
      );
      await _runOptionalFinishing(
        masterId: masterId,
        result: result,
        settings: settings,
      );

      outcomes.add(PostSessionIntegrationOutcome(
        masterId: masterId,
        filter: filterValue,
        result: result,
      ));
    }

    return outcomes;
  }

  /// Run a **throwaway, non-persisting** integration of the accepted light
  /// [subs] (first filter group) with [settings], for exploratory comparison
  /// (e.g. the A/B recipe panel). Writes the master/preview to a temp directory
  /// and returns the decoded [IntegrateSessionResult] **without** inserting an
  /// `integrated_masters` row, the improvement curve, the optional finishing
  /// passes, or any fold records — so a comparison run never pollutes the master
  /// library or the durable smart-report state.
  ///
  /// Returns null when [subs] is empty.
  Future<IntegrateSessionResult?> previewIntegrate({
    required List<CapturedImage> subs,
    required IntegrationSettings settings,
    bool generatePreview = true,
  }) async {
    if (subs.isEmpty) return null;

    // Compare on the dominant filter group only — A/B is about the recipe, not
    // multi-filter fan-out; mixing filters into one throwaway master is never
    // what the comparison wants.
    final groups = _groupByFilter(subs);
    final entry = groups.entries.first;
    final groupSubs = entry.value;

    final calibration = await _resolveCalibration(
      subs: groupSubs,
      biasPath: null,
      cosmeticCorrection: settings.cosmeticCorrection,
    );

    final tempDir = await Directory.systemTemp.createTemp('ns_ab_preview');
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final masterFitsPath = '${tempDir.path}/ab_preview_$stamp.fits';
    final previewPath =
        generatePreview ? _swapExtension(masterFitsPath, '.png') : null;
    final rejectionMapPath = settings.generateRejectionMap
        ? _suffixBeforeExtension(masterFitsPath, '_rejmap')
        : null;

    final reference = _chooseReferencePath(groupSubs);
    final exposures =
        groupSubs.map((s) => s.exposureDuration).toList(growable: false);

    final args = <String, dynamic>{
      'lightPaths': groupSubs.map((s) => s.filePath).toList(),
      if (reference != null) 'reference': reference,
      'exposuresSec': exposures,
      'calibration': calibration.toBridgeJson(),
      'settings': settings.toBridgeSettings(),
      'output': {
        'masterFitsPath': masterFitsPath,
        if (previewPath != null) 'previewPngPath': previewPath,
        if (rejectionMapPath != null) 'rejectionMapPath': rejectionMapPath,
      },
    };

    return _seam.integrateSession(args);
  }

  /// Build the per-sub `analyzeNight` inputs from the accepted per-frame records,
  /// invoke the seam, and persist the resulting [IntegrationCurve] (as
  /// `improvement_curve_json`) plus the full-night SNR / integration-time anchor
  /// (`target_snr` / `target_integration_s`) via [updateSmartFields].
  ///
  /// Fail-soft: any failure (no accepted/measured subs, seam error) logs and
  /// returns without disturbing the committed master row.
  Future<void> _analyzeAndStoreCurve({
    required int masterId,
    required IntegrateSessionResult result,
    required IntegrationSettings settings,
  }) async {
    try {
      final qualities = <Map<String, dynamic>>[];
      final weights = <double>[];
      final exposures = <double>[];
      // The exact ordered population the optimizer ranks — the sub on-disk paths
      // in the same (filtered, capture) order the qualities/weights arrays use.
      // Persisted alongside the curve so a later curve-linked cull can map the
      // recommendation's `keptIndices` back to specific subs and bail out when
      // the live accepted set no longer matches this population (rather than
      // silently rejecting the wrong subs by raw index).
      final population = <String>[];
      for (final record in result.perFrameStats) {
        // Only accepted, measured subs carry honest quality descriptors; the
        // optimizer ranks the population, so unmeasured/dropped subs are skipped.
        if (!record.accepted || record.snr == null) continue;
        qualities.add(<String, dynamic>{
          'snr': record.snr,
          if (record.fwhm != null) 'fwhm': record.fwhm,
          if (record.eccentricity != null) 'eccentricity': record.eccentricity,
        });
        weights.add(record.weight);
        // Per-sub exposure is not on the per-frame record; fall back to the
        // night's mean exposure so the cumulative-time axis stays meaningful.
        exposures.add(_meanExposurePerSub(result));
        population.add(record.path);
      }
      if (qualities.isEmpty) return;

      final curve = await _seam.analyzeNight(
        qualities: qualities,
        weights: weights,
        exposuresS: exposures,
      );

      // Store the curve JSON with the population identity as a sibling key so
      // the typed [IntegrationCurve] stays pure (it round-trips its own keys and
      // ignores the extra one) while the cull path can recover the ordering.
      final stored = curve.toJson()
        ..['population'] = population;

      final anchor = curve.points.isNotEmpty ? curve.points.last : null;
      await _mastersDao.updateSmartFields(
        masterId,
        improvementCurveJson: jsonEncode(stored),
        targetSnr: anchor?.snr,
        targetIntegrationS: anchor?.cumulativeIntegrationS,
      );
    } catch (e, st) {
      _logSoftFailure('analyzeNight/improvementCurve', e, st);
    }
  }

  /// Run the gated optional finishing passes on the master in place, each
  /// fail-soft (log + continue): background extraction, colour calibration
  /// (delegated to a [ColorCalibrationService] when present — none is wired yet,
  /// so it is skipped gracefully), and the star-reduction / deconvolution
  /// previews. Resulting artifact paths are recorded via [updateSmartFields].
  Future<void> _runOptionalFinishing({
    required int masterId,
    required IntegrateSessionResult result,
    required IntegrationSettings settings,
  }) async {
    final masterFits = result.masterFitsPath;

    if (settings.extractBackground) {
      await _softStep('extractBackground', () async {
        final outPath = _suffixBeforeExtension(masterFits, '_bgx');
        final written = await _seam.extractBackground(<String, dynamic>{
          'inputFits': masterFits,
          'outputFits': outPath,
          'config': <String, dynamic>{
            'polyDegree': settings.backgroundPolyDegree,
            'preserveMean': settings.backgroundPreserveMean,
          },
        });
        await _mastersDao.updateSmartFields(
          masterId,
          backgroundExtracted: true,
        );
        return written;
      });
    }

    if (settings.colorCalibrate) {
      // Colour calibration needs Dart-side star↔catalogue matching (B–V) before
      // the seam can solve a white balance. That matching is the job of a
      // ColorCalibrationService, which is not wired into this service yet — so
      // we skip gracefully rather than fabricating matches. When the service is
      // injected, delegate the match here and call `_seam.colorCalibrate(...)`.
      _logSoftFailure(
        'colorCalibrate',
        StateError(
          'colour calibration skipped: no ColorCalibrationService available '
          'to match catalogue stars',
        ),
        StackTrace.current,
      );
    }

    if (settings.reduceStars) {
      await _softStep('reduceStarsPreview', () async {
        final outPath = _suffixBeforeExtension(masterFits, '_starred');
        return _seam.reduceStarsPreview(<String, dynamic>{
          'inputFits': masterFits,
          'outputFits': outPath,
          'config': <String, dynamic>{
            'strength': settings.starReductionStrength,
            'method': settings.starReduceMethod.wire,
          },
        });
      });
    }

    if (settings.deconvolve) {
      await _softStep('deconvolvePreview', () async {
        final outPath = _suffixBeforeExtension(masterFits, '_decon');
        return _seam.deconvolvePreview(<String, dynamic>{
          'inputFits': masterFits,
          'outputFits': outPath,
          'config': <String, dynamic>{
            'iterations': settings.deconIterations,
            'regularization': settings.deconRegularization,
          },
        });
      });
    }
  }

  /// Mean exposure per contributing sub: total integration time over the count
  /// of integrated frames, or 0 when nothing integrated.
  static double _meanExposurePerSub(IntegrateSessionResult result) {
    final n = result.framesIntegrated;
    if (n <= 0) return 0.0;
    return result.totalIntegrationSec / n;
  }

  /// Run a fail-soft finishing step: log any throw and swallow it so the master
  /// persist is never aborted by an optional pass.
  Future<void> _softStep(
    String name,
    Future<String> Function() step,
  ) async {
    try {
      await step();
    } catch (e, st) {
      _logSoftFailure(name, e, st);
    }
  }

  void _logSoftFailure(String step, Object error, StackTrace stackTrace) {
    developer.log(
      'post-session optional step "$step" failed (continuing)',
      name: 'PostSessionIntegrationService',
      error: error,
      stackTrace: stackTrace,
      level: 900, // WARNING
    );
  }

  /// Persist the master row + per-sub fold records, returning the new master id.
  Future<int> _persist({
    required int? targetId,
    required String? targetName,
    required String? filter,
    required IntegrationSettings settings,
    required IntegrateSessionResult result,
    required List<CapturedImage> subs,
  }) async {
    final name = _masterName(targetName: targetName, filter: filter);
    final masterId = await _mastersDao.insertMaster(
      targetId: targetId,
      name: name,
      masterFitsPath: result.masterFitsPath,
      previewPngPath: result.previewPath,
      sidecarPath: null,
      rejectionMapPath: result.rejectionMapPath,
      status: IntegratedMasterStatus.finalized,
      accumulationMode: AccumulationMode.batch,
      channels: result.channels,
      width: result.width,
      height: result.height,
      frameCount: result.framesIntegrated,
      totalIntegrationSeconds: result.totalIntegrationSec,
      filter: filter,
      settingsJson: settings.toJsonString(),
      statsJson: _statsJson(result),
    );

    // Fold-record each sub, keyed by file path so the per-frame native stats map
    // back to the captured-image rows for dedup + the cull UI.
    final byPath = {for (final s in subs) s.filePath: s};
    for (final record in result.perFrameStats) {
      final sub = byPath[record.path];
      if (sub == null) continue;
      await _mastersDao.recordFoldedFrame(
        masterId: masterId,
        imageId: sub.id,
        weight: record.weight > 0 ? record.weight : null,
        alignmentResidualPx: record.rmsResidualPx,
        accepted: record.accepted,
        rejectionReason: record.reason,
        // v42 per-sub science metrics from the native FrameQuality the
        // integration already measured — the Night Doctor reads these.
        snr: record.snr,
        fwhm: record.fwhm,
        eccentricity: record.eccentricity,
      );
    }

    return masterId;
  }

  /// Resolve calibration masters for one filter group from the subs' shared
  /// capture parameters (gain / exposure / temperature / binning / filter).
  ///
  /// The group's first sub anchors the match parameters; in practice a filter
  /// group from one session shares gain/binning. A dark match requires the
  /// library to hold a compatible master dark, and a flat match requires a
  /// registered master flat for the filter — both return null when absent
  /// (calibration is then skipped for that master type, never faked).
  Future<ResolvedCalibration> _resolveCalibration({
    required List<CapturedImage> subs,
    String? biasPath,
    required bool cosmeticCorrection,
  }) async {
    final anchor = subs.first;
    final gain = anchor.gain ?? 0;
    final offset = anchor.offset ?? 0;
    final binX = anchor.binX;
    final binY = anchor.binY;
    final temperature = anchor.sensorTemp;

    final dark = await _darkLibrary.findMatchingDark(
      exposureTime: anchor.exposureDuration,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      temperature: temperature,
    );

    final flat = await _flatLibrary.findBestMatch(
      filter: anchor.filter,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      temperature: temperature,
    );

    return ResolvedCalibration(
      darkPath: dark?.masterDarkPath ?? dark?.filePath,
      flatPath: flat?.filePath,
      biasPath:
          (biasPath != null && biasPath.trim().isNotEmpty) ? biasPath : null,
      cosmeticCorrection: cosmeticCorrection,
    );
  }

  Map<String, List<CapturedImage>> _groupByFilter(List<CapturedImage> subs) {
    final out = <String, List<CapturedImage>>{};
    for (final sub in subs) {
      final bucket = _filterBucket(sub.filter);
      out.putIfAbsent(bucket, () => <CapturedImage>[]).add(sub);
    }
    return out;
  }

  String _filterBucket(String? filter) {
    if (filter == null) return noFilterBucket;
    final trimmed = filter.trim();
    return trimmed.isEmpty ? noFilterBucket : trimmed;
  }

  /// Pick the alignment reference: highest qualityScore, tie-broken by lowest
  /// HFR then most-recent capture. Returns null (⇒ native "auto") when no sub
  /// carries a usable metric, letting the engine choose by composite quality.
  String? _chooseReferencePath(List<CapturedImage> subs) {
    CapturedImage? best;
    for (final s in subs) {
      if (best == null || _isBetterReference(s, best)) {
        best = s;
      }
    }
    // Only hand the native side an explicit reference when we have a graded
    // basis for it; otherwise defer to the engine's composite-quality auto pick.
    if (best == null || (best.qualityScore == null && best.hfr == null)) {
      return null;
    }
    return best.filePath;
  }

  bool _isBetterReference(CapturedImage candidate, CapturedImage current) {
    final cQ = candidate.qualityScore;
    final curQ = current.qualityScore;
    if (cQ != null || curQ != null) {
      if (cQ == null) return false;
      if (curQ == null) return true;
      if (cQ != curQ) return cQ > curQ;
    }
    final cH = candidate.hfr;
    final curH = current.hfr;
    if (cH != null || curH != null) {
      if (cH == null) return false;
      if (curH == null) return true;
      if (cH != curH) return cH < curH;
    }
    return candidate.capturedAt.isAfter(current.capturedAt);
  }

  String _masterName({String? targetName, String? filter}) {
    final base = (targetName != null && targetName.trim().isNotEmpty)
        ? targetName.trim()
        : 'Master';
    if (filter != null && filter.trim().isNotEmpty) {
      return '$base · ${filter.trim()}';
    }
    return base;
  }

  String _statsJson(IntegrateSessionResult result) {
    return '{'
        '"framesIntegrated":${result.framesIntegrated},'
        '"framesRejected":${result.framesRejected},'
        '"rmsResidual":${result.rmsResidual},'
        '"totalIntegrationSec":${result.totalIntegrationSec}'
        '}';
  }

  /// Replace the path's extension (`master.fits` → `master.png`). If there is no
  /// `.` in the file segment, the new extension is appended.
  static String _swapExtension(String path, String newExt) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path$newExt';
    return '${path.substring(0, dot)}$newExt';
  }

  /// Insert [suffix] before the extension (`master.fits` →
  /// `master_rejmap.fits`).
  static String _suffixBeforeExtension(String path, String suffix) {
    final slash = path.lastIndexOf(RegExp(r'[\\/]'));
    final dot = path.lastIndexOf('.');
    if (dot <= slash) return '$path$suffix';
    return '${path.substring(0, dot)}$suffix${path.substring(dot)}';
  }
}

/// Provider for the [PostSessionIntegrationService].
final postSessionIntegrationServiceProvider =
    Provider<PostSessionIntegrationService>((ref) {
  return PostSessionIntegrationService(
    mastersDao: ref.watch(integratedMastersDaoProvider),
    darkLibrary: ref.watch(darkLibraryServiceProvider),
    flatLibrary: ref.watch(flatLibraryServiceProvider),
    seam: ref.watch(postSessionSeamProvider),
  );
});
