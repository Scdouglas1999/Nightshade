import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/calibration/dark_library_match_tolerances.dart';
import 'stacking_engine_seam.dart';
import '../models/imaging/stack_and_share_models.dart';
import '../providers/dark_library_provider.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/stacked_results_dao.dart';
import '../providers/database_provider.dart';
import 'calibration_service.dart';
import 'dark_library_service.dart';
import 'live_stacking_service.dart';
import 'logging_service.dart';
import 'stack_light_selector.dart';

/// Thrown when a Stack-and-Share run is requested while the live-stacking
/// engine singleton is already busy (a live EAA session, a sequencer
/// `LiveStackingNode`, or another in-flight Stack-and-Share run).
///
/// The native stacker is a process-wide singleton: starting a Stack-and-Share
/// run would call `apiStackingStart`/`apiStackingStartFromData` and clobber the
/// reference frame and accumulated buffer of whatever is currently running.
/// Rather than silently corrupting an active session, [StackAndShareService.run]
/// refuses to start and surfaces this exception so the UI can tell the operator
/// to stop live stacking first — "errors are a feature" (see CLAUDE.md).
class LiveStackBusyException implements Exception {
  /// Human-readable explanation suitable for direct display.
  final String message;

  const LiveStackBusyException(this.message);

  @override
  String toString() => 'LiveStackBusyException: $message';
}

/// One-button orchestrator for the **Stack-and-Share Loop** (component C6).
///
/// [run] drives the whole pipeline end-to-end for a single imaging session:
///
///  1. **Guard** — refuse to run if the native stacker is already active
///     ([LiveStackBusyException]); the engine is a singleton and we must not
///     clobber a live EAA / sequencer session.
///  2. **Select** ([StackAndSharePhase.selectingLights]) — delegate to
///     [StackLightSelector] (C5) to choose the lights and the alignment
///     reference, honouring the [StackAndShareConfig] quality / accepted gates.
///  3. **Calibrate + stack** — when [StackAndShareConfig.applyCalibration] is
///     set, each light's raw u16 pixels are loaded and calibrated in memory
///     ([StackAndSharePhase.calibrating]) using a dark matched through the
///     dark library plus the configured master flat / bias, then fed to the
///     engine via `startFromData` / `addFrameFromData`
///     ([StackAndSharePhase.stacking]). When calibration is off, the engine's
///     own native file loader is used (`apiStackingStart` /
///     `apiStackingAddFrame`) so no lossy float→u16 round-trip occurs.
///  4. **Result** — `apiStackingGetResult` yields the integrated u16 buffer,
///     dimensions, and final [LiveStackingStats].
///  5. **Stretch** ([StackAndSharePhase.stretching]) — when
///     [StackAndShareConfig.autoStretch] is set, the integrated image is run
///     through the reusable STF path (`apiAutoStretchImage`) to produce an
///     RGBA display buffer; otherwise the mono u16 result is kept as-is.
///  6. **Persist** — a [StackAndShareResult] is built (integration seconds from
///     the selection, alignment residual from the engine stats, single filter
///     when the selection is mono) and written via [StackedResultsDao.insertResult]
///     (C3); the returned row id is stamped onto the result.
///  7. **Release** — `apiStackingStop` is **always** called in a `finally` so
///     the singleton is genuinely freed even if a step throws. `stop` (not
///     `reset`) is required: `reset` only clears the accumulated buffer but
///     leaves the singleton allocated, so `apiStackingIsActive` would keep
///     returning true and the entry guard (step 1) would reject every
///     subsequent run.
///
/// On any failure the run emits a final [StackAndSharePhase.error] progress
/// event and rethrows; errors are never swallowed.
///
/// The integrated raw u16 buffer and the stretched RGBA buffer from the most
/// recent successful run are retained on [lastRawResult] / [lastRgbaResult] so
/// the provider layer (C7) and the share/export step (C8) can consume them
/// without re-stacking.
class StackAndShareService {
  StackAndShareService(
    this._ref, {
    StackingEngineSeam engine = const BridgeStackingEngineSeam(),
  }) : _engine = engine;

  final Ref _ref;

  /// Injectable seam over the native stacker singleton + raw FITS / stretch
  /// bridge calls. Defaults to [BridgeStackingEngineSeam]; tests substitute a
  /// fake so the orchestrator body runs without the Rust dynamic library.
  final StackingEngineSeam _engine;

