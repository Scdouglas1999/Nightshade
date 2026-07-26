import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show PlateSolveResult;
import '../backend/roles/device_backend.dart';
import 'plate_solve_service.dart';
import 'imaging_service.dart';
import 'device_service.dart';
import 'smart_notification_service.dart';
import '../providers/backend_provider.dart';
import '../providers/constellation_provider.dart'
    show coImagingSessionServiceProvider;
import '../providers/equipment_provider.dart';
import '../providers/imaging_provider.dart' show exposureSettingsProvider;
import '../providers/current_screen_provider.dart';
import 'logging_service.dart' show loggingServiceProvider;
import '../models/imaging/imaging_models.dart';
import '../models/equipment/equipment_models.dart';

/// Thrown when the mount status query fails for too many consecutive ticks
/// during the post-slew settle poll. Distinguishes a sustained
/// disconnect/hang from a single transient blip that the poll loop can ride
/// out.
///
/// Errors are a feature — surfacing this as a typed exception (rather than
/// silently waiting out the 60s wall-clock cap) lets callers and tests
/// observe the actual failure mode instead of "centering timed out".
class CenteringMountUnresponsiveException implements Exception {
  /// Number of consecutive failed `getMountStatus` calls before giving up.
  final int consecutiveFailures;

  /// Total wall-clock duration spanned by [consecutiveFailures] at the
  /// poll-tick rate.
  final Duration elapsed;

  /// The underlying error from the most recent failed mount status query.
  final Object cause;

  const CenteringMountUnresponsiveException({
    required this.consecutiveFailures,
    required this.elapsed,
    required this.cause,
  });

  @override
  String toString() {
    final seconds = elapsed.inMilliseconds / 1000.0;
    return 'Mount status query failed $consecutiveFailures times '
        'consecutively over ${seconds.toStringAsFixed(1)}s '
        '— aborting centering. The mount may be disconnected or '
        'unresponsive. Last error: $cause';
  }
}

/// Thrown when the mount keeps reporting that it is slewing for the full
/// post-slew settle budget.
class CenteringSlewTimeoutException implements Exception {
  final Duration elapsed;

  const CenteringSlewTimeoutException({required this.elapsed});

  @override
  String toString() {
    final seconds = elapsed.inMilliseconds / 1000.0;
    return 'Mount was still slewing after ${seconds.toStringAsFixed(1)}s. '
        'Centering stopped instead of taking another exposure while the mount '
        'was moving.';
  }
}

/// Result of a centering operation
class CenteringResult {
  final bool success;
  final double? finalOffsetArcsec;
  final int iterations;
  final String? errorMessage;
  final List<CenteringIteration> iterationHistory;

  const CenteringResult({
    required this.success,
    this.finalOffsetArcsec,
    required this.iterations,
    this.errorMessage,
    required this.iterationHistory,
  });

  factory CenteringResult.success({
    required double finalOffsetArcsec,
    required int iterations,
    required List<CenteringIteration> iterationHistory,
  }) {
    return CenteringResult(
      success: true,
      finalOffsetArcsec: finalOffsetArcsec,
      iterations: iterations,
      errorMessage: null,
      iterationHistory: iterationHistory,
    );
  }

  factory CenteringResult.failure({
    required String errorMessage,
    required int iterations,
    required List<CenteringIteration> iterationHistory,
  }) {
    return CenteringResult(
      success: false,
      finalOffsetArcsec: null,
      iterations: iterations,
      errorMessage: errorMessage,
      iterationHistory: iterationHistory,
    );
  }
}

/// Single iteration of the centering process
class CenteringIteration {
  final int iterationNumber;
  final double? solvedRa;
  final double? solvedDec;
  final double? targetRa;
  final double? targetDec;
  final double? offsetArcsec;
  final double? offsetArcmin;
  final bool plateSolveSuccess;
  final String? errorMessage;
  final DateTime timestamp;

  const CenteringIteration({
    required this.iterationNumber,
    this.solvedRa,
    this.solvedDec,
    this.targetRa,
    this.targetDec,
    this.offsetArcsec,
    this.offsetArcmin,
    required this.plateSolveSuccess,
    this.errorMessage,
    required this.timestamp,
  });
}

/// Configuration for centering operation
class CenteringConfig {
  /// Maximum number of centering iterations
  final int maxIterations;

  /// Tolerance in arcseconds - centering succeeds if offset is below this
  final double toleranceArcsec;

  /// Exposure time for centering images in seconds
  final double exposureTime;

  /// Binning to use for centering images
  final int binning;

  /// Gain to use for centering images. When omitted, the current imaging gain
  /// is preserved.
  final int? gain;

  /// Offset to use for centering images. When omitted, the current imaging
  /// offset is preserved.
  final int? offset;

  /// Whether to sync mount after successful plate solve
  final bool syncMount;

  /// Maximum wall-clock time for the full centering operation
  final Duration overallTimeout;

  const CenteringConfig({
    this.maxIterations = 5,
    this.toleranceArcsec = 30.0,
    this.exposureTime = 3.0,
    this.binning = 2,
    this.gain,
    this.offset,
    this.syncMount = false,
    this.overallTimeout = const Duration(minutes: 10),
  });
}

