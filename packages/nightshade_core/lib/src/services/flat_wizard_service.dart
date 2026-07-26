import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../backend/nightshade_backend.dart';
import '../backend/network_backend.dart';
import '../models/flat_wizard/flat_capture_config.dart';
import '../models/flat_wizard/flat_wizard_settings.dart';
import '../models/sequence/sequence_models.dart';
import '../models/imaging/imaging_models.dart';
import '../providers/backend_provider.dart';
import '../providers/flat_wizard_provider.dart';
import 'sky_brightness_tracker.dart';
import 'flat_exposure_calculator.dart';

/// Result of a flat frame calibration for a single filter
class FlatResult {
  final String filter;
  final double exposure;
  final double adu;
  final bool success;
  final int iterations;
  final String? errorMessage;

  /// True when calibration stopped because a cancel was requested (as opposed
  /// to a hardware/convergence failure). A cancelled result is never
  /// `success`, but the caller must distinguish it from a genuine failure so
  /// the run reports "Cancelled" rather than "failed" and does not mark the
  /// filter as failed.
  final bool cancelled;

  /// True when the ENTIRE run must stop, not just this filter: the calibration
  /// exposure timed out or the camera's post-abort idle state could not be
  /// confirmed, so it is unsafe to start any further exposure. A plain
  /// `!success` (e.g. failed to converge) lets the run continue to the next
  /// filter; [haltRun] does not.
  final bool haltRun;

  /// True when the camera's state is UNKNOWN after a failed abort/settle — the
  /// operator must be told to check the hardware before retrying.
  final bool cameraStateUnknown;

  const FlatResult({
    required this.filter,
    required this.exposure,
    required this.adu,
    required this.success,
    this.iterations = 0,
    this.errorMessage,
    this.cancelled = false,
    this.haltRun = false,
    this.cameraStateUnknown = false,
  });

  FlatResult copyWith({
    String? filter,
    double? exposure,
    double? adu,
    bool? success,
    int? iterations,
    String? errorMessage,
    bool? cancelled,
    bool? haltRun,
    bool? cameraStateUnknown,
  }) {
    return FlatResult(
      filter: filter ?? this.filter,
      exposure: exposure ?? this.exposure,
      adu: adu ?? this.adu,
      success: success ?? this.success,
      iterations: iterations ?? this.iterations,
      errorMessage: errorMessage ?? this.errorMessage,
      cancelled: cancelled ?? this.cancelled,
      haltRun: haltRun ?? this.haltRun,
      cameraStateUnknown: cameraStateUnknown ?? this.cameraStateUnknown,
    );
  }
}

/// Cooperative cancellation token threaded through the flat-capture lifecycle.
///
/// A single token is created per capture run by [FlatWizardNotifier.runCapture]
/// and passed down into every [FlatWizardService] call. Cancellation is
/// cooperative: callers poll [isCancelled] between hardware operations, and the
/// in-flight exposure wait races [whenCancelled] so a cancel that arrives
/// mid-exposure aborts the hardware promptly instead of waiting out a fixed
/// delay.
class FlatCancelToken {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  /// Whether a cancel has been requested.
  bool get isCancelled => _cancelled;

  /// Completes the first time [cancel] is called. Used to race against an
  /// in-flight exposure-completion event so cancellation is not blocked by a
  /// long exposure.
  Future<void> get whenCancelled => _completer.future;

  /// Request cancellation. Idempotent — the second and later calls are no-ops
  /// so [whenCancelled] completes exactly once.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Terminal outcome of a single authoritative frame capture.
enum FlatFrameOutcome {
  /// Exposure completed and an image was retrieved.
  completed,

  /// Exposure completed/failed but no usable image was produced, or the
  /// hardware reported an explicit failure.
  failed,

  /// A cancel was requested; the exposure was aborted (or never started).
  cancelled,

  /// No terminal completion event arrived within the bounded wait.
  timedOut,
}

/// Result of [FlatWizardService.exposeAndAwait]: the authoritative outcome plus
/// the retrieved image (on [FlatFrameOutcome.completed]) and its mean ADU.
class FlatFrameCapture {
  final FlatFrameOutcome outcome;
  final CapturedImageResult? image;
  final String? error;

  /// Whether the camera is CONFIRMED idle/quiescent after this frame. A
  /// completed or failed frame reached a terminal event, so the camera is
  /// provably idle. For a timed-out or cancelled frame this reflects whether
  /// abort + a bounded settle wait was confirmed: when false the camera's state
  /// is UNKNOWN and the run must stop rather than risk overlapping the next
  /// exposure with a still-active one.
  final bool cameraQuiescent;

  const FlatFrameCapture({
    required this.outcome,
    this.image,
    this.error,
    this.cameraQuiescent = true,
  });

  /// Mean ADU of the retrieved frame, or null when no image was produced.
  double? get adu => image?.stats.mean;

  bool get isCompleted => outcome == FlatFrameOutcome.completed;
  bool get isCancelled => outcome == FlatFrameOutcome.cancelled;
  bool get isTimedOut => outcome == FlatFrameOutcome.timedOut;
}

/// Classification of an incoming event relative to an in-flight exposure.
enum _ExposureEventKind { completedOk, failed, cancelled, notTerminal }

/// Internal union describing which of the three racing sources woke the
/// exposure wait in [FlatWizardService.exposeAndAwait]: a terminal event, a
/// cancel request, or the overall timeout.
class _CaptureWake {
  final _ExposureEventKind? kind;
  final bool isTimeout;

  const _CaptureWake._(this.kind, this.isTimeout);

  factory _CaptureWake.event(_ExposureEventKind k) => _CaptureWake._(k, false);
  factory _CaptureWake.cancel() => const _CaptureWake._(null, false);
  factory _CaptureWake.timeout() => const _CaptureWake._(null, true);

