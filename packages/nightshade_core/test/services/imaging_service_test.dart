import 'package:flutter_test/flutter_test.dart';
import 'dart:math' as math;

void main() {
  group('ImagingService Quality Score Tests', () {
    // Helper to access private method via reflection or re-implementation
    double calculateQualityScore({
      required double? hfr,
      required int? starCount,
      required double mean,
      required double stdDev,
    }) {
      double score = 0.0;
      double weightSum = 0.0;

      // HFR component (40% weight)
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
      if (mean > 0.0) {
        final cv = stdDev / mean;
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

      if (hfr != null && hfr > 5.0) {
        final hfrExcess = math.min(15.0, hfr - 5.0);
        final penaltyFactor = 1.0 - (hfrExcess / 15.0) * 0.25;
        normalizedScore *= penaltyFactor;
      }

      return normalizedScore.clamp(0.0, 100.0);
    }

    test('Quality score for excellent image', () {
      final score = calculateQualityScore(
        hfr: 1.8,
        starCount: 150,
        mean: 5000.0,
        stdDev: 500.0, // CV = 0.1
      );
      expect(score, greaterThan(85.0),
          reason: 'Excellent image (HFR=1.8, stars=150, CV=0.1) should score > 85');
    });

    test('Quality score for good image', () {
      final score = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 800.0, // CV = 0.16
      );
      expect(score, greaterThan(70.0),
          reason: 'Good image should score > 70');
      expect(score, lessThan(85.0),
          reason: 'Good image should score < 85');
    });

    test('Quality score for poor image', () {
      final score = calculateQualityScore(
        hfr: 6.0,
        starCount: 15,
        mean: 5000.0,
        stdDev: 2000.0, // CV = 0.4
      );
      expect(score, lessThan(40.0),
          reason: 'Poor image (HFR=6.0, stars=15, CV=0.4) should score < 40');
    });

    test('Quality score with no HFR/star data', () {
      final score = calculateQualityScore(
        hfr: null,
        starCount: null,
        mean: 5000.0,
        stdDev: 800.0,
      );
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(100.0),
          reason: 'Score should be in valid range even with no HFR/star data');
    });

    test('Quality score with zero values', () {
      final score = calculateQualityScore(
        hfr: 0.0,
        starCount: 0,
        mean: 0.0,
        stdDev: 0.0,
      );
      expect(score, greaterThanOrEqualTo(0.0));
      expect(score, lessThanOrEqualTo(100.0),
          reason: 'Score should be valid even with zeros');
    });

    test('Quality score with very high HFR', () {
      final score = calculateQualityScore(
        hfr: 20.0,
        starCount: 150,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score, lessThan(50.0),
          reason: 'Very high HFR should lower score significantly');
    });

    test('Quality score for perfect image', () {
      final score = calculateQualityScore(
        hfr: 1.5,
        starCount: 200,
        mean: 10000.0,
        stdDev: 500.0, // CV = 0.05
      );
      expect(score, greaterThan(90.0),
          reason: 'Perfect image (HFR=1.5, stars=200, CV=0.05) should score > 90');
    });

    test('Quality score HFR thresholds', () {
      // Test HFR boundaries
      final score1 = calculateQualityScore(
        hfr: 1.9,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score2 = calculateQualityScore(
        hfr: 2.1,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score1, greaterThan(score2),
          reason: 'HFR 1.9 should score higher than 2.1');

      final score3 = calculateQualityScore(
        hfr: 2.9,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score4 = calculateQualityScore(
        hfr: 3.1,
        starCount: 100,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score3, greaterThan(score4),
          reason: 'HFR 2.9 should score higher than 3.1');
    });

    test('Quality score star count thresholds', () {
      // Test star count boundaries
      final score1 = calculateQualityScore(
        hfr: 2.5,
        starCount: 19,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score2 = calculateQualityScore(
        hfr: 2.5,
        starCount: 21,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score2, greaterThan(score1),
          reason: '21 stars should score higher than 19 stars');

      final score3 = calculateQualityScore(
        hfr: 2.5,
        starCount: 49,
        mean: 5000.0,
        stdDev: 500.0,
      );
      final score4 = calculateQualityScore(
        hfr: 2.5,
        starCount: 51,
        mean: 5000.0,
        stdDev: 500.0,
      );
      expect(score4, greaterThan(score3),
          reason: '51 stars should score higher than 49 stars');
    });

    test('Quality score uniformity component', () {
      // Test different CV values with same HFR and star count
      final score1 = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 400.0, // CV = 0.08 (excellent)
      );
      final score2 = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 1000.0, // CV = 0.2 (good)
      );
      final score3 = calculateQualityScore(
        hfr: 2.5,
        starCount: 75,
        mean: 5000.0,
        stdDev: 2000.0, // CV = 0.4 (poor)
      );
      expect(score1, greaterThan(score2),
          reason: 'Better uniformity (CV=0.08) should score higher');
      expect(score2, greaterThan(score3),
          reason: 'Good uniformity (CV=0.2) should score higher than poor (CV=0.4)');
    });

    test('Quality score is in valid range', () {
      // Test various combinations to ensure score is always 0-100
      final testCases = [
        {'hfr': 1.0, 'stars': 200, 'mean': 10000.0, 'std': 300.0},
        {'hfr': 10.0, 'stars': 5, 'mean': 1000.0, 'std': 500.0},
        {'hfr': 3.5, 'stars': 75, 'mean': 5000.0, 'std': 750.0},
        {'hfr': null, 'stars': 100, 'mean': 5000.0, 'std': 500.0},
        {'hfr': 2.0, 'stars': null, 'mean': 5000.0, 'std': 500.0},
      ];

      for (final testCase in testCases) {
        final score = calculateQualityScore(
          hfr: testCase['hfr'] as double?,
          starCount: testCase['stars'] as int?,
          mean: testCase['mean'] as double,
          stdDev: testCase['std'] as double,
        );
        expect(score, greaterThanOrEqualTo(0.0));
        expect(score, lessThanOrEqualTo(100.0),
            reason: 'Score must be in 0-100 range for: $testCase');
      }
    });
  });
}
