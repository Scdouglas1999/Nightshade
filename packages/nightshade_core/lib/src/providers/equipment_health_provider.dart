import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/equipment_health_service.dart';
import 'database_provider.dart';

/// Service provider for EquipmentHealthService.
final equipmentHealthServiceProvider =
    Provider<EquipmentHealthService>((ref) {
  return const EquipmentHealthService();
});

/// Device health snapshots supplied by the UI or a background monitor.
///
/// The UI layer (or a background polling notifier) must override this provider
/// with actual device heartbeat data. The default is an empty list so that the
/// health report degrades gracefully to session-only analysis.
final deviceHealthSnapshotsProvider =
    StateProvider<List<DeviceHealthSnapshot>>((ref) {
  return const [];
});

/// Reactive equipment health report built from session history and device
/// heartbeats.
///
/// Re-evaluates whenever the sessions stream or device-health state changes.
final equipmentHealthReportProvider =
    Provider<AsyncValue<EquipmentHealthReport>>((ref) {
  final sessionsAsync = ref.watch(allSessionsProvider);
  final deviceHealth = ref.watch(deviceHealthSnapshotsProvider);
  final service = ref.watch(equipmentHealthServiceProvider);

  return sessionsAsync.when(
    data: (sessions) {
      final report = service.analyze(
        sessions: sessions,
        deviceHealth: deviceHealth,
      );
      return AsyncValue.data(report);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stackTrace) => AsyncValue.error(error, stackTrace),
  );
});
