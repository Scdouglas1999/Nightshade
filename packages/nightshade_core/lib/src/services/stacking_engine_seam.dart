import 'dart:typed_data';

import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;

import 'live_stacking_service.dart';

/// A linear, unstretched FITS read: the raw sensor pixels plus dimensions.
///
/// Mirrors the subset of [bridge.FitsLinearReadResult] the Stack-and-Share
/// orchestrator consumes, so the [StackingEngineSeam] exposes a plain value
/// type rather than leaking the generated bridge class through the seam (which
/// keeps the seam trivially fakeable in tests).
class LinearFrameData {
  /// Frame width in pixels.
  final int width;

  /// Frame height in pixels.
  final int height;

  /// Linear (unstretched) sensor samples, `width * height` long. BZERO/BSCALE
  /// have already been applied by the FITS reader.
  final List<double> linearData;

  const LinearFrameData({
    required this.width,
    required this.height,
    required this.linearData,
  });
}

/// Injectable seam over the process-wide native stacking engine and the raw
/// FITS / stretch bridge calls the [StackAndShareService] orchestrator depends
/// on.
///
/// **Why this exists.** The native stacker is a process-wide singleton reached
/// through free functions on the generated bridge (`apiStackingIsActive`,
/// `apiStackingStart`, `apiStackingStop`, …). Calling those statics directly
/// from the orchestrator made the single most logic-dense piece of the
/// Stack-and-Share feature — the busy guard, the reference-first ordering, the
/// per-frame accept/reject accounting, and the always-release `finally` — only
/// exercisable with the Rust dynamic library loaded, i.e. effectively untested.
///
/// This abstraction follows the same injection pattern the sibling
/// `StackShareExportService` uses for its PNG/JPEG save functions: the default
/// implementation ([BridgeStackingEngineSeam]) forwards to the bridge so
/// production behaviour is unchanged, and tests substitute a fake so the
/// orchestrator body runs end-to-end without native code.
///
/// The frame-adding / result-fetching calls already flow through the injectable
/// [LiveStackingService] provider, so this seam deliberately covers only the
/// calls that were *not* already wrapped: the active check, the two start
/// paths, the auto-stretch, the raw FITS read, and the stop.
abstract class StackingEngineSeam {
  /// Whether the native stacker singleton currently holds a session.
  ///
  /// True while a live EAA session, a sequencer `LiveStackingNode`, or another
  /// in-flight Stack-and-Share run owns the engine. The orchestrator refuses to
  /// start when this is true so it never clobbers an active session.
  bool isActive();

  /// Start the stack from a reference frame loaded by the engine's own native
  /// FITS/XISF loader (the calibration-off path — no lossy float→u16
  /// round-trip).
  Future<LiveStackingStats> startFromFile({
    required String referenceImagePath,
    required LiveStackingConfig config,
  });

  /// Start the stack from already-calibrated in-memory u16 pixels (the
  /// calibration-on path).
  Future<LiveStackingStats> startFromData({
    required int width,
    required int height,
    required List<int> data,
    required LiveStackingConfig config,
  });

  /// Read a frame's unstretched linear pixels (science read path) so the
  /// integration works on genuine sensor values rather than display bytes.
  Future<LinearFrameData> readLinearFrame(String filePath);

  /// Auto-stretch an integrated u16 buffer into an 8-bit RGBA display buffer
  /// via the engine's screen-transfer (STF) path.
  Uint8List autoStretch({
    required int width,
    required int height,
    required List<int> data,
  });

  /// Stop the stacker and release the singleton.
  ///
  /// Unlike the engine's `reset` (which clears accumulated data but leaves the
  /// singleton allocated, so [isActive] keeps returning true), `stop` frees the
  /// guard so a subsequent [isActive] returns false and the next consumer — a
  /// later Stack-and-Share run or a live EAA session — can acquire the engine.
  Future<void> stop();
}

/// Production [StackingEngineSeam] that forwards to the native bridge.
class BridgeStackingEngineSeam implements StackingEngineSeam {
  const BridgeStackingEngineSeam();

  @override
  bool isActive() => bridge.apiStackingIsActive();

  @override
  Future<LiveStackingStats> startFromFile({
    required String referenceImagePath,
    required LiveStackingConfig config,
  }) async {
    final stats = await bridge.apiStackingStart(
      referenceImagePath: referenceImagePath,
      config: _bridgeConfig(config),
    );
    return _toStats(stats);
  }

  @override
  Future<LiveStackingStats> startFromData({
    required int width,
    required int height,
    required List<int> data,
    required LiveStackingConfig config,
  }) async {
    final stats = await bridge.apiStackingStartFromData(
      width: width,
      height: height,
      data: data,
      config: _bridgeConfig(config),
    );
    return _toStats(stats);
  }

  @override
  Future<LinearFrameData> readLinearFrame(String filePath) async {
    final read = await bridge.apiReadFitsLinearData(filePath: filePath);
    return LinearFrameData(
      width: read.width,
      height: read.height,
      linearData: read.linearData,
    );
  }

  @override
  Uint8List autoStretch({
    required int width,
    required int height,
    required List<int> data,
  }) {
    return bridge.apiAutoStretchImage(width: width, height: height, data: data);
  }

  @override
  Future<void> stop() => bridge.apiStackingStop();

  bridge.ApiLiveStackingConfig _bridgeConfig(LiveStackingConfig config) {
    return bridge.ApiLiveStackingConfig(
      sigmaClipEnabled: config.sigmaClipEnabled,
      sigmaClipThreshold: config.sigmaClipThreshold,
      maxMatchStars: config.maxMatchStars,
      matchRadiusPx: config.matchRadiusPx,
      matchFluxTolerance: config.matchFluxTolerance,
      minMatchedPairs: config.minMatchedPairs,
    );
  }

  LiveStackingStats _toStats(bridge.ApiLiveStackingStats s) {
    return LiveStackingStats(
      stackedFrameCount: s.stackedFrameCount,
      totalFramesAttempted: s.totalFramesAttempted,
      rejectedAlignmentFailures: s.rejectedAlignmentFailures,
      avgMatchedPairs: s.avgMatchedPairs,
      avgAlignmentResidual: s.avgAlignmentResidual,
      totalSigmaRejectedPixels: s.totalSigmaRejectedPixels.toInt(),
    );
  }
}