  /// The cancel branch fired (no event, not a timeout).
  bool get isCancel => kind == null && !isTimeout;
}

/// Service for flat frame calibration and sequence generation
class FlatWizardService {
  final NightshadeBackend backend;

  // Image download timeout was previously
  // a hardcoded `Duration(seconds: 60)` constant. It is now sourced from
  // [FlatWizardGlobalSettings.imageDownloadTimeoutSeconds] (default 60s) so
  // operators with very large sensors or slow USB hubs can tune it without a
  // recompile. Defaults are passed in via the provider constructor below.
  final Duration imageDownloadTimeout;

  /// Default maximum binary-search iterations used by [quickCalibrate]. Wired
  /// from [FlatWizardGlobalSettings.maxIterations] (default 8).
  final int defaultMaxIterations;

  FlatWizardService(
    this.backend, {
    this.imageDownloadTimeout = const Duration(seconds: 60),
    this.defaultMaxIterations = 8,
    this.quickMinExposure = 0.001,
    this.quickMaxExposure = 30.0,
  });

  /// Build a service from [FlatWizardGlobalSettings] so settings-driven defaults
  /// flow into the service in one place.
  factory FlatWizardService.fromSettings(
    NightshadeBackend backend,
    FlatWizardGlobalSettings settings,
  ) {
    return FlatWizardService(
      backend,
      imageDownloadTimeout: Duration(
        seconds: settings.imageDownloadTimeoutSeconds,
      ),
      defaultMaxIterations: settings.maxIterations,
      quickMinExposure: settings.minExposure,
      quickMaxExposure: settings.maxExposure,
    );
  }

  /// Resolve the effective, capability-aware capture configuration for a flat
  /// run from the CONNECTED camera plus the active profile.
  ///
  /// This is the single source of truth for the effective ADU range, the gain/
  /// offset actually commanded, and the binning — used by the UI preview, the
  /// backend command, the FITS header, and the DB record so they cannot drift.
  ///
  /// Host authority (defect: remote mode): [backend.getCameraStatus] and
  /// [backend.getCameraCapabilities] route to the master on a [NetworkBackend],
  /// so the host — not the phone — defines the range and capability limits. Both
  /// Calls are best-effort so the UI can still render a disconnected/partial
  /// preview, but the returned [FlatCaptureConfig.rangeKnown] tells capture
  /// callers whether the ADU range is authoritative enough to automate.
  static Future<FlatCaptureConfig> resolveCaptureConfig({
    required NightshadeBackend backend,
    required String deviceId,
    int? profileDefaultGain,
    int? profileDefaultOffset,
    int? profileBinX,
    int? profileBinY,
    int? currentGain,
    int? currentOffset,
    int? fallbackBinX,
    int? fallbackBinY,
  }) async {
    CameraStatus? status;
    CameraCapabilities? caps;
    // Bare `catch` (not `on Exception`): an unavailable/disconnected device may
    // surface as an Error, and a capability probe must never abort the run —
    // but a failed probe degrades the resolved config (guessed range, default
    // gain), so it is logged rather than silently swallowed.
    try {
      status = await backend.getCameraStatus(deviceId);
    } catch (e) {
      developer.log(
        'FlatWizard: camera status probe failed for $deviceId: $e',
        name: 'FlatWizardService',
        level: 900,
      );
    }
    try {
      caps = await backend.getCameraCapabilities(deviceId);
    } catch (e) {
      developer.log(
        'FlatWizard: camera capabilities probe failed for $deviceId: $e',
        name: 'FlatWizardService',
        level: 900,
      );
    }

    // ---- Effective full-scale ADU ----
    // The DRIVER-reported max-ADU is authoritative, and bit depth is only a
    // last-resort fallback when no driver value exists.
    //
    // This used to take `min(status.maxAdu, (1 << bitDepth) - 1)` on the theory
    // that a 12/14-bit sensor "cannot reach" a 16-bit ADU. That confuses ADC
    // resolution with the pixel container: 12- and 14-bit astro CMOS drivers
    // left-justify their samples into the 16-bit pixel word, so an ASI1600MM
    // (bitDepth 12) genuinely produces values up to 65504 — measured live: a
    // 2 ms frame read min 3856 / max 5792 / median 4464 (all exact multiples of
    // 16) and a saturated frame clipped at 65504. The min() therefore pinned the
    // flat target at 50% of 4095 = 2048, BELOW the camera's own bias floor at
    // the shortest possible exposure, so flat calibration could never converge
    // on that camera — it drove exposure to the minimum and reported
    // `minExposureReached` forever.
    //
    // Measured ADU (`FlatFrameCapture.adu` = `image.stats.mean`) is in pixel
    // container units, so the target must be scaled by the container's full
    // scale — which is exactly what `CameraStatus.maxAdu` reports. Trusting the
    // driver can only be wrong if a driver misreports its own MaxADU; being
    // wrong high merely lengthens flats, whereas the bit-depth guess made them
    // unreachable.
    final bitDepth = caps?.bitDepth;
    int? maxAduCandidate;
    if (status != null && status.maxAdu > 0) {
      maxAduCandidate = status.maxAdu;
    } else if (bitDepth != null && bitDepth >= 1 && bitDepth <= 32) {
      maxAduCandidate = (1 << bitDepth) - 1;
    }
    final rangeKnown = maxAduCandidate != null;
    final maxAdu = maxAduCandidate ?? FlatExposureCalculator.fallbackMaxAdu;

    // ---- Gain ----
    // Unknown is NOT permission to command a control. Fail closed to the
    // driver default unless at least one authoritative surface explicitly
    // reports support and neither explicitly rejects it.
    final gainSupported =
        (caps?.canSetGain == true || status?.canSetGain == true) &&
        caps?.canSetGain != false &&
        status?.canSetGain != false;
    int? gain;
    if (gainSupported) {
      // profile default wins, then the live connected value. Null => the
      // camera/driver default (NOT numeric zero).
      gain = profileDefaultGain ?? currentGain ?? status?.gain;
      gain = _clampToRange(gain, caps?.gainMin, caps?.gainMax);
    }

    // ---- Offset ----
    final offsetSupported =
        (caps?.canSetOffset == true || status?.canSetOffset == true) &&
        caps?.canSetOffset != false &&
        status?.canSetOffset != false;
    int? offset;
    if (offsetSupported) {
      offset = profileDefaultOffset ?? currentOffset ?? status?.offset;
      offset = _clampToRange(offset, caps?.offsetMin, caps?.offsetMax);
    }

    // ---- Binning ----
    var binX = (profileBinX ?? fallbackBinX ?? 1);
    var binY = (profileBinY ?? fallbackBinY ?? 1);
    if (binX < 1) binX = 1;
    if (binY < 1) binY = 1;
    // Binning has no status-level capability flag, so only an explicit camera
    // capability enables it. Unknown drivers remain at the safe 1x1 default.
    final canBin = caps?.canBin == true;
    final canAsymmetricBin = caps?.canAsymmetricBin ?? false;
    if (!canBin) {
      // Camera cannot bin — never command anything but 1×1.
      binX = 1;
      binY = 1;
    } else {
      final mbx = caps?.maxBinX;
      final mby = caps?.maxBinY;
      if (mbx != null && mbx >= 1 && binX > mbx) binX = mbx;
      if (mby != null && mby >= 1 && binY > mby) binY = mby;
      // Only force symmetric when we KNOW asymmetric binning is unsupported.
      if (caps != null && !canAsymmetricBin && binX != binY) binY = binX;
    }

    return FlatCaptureConfig(
      maxAdu: maxAdu,
      bitDepth: bitDepth,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      canSetGain: gainSupported,
      canSetOffset: offsetSupported,
      gainMin: caps?.gainMin,
      gainMax: caps?.gainMax,
      offsetMin: caps?.offsetMin,
      offsetMax: caps?.offsetMax,
      canBin: canBin,
      canAsymmetricBin: canAsymmetricBin,
      maxBinX: caps?.maxBinX ?? binX,
      maxBinY: caps?.maxBinY ?? binY,
      hostAuthoritative: backend is NetworkBackend,
      capabilitiesKnown: caps != null,
      rangeKnown: rangeKnown,
    );
  }