/// Current state of centering operation
enum CenteringState {
  idle,
  exposing,
  solving,
  slewing,
  verifying,
  completed,
  error,
}

/// Status information during centering
class CenteringStatus {
  final CenteringState state;
  final int currentIteration;
  final int maxIterations;
  final double? currentOffsetArcsec;
  final double? currentOffsetArcmin;
  final String? message;
  final List<CenteringIteration> iterationHistory;

  /// Path to the most recently captured centering image
  final String? lastImagePath;

  /// Solved RA of the most recent plate solve (hours)
  final double? solvedRa;

  /// Solved Dec of the most recent plate solve (degrees)
  final double? solvedDec;

  const CenteringStatus({
    required this.state,
    required this.currentIteration,
    required this.maxIterations,
    this.currentOffsetArcsec,
    this.currentOffsetArcmin,
    this.message,
    required this.iterationHistory,
    this.lastImagePath,
    this.solvedRa,
    this.solvedDec,
  });

  CenteringStatus copyWith({
    CenteringState? state,
    int? currentIteration,
    int? maxIterations,
    double? currentOffsetArcsec,
    double? currentOffsetArcmin,
    String? message,
    List<CenteringIteration>? iterationHistory,
    String? lastImagePath,
    double? solvedRa,
    double? solvedDec,
  }) {
    return CenteringStatus(
      state: state ?? this.state,
      currentIteration: currentIteration ?? this.currentIteration,
      maxIterations: maxIterations ?? this.maxIterations,
      currentOffsetArcsec: currentOffsetArcsec ?? this.currentOffsetArcsec,
      currentOffsetArcmin: currentOffsetArcmin ?? this.currentOffsetArcmin,
      message: message ?? this.message,
      iterationHistory: iterationHistory ?? this.iterationHistory,
      lastImagePath: lastImagePath ?? this.lastImagePath,
      solvedRa: solvedRa ?? this.solvedRa,
      solvedDec: solvedDec ?? this.solvedDec,
    );
  }

  factory CenteringStatus.idle() {
    return const CenteringStatus(
      state: CenteringState.idle,
      currentIteration: 0,
      maxIterations: 0,
      iterationHistory: [],
    );
  }
}

/// Service for automated target centering using plate solving
class CenteringService {
  final Ref _ref;
  final DeviceBackend _backend;

  /// Interval between mount-status polls during post-slew settle.
  ///
  /// 500ms keeps UI status reasonably fresh without hammering the bridge.
  static const Duration _defaultPollInterval = Duration(milliseconds: 500);

  /// Upper bound (in ticks) on the post-slew settle wait. 120 × 500ms = 60s
  /// — preserves the existing wall-clock budget for slow-but-working mounts.
  static const int _defaultMaxPollTicks = 120;

  /// Maximum number of consecutive `getMountStatus` failures tolerated
  /// during the settle poll before aborting centering with a typed
  /// [CenteringMountUnresponsiveException].
  ///
  /// 6 ticks × [_pollInterval] = 3 seconds of unbroken failure. A single
  /// transient blip (e.g. one missed COM frame, INDI reconnect) recovers on
  /// the next tick and never trips this threshold; a permanently-broken
  /// mount fails fast at 3s rather than dragging out the full 60s timeout.
  static const int _maxConsecutiveQueryFailures = 6;

  final Duration _pollInterval;
  final int _maxPollTicks;

  // Flag flipped by [stop]; checked at every centering loop yield-point so the
  // user-visible Abort path returns promptly and the post-stop status is
  // explicit ("aborted") rather than ambiguous.
  bool _abortRequested = false;
  bool _isRunning = false;
  bool _retired = false;
  bool _captureInFlight = false;
  bool _slewInFlight = false;
  Future<void>? _stopFuture;
  ImagingService? _ownedImagingService;
  DeviceService? _ownedDeviceService;

  CenteringService(
    this._ref, {
    DeviceBackend? backend,
    Duration slewPollInterval = _defaultPollInterval,
    int maxSlewPollTicks = _defaultMaxPollTicks,
  }) : _backend = backend ?? _ref.read(deviceBackendProvider),
       _pollInterval = slewPollInterval,
       _maxPollTicks = maxSlewPollTicks;

  /// True while a centering run has been asked to stop but hasn't returned yet.
  bool get isAborting => _abortRequested;

  /// True until the active centering owner's Future has fully settled.
  bool get isRunning => _isRunning;

  /// Abort the current centering run.
  ///
  /// Cancels the in-flight exposure (so the camera doesn't sit idle for the
  /// remainder of [CenteringConfig.exposureTime]) and aborts any in-progress
  /// mount slew, then sets the abort flag that the centering loop polls. The
  /// loop returns a [CenteringResult.failure] with `errorMessage: 'Aborted'`.
  ///
  /// Safe to call when no run is active. Only hardware currently owned by this
  /// service is interrupted, so an idle stop cannot cancel an unrelated camera
  /// exposure or mount slew.
  Future<void> stop() async {
    if (!_isRunning) return;
    _abortRequested = true;

    final existing = _stopFuture;
    if (existing != null) {
      await existing;
      return;
    }

    final operation = _stopOwnedHardware();
    _stopFuture = operation;
    await operation;
  }

