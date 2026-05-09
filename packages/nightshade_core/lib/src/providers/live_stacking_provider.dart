import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/live_stacking_service.dart';
import '../services/logging_service.dart';

/// Current state of the live stacking session.
enum LiveStackingStatus {
  /// No stacking session is active.
  idle,

  /// Stacking is active and processing frames.
  running,

  /// An error occurred during stacking.
  error,
}

/// Full state of the live stacking session for UI consumption.
class LiveStackingState {
  final LiveStackingStatus status;
  final LiveStackingStats stats;
  final LiveStackingConfig config;

  /// The most recent stacked preview image as u16 pixel data.
  final Uint16List? previewData;
  final int previewWidth;
  final int previewHeight;

  /// Error message if status == error.
  final String? errorMessage;

  const LiveStackingState({
    this.status = LiveStackingStatus.idle,
    this.stats = const LiveStackingStats(),
    this.config = const LiveStackingConfig(),
    this.previewData,
    this.previewWidth = 0,
    this.previewHeight = 0,
    this.errorMessage,
  });

  LiveStackingState copyWith({
    LiveStackingStatus? status,
    LiveStackingStats? stats,
    LiveStackingConfig? config,
    Uint16List? previewData,
    int? previewWidth,
    int? previewHeight,
    String? errorMessage,
  }) {
    return LiveStackingState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      config: config ?? this.config,
      previewData: previewData ?? this.previewData,
      previewWidth: previewWidth ?? this.previewWidth,
      previewHeight: previewHeight ?? this.previewHeight,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// StateNotifier that manages the live stacking session.
///
/// Coordinates the LiveStackingService and exposes state to the UI.
class LiveStackingNotifier extends StateNotifier<LiveStackingState> {
  final Ref _ref;

  LiveStackingNotifier(this._ref) : super(const LiveStackingState());

  LoggingService get _logger => _ref.read(loggingServiceProvider);
  LiveStackingService get _service => _ref.read(liveStackingServiceProvider);

  /// Start a new live stacking session from a reference image file.
  Future<void> startFromFile(String referenceImagePath,
      {LiveStackingConfig? config}) async {
    final effectiveConfig = config ?? state.config;
    state = state.copyWith(
      status: LiveStackingStatus.running,
      config: effectiveConfig,
      errorMessage: null,
    );

    try {
      final stats = await _service.startFromFile(
        referenceImagePath: referenceImagePath,
        config: effectiveConfig,
      );

      if (!mounted) return;

      state = state.copyWith(stats: stats);
      _logger.info(
          'Live stacking started: ${stats.stackedFrameCount} frames',
          source: 'LiveStackingNotifier');
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: LiveStackingStatus.error,
        errorMessage: e.toString(),
      );
      _logger.error('Failed to start live stacking: $e',
          source: 'LiveStackingNotifier');
    }
  }

  /// Start a new live stacking session from raw pixel data.
  Future<void> startFromData({
    required int width,
    required int height,
    required List<int> data,
    LiveStackingConfig? config,
  }) async {
    final effectiveConfig = config ?? state.config;
    state = state.copyWith(
      status: LiveStackingStatus.running,
      config: effectiveConfig,
      errorMessage: null,
    );

    try {
      final stats = await _service.startFromData(
        width: width,
        height: height,
        data: data,
        config: effectiveConfig,
      );

      if (!mounted) return;

      state = state.copyWith(stats: stats);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        status: LiveStackingStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Add a frame to the stack from a file.
  Future<void> addFrameFromFile(String imagePath) async {
    if (state.status != LiveStackingStatus.running) return;

    try {
      final result = await _service.addFrameFromFile(imagePath);

      if (!mounted) return;

      state = state.copyWith(
        stats: result.stats,
        previewData: Uint16List.fromList(result.data),
        previewWidth: result.width,
        previewHeight: result.height,
      );
    } catch (e) {
      if (!mounted) return;
      // Frame rejection is not a fatal error -- log and continue
      _logger.warning('Frame rejected: $e', source: 'LiveStackingNotifier');
    }
  }

  /// Add a frame to the stack from raw pixel data.
  Future<void> addFrameFromData({
    required int width,
    required int height,
    required List<int> data,
  }) async {
    if (state.status != LiveStackingStatus.running) return;

    try {
      final result = await _service.addFrameFromData(
        width: width,
        height: height,
        data: data,
      );

      if (!mounted) return;

      state = state.copyWith(
        stats: result.stats,
        previewData: Uint16List.fromList(result.data),
        previewWidth: result.width,
        previewHeight: result.height,
      );
    } catch (e) {
      if (!mounted) return;
      _logger.warning('Frame rejected: $e', source: 'LiveStackingNotifier');
    }
  }

  /// Update the stacking configuration.
  void updateConfig(LiveStackingConfig config) {
    state = state.copyWith(config: config);
  }

  /// Reset the stack (clear accumulated data, keep reference).
  Future<void> reset() async {
    try {
      await _service.reset();
      if (!mounted) return;
      state = state.copyWith(
        stats: const LiveStackingStats(),
        previewData: null,
        previewWidth: 0,
        previewHeight: 0,
      );
    } catch (e) {
      _logger.error('Failed to reset stacker: $e',
          source: 'LiveStackingNotifier');
    }
  }

  /// Stop stacking and release resources.
  Future<void> stop() async {
    try {
      await _service.stop();
    } catch (e) {
      _logger.error('Failed to stop stacker: $e',
          source: 'LiveStackingNotifier');
    }

    if (!mounted) return;
    state = const LiveStackingState();
  }
}

/// Provider for the live stacking state.
final liveStackingProvider =
    StateNotifierProvider<LiveStackingNotifier, LiveStackingState>((ref) {
  return LiveStackingNotifier(ref);
});

/// Convenience provider for just the frame count.
final liveStackingFrameCountProvider = Provider<int>((ref) {
  return ref.watch(liveStackingProvider).stats.stackedFrameCount;
});

/// Convenience provider for whether stacking is active.
final liveStackingIsActiveProvider = Provider<bool>((ref) {
  return ref.watch(liveStackingProvider).status == LiveStackingStatus.running;
});
