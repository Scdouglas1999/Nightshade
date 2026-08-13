part of '../bridge_stub.dart';

extension _NativeBridgeDiscoveryOperations on _NativeBridgeImplementation {
  // =========================================================================
  // Device Discovery
  // =========================================================================

  /// Discover available devices of a specific type.
  ///
  /// This queries:
  /// 1. Native bridge (if available) - includes ASCOM, native ZWO, Alpaca, etc.
  /// 2. Real ASCOM drivers from Windows Registry (Windows only, fallback)
  /// 3. Real Alpaca devices on the network via HTTP (cross-platform)
  /// 4. PHD2 instances on the local network (guider type only)
  ///
  /// Results are cached for 60 seconds. Call [invalidateDiscoveryCache] to
  /// force a fresh discovery. A single sweep discovers ALL device types so
  /// that concurrent callers (e.g. 5 parallel calls at startup) share one
  /// network scan instead of each launching their own.
  Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType) async {
    // Fast path: return from cache if still valid for this type
    final now = DateTime.now();
    if (_discoveryCacheTime != null &&
        now.difference(_discoveryCacheTime!) < _discoveryCacheTtl &&
        _discoveryCache.containsKey(deviceType)) {
      return List.unmodifiable(_discoveryCache[deviceType]!);
    }

    // If a sweep is already running, wait for it and then return cached result
    if (_discoverySweepInProgress != null) {
      await _discoverySweepInProgress!.future;
      // After the sweep, result should be in cache
      if (_discoveryCache.containsKey(deviceType)) {
        return List.unmodifiable(_discoveryCache[deviceType]!);
      }
      // Sweep finished but didn't populate this type (shouldn't happen, but
      // return empty rather than silently looping)
      return const [];
    }

    // We are the first caller â€” run a full sweep for ALL device types
    final sweepCompleter = Completer<void>();
    _discoverySweepInProgress = sweepCompleter;

    try {
      await _runFullDiscoverySweep();
    } finally {
      _discoverySweepInProgress = null;
      sweepCompleter.complete();
    }

    return List.unmodifiable(_discoveryCache[deviceType] ?? const []);
  }

  /// Run a single discovery sweep that populates [_discoveryCache] for every
  /// [DeviceType]. This is called at most once per cache TTL window.
  Future<void> _runFullDiscoverySweep() async {
    // Prepare empty lists for every device type
    final allDevices = <DeviceType, List<DeviceInfo>>{};
    for (final dt in DeviceType.values) {
      allDevices[dt] = <DeviceInfo>[];
    }

    // =========================================================================
    // 1. Native Bridge Discovery (includes ASCOM, native ZWO, Alpaca, etc.)
    // =========================================================================
    if (_nativeAvailable) {
      // Discover all types in parallel through native bridge
      final futures = <Future<void>>[];
      for (final dt in DeviceType.values) {
        futures.add(() async {
          try {
            final genDeviceType = _toGenDeviceType(dt);
            final nativeDevices = await gen_api.apiDiscoverDevices(
              deviceType: genDeviceType,
            );

            for (final nativeDev in nativeDevices) {
              allDevices[dt]!.add(
                DeviceInfo(
                  id: nativeDev.id,
                  name: nativeDev.name,
                  deviceType: _fromGenDeviceType(nativeDev.deviceType),
                  driverType: _fromGenDriverType(nativeDev.driverType),
                  description: nativeDev.description,
                  driverVersion: nativeDev.driverVersion,
                  displayName: nativeDev.displayName,
                ),
              );
            }
          } catch (e) {
            if (!e.toString().contains('RustLib') &&
                !e.toString().contains('not initialized')) {
              developer.log(
                '[Discovery] Native discovery error for ${dt.displayName}: $e',
                name: 'NativeBridge',
                level: 900,
              );
            }
          }
        }());
      }
      await Future.wait(futures);
    }

    // =========================================================================
    // 2. Fallback: ASCOM Discovery (Windows only, direct COM via Registry)
    //    Only used when native bridge is unavailable.
    // =========================================================================
    if (!_nativeAvailable && Platform.isWindows) {
      for (final dt in DeviceType.values) {
        try {
          final ascomType = _deviceTypeToAscomType(dt);
          if (ascomType != null) {
            final ascomDrivers = await ascom.discoverAscomDrivers(ascomType);
            for (final driver in ascomDrivers) {
              allDevices[dt]!.add(
                DeviceInfo(
                  id: driver.id,
                  name: driver.name,
                  deviceType: dt,
                  driverType: DriverType.ascom,
                  description: 'ASCOM driver: ${driver.progId}',
                  driverVersion: 'ASCOM',
                  displayName: driver.name,
                ),
              );
            }
          }
        } catch (e) {
          developer.log(
            '[Discovery] ASCOM fallback discovery failed for ${dt.displayName}: $e',
            name: 'NativeBridge',
            level: 900,
          );
        }
      }
    } else if (!Platform.isWindows && !_ascomNotWindowsWarned) {
      developer.log(
        '[Discovery] ASCOM not available (non-Windows platform)',
        name: 'NativeBridge',
        level: 800,
      );
      _ascomNotWindowsWarned = true;
    }

    if (!_nativeAvailable) {
      // =======================================================================
      // 3. Alpaca Discovery (cross-platform, single UDP broadcast for all types)
      // =======================================================================
      try {
        final alpacaDevices = await alpaca.discoverAllAlpacaDevices(
          timeout: const Duration(seconds: 2),
        );

        for (final device in alpacaDevices) {
          for (final dt in DeviceType.values) {
            if (_alpacaTypeMatches(device.deviceType, dt)) {
              allDevices[dt]!.add(
                DeviceInfo(
                  id: device.id,
                  name: device.deviceName,
                  deviceType: dt,
                  driverType: DriverType.alpaca,
                  description:
                      'Alpaca device at ${device.server.host}:${device.server.port}',
                  driverVersion: 'Alpaca',
                  displayName: device.deviceName,
                ),
              );
            }
          }
        }
      } catch (e) {
        developer.log(
          '[Discovery] Alpaca discovery failed: $e',
          name: 'NativeBridge',
          level: 900,
        );
      }

      // =======================================================================
      // 4. PHD2 Discovery (guider type only)
      // =======================================================================
      try {
        final phd2Instances = await _discoverPhd2Instances();

        if (phd2Instances.isNotEmpty) {
          allDevices[DeviceType.guider]!.add(
            const DeviceInfo(
              id: 'phd2_guider',
              name: 'PHD2 Guiding',
              deviceType: DeviceType.guider,
              driverType: DriverType.native,
              description: 'PHD2 autoguiding software',
              driverVersion: '2.6+',
              displayName: 'PHD2 Guiding',
            ),
          );
        }
      } catch (e) {
        developer.log(
          '[Discovery] PHD2 discovery failed: $e',
          name: 'NativeBridge',
          level: 900,
        );
      }
    }

    // =========================================================================
    // Populate cache and print a single summary line
    // =========================================================================
    for (final devices in allDevices.values) {
      final seenIds = <String>{};
      devices.removeWhere((device) => !seenIds.add(device.id));
    }

    _discoveryCache.clear();
    _discoveryCache.addAll(allDevices);
    _discoveryCacheTime = DateTime.now();

    // Build a compact summary of non-empty types
    final parts = <String>[];
    for (final dt in DeviceType.values) {
      final count = allDevices[dt]!.length;
      if (count > 0) {
        parts.add(
          '$count ${dt.displayName.toLowerCase()}${count == 1 ? '' : 's'}',
        );
      }
    }
    if (parts.isNotEmpty) {
      developer.log(
        '[Discovery] Complete: ${parts.join(', ')}',
        name: 'NativeBridge',
        level: 800,
      );
    } else {
      developer.log(
        '[Discovery] Complete: no devices found',
        name: 'NativeBridge',
        level: 800,
      );
    }
  }

  /// Convert DeviceType to ASCOM device type string
  String? _deviceTypeToAscomType(DeviceType deviceType) {
    switch (deviceType) {
      case DeviceType.camera:
        return 'Camera';
      case DeviceType.mount:
        return 'Telescope';
      case DeviceType.focuser:
        return 'Focuser';
      case DeviceType.filterWheel:
        return 'FilterWheel';
      case DeviceType.guider:
        return 'Camera'; // Guider cameras use Camera type
      case DeviceType.rotator:
        return 'Rotator';
      case DeviceType.dome:
        return 'Dome';
      case DeviceType.weather:
        return 'ObservingConditions';
      case DeviceType.safetyMonitor:
        return 'SafetyMonitor';
      case DeviceType.switch_:
        return 'Switch';
      case DeviceType.coverCalibrator:
        return 'CoverCalibrator';
    }
  }

  /// Discover PHD2 instances on the network
  /// Checks if PHD2 is installed (always shows it if installed, even if not running)
  /// Connection will launch PHD2 if it's installed but not running
  /// Also scans local subnet for remote PHD2 instances
  Future<List<Map<String, dynamic>>> _discoverPhd2Instances() async {
    final instances = <Map<String, dynamic>>[];
    const defaultPort = 4400;
    final discoveredHosts = <String>{};

    // Always check if PHD2 is installed - if it is, add it to the list
    // Connection will handle launching it if needed
    final isInstalled = await _isPhd2Installed();
    if (isInstalled) {
      instances.add({'host': 'localhost', 'port': defaultPort});
      discoveredHosts.add('localhost');
      discoveredHosts.add('127.0.0.1');
    }

    // Network subnet scanning for remote PHD2 instances
    try {
      final localIps = await _getLocalNetworkAddresses();

      for (final subnet in localIps) {
        final remoteInstances = await _scanSubnetForPhd2(subnet, defaultPort);

        for (final host in remoteInstances) {
          if (!discoveredHosts.contains(host)) {
            instances.add({'host': host, 'port': defaultPort});
            discoveredHosts.add(host);
          }
        }
      }
    } catch (e) {
      developer.log(
        '[Discovery] PHD2 network scan failed: $e',
        name: 'NativeBridge',
        level: 900,
      );
      // Continue with local instance if we found one
    }

    return instances;
  }

  /// Get local network addresses to scan
  Future<List<String>> _getLocalNetworkAddresses() async {
    final subnets = <String>[];

    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          // Extract subnet (assuming /24 network)
          final parts = ip.split('.');
          if (parts.length == 4) {
            final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            if (!subnets.contains(subnet)) {
              subnets.add(subnet);
            }
          }
        }
      }
    } catch (e) {
      developer.log(
        '[Discovery] Failed to get network interfaces: $e',
        name: 'NativeBridge',
        level: 900,
      );
    }

    return subnets;
  }

  /// Scan a subnet for PHD2 instances
  /// Scans all hosts in the subnet (xxx.xxx.xxx.1-254) on port 4400
  Future<List<String>> _scanSubnetForPhd2(String subnet, int port) async {
    final foundHosts = <String>[];
    final futures = <Future<void>>[];

    // Scan all possible host addresses in parallel (1-254)
    for (int i = 1; i <= 254; i++) {
      final host = '$subnet.$i';

      // Skip localhost (already checked)
      if (i == 1 && (subnet == '127.0.0' || subnet == '::1')) continue;

      futures.add(
        _checkPhd2AtHost(host, port)
            .then((isRunning) {
              if (isRunning) {
                foundHosts.add(host);
              }
            })
            .catchError((e) {
              // Ignore individual connection failures
            }),
      );

      // Process in batches to avoid overwhelming the system
      if (futures.length >= 50) {
        await Future.wait(futures, eagerError: false);
        futures.clear();
      }
    }

    // Wait for remaining checks
    if (futures.isNotEmpty) {
      await Future.wait(futures, eagerError: false);
    }

    return foundHosts;
  }

  /// Check if PHD2 is running at a specific host:port
  Future<bool> _checkPhd2AtHost(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );

      // Successfully connected - verify it's actually PHD2 by sending a simple request
      try {
        // Send a get_app_state request
        const request = '{"method":"get_app_state","id":1}\r\n';
        socket.write(request);
        await socket.flush();

        // Wait for response with timeout
        final response = await socket
            .timeout(const Duration(seconds: 1))
            .first
            .timeout(const Duration(seconds: 1), onTimeout: () => Uint8List(0));

        socket.destroy();

        // If we got a response, it's likely PHD2
        if (response.isNotEmpty) {
          final responseStr = String.fromCharCodes(response);
          // Check if response looks like JSON-RPC
          return responseStr.contains('result') ||
              responseStr.contains('error');
        }
      } catch (e) {
        socket.destroy();
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if PHD2 is installed on the system
  Future<bool> _isPhd2Installed() async {
    // First check if it's already running (fastest check)
    if (await phd2.checkPhd2Running(host: 'localhost', port: 4400)) {
      return true;
    }

    // Platform-specific installation checks
    if (Platform.isWindows) {
      return await _isPhd2InstalledWindows();
    } else if (Platform.isMacOS) {
      return await _isPhd2InstalledMacOS();
    } else if (Platform.isLinux) {
      return await _isPhd2InstalledLinux();
    }

    // Unknown platform - assume not installed
    return false;
  }

  /// Check if PHD2 is installed on Windows
  Future<bool> _isPhd2InstalledWindows() async {
    final phd2Paths = [
      r'C:\Program Files (x86)\PHDGuiding2\phd2.exe',
      r'C:\Program Files\PHDGuiding2\phd2.exe',
      r'C:\Program Files (x86)\PHD2\phd2.exe',
      r'C:\Program Files\PHD2\phd2.exe',
    ];

    for (final path in phd2Paths) {
      if (await File(path).exists()) {
        return true;
      }
    }

    // Check if phd2 process is running
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq phd2.exe',
      ]);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.contains('phd2.exe')) {
          return true;
        }
      }
    } catch (e) {
      // Process check failed - not critical, continue
    }

    return false;
  }

  /// Check if PHD2 is installed on macOS
  Future<bool> _isPhd2InstalledMacOS() async {
    // Common installation paths on macOS
    final phd2Paths = [
      '/Applications/PHD2.app',
      '/Applications/phd2.app',
      '${Platform.environment['HOME']}/Applications/PHD2.app',
      '${Platform.environment['HOME']}/Applications/phd2.app',
    ];

    for (final path in phd2Paths) {
      if (await Directory(path).exists()) {
        return true;
      }
    }

    // Check if phd2 is in PATH
    try {
      final result = await Process.run('which', ['phd2']);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // PATH check failed - not critical, continue
    }

    // Check if phd2 process is running
    try {
      final result = await Process.run('pgrep', ['-x', 'phd2']);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // Process check failed - not critical, continue
    }

    return false;
  }

  /// Check if PHD2 is installed on Linux
  Future<bool> _isPhd2InstalledLinux() async {
    // Common installation paths on Linux
    final phd2Paths = [
      '/usr/bin/phd2',
      '/usr/local/bin/phd2',
      '${Platform.environment['HOME']}/.local/bin/phd2',
      '/opt/phd2/bin/phd2',
    ];

    for (final path in phd2Paths) {
      if (await File(path).exists()) {
        return true;
      }
    }

    // Check if phd2 is in PATH
    try {
      final result = await Process.run('which', ['phd2']);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // PATH check failed - not critical, continue
    }

    // Check if phd2 process is running
    try {
      final result = await Process.run('pgrep', ['-x', 'phd2']);
      if (result.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // Process check failed - not critical, continue
    }

    // Check common package manager installations
    try {
      // Check if installed via apt (Debian/Ubuntu)
      final dpkgResult = await Process.run('dpkg', ['-l', 'phd2']);
      if (dpkgResult.exitCode == 0 &&
          dpkgResult.stdout.toString().contains('phd2')) {
        return true;
      }
    } catch (e) {
      // dpkg might not be available
    }

    try {
      // Check if installed via rpm (Fedora/RedHat)
      final rpmResult = await Process.run('rpm', ['-q', 'phd2']);
      if (rpmResult.exitCode == 0) {
        return true;
      }
    } catch (e) {
      // rpm might not be available
    }

    return false;
  }

  /// Convert local DeviceType to generated DeviceType
  gen_device.DeviceType _toGenDeviceType(DeviceType deviceType) {
    switch (deviceType) {
      case DeviceType.camera:
        return gen_device.DeviceType.camera;
      case DeviceType.mount:
        return gen_device.DeviceType.mount;
      case DeviceType.focuser:
        return gen_device.DeviceType.focuser;
      case DeviceType.filterWheel:
        return gen_device.DeviceType.filterWheel;
      case DeviceType.guider:
        return gen_device.DeviceType.guider;
      case DeviceType.dome:
        return gen_device.DeviceType.dome;
      case DeviceType.rotator:
        return gen_device.DeviceType.rotator;
      case DeviceType.weather:
        return gen_device.DeviceType.weather;
      case DeviceType.safetyMonitor:
        return gen_device.DeviceType.safetyMonitor;
      case DeviceType.switch_:
        return gen_device.DeviceType.switch_;
      case DeviceType.coverCalibrator:
        return gen_device.DeviceType.coverCalibrator;
    }
  }

  /// Convert generated DeviceType to local DeviceType
  DeviceType _fromGenDeviceType(gen_device.DeviceType deviceType) {
    switch (deviceType) {
      case gen_device.DeviceType.camera:
        return DeviceType.camera;
      case gen_device.DeviceType.mount:
        return DeviceType.mount;
      case gen_device.DeviceType.focuser:
        return DeviceType.focuser;
      case gen_device.DeviceType.filterWheel:
        return DeviceType.filterWheel;
      case gen_device.DeviceType.guider:
        return DeviceType.guider;
      case gen_device.DeviceType.dome:
        return DeviceType.dome;
      case gen_device.DeviceType.rotator:
        return DeviceType.rotator;
      case gen_device.DeviceType.weather:
        return DeviceType.weather;
      case gen_device.DeviceType.safetyMonitor:
        return DeviceType.safetyMonitor;
      case gen_device.DeviceType.switch_:
        return DeviceType.switch_;
      case gen_device.DeviceType.coverCalibrator:
        return DeviceType.coverCalibrator;
    }
  }

  /// Convert generated DriverType to local DriverType
  DriverType _fromGenDriverType(gen_device.DriverType driverType) {
    switch (driverType) {
      case gen_device.DriverType.ascom:
        return DriverType.ascom;
      case gen_device.DriverType.alpaca:
        return DriverType.alpaca;
      case gen_device.DriverType.indi:
        return DriverType.indi;
      case gen_device.DriverType.native:
        return DriverType.native;
      case gen_device.DriverType.simulator:
        return DriverType.simulator;
    }
  }

  /// Check if an Alpaca device type matches our DeviceType
  bool _alpacaTypeMatches(String alpacaType, DeviceType deviceType) {
    switch (deviceType) {
      case DeviceType.camera:
        return alpacaType == 'camera';
      case DeviceType.mount:
        return alpacaType == 'telescope';
      case DeviceType.focuser:
        return alpacaType == 'focuser';
      case DeviceType.filterWheel:
        return alpacaType == 'filterwheel';
      case DeviceType.guider:
        return alpacaType == 'camera'; // Guider cameras
      case DeviceType.rotator:
        return alpacaType == 'rotator';
      case DeviceType.dome:
        return alpacaType == 'dome';
      case DeviceType.weather:
        return alpacaType == 'observingconditions';
      case DeviceType.safetyMonitor:
        return alpacaType == 'safetymonitor';
      case DeviceType.switch_:
        return alpacaType == 'switch';
      case DeviceType.coverCalibrator:
        return alpacaType == 'covercalibrator';
    }
  }
}
