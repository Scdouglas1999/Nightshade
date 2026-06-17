part of '../network_backend.dart';

/// Remote (REST) client for the host's live-stacking control surface.
///
/// The stacking engine runs on the appliance; these calls drive it over
/// `/api/stacking/*`. The stacked preview comes back as a raw little-endian
/// u16 buffer ([stackingGetResult]); dimensions + stats arrive as JSON so the
/// buffer can be decoded without a header round-trip.
mixin _NetworkBackendStackingOperations on _NetworkBackendTransport {
  Map<String, Object?> _stackingConfigToJson(LiveStackingConfig c) => {
    'sigmaClipEnabled': c.sigmaClipEnabled,
    'sigmaClipThreshold': c.sigmaClipThreshold,
    'maxMatchStars': c.maxMatchStars,
    'matchRadiusPx': c.matchRadiusPx,
    'matchFluxTolerance': c.matchFluxTolerance,
    'minMatchedPairs': c.minMatchedPairs,
    'sensorMode': c.sensorMode,
    if (c.bayerPattern != null) 'bayerPattern': c.bayerPattern,
    'demosaicQuality': c.demosaicQuality,
  };

  LiveStackingStats _stackingStatsFromJson(Map<String, dynamic>? json) {
    if (json == null) return const LiveStackingStats();
    return LiveStackingStats(
      stackedFrameCount: (json['stackedFrameCount'] as num?)?.toInt() ?? 0,
      totalFramesAttempted:
          (json['totalFramesAttempted'] as num?)?.toInt() ?? 0,
      rejectedAlignmentFailures:
          (json['rejectedAlignmentFailures'] as num?)?.toInt() ?? 0,
      avgMatchedPairs: (json['avgMatchedPairs'] as num?)?.toDouble() ?? 0.0,
      avgAlignmentResidual:
          (json['avgAlignmentResidual'] as num?)?.toDouble() ?? 0.0,
      totalSigmaRejectedPixels:
          (json['totalSigmaRejectedPixels'] as num?)?.toInt() ?? 0,
    );
  }

  /// Start (or arm) live stacking on the host. With [referencePath] (a host
  /// path) the stack starts immediately from that frame; without it the host
  /// arms and the next captured frame becomes the reference.
  Future<LiveStackingStats> stackingStart({
    String? referencePath,
    LiveStackingConfig config = const LiveStackingConfig(),
  }) async {
    final response = await _post('stacking/start', {
      'config': _stackingConfigToJson(config),
      if (referencePath != null) 'referencePath': referencePath,
    });
    return _stackingStatsFromJson(response['stats'] as Map<String, dynamic>?);
  }

  /// Push the host config to apply on the next start.
  Future<void> stackingUpdateConfig(LiveStackingConfig config) async {
    await _post('stacking/config', {'config': _stackingConfigToJson(config)});
  }

  /// Add a host-side frame to the running stack and return the refreshed
  /// result (dimensions + stats + stacked pixels).
  Future<LiveStackingResult> stackingAddFrame(String imagePath) async {
    await _post('stacking/add-frame', {'imagePath': imagePath});
    return stackingGetResult();
  }

  /// Current accumulation stats only (cheap; no pixels).
  Future<LiveStackingStats> stackingGetStats() async {
    final response = await _get('stacking/stats');
    return _stackingStatsFromJson(response['stats'] as Map<String, dynamic>?);
  }

  /// Fetch the current stacked result: dimensions + stats (JSON) plus the raw
  /// little-endian u16 pixel buffer (binary).
  Future<LiveStackingResult> stackingGetResult() async {
    final meta = await _get('stacking/result');
    final width = (meta['width'] as num).toInt();
    final height = (meta['height'] as num).toInt();
    final channels = (meta['channels'] as num?)?.toInt() ?? 1;
    final stats = _stackingStatsFromJson(
      meta['stats'] as Map<String, dynamic>?,
    );

    final bytes = await _downloadBytes('stacking/preview');
    // Decode little-endian u16 samples. The host writes native (LE) order and
    // tags the response `x-stack-endian: little`.
    final byteData = ByteData.sublistView(bytes);
    final sampleCount = bytes.lengthInBytes ~/ 2;
    final samples = Uint16List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = byteData.getUint16(i * 2, Endian.little);
    }

    return LiveStackingResult(
      width: width,
      height: height,
      channels: channels,
      data: samples,
      stats: stats,
    );
  }

  /// Clear the accumulation (host stays armed).
  Future<void> stackingReset() async {
    await _post('stacking/reset', const {});
  }

  /// Stop the stacker and disarm host auto-feed.
  Future<void> stackingStop() async {
    await _post('stacking/stop', const {});
  }

  /// Liveness + counters.
  Future<({bool active, int frameCount})> stackingStatus() async {
    final response = await _get('stacking/status');
    return (
      active: response['active'] as bool? ?? false,
      frameCount: (response['frameCount'] as num?)?.toInt() ?? 0,
    );
  }
}
