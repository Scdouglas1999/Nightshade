/// Tracks sky brightness changes during twilight for predictive exposure calculation
class SkyBrightnessTracker {
  final List<_BrightnessSample> _samples = [];

  /// Maximum age of samples to consider (5 minutes)
  static const _maxSampleAge = Duration(minutes: 5);

  /// Minimum samples needed for rate calculation
  static const _minSamples = 2;

  /// Add a brightness measurement
  void addSample({
    required double adu,
    required double exposureTime,
    required DateTime timestamp,
  }) {
    // Normalize ADU to ADU per second for comparison
    final aduPerSecond = adu / exposureTime;

    _samples.add(_BrightnessSample(
      aduPerSecond: aduPerSecond,
      timestamp: timestamp,
    ));

    // Prune old samples
    _pruneOldSamples();
  }

  void _pruneOldSamples() {
    final cutoff = DateTime.now().subtract(_maxSampleAge);
    _samples.removeWhere((s) => s.timestamp.isBefore(cutoff));
  }

  /// Calculate current rate of brightness change (ADU/s per second)
  /// Positive = brightening (dawn), Negative = darkening (dusk)
  double? calculateRate() {
    if (_samples.length < _minSamples) return null;

    // Use linear regression for rate calculation
    final n = _samples.length;
    final now = DateTime.now();

    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (final sample in _samples) {
      // X = seconds ago (negative so older = smaller)
      final x = sample.timestamp.difference(now).inMilliseconds / 1000.0;
      final y = sample.aduPerSecond;

      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    final denominator = n * sumX2 - sumX * sumX;
    if (denominator.abs() < 0.0001) return null;

    // Slope = rate of change
    final slope = (n * sumXY - sumX * sumY) / denominator;

    return slope;
  }

  /// Predict ADU at a future time given current conditions
  double? predictAdu({
    required double exposureTime,
    required Duration futureOffset,
  }) {
    if (_samples.isEmpty) return null;

    final rate = calculateRate();
    final currentAduPerSec = _samples.last.aduPerSecond;

    if (rate == null) {
      // No rate info, just use current value
      return currentAduPerSec * exposureTime;
    }

    // Account for exposure duration (average over exposure period)
    final futureSeconds = futureOffset.inMilliseconds / 1000.0;
    final exposureMidpoint = futureSeconds + (exposureTime / 2);
    final midpointAduPerSec = currentAduPerSec + (rate * exposureMidpoint);

    return midpointAduPerSec * exposureTime;
  }

  /// Calculate optimal exposure to achieve target ADU
  double? calculateOptimalExposure({
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
  }) {
    if (_samples.isEmpty) return null;

    final rate = calculateRate();
    final currentAduPerSec = _samples.last.aduPerSecond;

    if (currentAduPerSec <= 0) return null;

    // Simple case: no rate change
    if (rate == null || rate.abs() < 0.001) {
      final exposure = targetAdu / currentAduPerSec;
      return exposure.clamp(minExposure, maxExposure);
    }

    // With rate change, solve iteratively
    // Start with naive estimate
    double exposure = targetAdu / currentAduPerSec;

    for (int i = 0; i < 5; i++) {
      final predictedAdu = predictAdu(
        exposureTime: exposure,
        futureOffset: Duration.zero,
      );

      if (predictedAdu == null || predictedAdu <= 0) break;

      // Adjust exposure
      final ratio = targetAdu / predictedAdu;
      exposure = (exposure * ratio).clamp(minExposure, maxExposure);

      // Check convergence
      if ((ratio - 1.0).abs() < 0.02) break;
    }

    return exposure.clamp(minExposure, maxExposure);
  }

  /// Whether sky is getting brighter (dawn) or darker (dusk)
  bool? isBrightening() {
    final rate = calculateRate();
    if (rate == null) return null;
    return rate > 0;
  }

  /// Get number of samples
  int get sampleCount => _samples.length;

  /// Clear all samples
  void clear() => _samples.clear();
}

class _BrightnessSample {
  final double aduPerSecond;
  final DateTime timestamp;

  _BrightnessSample({
    required this.aduPerSecond,
    required this.timestamp,
  });
}
