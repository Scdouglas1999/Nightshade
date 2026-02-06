import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show
        FrameQualityAssessment,
        FrameQualityAssessmentService,
        FrameQualityLevel;
import 'package:nightshade_core/src/database/database.dart' show CapturedImage;

CapturedImage _image({
  required int id,
  double? qualityScore,
  double? hfr,
  int? starCount,
  double? guidingRmsTotal,
}) {
  final now = DateTime(2026, 1, 1, 0, 0);
  return CapturedImage(
    id: id,
    filePath: '/tmp/$id.fits',
    fileName: '$id.fits',
    fileFormat: 'fits',
    frameType: 'light',
    exposureDuration: 300,
    binX: 1,
    binY: 1,
    qualityScore: qualityScore,
    hfr: hfr,
    starCount: starCount,
    guidingRmsTotal: guidingRmsTotal,
    isPlateSolved: false,
    capturedAt: now,
    createdAt: now,
    isAccepted: true,
  );
}

void main() {
  group('FrameQualityAssessmentService', () {
    const service = FrameQualityAssessmentService();

    test('classifies a clean frame as good', () {
      final result = service.assessFrame(
        _image(
          id: 1,
          qualityScore: 88,
          hfr: 2.2,
          starCount: 120,
          guidingRmsTotal: 1.1,
        ),
      );

      expect(result.level, FrameQualityLevel.good);
      expect(result.needsReview, isFalse);
      expect(result.reasons, isEmpty);
    });

    test('classifies strongly degraded frame as poor with reasons', () {
      final result = service.assessFrame(
        _image(
          id: 2,
          qualityScore: 35,
          hfr: 5.1,
          starCount: 12,
          guidingRmsTotal: 3.4,
        ),
      );

      expect(result.level, FrameQualityLevel.poor);
      expect(result.needsReview, isTrue);
      expect(result.reasons, isNotEmpty);
      expect(
        result.reasons.any((reason) => reason.contains('Very soft stars')),
        isTrue,
      );
    });

    test('uses session medians to flag HFR outliers', () {
      final frames = [
        _image(
          id: 1,
          qualityScore: 85,
          hfr: 2.1,
          starCount: 100,
          guidingRmsTotal: 1.0,
        ),
        _image(
          id: 2,
          qualityScore: 84,
          hfr: 2.2,
          starCount: 98,
          guidingRmsTotal: 1.1,
        ),
        _image(
          id: 3,
          qualityScore: 80,
          hfr: 4.8,
          starCount: 70,
          guidingRmsTotal: 1.1,
        ),
      ];

      final batch = service.assessBatch(frames);
      final outlier = batch[3]!;

      expect(outlier.level, isNot(FrameQualityLevel.good));
      expect(
        outlier.reasons.any((reason) => reason.contains('session median')),
        isTrue,
      );
    });

    test('builds summary counts from assessments', () {
      final assessments = {
        1: const FrameQualityAssessment(
          level: FrameQualityLevel.good,
          advisoryScore: 90,
          reasons: [],
        ),
        2: const FrameQualityAssessment(
          level: FrameQualityLevel.needsReview,
          advisoryScore: 62,
          reasons: ['Low star count'],
        ),
        3: const FrameQualityAssessment(
          level: FrameQualityLevel.poor,
          advisoryScore: 30,
          reasons: ['Very soft stars'],
        ),
      };

      final summary = service.summarize(assessments);

      expect(summary.total, 3);
      expect(summary.good, 1);
      expect(summary.needsReview, 1);
      expect(summary.poor, 1);
    });
  });
}