  Future<void> _stopOwnedHardware() async {
    if (_captureInFlight) {
      _ownedImagingService?.cancelExposure();
    }

    if (_slewInFlight) {
      await _ownedDeviceService?.abortMountSlew();
    }
  }

  /// Retire this service when its backend changes. Any old-host work keeps
  /// unwinding against the services captured at admission and cannot abort or
  /// slew hardware on the replacement host.
  void retire() {
    if (_retired) return;
    _retired = true;
    if (!_isRunning) return;
    _abortRequested = true;
    unawaited(_stopOwnedHardware().catchError((_) {}));
  }

  /// Center on target coordinates with iterative plate solve and slew
  ///
  /// Returns a [CenteringResult] with success status and iteration history
  Future<CenteringResult> centerOnTarget({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    CenteringConfig config = const CenteringConfig(),
    void Function(CenteringStatus)? onStatusUpdate,
  }) async {
    final validationError = _validateRequest(
      targetRa: targetRa,
      targetDec: targetDec,
      solverConfig: solverConfig,
      config: config,
    );
    if (validationError != null) {
      return CenteringResult.failure(
        errorMessage: validationError,
        iterations: 0,
        iterationHistory: const [],
      );
    }

    if (_isRunning) {
      return CenteringResult.failure(
        errorMessage: 'Another centering operation is already running',
        iterations: 0,
        iterationHistory: const [],
      );
    }

    _isRunning = true;
    _abortRequested = false;
    final workFuture = _runCentering(
      targetRa: targetRa,
      targetDec: targetDec,
      solverConfig: solverConfig,
      config: config,
      onStatusUpdate: onStatusUpdate,
    );
    try {
      return await workFuture.timeout(
        config.overallTimeout,
        onTimeout: () async {
          await stop();
          CenteringResult? settledResult;
          try {
            settledResult = await workFuture;
          } catch (_) {
            // The timeout remains the user-facing terminal reason. Waiting for
            // the owner Future here is about hardware settlement, not replacing
            // it with a secondary cancellation exception.
          }
          return CenteringResult.failure(
            errorMessage:
                'Centering timed out after ${config.overallTimeout.inSeconds} seconds',
            iterations: settledResult?.iterations ?? 0,
            iterationHistory:
                settledResult?.iterationHistory ?? const <CenteringIteration>[],
          );
        },
      );
    } finally {
      final stopFuture = _stopFuture;
      try {
        if (stopFuture != null) {
          await stopFuture;
        }
      } finally {
        _isRunning = false;
        _abortRequested = false;
        _captureInFlight = false;
        _slewInFlight = false;
        _stopFuture = null;
        _ownedImagingService = null;
        _ownedDeviceService = null;
      }
    }
  }

  String? _validateRequest({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    required CenteringConfig config,
  }) {
    if (!targetRa.isFinite || targetRa < 0 || targetRa > 24) {
      return 'Target RA must be between 0 and 24 hours';
    }
    if (!targetDec.isFinite || targetDec < -90 || targetDec > 90) {
      return 'Target declination must be between -90° and +90°';
    }
    if (config.maxIterations < 1) {
      return 'Centering requires at least one iteration';
    }
    if (!config.toleranceArcsec.isFinite || config.toleranceArcsec <= 0) {
      return 'Centering tolerance must be greater than zero';
    }
    if (!config.exposureTime.isFinite || config.exposureTime <= 0) {
      return 'Centering exposure time must be greater than zero';
    }
    if (config.binning < 1) {
      return 'Centering binning must be at least 1';
    }
    if (config.gain != null && config.gain! < 0) {
      return 'Centering gain cannot be negative';
    }
    if (config.offset != null && config.offset! < 0) {
      return 'Centering offset cannot be negative';
    }
    if (config.overallTimeout <= Duration.zero) {
      return 'Centering timeout must be greater than zero';
    }
    if (solverConfig.timeoutSeconds < 1) {
      return 'Plate-solve timeout must be at least one second';
    }
    if (solverConfig.searchRadius != null &&
        (!solverConfig.searchRadius!.isFinite ||
            solverConfig.searchRadius! <= 0)) {
      return 'Plate-solve search radius must be greater than zero';
    }
    return null;
  }

  Future<CenteringResult> _runCentering({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    required CenteringConfig config,
    void Function(CenteringStatus)? onStatusUpdate,
  }) async {
    // WS3 Gap 1 — live co-imaging framing offset: when this target centre
    // belongs to a co-imaging session this rig is in, slew/centre on
    // `centre + the rig's hub-assigned offset` so the rigs tile the field and
    // reject correlated/walking noise instead of all framing identically. The
    // offset resolves from the durable membership (no hub round-trip); a rig in
    // no covering session, or any failure, falls through to the raw target so
    // ordinary centering is never affected. `targetRa` is app-canonical HOURS;
    // the offset helper works in degrees, so we convert at the boundary.
    final framed = await _resolveCoImagingFramedTarget(
      targetRaHours: targetRa,
      targetDecDeg: targetDec,
    );
    final effectiveRa = framed?.raHours ?? targetRa;
    final effectiveDec = framed?.decDeg ?? targetDec;
    if (_abortRequested) return _abortedResult(0, const []);
    return _centerOnTargetInternal(
      targetRa: effectiveRa,
      targetDec: effectiveDec,
      solverConfig: solverConfig,
      config: config,
      onStatusUpdate: onStatusUpdate,
    );
  }

