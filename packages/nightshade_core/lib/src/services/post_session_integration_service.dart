import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show PlateSolveResult;

import '../database/daos/integrated_masters_dao.dart';
import '../database/database.dart';
import '../models/imaging/integrated_master.dart';
import '../models/imaging/integration_curve.dart';
import '../models/imaging/integration_settings.dart';
import '../models/calibration/calibration_library_models.dart';
import '../models/calibration/dark_library_match_tolerances.dart';
import '../providers/dark_library_provider.dart';
import 'calibration_library_service.dart';
import 'color_calibration_service.dart';
import 'dark_library_service.dart';
import 'flat_library_service.dart';
import 'plate_solve_service.dart';
import 'post_session_seam.dart';
import 'wcs_overlay.dart';

/// Resolved calibration master paths for one filter group (the inputs to the
/// native `calibration` JSON block).
class ResolvedCalibration {
  final String? darkPath;
  final String? flatPath;
  final String? biasPath;
  final bool cosmeticCorrection;

  /// Operator-facing warnings produced by the Calibration Library matcher
  /// while selecting these masters (temperature mismatch, exposure scaling,
  /// stale flats, …). Empty for pinned/legacy selections. Not part of the
  /// native bridge JSON — surfaced on [PostSessionIntegrationOutcome].
  final List<String> warnings;

  const ResolvedCalibration({
    this.darkPath,
    this.flatPath,
    this.biasPath,
    this.cosmeticCorrection = true,
    this.warnings = const [],
  });

  Map<String, dynamic> toBridgeJson() => {
    if (darkPath != null) 'dark': darkPath,
    if (flatPath != null) 'flat': flatPath,
    if (biasPath != null) 'bias': biasPath,
    'cosmeticCorrection': cosmeticCorrection,
  };
}

/// The eight plate-solved WCS scalars in the CD-matrix form ASTAP /
/// `WcsInfo::from_plate_solve` (`imaging/src/fits.rs:1094`) emit. Returned by a
/// [MasterPlateSolver] and persisted verbatim via
/// [IntegratedMastersDao.updateWcs] so the catalog annotation overlay and colour
/// calibration can both reconstruct a `WcsOverlay`.
class MasterWcsSolution {
  final double crval1;
  final double crval2;
  final double crpix1;
  final double crpix2;
  final double cd1_1;
  final double cd1_2;
  final double cd2_1;
  final double cd2_2;

  const MasterWcsSolution({
    required this.crval1,
    required this.crval2,
    required this.crpix1,
    required this.crpix2,
    required this.cd1_1,
    required this.cd1_2,
    required this.cd2_1,
    required this.cd2_2,
  });
}

/// A fail-soft plate-solve of a finished master FITS. Implementations wrap
/// `PlateSolveService.solveWithFallback` (at the provider boundary, where the
/// Riverpod `_ref` lives) and convert the `PlateSolveResult` to the CD-matrix
/// [MasterWcsSolution]. Returns null when no solver is installed or the solve
/// fails — the master persist is never aborted by a missing solver.
///
/// [hintRaHours] / [hintDecDegrees] are the target's catalog coordinates when
/// known, to make the solve fast/robust (`apiPlateSolveNear`); a blind solve is
/// the fallback otherwise.
typedef MasterPlateSolver =
    Future<MasterWcsSolution?> Function({
      required String imagePath,
      required int imageWidth,
      required int imageHeight,
      double? hintRaHours,
      double? hintDecDegrees,
    });

/// A fail-soft catalog colour calibration of a finished master FITS.
/// Implementations wrap [ColorCalibrationService.calibrate] (at the provider
/// boundary, where the Riverpod `_ref` + on-disk star catalog live): they detect
/// + photometer stars on [masterFits], project them with [wcs], cross-match to
/// catalogue B–V, solve the per-channel white balance, and write the rebalanced
/// master to [outputFits].
///
/// Returns the written calibrated path on success, or null when no calibrator is
/// installed, the field cross-matched too few stars (a *skipped* result), or the
/// solve failed — the master persist is never aborted by colour calibration.
typedef MasterColorCalibrator =
    Future<String?> Function({
      required String masterFits,
      required String outputFits,
      required WcsOverlay wcs,
      required int channels,
    });

