import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../backend/nightshade_backend.dart';
import '../models/calibration/dark_library_match_tolerances.dart';
import 'stacking_engine_seam.dart';
import '../models/imaging/stack_and_share_models.dart';
import '../providers/auto_stretch_provider.dart';
import '../providers/capability_provider.dart';
import '../providers/dark_library_provider.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/stacked_results_dao.dart';
import '../providers/database_provider.dart';
import '../providers/backend_provider.dart';
import 'calibration_service.dart';
import 'dark_library_service.dart';
import 'live_stacking_service.dart';
import 'logging_service.dart';
import 'stack_light_selector.dart';
import 'stack_share_export_service.dart';

/// Persists the display preview that makes a completed stack genuinely
/// reopenable after the in-memory integration buffer is released.
typedef StackResultPreviewPersister =
    Future<String> Function({
      required StackAndShareResult result,
      required Uint8List rgba,
    });

/// Thrown when a Stack-and-Share run is requested while the live-stacking
/// engine singleton is already busy (a live EAA session, a sequencer
/// `LiveStackingNode`, or another in-flight Stack-and-Share run).
///
/// The native stacker is a process-wide singleton: starting a Stack-and-Share
/// run would call `apiStackingStart`/`apiStackingStartFromData` and clobber the
/// reference frame and accumulated buffer of whatever is currently running.
/// Rather than silently corrupting an active session, [StackAndShareService.run]
/// refuses to start and surfaces this exception so the UI can tell the operator
/// to stop live stacking first — errors are a feature here.
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
/// [StackLightSelector] to choose the lights and the alignment
///     reference, honouring the [StackAndShareConfig] quality / accepted gates.
///  3. **Calibrate + stack** — when [StackAndShareConfig.applyCalibration] is
///     set, each light's raw u16 pixels are loaded and calibrated in memory
///     ([StackAndSharePhase.calibrating]) using a dark matched through the
///     dark library plus the configured master flat / bias, then fed to the
///     engine via `startFromData` / `addFrameFromData`
///     ([StackAndSharePhase.stacking]). When calibration is off, the engine's
///     own native file loader is used (`apiStackingStart` /
///     `apiStackingAddFrame`) so no lossy float→u16 round-trip occurs.
///  4. **Result** — `apiStackingGetResult` yields the integrated buffer, its
///     dimensions, the channel layout (`1` mono, `3` interleaved RGB16 for an
///     OSC stack the engine debayered), and the final [LiveStackingStats].
///  5. **Stretch** ([StackAndSharePhase.stretching]) — when
///     [StackAndShareConfig.autoStretch] is set, the integrated image is run
///     through the STF path with the result's channel count, so a colour stack
///     takes the per-channel (unlinked) stretch and a mono stack the grayscale
///     stretch; otherwise the raw result is kept as-is.
///  6. **Persist** — a [StackAndShareResult] is built (integration seconds from
///     the selection, alignment residual from the engine stats, colour flag +
///     channel count from the integrated result, filter `'OSC'` for a colour
///     stack / the single filter when the selection is mono) and written via
/// [StackedResultsDao.insertResult]; the returned row id is stamped
///     onto the result.
///
/// **OSC / colour resolution.** Before stacking, the run resolves the sensor
/// mode ([StackAndShareConfig.sensorMode]) into a concrete engine config: for
/// `osc`/`auto` with no explicit Bayer override it discovers the pattern from
/// the connected camera's [CameraCapabilities] (live) or the reference frame's
/// FITS `BAYERPAT` geometry (file). `osc` with no resolvable pattern is a hard
/// [StateError] — never a silent mono fallback that would scramble the mosaic.
/// The calibrated/raw CFA mono plane is fed to the engine **unchanged**; the
/// native stacker debayers post-calibration (Dart never debayers).
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
/// the provider layer and the share/export step can consume them
/// without re-stacking.
class StackAndShareService {
  StackAndShareService(
    this._ref, {
    NightshadeBackend? backend,
    StackingEngineSeam engine = const BridgeStackingEngineSeam(),
    StackResultPreviewPersister? persistPreview,
  }) : _backend = backend ?? _ref.read(backendProvider),
       _backendNotifier = _ref.read(backendProvider.notifier),
       _logger = _ref.read(loggingServiceProvider),
       _engine = engine,
       _persistPreview = persistPreview;