  /// The integrated, calibrated u16 result of the most recent successful run,
  /// or null if no run has completed (or the last run failed). The provider
  /// layer reads this to feed the FITS save (C1) and the share-card renderer.
  StackedRawResult? get lastRawResult => _lastRawResult;
  StackedRawResult? _lastRawResult;

  /// The auto-stretched RGBA display buffer of the most recent successful run,
  /// or null when the last run did not stretch (mono) or has not completed.
  StackedRgbaResult? get lastRgbaResult => _lastRgbaResult;
  StackedRgbaResult? _lastRgbaResult;

  LoggingService get _logger => _ref.read(loggingServiceProvider);
  StackLightSelector get _selector => _ref.read(stackLightSelectorProvider);
  CalibrationService get _calibration => _ref.read(calibrationServiceProvider);
  DarkLibraryService get _darkLibrary => _ref.read(darkLibraryServiceProvider);
  ImagesDao get _imagesDao => _ref.read(imagesDaoProvider);
  SessionsDao get _sessionsDao => _ref.read(sessionsDaoProvider);
  StackedResultsDao get _resultsDao => _ref.read(stackedResultsDaoProvider);

  /// Run the full Stack-and-Share pipeline for [sessionId] under [config].
  ///
  /// [onProgress] is invoked synchronously at every phase / per-frame
  /// transition so the UI can render a live progress bar. It is optional;
  /// callers that only want the final result may omit it.
  Future<StackAndShareResult> run({
    required int sessionId,
    required StackAndShareConfig config,
    void Function(StackAndShareProgress)? onProgress,
  }) async {
    // (1) Guard: never clobber an active live-stacking singleton.
    if (_engine.isActive()) {
      throw const LiveStackBusyException(
        'Stop live stacking before running Stack-and-Share',
      );
    }

    void emit(StackAndShareProgress progress) => onProgress?.call(progress);

    // Reset any retained buffers from a previous run; a fresh run only exposes
    // its own output, never a stale one.
    _lastRawResult = null;
    _lastRgbaResult = null;

    var progress = const StackAndShareProgress(
      phase: StackAndSharePhase.selectingLights,
    );
    emit(progress);

    try {
      // (2) Selection — which lights, and which is the alignment reference.
      final selection = await _selector.selectForSession(
        sessionId: sessionId,
        config: config,
      );

      final referencePath = selection.referencePath;
      if (referencePath == null) {
        // The selector guarantees a non-empty selection (it throws
        // NoLightsToStackException otherwise), so a missing reference path is a
        // genuine invariant violation, not a user-facing empty stack.
        throw StateError(
          'Stack selection for session $sessionId returned no reference frame',
        );
      }

      // Order the selected frames so the alignment reference is processed
      // first; every other selected frame follows in selection order.
      final reference = selection.selected.firstWhere((f) => f.isReference);
      final followers = selection.selected
          .where((f) => f.imageId != reference.imageId)
          .toList(growable: false);

      final framesTotal = selection.selected.length;
      progress = progress.copyWith(framesTotal: framesTotal);

      // Resolve the owning session's target id for the persisted provenance
      // record (the selector already resolved the human-readable target name).
      final session = await _sessionsDao.getSessionById(sessionId);
      final targetId = session?.targetId;

      // Pre-resolve calibration inputs once when calibration is enabled: the
      // master flat / bias are shared across every frame, so load them a single
      // time rather than per-frame.
      _CalibrationContext? calibration;
      if (config.applyCalibration) {
        calibration = await _buildCalibrationContext();
      }

      // (3)+(4) Feed the reference, then every follower, into the engine.
      var framesProcessed = 0;
      var framesRejected = 0;

      // Start the stack from the reference frame.
      await _startStack(
        frame: reference,
        config: config,
        calibration: calibration,
        emitCalibrating: (file) {
          emit(progress.copyWith(
            phase: StackAndSharePhase.calibrating,
            currentFile: file,
          ));
        },
      );
      framesProcessed = 1; // The reference is always frame #1 in the stack.
      progress = progress.copyWith(
        phase: StackAndSharePhase.stacking,
        framesProcessed: framesProcessed,
        framesRejected: framesRejected,
        currentFile: reference.filePath,
      );
      emit(progress);

      // Track the engine's running stacked count so we can attribute each
      // follower as accepted (count advanced) or rejected (count unchanged).
      var lastStackedCount = 1;

      for (final frame in followers) {
        if (calibration != null) {
          emit(progress.copyWith(
            phase: StackAndSharePhase.calibrating,
            currentFile: frame.filePath,
          ));
        }

        final result = await _addStackFrame(
          frame: frame,
          calibration: calibration,
        );

        framesProcessed++;
        final stackedCount = result.stats.stackedFrameCount;
        if (stackedCount <= lastStackedCount) {
          // The engine did not accept this frame (alignment failure / pixel
          // rejection left the integrated frame count unchanged).
          framesRejected++;
        }
        lastStackedCount = stackedCount;

        progress = progress.copyWith(
          phase: StackAndSharePhase.stacking,
          framesProcessed: framesProcessed,
          framesRejected: framesRejected,
          currentFile: frame.filePath,
        );
        emit(progress);
      }

      // (5) Final integrated result + statistics.
      final stacked = await _ref
          .read(liveStackingServiceProvider)
          .getCurrentResult();
      final stats = stacked.stats;
      final rawU16 = Uint16List.fromList(stacked.data);

      _lastRawResult = StackedRawResult(
        width: stacked.width,
        height: stacked.height,
        data: rawU16,
      );

      // (6) Optional auto-stretch to an RGBA display buffer.
      if (config.autoStretch) {
        progress = progress
            .copyWith(phase: StackAndSharePhase.stretching)
            .clearCurrentFile();
        emit(progress);

        final rgba = _engine.autoStretch(
          width: stacked.width,
          height: stacked.height,
          data: stacked.data,
        );
        _lastRgbaResult = StackedRgbaResult(
          width: stacked.width,
          height: stacked.height,
          rgba: rgba,
        );
      }

      // (7) Build + persist the provenance record.
      final result = StackAndShareResult(
        sessionId: sessionId,
        targetId: targetId,
        targetName: selection.targetName,
        width: stacked.width,
        height: stacked.height,
        framesStacked: stats.stackedFrameCount,
        framesAttempted: framesTotal,
        integrationSecs: selection.totalIntegrationSecs,
        avgAlignmentResidual: stats.avgAlignmentResidual,
        // The live-stacking engine does not measure HFR, so it is left null
        // rather than fabricated from the reference frame's quality score
        // (different metric); a later analysis pass may populate it.
        avgHfr: null,
        filter: _singleFilter(selection),
        createdAt: DateTime.now(),
        stats: stats,
      );

      final id = await _resultsDao.insertResult(result);
      final persisted = result.copyWith(id: id);

      emit(progress
          .copyWith(
            phase: StackAndSharePhase.complete,
            framesProcessed: framesTotal,
          )
          .clearCurrentFile());

      _logger.info(
        'Stack-and-Share complete for session $sessionId: '
        '${stats.stackedFrameCount}/$framesTotal frames stacked, '
        '${persisted.integrationSecs.toStringAsFixed(0)}s integration '
        '(result id $id)',
        source: 'StackAndShareService',
      );

      return persisted;
    } catch (e, st) {
      // (9) Surface the failure: emit a terminal error phase, log, and rethrow.
      _lastRawResult = null;
      _lastRgbaResult = null;
      emit(progress.copyWith(phase: StackAndSharePhase.error).clearCurrentFile());
      _logger.error(
        'Stack-and-Share failed for session $sessionId: $e',
        source: 'StackAndShareService',
        fields: {'stackTrace': st.toString()},
      );
      rethrow;
    } finally {
      // (8) Always release the engine singleton, even on failure, so a later
      // live-stacking session is not blocked by leftover stacker state.
      //
      // `stop` — not `reset` — is required here: `reset` clears the accumulated
      // buffer but leaves the singleton allocated, so `isActive()` would keep
      // returning true and the entry guard (step 1) would refuse every later
      // run, making the feature single-shot per app launch. `stop` frees the
      // guard so `isActive()` returns false again.
      //
      // Guard the stop in its own try/catch: when the pipeline itself threw, the
      // `catch` above is already rethrowing the real cause — a release failure
      // must not mask it. We log it instead so the leaked singleton is still
      // visible to operators ("errors are a feature").
      try {
        await _engine.stop();
      } catch (stopError, stopStack) {
        _logger.error(
          'Stack-and-Share failed to release the stacking engine for session '
          '$sessionId: $stopError',
          source: 'StackAndShareService',
          fields: {'stackTrace': stopStack.toString()},
        );
      }
    }
  }

