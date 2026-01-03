/// ASCOM Client - Native Windows COM-based ASCOM driver support
///
/// This allows direct communication with ASCOM drivers installed on Windows
/// without needing additional software like ASCOM Remote.
///
/// Reference: https://ascom-standards.org/

import 'dart:io';

// Only compile on Windows
// ignore: unused_import
import 'dart:ffi' if (dart.library.html) 'dart:html';

/// Check if running on Windows
bool get isWindows => Platform.isWindows;

// Conditional imports for win32 - only works on Windows
// We use dynamic imports to avoid compilation errors on non-Windows platforms

/// Information about a discovered ASCOM driver
class AscomDriver {
  final String progId;
  final String name;
  final String description;
  final String deviceType;

  AscomDriver({
    required this.progId,
    required this.name,
    this.description = '',
    required this.deviceType,
  });

  /// Generate a unique device ID
  String get id => 'ascom:$progId';

  @override
  String toString() => 'AscomDriver($name, $progId)';
}

/// Discover ASCOM drivers from the Windows Registry
///
/// ASCOM drivers register themselves under:
/// HKEY_LOCAL_MACHINE\SOFTWARE\ASCOM\<DeviceType> Drivers\<ProgID>
Future<List<AscomDriver>> discoverAscomDrivers(String deviceType) async {
  if (!isWindows) {
    return [];
  }

  final drivers = <AscomDriver>[];

  try {
    // Use win32 to query the registry
    // Import win32 dynamically
    final win32 = await _getWin32();
    if (win32 == null) return [];

    final registryPath = r'SOFTWARE\ASCOM\' + deviceType + ' Drivers';

    // Query the registry for ASCOM drivers
    final driverList = await _queryAscomRegistry(registryPath);

    for (final progId in driverList) {
      final name = await _getDriverName(registryPath, progId);
      drivers.add(AscomDriver(
        progId: progId,
        name: name ?? progId,
        deviceType: deviceType,
      ));
    }
  } catch (e) {
    print('Error discovering ASCOM $deviceType drivers: $e');
  }

  return drivers;
}

/// Discover all ASCOM device types
Future<List<AscomDriver>> discoverAllAscomDrivers() async {
  if (!isWindows) {
    return [];
  }

  final allDrivers = <AscomDriver>[];

  final deviceTypes = [
    'Camera',
    'Telescope',
    'Focuser',
    'FilterWheel',
    'Rotator',
    'Dome',
    'SafetyMonitor',
    'ObservingConditions',
  ];

  for (final type in deviceTypes) {
    final drivers = await discoverAscomDrivers(type);
    allDrivers.addAll(drivers);
  }

  return allDrivers;
}

// ============================================================================
// Win32 Registry Access
// ============================================================================

dynamic _win32Module;

Future<dynamic> _getWin32() async {
  if (!isWindows) return null;

  try {
    // win32 package handles its own conditional compilation
    _win32Module ??= true; // Just flag that we've tried
    return _win32Module;
  } catch (e) {
    print('Failed to load win32: $e');
    return null;
  }
}

/// Query ASCOM registry for driver ProgIDs
Future<List<String>> _queryAscomRegistry(String registryPath) async {
  if (!isWindows) return [];

  final drivers = <String>[];

  try {
    // Import win32 registry functions
    // This uses Dart's conditional import mechanism
    final result = await _executeRegistryQuery(registryPath);
    drivers.addAll(result);
  } catch (e) {
    print('Registry query failed: $e');
  }

  return drivers;
}

