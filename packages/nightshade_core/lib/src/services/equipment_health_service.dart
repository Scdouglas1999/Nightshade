import '../database/database.dart' show ImagingSession;
import 'usb_disconnect_log.dart';

class DeviceHealthSnapshot {
  final String deviceId;
  final int lastSuccessfulTimestampMs;
  final bool isHealthy;

  /// Number of times this device disconnected (or surfaced a connection
  /// error) in the past 24 hours. Used by the pre-flight USB-stability
  /// check (`UsbStabilityRule`) — > 3 disconnects warns the user that the
  /// cable / hub / driver is suspect before a long unattended run begins.
  ///
  /// Defaults to 0 so existing call sites that only populate `isHealthy`
  /// keep their current behaviour: an unhealthy device with no count
  /// still surfaces as "device heartbeat failure" through the existing
  /// `analyze()` path.
  final int disconnectCountLast24h;

  /// Optional human-readable device label (for UI / error messages).
  /// Falls back to [deviceId] when null.
  final String? deviceLabel;

  const DeviceHealthSnapshot({
    required this.deviceId,
    required this.lastSuccessfulTimestampMs,
    required this.isHealthy,
    this.disconnectCountLast24h = 0,
    this.deviceLabel,
  });

  String get displayName => deviceLabel ?? deviceId;
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

  const EquipmentHealthReport({required this.score, required this.insights});
}

/// Connected-device descriptor used by [EquipmentHealthService.buildSnapshots]
/// to merge a USB disconnect log + the live connection state into one
/// `DeviceHealthSnapshot` list. Matches the data the
/// `*StateProvider` notifiers already track (deviceId, displayName,
/// lastSuccessfulCommunication, isHealthy) without depending on any
/// particular notifier so a remote backend or a headless tool can build
/// the same shape.
class DeviceConnectionDescriptor {
  final String deviceId;
  final String? deviceLabel;
  final bool isHealthy;
  final DateTime? lastSuccessfulCommunication;

  const DeviceConnectionDescriptor({
    required this.deviceId,
    this.deviceLabel,
    this.isHealthy = true,
    this.lastSuccessfulCommunication,
  });
}

/// Longitudinal equipment health scoring from session trends and heartbeats.
class EquipmentHealthService {
  const EquipmentHealthService();

  /// Build [DeviceHealthSnapshot]s from the connected-device list plus
  /// the rolling USB disconnect log.
  ///
  /// This is the production path that fills
  /// [DeviceHealthSnapshot.disconnectCountLast24h]. The pre-flight USB
  /// stability rule reads the resulting list via
  /// `deviceHealthSnapshotsProvider`; the post-session diagnostics
  /// summary derives a "disconnects during session" count from the same
  /// log directly.
  ///
  /// Devices that appear in the disconnect log but not in [connected]
  /// are included (with `isHealthy: false`) so the user still sees the
  /// flake count for a device that hasn't reconnected — e.g. an INDI
  /// camera that vanished mid-session.
  List<DeviceHealthSnapshot> buildSnapshots({
    required List<DeviceConnectionDescriptor> connected,
    required UsbDisconnectLog disconnectLog,
    DateTime? now,
  }) {
    final perDeviceCounts = disconnectLog.perDeviceCounts(now: now);
    final byId = <String, DeviceHealthSnapshot>{};

    for (final device in connected) {
      final id = device.deviceId;
      byId[id] = DeviceHealthSnapshot(
        deviceId: id,
        deviceLabel: device.deviceLabel,
        lastSuccessfulTimestampMs:
            device.lastSuccessfulCommunication?.millisecondsSinceEpoch ?? 0,
        isHealthy: device.isHealthy,
        disconnectCountLast24h: perDeviceCounts[id] ?? 0,
      );
    }

    // Pull in devices that disconnected and never came back (or that
    // reconnected through a path that didn't populate the connected
    // list). Without this branch the snapshot list would silently drop
    // the most interesting cases — a USB cable yanked at the start of
    // a run that the user is unaware of.
    for (final entry in perDeviceCounts.entries) {
      if (byId.containsKey(entry.key)) continue;
      byId[entry.key] = DeviceHealthSnapshot(
        deviceId: entry.key,
        lastSuccessfulTimestampMs: 0,
        isHealthy: false,
        disconnectCountLast24h: entry.value,
      );
    }

    return byId.values.toList(growable: false);
  }

  EquipmentHealthReport analyze({
    required List<ImagingSession> sessions,
    required List<DeviceHealthSnapshot> deviceHealth,
  }) {
    final recentSessions = [...sessions]
      ..sort((a, b) => b.startTime.compareTo(a.startTime));

    final latest = recentSessions.take(5).toList(growable: false);
    final baseline = recentSessions.skip(5).take(10).toList(growable: false);

    final recentGuiding = _mean(
      latest.map((session) => session.avgGuidingRms).whereType<double>(),
    );
    final baselineGuiding = _mean(
      baseline.map((session) => session.avgGuidingRms).whereType<double>(),
    ).clamp(0.1, 100.0);
    final recentHfr = _mean(
      latest.map((session) => session.avgHfr).whereType<double>(),
    );
    final baselineHfr = _mean(
      baseline.map((session) => session.avgHfr).whereType<double>(),
    ).clamp(0.1, 100.0);
    final failureRate = _failureRate(latest);
    final unhealthyDevices = deviceHealth
        .where((snapshot) => !snapshot.isHealthy)
        .toList(growable: false);

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
        const EquipmentHealthInsight(
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
          severity: failureRate >= 0.2
              ? EquipmentHealthSeverity.critical
              : EquipmentHealthSeverity.warning,
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
          message:
              'No negative trend exceeded alert thresholds in the recent session history.',
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
    final list = values
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (list.isEmpty) {
      return 0.0;
    }
    return list.reduce((a, b) => a + b) / list.length;
  }

  double _failureRate(List<ImagingSession> sessions) {
    if (sessions.isEmpty) {
      return 0.0;
    }
    final failed = sessions.fold<int>(
      0,
      (sum, session) => sum + session.failedExposures,
    );
    final total = sessions.fold<int>(
      0,
      (sum, session) => sum + session.totalExposures,
    );
    if (total <= 0) {
      return 0.0;
    }
    return failed / total;
  }
}
