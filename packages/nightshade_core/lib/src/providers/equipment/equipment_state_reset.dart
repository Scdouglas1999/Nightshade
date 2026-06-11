import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device_heartbeat_health_provider.dart';
import 'camera_state_provider.dart';
import 'cover_calibrator_state_provider.dart';
import 'dome_state_provider.dart';
import 'filter_wheel_state_provider.dart';
import 'focuser_state_provider.dart';
import 'guider_state_provider.dart';
import 'mount_state_provider.dart';
import 'rotator_state_provider.dart';
import 'safety_monitor_state_provider.dart';
import 'switch_state_provider.dart';
import 'weather_state_provider.dart';

/// Reset every equipment-state notifier to disconnected baseline.
///
/// Called when the active [NightshadeBackend] is swapped so UI does not
/// continue showing devices as connected against a backend that never
/// opened them.
void resetAllEquipmentStateNotifiers(Ref ref) {
  ref.read(cameraStateProvider.notifier).setDisconnected();
  ref.read(mountStateProvider.notifier).setDisconnected();
  ref.read(focuserStateProvider.notifier).setDisconnected();
  ref.read(filterWheelStateProvider.notifier).setDisconnected();
  ref.read(guiderStateProvider.notifier).setDisconnected();
  ref.read(rotatorStateProvider.notifier).setDisconnected();
  ref.read(domeStateProvider.notifier).setDisconnected();
  ref.read(weatherStateProvider.notifier).setDisconnected();
  ref.read(safetyMonitorStateProvider.notifier).setDisconnected();
  ref.read(switchStateProvider.notifier).setDisconnected();
  ref.read(coverCalibratorStateProvider.notifier).setDisconnected();

  try {
    ref.read(deviceHeartbeatHealthProvider.notifier).clearAll();
  } on Object {
    // Heartbeat provider may be unavailable mid-disposal during shutdown.
  }
}