  final Ref _ref;
  final NightshadeBackend _backend;
  final BackendNotifier _backendNotifier;
  final LoggingService _logger;
  bool _retired = false;

  // The native stacking engine is process-wide. This admission lock closes
  // the gap before the engine reports itself active (selection/calibration can
  // await for seconds), when two rapid invocations would otherwise both pass
  // isActive() and then clobber the same singleton.
  static Object? _processRunOwner;

  /// Injectable seam over the native stacker singleton + raw FITS / stretch
  /// bridge calls. Defaults to [BridgeStackingEngineSeam]; tests substitute a
  /// fake so the orchestrator body runs without the Rust dynamic library.
  final StackingEngineSeam _engine;

  /// Production persists a lossless preview for every completed result. Tests
  /// that exercise only orchestration may omit this seam; persistence-specific
  /// tests inject it explicitly.
  final StackResultPreviewPersister? _persistPreview;

  /// The integrated, calibrated u16 result of the most recent successful run,
  /// or null if no run has completed (or the last run failed). The provider
  /// layer reads this to feed the FITS save and the share-card renderer.
  StackedRawResult? get lastRawResult => _lastRawResult;
  StackedRawResult? _lastRawResult;

  /// The auto-stretched RGBA display buffer of the most recent successful run,
  /// or null when the last run did not stretch (mono) or has not completed.
  StackedRgbaResult? get lastRgbaResult => _lastRgbaResult;
  StackedRgbaResult? _lastRgbaResult;

  StackLightSelector get _selector => _ref.read(stackLightSelectorProvider);
  CalibrationService get _calibration => _ref.read(calibrationServiceProvider);
  DarkLibraryService get _darkLibrary => _ref.read(darkLibraryServiceProvider);
  ImagesDao get _imagesDao => _ref.read(imagesDaoProvider);
  SessionsDao get _sessionsDao => _ref.read(sessionsDaoProvider);
  StackedResultsDao get _resultsDao => _ref.read(stackedResultsDaoProvider);

  bool get _hasAuthority =>
      !_retired && _backendNotifier.isCurrentBackend(_backend);

  void retire() => _retired = true;

  void _ensureAuthority() {
    if (_hasAuthority) return;
    throw StateError(
      'The imaging host changed while Stack & Share was running. The outgoing '
      'run was stopped and its result was discarded; start it again on the '
      'current host.',
    );
  }

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
    _ensureAuthority();
    if (_backend is NetworkBackend) {
      throw StateError(
        'Stack & Share runs on the imaging host, not a remote controller.',
      );
    }
    if (_processRunOwner != null) {
      throw const LiveStackBusyException(
        'Another Stack-and-Share run is already preparing or stacking',
      );
    }

    // (1) Guard: never clobber an active live-stacking singleton.
    if (_engine.isActive()) {
      throw const LiveStackBusyException(
        'Stop live stacking before running Stack-and-Share',
      );
    }

    // Capture every provider value used after the first await while this
    // service's Ref is still current. Authority checks prevent later work from
    // continuing, but the cleanup path must still be able to reach the exact
    // old-host DAO and stacker after Riverpod rebuilds this provider.
    final selector = _selector;
    final sessionsDao = _sessionsDao;
    final resultsDao = _resultsDao;
    final liveStacking = _ref.read(liveStackingServiceProvider);

    final runOwner = Object();
    _processRunOwner = runOwner;

    void emit(StackAndShareProgress progress) {
      _ensureAuthority();
      onProgress?.call(progress);
    }

    var progress = const StackAndShareProgress(
      phase: StackAndSharePhase.selectingLights,
    );
    int? incompleteResultId;

