import '../database/database.dart' show CapturedImage;

/// Advisory quality level for a captured frame.
///
/// This is informational only. It does not delete files or modify the capture.
enum FrameQualityLevel {
  good,
  needsReview,
  poor,
}

/// Result of quality assessment for a single frame.
class FrameQualityAssessment {
  final FrameQualityLevel level;
  final double advisoryScore;
  final List<String> reasons;

  const FrameQualityAssessment({
    required this.level,
    required this.advisoryScore,
    required this.reasons,
  });

  bool get needsReview => level != FrameQualityLevel.good;

  String get label {
    switch (level) {
      case FrameQualityLevel.good:
        return 'Good';
      case FrameQualityLevel.needsReview:
        return 'Needs Review';
      case FrameQualityLevel.poor:
        return 'Poor';
    }
  }
}

/// Summary counts for a set of assessed frames.
class FrameQualitySummary {
  final int total;
  final int good;
  final int needsReview;
  final int poor;

  const FrameQualitySummary({
    required this.total,
    required this.good,
    required this.needsReview,
    required this.poor,
  });
}

/// Provides non-destructive frame quality assessment.
///
/// The service classifies frames for user guidance. It never deletes files and
/// does not change frame acceptance flags.
class FrameQualityAssessmentService {
  const FrameQualityAssessmentService();

  /// Assess a single frame with optional reference medians from the session.
  FrameQualityAssessment assessFrame(
    CapturedImage image, {
    double? referenceHfr,
    double? referenceGuidingRms,
  }) {
    var advisoryScore = image.qualityScore ?? 75.0;
    var severeIssue = false;
    var moderateIssueCount = 0;
    final reasons = <String>[];

    final hfr = image.hfr;
    if (hfr != null) {
      if (hfr >= 4.5) {
        advisoryScore -= 25;
        severeIssue = true;
        reasons.add('Very soft stars (HFR ${hfr.toStringAsFixed(2)} px)');
      } else if (hfr >= 3.5) {
        advisoryScore -= 12;
        moderateIssueCount++;
        reasons.add('Soft stars (HFR ${hfr.toStringAsFixed(2)} px)');
      }

      if (referenceHfr != null && referenceHfr > 0) {
        final ratio = hfr / referenceHfr;
        if (ratio >= 1.8) {
          advisoryScore -= 20;
          severeIssue = true;
          reasons.add('HFR is ${ratio.toStringAsFixed(1)}x session median');
        } else if (ratio >= 1.4) {
          advisoryScore -= 10;
          moderateIssueCount++;
          reasons.add('HFR above session median');
        }
      }
    }

    final starCount = image.starCount;
    if (starCount != null) {
      if (starCount < 20) {
        advisoryScore -= 20;
        severeIssue = true;
        reasons.add('Very low star count ($starCount)');
      } else if (starCount < 50) {
        advisoryScore -= 10;
        moderateIssueCount++;
        reasons.add('Low star count ($starCount)');
      }
    }

    final guidingRms = image.guidingRmsTotal;
    if (guidingRms != null) {
      if (guidingRms >= 3.0) {
        advisoryScore -= 20;
        severeIssue = true;
        reasons.add('High guiding RMS (${guidingRms.toStringAsFixed(2)}")');
      } else if (guidingRms >= 2.0) {
        advisoryScore -= 10;
        moderateIssueCount++;
        reasons.add('Elevated guiding RMS (${guidingRms.toStringAsFixed(2)}")');
      }

      if (referenceGuidingRms != null && referenceGuidingRms > 0) {
        final ratio = guidingRms / referenceGuidingRms;
        if (ratio >= 1.8) {
          advisoryScore -= 10;
          moderateIssueCount++;
          reasons.add('Guiding RMS spike vs session baseline');
        }
      }
    }

    final qualityScore = image.qualityScore;
    if (qualityScore != null) {
      if (qualityScore < 40) {
        advisoryScore -= 15;
        severeIssue = true;
        reasons.add('Low quality score (${qualityScore.toStringAsFixed(0)})');
      } else if (qualityScore < 60) {
        advisoryScore -= 8;
        moderateIssueCount++;
        reasons.add('Quality score below typical range');
      }
    }

    advisoryScore = advisoryScore.clamp(0.0, 100.0);

    final level = severeIssue || advisoryScore < 45
        ? FrameQualityLevel.poor
        : (advisoryScore < 70 || moderateIssueCount >= 2)
            ? FrameQualityLevel.needsReview
            : FrameQualityLevel.good;

    return FrameQualityAssessment(
      level: level,
      advisoryScore: advisoryScore,
      reasons: reasons,
    );
  }

  /// Assess all frames in a set using session medians as reference points.
  Map<int, FrameQualityAssessment> assessBatch(Iterable<CapturedImage> images) {
    final list = images.toList();
    final medianHfr = _median(
      list.map((i) => i.hfr).whereType<double>().where((v) => v > 0),
    );
    final medianGuidingRms = _median(
      list
          .map((i) => i.guidingRmsTotal)
          .whereType<double>()
          .where((v) => v > 0),
    );

    return {
      for (final image in list)
        image.id: assessFrame(
          image,
          referenceHfr: medianHfr,
          referenceGuidingRms: medianGuidingRms,
        ),
    };
  }

  /// Build counts for dashboard and session overview display.
  FrameQualitySummary summarize(Map<int, FrameQualityAssessment> assessments) {
    var good = 0;
    var review = 0;
    var poor = 0;

    for (final assessment in assessments.values) {
      switch (assessment.level) {
        case FrameQualityLevel.good:
          good++;
          break;
        case FrameQualityLevel.needsReview:
          review++;
          break;
        case FrameQualityLevel.poor:
          poor++;
          break;
      }
    }

    return FrameQualitySummary(
      total: assessments.length,
      good: good,
      needsReview: review,
      poor: poor,
    );
  }

  double? _median(Iterable<double> values) {
    final sorted = values.toList()..sort();
    if (sorted.isEmpty) return null;

    final middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[middle];
    }

    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }
}
