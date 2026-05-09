import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;

import '../services/logging_service.dart';

/// Configuration for the live stacking engine.
class LiveStackingConfig {
  /// Whether sigma clipping is enabled for pixel rejection.
  final bool sigmaClipEnabled;

  /// Sigma threshold for pixel rejection (e.g. 2.5 means reject > 2.5 sigma from mean).
  final double sigmaClipThreshold;

  /// Maximum number of stars to use for matching.
  final int maxMatchStars;

  /// Maximum distance in pixels for a star match to be valid.
  final double matchRadiusPx;

  /// Maximum flux ratio difference for a star match (0.0 to 1.0).
  final double matchFluxTolerance;

  /// Minimum number of matched star pairs required for alignment.
  final int minMatchedPairs;

  const LiveStackingConfig({
    this.sigmaClipEnabled = true,
    this.sigmaClipThreshold = 2.5,
    this.maxMatchStars = 100,
    this.matchRadiusPx = 50.0,
    this.matchFluxTolerance = 0.7,
    this.minMatchedPairs = 5,
  });

  LiveStackingConfig copyWith({
    bool? sigmaClipEnabled,
    double? sigmaClipThreshold,
    int? maxMatchStars,
    double? matchRadiusPx,
    double? matchFluxTolerance,
    int? minMatchedPairs,
  }) {
    return LiveStackingConfig(
      sigmaClipEnabled: sigmaClipEnabled ?? this.sigmaClipEnabled,
      sigmaClipThreshold: sigmaClipThreshold ?? this.sigmaClipThreshold,
      maxMatchStars: maxMatchStars ?? this.maxMatchStars,
      matchRadiusPx: matchRadiusPx ?? this.matchRadiusPx,
      matchFluxTolerance: matchFluxTolerance ?? this.matchFluxTolerance,
      minMatchedPairs: minMatchedPairs ?? this.minMatchedPairs,
    );
  }
}

/// Statistics about the current stacking session.
class LiveStackingStats {
  final int stackedFrameCount;
  final int totalFramesAttempted;
  final int rejectedAlignmentFailures;
  final double avgMatchedPairs;
  final double avgAlignmentResidual;
  final int totalSigmaRejectedPixels;

  const LiveStackingStats({
    this.stackedFrameCount = 0,
    this.totalFramesAttempted = 0,
    this.rejectedAlignmentFailures = 0,
    this.avgMatchedPairs = 0.0,
    this.avgAlignmentResidual = 0.0,
    this.totalSigmaRejectedPixels = 0,
  });
}

/// Result from adding a frame to the live stack.
class LiveStackingResult {
  final int width;
  final int height;
  final List<int> data;
  final LiveStackingStats stats;

  const LiveStackingResult({
    required this.width,
    required this.height,
    required this.data,
    required this.stats,
  });
}

/// Service that wraps the native live stacking bridge calls.
///
/// The live stacking engine aligns and averages incoming frames in real time,
/// providing a continuously improving preview for EAA and outreach.
class LiveStackingService {
  final Ref _ref;

  LiveStackingService(this._ref);

  LoggingService get _logger => _ref.read(loggingServiceProvider);

  /// Start live stacking with a reference image file.
  ///
  /// The reference frame defines the coordinate system; all subsequent frames
  /// are star-matched and aligned to it.
  Future<LiveStackingStats> startFromFile({
    required String referenceImagePath,
    LiveStackingConfig config = const LiveStackingConfig(),
  }) async {
    _logger.info('Starting live stacking from file: $referenceImagePath',
        source: 'LiveStackingService');

    final bridgeConfig = bridge.ApiLiveStackingConfig(
      sigmaClipEnabled: config.sigmaClipEnabled,
      sigmaClipThreshold: config.sigmaClipThreshold,
      maxMatchStars: config.maxMatchStars,
      matchRadiusPx: config.matchRadiusPx,
      matchFluxTolerance: config.matchFluxTolerance,
      minMatchedPairs: config.minMatchedPairs,
    );

    final result = await bridge.apiStackingStart(
      referenceImagePath: referenceImagePath,
      config: bridgeConfig,
    );

    return _convertStats(result);
  }

