// ignore_for_file: unused_element

part of '../imaging_service.dart';

extension _ImagingServiceQualityProcessing on ImagingService {
  /// Calculate image quality score (0-100)
  /// Mirrors the Rust implementation in imaging/fits.rs
  double _calculateQualityScore({
    required double? hfr,
    required int? starCount,
    required double mean,
    required double stdDev,
  }) {
    double score = 0.0;
    double weightSum = 0.0;

    // HFR component (40% weight)
    // Excellent: < 2.0, Good: 2-3, Fair: 3-5, Poor: > 5
    if (hfr != null && hfr > 0.0) {
      final hfrScore = hfr < 2.0
          ? 100.0
          : hfr < 3.0
              ? 100.0 - (hfr - 2.0) * 25.0
              : hfr < 5.0
                  ? 75.0 - (hfr - 3.0) * 25.0
                  : math.max(0.0, 25.0 - math.min(5.0, hfr - 5.0) * 5.0);
      score += hfrScore * 0.4;
      weightSum += 0.4;
    }

    // Star count component (30% weight)
    // Excellent: > 100, Good: 50-100, Fair: 20-50, Poor: < 20
    if (starCount != null) {
      final starScore = starCount >= 100
          ? 100.0
          : starCount >= 50
              ? 66.0 + (starCount - 50) / 50.0 * 34.0
              : starCount >= 20
                  ? 33.0 + (starCount - 20) / 30.0 * 33.0
                  : math.max(0.0, starCount / 20.0 * 33.0);
      score += starScore * 0.3;
      weightSum += 0.3;
    }

    // Background uniformity component (30% weight)
    // Lower noise is better - check coefficient of variation
    if (mean > 0.0) {
      final cv = stdDev / mean; // Coefficient of variation
      final uniformityScore = cv < 0.1
          ? 100.0
          : cv < 0.3
              ? 100.0 - (cv - 0.1) * 333.0
              : math.max(0.0, 33.0 - math.min(0.33, cv - 0.3) * 100.0);
      score += uniformityScore * 0.3;
      weightSum += 0.3;
    }

    if (weightSum <= 0.0) {
      return 0.0;
    }

    var normalizedScore = (score / weightSum).clamp(0.0, 100.0);

    // Apply an additional global penalty for severe focus issues.
    // Extremely high HFR should meaningfully reduce overall quality even when
    // star count/background metrics look strong.
    if (hfr != null && hfr > 5.0) {
      final hfrExcess = math.min(15.0, hfr - 5.0);
      final penaltyFactor = 1.0 - (hfrExcess / 15.0) * 0.25;
      normalizedScore *= penaltyFactor;
    }

    return normalizedScore.clamp(0.0, 100.0);
  }

  /// Generate a simulated star field image
  CapturedImageData _generateSimulatedImage({
    required int width,
    required int height,
    required ExposureSettings settings,
    String? targetName,
  }) {
    final pixelCount = width * height;
    final grayData = Uint8List(pixelCount);
    final histogram = List<int>.filled(256, 0);

    // Random number generator
    int seed = DateTime.now().microsecondsSinceEpoch;
    int random() {
      seed = ((seed * 1103515245 + 12345) & 0x7fffffff);
      return seed;
    }

    double randomDouble() => random() / 0x7fffffff;
    int randomRange(int min, int max) => min + (random() % (max - min));

    // Background level based on gain and exposure
    final gain = settings.gain;
    final exposureTime = settings.exposureTime;
    final baseBackground =
        (30 + gain * 0.2 + exposureTime * 2).round().clamp(20, 100);
    final noiseLevel = (10 + gain * 0.1).round().clamp(5, 30);

    // Fill with background + noise
    for (int i = 0; i < pixelCount; i++) {
      final noise = (randomDouble() * noiseLevel).round() - noiseLevel ~/ 2;
      grayData[i] = (baseBackground + noise).clamp(0, 255);
    }

    // Add stars
    final numStars = (50 + exposureTime * 30).round().clamp(30, 300);
    int starCount = 0;
    double totalHfr = 0;
    double totalFwhm = 0;

    for (int s = 0; s < numStars; s++) {
      final x = randomRange(5, width - 5);
      final y = randomRange(5, height - 5);
      final brightness = randomRange(150, 255);
      final size = 1.0 + randomDouble() * 2.5;

      // Draw Gaussian star profile
      final radius = (size * 3).ceil();
      for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
          final px = x + dx;
          final py = y + dy;

          if (px >= 0 && px < width && py >= 0 && py < height) {
            final distSq = dx * dx + dy * dy;
            final sigmaSq = size * size;
            final intensity = brightness * math.exp(-distSq / (2 * sigmaSq));

            final idx = py * width + px;
            grayData[idx] = (grayData[idx] + intensity.round()).clamp(0, 255);
          }
        }
      }

      starCount++;
      totalHfr += size * 0.8;
      totalFwhm += size * 2.35; // FWHM ≈ 2.35 * sigma for Gaussian
    }

    // Add hot pixels
    for (int i = 0; i < 15; i++) {
      final idx = randomRange(0, pixelCount);
      grayData[idx] = randomRange(200, 255);
    }

    // Calculate histogram from grayscale data (before RGBA conversion)
    for (int i = 0; i < pixelCount; i++) {
      histogram[grayData[i]]++;
    }

    // Calculate stats from grayscale data
    double sum = 0;
    int min = 255;
    int max = 0;

    for (int i = 0; i < pixelCount; i++) {
      final val = grayData[i];
      sum += val;
      if (val < min) min = val;
      if (val > max) max = val;
    }

    final mean = sum / pixelCount;
    final avgHfr = starCount > 0 ? totalHfr / starCount : 0.0;
    final avgFwhm = starCount > 0 ? totalFwhm / starCount : 0.0;

    // Calculate standard deviation
    double varianceSum = 0;
    for (int i = 0; i < pixelCount; i++) {
      final diff = grayData[i] - mean;
      varianceSum += diff * diff;
    }
    final stdDev = math.sqrt(varianceSum / pixelCount);

    // Calculate median
    int cumulative = 0;
    double median = 128;
    for (int i = 0; i < 256; i++) {
      cumulative += histogram[i];
      if (cumulative >= pixelCount / 2) {
        median = i.toDouble();
        break;
      }
    }

    // Convert grayscale to RGBA for display
    final displayData = Uint8List(pixelCount * 4);
    for (int i = 0; i < pixelCount; i++) {
      final gray = grayData[i];
      final d = i * 4;
      displayData[d] = gray;
      displayData[d + 1] = gray;
      displayData[d + 2] = gray;
      displayData[d + 3] = 255;
    }

    return CapturedImageData(
      width: width,
      height: height,
      displayData: displayData,
      histogram: histogram,
      stats: ImageStats(
        min: min.toDouble(),
        max: max.toDouble(),
        mean: mean,
        median: median,
        stdDev: stdDev,
        hfr: avgHfr + (randomDouble() - 0.5) * 0.3,
        fwhm: avgFwhm + (randomDouble() - 0.5) * 0.5,
        starCount: starCount,
        background: baseBackground.toDouble(),
        noise: noiseLevel.toDouble(),
        snr: mean / stdDev,
      ),
      capturedAt: DateTime.now(),
      settings: settings,
      targetName: targetName,
    );
  }
}