/// The outcome of one post-session integration run for a single filter group.
class PostSessionIntegrationOutcome {
  /// The persisted `integrated_masters` row id.
  final int masterId;

  /// The filter this group integrated (null/`'(none)'` for unfiltered).
  final String? filter;

  /// The decoded native integration result.
  final IntegrateSessionResult result;

  /// Warnings from the calibration auto-match for this group (see
  /// [ResolvedCalibration.warnings]). Empty when masters were pinned or no
  /// matcher is wired.
  final List<String> calibrationWarnings;

  const PostSessionIntegrationOutcome({
    required this.masterId,
    required this.filter,
    required this.result,
    this.calibrationWarnings = const [],
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
    CalibrationLibraryService? calibrationLibrary,
    MasterPlateSolver? plateSolver,
    MasterColorCalibrator? colorCalibrator,
    DarkLibraryMatchTolerances darkTolerances =
        DarkLibraryMatchTolerances.defaults,
  }) : _mastersDao = mastersDao,
       _darkLibrary = darkLibrary,
       _flatLibrary = flatLibrary,
       _seam = seam,
       _calibrationLibrary = calibrationLibrary,
       _plateSolver = plateSolver,
       _colorCalibrator = colorCalibrator,
       _darkTolerances = darkTolerances;

  final IntegratedMastersDao _mastersDao;
  final DarkLibraryService _darkLibrary;
  final FlatLibraryService _flatLibrary;
  final PostSessionSeam _seam;

  /// Dark-frame match tolerances, resolved from
  /// [darkLibraryMatchTolerancesProvider] at the provider boundary so the
  /// post-session integration matcher agrees with the coverage UI and the live
  /// calibration path. Previously the legacy [DarkLibraryService] fallback used
  /// the code defaults (±1.0°C), which could silently disagree with the ±2.0°C
  /// the rest of the app applies — a dark used during the session might then be
  /// skipped when integrating the same subs afterward.
  final DarkLibraryMatchTolerances _darkTolerances;

  /// Optional Calibration Library matcher. When wired, un-pinned master
  /// selection routes through [CalibrationLibraryService.match] so the
  /// transparent scoring + warnings drive the auto-pick; when null the legacy
  /// per-DAO matching ([DarkLibraryService] / [FlatLibraryService]) is used.
  final CalibrationLibraryService? _calibrationLibrary;

  /// Optional fail-soft plate-solver for the finished master FITS, injected at
  /// the provider boundary (where the `PlateSolveService` Riverpod `_ref`
  /// lives). When null, WCS persistence is skipped gracefully — annotation /
  /// colour calibration stay un-lit, but the master persist is unaffected.
  final MasterPlateSolver? _plateSolver;

