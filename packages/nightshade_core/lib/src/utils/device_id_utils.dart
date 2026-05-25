/// Device-ID format validation.
///
/// DEV-P1-7: connect methods on [DeviceService] previously ran a full
/// `discoverDevices(type)` sweep before every connect attempt and rejected
/// any id that wasn't in the result list with `"Camera not found: $id"`.
/// That meant a reconnect of a known-good device would fail whenever the
/// last discovery transient hadn't yet refreshed — typical after a USB
/// hub blip or after switching backends. The user already knows what they
/// want to connect; the backend is the only source of truth for whether
/// the device is actually reachable. So we replace the discovery
/// precondition with a cheap format check here.
///
/// Format check is intentionally narrow: it only confirms the id matches
/// one of Nightshade's known driver-prefix conventions. It does NOT
/// validate that the device exists, is reachable, or is the right kind of
/// device — those are the backend's job, and their failures must still
/// surface from `connectDevice`.
library;

/// Known device-id prefixes used by every Nightshade driver layer.
///
/// Format conventions (see CLAUDE.md "Device IDs"):
///   - `ascom:<prog_id>`                       (Windows ASCOM COM driver)
///   - `alpaca:<host:port:device_number>`      (cross-platform ASCOM HTTP)
///   - `indi:<host:port:device_name>`          (Linux/macOS INDI server)
///   - `native:<vendor>:<id>[:...]`            (native vendor SDKs incl.
///                                              `native:builtin_guider:...`,
///                                              `native:touptek:<brand>:<idx>`)
///   - `simulator:...`                          (in-process simulators)
///
/// Plus two single-name special cases for the PHD2 / built-in guider that
/// callers may pass without a colon-prefix:
///   - `phd2`, `phd2_guider`                   (PHD2 socket guider)
///   - `builtin_guider`                         (legacy alias before the
///                                               full `native:builtin_guider:...`
///                                               id became canonical)
const List<String> kKnownDeviceIdPrefixes = <String>[
  'ascom:',
  'alpaca:',
  'indi:',
  'native:',
  'simulator:',
  'phd2:',
  'phd2://',
];

/// Single-token device ids that are accepted without a colon prefix.
const List<String> kKnownDeviceIdSingletons = <String>[
  'phd2',
  'phd2_guider',
  'builtin_guider',
];

/// Returns `true` if [deviceId] looks like a Nightshade-formatted device id.
///
/// The check is purely structural. It does NOT confirm the device exists
/// — that is the backend's responsibility, and a malformed id is the only
/// case where we want to fail before bothering the backend.
bool isValidDeviceIdFormat(String deviceId) {
  if (deviceId.isEmpty) return false;
  if (kKnownDeviceIdSingletons.contains(deviceId)) return true;
  for (final prefix in kKnownDeviceIdPrefixes) {
    if (deviceId.startsWith(prefix) && deviceId.length > prefix.length) {
      return true;
    }
  }
  return false;
}