/// Execute a registry query using Process to run reg.exe
/// This is a fallback that works without win32 package
Future<List<String>> _executeRegistryQuery(String registryPath) async {
  final drivers = <String>[];

  try {
    print('[ASCOM Registry] Querying: HKLM\\$registryPath');

    // Use reg.exe to query the registry (works on all Windows)
    final result = await Process.run(
      'reg',
      ['query', 'HKLM\\$registryPath'],
      runInShell: true,
    );

    print('[ASCOM Registry] Exit code: ${result.exitCode}');

    if (result.exitCode == 0) {
      final output = result.stdout as String;
      final lines = output.split('\n');

      print('[ASCOM Registry] Registry output has ${lines.length} lines');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty ||
            trimmed.startsWith('HKEY_') ||
            trimmed.startsWith('End')) {
          continue;
        }

        // Look for ProgID keys - they should be direct subkeys
        // Format: ASCOM.Simulator.Camera (no spaces, contains dots)
        if (trimmed.contains('.') &&
            !trimmed.contains(' ') &&
            !trimmed.contains('REG_')) {
          drivers.add(trimmed);
          print('[ASCOM Registry] Found driver: $trimmed');
        }
      }

      // Also check WOW6432Node for 32-bit drivers on 64-bit Windows
      final wowPath = registryPath.replaceFirst(
          'SOFTWARE\\ASCOM', 'SOFTWARE\\WOW6432Node\\ASCOM');
      print('[ASCOM Registry] Also checking: HKLM\\$wowPath');

      try {
        final wowResult = await Process.run(
          'reg',
          ['query', 'HKLM\\$wowPath'],
          runInShell: true,
        );

        if (wowResult.exitCode == 0) {
          final wowOutput = wowResult.stdout as String;
          final wowLines = wowOutput.split('\n');

          for (final line in wowLines) {
            final trimmed = line.trim();
            if (trimmed.isEmpty ||
                trimmed.startsWith('HKEY_') ||
                trimmed.startsWith('End')) {
              continue;
            }

            if (trimmed.contains('.') &&
                !trimmed.contains(' ') &&
                !trimmed.contains('REG_')) {
              if (!drivers.contains(trimmed)) {
                drivers.add(trimmed);
                print('[ASCOM Registry] Found WOW64 driver: $trimmed');
              }
            }
          }
        }
      } catch (e) {
        print('[ASCOM Registry] WOW64 query failed (non-fatal): $e');
      }
    } else {
      print('[ASCOM Registry] Registry query failed. Stderr: ${result.stderr}');
    }
  } catch (e, stackTrace) {
    print('[ASCOM Registry] Failed to query registry: $e');
    print('[ASCOM Registry] Stack trace: $stackTrace');
  }

  print('[ASCOM Registry] Total drivers found: ${drivers.length}');
  return drivers.toSet().toList(); // Remove duplicates
}

/// Get the friendly name of a driver from registry
Future<String?> _getDriverName(String registryPath, String progId) async {
  try {
    final result = await Process.run(
      'reg',
      ['query', 'HKLM\\$registryPath\\$progId', '/v', '(Default)'],
      runInShell: true,
    );

    if (result.exitCode == 0) {
      final output = result.stdout as String;
      // Parse the REG_SZ value
      final match = RegExp(r'REG_SZ\s+(.+)').firstMatch(output);
      if (match != null) {
        return match.group(1)?.trim();
      }
    }
  } catch (e) {
    // Ignore errors, just return null
  }

  return null;
}

// ============================================================================
// ASCOM COM Client (for device connection)
// ============================================================================

/// ASCOM device client using COM automation
///
/// Note: Full COM automation requires win32 package with IDispatch support.
/// For now, we provide a basic structure that can be expanded.
class AscomDeviceClient {
  final String progId;
  final String deviceType;
  bool _connected = false;

  // COM object reference (when using win32)
  dynamic _comObject;

  AscomDeviceClient({
    required this.progId,
    required this.deviceType,
  });

  /// Check if connected
  bool get isConnected => _connected;