    try {
      // Reset any retained buffers from a previous run; a fresh run only
      // exposes its own output, never a stale one.
      _lastRawResult = null;
      _lastRgbaResult = null;
      emit(progress);

      // (2) Selection — which lights, and which is the alignment reference.
      final selection = await selector.selectForSession(
        sessionId: sessionId,
        config: config,
      );
      _ensureAuthority();

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
      final session = await sessionsDao.getSessionById(sessionId);
      _ensureAuthority();
      final targetId = session?.targetId;

      // Pre-resolve calibration inputs once when calibration is enabled: the
      // master flat / bias are shared across every frame, so load them a single
      // time rather than per-frame.
      _CalibrationContext? calibration;
      if (config.applyCalibration) {
        calibration = await _buildCalibrationContext();
        _ensureAuthority();
      }

      // Resolve the OSC / colour intent ONCE for the whole run, off the
      // reference frame, before any engine work. The live stacker fixes the
      // sensor mode + Bayer pattern at `start`; every follower inherits it, so
      // resolving once here keeps the whole integration on a single consistent
      // colour path (a mid-stack mode flip would mix mono and RGB buffers).
      final stackingConfig = await _resolveStackingConfig(
        config: config,
        reference: reference,
      );
      _ensureAuthority();

      // (3)+(4) Feed the reference, then every follower, into the engine.
      var framesProcessed = 0;
      var framesRejected = 0;

      // Start the stack from the reference frame.
      await _startStack(
        frame: reference,
        stackingConfig: stackingConfig,
        calibration: calibration,
        emitCalibrating: (file) {
          emit(
            progress.copyWith(
              phase: StackAndSharePhase.calibrating,
              currentFile: file,
            ),
          );
        },
      );
      _ensureAuthority();
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
          emit(
            progress.copyWith(
              phase: StackAndSharePhase.calibrating,
              currentFile: frame.filePath,
            ),
          );
        }

        final result = await _addStackFrame(
          frame: frame,
          calibration: calibration,
        );
        _ensureAuthority();

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
      final stacked = await liveStacking.getCurrentResult();
      _ensureAuthority();
      final stats = stacked.stats;
      final rawU16 = Uint16List.fromList(stacked.data);

      // The engine reports the integrated channel layout directly: `1` for a
      // mono integration, `3` for an OSC integration it debayered to
      // interleaved RGB16. Anything else has no display/persist layout and is a
      // genuine engine-contract violation rather than something to paper over.
      final channels = stacked.channels;
      if (channels != 1 && channels != 3) {
        throw StateError(
          'Stacking engine returned an integrated result with $channels '
          'channels; only 1 (mono) or 3 (interleaved RGB16) are supported.',
        );
      }
      final isColor = channels == 3;

      // Guard the buffer length against the reported layout so a mismatch
      // surfaces here instead of corrupting the stretch / persisted record.
      final expectedSamples = stacked.width * stacked.height * channels;
      if (rawU16.length != expectedSamples) {
        throw StateError(
          'Stacking engine returned ${rawU16.length} samples for a '
          '${stacked.width}x${stacked.height} $channels-channel result '
          '(expected $expectedSamples).',
        );
      }

      _lastRawResult = StackedRawResult(
        width: stacked.width,
        height: stacked.height,
        channels: channels,
        data: rawU16,
      );