  /// Start the stack from [frame], either via the in-memory calibrated data
  /// path (when [calibration] is provided) or the engine's native file loader.
  Future<void> _startStack({
    required StackedFrameSelection frame,
    required StackAndShareConfig config,
    required _CalibrationContext? calibration,
    required void Function(String file) emitCalibrating,
  }) async {
    if (calibration == null) {
      await _engine.startFromFile(
        referenceImagePath: frame.filePath,
        config: config.stackingConfig,
      );
      return;
    }

    emitCalibrating(frame.filePath);
    final calibrated = await _loadCalibrated(frame, calibration);
    await _engine.startFromData(
      width: calibrated.width,
      height: calibrated.height,
      data: calibrated.data,
      config: config.stackingConfig,
    );
  }

  /// Add [frame] to the running stack, mirroring the data/file split used by
  /// [_startStack]. Returns the engine result so the caller can read the
  /// running stacked-frame count.
  Future<LiveStackingResult> _addStackFrame({
    required StackedFrameSelection frame,
    required _CalibrationContext? calibration,
  }) async {
    final service = _ref.read(liveStackingServiceProvider);
    if (calibration == null) {
      return service.addFrameFromFile(frame.filePath);
    }
    final calibrated = await _loadCalibrated(frame, calibration);
    return service.addFrameFromData(
      width: calibrated.width,
      height: calibrated.height,
      data: calibrated.data,
    );
  }

