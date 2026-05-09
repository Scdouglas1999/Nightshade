import '../database/database.dart' show ImagingSession;

class DeviceHealthSnapshot {
  final String deviceId;
  final int lastSuccessfulTimestampMs;
  final bool isHealthy;

  const DeviceHealthSnapshot({
    required this.deviceId,
    required this.lastSuccessfulTimestampMs,
    required this.isHealthy,
  });
}

enum EquipmentHealthSeverity { info, warning, critical }

class EquipmentHealthInsight {
  final String title;
  final String message;
  final EquipmentHealthSeverity severity;

  const EquipmentHealthInsight({
    required this.title,
    required this.message,
    required this.severity,
  });
}

class EquipmentHealthReport {
  final double score;
  final List<EquipmentHealthInsight> insights;

  const EquipmentHealthReport({
    required this.score,
    required this.insights,
  });
}

/// Longitudinal equipment health scoring from session trends and heartbeats.
class EquipmentHealthService {
  const EquipmentHealthService();

  EquipmentHealthReport analyze({
    required List<ImagingSession> sessions,
    required List<DeviceHealthSnapshot> deviceHealth,
  }) {
    final recentSessions = [...sessions]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    final latest = recentSessions.take(5).toList(growable: false);
    final baseline = recentSessions.skip(5).take(10).toList(growable: false);

    final recentGuiding = _mean(latest.map((session) => session.avgGuidingRms).whereType<double>());
    final baselineGuiding =
        _mean(baseline.map((session) => session.avgGuidingRms).whereType<double>()).clamp(0.1, 100.0);
    final recentHfr = _mean(latest.map((session) => session.avgHfr).whereType<double>());
    final baselineHfr =
        _mean(baseline.map((session) => session.avgHfr).whereType<double>()).clamp(0.1, 100.0);
    final failureRate = _failureRate(latest);
    final unhealthyDevices = deviceHealth.where((snapshot) => !snapshot.isHealthy).toList(growable: false);

    var score = 100.0;
    final insights = <EquipmentHealthInsight>[];

    if (recentGuiding > 0 && recentGuiding > baselineGuiding * 1.25) {
      score -= 18;
      insights.add(
        EquipmentHealthInsight(
          title: 'Guiding degradation',
          message:
              'Recent guiding RMS is ${(recentGuiding / baselineGuiding).toStringAsFixed(2)}x the historical baseline. Check balance, flexure, and backlash.',
          severity: EquipmentHealthSeverity.warning,
        ),
      );
    }

    if (recentHfr > 0 && recentHfr > baselineHfr * 1.15) {
      score -= 14;
      insights.add(
        EquipmentHealthInsight(
          title: 'Focus quality drift',
          message:
              'Recent median HFR is elevated versus the longer-term baseline. Inspect focus repeatability and thermal drift compensation.',
          severity: EquipmentHealthSeverity.warning,
        ),
      );
    }

    if (failureRate >= 0.12) {
      score -= 20;
      insights.add(
        EquipmentHealthInsight(
          title: 'Capture reliability risk',
          message:
              'Recent failed-exposure rate is ${(failureRate * 100).toStringAsFixed(0)}%. Review cables, power stability, and camera timeouts.',
          severity:
              failureRate >= 0.2 ? EquipmentHealthSeverity.critical : EquipmentHealthSeverity.warning,
        ),
      );
    }

    if (unhealthyDevices.isNotEmpty) {
      score -= 25;
      insights.add(
        EquipmentHealthInsight(
          title: 'Device heartbeat failures',
          message:
              'Unhealthy devices detected: ${unhealthyDevices.map((snapshot) => snapshot.deviceId).join(', ')}.',
          severity: EquipmentHealthSeverity.critical,
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        const EquipmentHealthInsight(
          title: 'Equipment health stable',
          message: 'No negative trend exceeded alert thresholds in the recent session history.',
          severity: EquipmentHealthSeverity.info,
        ),
      );
    }

    return EquipmentHealthReport(
      score: score.clamp(0.0, 100.0),
      insights: insights,
    );
  }

  double _mean(Iterable<double> values) {
    final list = values.where((value) => value.isFinite).toList(growable: false);
    if (list.isEmpty) {
      return 0.0;
    }
    return list.reduce((a, b) => a + b) / list.length;
  }

  double _failureRate(List<ImagingSession> sessions) {
    if (sessions.isEmpty) {
      return 0.0;
    }
    final failed = sessions.fold<int>(0, (sum, session) => sum + session.failedExposures);
    final total = sessions.fold<int>(0, (sum, session) => sum + session.totalExposures);
    if (total <= 0) {
      return 0.0;
    }
    return failed / total;
  }
}