  /// Clamp [value] into the inclusive `[lo, hi]` capability range when known.
  /// A null [value] stays null (the camera/driver default is used).
  static int? _clampToRange(int? value, int? lo, int? hi) {
    if (value == null) return null;
    var v = value;
    if (lo != null && v < lo) v = lo;
    if (hi != null && v > hi) v = hi;
    return v;
  }

  /// Calculate next exposure time to reach target ADU using proportional adjustment
  ///
  /// Uses a conservative approach with safety limits to avoid overshooting:
  /// - Limits adjustment ratio to prevent extreme jumps
  /// - Applies minimum/maximum exposure bounds
  /// - Uses logarithmic damping for large adjustments
  double calculateNextExposure({
    required double currentExposure,
    required double currentAdu,
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
  }) {
    // Avoid division by zero
    if (currentAdu <= 0) {
      return (minExposure + maxExposure) / 2;
    }

    // Calculate raw ratio
    final ratio = targetAdu / currentAdu;

    // Apply safety limits to prevent extreme jumps
    // Allow max 3x increase or 1/3x decrease per iteration
    final clampedRatio = ratio.clamp(0.33, 3.0);

    // For large adjustments, use logarithmic damping
    final adjustedRatio = clampedRatio > 2.0 || clampedRatio < 0.5
        ? 1.0 +
              (clampedRatio - 1.0) *
                  0.7 // Reduce aggressive changes
        : clampedRatio;

    // Calculate next exposure
    final nextExposure = currentExposure * adjustedRatio;

    // Clamp to valid range
    return nextExposure.clamp(minExposure, maxExposure);
  }

  /// Imaging event types that terminate an in-flight exposure. Anything else
  /// on the stream (progress, temperature, download-started, unrelated
  /// categories) is ignored so the wait cannot be woken by a stray event.
  static const Set<String> _terminalExposureEventTypes = {
    'ExposureComplete',
    'ExposureCompleted',
    'ExposureFailed',
    'ExposureCancelled',
  };

  /// Keys under which an imaging event may carry the originating camera id.
  /// FFI-originated exposure events do NOT carry any of these (the native side
  /// has a single active camera), so absence means "accept" (operation
  /// scoping). When a key IS present it MUST match the camera we drove, so a
  /// second camera's completion on a shared stream can never satisfy our wait.
  static const List<String> _deviceIdKeys = [
    'deviceId',
    'device_id',
    'cameraId',
    'camera_id',
  ];

  /// Classify [event] relative to an exposure we started on [deviceId].
  ///
  /// Returns [_ExposureEventKind.notTerminal] for anything that must NOT settle
  /// the wait: non-imaging categories, non-terminal event types, and — the
  /// correlation guard — a terminal event tagged with a *different* device id.
  _ExposureEventKind _classifyExposureEvent(
    NightshadeEvent event,
    String deviceId,
  ) {
    if (event.category != EventCategory.imaging) {
      return _ExposureEventKind.notTerminal;
    }
    if (!_terminalExposureEventTypes.contains(event.eventType)) {
      return _ExposureEventKind.notTerminal;
    }
    // Device correlation: if the event names a device, it must be ours.
    for (final key in _deviceIdKeys) {
      final raw = event.data[key];
      if (raw != null &&
          raw.toString().isNotEmpty &&
          raw.toString() != deviceId) {
        return _ExposureEventKind.notTerminal;
      }
    }
    switch (event.eventType) {
      case 'ExposureFailed':
        return _ExposureEventKind.failed;
      case 'ExposureCancelled':
        return _ExposureEventKind.cancelled;
      case 'ExposureComplete':
        // Legacy event carries an explicit success flag.
        final success = event.data['success'];
        return success == false
            ? _ExposureEventKind.failed
            : _ExposureEventKind.completedOk;
      default: // ExposureCompleted
        return _ExposureEventKind.completedOk;
    }
  }