  /// Optional fail-soft catalog colour calibrator for the finished master FITS,
  /// injected at the provider boundary (where the `ColorCalibrationService` +
  /// on-disk star catalog live). Invoked only when `settings.colorCalibrate` is
  /// set AND the master has a solved WCS (the projection it needs to place
  /// detections on the sky). When null, the colour-calibration gate is skipped
  /// gracefully — never aborting the master persist.
  final MasterColorCalibrator? _colorCalibrator;

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
    ResolvedCalibration? pinnedCalibration,
    bool generatePreview = true,
    double? hintRaHours,
    double? hintDecDegrees,
  }) async {
    if (subs.isEmpty) {
      throw ArgumentError.value(subs, 'subs', 'must not be empty');
    }

    final groups = _groupByFilter(subs);
    final outcomes = <PostSessionIntegrationOutcome>[];

    for (final entry in groups.entries) {
      final filterBucket = entry.key;
      final groupSubs = entry.value;
      final filterValue = filterBucket == noFilterBucket ? null : filterBucket;

      // A user-pinned calibration set bypasses auto-matching entirely (it is
      // applied verbatim to every filter group); otherwise the Calibration
      // Library / legacy DAOs pick the masters.
      final calibration =
          pinnedCalibration ??
          await _resolveCalibration(
            subs: groupSubs,
            biasPath: biasPath,
            cosmeticCorrection: settings.cosmeticCorrection,
          );

      final masterFitsPath = outputFitsPathBuilder(filterBucket);
      final previewPath = generatePreview
          ? _swapExtension(masterFitsPath, '.png')
          : null;
      final rejectionMapPath = settings.generateRejectionMap
          ? _suffixBeforeExtension(masterFitsPath, '_rejmap')
          : null;
      final rejectionMapPreviewPath = rejectionMapPath == null
          ? null
          : _swapExtension(rejectionMapPath, '.png');

      final reference = _chooseReferencePath(groupSubs);
      final exposures = groupSubs
          .map((s) => s.exposureDuration)
          .toList(growable: false);

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
          if (rejectionMapPreviewPath != null)
            'rejectionMapPreviewPath': rejectionMapPreviewPath,
        },
      };

      var result = await _seam.integrateSession(args);

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
      // Drizzle branch: when enabled, re-deposit each accepted sub's raw pixels
      // onto a finer output grid using its source→reference registration
      // transform (surfaced per-frame above), then swap the drizzled FITS in as
      // the persisted master so everything downstream (hero, overlay, WCS solve,
      // finishing) sees the drizzled result. Fail-soft — a drizzle failure
      // leaves the already-committed standard master untouched. May rewrite
      // `result` so the WCS solve + finishing target the drizzled FITS + its
      // scaled dimensions.
      result = await _runDrizzle(
        masterId: masterId,
        result: result,
        settings: settings,
        calibration: calibration,
      );
      // Plate-solve the finished (possibly drizzled) master FITS and persist its
      // WCS. Fail-soft: a missing solver / failed solve leaves the master
      // un-annotatable (annotation + colour calibration stay skipped) but never
      // aborts the already-committed persist. Solve BEFORE the optional finishing
      // passes so the colour-calibration gate has the WCS the catalog match needs.
      final wcs = await _solveAndStoreWcs(
        masterId: masterId,
        result: result,
        hintRaHours: hintRaHours,
        hintDecDegrees: hintDecDegrees,
      );
      await _runOptionalFinishing(
        masterId: masterId,
        result: result,
        settings: settings,
        wcs: wcs,
      );

      outcomes.add(
        PostSessionIntegrationOutcome(
          masterId: masterId,
          filter: filterValue,
          result: result,
          calibrationWarnings: calibration.warnings,
        ),
      );
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
    final previewPath = generatePreview
        ? _swapExtension(masterFitsPath, '.png')
        : null;
    final rejectionMapPath = settings.generateRejectionMap
        ? _suffixBeforeExtension(masterFitsPath, '_rejmap')
        : null;
    final rejectionMapPreviewPath = rejectionMapPath == null
        ? null
        : _swapExtension(rejectionMapPath, '.png');

    final reference = _chooseReferencePath(groupSubs);
    final exposures = groupSubs
        .map((s) => s.exposureDuration)
        .toList(growable: false);

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
        if (rejectionMapPreviewPath != null)
          'rejectionMapPreviewPath': rejectionMapPreviewPath,
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
          // `noise` is load-bearing: the optimizer (`apiAnalyzeNight`) skips any
          // sub with `noise <= 0` from its variance sums, so omitting it
          // collapses the whole improvement curve (and `targetSnr`) to zero.
          // Surfaced per-sub by the native integrate FFI; thread it through.
          if (record.noise != null) 'noise': record.noise,
          if (record.background != null) 'background': record.background,
          if (record.starCount != null) 'starCount': record.starCount,
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
      final stored = curve.toJson()..['population'] = population;

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

  /// Plate-solve the finished master FITS via the injected [_plateSolver] and
  /// persist the resulting eight CD-matrix WCS scalars via
  /// [IntegratedMastersDao.updateWcs].
  ///
  /// Fail-soft and idempotent-friendly: returns null when no solver is
  /// injected, when the solve fails / no solver is installed (the closure
  /// returns null), or when the master has no FITS on disk. On success the row's
  /// WCS columns fill in, lighting up the catalog annotation overlay AND colour
  /// calibration (both reconstruct a `WcsOverlay` from these columns), and the
  /// solved [MasterWcsSolution] is returned so the colour-calibration finishing
  /// pass can reuse it without a database round-trip.
  Future<MasterWcsSolution?> _solveAndStoreWcs({
    required int masterId,
    required IntegrateSessionResult result,
    double? hintRaHours,
    double? hintDecDegrees,
  }) async {
    final solver = _plateSolver;
    if (solver == null) return null;
    final masterFits = result.masterFitsPath;
    if (masterFits.trim().isEmpty) return null;
    try {
      final wcs = await solver(
        imagePath: masterFits,
        imageWidth: result.width,
        imageHeight: result.height,
        hintRaHours: hintRaHours,
        hintDecDegrees: hintDecDegrees,
      );
      if (wcs == null) return null; // No solver / failed solve — un-annotated.
      await _mastersDao.updateWcs(
        masterId,
        crval1: wcs.crval1,
        crval2: wcs.crval2,
        crpix1: wcs.crpix1,
        crpix2: wcs.crpix2,
        cd1_1: wcs.cd1_1,
        cd1_2: wcs.cd1_2,
        cd2_1: wcs.cd2_1,
        cd2_2: wcs.cd2_2,
      );
      return wcs;
    } catch (e, st) {
      _logSoftFailure('solveAndStoreWcs', e, st);
      return null;
    }
  }

  /// Reconstruct a [WcsOverlay] (cdelt/crota form) from a solved CD-matrix
  /// [MasterWcsSolution], inverting the native sign convention
  /// (`WcsInfo::from_plate_solve`, `imaging/src/fits.rs`):
  /// `cdelt1 = -‖(cd1_1, cd2_1)‖` (RA negative), `cdelt2 = ‖(cd1_2, cd2_2)‖`,
  /// `crota2 = atan2(cd2_1, cd2_2)` — the same derivation the UI's
  /// `_resolveMasterWcs` uses to read the persisted v44 columns. The colour
  /// calibrator needs this overlay to project detections onto the sky.
  static WcsOverlay _overlayFromSolution(MasterWcsSolution wcs) {
    final cdelt1 = -math.sqrt(
      wcs.cd1_1 * wcs.cd1_1 + wcs.cd2_1 * wcs.cd2_1,
    ); // RA: neg.
    final cdelt2 = math.sqrt(wcs.cd1_2 * wcs.cd1_2 + wcs.cd2_2 * wcs.cd2_2);
    final crota2 = math.atan2(wcs.cd2_1, wcs.cd2_2) * 180.0 / math.pi;
    return WcsOverlay(
      crpix1: wcs.crpix1,
      crpix2: wcs.crpix2,
      crval1: wcs.crval1,
      crval2: wcs.crval2,
      cdelt1: cdelt1,
      cdelt2: cdelt2,
      crota2: crota2,
    );
  }

  /// Run the gated optional finishing passes on the master in place, each
  /// fail-soft (log + continue): background extraction, colour calibration
  /// (delegated to the injected [MasterColorCalibrator] when present and the
  /// master carries a solved [wcs]; skipped gracefully otherwise), and the
  /// star-reduction / deconvolution previews. Each pass that writes an artifact
  /// persists its on-disk output path onto the master (the v44
  /// `background_extracted_path` / `deconvolved_path` / `star_reduced_path` /
  /// `color_calibrated_path` columns) so the workbench can surface the result;
  /// previously these written paths were discarded and only
  /// `background_extracted=1` survived.
  ///
  /// [wcs] is the master's just-solved WCS (from [_solveAndStoreWcs]) or null
  /// when the master is un-solved — colour calibration needs it to place
  /// detections on the sky, so its gate is skipped when it is null.
  Future<void> _runOptionalFinishing({
    required int masterId,
    required IntegrateSessionResult result,
    required IntegrationSettings settings,
    required MasterWcsSolution? wcs,
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
        await _mastersDao.updateFinishingPaths(
          masterId,
          backgroundExtractedPath: written,
        );
        return written;
      });
    }

    if (settings.colorCalibrate) {
      // Colour calibration needs Dart-side star↔catalogue matching (B–V), which
      // is the job of the injected [MasterColorCalibrator] (wrapping
      // [ColorCalibrationService] at the provider boundary). It also needs the
      // master's solved WCS to project detections onto the sky. Both must be
      // present; otherwise we skip gracefully rather than fabricating matches.
      final calibrator = _colorCalibrator;
      if (calibrator == null || wcs == null) {
        _logSoftFailure(
          'colorCalibrate',
          StateError(
            'colour calibration skipped: '
            '${calibrator == null ? 'no MasterColorCalibrator injected' : 'master has no solved WCS'}',
          ),
          StackTrace.current,
        );
      } else {
        await _softStep('colorCalibrate', () async {
          final outPath = _suffixBeforeExtension(masterFits, '_color');
          final written = await calibrator(
            masterFits: masterFits,
            outputFits: outPath,
            wcs: _overlayFromSolution(wcs),
            channels: result.channels,
          );
          // null ⇒ skipped (too few catalog matches / no catalog): leave the
          // master un-calibrated rather than persisting a phantom path.
          if (written == null || written.trim().isEmpty) {
            throw StateError(
              'colour calibration produced no output (too few catalogue '
              'cross-matches)',
            );
          }
          await _mastersDao.updateSmartFields(
            masterId,
            colorCalibratedPath: written,
          );
          return written;
        });
      }
    }

    if (settings.reduceStars) {
      await _softStep('reduceStarsPreview', () async {
        final outPath = _suffixBeforeExtension(masterFits, '_starred');
        final written = await _seam.reduceStarsPreview(<String, dynamic>{
          'inputFits': masterFits,
          'outputFits': outPath,
          'config': <String, dynamic>{
            'strength': settings.starReductionStrength,
            'method': settings.starReduceMethod.wire,
          },
        });
        await _mastersDao.updateFinishingPaths(
          masterId,
          starReducedPath: written,
        );
        return written;
      });
    }

    if (settings.deconvolve) {
      await _softStep('deconvolvePreview', () async {
        final outPath = _suffixBeforeExtension(masterFits, '_decon');
        final written = await _seam.deconvolvePreview(<String, dynamic>{
          'inputFits': masterFits,
          'outputFits': outPath,
          'config': <String, dynamic>{
            'iterations': settings.deconIterations,
            'regularization': settings.deconRegularization,
          },
        });
        await _mastersDao.updateFinishingPaths(
          masterId,
          deconvolvedPath: written,
        );
        return written;
      });
    }
  }

  /// Drizzle-integrate the accepted subs onto a `scale`× output grid using each
  /// sub's source→reference registration transform (surfaced per-frame by the
  /// native integrate pass), then swap the drizzled FITS in as the persisted
  /// master.
  ///
  /// Returns the (possibly rewritten) [IntegrateSessionResult]: on a successful
  /// drizzle the master FITS path + output dimensions are replaced with the
  /// drizzled artifact's, so the caller's downstream WCS solve and the persisted
  /// row both describe the drizzled master. When [IntegrationSettings.drizzle] is
  /// off — or no accepted sub carried a transform, or the drizzle fails — the
  /// input [result] is returned unchanged (fail-soft: the standard master, which
  /// is already committed, stays the master).
  Future<IntegrateSessionResult> _runDrizzle({
    required int masterId,
    required IntegrateSessionResult result,
    required IntegrationSettings settings,
    required ResolvedCalibration calibration,
  }) async {
    if (!settings.drizzle) return result;

    try {
      // Each accepted sub contributes its raw, un-resampled pixels + the
      // source→reference transform fitted during registration. Drizzle deposits
      // those raw drops onto the finer grid itself (no pre-resampling), so the
      // input is the *original* sub FITS — exactly `perFrameStats.path`. Subs
      // that failed registration carry no transform and are skipped.
      final frames = <Map<String, dynamic>>[];
      for (final record in result.perFrameStats) {
        if (!record.accepted) continue;
        final transform = record.transform;
        if (transform == null || transform.length != 9) continue;
        frames.add(<String, dynamic>{
          'fitsPath': record.path,
          'transform': transform,
          'weight': record.weight,
        });
      }
      if (frames.isEmpty) {
        _logSoftFailure(
          'drizzleIntegrate',
          StateError(
            'drizzle skipped: no accepted sub carried a registration '
            'transform',
          ),
          StackTrace.current,
        );
        return result;
      }

      final outputFits = _suffixBeforeExtension(
        result.masterFitsPath,
        '_drizzle',
      );
      final coverageFits = _suffixBeforeExtension(outputFits, '_cov');
      final coveragePng = _swapExtension(coverageFits, '.png');
      // A stretched preview PNG sibling for the drizzled master, so the hero
      // shows the (scaled) drizzled image rather than the standard 1× preview.
      final previewPng = _swapExtension(outputFits, '.png');
      final drizzleResult = await _seam.drizzleIntegrate(<String, dynamic>{
        'frames': frames,
        'refW': result.width,
        'refH': result.height,
        'config': <String, dynamic>{
          'scale': settings.drizzleScale,
          'pixfrac': settings.drizzlePixfrac,
          'kernel': settings.drizzleKernel.wire,
        },
        'bayer': settings.bayerDrizzle,
        // Drizzle deposits raw sub pixels, so it must apply the SAME resolved
        // calibration the standard integrate path applied — otherwise the
        // drizzled master that gets swapped in as canonical is uncalibrated
        // (amp glow / hot pixels / vignetting / dust). The drizzle-native side
        // consumes the same `{dark?, flat?, bias?, cosmeticCorrection}` shape
        // `api_integrate_session` does, calibrating each frame before drizzling.
        'calibration': calibration.toBridgeJson(),
        'outputFits': outputFits,
        'coverageFits': coverageFits,
        'coveragePngPath': coveragePng,
        'previewPngPath': previewPng,
      });

      final outputPath = drizzleResult['outputPath'] as String?;
      if (outputPath == null || outputPath.isEmpty) {
        _logSoftFailure(
          'drizzleIntegrate',
          StateError('drizzle returned no outputPath'),
          StackTrace.current,
        );
        return result;
      }
      final outWidth = (drizzleResult['outWidth'] as num?)?.toInt();
      final outHeight = (drizzleResult['outHeight'] as num?)?.toInt();
      final outChannels = (drizzleResult['channels'] as num?)?.toInt();
      final drizzleCoverage = drizzleResult['coveragePath'] as String?;
      final drizzleCoveragePreview =
          drizzleResult['coveragePngPath'] as String?;
      // The drizzled master's preview, when the native side wrote one; fall back
      // to the standard preview if not (older native lib / write skipped).
      final drizzlePreview = drizzleResult['previewPngPath'] as String?;
      final newPreview = (drizzlePreview != null && drizzlePreview.isNotEmpty)
          ? drizzlePreview
          : result.previewPath;

      // Swap the drizzled FITS + its preview in as the persisted master, with
      // its scaled dimensions, so the hero / overlay / WCS solve all see the
      // drizzled result rather than the standard resample-and-combine master.
      await _mastersDao.updateBookkeeping(
        masterId,
        masterFitsPath: outputPath,
        previewPngPath: newPreview,
        coverageMapPath: drizzleCoverage,
        coverageMapPreviewPath: drizzleCoveragePreview,
        width: outWidth,
        height: outHeight,
        channels: outChannels,
      );

      // Re-stamp the result so the caller's WCS solve targets the drizzled FITS
      // and its (scaled) geometry, and the immediate post-integrate hero shows
      // the drizzled preview — leaving every other field intact.
      return IntegrateSessionResult(
        masterFitsPath: outputPath,
        previewPath: newPreview,
        rejectionMapPath: result.rejectionMapPath,
        rejectionMapPreviewPath: result.rejectionMapPreviewPath,
        coverageMapPath: drizzleCoverage,
        coverageMapPreviewPath: drizzleCoveragePreview,
        framesIntegrated: result.framesIntegrated,
        framesRejected: result.framesRejected,
        totalIntegrationSec: result.totalIntegrationSec,
        rmsResidual: result.rmsResidual,
        width: outWidth ?? result.width,
        height: outHeight ?? result.height,
        channels: outChannels ?? result.channels,
        perFrameStats: result.perFrameStats,
      );
    } catch (e, st) {
      _logSoftFailure('drizzleIntegrate', e, st);
      return result;
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
  Future<void> _softStep(String name, Future<String> Function() step) async {
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
      rejectionMapPreviewPath: result.rejectionMapPreviewPath,
      coverageMapPath: result.coverageMapPath,
      coverageMapPreviewPath: result.coverageMapPreviewPath,
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

    // Preferred path: the Calibration Library's transparent matcher (scored
    // picks + operator-facing warnings). The legacy DAO path below remains
    // for callers constructed without the library service.
    final library = _calibrationLibrary;
    if (library != null) {
      final matchSet = await library.match(
        LightFrameContext(
          gain: gain,
          offset: offset,
          exposureSeconds: anchor.exposureDuration,
          temperature: temperature,
          filter: anchor.filter,
          binX: binX,
          binY: binY,
        ),
        // The automated post-session pipeline can only apply a master that is
        // already on local disk: a REMOTE candidate's `filePath` is null until
        // it is downloaded, and pulling a shared master is a consent-gated,
        // explicit user action (`acceptRemoteMaster`), never a silent
        // auto-download. Folding remote candidates here would let a remote pick
        // with a null path win the ranking and then silently disable dark/flat
        // calibration (its path resolves to null). So match LOCAL-only.
        includeRemote: false,
      );
      final explicitBias = (biasPath != null && biasPath.trim().isNotEmpty)
          ? biasPath
          : null;
      return ResolvedCalibration(
        darkPath: matchSet.dark?.record.filePath,
        flatPath: matchSet.flat?.record.filePath,
        // An explicit bias override wins; otherwise only auto-fill the bias
        // when no dark matched (a matched dark already carries the bias
        // signal — supplying both would double-subtract the pedestal).
        biasPath:
            explicitBias ??
            (matchSet.dark == null ? matchSet.bias?.record.filePath : null),
        cosmeticCorrection: cosmeticCorrection,
        warnings: matchSet.allWarnings,
      );
    }

    final dark = await _darkLibrary.findMatchingDark(
      exposureTime: anchor.exposureDuration,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      temperature: temperature,
      tolerances: _darkTolerances,
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
      biasPath: (biasPath != null && biasPath.trim().isNotEmpty)
          ? biasPath
          : null,
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
///
/// The [MasterPlateSolver] closure is wired here (the provider boundary, where
/// the `PlateSolveService` Riverpod handle lives): it plate-solves the finished
/// master FITS via `solveWithFallback` and converts the `PlateSolveResult` to
/// the eight CD-matrix WCS scalars using the same sign convention as the native
/// source of truth (`WcsInfo::from_plate_solve`, `imaging/src/fits.rs:1094`):
/// `cd1_1 = -scale·cosθ`, `cd1_2 = cd2_1 = scale·sinθ`, `cd2_2 = scale·cosθ`,
/// with `scale` in deg/px and `θ` the field rotation. The reference pixel is the
/// image centre. Fail-soft: a non-success solve (no solver installed, solve
/// failure) yields null, so WCS persistence is skipped without aborting the
/// master persist.
final postSessionIntegrationServiceProvider = Provider<PostSessionIntegrationService>((
  ref,
) {
  return PostSessionIntegrationService(
    mastersDao: ref.watch(integratedMastersDaoProvider),
    darkLibrary: ref.watch(darkLibraryServiceProvider),
    flatLibrary: ref.watch(flatLibraryServiceProvider),
    seam: ref.watch(postSessionSeamProvider),
    darkTolerances: ref.watch(darkLibraryMatchTolerancesProvider),
    // Calibration Library Manager: routes un-pinned master selection through
    // the transparent scored matcher so its warnings reach the outcome /
    // morning report.
    calibrationLibrary: ref.watch(calibrationLibraryServiceProvider),
    // Catalog colour calibration of the finished master, wired at the provider
    // boundary (where the `ColorCalibrationService` + its on-disk HYG catalog
    // live). The closure delegates to `ColorCalibrationService.calibrate`, which
    // detects + photometers stars, cross-matches catalogue B–V via the supplied
    // WCS, solves the per-channel white balance, and writes the rebalanced
    // master. Returns null on the fail-soft *skipped* result (too few matches /
    // no catalog) so the gate persists nothing rather than a phantom path.
    colorCalibrator:
        ({
          required String masterFits,
          required String outputFits,
          required WcsOverlay wcs,
          required int channels,
        }) async {
          final service = ref.read(colorCalibrationServiceProvider);
          final result = await service.calibrate(
            masterFits: masterFits,
            outputFits: outputFits,
            wcs: wcs,
            channels: channels,
          );
          if (ColorCalibrationService.wasSkipped(result)) return null;
          return result.outputPath;
        },
    plateSolver:
        ({
          required String imagePath,
          required int imageWidth,
          required int imageHeight,
          double? hintRaHours,
          double? hintDecDegrees,
        }) async {
          final solveService = ref.read(plateSolveServiceProvider);
          final PlateSolveResult solve;
          try {
            solve = await solveService.solveWithFallback(
              imagePath: imagePath,
              hintRaHours: hintRaHours,
              hintDecDegrees: hintDecDegrees,
            );
          } on SolverNotAvailableError {
            // No configured solver — stay un-annotated, never throw out of the
            // optional WCS step.
            return null;
          }
          if (!solve.success) return null;

          // Convert (ra°, dec°, pixelScale arcsec/px, rotation°) to the CD matrix.
          final scaleDeg = solve.pixelScale / 3600.0;
          final rotRad = solve.rotation * math.pi / 180.0;
          final cosRot = math.cos(rotRad);
          final sinRot = math.sin(rotRad);
          return MasterWcsSolution(
            crval1: solve.ra,
            crval2: solve.dec,
            crpix1: imageWidth / 2.0,
            crpix2: imageHeight / 2.0,
            cd1_1:
                -scaleDeg * cosRot, // Negative for RA increasing to the left.
            cd1_2: scaleDeg * sinRot,
            cd2_1: scaleDeg * sinRot,
            cd2_2: scaleDeg * cosRot,
          );
        },
  );
});