  /// Resolve the co-imaging framing-offset-adjusted centre for a requested
  /// target (HOURS RA in / HOURS RA out), or null when this rig is not an active
  /// member of any co-imaging session covering the point. Defensive: a missing
  /// hub, an unbuilt provider (e.g. a centering unit test), or any resolver
  /// error logs a warning and returns null so centering proceeds on the raw
  /// target — the offset is an enhancement, never a precondition.
  Future<({double raHours, double decDeg})?> _resolveCoImagingFramedTarget({
    required double targetRaHours,
    required double targetDecDeg,
  }) async {
    try {
      final coImaging = _ref.read(coImagingSessionServiceProvider);
      final framed = await coImaging.framedCenterForPoint(
        centerRaDeg: targetRaHours * 15.0,
        centerDecDeg: targetDecDeg,
      );
      if (framed == null) return null;
      final raHours = framed.raDeg / 15.0;
      if (raHours == targetRaHours && framed.decDeg == targetDecDeg) {
        // Anchor slot (zero offset): nothing to apply.
        return null;
      }
      _ref
          .read(loggingServiceProvider)
          .info(
            'Co-imaging: framing this rig on its assigned coverage tile '
            '(${raHours.toStringAsFixed(4)}h, '
            '${framed.decDeg.toStringAsFixed(4)} deg) instead of the raw centre '
            '(${targetRaHours.toStringAsFixed(4)}h, '
            '${targetDecDeg.toStringAsFixed(4)} deg).',
            source: 'CenteringService',
          );
      return (raHours: raHours, decDeg: framed.decDeg);
    } catch (e) {
      _ref
          .read(loggingServiceProvider)
          .warning(
            'Co-imaging framing-offset resolve failed; centering on the raw '
            'target: $e',
            source: 'CenteringService',
          );
      return null;
    }
  }

  CenteringResult _abortedResult(
    int iteration,
    List<CenteringIteration> iterations,
  ) {
    return CenteringResult.failure(
      errorMessage: 'Aborted by user',
      iterations: iteration,
      iterationHistory: iterations,
    );
  }