  /// Authoritative single-frame capture used by BOTH the calibration solver and
  /// the frame-capture loop.
  ///
  /// Correctness guarantees this centralizes:
  ///   * Subscribes to the event stream BEFORE starting the exposure, so a fast
  ///     completion cannot fire before we are listening.
  ///   * Settles on the FIRST terminal exposure event correlated to
  ///     [deviceId] (see [_classifyExposureEvent]) — never a fixed delay, so a
  ///     slow readout is waited out and a stray/unrelated-device event is
  ///     ignored.
  ///   * Cooperative cancel: if [cancelToken] is (or becomes) cancelled while
  ///     the exposure is in flight, [cameraAbortExposure] is called EXACTLY
  ///     once, then we wait a bounded time for the hardware to settle before
  ///     returning [FlatFrameOutcome.cancelled] — the caller then starts no
  ///     further frame.
  ///   * Timeout: an exposure that does not reach a terminal event within the
  ///     overall bound is aborted EXACTLY once and awaited-to-settle just like a
  ///     cancel. The stale prior image is NEVER read as the timed-out frame. If
  ///     the abort throws or idle cannot be confirmed the returned capture has
  ///     `cameraQuiescent == false` so the caller stops the run.
  ///   * Only [FlatFrameOutcome.completed] fetches the image; a null image is
  ///     reported as [FlatFrameOutcome.failed], not a silent success.
  ///
  /// [gain]/[offset] are nullable: `null` commands the camera/driver default
  /// (NOT numeric zero) and is passed straight through to the backend.
  Future<FlatFrameCapture> exposeAndAwait({
    required String deviceId,
    required double exposureTime,
    int? gain,
    int? offset,
    String? filterName,
    int? filterPosition,
    String? filterWheelDeviceId,
    int binX = 1,
    int binY = 1,
    FlatCancelToken? cancelToken,
    Duration abortSettleTimeout = const Duration(seconds: 10),
    Duration? overallTimeout,
  }) async {
    // A cancel that arrived before we even started: do not touch the hardware.
    if (cancelToken?.isCancelled ?? false) {
      return const FlatFrameCapture(outcome: FlatFrameOutcome.cancelled);
    }

    try {
      // Change filter if specified and a filter wheel device ID is available.
      if (filterWheelDeviceId != null) {
        if (filterName != null) {
          await backend.filterWheelSetByName(filterWheelDeviceId, filterName);
        } else if (filterPosition != null) {
          await backend.filterWheelSetPosition(
            filterWheelDeviceId,
            filterPosition,
          );
        }
      }

      if (cancelToken?.isCancelled ?? false) {
        return const FlatFrameCapture(outcome: FlatFrameOutcome.cancelled);
      }

      // Subscribe BEFORE starting the exposure to avoid a lost-wakeup race.
      final terminal = Completer<_ExposureEventKind>();
      final subscription = backend.eventStream.listen((event) {
        final kind = _classifyExposureEvent(event, deviceId);
        if (kind == _ExposureEventKind.notTerminal) return;
        if (!terminal.isCompleted) terminal.complete(kind);
      });

      var aborted = false;

      // Abort the in-flight exposure EXACTLY once, then wait a bounded time for
      // the authoritative terminal settle event so the driver is provably
      // quiescent before the caller moves on (or stops). Returns whether the
      // camera is confirmed idle: false when the abort itself threw or the
      // settle event never arrived — in which case the camera state is UNKNOWN.
      Future<bool> abortAndSettle() async {
        if (!aborted) {
          aborted = true;
          try {
            await backend.cameraAbortExposure(deviceId);
          } catch (e) {
            developer.log(
              'FlatWizardService: cameraAbortExposure failed: $e',
              name: 'FlatWizardService',
              level: 900,
              error: e,
            );
            return false; // abort failed → camera state unknown
          }
        }
        var settled = true;
        await terminal.future.timeout(
          abortSettleTimeout,
          onTimeout: () {
            settled = false; // idle could not be confirmed in time
            return _ExposureEventKind.cancelled;
          },
        );
        return settled;
      }

      try {
        await backend.cameraStartExposure(
          deviceId: deviceId,
          exposureTime: exposureTime,
          frameType: FrameType.flat,
          gain: gain,
          offset: offset,
          binX: binX,
          binY: binY,
        );

        // Race the authoritative terminal event against a cancel request and a
        // generous overall timeout (exposure + readout/download headroom).
        // `whenCancelled` completes immediately if the token was already
        // cancelled just before we got here, so a late cancel is never missed.
        final overall =
            overallTimeout ??
            Duration(milliseconds: (exposureTime * 1000).toInt() + 30000);
        final futures = <Future<_CaptureWake>>[
          terminal.future.then(_CaptureWake.event),
        ];
        if (cancelToken != null) {
          futures.add(
            cancelToken.whenCancelled.then((_) => _CaptureWake.cancel()),
          );
        }
        final wake = await Future.any(
          futures,
        ).timeout(overall, onTimeout: _CaptureWake.timeout);

        if (wake.isTimeout) {
          // The exposure never reached a terminal event. Abort it (once) and
          // wait for the camera to settle — do NOT read `getLastImage`, which
          // would hand back a STALE prior frame as if it were this exposure.
          developer.log(
            'FlatWizardService: Exposure timed out after '
            '${exposureTime + 30}s; aborting',
            name: 'FlatWizardService',
            level: 900,
          );
          final quiescent = await abortAndSettle();
          return FlatFrameCapture(
            outcome: FlatFrameOutcome.timedOut,
            cameraQuiescent: quiescent,
            error: quiescent
                ? 'Exposure timed out (camera aborted and idle)'
                : 'Exposure timed out and the camera could not be confirmed '
                      'idle — check the camera',
          );
        }

        if (wake.isCancel) {
          // Cancel requested mid-exposure: abort the hardware EXACTLY once,
          // then wait a bounded time for the terminal settle event so the
          // driver is quiescent before the caller moves on (or stops).
          final quiescent = await abortAndSettle();
          return FlatFrameCapture(
            outcome: FlatFrameOutcome.cancelled,
            cameraQuiescent: quiescent,
          );
        }

        final kind = wake.kind!;
        if (kind == _ExposureEventKind.cancelled) {
          return const FlatFrameCapture(outcome: FlatFrameOutcome.cancelled);
        }
        if (kind == _ExposureEventKind.failed) {
          return const FlatFrameCapture(
            outcome: FlatFrameOutcome.failed,
            error: 'Exposure reported failure',
          );
        }
      } finally {
        await subscription.cancel();
      }

      // Terminal completed-ok: retrieve the image (bounded download timeout).
      final image = await backend
          .cameraGetLastImage(deviceId)
          .timeout(
            imageDownloadTimeout,
            onTimeout: () {
              developer.log(
                'FlatWizardService: Image retrieval timed out after '
                '${imageDownloadTimeout.inSeconds}s',
                name: 'FlatWizardService',
                level: 900,
              );
              return null;
            },
          );
      if (image == null) {
        developer.log(
          'FlatWizardService: Failed to retrieve captured frame',
          name: 'FlatWizardService',
          level: 900,
        );
        return const FlatFrameCapture(
          outcome: FlatFrameOutcome.failed,
          error: 'Failed to retrieve captured frame',
        );
      }
      return FlatFrameCapture(
        outcome: FlatFrameOutcome.completed,
        image: image,
      );
    } catch (e) {
      developer.log(
        'FlatWizardService: Error capturing frame: $e',
        name: 'FlatWizardService',
        level: 1000,
        error: e,
      );
      return FlatFrameCapture(
        outcome: FlatFrameOutcome.failed,
        error: e.toString(),
      );
    }
  }

