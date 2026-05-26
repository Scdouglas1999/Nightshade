import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/equipment/equipment_models.dart' show DeviceConnectionState;
import '../services/equipment_health_service.dart';
import 'database_provider.dart';
import 'equipment/camera_state_provider.dart';
import 'equipment/filter_wheel_state_provider.dart';
import 'equipment/focuser_state_provider.dart';
import 'equipment/mount_state_provider.dart';
import 'equipment/rotator_state_provider.dart';
import 'usb_disconnect_log_provider.dart';

/// Service provider for EquipmentHealthService.
final equipmentHealthServiceProvider =
    Provider<EquipmentHealthService>((ref) {
  return const EquipmentHealthService();
});

/// Device health snapshots derived from the live equipment-state notifiers
/// plus the rolling [UsbDisconnectLog]. Wave 5.5 wired the production path
/// so `disconnectCountLast24h` actually carries non-zero values; before
/// this provider was a placeholder `StateProvider<[]>` that the UI never
/// populated, leaving the pre-flight USB stability check inert.
///
/// Tests can override this provider with a static list if they want to
/// bypass the live wiring (e.g. preflight_rules_test does exactly that).
final deviceHealthSnapshotsProvider =
    Provider<List<DeviceHealthSnapshot>>((ref) {
  final service = ref.watch(equipmentHealthServiceProvider);
  final disconnectLog = ref.watch(usbDisconnectLogProvider);

  final descriptors = <DeviceConnectionDescriptor>[];

  // Camera carries an explicit health timer; the other notifiers only
  // track connection state + last error, so we synthesise an isHealthy
  // boolean from `connected && !hasError`. The pre-flight USB stability
  // rule reads `disconnectCountLast24h` directly so the exact value of
  // isHealthy doesn't matter for that path, but the EquipmentHealthReport
  // surfaces device-down warnings when isHealthy is false — so a
  // disconnected mount mid-session correctly raises a critical health
  // insight.
  final camera = ref.watch(cameraStateProvider);
  if (camera.deviceId != null && camera.deviceId!.isNotEmpty) {
    descriptors.add(DeviceConnectionDescriptor(
      deviceId: camera.deviceId!,
      deviceLabel: camera.deviceName,
      isHealthy: camera.isHealthy,
      lastSuccessfulCommunication: camera.lastSuccessfulCommunication,
    ));
  }

  void addBasic(String? deviceId, String? deviceLabel,
      DeviceConnectionState connectionState, bool hasError) {
    if (deviceId == null || deviceId.isEmpty) return;
    final isHealthy =
        connectionState == DeviceConnectionState.connected && !hasError;
    descriptors.add(DeviceConnectionDescriptor(
      deviceId: deviceId,
      deviceLabel: deviceLabel,
      isHealthy: isHealthy,
    ));
  }

  final mount = ref.watch(mountStateProvider);
  addBasic(mount.deviceId, mount.deviceName, mount.connectionState,
      mount.hasError);
  final focuser = ref.watch(focuserStateProvider);
  addBasic(focuser.deviceId, focuser.deviceName, focuser.connectionState,
      focuser.hasError);
  final filterWheel = ref.watch(filterWheelStateProvider);
  addBasic(filterWheel.deviceId, filterWheel.deviceName,
      filterWheel.connectionState, filterWheel.hasError);
  final rotator = ref.watch(rotatorStateProvider);
  addBasic(rotator.deviceId, rotator.deviceName, rotator.connectionState,
      rotator.hasError);

  return service.buildSnapshots(
    connected: descriptors,
    disconnectLog: disconnectLog,
  );
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