  /// Load [frame]'s raw linear pixels and apply in-memory calibration
  /// (dark / flat / bias) using [context].
  ///
  /// The light's exposure / gain / binning / temperature drive the per-frame
  /// dark match (the master flat / bias in [context] are shared); a frame with
  /// no matching dark and no master flat / bias is fed uncalibrated rather than
  /// silently dropped — the selector already decided it belongs in the stack.
  Future<_RawFrame> _loadCalibrated(
    StackedFrameSelection frame,
    _CalibrationContext context,
  ) async {
    final raw = await _loadRawU16(frame.filePath);

    final meta = await _imagesDao.getImageById(frame.imageId);
    Uint16List? darkData;
    if (meta != null && meta.gain != null) {
      final match = await _darkLibrary.findMatchingDark(
        exposureTime: meta.exposureDuration,
        gain: meta.gain!,
        offset: meta.offset ?? 0,
        binX: meta.binX,
        binY: meta.binY,
        temperature: meta.sensorTemp,
        tolerances: context.tolerances,
      );
      if (match != null) {
        darkData = await _loadMatchingPixels(match.filePath, raw.pixelCount);
      }
    }

    final calibrated = _calibration.calibrateData(
      width: raw.width,
      height: raw.height,
      lightData: raw.data,
      darkData: darkData,
      flatData: _validateDimensions(context.flatData, raw.pixelCount, 'flat'),
      biasData: _validateDimensions(context.biasData, raw.pixelCount, 'bias'),
    );

    return _RawFrame(
      width: raw.width,
      height: raw.height,
      data: calibrated,
    );
  }

  /// Build the shared calibration context (tolerances + master flat / bias
  /// pixels) once per run. The flat / bias are loaded into u16 here so they are
  /// not re-read from disk for every frame.
  Future<_CalibrationContext> _buildCalibrationContext() async {
    final tolerances = _ref.read(darkLibraryMatchTolerancesProvider);
    final settings = _ref.read(calibrationSettingsProvider);

    Uint16List? flatData;
    final flatPath = settings.masterFlatPath;
    if (flatPath != null && flatPath.isNotEmpty) {
      if (!File(flatPath).existsSync()) {
        throw FileSystemException('Master flat file not found', flatPath);
      }
      flatData = await _darkLibrary.loadDarkPixels(flatPath);
    }

    Uint16List? biasData;
    final biasPath = settings.masterBiasPath;
    if (biasPath != null && biasPath.isNotEmpty) {
      if (!File(biasPath).existsSync()) {
        throw FileSystemException('Master bias file not found', biasPath);
      }
      biasData = await _darkLibrary.loadDarkPixels(biasPath);
    }

    return _CalibrationContext(
      tolerances: tolerances,
      flatData: flatData,
      biasData: biasData,
    );
  }