  /// Full outcome of the most recent [captureTestFrame] call on the REAL
  /// capture path. The calibration solvers read this AFTER awaiting
  /// [captureTestFrame] so they can distinguish a timeout (halt the run) or a
  /// cancel from an ordinary off-target measurement — WITHOUT widening
  /// [captureTestFrame]'s `double?` contract, which stays deliberately simple so
  /// tests can inject ADU samples by overriding it. A [captureTestFrame]
  /// override that does not touch this field (a test double) leaves it null, and
  /// the solver then treats a non-null ADU as an ordinary completed measurement.
  FlatFrameCapture? _lastTestFrameOutcome;

  /// Capture a single test frame and return its mean ADU.
  ///
  /// Thin compatibility wrapper over [exposeAndAwait]: returns the mean ADU on
  /// a completed capture, or null on any non-completed outcome (failure,
  /// cancellation, timeout). Waits for the authoritative completion event
  /// rather than a fixed delay. The FULL outcome (needed to tell a timeout from
  /// a plain failure) is recorded in [_lastTestFrameOutcome]. This is the single
  /// overridable capture seam the calibration solvers route through, so a test
  /// double can inject ADU samples without reimplementing the event plumbing.
  Future<double?> captureTestFrame({
    required String deviceId,
    required double exposureTime,
    int? gain,
    int? offset,
    String? filterName,
    int? filterPosition,
    String? filterWheelDeviceId,
    int binX = 1,
    int binY = 1,
    FlatCancelToken? cancelToken,
    Duration abortSettleTimeout = const Duration(seconds: 10),
    Duration? overallTimeout,
  }) async {
    final capture = await exposeAndAwait(
      deviceId: deviceId,
      exposureTime: exposureTime,
      gain: gain,
      offset: offset,
      filterName: filterName,
      filterPosition: filterPosition,
      filterWheelDeviceId: filterWheelDeviceId,
      binX: binX,
      binY: binY,
      cancelToken: cancelToken,
      abortSettleTimeout: abortSettleTimeout,
      overallTimeout: overallTimeout,
    );
    _lastTestFrameOutcome = capture;
    return capture.adu;
  }

  /// Run iterative calibration to find optimal exposure for target ADU
  ///
  /// Uses binary search-like algorithm with adaptive step sizing:
  /// 1. Start with initial exposure estimate
  /// 2. Capture test frame and measure ADU
  /// 3. Calculate next exposure using proportional adjustment
  /// 4. Repeat until within tolerance or max iterations reached
  ///
  /// Returns [FlatResult] with optimal exposure and final ADU
  Future<FlatResult> calibrateFilter({
    required String deviceId,
    required String filter,
    int? gain,
    int? offset,
    required double targetAdu,
    required double tolerance,
    required double minExposure,
    required double maxExposure,
    int maxIterations = 10,
    int binX = 1,
    int binY = 1,
    FlatCancelToken? cancelToken,
    Duration abortSettleTimeout = const Duration(seconds: 10),
    Duration? overallTimeout,
    void Function(int iteration, double exposure, double adu)? onProgress,
  }) async {
    // Start with midpoint exposure
    double exposure = math.sqrt(minExposure * maxExposure);
    double? lastAdu;
    int iteration = 0;

    developer.log(
      'FlatWizardService: Starting calibration for filter "$filter"\n'
      '  Target ADU: ${targetAdu.toStringAsFixed(0)}\n'
      '  Tolerance: ±${tolerance.toStringAsFixed(1)}%\n'
      '  Exposure range: ${minExposure.toStringAsFixed(3)}s - ${maxExposure.toStringAsFixed(3)}s',
      name: 'FlatWizardService',
      level: 800,
    );

    for (iteration = 1; iteration <= maxIterations; iteration++) {
      // Cooperative cancel BETWEEN iterations: a cancel requested during the
      // previous exposure (or the settle wait) stops the solver immediately
      // instead of running another test frame.
      if (cancelToken?.isCancelled ?? false) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          cancelled: true,
          iterations: iteration - 1,
          errorMessage: 'Cancelled',
        );
      }

