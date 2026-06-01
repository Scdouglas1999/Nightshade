part of '../bridge_stub.dart';

extension _NativeBridgeRuntimeOperations on _NativeBridgeImplementation {
  // =========================================================================
  // Initialization
  // =========================================================================

  /// Initialize the native bridge
  Future<void> init({String? logDirectory}) async {
    if (_initialized) return;

    // Try to load native library manually (for fallback path)
    await _tryLoadNativeLibrary();

    // FRB defaults to a dev-tree relative path (see kDefaultExternalLibraryLoaderConfig)
    // which does not exist next to a packaged Release exe. When we found the DLL
    // beside the executable, pass that path explicitly.
    try {
      if (_loadedNativeLibraryPath != null) {
        await frb.RustLib.init(
          externalLibrary: ExternalLibrary.open(_loadedNativeLibraryPath!),
        );
      } else {
        await frb.RustLib.init();
      }

      // Initialize the native bridge API
      if (logDirectory != null) {
        gen_api.apiInitWithLogging(logDirectory: logDirectory);
      } else {
        gen_api.apiInit();
      }

      // Verify it's working
      final version = gen_api.apiGetVersion();
      developer.log('[Bridge] Native bridge v$version ready',
          name: 'NativeBridge', level: 800);

      // Mark as available for native discovery
      _nativeAvailable = true;
    } catch (e) {
      developer.log('[Bridge] RustLib initialization failed: $e',
          name: 'NativeBridge', level: 1000);
      // Mark as unavailable since RustLib couldn't initialize
      _nativeAvailable = false;
    }

    // Initialize default states
    _initializeDefaultStates();

    _initialized = true;

    // Emit initialization event
    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.system,
      eventType: 'Initialized',
      data: {'nativeAvailable': _nativeAvailable},
    ));

    if (_nativeAvailable) {
      developer.log('[Bridge] Loaded native library',
          name: 'NativeBridge', level: 800);
    } else {
      // Why: warning-level â€” running without native bridge means hardware
      // operations will fail closed, which is a degraded-but-running state
      // operators must be able to spot in logs.
      developer.log(
          '[Bridge] Native bridge unavailable; running in fail-closed fallback mode',
          name: 'NativeBridge',
          level: 900);
    }
  }

  void _initializeDefaultStates() {
    _cameraStatus = const CameraStatus(
      connected: false,
      state: gen_device.CameraState.idle,
      sensorTemp: 20.0,
      coolerPower: 0.0,
      targetTemp: -10.0,
      coolerOn: false,
      gain: 100,
      offset: 10,
      binX: 1,
      binY: 1,
      sensorWidth: 4144,
      sensorHeight: 2822,
      pixelSizeX: 3.76,
      pixelSizeY: 3.76,
      maxAdu: 65535,
      canCool: true,
      canSetGain: true,
      canSetOffset: true,
    );

    _mountStatus = const MountStatus(
      connected: false,
      tracking: false,
      slewing: false,
      parked: true,
      atHome: false,
      sideOfPier: PierSide.unknown,
      rightAscension: 0.0,
      declination: 0.0,
      altitude: 0.0,
      azimuth: 0.0,
      siderealTime: 0.0,
      trackingRate: TrackingRate.sidereal,
      canPark: true,
      canSlew: true,
      canSync: true,
      canPulseGuide: true,
      canSetTrackingRate: true,
      availability: {},
    );

    _focuserStatus = const FocuserStatus(
      connected: false,
      position: 25000,
      moving: false,
      temperature: 20.0,
      maxPosition: 50000,
      stepSize: 1.0,
      isAbsolute: true,
      hasTemperature: true,
    );

    _filterWheelStatus = const FilterWheelStatus(
      connected: false,
      position: 0,
      moving: false,
      filterCount: 7,
      filterNames: ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'],
    );
  }

  /// Try to load the native library
  Future<bool> _tryLoadNativeLibrary() async {
    try {
      // Determine library name based on platform
      String libName;
      if (Platform.isWindows) {
        libName = 'nightshade_bridge.dll';
      } else if (Platform.isLinux) {
        libName = 'libnightshade_bridge.so';
      } else if (Platform.isMacOS) {
        libName = 'libnightshade_bridge.dylib';
      } else {
        // Unsupported platform
        return false;
      }

      // Get the executable directory
      final executablePath = Platform.resolvedExecutable;
      final executableDir = path.dirname(executablePath);

      // Try to find the native library in common locations
      final possiblePaths = <String>[];

      if (Platform.isWindows) {
        // Windows: library should be next to executable or in data directory
        possiblePaths.addAll([
          // First, check next to the executable (most common location)
          path.join(executableDir, libName),
          // Check parent directories (for release builds)
          path.join(executableDir, '..', libName),
          path.join(executableDir, '..', '..', libName),
          // Check in data directory
          path.join(executableDir, 'data', 'flutter_assets', libName),
          // Check if we can find the project root by looking for common markers
          // Try to find native/nightshade_native from executable location
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'bridge', 'target', 'release', libName),
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'target', 'release', libName),
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'bridge', 'target', 'debug', libName),
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'target', 'debug', libName),
          // Check if executable is in a Release/Debug folder
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'bridge', 'target', 'release', libName),
        ]);

        // Also try to find project root from current working directory
        try {
          final cwd = Directory.current.path;
          possiblePaths.addAll([
            path.join(cwd, 'native', 'nightshade_native', 'bridge', 'target',
                'release', libName),
            path.join(cwd, 'native', 'nightshade_native', 'target', 'release',
                libName),
            path.join(cwd, '..', 'native', 'nightshade_native', 'bridge',
                'target', 'release', libName),
            path.join(cwd, '..', '..', 'native', 'nightshade_native', 'bridge',
                'target', 'release', libName),
          ]);
        } catch (e) {
          // Ignore errors getting current directory
        }
      } else if (Platform.isLinux) {
        // Linux: library should be in lib/ directory relative to executable
        possiblePaths.addAll([
          path.join(executableDir, 'lib', libName),
          path.join(executableDir, '..', 'lib', libName),
          path.join(executableDir, libName),
          // Development build location
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'target', 'release', libName),
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'target', 'debug', libName),
          // System library path
          '/usr/local/lib/$libName',
        ]);
      } else if (Platform.isMacOS) {
        // macOS: library should be in Frameworks directory of app bundle
        possiblePaths.addAll([
          path.join(executableDir, '..', 'Frameworks', libName),
          path.join(executableDir, 'Frameworks', libName),
          path.join(executableDir, libName),
          // Development build location
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'target', 'release', libName),
          path.join(executableDir, '..', '..', '..', 'native',
              'nightshade_native', 'target', 'debug', libName),
        ]);
      }

      // Try to load the library from each possible path
      for (final libPath in possiblePaths) {
        try {
          final file = File(libPath);
          if (await file.exists()) {
            try {
              _nativeLib = DynamicLibrary.open(libPath);
              _loadedNativeLibraryPath = path.normalize(libPath);
              return true;
            } catch (e) {
              developer.log(
                '[Bridge] Failed to load native library at $libPath: $e',
                name: 'NativeBridge',
                level: 900,
              );
            }
          }
        } catch (e) {
          // Continue trying other paths
        }
      }

      _loadedNativeLibraryPath = null;
      _nativeLib = null;

      // Why: warning-level â€” same fail-closed signal as the init path; this
      // is the dlopen-side failure when the library couldn't be located on
      // any search path.
      developer.log(
          '[Bridge] Native library not found. Native-only operations will fail closed.',
          name: 'NativeBridge',
          level: 900);
      return false;
    } catch (e) {
      developer.log('[Bridge] Error loading native library: $e',
          name: 'NativeBridge', level: 1000);
      return false;
    }
  }

  /// Check if native library is available
  bool get isNativeAvailable => _nativeAvailable;

  /// Invalidate the discovery cache so the next call runs full discovery.
  /// Call this when the user explicitly requests a refresh, or after
  /// connecting/disconnecting a device.
  void invalidateDiscoveryCache() {
    _discoveryCache.clear();
    _discoveryCacheTime = null;
  }

  /// Get the version of the native library
  String getNativeVersion() {
    if (_nativeAvailable && _nativeLib != null) {
      try {
        // Try to call the native get_version function
        final getVersion = _nativeLib!
            .lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>(
                'get_native_version');

        final versionPtr = getVersion();
        if (versionPtr != nullptr) {
          final version = versionPtr.toDartString();
          return version;
        }
      } catch (e) {
        developer.log('[Bridge] Failed to get native version: $e',
            name: 'NativeBridge', level: 900);
      }
      return '0.1.0';
    }
    // Native library not loaded - return fallback version
    // Note: Hardware operations will fail without native library
    return '0.1.0-fallback (native library not loaded)';
  }

  /// Get the loaded native library (if available)
  DynamicLibrary? get nativeLibrary => _nativeLib;

  // =========================================================================
  // Event Stream
  // =========================================================================

  /// Stream of events from the native side
  Stream<NightshadeEvent> eventStream() {
    // If native is available, use the real event stream from Rust
    if (_nativeAvailable) {
      try {
        return gen_api.apiEventStream();
      } catch (e) {
        developer.log('[Bridge] Failed to get native event stream: $e',
            name: 'NativeBridge', level: 1000);
      }
    }

    // Fallback to local event controller for simulator mode
    // Convert internal fallback events to proper NightshadeEvent format
    var fallbackEventId = BigInt.zero;
    return _eventController.stream.map((fallbackEvent) {
      fallbackEventId += BigInt.one;
      return gen_event.NightshadeEvent(
        eventId: fallbackEventId,
        timestamp: fallbackEvent.timestamp,
        severity: fallbackEvent.severity,
        category: fallbackEvent.category,
        payload: gen_event.EventPayload.system(
          gen_event.SystemEvent.notification(
            title: fallbackEvent.eventType,
            message: fallbackEvent.data.toString(),
            level: fallbackEvent.severity.name,
          ),
        ),
      );
    });
  }
}