  /// Load a calibration frame's pixels and assert it matches the light's pixel
  /// count, so a mismatched master (wrong binning / sensor) fails loudly rather
  /// than corrupting the calibration math.
  Future<Uint16List> _loadMatchingPixels(
    String path,
    int expectedPixels,
  ) async {
    final pixels = await _darkLibrary.loadDarkPixels(path);
    if (pixels.length != expectedPixels) {
      throw StateError(
        'Calibration frame "$path" has ${pixels.length} pixels but the light '
        'frame has $expectedPixels — they must share dimensions / binning.',
      );
    }
    return pixels;
  }

  /// Guard a pre-loaded master against a per-light pixel-count mismatch.
  /// Returns the master unchanged when it matches, throws when it does not, and
  /// passes null through (the correction is simply skipped).
  Uint16List? _validateDimensions(
    Uint16List? master,
    int expectedPixels,
    String label,
  ) {
    if (master == null) return null;
    if (master.length != expectedPixels) {
      throw StateError(
        'Master $label has ${master.length} pixels but the light frame has '
        '$expectedPixels — they must share dimensions / binning.',
      );
    }
    return master;
  }

  /// Read a frame's unstretched linear pixels and quantise to u16.
  ///
  /// Uses the science-grade linear read path so the stacked integration works
  /// on genuine sensor values rather than display-stretched bytes. Linear
  /// values are clamped to `[0, 65535]` (the engine and calibration pipeline
  /// operate on u16); the FITS reader in Rust has already applied BZERO/BSCALE.
  Future<_RawFrame> _loadRawU16(String filePath) async {
    final linear = await _engine.readLinearFrame(filePath);
    final pixelCount = linear.width * linear.height;
    if (linear.linearData.length != pixelCount) {
      throw StateError(
        'FITS "$filePath" reported ${linear.width}x${linear.height} '
        '($pixelCount px) but returned ${linear.linearData.length} samples.',
      );
    }
    final data = Uint16List(pixelCount);
    for (var i = 0; i < pixelCount; i++) {
      final v = linear.linearData[i];
      if (v <= 0) {
        data[i] = 0;
      } else if (v >= 65535) {
        data[i] = 65535;
      } else {
        data[i] = (v + 0.5).floor();
      }
    }
    return _RawFrame(width: linear.width, height: linear.height, data: data);
  }

  /// The single filter of the stack, or null when the selection spans multiple
  /// filters (or none were recorded). A pure-luminance / mono stack reports its
  /// one filter; an LRGB selection reports null so the result is not mislabelled.
  String? _singleFilter(StackSelectionSummary selection) {
    final named = selection.perFilterCounts.keys
        .where((f) => f != StackLightSelector.noFilterBucket)
        .toList(growable: false);
    if (named.length == 1) return named.first;
    return null;
  }

}

/// Integrated raw u16 result of a completed Stack-and-Share run, retained so
/// downstream steps (FITS save, share-card render) can reuse it without
/// re-stacking.
class StackedRawResult {
  final int width;
  final int height;
  final Uint16List data;

  const StackedRawResult({
    required this.width,
    required this.height,
    required this.data,
  });
}

/// Auto-stretched RGBA display buffer of a completed Stack-and-Share run.
class StackedRgbaResult {
  final int width;
  final int height;
  final Uint8List rgba;

  const StackedRgbaResult({
    required this.width,
    required this.height,
    required this.rgba,
  });
}

/// Per-run, shared calibration inputs: the dark-match tolerances and the
/// already-loaded master flat / bias pixels (null when not configured).
class _CalibrationContext {
  final DarkLibraryMatchTolerances tolerances;
  final Uint16List? flatData;
  final Uint16List? biasData;

  const _CalibrationContext({
    required this.tolerances,
    required this.flatData,
    required this.biasData,
  });
}

/// A raw u16 frame with its dimensions.
class _RawFrame {
  final int width;
  final int height;
  final Uint16List data;

  const _RawFrame({
    required this.width,
    required this.height,
    required this.data,
  });

  /// Number of pixels (`width * height`), i.e. the calibration-frame length a
  /// matching dark / flat / bias must share.
  int get pixelCount => width * height;
}

/// Provider for the [StackAndShareService].
///
/// Reads the selector, calibration, dark-library, DAO, and live-stacking
/// providers lazily inside the service so it follows the same Drift instance
/// and backend as the rest of the app, and so test overrides flow through.
final stackAndShareServiceProvider = Provider<StackAndShareService>((ref) {
  return StackAndShareService(ref);
});