      developer.log(
        'FlatWizardService: Iteration $iteration/$maxIterations - '
        'Testing exposure: ${exposure.toStringAsFixed(3)}s',
        name: 'FlatWizardService',
        level: 800,
      );

      // Measure through the overridable [captureTestFrame] seam (so tests can
      // inject ADU samples) then read the FULL outcome, so a cancel that lands
      // mid-exposure aborts the hardware and a timeout is distinguishable from a
      // plain capture failure.
      final adu = await captureTestFrame(
        deviceId: deviceId,
        exposureTime: exposure,
        gain: gain,
        offset: offset,
        filterName: filter,
        binX: binX,
        binY: binY,
        cancelToken: cancelToken,
        abortSettleTimeout: abortSettleTimeout,
        overallTimeout: overallTimeout,
      );
      final outcome = _lastTestFrameOutcome;
      _lastTestFrameOutcome = null;

      if (outcome != null && outcome.isCancelled) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          cancelled: true,
          iterations: iteration,
          errorMessage: 'Cancelled',
        );
      }
      if (outcome != null && outcome.isTimedOut) {
        // A timeout means the exposure pipeline is misbehaving; the run must
        // STOP (fail-safe) rather than risk overlapping the next exposure.
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          iterations: iteration,
          haltRun: true,
          cameraStateUnknown: !outcome.cameraQuiescent,
          errorMessage: outcome.error ?? 'Exposure timed out',
        );
      }
      if (adu == null) {
        // A terminal failure/null image (or a pre-start cancel). The camera IS
        // settled, so the run may continue to the next filter (this filter is
        // marked failed). The exact cause is logged in [exposeAndAwait].
        if (cancelToken?.isCancelled ?? false) {
          return FlatResult(
            filter: filter,
            exposure: exposure,
            adu: lastAdu ?? 0,
            success: false,
            cancelled: true,
            iterations: iteration,
            errorMessage: 'Cancelled',
          );
        }
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          iterations: iteration,
          errorMessage: 'Failed to capture test frame',
        );
      }

      lastAdu = adu;
      developer.log(
        'FlatWizardService: Measured ADU: ${adu.toStringAsFixed(0)}',
        name: 'FlatWizardService',
        level: 800,
      );

      // Notify progress callback
      onProgress?.call(iteration, exposure, adu);

      // Check if within tolerance
      final error = ((adu - targetAdu).abs() / targetAdu) * 100;
      if (error <= tolerance) {
        developer.log(
          'FlatWizardService: SUCCESS! Found optimal exposure: '
          '${exposure.toStringAsFixed(3)}s (ADU: ${adu.toStringAsFixed(0)}, '
          'error: ${error.toStringAsFixed(2)}%)',
          name: 'FlatWizardService',
          level: 800,
        );
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: true,
          iterations: iteration,
        );
      }

      // Calculate next exposure
      final nextExposure = calculateNextExposure(
        currentExposure: exposure,
        currentAdu: adu,
        targetAdu: targetAdu,
        minExposure: minExposure,
        maxExposure: maxExposure,
      );

      // Check for convergence (exposure not changing significantly)
      if ((nextExposure - exposure).abs() < 0.001) {
        developer.log(
          'FlatWizardService: Converged at exposure: ${exposure.toStringAsFixed(3)}s '
          '(ADU: ${adu.toStringAsFixed(0)})',
          name: 'FlatWizardService',
          level: 800,
        );
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: error <= tolerance * 2, // Accept if within 2x tolerance
          iterations: iteration,
        );
      }

      exposure = nextExposure;
    }

    // Max iterations reached
    developer.log(
      'FlatWizardService: Max iterations reached. Best result: '
      '${exposure.toStringAsFixed(3)}s (ADU: ${lastAdu?.toStringAsFixed(0) ?? "N/A"})',
      name: 'FlatWizardService',
      level: 900,
    );
    return FlatResult(
      filter: filter,
      exposure: exposure,
      adu: lastAdu ?? 0,
      success: false,
      iterations: maxIterations,
      errorMessage: 'Max iterations reached without convergence',
    );
  }

  /// Calibrate filter with rate tracking for sky flats
  ///
  /// Uses predictive exposure calculation based on sky brightness rate
  Future<FlatResult> calibrateFilterWithRateTracking({
    required String deviceId,
    required String filter,
    int? gain,
    int? offset,
    required double targetAdu,
    required double tolerance,
    required double minExposure,
    required double maxExposure,
    required SkyBrightnessTracker brightnessTracker,
    double? historicalExposure,
    int maxIterations = 3, // Fewer iterations for sky flats (speed matters)
    int binX = 1,
    int binY = 1,
    FlatCancelToken? cancelToken,
    Duration abortSettleTimeout = const Duration(seconds: 10),
    Duration? overallTimeout,
    void Function(int iteration, double exposure, double adu, String status)?
    onProgress,
  }) async {
    // Get starting exposure
    double exposure = FlatExposureCalculator.getStartingExposure(
      historicalExposure: historicalExposure,
      minExposure: minExposure,
      maxExposure: maxExposure,
      currentSkyAduRate: brightnessTracker.calculateRate(),
    );

    double? lastAdu;
    int iteration = 0;

    for (iteration = 1; iteration <= maxIterations; iteration++) {
      if (cancelToken?.isCancelled ?? false) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          cancelled: true,
          iterations: iteration - 1,
          errorMessage: 'Cancelled',
        );
      }

      onProgress?.call(iteration, exposure, lastAdu ?? 0, 'Testing exposure');

      // Measure through the overridable [captureTestFrame] seam, then read the
      // FULL outcome (cancel-aware; a timeout halts the whole run fail-safe).
      final adu = await captureTestFrame(
        deviceId: deviceId,
        exposureTime: exposure,
        gain: gain,
        offset: offset,
        filterName: filter,
        binX: binX,
        binY: binY,
        cancelToken: cancelToken,
        abortSettleTimeout: abortSettleTimeout,
        overallTimeout: overallTimeout,
      );
      final outcome = _lastTestFrameOutcome;
      _lastTestFrameOutcome = null;

      if (outcome != null && outcome.isCancelled) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          cancelled: true,
          iterations: iteration,
          errorMessage: 'Cancelled',
        );
      }
      if (outcome != null && outcome.isTimedOut) {
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          iterations: iteration,
          haltRun: true,
          cameraStateUnknown: !outcome.cameraQuiescent,
          errorMessage: outcome.error ?? 'Exposure timed out',
        );
      }
      if (adu == null) {
        if (cancelToken?.isCancelled ?? false) {
          return FlatResult(
            filter: filter,
            exposure: exposure,
            adu: lastAdu ?? 0,
            success: false,
            cancelled: true,
            iterations: iteration,
            errorMessage: 'Cancelled',
          );
        }
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: lastAdu ?? 0,
          success: false,
          iterations: iteration,
          errorMessage: 'Failed to capture test frame',
        );
      }

      lastAdu = adu;

      // Update brightness tracker
      brightnessTracker.addSample(
        adu: adu,
        exposureTime: exposure,
        timestamp: DateTime.now(),
      );

      // Check if within tolerance
      final toleranceAdu = targetAdu * tolerance / 100.0;
      if ((adu - targetAdu).abs() <= toleranceAdu) {
        onProgress?.call(iteration, exposure, adu, 'On target');
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: true,
          iterations: iteration,
        );
      }

      // Calculate next exposure using rate-aware prediction
      final predictedExposure = brightnessTracker.calculateOptimalExposure(
        targetAdu: targetAdu,
        minExposure: minExposure,
        maxExposure: maxExposure,
      );

      if (predictedExposure != null) {
        exposure = predictedExposure;
      } else {
        // Fall back to the single canonical proportional-adjustment engine
        // (the same [calculateNextExposure] that drives the standalone wizard
        // screen and the headless /api/flat-wizard handlers via
        // [calibrateFilter]). Previously this used a second, divergent copy in
        // FlatExposureCalculator; collapsed to one source of truth.
        exposure = calculateNextExposure(
          currentExposure: exposure,
          currentAdu: adu,
          targetAdu: targetAdu,
          minExposure: minExposure,
          maxExposure: maxExposure,
        );
      }

      // Check limits
      final limitStatus = FlatExposureCalculator.checkLimits(
        exposure: exposure,
        measuredAdu: adu,
        targetAdu: targetAdu,
        minExposure: minExposure,
        maxExposure: maxExposure,
        tolerancePercent: tolerance,
      );

      if (limitStatus == ExposureLimitStatus.maxExposureReached) {
        onProgress?.call(iteration, exposure, adu, 'Max exposure reached');
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: false,
          iterations: iteration,
          errorMessage: 'Max exposure reached but still under target',
        );
      }

      if (limitStatus == ExposureLimitStatus.minExposureReached) {
        onProgress?.call(iteration, exposure, adu, 'Min exposure reached');
        return FlatResult(
          filter: filter,
          exposure: exposure,
          adu: adu,
          success: false,
          iterations: iteration,
          errorMessage: 'Min exposure reached but still over target',
        );
      }
    }

    // Return best effort
    return FlatResult(
      filter: filter,
      exposure: exposure,
      adu: lastAdu ?? 0,
      success: false,
      iterations: maxIterations,
      errorMessage: 'Did not converge within $maxIterations iterations',
    );
  }

  /// Calibrate multiple filters in sequence
  ///
  /// Runs calibration for each filter and returns list of results
  Future<List<FlatResult>> calibrateMultipleFilters({
    required String deviceId,
    required List<String> filters,
    int? gain,
    int? offset,
    required double targetAdu,
    required double tolerance,
    required double minExposure,
    required double maxExposure,
    int maxIterations = 10,
    int binX = 1,
    int binY = 1,
    FlatCancelToken? cancelToken,
    Duration abortSettleTimeout = const Duration(seconds: 10),
    Duration? overallTimeout,
    void Function(String filter, int iteration, double exposure, double adu)?
    onProgress,
    void Function(String filter, FlatResult result)? onFilterComplete,
  }) async {
    final results = <FlatResult>[];

    for (final filter in filters) {
      if (cancelToken?.isCancelled ?? false) break;

      developer.log(
        'FlatWizardService: Starting calibration for filter: $filter',
        name: 'FlatWizardService',
        level: 800,
      );

      final result = await calibrateFilter(
        deviceId: deviceId,
        filter: filter,
        gain: gain,
        offset: offset,
        targetAdu: targetAdu,
        tolerance: tolerance,
        minExposure: minExposure,
        maxExposure: maxExposure,
        maxIterations: maxIterations,
        binX: binX,
        binY: binY,
        cancelToken: cancelToken,
        abortSettleTimeout: abortSettleTimeout,
        overallTimeout: overallTimeout,
        onProgress: (iteration, exposure, adu) {
          onProgress?.call(filter, iteration, exposure, adu);
        },
      );

      results.add(result);
      onFilterComplete?.call(filter, result);

      if (result.cancelled) break;
      // Fail-safe: a timeout/uncertain-camera result stops the whole batch, not
      // just this filter.
      if (result.haltRun) break;

      if (!result.success) {
        developer.log(
          'FlatWizardService: Warning - Calibration failed for filter: $filter',
          name: 'FlatWizardService',
          level: 900,
        );
      }
    }

    return results;
  }

  /// Generate sequence nodes from flat calibration results
  ///
  /// Creates ExposureNode for each successful calibration with specified frame count
  /// Nodes are created as independent flat capture sequences
  List<SequenceNode> generateFlatSequence({
    required List<FlatResult> calibrations,
    required int framesPerFilter,
    int binX = 1,
    int binY = 1,
    int? gain,
    int? offset,
    bool onlySuccessful = true,
  }) {
    final nodes = <SequenceNode>[];
    int orderIndex = 0;

    for (final cal in calibrations) {
      // Skip failed calibrations if requested
      if (onlySuccessful && !cal.success) {
        developer.log(
          'FlatWizardService: Skipping failed calibration for filter: ${cal.filter}',
          name: 'FlatWizardService',
          level: 800,
        );
        continue;
      }

      // Create exposure node for this filter
      final node = ExposureNode(
        id: const Uuid().v4(),
        name: 'Flat ${cal.filter}',
        durationSecs: cal.exposure,
        count: framesPerFilter,
        filter: cal.filter,
        gain: gain,
        offset: offset,
        binning: _binningFromInts(binX, binY),
        frameType: FrameType.flat,
        orderIndex: orderIndex++,
        isEnabled: true,
      );

      nodes.add(node);
      developer.log(
        'FlatWizardService: Generated sequence node - '
        'Filter: ${cal.filter}, Exposure: ${cal.exposure.toStringAsFixed(3)}s, '
        'Count: $framesPerFilter',
        name: 'FlatWizardService',
        level: 800,
      );
    }

    return nodes;
  }

  /// Generate a complete flat sequence with optional sequence wrapper
  ///
  /// Creates InstructionSetNode containing all flat exposure nodes
  /// Returns a complete Sequence ready to be saved or executed
  Sequence generateCompleteSequence({
    required List<FlatResult> calibrations,
    required int framesPerFilter,
    String sequenceName = 'Flat Frame Sequence',
    String? description,
    int binX = 1,
    int binY = 1,
    int? gain,
    int? offset,
    bool onlySuccessful = true,
  }) {
    // Generate flat capture nodes
    final captureNodes = generateFlatSequence(
      calibrations: calibrations,
      framesPerFilter: framesPerFilter,
      binX: binX,
      binY: binY,
      gain: gain,
      offset: offset,
      onlySuccessful: onlySuccessful,
    );

    // Create root instruction set node
    final rootId = const Uuid().v4();
    final rootNode = InstructionSetNode(
      id: rootId,
      name: 'Flat Frames',
      childIds: captureNodes.map((n) => n.id).toList(),
      orderIndex: 0,
      isEnabled: true,
    );

    // Update child nodes with parent reference
    final updatedNodes = <String, SequenceNode>{rootId: rootNode};
    for (int i = 0; i < captureNodes.length; i++) {
      final child = captureNodes[i];
      updatedNodes[child.id] = child.copyWith(parentId: rootId, orderIndex: i);
    }

    // Build description
    final desc =
        description ??
        'Flat frame sequence generated from wizard\n'
            'Filters: ${calibrations.where((c) => !onlySuccessful || c.success).map((c) => c.filter).join(", ")}\n'
            'Frames per filter: $framesPerFilter\n'
            'Generated: ${DateTime.now().toIso8601String()}';

    return Sequence(
      id: const Uuid().v4(),
      name: sequenceName,
      description: desc,
      nodes: updatedNodes,
      rootNodeId: rootId,
      isTemplate: false,
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );
  }

  /// Quick calibration with intelligent defaults
  ///
  /// Simplified calibration that uses standard settings for most scenarios
  Future<FlatResult> quickCalibrate({
    required String deviceId,
    required String filter,
    int? gain,
    int? offset,
    double targetAdu = 30000,
    double tolerancePercent = 10.0,
    int binX = 1,
    int binY = 1,
  }) async {
    // Exposure bounds and iteration count come from the
    // service's settings-derived fields rather than hardcoded literals so the
    // user can tune them via the flat wizard global-settings panel.
    return calibrateFilter(
      deviceId: deviceId,
      filter: filter,
      gain: gain,
      offset: offset,
      targetAdu: targetAdu,
      tolerance: tolerancePercent,
      minExposure: quickMinExposure,
      maxExposure: quickMaxExposure,
      maxIterations: defaultMaxIterations,
      binX: binX,
      binY: binY,
    );
  }

  /// Default minimum exposure for [quickCalibrate]. Was hardcoded 0.001s.
  /// Promoted to a service field so user settings can override it.
  final double quickMinExposure;

  /// Default maximum exposure for [quickCalibrate]. Was hardcoded 30.0s.
  final double quickMaxExposure;
}

/// Helper function to convert bin values to BinningMode
BinningMode _binningFromInts(int x, int y) {
  if (x == 1 && y == 1) return BinningMode.one;
  if (x == 2 && y == 2) return BinningMode.two;
  if (x == 3 && y == 3) return BinningMode.three;
  if (x == 4 && y == 4) return BinningMode.four;
  return BinningMode.one;
}

/// Provider for FlatWizardService.
///
/// Re-watches `flatWizardProvider` so a
/// settings change (min/max exposure, image download timeout, max iterations)
/// rebuilds the service with the new values instead of being silently ignored.
final flatWizardServiceProvider = Provider<FlatWizardService>((ref) {
  final backend = ref.watch(backendProvider.select((b) => b));
  final settings = ref.watch(
    flatWizardProvider.select((s) => s.globalSettings),
  );
  return FlatWizardService.fromSettings(backend, settings);
});
