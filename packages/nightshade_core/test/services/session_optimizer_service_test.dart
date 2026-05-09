import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart'
    show ImagingSession, Target;

class _MockLoggingService extends Mock implements LoggingService {}

void main() {
  group('SessionOptimizerService', () {
    late SessionOptimizerService service;

    setUp(() {
      service = SessionOptimizerService(
        suggestionService: TargetSuggestionService(
          loggingService: _MockLoggingService(),
        ),
      );
    });

    Target target({
      required int id,
      required String name,
      required double ra,
      required double dec,
      String? objectType,
      double? magnitude,
      int totalPlannedSubs = 0,
      double totalIntegrationSecs = 0,
    }) {
      return Target(
        id: id,
        name: name,
        ra: ra,
        dec: dec,
        objectType: objectType,
        magnitude: magnitude,
        minAltitude: 20,
        totalPlannedSubs: totalPlannedSubs,
        totalIntegrationSecs: totalIntegrationSecs,
        priority: 1,
        capturedSubs: 0,
        goalIntegrationSecs: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isFavorite: false,
      );
    }

    ImagingSession session({
      required int id,
      required int targetId,
      required double totalIntegrationSecs,
    }) {
      return ImagingSession(
        id: id,
        targetId: targetId,
        startTime: DateTime(2026, 1, 1, 20),
        totalExposures: 10,
        successfulExposures: 10,
        failedExposures: 0,
        totalIntegrationSecs: totalIntegrationSecs,
        autofocusCount: 1,
        status: 'completed',
      );
    }

    test('produces a primary recommendation and alternates', () async {
      final plan = await service.optimizeTonight(
        config: const TargetSuggestionConfig(
          minAltitude: 0,
          minScore: 0,
        ),
        latitude: 40,
        longitude: -75,
        targets: [
          target(id: 1, name: 'Vega', ra: 18.6, dec: 38.8, objectType: 'Star'),
          target(id: 2, name: 'Deneb', ra: 20.7, dec: 45.3, objectType: 'Star'),
          target(id: 3, name: 'Andromeda', ra: 0.7, dec: 41.3, objectType: 'Galaxy'),
        ],
        sessions: const [],
        observationTime: DateTime(2026, 8, 1, 22),
      );

      expect(plan.hasRecommendation, isTrue);
      expect(plan.primaryTarget, isNotNull);
      expect(plan.alternates.length, lessThanOrEqualTo(3));
      expect(plan.recommendedExposureSeconds, greaterThan(0));
      expect(plan.rationale, isNotEmpty);
    });

    test('returns actionable fallback when no targets fit', () async {
      final plan = await service.optimizeTonight(
        config: const TargetSuggestionConfig(minAltitude: 80, minScore: 95),
        latitude: 40,
        longitude: -75,
        targets: [
          target(id: 1, name: 'Low South', ra: 12, dec: -70),
        ],
        sessions: const [],
        observationTime: DateTime(2026, 3, 1, 22),
      );

      expect(plan.hasRecommendation, isFalse);
      expect(plan.rationale.single, contains('No viable targets'));
      expect(plan.riskFactors.single, contains('constraints'));
    });

    test('flags nearly complete targets as a risk factor', () async {
      final plan = await service.optimizeTonight(
        config: const TargetSuggestionConfig(minAltitude: 0, minScore: 0),
        latitude: 40,
        longitude: -75,
        targets: [
          target(
            id: 1,
            name: 'Almost Done',
            ra: 18.6,
            dec: 38.8,
            totalPlannedSubs: 100,
          ),
        ],
        sessions: [
          session(id: 1, targetId: 1, totalIntegrationSecs: 27000),
        ],
        observationTime: DateTime(2026, 8, 1, 22),
      );

      expect(
        plan.riskFactors.any((factor) => factor.contains('nearly complete')),
        isTrue,
      );
    });
  });
}
