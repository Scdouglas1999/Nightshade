part of '../bridge_stub.dart';

extension _NativeBridgeConnectionOperations on _NativeBridgeImplementation {
  // =========================================================================
  // Device Connection
  // =========================================================================

  DriverType? _inferDriverTypeFromDeviceId(String deviceId) {
    if (deviceId.startsWith('ascom:')) return DriverType.ascom;
    if (deviceId.startsWith('alpaca:')) return DriverType.alpaca;
    if (deviceId.startsWith('indi:')) return DriverType.indi;
    if (deviceId.startsWith('native:')) return DriverType.native;
    if (deviceId.startsWith('sim:') || deviceId.startsWith('simulator:')) {
      return DriverType.simulator;
    }
    return null;
  }

  void _recordConnectedDevice({
    required DeviceType deviceType,
    required String deviceId,
    DriverType? driverType,
    String? name,
    String? displayName,
    String? description,
    String? driverVersion,
  }) {
    _connectedDevices[deviceId] = true;

    final resolvedDriverType =
        driverType ?? _inferDriverTypeFromDeviceId(deviceId);
    if (resolvedDriverType == null) {
      developer.log(
        '[Bridge] Connected device "$deviceId" has no inferable driver type; omitting from fallback connected-device metadata.',
        name: 'NativeBridge',
        level: 900,
      );
      _connectedDeviceInfo.remove(deviceId);
      return;
    }

    final resolvedName = name ?? deviceId;
    _connectedDeviceInfo[deviceId] = DeviceInfo(
      id: deviceId,
      name: resolvedName,
      deviceType: deviceType,
      driverType: resolvedDriverType,
      description: description ?? 'Connected device',
      driverVersion: driverVersion ?? 'unknown',
      displayName: displayName ?? resolvedName,
    );
  }

  /// Connect to a device
  Future<void> connectDevice(DeviceType deviceType, String deviceId) async {
    // Check if this is PHD2 (supports new format: phd2:host:port or legacy: phd2)
    if (_isPhd2DeviceId(deviceId)) {
      String? host;
      int? port;

      if (deviceId.startsWith('phd2://')) {
        final uri = Uri.tryParse(deviceId);
        host = uri?.host;
        port = uri?.port == 0 ? null : uri?.port;
      } else if (deviceId.startsWith('phd2:')) {
        // Parse phd2:host:port format
        final parts = deviceId.split(':');
        if (parts.length >= 3) {
          host = parts[1];
          port = int.tryParse(parts[2]) ?? 4400;
        }
      }

      await phd2Connect(host: host, port: port);
      _recordConnectedDevice(
        deviceType: deviceType,
        deviceId: 'phd2_guider',
        driverType: DriverType.native,
        name: 'PHD2',
        displayName: 'PHD2',
        description: 'PHD2 Guiding',
        driverVersion: 'external',
      );
      return;
    }

    // =========================================================================
    // Try Native Bridge Connection First (for ASCOM, native, Alpaca, INDI)
    // =========================================================================
    // For devices discovered by native bridge (ascom:, native:, indi:),
    // always use native bridge connection. For other devices (alpaca:),
    // try native bridge first but fall back to the fallback path if needed.
    final shouldUseNativeOnly =
        deviceId.startsWith('ascom:') ||
        deviceId.startsWith('native:') ||
        deviceId.startsWith('indi:');

    if (_nativeAvailable) {
      try {
        developer.log(
          '[Bridge] Attempting native connection for $deviceId...',
          name: 'NativeBridge',
          level: 800,
        );
        final genDeviceType = _toGenDeviceType(deviceType);
        await gen_api.apiConnectDevice(
          deviceType: genDeviceType,
          deviceId: deviceId,
        );
        developer.log(
          '[Bridge] âœ“ Successfully connected to $deviceId via native bridge',
          name: 'NativeBridge',
          level: 800,
        );

        _recordConnectedDevice(deviceType: deviceType, deviceId: deviceId);

        // Emit connection event
        _eventController.add(
          _FallbackNightshadeEvent(
            timestamp: DateTime.now().millisecondsSinceEpoch,
            severity: EventSeverity.info,
            category: EventCategory.equipment,
            eventType: 'Connected',
            data: {'deviceType': deviceType.name, 'deviceId': deviceId},
          ),
        );

        return; // Success - native bridge handled it
      } catch (e, stackTrace) {
        developer.log(
          '[Bridge] âœ— Native connection failed for $deviceId',
          name: 'NativeBridge',
          level: 1000,
          error: e,
          stackTrace: stackTrace,
        );

        // If this device must use native bridge (was discovered by it),
        // don't fall back - throw the error
        if (shouldUseNativeOnly) {
          throw Exception(
            'Failed to connect to $deviceId via native bridge: $e',
          );
        }

        developer.log(
          '[Bridge] Device supports fallback - trying fallback methods...',
          name: 'NativeBridge',
          level: 900,
        );
        // Continue to fallback bridge methods below
      }
    } else if (shouldUseNativeOnly) {
      // Native bridge required but not available
      throw Exception(
        'Cannot connect to $deviceId: Native bridge required but not available',
      );
    }

    // =========================================================================
    // Fallback Connection Methods (for when native bridge unavailable)
    // =========================================================================

    // Check if this is an Alpaca device
    if (deviceId.startsWith('alpaca:')) {
      await _connectAlpacaDevice(deviceType, deviceId);
      return;
    }

    // Check if this is an ASCOM device
    if (deviceId.startsWith('ascom:')) {
      await _connectAscomDevice(deviceType, deviceId);
      return;
    }

    // Unknown device type - can't connect
    throw Exception(
      'Unknown device: $deviceId. No ASCOM/Alpaca devices found.',
    );
  }