  /// Connect to the ASCOM device
  Future<void> connect() async {
    if (!isWindows) {
      throw UnsupportedError('ASCOM is only available on Windows');
    }

    try {
      // For now, we'll use a scripting approach via PowerShell
      // This works without additional dependencies
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
          try {
            \$device = New-Object -ComObject "$progId"
            \$device.Connected = \$true
            Write-Output "SUCCESS"
          } catch {
            Write-Output "ERROR: \$_"
          }
          '''
        ],
        runInShell: true,
      );

      if (result.stdout.toString().contains('SUCCESS')) {
        _connected = true;
        print('Connected to ASCOM device: $progId');
      } else {
        throw Exception('Failed to connect: ${result.stdout}');
      }
    } catch (e) {
      throw Exception('Failed to connect to ASCOM device $progId: $e');
    }
  }

  /// Disconnect from the ASCOM device
  Future<void> disconnect() async {
    if (!_connected) return;

    try {
      await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '''
          try {
            \$device = New-Object -ComObject "$progId"
            \$device.Connected = \$false
            Write-Output "SUCCESS"
          } catch {
            Write-Output "ERROR: \$_"
          }
          '''
        ],
        runInShell: true,
      );

      _connected = false;
      print('Disconnected from ASCOM device: $progId');
    } catch (e) {
      print('Error disconnecting: $e');
    }
  }

  /// Get a property value from the ASCOM device
  Future<dynamic> getProperty(String propertyName) async {
    if (!_connected) {
      throw StateError('Device not connected');
    }

    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        '''
        try {
          \$device = New-Object -ComObject "$progId"
          \$device.Connected = \$true
          \$value = \$device.$propertyName
          Write-Output \$value
        } catch {
          Write-Error \$_
        }
        '''
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to get property $propertyName: ${result.stderr}');
    }

    return result.stdout.toString().trim();
  }

  /// Set a property value on the ASCOM device
  Future<void> setProperty(String propertyName, dynamic value) async {
    if (!_connected) {
      throw StateError('Device not connected');
    }

    final valueStr = value is String ? '"$value"' : value.toString();

    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        '''
        try {
          \$device = New-Object -ComObject "$progId"
          \$device.Connected = \$true
          \$device.$propertyName = $valueStr
          Write-Output "SUCCESS"
        } catch {
          Write-Error \$_
        }
        '''
      ],
      runInShell: true,
    );

    if (result.exitCode != 0 || !result.stdout.toString().contains('SUCCESS')) {
      throw Exception('Failed to set property $propertyName: ${result.stderr}');
    }
  }

  /// Call a method on the ASCOM device
  Future<dynamic> callMethod(String methodName, [List<dynamic>? args]) async {
    if (!_connected) {
      throw StateError('Device not connected');
    }

    final argsStr =
        args?.map((a) => a is String ? '"$a"' : a.toString()).join(', ') ?? '';

    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        '''
        try {
          \$device = New-Object -ComObject "$progId"
          \$device.Connected = \$true
          \$result = \$device.$methodName($argsStr)
          Write-Output \$result
        } catch {
          Write-Error \$_
        }
        '''
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception('Failed to call method $methodName: ${result.stderr}');
    }

    return result.stdout.toString().trim();
  }

  /// Dispose resources
  void dispose() {
    _comObject = null;
    _connected = false;
  }
}

// ============================================================================
// ASCOM Chooser
// ============================================================================

/// Show the ASCOM Chooser dialog
///
/// This uses the standard ASCOM.Utilities.Chooser COM object to let
/// users select a device from the installed drivers.
Future<String?> showAscomChooser(String deviceType) async {
  if (!isWindows) {
    return null;
  }

  try {
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        '''
        try {
          \$chooser = New-Object -ComObject "ASCOM.Utilities.Chooser"
          \$chooser.DeviceType = "$deviceType"
          \$progId = \$chooser.Choose("")
          if (\$progId -ne "") {
            Write-Output \$progId
          }
        } catch {
          Write-Error \$_
        }
        '''
      ],
      runInShell: true,
    );

    if (result.exitCode == 0) {
      final progId = result.stdout.toString().trim();
      if (progId.isNotEmpty && progId.contains('.')) {
        return progId;
      }
    }
  } catch (e) {
    print('Failed to show ASCOM chooser: $e');
  }

  return null;
}