      // (6) Optional auto-stretch to an RGBA display buffer. The channel count
      // is forwarded so a colour stack takes the per-channel (unlinked) STF
      // route rather than being treated as a single luminance plane.
      if (config.autoStretch) {
        progress = progress
            .copyWith(phase: StackAndSharePhase.stretching)
            .clearCurrentFile();
        emit(progress);

        final rgba = _engine.autoStretch(
          width: stacked.width,
          height: stacked.height,
          data: stacked.data,
          channels: channels,
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
        filter: _singleFilter(selection, isColor: isColor),
        isColor: isColor,
        channels: channels,
        createdAt: DateTime.now(),
        stats: stats,
      );

      final id = await resultsDao.insertResult(result);
      incompleteResultId = id;
      _ensureAuthority();
      var persisted = result.copyWith(id: id);

      // Metadata alone is not a saved result: the raw integration is released
      // when the auto-disposed provider goes away. Persist a lossless display
      // preview before declaring the run complete so history survives app
      // navigation and process restarts. When auto-stretch was disabled for the
      // run, render an STF only for this viewer preview; the retained raw buffer
      // and run configuration remain unchanged.
      final persistPreview = _persistPreview;
      if (persistPreview != null) {
        progress = progress
            .copyWith(phase: StackAndSharePhase.exporting)
            .clearCurrentFile();
        emit(progress);

        final previewRgba =
            _lastRgbaResult?.rgba ??
            _engine.autoStretch(
              width: stacked.width,
              height: stacked.height,
              data: rawU16,
              channels: channels,
            );
        final previewPath = await persistPreview(
          result: persisted,
          rgba: previewRgba,
        );
        _ensureAuthority();
        persisted = persisted.copyWith(exportedImagePath: previewPath);
      }

      emit(
        progress
            .copyWith(
              phase: StackAndSharePhase.complete,
              framesProcessed: framesTotal,
            )
            .clearCurrentFile(),
      );
      incompleteResultId = null;

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
      final resultId = incompleteResultId;
      if (resultId != null) {
        try {
          await resultsDao.deleteResult(resultId);
          incompleteResultId = null;
        } catch (cleanupError, cleanupStack) {
          _logger.error(
            'Failed to remove incomplete stacked result $resultId: '
            '$cleanupError',
            source: 'StackAndShareService',
            fields: {'stackTrace': cleanupStack.toString()},
          );
        }
      }
      if (_hasAuthority) {
        emit(
          progress.copyWith(phase: StackAndSharePhase.error).clearCurrentFile(),
        );
      }
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
      if (identical(_processRunOwner, runOwner)) {
        _processRunOwner = null;
      }
    }
  }

  /// Start the stack from [frame], either via the in-memory calibrated data
  /// path (when [calibration] is provided) or the engine's native file loader.
  ///
  /// [stackingConfig] is the OSC-resolved engine config from
  /// [_resolveStackingConfig] — it carries the concrete sensor mode + Bayer
  /// pattern + demosaic quality the engine debayers with. For the calibrated
  /// data path the calibrated CFA mono plane is fed **unchanged**: the native
  /// stacker (component C3) debayers post-calibration, so debayering here would
  /// double-process the mosaic.
  Future<void> _startStack({
    required StackedFrameSelection frame,
    required LiveStackingConfig stackingConfig,
    required _CalibrationContext? calibration,
    required void Function(String file) emitCalibrating,
  }) async {
    if (calibration == null) {
      await _engine.startFromFile(
        referenceImagePath: frame.filePath,
        config: stackingConfig,
      );
      _ensureAuthority();
      return;
    }

    emitCalibrating(frame.filePath);
    final calibrated = await _loadCalibrated(frame, calibration);
    _ensureAuthority();
    await _engine.startFromData(
      width: calibrated.width,
      height: calibrated.height,
      data: calibrated.data,
      config: stackingConfig,
    );
    _ensureAuthority();
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
    _ensureAuthority();
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
    _ensureAuthority();

    final meta = await _imagesDao.getImageById(frame.imageId);
    _ensureAuthority();
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
      _ensureAuthority();
      if (match != null) {
        darkData = await _loadMatchingPixels(match.filePath, raw.pixelCount);
        _ensureAuthority();
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

    return _RawFrame(width: raw.width, height: raw.height, data: calibrated);
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
      _ensureAuthority();
    }

    Uint16List? biasData;
    final biasPath = settings.masterBiasPath;
    if (biasPath != null && biasPath.isNotEmpty) {
      if (!File(biasPath).existsSync()) {
        throw FileSystemException('Master bias file not found', biasPath);
      }
      biasData = await _darkLibrary.loadDarkPixels(biasPath);
      _ensureAuthority();
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
    _ensureAuthority();
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
    _ensureAuthority();
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

  /// Resolve the OSC / colour intent for the run into a concrete engine config.
  ///
  /// The Stack-and-Share config carries a *sensor mode* (`auto` / `mono` /
  /// `osc`) and optional Bayer/demosaic knobs; the live stacker needs a single
  /// resolved [LiveStackingConfig] it can fix for the whole integration. This
  /// folds the share-loop OSC knobs into the wrapped stacking config (via
  /// [StackAndShareConfig.resolvedStackingConfig]) and then, for the OSC and
  /// auto modes, pins the concrete Bayer pattern:
  ///
  ///  * an explicit [StackAndShareConfig.bayerPatternOverride] always wins;
  ///  * otherwise the pattern is discovered from the connected camera's
  ///    [CameraCapabilities] (the live path) or, failing that, from the
  ///    reference frame's FITS `BAYERPAT` geometry exposed on
  ///    [LinearFrameData.bayerPattern] (the file path).
  ///
  /// For `sensorMode == 'osc'` an unresolvable pattern is a hard [StateError]:
  /// debayering with a guessed pattern would scramble the colour mosaic, so the
  /// run refuses rather than silently producing a wrong-colour stack ("errors
  /// are a feature"). For `auto`, leaving the pattern null is fine — the native
  /// engine only debayers when the frame actually carries Bayer geometry and
  /// otherwise treats the frame as mono. For `mono`, no resolution is needed.
  Future<LiveStackingConfig> _resolveStackingConfig({
    required StackAndShareConfig config,
    required StackedFrameSelection reference,
  }) async {
    final resolved = config.resolvedStackingConfig;
    final mode = config.sensorMode.trim().toLowerCase();

    // Mono never debayers; an explicit override already pins the pattern.
    if (mode == 'mono' || resolved.bayerPattern != null) {
      return resolved;
    }

    // auto / osc with no explicit override: discover the pattern, preferring
    // the live camera's declared CFA, then the reference frame's FITS geometry.
    final pattern = await _discoverBayerPattern(reference);
    _ensureAuthority();

    if (pattern == null) {
      if (mode == 'osc') {
        throw StateError(
          'Stack-and-Share is configured for OSC (colour) stacking but no '
          'Bayer pattern could be resolved for reference frame '
          '"${reference.filePath}": the connected camera reports no CFA '
          'pattern and the frame carries no FITS BAYERPAT geometry. Set an '
          'explicit Bayer pattern or use auto/mono mode.',
        );
      }
      // auto with no pattern → treat as mono (engine will not debayer).
      return resolved;
    }

    return resolved.copyWith(bayerPattern: pattern);
  }

  /// Discover the reference frame's Bayer pattern, preferring the connected
  /// camera's [CameraCapabilities] (the live path) and falling back to the
  /// reference frame's FITS `BAYERPAT` geometry (the file path). Returns null
  /// when neither source declares a CFA pattern (i.e. a mono sensor / frame).
  Future<String?> _discoverBayerPattern(StackedFrameSelection reference) async {
    // Live path: the connected camera's capabilities. An OSC camera advertises
    // `isColor` plus its `bayerPattern`; a mono camera advertises neither.
    final cameraId = _ref.read(connectedCameraIdProvider);
    if (cameraId != null && cameraId.isNotEmpty) {
      final caps = await _ref.read(cameraCapabilitiesProvider(cameraId).future);
      _ensureAuthority();
      final pattern = caps?.bayerPattern?.trim();
      if (caps != null &&
          caps.isColor &&
          pattern != null &&
          pattern.isNotEmpty) {
        return pattern;
      }
    }

    // File path: the reference frame's FITS BAYERPAT geometry (null for mono).
    final linear = await _engine.readLinearFrame(reference.filePath);
    _ensureAuthority();
    final framePattern = linear.bayerPattern?.trim();
    if (framePattern != null && framePattern.isNotEmpty) {
      return framePattern;
    }
    return null;
  }

  /// The single filter of the stack, or null when the selection spans multiple
  /// filters (or none were recorded).
  ///
  /// An OSC (colour) stack is labelled `'OSC'` — a one-shot-colour integration
  /// has no single named filter (it captures R, G and B through the CFA at
  /// once), so reporting the (often `noFilterBucket`) capture filter would be
  /// misleading; `'OSC'` is the conventional AstroBin/acquisition label. A mono
  /// stack reports its one filter; a multi-filter selection reports null so the
  /// result is not mislabelled.
  String? _singleFilter(
    StackSelectionSummary selection, {
    required bool isColor,
  }) {
    if (isColor) return 'OSC';
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

  /// Channel layout of [data]: `1` for a single mono luminance plane
  /// (`width * height` samples), `3` for an OSC integration stored as
  /// interleaved RGB16 (`width * height * 3` samples). Defaults to `1` so
  /// existing mono consumers are unaffected.
  final int channels;

  /// Integrated samples. For a mono result this is one luminance plane; for a
  /// colour result it is interleaved RGB16 (R,G,B per pixel).
  final Uint16List data;

  const StackedRawResult({
    required this.width,
    required this.height,
    this.channels = 1,
    required this.data,
  });

  /// Whether this is a colour (3-channel interleaved RGB16) result.
  bool get isColor => channels == 3;
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
  final backend = ref.watch(backendProvider);
  final exportService = ref.watch(stackShareExportServiceProvider);
  final service = StackAndShareService(
    ref,
    backend: backend,
    persistPreview: ({required result, required rgba}) {
      return exportService.persistViewerPreview(result: result, rgba: rgba);
    },
  );
  ref.onDispose(service.retire);
  return service;
});