  /// Connect to an ASCOM device
  Future<void> _connectAscomDevice(
    DeviceType deviceType,
    String deviceId,
  ) async {
    if (!Platform.isWindows) {
      throw Exception('ASCOM is only available on Windows');
    }

    // Parse the device ID: ascom:ProgID
    final progId = deviceId.substring(6); // Remove "ascom:"

    final ascomType = _deviceTypeToAscomType(deviceType);
    if (ascomType == null) {
      throw Exception('Unsupported device type for ASCOM: $deviceType');
    }

    final client = ascom.AscomDeviceClient(
      progId: progId,
      deviceType: ascomType,
    );

    try {
      developer.log(
        '[ASCOM] Connecting to device: $progId',
        name: 'NativeBridge',
        level: 800,
      );
      await client.connect();

      _ascomClients[deviceId] = client;
      _recordConnectedDevice(
        deviceType: deviceType,
        deviceId: deviceId,
        driverType: DriverType.ascom,
      );

      _eventController.add(
        _FallbackNightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.equipment,
          eventType: 'Connected',
          data: {'deviceType': deviceType.name, 'deviceId': deviceId},
        ),
      );

      developer.log(
        '[ASCOM] Connected to device: $progId',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      client.dispose();
      throw Exception('Failed to connect to ASCOM device: $e');
    }
  }

  /// Connect to an Alpaca device
  Future<void> _connectAlpacaDevice(
    DeviceType deviceType,
    String deviceId,
  ) async {
    // Parse the device ID. Discovery emits the canonical form
    //   alpaca:{protocol}://{host}:{port}:{type}:{num}
    // (e.g. alpaca:http://127.0.0.1:32323:telescope:0), matching the Rust
    // `parse_alpaca`. An older form `alpaca:host:port/type/number` is still
    // accepted for backward compatibility. Previously this only handled the
    // legacy slash form, so a canonical id split on '/' yielded host="http"
    // (the protocol token), port=11111 (default), and an empty device type —
    // producing the broken URL `http://http:11111/api/v1//0/connected` and
    // failing every Alpaca connection.
    final remainder = deviceId.substring(7); // Remove "alpaca:"
    final String host;
    final int port;
    final String deviceTypeName;
    final int deviceNumber;

    if (remainder.contains('://')) {
      // Canonical: protocol://host:port:type:num (colon-separated).
      final afterProtocol = remainder.split('://').last;
      final segs = afterProtocol.split(':');
      if (segs.length < 4) {
        throw Exception('Invalid Alpaca device ID: $deviceId');
      }
      // type and number are the last two segments; host:port are the first two.
      // (Reading from the ends tolerates a host that itself contains extra
      // colons, e.g. a future IPv6 literal.)
      host = segs[0];
      port = int.tryParse(segs[1]) ?? 11111;
      deviceTypeName = segs[segs.length - 2];
      deviceNumber = int.tryParse(segs[segs.length - 1]) ?? 0;
    } else {
      // Legacy: host:port/type/number (slash-separated type/number).
      final parts = remainder.split('/');
      if (parts.length < 3) {
        throw Exception('Invalid Alpaca device ID: $deviceId');
      }
      final hostPort = parts[0].split(':');
      if (hostPort.length != 2) {
        throw Exception('Invalid Alpaca device ID: $deviceId');
      }
      host = hostPort[0];
      port = int.tryParse(hostPort[1]) ?? 11111;
      deviceTypeName = parts[1];
      deviceNumber = int.tryParse(parts[2]) ?? 0;
    }

    final server = alpaca.AlpacaServer(host: host, port: port);
    final alpacaDevice = alpaca.AlpacaDevice(
      deviceName: 'Alpaca Device',
      deviceType: deviceTypeName,
      deviceNumber: deviceNumber,
      uniqueId: deviceId,
      server: server,
    );

    // Create appropriate client based on device type
    alpaca.AlpacaClient client;
    switch (deviceType) {
      case DeviceType.camera:
      case DeviceType.guider:
        client = alpaca.AlpacaCameraClient(alpacaDevice);
        break;
      case DeviceType.mount:
        client = alpaca.AlpacaMountClient(alpacaDevice);
        break;
      case DeviceType.focuser:
        client = alpaca.AlpacaFocuserClient(alpacaDevice);
        break;
      case DeviceType.filterWheel:
        client = alpaca.AlpacaFilterWheelClient(alpacaDevice);
        break;
      default:
        client = alpaca.AlpacaClient(alpacaDevice);
    }

    try {
      developer.log(
        '[Alpaca] Connecting to device: $deviceId',
        name: 'NativeBridge',
        level: 800,
      );
      await client.connect();

      _alpacaClients[deviceId] = client;
      _alpacaDevices[deviceId] = alpacaDevice;
      _recordConnectedDevice(
        deviceType: deviceType,
        deviceId: deviceId,
        driverType: DriverType.alpaca,
        name: alpacaDevice.deviceName,
        displayName: alpacaDevice.deviceName,
      );

      _eventController.add(
        _FallbackNightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.equipment,
          eventType: 'Connected',
          data: {'deviceType': deviceType.name, 'deviceId': deviceId},
        ),
      );

      developer.log(
        '[Alpaca] Connected to device: $deviceId',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      client.dispose();
      throw Exception('Failed to connect to Alpaca device: $e');
    }
  }

