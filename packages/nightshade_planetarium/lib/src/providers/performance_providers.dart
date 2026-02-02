import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks frame timing for performance monitoring.
///
/// This class collects frame time measurements and calculates
/// rolling averages to help identify performance issues and
/// potentially enable auto-quality adjustment.
class PerformanceMonitor extends ChangeNotifier {
  final List<double> _frameTimings = [];
  final List<double> _buildTimings = [];
  final List<double> _rasterTimings = [];
  static const int _maxSamples = 30;
  bool _dirty = false;
  Timer? _notifyTimer;

  PerformanceMonitor({Duration notifyInterval = const Duration(milliseconds: 250)}) {
    _notifyTimer = Timer.periodic(notifyInterval, (_) {
      if (!_dirty) return;
      _dirty = false;
      notifyListeners();
    });
  }

  /// Record a frame time measurement in milliseconds.
  void recordFrameTime(double milliseconds) {
    _record(_frameTimings, milliseconds);
    _dirty = true;
  }

  /// Record build and raster timings in milliseconds.
  void recordFrameTimings({
    required double buildMs,
    required double rasterMs,
    required double totalMs,
  }) {
    _record(_buildTimings, buildMs);
    _record(_rasterTimings, rasterMs);
    _record(_frameTimings, totalMs);
    _dirty = true;
  }

  /// Get the average frame time over recent frames.
  double get averageFrameTime {
    if (_frameTimings.isEmpty) return 0;
    return _frameTimings.reduce((a, b) => a + b) / _frameTimings.length;
  }

  /// Get the average build (UI thread) time.
  double get averageBuildTime {
    if (_buildTimings.isEmpty) return 0;
    return _buildTimings.reduce((a, b) => a + b) / _buildTimings.length;
  }

  /// Get the average raster (GPU) time.
  double get averageRasterTime {
    if (_rasterTimings.isEmpty) return 0;
    return _rasterTimings.reduce((a, b) => a + b) / _rasterTimings.length;
  }

  /// Get the estimated frames per second based on average frame time.
  double get estimatedFps {
    final avg = averageFrameTime;
    return avg > 0 ? 1000 / avg : 60;
  }

  /// Get the minimum frame time (best performance).
  double get minFrameTime {
    if (_frameTimings.isEmpty) return 0;
    return _frameTimings.reduce((a, b) => a < b ? a : b);
  }

  /// Get the maximum frame time (worst performance).
  double get maxFrameTime {
    if (_frameTimings.isEmpty) return 0;
    return _frameTimings.reduce((a, b) => a > b ? a : b);
  }

  /// Get the number of samples currently collected.
  int get sampleCount => _frameTimings.length;

  /// Check if performance is below target (e.g., < 30 FPS).
  bool get isPerformanceLow => estimatedFps < 30;

  /// Check if performance is good (e.g., >= 55 FPS).
  bool get isPerformanceGood => estimatedFps >= 55;

  /// Clear all collected frame timings.
  void reset() {
    _frameTimings.clear();
    _buildTimings.clear();
    _rasterTimings.clear();
    _dirty = false;
    notifyListeners();
  }

  void _record(List<double> samples, double milliseconds) {
    samples.add(milliseconds);
    if (samples.length > _maxSamples) {
      samples.removeAt(0);
    }
  }

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    super.dispose();
  }
}

/// Provider for the performance monitor singleton.
final performanceMonitorProvider = ChangeNotifierProvider<PerformanceMonitor>((ref) {
  return PerformanceMonitor();
});

/// Provider for enabling/disabling auto quality adjustment.
///
/// When enabled, the system can automatically adjust render quality
/// based on measured frame rates to maintain smooth performance.
/// Enabled by default to ensure smooth experience on varied hardware.
final autoQualityEnabledProvider = StateProvider<bool>((ref) => true);

/// Computed provider that suggests a quality adjustment based on performance.
///
/// Returns:
/// - 1 if performance is good and quality could be increased
/// - 0 if performance is acceptable
/// - -1 if performance is low and quality should be decreased
final qualityAdjustmentSuggestionProvider = Provider<int>((ref) {
  final autoEnabled = ref.watch(autoQualityEnabledProvider);
  if (!autoEnabled) return 0;

  final monitor = ref.watch(performanceMonitorProvider);
  if (monitor.sampleCount < 10) return 0; // Not enough data

  if (monitor.isPerformanceLow) return -1;
  if (monitor.isPerformanceGood) return 1;
  return 0;
});
