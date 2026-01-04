import 'device_types.dart';

/// Information about a discovered device
class DeviceInfo {
  final String id;
  final String name;
  final DeviceType deviceType;
  final DriverType driverType;
  final String description;
  final String driverVersion;

  const DeviceInfo({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.driverType,
    required this.description,
    required this.driverVersion,
  });

  /// Alias for backward compatibility (use driverType instead)
  @Deprecated('Use driverType instead')
  DriverType get backend => driverType;

  /// Alias for backward compatibility (use deviceType instead)
  @Deprecated('Use deviceType instead')
  DeviceType get type => deviceType;

  /// Create from JSON (for network transport)
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      deviceType: DeviceType.values.firstWhere(
        (e) => e.name == json['deviceType'],
        orElse: () => DeviceType.camera,
      ),
      driverType: DriverType.values.firstWhere(
        (e) => e.name == json['driverType'],
        orElse: () => DriverType.simulator,
      ),
      description: json['description'] as String? ?? '',
      driverVersion: json['driverVersion'] as String? ?? '',
    );
  }

  /// Convert to JSON (for network transport)
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'deviceType': deviceType.name,
        'driverType': driverType.name,
        'description': description,
        'driverVersion': driverVersion,
      };

  @override
  String toString() => 'DeviceInfo($name, $deviceType, $driverType)';
}
