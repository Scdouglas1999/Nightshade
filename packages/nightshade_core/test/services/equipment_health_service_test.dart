import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

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

  group('EquipmentHealthService.buildSnapshots (Wave 5.5)', () {
    const service = EquipmentHealthService();

    test('populates disconnectCountLast24h from the USB log', () {
      final now = DateTime.utc(2026, 5, 18, 22, 0);
      final log = UsbDisconnectLog(now: () => now);
      log.recordDisconnect(
        deviceId: 'cam-1',
        timestamp: now.subtract(const Duration(minutes: 10)),
      );
      log.recordDisconnect(
        deviceId: 'cam-1',
        timestamp: now.subtract(const Duration(hours: 4)),
      );
      log.recordDisconnect(
        deviceId: 'mount-1',
        timestamp: now.subtract(const Duration(hours: 1)),
      );

      final snapshots = service.buildSnapshots(
        connected: const [
          DeviceConnectionDescriptor(
            deviceId: 'cam-1',
            deviceLabel: 'Test Camera',
            isHealthy: true,
          ),
          DeviceConnectionDescriptor(deviceId: 'mount-1', isHealthy: true),
        ],
        disconnectLog: log,
        now: now,
      );

      final cam = snapshots.firstWhere((s) => s.deviceId == 'cam-1');
      final mount = snapshots.firstWhere((s) => s.deviceId == 'mount-1');
      expect(cam.disconnectCountLast24h, 2);
      expect(cam.deviceLabel, 'Test Camera');
      expect(cam.isHealthy, isTrue);
      expect(mount.disconnectCountLast24h, 1);
    });

    test('includes devices that only appear in the disconnect log', () {
      // INDI camera that vanished mid-session and hasn't reconnected:
      // shows up in the log but not the connected list. The pre-flight
      // check still needs to see the flake history.
      final now = DateTime.utc(2026, 5, 18, 22, 0);
      final log = UsbDisconnectLog(now: () => now);
      log.recordDisconnect(
        deviceId: 'vanished-cam',
        timestamp: now.subtract(const Duration(hours: 1)),
      );

      final snapshots = service.buildSnapshots(
        connected: const [],
        disconnectLog: log,
        now: now,
      );
      expect(snapshots.length, 1);
      expect(snapshots.first.deviceId, 'vanished-cam');
      expect(
        snapshots.first.isHealthy,
        isFalse,
        reason: 'devices in the log but not connected count as unhealthy',
      );
      expect(snapshots.first.disconnectCountLast24h, 1);
    });

    test('connected device with no disconnects has count == 0', () {
      final now = DateTime.utc(2026, 5, 18, 22, 0);
      final log = UsbDisconnectLog(now: () => now);

      final snapshots = service.buildSnapshots(
        connected: const [
          DeviceConnectionDescriptor(deviceId: 'stable-cam', isHealthy: true),
        ],
        disconnectLog: log,
        now: now,
      );
      expect(snapshots.single.disconnectCountLast24h, 0);
    });
  });
}
