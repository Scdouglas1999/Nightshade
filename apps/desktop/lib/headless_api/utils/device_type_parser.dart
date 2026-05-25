import 'package:nightshade_core/nightshade_core.dart';

/// Parse a device-type string (case-insensitive) into [DeviceType], or
/// null if no match. Mirrors the wire-format convention used by the
/// connect-device handler.
DeviceType? parseDeviceType(String value) {
  final normalized = value.toLowerCase();
  for (final dt in DeviceType.values) {
    if (dt.name.toLowerCase() == normalized) {
      return dt;
    }
  }
  return null;
}

/// Pipe-separated list of valid device-type names, suitable for
/// embedding in a [BadRequestError.expected] field.
String validDeviceTypeList() => DeviceType.values.map((d) => d.name).join('|');