  Future<CenteringResult> _centerOnTargetInternal({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    required CenteringConfig config,
    void Function(CenteringStatus)? onStatusUpdate,
  }) async {
    final iterations = <CenteringIteration>[];
    final mountState = _ref.read(mountStateProvider);
    final cameraState = _ref.read(cameraStateProvider);

    // Validate mount and camera are connected
    if (mountState.connectionState != DeviceConnectionState.connected) {
      return CenteringResult.failure(
        errorMessage: 'Mount not connected',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      return CenteringResult.failure(
        errorMessage: 'Camera not connected',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    final imagingService = _ref.read(imagingServiceProvider);
    final plateSolveService = _ref.read(plateSolveServiceProvider);
    final deviceService = _ref.read(deviceServiceProvider);
    _ownedImagingService = imagingService;
    _ownedDeviceService = deviceService;

    // Fail before taking a throwaway exposure when the selected solver is not
    // usable. This also catches the case where another solver is installed but
    // the explicitly selected one is not configured.
    await plateSolveService.ensureSolverAvailable();
    if (_abortRequested) return _abortedResult(0, iterations);

    // A "Slew & Center" action reaches this service as soon as the mount
    // accepts the initial slew command; that command Future does not mean the
    // mount has physically settled. Query the live backend and wait before the
    // first exposure so the frame is not captured while stars are trailing.
    final mountId = mountState.deviceId;
    if (mountId != null) {
      var shouldWaitForInitialSlew = false;
      try {
        shouldWaitForInitialSlew = (await _backend.getMountStatus(
          mountId,
        )).slewing;
      } catch (_) {
        // Let the bounded poll tolerate transient query failures and surface a
        // typed error if the mount remains unreachable.
        shouldWaitForInitialSlew = true;
      }

      if (shouldWaitForInitialSlew) {
        onStatusUpdate?.call(
          CenteringStatus(
            state: CenteringState.slewing,
            currentIteration: 0,
            maxIterations: config.maxIterations,
            message: 'Waiting for the initial slew to settle...',
            iterationHistory: iterations,
          ),
        );
        _slewInFlight = true;
        try {
          await _waitForSlewComplete(mountId);
        } on CenteringMountUnresponsiveException catch (e) {
          if (_abortRequested) return _abortedResult(0, iterations);
          return CenteringResult.failure(
            errorMessage: e.toString(),
            iterations: 0,
            iterationHistory: iterations,
          );
        } on CenteringSlewTimeoutException catch (e) {
          if (_abortRequested) return _abortedResult(0, iterations);
          return CenteringResult.failure(
            errorMessage: e.toString(),
            iterations: 0,
            iterationHistory: iterations,
          );
        } finally {
          _slewInFlight = false;
        }
        if (_abortRequested) return _abortedResult(0, iterations);
      }
    }

    for (int iteration = 1; iteration <= config.maxIterations; iteration++) {
      if (_abortRequested) return _abortedResult(iteration - 1, iterations);

      // Update status
      onStatusUpdate?.call(
        CenteringStatus(
          state: CenteringState.exposing,
          currentIteration: iteration,
          maxIterations: config.maxIterations,
          message:
              'Taking centering image (iteration $iteration/${config.maxIterations})...',
          iterationHistory: iterations,
        ),
      );

      // Step 1: Take short exposure
      final currentExposure = _ref.read(exposureSettingsProvider);
      final exposureSettings = ExposureSettings(
        exposureTime: config.exposureTime,
        gain: config.gain ?? currentExposure.gain,
        offset: config.offset ?? currentExposure.offset,
        binningX: config.binning,
        binningY: config.binning,
        frameType: FrameType.light,
      );

      CapturedImageData? capturedImage;
      _captureInFlight = true;
      try {
        capturedImage = await imagingService.captureImage(
          settings: exposureSettings,
          targetName: 'Centering',
        );
      } catch (e) {
        // Abort interrupts the in-flight exposure via cancelExposure() — the
        // imaging service surfaces this as a thrown error. Translate to an
        // explicit aborted result so the UI doesn't show "Centering Failed:
        // exposure cancelled".
        if (_abortRequested) return _abortedResult(iteration, iterations);
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: 'Image capture failed: $e',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Failed to capture image: $e',
          iterations: iteration,
          iterationHistory: iterations,
        );
      } finally {
        _captureInFlight = false;
      }

      if (capturedImage == null) {
        // imagingService.cancelExposure() can return null instead of throwing;
        // attribute null-on-abort to the user, not to the camera.
        if (_abortRequested) return _abortedResult(iteration, iterations);

        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: 'Image capture was cancelled',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Image capture cancelled',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      if (_abortRequested) return _abortedResult(iteration, iterations);

      // Step 2: Plate solve the image
      onStatusUpdate?.call(
        CenteringStatus(
          state: CenteringState.solving,
          currentIteration: iteration,
          maxIterations: config.maxIterations,
          message: 'Plate solving image...',
          iterationHistory: iterations,
          lastImagePath: capturedImage.filePath,
        ),
      );

      PlateSolveResult? solveResult;
      if (capturedImage.filePath != null) {
        solveResult = await plateSolveService.solveWithFallback(
          imagePath: capturedImage.filePath!,
          hintRaHours: solverConfig.hintRa ?? targetRa,
          hintDecDegrees: solverConfig.hintDec ?? targetDec,
          searchRadiusDegrees: solverConfig.searchRadius,
          timeoutSeconds: solverConfig.timeoutSeconds,
        );
      } else {
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: 'No image file path available',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        return CenteringResult.failure(
          errorMessage: 'Image file not saved',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // A plate solver cannot currently be interrupted, so Abort may arrive
      // while the solve Future is in flight. Never use a late solution to sync
      // or slew the mount after the user has cancelled.
      if (_abortRequested) return _abortedResult(iteration, iterations);

      if (!solveResult.success) {
        final iter = CenteringIteration(
          iterationNumber: iteration,
          plateSolveSuccess: false,
          errorMessage: solveResult.error ?? 'Plate solve failed',
          timestamp: DateTime.now(),
        );
        iterations.add(iter);

        // If we still have iterations left, retry after a short delay
        // instead of immediately aborting. Transient solve failures (e.g.
        // clouds, tracking hiccup) often succeed on the next attempt.
        if (iteration < config.maxIterations) {
          onStatusUpdate?.call(
            CenteringStatus(
              state: CenteringState.solving,
              currentIteration: iteration,
              maxIterations: config.maxIterations,
              message: 'Plate solve failed, retrying in 500ms...',
              iterationHistory: iterations,
              lastImagePath: capturedImage.filePath,
            ),
          );
          await Future.delayed(const Duration(milliseconds: 500));
          if (_abortRequested) return _abortedResult(iteration, iterations);
          continue;
        }

        return CenteringResult.failure(
          errorMessage:
              'Plate solve failed after $iteration attempts: ${solveResult.error}',
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // Step 3: Calculate offset from target.
      //
      // `solveResult.ra` is in DEGREES (solver/FITS frame). Normalise to
      // hours immediately so every downstream use in this iteration — the
      // offset math, the sync-to-solved-position slew, the status display and
      // the recorded iteration history — speaks the app-canonical hours frame
      // that `targetRa`, the mount and `CenteringStatus.solvedRa` all use.
      final solvedRa = _solvedRaHours(solveResult.ra);
      final solvedDec = solveResult.dec;
      final offset = _calculateOffset(targetRa, targetDec, solvedRa, solvedDec);

      final iter = CenteringIteration(
        iterationNumber: iteration,
        solvedRa: solvedRa,
        solvedDec: solvedDec,
        targetRa: targetRa,
        targetDec: targetDec,
        offsetArcsec: offset,
        offsetArcmin: offset / 60.0,
        plateSolveSuccess: true,
        timestamp: DateTime.now(),
      );
      iterations.add(iter);

      onStatusUpdate?.call(
        CenteringStatus(
          state: CenteringState.verifying,
          currentIteration: iteration,
          maxIterations: config.maxIterations,
          currentOffsetArcsec: offset,
          currentOffsetArcmin: offset / 60.0,
          message: 'Offset: ${(offset / 60.0).toStringAsFixed(2)} arcmin',
          iterationHistory: iterations,
          lastImagePath: capturedImage.filePath,
          solvedRa: solvedRa,
          solvedDec: solvedDec,
        ),
      );

      // Step 4: Check if within tolerance
      if (offset <= config.toleranceArcsec) {
        onStatusUpdate?.call(
          CenteringStatus(
            state: CenteringState.completed,
            currentIteration: iteration,
            maxIterations: config.maxIterations,
            currentOffsetArcsec: offset,
            currentOffsetArcmin: offset / 60.0,
            message: 'Target centered successfully!',
            iterationHistory: iterations,
            lastImagePath: capturedImage.filePath,
            solvedRa: solvedRa,
            solvedDec: solvedDec,
          ),
        );

        // Smart notification for centering completion
        final offsetArcmin = offset / 60.0;
        _ref
            .read(smartNotificationServiceProvider)
            .showSuccessIfNotOnScreens(
              message:
                  'Target centered (offset: ${offsetArcmin.toStringAsFixed(2)} arcmin)',
              relevantScreens: [AppScreen.imaging, AppScreen.sequencer],
              title: 'Centering Complete',
            );

        return CenteringResult.success(
          finalOffsetArcsec: offset,
          iterations: iteration,
          iterationHistory: iterations,
        );
      }

      // Step 5: Slew to correct position
      onStatusUpdate?.call(
        CenteringStatus(
          state: CenteringState.slewing,
          currentIteration: iteration,
          maxIterations: config.maxIterations,
          currentOffsetArcsec: offset,
          currentOffsetArcmin: offset / 60.0,
          message: 'Slewing to target...',
          iterationHistory: iterations,
          lastImagePath: capturedImage.filePath,
          solvedRa: solvedRa,
          solvedDec: solvedDec,
        ),
      );

      _slewInFlight = true;
      try {
        if (config.syncMount) {
          // Sync mount to solved coordinates, then slew to target
          await deviceService.syncMountToCoordinates(solvedRa, solvedDec);
          if (_abortRequested) return _abortedResult(iteration, iterations);
          await deviceService.slewMountToCoordinates(targetRa, targetDec);
        } else {
          // Just slew to target coordinates
          await deviceService.slewMountToCoordinates(targetRa, targetDec);
        }
        if (_abortRequested) return _abortedResult(iteration, iterations);

        // Wait for slew to complete by polling mount status.
        final correctionMountId = mountState.deviceId;
        if (correctionMountId != null) {
          await _waitForSlewComplete(correctionMountId);
        } else {
          await Future.delayed(const Duration(seconds: 2));
        }
      } on CenteringMountUnresponsiveException catch (e) {
        if (_abortRequested) return _abortedResult(iteration, iterations);
        return CenteringResult.failure(
          errorMessage: e.toString(),
          iterations: iteration,
          iterationHistory: iterations,
        );
      } on CenteringSlewTimeoutException catch (e) {
        if (_abortRequested) return _abortedResult(iteration, iterations);
        return CenteringResult.failure(
          errorMessage: e.toString(),
          iterations: iteration,
          iterationHistory: iterations,
        );
      } catch (e) {
        // Abort triggers abortMountSlew() which surfaces as a thrown error
        // from the in-flight slew future; report as user abort, not failure.
        if (_abortRequested) return _abortedResult(iteration, iterations);
        return CenteringResult.failure(
          errorMessage: 'Mount slew failed: $e',
          iterations: iteration,
          iterationHistory: iterations,
        );
      } finally {
        _slewInFlight = false;
      }

      if (_abortRequested) return _abortedResult(iteration, iterations);

      // Small delay before next iteration
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Max iterations reached without achieving tolerance
    final lastOffset = iterations.isNotEmpty
        ? iterations.last.offsetArcsec
        : null;
    return CenteringResult.failure(
      errorMessage:
          'Maximum iterations (${config.maxIterations}) reached. Final offset: ${lastOffset != null ? (lastOffset / 60.0).toStringAsFixed(2) : 'unknown'} arcmin',
      iterations: config.maxIterations,
      iterationHistory: iterations,
    );
  }

  /// Quick center using current mount position
  /// Takes an image, plate solves it, and slews to center the solved position
  Future<CenteringResult> plateAndCenter({
    required PlateSolverConfig solverConfig,
    CenteringConfig config = const CenteringConfig(),
    void Function(CenteringStatus)? onStatusUpdate,
  }) async {
    final mountState = _ref.read(mountStateProvider);

    // Get current mount position as target
    if (mountState.ra == null || mountState.dec == null) {
      return CenteringResult.failure(
        errorMessage: 'Mount position not available',
        iterations: 0,
        iterationHistory: [],
      );
    }

    return centerOnTarget(
      targetRa: mountState.ra!,
      targetDec: mountState.dec!,
      solverConfig: solverConfig,
      config: config,
      onStatusUpdate: onStatusUpdate,
    );
  }

  /// Verify that the current position is centered on target
  /// Takes an image, plate solves it, and returns the offset
  Future<CenteringResult> verifyCenter({
    required double targetRa,
    required double targetDec,
    required PlateSolverConfig solverConfig,
    double toleranceArcsec = 30.0,
    double exposureTime = 3.0,
    int binning = 2,
    int? gain,
    int? offset,
  }) async {
    final iterations = <CenteringIteration>[];
    final cameraState = _ref.read(cameraStateProvider);

    if (cameraState.connectionState != DeviceConnectionState.connected) {
      return CenteringResult.failure(
        errorMessage: 'Camera not connected',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    final imagingService = _ref.read(imagingServiceProvider);
    final plateSolveService = _ref.read(plateSolveServiceProvider);

    // Take an image
    final currentExposure = _ref.read(exposureSettingsProvider);
    final exposureSettings = ExposureSettings(
      exposureTime: exposureTime,
      gain: gain ?? currentExposure.gain,
      offset: offset ?? currentExposure.offset,
      binningX: binning,
      binningY: binning,
      frameType: FrameType.light,
    );

    CapturedImageData? capturedImage;
    try {
      capturedImage = await imagingService.captureImage(
        settings: exposureSettings,
        targetName: 'Verification',
      );
    } catch (e) {
      return CenteringResult.failure(
        errorMessage: 'Failed to capture image: $e',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    if (capturedImage == null || capturedImage.filePath == null) {
      return CenteringResult.failure(
        errorMessage: 'Image capture failed or cancelled',
        iterations: 0,
        iterationHistory: iterations,
      );
    }

    // Plate solve
    final solveResult = await plateSolveService.solveWithFallback(
      imagePath: capturedImage.filePath!,
      hintRaHours: solverConfig.hintRa ?? targetRa,
      hintDecDegrees: solverConfig.hintDec ?? targetDec,
      searchRadiusDegrees: solverConfig.searchRadius,
      timeoutSeconds: solverConfig.timeoutSeconds,
    );

    if (!solveResult.success) {
      final iter = CenteringIteration(
        iterationNumber: 1,
        plateSolveSuccess: false,
        errorMessage: solveResult.error ?? 'Plate solve failed',
        timestamp: DateTime.now(),
      );
      iterations.add(iter);

      return CenteringResult.failure(
        errorMessage: 'Plate solve failed: ${solveResult.error}',
        iterations: 1,
        iterationHistory: iterations,
      );
    }

    // Calculate offset. `solveResult.ra` is in DEGREES; normalise to hours so
    // it matches `targetRa` (hours) and the `CenteringIteration.solvedRa`
    // contract — same fix as the iterative `_centerOnTargetInternal` path.
    final solvedRaHours = _solvedRaHours(solveResult.ra);
    final angularOffset = _calculateOffset(
      targetRa,
      targetDec,
      solvedRaHours,
      solveResult.dec,
    );

    final iter = CenteringIteration(
      iterationNumber: 1,
      solvedRa: solvedRaHours,
      solvedDec: solveResult.dec,
      targetRa: targetRa,
      targetDec: targetDec,
      offsetArcsec: angularOffset,
      offsetArcmin: angularOffset / 60.0,
      plateSolveSuccess: true,
      timestamp: DateTime.now(),
    );
    iterations.add(iter);

    if (angularOffset <= toleranceArcsec) {
      return CenteringResult.success(
        finalOffsetArcsec: angularOffset,
        iterations: 1,
        iterationHistory: iterations,
      );
    } else {
      return CenteringResult.failure(
        errorMessage:
            'Offset ${(angularOffset / 60.0).toStringAsFixed(2)} arcmin exceeds tolerance ${(toleranceArcsec / 60.0).toStringAsFixed(2)} arcmin',
        iterations: 1,
        iterationHistory: iterations,
      );
    }
  }

  /// Poll the mount until `slewing == false`, the overall poll cap is hit, or
  /// abort is requested.
  ///
  /// Two distinct timeouts protect this loop:
  ///   1. [_maxPollTicks] (60s wall-clock) — upper bound for a
  ///      slow-but-working mount that just hasn't finished slewing yet.
  ///   2. [_maxConsecutiveQueryFailures] (3s of unbroken errors) — fail-fast
  ///      escalation when the mount stops answering at all (disconnected,
  ///      driver crashed, COM hung). A single transient failure resets on
  ///      the next successful poll and never trips this; only sustained
  ///      brokenness escalates by throwing
  ///      [CenteringMountUnresponsiveException].
  Future<void> _waitForSlewComplete(String mountId) async {
    await Future.delayed(_pollInterval);
    int pollCount = 0;
    int consecutiveQueryFailures = 0;
    Object? lastQueryError;
    while (pollCount < _maxPollTicks && !_abortRequested) {
      try {
        final status = await _backend.getMountStatus(mountId);
        // Success — clear the consecutive-failure counter. A single
        // transient error followed by a good poll must NOT escalate.
        consecutiveQueryFailures = 0;
        lastQueryError = null;
        if (!status.slewing) {
          return;
        }
      } on CenteringMountUnresponsiveException {
        // Never wrap our own escalation — preserve the original frame.
        rethrow;
      } on Object catch (e) {
        consecutiveQueryFailures++;
        lastQueryError = e;
        // ignore: avoid_print
        print(
          'CenteringService: post-slew status poll failed '
          '($consecutiveQueryFailures/$_maxConsecutiveQueryFailures): $e',
        );

        if (consecutiveQueryFailures >= _maxConsecutiveQueryFailures) {
          // Errors are a feature: escalate the sustained outage as a
          // typed exception so the caller can surface a precise failure
          // reason in [CenteringResult], rather than silently riding out
          // the 60s cap.
          throw CenteringMountUnresponsiveException(
            consecutiveFailures: consecutiveQueryFailures,
            elapsed: _pollInterval * consecutiveQueryFailures,
            cause: lastQueryError,
          );
        }
      }
      await Future.delayed(_pollInterval);
      pollCount++;
    }

    if (!_abortRequested) {
      throw CenteringSlewTimeoutException(
        elapsed: _pollInterval * _maxPollTicks,
      );
    }
  }

  /// Right ascension returned by the plate solver, in **degrees**, converted
  /// to the app-canonical **hours** the rest of the centering pipeline uses.
  ///
  /// This is the fix for the 2026-06-04 full-night-audit "slew & center never
  /// converges" bug. `PlateSolveResult.ra` arrives in degrees: the Rust
  /// `PlateSolveResult.ra` is documented "Solved RA in degrees" and reads FITS
  /// `CRVAL1` (degrees) verbatim, and the network host forwards that same
  /// value unchanged. Every other RA in this service is in hours — the slew
  /// target (`slewMountToCoordinates` expects hours), the mount sync
  /// (`syncMountToCoordinates` expects hours), `mountState.ra` (ASCOM
  /// `RightAscension`, hours) and the `CenteringStatus.solvedRa` contract
  /// ("hours"). Normalising once here keeps the offset math, the sync-to-
  /// solved-position slew, and the status display all consistent. Without
  /// this, the solved RA was 15× the target RA's frame, so the offset never
  /// fell below tolerance and the loop ran out its iterations.
  static double _solvedRaHours(double solvedRaDegrees) {
    return solvedRaDegrees / 15.0;
  }

  /// Calculate angular separation between two celestial coordinates in
  /// arcseconds, using the haversine formula for great-circle distance.
  ///
  /// Both [targetRa] and [solvedRa] are in **hours** here (the solver's
  /// degrees value is normalised to hours via [_solvedRaHours] before it
  /// reaches this method); [targetDec]/[solvedDec] are in degrees.
  double _calculateOffset(
    double targetRa,
    double targetDec,
    double solvedRa,
    double solvedDec,
  ) {
    // Convert RA from hours to radians (both operands are in hours).
    final ra1 =
        targetRa * 15.0 * math.pi / 180.0; // hours -> degrees -> radians
    final ra2 = solvedRa * 15.0 * math.pi / 180.0;

    // Convert Dec from degrees to radians
    final dec1 = targetDec * math.pi / 180.0;
    final dec2 = solvedDec * math.pi / 180.0;

    // Haversine formula for great circle distance
    final deltaRa = ra2 - ra1;
    final deltaDec = dec2 - dec1;

    final a =
        math.pow(math.sin(deltaDec / 2), 2) +
        math.cos(dec1) * math.cos(dec2) * math.pow(math.sin(deltaRa / 2), 2);
    final c = 2 * math.asin(math.sqrt(a));

    // Convert radians to arcseconds
    final offsetRadians = c;
    final offsetDegrees = offsetRadians * 180.0 / math.pi;
    final offsetArcsec = offsetDegrees * 3600.0;

    return offsetArcsec;
  }
}

/// Provider for the centering service
final centeringServiceProvider = Provider<CenteringService>((ref) {
  final backend = ref.watch(deviceBackendProvider);
  final service = CenteringService(
    ref,
    backend: backend,
    slewPollInterval: ref.watch(centeringSlewPollIntervalProvider),
    maxSlewPollTicks: ref.watch(centeringSlewMaxPollTicksProvider),
  );
  ref.onDispose(service.retire);
  return service;
});

/// Timing seams used by deterministic centering lifecycle tests.
final centeringSlewPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 500),
);
final centeringSlewMaxPollTicksProvider = Provider<int>((ref) => 120);

/// Provider for centering status
final centeringStatusProvider = StateProvider<CenteringStatus>((ref) {
  return CenteringStatus.idle();
});

/// Provider for last centering result
final lastCenteringResultProvider = StateProvider<CenteringResult?>(
  (ref) => null,
);
