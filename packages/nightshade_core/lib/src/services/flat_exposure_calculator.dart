import 'dart:math' as math;

/// Calculates optimal flat frame exposure with improved convergence
class FlatExposureCalculator {
  /// Convert histogram percentage to ADU (16-bit)
  static int histogramPercentToAdu(double percent) {
    return ((percent / 100.0) * 65535).round();
  }

  /// Convert ADU to histogram percentage
  static double aduToHistogramPercent(int adu) {
    return (adu / 65535.0) * 100.0;
  }

  /// Calculate next exposure with capped adjustments
  ///
  /// This prevents the wild jumps seen in naive proportional adjustment
  static double calculateNextExposure({
    required double currentExposure,
    required double currentAdu,
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
    double maxAdjustmentFactor = 2.0,
  }) {
    if (currentAdu <= 0) {
      // No signal, try middle of range
      return math.sqrt(minExposure * maxExposure);
    }

    // Calculate raw ratio
    final ratio = targetAdu / currentAdu;

    // Cap the adjustment to prevent wild jumps
    // Max 2x increase or 0.5x decrease per iteration
    final cappedRatio = ratio.clamp(
      1.0 / maxAdjustmentFactor,
      maxAdjustmentFactor,
    );

    // Apply logarithmic damping for smoother convergence
    // This reduces oscillation around the target
    final dampedRatio = _applyDamping(cappedRatio);

    final nextExposure = currentExposure * dampedRatio;

    return nextExposure.clamp(minExposure, maxExposure);
  }

  /// Apply damping to reduce oscillation
  static double _applyDamping(double ratio) {
    // For ratios close to 1.0, use as-is
    if (ratio >= 0.8 && ratio <= 1.25) {
      return ratio;
    }

    // For larger adjustments, dampen by 30%
    final deviation = ratio - 1.0;
    return 1.0 + (deviation * 0.7);
  }

  /// Binary search with early termination
  ///
  /// More efficient than proportional adjustment for stable light sources
  static double binarySearchExposure({
    required double lowExposure,
    required double highExposure,
    required double measuredAdu,
    required double targetAdu,
    required double tolerancePercent,
  }) {
    final toleranceAdu = targetAdu * tolerancePercent / 100.0;

    // Check if within tolerance
    if ((measuredAdu - targetAdu).abs() <= toleranceAdu) {
      // Already good, return current midpoint
      return (lowExposure + highExposure) / 2.0;
    }

    // Narrow the search range
    final midpoint = (lowExposure + highExposure) / 2.0;

    if (measuredAdu < targetAdu) {
      // Need more light, search upper half
      return (midpoint + highExposure) / 2.0;
    } else {
      // Too bright, search lower half
      return (lowExposure + midpoint) / 2.0;
    }
  }

  /// Get starting exposure from history or geometric mean
  static double getStartingExposure({
    double? historicalExposure,
    required double minExposure,
    required double maxExposure,
    double? currentSkyAduRate,
    double? historicalSkyAduRate,
  }) {
    if (historicalExposure != null) {
      // Adjust historical exposure for current sky conditions if available
      if (currentSkyAduRate != null &&
          historicalSkyAduRate != null &&
          historicalSkyAduRate.abs() > 0.001) {
        final ratio = currentSkyAduRate / historicalSkyAduRate;
        // Inverse relationship: brighter sky = shorter exposure
        final adjusted = historicalExposure / ratio.clamp(0.5, 2.0);
        return adjusted.clamp(minExposure, maxExposure);
      }
      return historicalExposure.clamp(minExposure, maxExposure);
    }

    // No history, use geometric mean (good for wide ranges)
    return math.sqrt(minExposure * maxExposure);
  }

  /// Check if exposure is at limits and suggest action
  static ExposureLimitStatus checkLimits({
    required double exposure,
    required double measuredAdu,
    required double targetAdu,
    required double minExposure,
    required double maxExposure,
    required double tolerancePercent,
  }) {
    final toleranceAdu = targetAdu * tolerancePercent / 100.0;
    final isOnTarget = (measuredAdu - targetAdu).abs() <= toleranceAdu;

    if (isOnTarget) {
      return ExposureLimitStatus.onTarget;
    }

    if (exposure >= maxExposure * 0.99 && measuredAdu < targetAdu) {
      return ExposureLimitStatus.maxExposureReached;
    }

    if (exposure <= minExposure * 1.01 && measuredAdu > targetAdu) {
      return ExposureLimitStatus.minExposureReached;
    }

    return ExposureLimitStatus.adjusting;
  }
}

enum ExposureLimitStatus {
  onTarget,
  adjusting,
  maxExposureReached,
  minExposureReached,
}