  /// Disconnect from a device
  Future<void> disconnectDevice(DeviceType deviceType, String deviceId) async {
    // Handle PHD2 disconnection (supports new format: phd2:host:port or legacy: phd2)
    var disconnectedByAuthoritativeBackend = false;
    if (_isPhd2DeviceId(deviceId)) {
      await phd2Disconnect();
      disconnectedByAuthoritativeBackend = true;
    }

    // Native-backed connects are authoritative in Rust, so their matching
    // disconnect must cross the same FFI boundary. Previously this method
    // only deleted the Dart fallback bookkeeping below. The UI and headless
    // endpoint therefore reported success while `api_get_connected_devices`
    // still returned every device and the native drivers stayed open.
    //
    // Alpaca is the sole device family that may fall back to the direct Dart
    // client after a native connect attempt fails. For it, a native
    // "not registered" error is expected and we continue to the direct
    // client cleanup. Every other native-available path must surface a Rust
    // disconnect failure instead of claiming success.
    if (_nativeAvailable && !disconnectedByAuthoritativeBackend) {
      try {
        await gen_api.apiDisconnectDevice(
          deviceType: _toGenDeviceType(deviceType),
          deviceId: deviceId,
        );
        disconnectedByAuthoritativeBackend = true;
      } catch (error, stackTrace) {
        if (!deviceId.startsWith('alpaca:')) {
          developer.log(
            '[Bridge] Native disconnect failed for $deviceId',
            name: 'NativeBridge',
            level: 1000,
            error: error,
            stackTrace: stackTrace,
          );
          rethrow;
        }
        developer.log(
          '[Bridge] Alpaca device $deviceId was not owned by the native '
          'backend; using the direct Dart client cleanup.',
          name: 'NativeBridge',
          level: 800,
        );
      }
    }

    // Handle Alpaca device disconnection
    if (!disconnectedByAuthoritativeBackend && deviceId.startsWith('alpaca:')) {
      final client = _alpacaClients[deviceId];
      if (client != null) {
        try {
          await client.disconnect();
        } catch (e) {
          developer.log(
            '[Alpaca] Error disconnecting device: $e',
            name: 'NativeBridge',
            level: 1000,
          );
        }
        client.dispose();
        _alpacaClients.remove(deviceId);
        _alpacaDevices.remove(deviceId);
      }
    }

    // Handle ASCOM device disconnection
    if (!disconnectedByAuthoritativeBackend && deviceId.startsWith('ascom:')) {
      final client = _ascomClients[deviceId];
      if (client != null) {
        try {
          await client.disconnect();
        } catch (e) {
          developer.log(
            '[ASCOM] Error disconnecting device: $e',
            name: 'NativeBridge',
            level: 1000,
          );
        }
        client.dispose();
        _ascomClients.remove(deviceId);
      }
    }

    _connectedDevices.remove(deviceId);
    _connectedDeviceInfo.remove(deviceId);

    _eventController.add(
      _FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'Disconnected',
        data: {'deviceType': deviceType.name, 'deviceId': deviceId},
      ),
    );
  }

  /// Get list of connected devices
  Future<List<DeviceInfo>> getConnectedDevices() async {
    // If native bridge is available, use it to get authoritative connected devices list
    if (_nativeAvailable) {
      try {
        final nativeDevices = await gen_api.apiGetConnectedDevices();
        // Sync our local tracking with native state
        _connectedDevices.clear();
        _connectedDeviceInfo.clear();
        for (final device in nativeDevices) {
          _recordConnectedDevice(
            deviceType: _fromGenDeviceType(device.deviceType),
            deviceId: device.id,
            driverType: _fromGenDriverType(device.driverType),
            name: device.name,
            displayName: device.displayName,
            description: device.description,
            driverVersion: device.driverVersion,
          );
        }
        return nativeDevices;
      } catch (e) {
        developer.log(
          '[Bridge] Warning: Failed to get connected devices from native API: $e',
          name: 'NativeBridge',
          level: 900,
        );
        // Fall through to fallback implementation
      }
    }

    // Fallback: return only explicitly tracked metadata captured at connection time.
    return _connectedDeviceInfo.values.toList(growable: false);
  }
}
