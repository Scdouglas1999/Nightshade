/// Typed exceptions thrown by [DeviceService] disconnect methods.
///
/// Audit DEV-P2-6: `EquipmentScreen._disconnectAllDevices` previously
/// filtered "device not connected" errors out of its toast feed by
/// running `e.toString().contains('not connected')` on a generic
/// [Exception]. That is fragile — a localization change or a reword
/// in `device_service.dart` would resurface a flood of "device not
/// connected" toasts every time the user clicked "Disconnect All",
/// because some devices in a profile are always selected-but-never-
/// connected.
///
/// The disconnect methods now throw [DeviceNotConnectedException] when
/// invoked on a device that has no `deviceId` recorded in its
/// `*StateProvider`. Callers that iterate every device type (the
/// equipment screen's bulk-disconnect button, the bundled
/// [DeviceService.disconnectAll]) catch this exception explicitly and
/// continue; every other disconnect failure still propagates.
///
/// Errors are a feature: this exception is intentionally narrow. Do not
/// broaden it to swallow generic disconnect failures (driver errors,
/// stale handles, timeouts, etc.) — those still need to bubble up so the
/// UI can warn the user.
library;

/// Thrown when a `DeviceService.disconnect<Type>()` is invoked on a device
/// that is not currently connected (no `deviceId` in the matching state
/// provider).
///
/// This is a precondition signal, not a hardware-level error. It indicates
/// that the caller asked to disconnect something that was never connected
/// in the first place, so there is nothing to do. UI consumers that issue
/// a "disconnect all" sweep should treat this exception as benign and skip
/// to the next device.
class DeviceNotConnectedException implements Exception {
  /// Friendly identifier of the device that was being disconnected, e.g.
  /// `'camera'`, `'filter wheel'`. Used by callers to compose log lines and
  /// (when appropriate) user-visible messages.
  final String deviceType;

  /// Human-readable description for logging / `toString`.
  final String message;

  const DeviceNotConnectedException(this.deviceType, [String? message])
      : message = message ?? 'No $deviceType is currently connected';

  @override
  String toString() => 'DeviceNotConnectedException($deviceType): $message';
}

/// Thrown when a `DeviceService.connect<Type>()` is called with a device id
/// that does not match any of Nightshade's known driver-prefix conventions
/// (see `kKnownDeviceIdPrefixes` in `utils/device_id_utils.dart`).
///
/// DEV-P1-7: this replaces the old "Camera not found: $id" string that the
/// connect methods used to throw after running a full `discoverDevices`
/// sweep on every connect attempt. Discovery is the wrong precondition for
/// connect — it forces a fresh hardware scan to validate a reconnect of a
/// known-good device, which fails whenever the discovery transient has
/// blipped (USB hub flicker, backend swap, etc.).
///
/// We now do a cheap structural format check up front and delegate the
/// real "is this device actually reachable?" decision to the backend's
/// `connectDevice` call. Only an outright malformed id (no recognized
/// driver prefix) trips this exception — every other failure must still
/// propagate from the backend so the UI can surface it.
class InvalidDeviceIdException implements Exception {
  /// The device id that failed format validation.
  final String deviceId;

  /// Friendly device type for the error message, e.g. `'camera'`.
  final String deviceType;

  const InvalidDeviceIdException(this.deviceType, this.deviceId);

  @override
  String toString() =>
      'InvalidDeviceIdException($deviceType): id "$deviceId" does not match '
      'any known driver prefix (ascom:, alpaca:, indi:, native:, simulator:, '
      'phd2, builtin_guider).';
}

/// Per-device status emitted by [DeviceService.connectAllFromProfile] while
/// a "Connect All" sweep is in flight.
///
/// DEV-P1-5: replaces a sequential `await connectX(...)` loop that took
/// 30-50 s for a full profile and gave the user no per-device progress.
/// The service now connects every configured device-type in parallel and
/// emits a stream of these progress updates so the UI can render
/// per-device chips with live status without blocking on the slowest
/// device.
enum DeviceConnectProgressStatus {
  /// Sweep has started for this device type but the backend connect call
  /// has not yet returned.
  connecting,

  /// `connectDevice` returned successfully and the state notifier is now
  /// connected.
  connected,

  /// `connectDevice` threw. [DeviceConnectProgress.error] carries the
  /// raw error and [DeviceConnectProgress.errorMessage] a stringified
  /// form for UI display.
  failed,
}

/// Progress event emitted by [DeviceService.connectAllFromProfile].
///
/// Errors are a feature: a `failed` event always carries the backend's
/// error verbatim so the UI can show it to the user. The stream does not
/// throw — per-device failures are reported as `failed` events, never as
/// stream errors, so a single bad device cannot abort the sweep.
class DeviceConnectProgress {
  /// Friendly device category being connected, e.g. `'camera'`, `'mount'`.
  final String deviceType;

  /// Device id that was passed to the connect call.
  final String deviceId;

  /// Current status of this device's connect attempt.
  final DeviceConnectProgressStatus status;

  /// Raw error object thrown by the backend, when [status] is `failed`.
  final Object? error;

  /// Stringified error for UI display, when [status] is `failed`.
  final String? errorMessage;

  const DeviceConnectProgress({
    required this.deviceType,
    required this.deviceId,
    required this.status,
    this.error,
    this.errorMessage,
  });

  @override
  String toString() => 'DeviceConnectProgress($deviceType=$deviceId, '
      'status=$status${errorMessage != null ? ", error=$errorMessage" : ""})';
}
