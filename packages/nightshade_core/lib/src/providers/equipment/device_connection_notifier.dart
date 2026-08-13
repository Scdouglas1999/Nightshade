import '../../models/equipment/equipment_models.dart'
    show DeviceConnectionState;

/// The connection surface every equipment state notifier exposes.
///
/// The master→slave mirror drives all eleven device notifiers through one
/// device-type table. Without a shared type that table has to be `dynamic`, and
/// a rename in any notifier becomes a runtime `NoSuchMethodError` on the
/// slave's event pump instead of an analyzer error.
///
/// Deliberately narrow: only the members the mirror actually drives. Each
/// device's own telemetry setters, and `connect` (whose signature genuinely
/// varies — the guider carries a friendly name through its retry), stay off it.
abstract interface class DeviceConnectionNotifier {
  /// Live connection state, read straight off the notifier's own state.
  DeviceConnectionState get connectionState;

  /// Id of the device this notifier currently represents, or null.
  String? get deviceId;

  void setConnecting(String deviceId, [String? deviceName]);
  void setConnected();
  void setDisconnected();
}
