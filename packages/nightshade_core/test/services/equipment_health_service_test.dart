import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' show ImagingSession;

void main() {
  group('EquipmentHealthService', () {
    const service = EquipmentHealthService();

    ImagingSession session({
      required int id,
      required DateTime start,
      required double avgGuidingRms,
      required double avgHfr,
      required int totalExposures,
      required int failedExposures,
    }) {
      return ImagingSession(
        id: id,
        startTime: start,
        avgGuidingRms: avgGuidingRms,
        avgHfr: avgHfr,
        totalExposures: totalExposures,
        successfulExposures: totalExposures - failedExposures,
        failedExposures: failedExposures,
        totalIntegrationSecs: 1800,
        autofocusCount: 1,
        status: 'completed',
      );
    }

    test('reports healthy baseline when no adverse trend exists', () {
      final report = service.analyze(
        sessions: [
          for (var i = 0; i < 8; i++)
            session(
              id: i,
              start: DateTime(2026, 1, 1).add(Duration(days: i)),
              avgGuidingRms: 0.8,
              avgHfr: 2.2,
              totalExposures: 20,
              failedExposures: 1,
            ),
        ],
        deviceHealth: const [
          DeviceHealthSnapshot(
            deviceId: 'camera',
            lastSuccessfulTimestampMs: 10,
            isHealthy: true,
          ),
        ],
      );

      expect(report.score, greaterThan(90));
      expect(report.insights.single.title, contains('stable'));
    });

    test('flags degraded guiding and unhealthy devices', () {
      final report = service.analyze(
        sessions: [
          for (var i = 0; i < 6; i++)
            session(
              id: i,
              start: DateTime(2026, 1, 1).add(Duration(days: i)),
              avgGuidingRms: i < 3 ? 0.8 : 1.5,
              avgHfr: i < 3 ? 2.2 : 2.9,
              totalExposures: 20,
              failedExposures: i < 3 ? 1 : 5,
            ),
        ],
        deviceHealth: const [
          DeviceHealthSnapshot(
            deviceId: 'mount',
            lastSuccessfulTimestampMs: 10,
            isHealthy: false,
          ),
        ],
      );

      expect(report.score, lessThan(80));
      expect(
        report.insights.any((insight) => insight.title.contains('Guiding')),
        isTrue,
      );
      expect(
        report.insights.any((insight) => insight.title.contains('heartbeat')),
        isTrue,
      );
    });
  });
}