  /// Start live stacking from raw pixel data in memory.
  ///
  /// Used when the reference frame is already captured and available as u16 data.
  Future<LiveStackingStats> startFromData({
    required int width,
    required int height,
    required List<int> data,
    LiveStackingConfig config = const LiveStackingConfig(),
  }) async {
    _logger.info('Starting live stacking from data: ${width}x$height',
        source: 'LiveStackingService');

    final bridgeConfig = bridge.ApiLiveStackingConfig(
      sigmaClipEnabled: config.sigmaClipEnabled,
      sigmaClipThreshold: config.sigmaClipThreshold,
      maxMatchStars: config.maxMatchStars,
      matchRadiusPx: config.matchRadiusPx,
      matchFluxTolerance: config.matchFluxTolerance,
      minMatchedPairs: config.minMatchedPairs,
    );

    final result = await bridge.apiStackingStartFromData(
      width: width,
      height: height,
      data: data,
      config: bridgeConfig,
    );

    return _convertStats(result);
  }

  /// Add a frame to the stack from a file path.
  ///
  /// Returns the current stacked result (can be displayed as a preview).
  Future<LiveStackingResult> addFrameFromFile(String imagePath) async {
    _logger.info('Adding frame to stack: $imagePath',
        source: 'LiveStackingService');

    final result = await bridge.apiStackingAddFrame(imagePath: imagePath);
    return _convertResult(result);
  }

  /// Add a frame to the stack from raw pixel data.
  Future<LiveStackingResult> addFrameFromData({
    required int width,
    required int height,
    required List<int> data,
  }) async {
    final result = await bridge.apiStackingAddFrameFromData(
      width: width,
      height: height,
      data: data,
    );
    return _convertResult(result);
  }

  /// Get the current stacked result without adding a frame.
  Future<LiveStackingResult> getCurrentResult() async {
    final result = await bridge.apiStackingGetResult();
    return _convertResult(result);
  }

  /// Get the current stacking statistics.
  Future<LiveStackingStats> getStats() async {
    final result = await bridge.apiStackingGetStats();
    return _convertStats(result);
  }

  /// Reset the stacker, clearing accumulated data but keeping the reference.
  Future<void> reset() async {
    _logger.info('Resetting live stacker', source: 'LiveStackingService');
    await bridge.apiStackingReset();
  }

  /// Stop live stacking and release all resources.
  Future<void> stop() async {
    _logger.info('Stopping live stacker', source: 'LiveStackingService');
    await bridge.apiStackingStop();
  }

  /// Check if live stacking is currently active.
  bool get isActive => bridge.apiStackingIsActive();

  /// Get the current frame count.
  int get frameCount => bridge.apiStackingFrameCount();

  LiveStackingStats _convertStats(bridge.ApiLiveStackingStats bridgeStats) {
    return LiveStackingStats(
      stackedFrameCount: bridgeStats.stackedFrameCount,
      totalFramesAttempted: bridgeStats.totalFramesAttempted,
      rejectedAlignmentFailures: bridgeStats.rejectedAlignmentFailures,
      avgMatchedPairs: bridgeStats.avgMatchedPairs,
      avgAlignmentResidual: bridgeStats.avgAlignmentResidual,
      totalSigmaRejectedPixels: bridgeStats.totalSigmaRejectedPixels.toInt(),
    );
  }

  LiveStackingResult _convertResult(bridge.ApiLiveStackingResult bridgeResult) {
    return LiveStackingResult(
      width: bridgeResult.width,
      height: bridgeResult.height,
      data: bridgeResult.data,
      stats: _convertStats(bridgeResult.stats),
    );
  }
}

/// Provider for the LiveStackingService.
final liveStackingServiceProvider = Provider<LiveStackingService>((ref) {
  return LiveStackingService(ref);
});
