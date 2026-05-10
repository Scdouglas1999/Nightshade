// ignore_for_file: unused_field

/// Nightshade Bridge - Dart FFI bindings to Rust native code
///
/// This file provides the bridge to the Rust native library.
/// The native DLL is loaded dynamically and provides real ASCOM/Alpaca
/// device discovery and connection on Windows.
///
/// For Alpaca devices, we use direct HTTP communication from Dart,
/// which works cross-platform without needing the native bridge.
///
/// When the native library is not available, this bridge will NOT fall back
/// to simulator implementations. Instead, it will return empty device lists
/// and throw errors for hardware operations. Use INDI/ASCOM/Alpaca external
/// simulators for testing instead of built-in fallback adapters.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;
import 'alpaca_client.dart' as alpaca;
import 'ascom_client.dart' as ascom;
import 'phd2_client.dart' as phd2;
import 'api.dart' as gen_api;
import 'device.dart' as gen_device;
import 'event.dart' as gen_event;
import 'state.dart' as gen_state;
import 'storage.dart' as gen_storage;
import 'frb_generated.dart' as frb;

// ============================================================================
// Error Messages for Fallback Mode
// ============================================================================

/// Error message thrown when fallback operations are called in production
const _fallbackErrorMessage = '''
Native bridge not available. This is the Dart fallback bridge.

Possible causes:
1. Native library failed to load - check build output
2. Running on unsupported platform (web)
3. DLL/dylib not found in expected location

For development: Use INDI/ASCOM/Alpaca simulators instead of built-in fallback adapters.
Simulators are disabled to prevent silent failures with fake data.
''';

Never _nativeBridgeRequired(String operation) {
  throw UnsupportedError(
    'Operation "$operation" requires the native bridge.\n$_fallbackErrorMessage',
  );
}

bool _isPhd2DeviceId(String deviceId) =>
    deviceId == 'phd2' ||
    deviceId == 'phd2_guider' ||
    deviceId.startsWith('phd2:') ||
    deviceId.startsWith('phd2://');

String _canonicalGuiderDeviceId(String deviceId) {
  if (_isPhd2DeviceId(deviceId)) {
    return 'phd2_guider';
  }
  return deviceId;
}

// ============================================================================
// Type Aliases - Use FRB-generated types to avoid duplication
// ============================================================================

// From device.dart
typedef DeviceType = gen_device.DeviceType;
typedef DriverType = gen_device.DriverType;
typedef CameraState = gen_device.CameraState;
typedef CameraStatus = gen_device.CameraStatus;
typedef DeviceInfo = gen_device.DeviceInfo;
typedef FilterWheelStatus = gen_device.FilterWheelStatus;
typedef FocuserStatus = gen_device.FocuserStatus;
typedef MountStatus = gen_device.MountStatus;
typedef PierSide = gen_device.PierSide;
typedef RotatorStatus = gen_device.RotatorStatus;
typedef TrackingRate = gen_device.TrackingRate;

// From state.dart
typedef EquipmentProfile = gen_state.EquipmentProfile;

// From storage.dart
typedef AppSettings = gen_storage.AppSettings;
typedef ObserverLocation = gen_storage.ObserverLocation;

// From api.dart
typedef AutofocusConfigApi = gen_api.AutofocusConfigApi;
typedef AutofocusResultApi = gen_api.AutofocusResultApi;
typedef CapturedImageResult = gen_api.CapturedImageResult;
typedef ImageStatsResult = gen_api.ImageStatsResult;
typedef Phd2Status = gen_api.Phd2Status;
typedef Phd2StarImage = gen_api.Phd2StarImage;
typedef PlateSolveResult = gen_api.PlateSolveResult;
// Note: SequencerState is NOT typedefed because FRB's SequencerState is a class,
// but we use a local enum for internal state management (see _InternalSequencerState below)

// From event.dart
typedef NightshadeEvent = gen_event.NightshadeEvent;
typedef EventSeverity = gen_event.EventSeverity;
typedef EventCategory = gen_event.EventCategory;
typedef PolarAlignmentEvent = gen_event.PolarAlignmentEvent;

// ============================================================================
// Extension on FRB-generated DeviceType
// ============================================================================

extension DeviceTypeExtension on DeviceType {
  String get displayName {
    switch (this) {
      case DeviceType.camera:
        return 'Camera';
      case DeviceType.mount:
        return 'Mount';
      case DeviceType.focuser:
        return 'Focuser';
      case DeviceType.filterWheel:
        return 'Filter Wheel';
      case DeviceType.guider:
        return 'Guider';
      case DeviceType.dome:
        return 'Dome';
      case DeviceType.rotator:
        return 'Rotator';
      case DeviceType.weather:
        return 'Weather';
      case DeviceType.safetyMonitor:
        return 'Safety Monitor';
      case DeviceType.switch_:
        return 'Switch';
      case DeviceType.coverCalibrator:
        return 'Cover Calibrator';
    }
  }
}

// ============================================================================
// Enums unique to bridge fallback layer (not in FRB-generated code)
// ============================================================================

/// Device connection state
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Frame type for camera exposures
enum FrameType {
  light,
  dark,
  flat,
  bias,
  darkFlat,
}

/// Dome shutter state
enum ShutterState {
  open,
  closed,
  opening,
  closing,
  error,
  unknown,
}

// EventSeverity, EventCategory, PolarAlignmentEvent, and NightshadeEvent are now typedefed from event.dart

// ============================================================================
// Data Classes unique to bridge fallback layer (not in FRB-generated code)
// ============================================================================

/// Session state from native
class NativeSessionState {
  final bool isActive;
  final int? startTime;
  final String? targetName;
  final double? targetRa;
  final double? targetDec;
  final int totalExposures;
  final int completedExposures;
  final double totalIntegrationSecs;
  final String? currentFilter;
  final bool isGuiding;
  final bool isCapturing;
  final bool isDithering;

  NativeSessionState({
    required this.isActive,
    this.startTime,
    this.targetName,
    this.targetRa,
    this.targetDec,
    required this.totalExposures,
    required this.completedExposures,
    required this.totalIntegrationSecs,
    this.currentFilter,
    required this.isGuiding,
    required this.isCapturing,
    required this.isDithering,
  });
}

/// Internal fallback event - used for simulator mode
/// This is different from gen_event.NightshadeEvent which uses EventPayload
class _FallbackNightshadeEvent {
  final int timestamp;
  final gen_event.EventSeverity severity;
  final gen_event.EventCategory category;
  final String eventType;
  final Map<String, dynamic> data;

  _FallbackNightshadeEvent({
    required this.timestamp,
    required this.severity,
    required this.category,
    required this.eventType,
    required this.data,
  });
}

/// Image statistics (unique to bridge fallback layer - different from ImageStatsResult)
class ImageStats {
  final double min;
  final double max;
  final double mean;
  final double median;
  final double stdDev;
  final double mad;

  ImageStats({
    required this.min,
    required this.max,
    required this.mean,
    required this.median,
    required this.stdDev,
    required this.mad,
  });
}

/// Sequencer status (unique to bridge fallback layer - different from SequencerState)
class SequencerStatus {
  final String state;
  final String? currentNodeId;
  final String? currentNodeName;
  final double progress;
  final String? message;

  SequencerStatus({
    required this.state,
    this.currentNodeId,
    this.currentNodeName,
    required this.progress,
    this.message,
  });
}

/// Checkpoint information for crash recovery
class CheckpointInfoApi {
  final String sequenceName;
  final String timestamp; // ISO-8601 format
  final int completedExposures;
  final double completedIntegrationSecs;
  final bool canResume;
  final int ageSeconds;

  CheckpointInfoApi({
    required this.sequenceName,
    required this.timestamp,
    required this.completedExposures,
    required this.completedIntegrationSecs,
    required this.canResume,
    required this.ageSeconds,
  });
}

/// Sequencer state enum for local state management
/// Note: This is hidden from library exports and FRB's SequencerState (a class) is exported instead
enum SequencerState {
  idle,
  running,
  paused,
  stopping,
  completed,
  failed,
}

// ============================================================================
// Native Bridge Implementation
// ============================================================================

/// Native bridge for communication with Rust backend
///
/// This bridge attempts to load the native Rust library and use it for
/// real device discovery and control. When the native library is not
/// available, native-only operations fail closed.
class NativeBridge {
  static bool _initialized = false;
  static bool _nativeAvailable = false;
  static DynamicLibrary? _nativeLib;
  static final _eventController =
      StreamController<_FallbackNightshadeEvent>.broadcast();

  // Simulated device states
  static final Map<String, bool> _connectedDevices = {};
  static final Map<String, DeviceInfo> _connectedDeviceInfo = {};
  static CameraStatus? _cameraStatus;
  static MountStatus? _mountStatus;
  static FocuserStatus? _focuserStatus;
  static FilterWheelStatus? _filterWheelStatus;

  // Full discovery result cache (keyed by DeviceType) with 60-second TTL.
  // A single sweep discovers ALL device types and populates the entire cache,
  // so concurrent callers for different types share one sweep.
  static final Map<DeviceType, List<DeviceInfo>> _discoveryCache = {};
  static DateTime? _discoveryCacheTime;
  static const _discoveryCacheTtl = Duration(seconds: 60);

  // Completer that gates concurrent discovery requests: if a full sweep is
  // already in progress, new callers await this instead of launching their own.
  static Completer<void>? _discoverySweepInProgress;

  // Static flag to only print "Not on Windows" once
  static bool _ascomNotWindowsWarned = false;

  // Active Alpaca connections
  static final Map<String, alpaca.AlpacaClient> _alpacaClients = {};
  static final Map<String, alpaca.AlpacaDevice> _alpacaDevices = {};

  // Active ASCOM connections
  static final Map<String, ascom.AscomDeviceClient> _ascomClients = {};

  // PHD2 client
  static phd2.Phd2Client? _phd2Client;

  // =========================================================================
  // Initialization
  // =========================================================================

  /// Initialize the native bridge
  static Future<void> init({String? logDirectory}) async {
    if (_initialized) return;

    // Try to load native library manually (for fallback path)
    _nativeAvailable = await _tryLoadNativeLibrary();

    // Try to initialize RustLib (it will try to auto-load the library)
    // This enables native ZWO discovery and proper ASCOM discovery
    // Note: If manual load succeeded, RustLib should also be able to find it
    try {
      await frb.RustLib.init();

      // Initialize the native bridge API
      if (logDirectory != null) {
        gen_api.apiInitWithLogging(logDirectory: logDirectory);
      } else {
        gen_api.apiInit();
      }

      // Verify it's working
      final version = gen_api.apiGetVersion();
      debugPrint('[Bridge] Native bridge v$version ready');

      // Mark as available for native discovery
      _nativeAvailable = true;
    } catch (e) {
      debugPrint('[Bridge] RustLib initialization failed: $e');
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
      debugPrint('[Bridge] Loaded native library');
    } else {
      debugPrint(
          '[Bridge] Native bridge unavailable; running in fail-closed fallback mode');
    }
  }

  static void _initializeDefaultStates() {
    _cameraStatus = const CameraStatus(
      connected: false,
      state: CameraState.idle,
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
      availability: const {},
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
  static Future<bool> _tryLoadNativeLibrary() async {
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
            _nativeLib = DynamicLibrary.open(libPath);
            return true;
          }
        } catch (e) {
          // Continue trying other paths
        }
      }

      // If we couldn't find the library, try loading by name (system will search)
      try {
        if (Platform.isWindows) {
          _nativeLib = DynamicLibrary.open(libName);
        } else if (Platform.isLinux) {
          _nativeLib = DynamicLibrary.open(libName);
        } else if (Platform.isMacOS) {
          _nativeLib = DynamicLibrary.open(libName);
        }
        return true;
      } catch (e) {
        // System search also failed
      }

      debugPrint(
          '[Bridge] Native library not found. Native-only operations will fail closed.');
      return false;
    } catch (e) {
      debugPrint('[Bridge] Error loading native library: $e');
      return false;
    }
  }

  /// Check if native library is available
  static bool get isNativeAvailable => _nativeAvailable;

  /// Invalidate the discovery cache so the next call runs full discovery.
  /// Call this when the user explicitly requests a refresh, or after
  /// connecting/disconnecting a device.
  static void invalidateDiscoveryCache() {
    _discoveryCache.clear();
    _discoveryCacheTime = null;
  }

  /// Get the version of the native library
  static String getNativeVersion() {
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
        debugPrint('[Bridge] Failed to get native version: $e');
      }
      return '0.1.0';
    }
    // Native library not loaded - return fallback version
    // Note: Hardware operations will fail without native library
    return '0.1.0-fallback (native library not loaded)';
  }

  /// Get the loaded native library (if available)
  static DynamicLibrary? get nativeLibrary => _nativeLib;

  // =========================================================================
  // Event Stream
  // =========================================================================

  /// Stream of events from the native side
  static Stream<NightshadeEvent> eventStream() {
    // If native is available, use the real event stream from Rust
    if (_nativeAvailable) {
      try {
        return gen_api.apiEventStream();
      } catch (e) {
        debugPrint('[Bridge] Failed to get native event stream: $e');
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

  // =========================================================================
  // Device Discovery
  // =========================================================================

  /// Discover INDI devices at a specific server address
  static Future<List<DeviceInfo>> apiDiscoverIndiAtAddress({
    required String host,
    required int port,
  }) async {
    try {
      // Connect to INDI server via TCP
      final socket =
          await Socket.connect(host, port, timeout: const Duration(seconds: 5));

      try {
        // Send getProperties command to request device list
        final command = '<getProperties version="1.7"/>\n';
        socket.add(utf8.encode(command));
        await socket.flush();

        // Read response with timeout
        final completer = Completer<String>();
        final buffer = StringBuffer();
        Timer? timeoutTimer;

        socket.listen(
          (data) {
            buffer.write(utf8.decode(data));
            // INDI responses can be chunked, so we accumulate until we have complete XML
            final response = buffer.toString();
            // Check if we have a complete XML document (ends with </indilib>)
            if (response.contains('</indilib>') ||
                response.contains('</defTextVector>') ||
                response.contains('</defNumberVector>')) {
              timeoutTimer?.cancel();
              if (!completer.isCompleted) {
                completer.complete(response);
              }
            }
          },
          onError: (Object error) {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) {
              completer.completeError(error);
            }
          },
          onDone: () {
            timeoutTimer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(buffer.toString());
            }
          },
          cancelOnError: false,
        );

        // Set timeout for reading response
        timeoutTimer = Timer(const Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            completer.complete(buffer.toString());
          }
        });

        // Wait for response or timeout
        final response = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => buffer.toString(),
        );

        // Parse XML response
        final devices = _parseIndiDevices(response, host, port);

        return devices;
      } finally {
        await socket.close();
      }
    } catch (e) {
      debugPrint('[Discovery] INDI discovery failed at $host:$port: $e');
      return [];
    }
  }

  /// Parse INDI XML response to extract device information
  static List<DeviceInfo> _parseIndiDevices(
      String xmlResponse, String host, int port) {
    final devices = <DeviceInfo>[];

    if (xmlResponse.isEmpty) {
      return devices;
    }

    try {
      final document = xml.XmlDocument.parse(xmlResponse);
      final root = document.rootElement;

      // Track devices and their properties
      final deviceProperties = <String, Set<String>>{};

      // Parse all property definitions to determine device types
      for (final element in root.findAllElements('*')) {
        final name = element.localName;

        if (name == 'defTextVector' ||
            name == 'defNumberVector' ||
            name == 'defSwitchVector' ||
            name == 'defLightVector' ||
            name == 'defBLOBVector') {
          final deviceAttr = element.getAttribute('device');
          final nameAttr = element.getAttribute('name');

          if (deviceAttr != null && nameAttr != null) {
            deviceProperties
                .putIfAbsent(deviceAttr, () => <String>{})
                .add(nameAttr);
          }
        }
      }

      // Convert to DeviceInfo based on properties
      for (final entry in deviceProperties.entries) {
        final deviceName = entry.key;
        final properties = entry.value;

        // Determine device type based on properties (matching native implementation)
        DeviceType? deviceType;

        if (properties.contains('CCD_EXPOSURE') ||
            properties.contains('CCD1')) {
          deviceType = DeviceType.camera;
        } else if (properties.contains('EQUATORIAL_EOD_COORD') ||
            properties.contains('EQUATORIAL_COORD') ||
            properties.contains('TELESCOPE_PARK')) {
          deviceType = DeviceType.mount;
        } else if (properties.contains('ABS_FOCUS_POSITION') ||
            properties.contains('REL_FOCUS_POSITION') ||
            properties.contains('FOCUS_MOTION')) {
          deviceType = DeviceType.focuser;
        } else if (properties.contains('FILTER_SLOT') ||
            properties.contains('FILTER_NAME')) {
          deviceType = DeviceType.filterWheel;
        } else if (properties.contains('ABS_ROTATOR_ANGLE') ||
            properties.contains('ROTATOR_ROTATION')) {
          deviceType = DeviceType.rotator;
        } else if (properties.contains('DOME_PARK') ||
            properties.contains('DOME_SHUTTER')) {
          deviceType = DeviceType.dome;
        } else if (properties.contains('WEATHER_TEMPERATURE') ||
            properties.contains('WEATHER_HUMIDITY') ||
            properties.contains('WEATHER_CLOUD_COVER')) {
          deviceType = DeviceType.weather;
        }

        // Only include devices we can identify
        if (deviceType != null) {
          devices.add(DeviceInfo(
            id: 'indi:$host:$port:$deviceName',
            name: deviceName,
            deviceType: deviceType,
            driverType: DriverType.indi,
            description: 'INDI device on $host:$port',
            driverVersion: 'INDI',
            displayName: deviceName,
          ));
        }
      }
    } catch (e) {
      debugPrint('[Discovery] Error parsing INDI XML response: $e');
      // Try to extract device names even if full parsing fails
      // (these devices are skipped because type cannot be determined)
      // Regex fallback intentionally does not add devices - malformed XML
      // means we cannot reliably determine device types
    }

    return devices;
  }

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
  static Future<List<DeviceInfo>> discoverDevices(DeviceType deviceType) async {
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

    // We are the first caller — run a full sweep for ALL device types
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
  static Future<void> _runFullDiscoverySweep() async {
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
            final nativeDevices =
                await gen_api.apiDiscoverDevices(deviceType: genDeviceType);

            for (final nativeDev in nativeDevices) {
              allDevices[dt]!.add(DeviceInfo(
                id: nativeDev.id,
                name: nativeDev.name,
                deviceType: _fromGenDeviceType(nativeDev.deviceType),
                driverType: _fromGenDriverType(nativeDev.driverType),
                description: nativeDev.description,
                driverVersion: nativeDev.driverVersion,
                displayName: nativeDev.displayName,
              ));
            }
          } catch (e) {
            if (!e.toString().contains('RustLib') &&
                !e.toString().contains('not initialized')) {
              debugPrint(
                  '[Discovery] Native discovery error for ${dt.displayName}: $e');
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
              allDevices[dt]!.add(DeviceInfo(
                id: driver.id,
                name: driver.name,
                deviceType: dt,
                driverType: DriverType.ascom,
                description: 'ASCOM driver: ${driver.progId}',
                driverVersion: 'ASCOM',
                displayName: driver.name,
              ));
            }
          }
        } catch (e) {
          debugPrint(
              '[Discovery] ASCOM fallback discovery failed for ${dt.displayName}: $e');
        }
      }
    } else if (!Platform.isWindows && !_ascomNotWindowsWarned) {
      debugPrint('[Discovery] ASCOM not available (non-Windows platform)');
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
              allDevices[dt]!.add(DeviceInfo(
                id: device.id,
                name: device.deviceName,
                deviceType: dt,
                driverType: DriverType.alpaca,
                description:
                    'Alpaca device at ${device.server.host}:${device.server.port}',
                driverVersion: 'Alpaca',
                displayName: device.deviceName,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('[Discovery] Alpaca discovery failed: $e');
      }

      // =======================================================================
      // 4. PHD2 Discovery (guider type only)
      // =======================================================================
      try {
        final phd2Instances = await _discoverPhd2Instances();

        if (phd2Instances.isNotEmpty) {
          allDevices[DeviceType.guider]!.add(const DeviceInfo(
            id: 'phd2_guider',
            name: 'PHD2 Guiding',
            deviceType: DeviceType.guider,
            driverType: DriverType.native,
            description: 'PHD2 autoguiding software',
            driverVersion: '2.6+',
            displayName: 'PHD2 Guiding',
          ));
        }
      } catch (e) {
        debugPrint('[Discovery] PHD2 discovery failed: $e');
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
            '$count ${dt.displayName.toLowerCase()}${count == 1 ? '' : 's'}');
      }
    }
    if (parts.isNotEmpty) {
      debugPrint('[Discovery] Complete: ${parts.join(', ')}');
    } else {
      debugPrint('[Discovery] Complete: no devices found');
    }
  }

  /// Convert DeviceType to ASCOM device type string
  static String? _deviceTypeToAscomType(DeviceType deviceType) {
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
  static Future<List<Map<String, dynamic>>> _discoverPhd2Instances() async {
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
      debugPrint('[Discovery] PHD2 network scan failed: $e');
      // Continue with local instance if we found one
    }

    return instances;
  }

  /// Get local network addresses to scan
  static Future<List<String>> _getLocalNetworkAddresses() async {
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
      debugPrint('[Discovery] Failed to get network interfaces: $e');
    }

    return subnets;
  }

  /// Scan a subnet for PHD2 instances
  /// Scans all hosts in the subnet (xxx.xxx.xxx.1-254) on port 4400
  static Future<List<String>> _scanSubnetForPhd2(
      String subnet, int port) async {
    final foundHosts = <String>[];
    final futures = <Future<void>>[];

    // Scan all possible host addresses in parallel (1-254)
    for (int i = 1; i <= 254; i++) {
      final host = '$subnet.$i';

      // Skip localhost (already checked)
      if (i == 1 && (subnet == '127.0.0' || subnet == '::1')) continue;

      futures.add(_checkPhd2AtHost(host, port).then((isRunning) {
        if (isRunning) {
          foundHosts.add(host);
        }
      }).catchError((e) {
        // Ignore individual connection failures
      }));

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
  static Future<bool> _checkPhd2AtHost(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 500),
      );

      // Successfully connected - verify it's actually PHD2 by sending a simple request
      try {
        // Send a get_app_state request
        final request = '{"method":"get_app_state","id":1}\r\n';
        socket.write(request);
        await socket.flush();

        // Wait for response with timeout
        final response = await socket
            .timeout(
              const Duration(seconds: 1),
            )
            .first
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () => Uint8List(0),
            );

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
  static Future<bool> _isPhd2Installed() async {
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
  static Future<bool> _isPhd2InstalledWindows() async {
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
      final result =
          await Process.run('tasklist', ['/FI', 'IMAGENAME eq phd2.exe']);
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
  static Future<bool> _isPhd2InstalledMacOS() async {
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
  static Future<bool> _isPhd2InstalledLinux() async {
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
  static gen_device.DeviceType _toGenDeviceType(DeviceType deviceType) {
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
  static DeviceType _fromGenDeviceType(gen_device.DeviceType deviceType) {
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
  static DriverType _fromGenDriverType(gen_device.DriverType driverType) {
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
  static bool _alpacaTypeMatches(String alpacaType, DeviceType deviceType) {
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

  // =========================================================================
  // Device Connection
  // =========================================================================

  static DriverType? _inferDriverTypeFromDeviceId(String deviceId) {
    if (deviceId.startsWith('ascom:')) return DriverType.ascom;
    if (deviceId.startsWith('alpaca:')) return DriverType.alpaca;
    if (deviceId.startsWith('indi:')) return DriverType.indi;
    if (deviceId.startsWith('native:')) return DriverType.native;
    if (deviceId.startsWith('sim:') || deviceId.startsWith('simulator:')) {
      return DriverType.simulator;
    }
    return null;
  }

  static void _recordConnectedDevice({
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
      debugPrint(
        '[Bridge] Connected device "$deviceId" has no inferable driver type; omitting from fallback connected-device metadata.',
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
  static Future<void> connectDevice(
      DeviceType deviceType, String deviceId) async {
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
    final shouldUseNativeOnly = deviceId.startsWith('ascom:') ||
        deviceId.startsWith('native:') ||
        deviceId.startsWith('indi:');

    if (_nativeAvailable) {
      try {
        debugPrint('[Bridge] Attempting native connection for $deviceId...');
        final genDeviceType = _toGenDeviceType(deviceType);
        await gen_api.apiConnectDevice(
            deviceType: genDeviceType, deviceId: deviceId);
        debugPrint(
            '[Bridge] ✓ Successfully connected to $deviceId via native bridge');

        _recordConnectedDevice(
          deviceType: deviceType,
          deviceId: deviceId,
        );

        // Emit connection event
        _eventController.add(_FallbackNightshadeEvent(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          severity: EventSeverity.info,
          category: EventCategory.equipment,
          eventType: 'Connected',
          data: {'deviceType': deviceType.name, 'deviceId': deviceId},
        ));

        return; // Success - native bridge handled it
      } catch (e, stackTrace) {
        debugPrint('[Bridge] ✗ Native connection failed for $deviceId');
        debugPrint('[Bridge] Error: $e');
        debugPrint('[Bridge] Stack trace: $stackTrace');

        // If this device must use native bridge (was discovered by it),
        // don't fall back - throw the error
        if (shouldUseNativeOnly) {
          throw Exception(
              'Failed to connect to $deviceId via native bridge: $e');
        }

        debugPrint(
            '[Bridge] Device supports fallback - trying fallback methods...');
        // Continue to fallback bridge methods below
      }
    } else if (shouldUseNativeOnly) {
      // Native bridge required but not available
      throw Exception(
          'Cannot connect to $deviceId: Native bridge required but not available');
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
        'Unknown device: $deviceId. No ASCOM/Alpaca devices found.');
  }

  /// Connect to an ASCOM device
  static Future<void> _connectAscomDevice(
      DeviceType deviceType, String deviceId) async {
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
      debugPrint('[ASCOM] Connecting to device: $progId');
      await client.connect();

      _ascomClients[deviceId] = client;
      _recordConnectedDevice(
        deviceType: deviceType,
        deviceId: deviceId,
        driverType: DriverType.ascom,
      );

      _eventController.add(_FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'Connected',
        data: {'deviceType': deviceType.name, 'deviceId': deviceId},
      ));

      debugPrint('[ASCOM] Connected to device: $progId');
    } catch (e) {
      client.dispose();
      throw Exception('Failed to connect to ASCOM device: $e');
    }
  }

  /// Connect to an Alpaca device
  static Future<void> _connectAlpacaDevice(
      DeviceType deviceType, String deviceId) async {
    // Parse the device ID: alpaca:host:port/type/number
    final parts = deviceId.substring(7).split('/'); // Remove "alpaca:"
    if (parts.length < 3) {
      throw Exception('Invalid Alpaca device ID: $deviceId');
    }

    final hostPort = parts[0].split(':');
    if (hostPort.length != 2) {
      throw Exception('Invalid Alpaca device ID: $deviceId');
    }

    final host = hostPort[0];
    final port = int.tryParse(hostPort[1]) ?? 11111;
    final deviceTypeName = parts[1];
    final deviceNumber = int.tryParse(parts[2]) ?? 0;

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
      debugPrint('[Alpaca] Connecting to device: $deviceId');
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

      _eventController.add(_FallbackNightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.equipment,
        eventType: 'Connected',
        data: {'deviceType': deviceType.name, 'deviceId': deviceId},
      ));

      debugPrint('[Alpaca] Connected to device: $deviceId');
    } catch (e) {
      client.dispose();
      throw Exception('Failed to connect to Alpaca device: $e');
    }
  }

  /// Disconnect from a device
  static Future<void> disconnectDevice(
      DeviceType deviceType, String deviceId) async {
    // Handle PHD2 disconnection (supports new format: phd2:host:port or legacy: phd2)
    if (_isPhd2DeviceId(deviceId)) {
      await phd2Disconnect();
    }

    // Handle Alpaca device disconnection
    if (deviceId.startsWith('alpaca:')) {
      final client = _alpacaClients[deviceId];
      if (client != null) {
        try {
          await client.disconnect();
        } catch (e) {
          debugPrint('[Alpaca] Error disconnecting device: $e');
        }
        client.dispose();
        _alpacaClients.remove(deviceId);
        _alpacaDevices.remove(deviceId);
      }
    }

    // Handle ASCOM device disconnection
    if (deviceId.startsWith('ascom:')) {
      final client = _ascomClients[deviceId];
      if (client != null) {
        try {
          await client.disconnect();
        } catch (e) {
          debugPrint('[ASCOM] Error disconnecting device: $e');
        }
        client.dispose();
        _ascomClients.remove(deviceId);
      }
    }

    _connectedDevices.remove(deviceId);
    _connectedDeviceInfo.remove(deviceId);

    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.equipment,
      eventType: 'Disconnected',
      data: {'deviceType': deviceType.name, 'deviceId': deviceId},
    ));
  }

  /// Check if a device is connected
  static Future<bool> isDeviceConnected(
      DeviceType deviceType, String deviceId) async {
    // If native bridge is available, use it for authoritative connection status
    if (_nativeAvailable) {
      try {
        return await gen_api.apiIsDeviceConnected(
            deviceType: _toGenDeviceType(deviceType), deviceId: deviceId);
      } catch (e) {
        debugPrint(
            '[Bridge] Warning: Failed to check device connection from native API: $e');
        // Fall through to local tracking
      }
    }
    return _connectedDevices[deviceId] ?? false;
  }

  /// Get list of connected devices
  static Future<List<DeviceInfo>> getConnectedDevices() async {
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
        debugPrint(
            '[Bridge] Warning: Failed to get connected devices from native API: $e');
        // Fall through to fallback implementation
      }
    }

    // Fallback: return only explicitly tracked metadata captured at connection time.
    return _connectedDeviceInfo.values.toList(growable: false);
  }

  // =========================================================================
  // Camera Control
  // =========================================================================

  /// Get camera status
  static Future<CameraStatus> getCameraStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getCameraStatus');
    }
    try {
      return await gen_api.getCameraStatus(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error getting camera status from native: $e');
      rethrow;
    }
  }

  /// Set camera cooler
  static Future<void> setCameraCooler(
      String deviceId, bool enabled, double? targetTemp) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraCooler');
    }
    try {
      await gen_api.setCameraCooler(
        deviceId: deviceId,
        enabled: enabled ? 1 : 0,
        targetTemp: targetTemp,
      );
    } catch (e) {
      debugPrint('[Bridge] Error setting camera cooler from native: $e');
      rethrow;
    }
  }

  /// Set camera gain
  static Future<void> setCameraGain(String deviceId, int gain) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraGain');
    }
    try {
      await gen_api.setCameraGain(deviceId: deviceId, gain: gain);
    } catch (e) {
      debugPrint('[Bridge] Error setting camera gain from native: $e');
      rethrow;
    }
  }

  /// Set camera offset
  static Future<void> setCameraOffset(String deviceId, int offset) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraOffset');
    }
    try {
      await gen_api.setCameraOffset(deviceId: deviceId, offset: offset);
    } catch (e) {
      debugPrint('[Bridge] Error setting camera offset from native: $e');
      rethrow;
    }
  }

  /// Set camera binning
  static Future<void> setCameraBinning(
      String deviceId, int binX, int binY) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraBinning');
    }
    try {
      await gen_api.apiSetCameraBinning(
          deviceId: deviceId, binX: binX, binY: binY);
    } catch (e) {
      debugPrint('[Bridge] Error setting camera binning from native: $e');
      rethrow;
    }
  }

  /// Set camera readout mode by index
  /// modeIndex: 0 = default/high quality, 1 = fast readout, etc.
  static Future<void> setReadoutMode({
    required String deviceId,
    required int modeIndex,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setReadoutMode');
    }
    try {
      await gen_api.apiCameraSetReadoutMode(
        deviceId: deviceId,
        modeIndex: modeIndex,
      );
    } catch (e) {
      debugPrint('[Bridge] Error calling native setReadoutMode: $e');
      rethrow;
    }
  }

  /// Start a camera exposure
  static Future<void> startExposure({
    required String deviceId,
    required double durationSecs,
    required int gain,
    required int offset,
    required int binX,
    required int binY,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('startExposure');
    }
    try {
      await gen_api.apiCameraStartExposure(
        deviceId: deviceId,
        durationSecs: durationSecs,
        gain: gain,
        offset: offset,
        binX: binX,
        binY: binY,
      );
    } catch (e) {
      debugPrint('[Bridge] Error calling native startExposure: $e');
      rethrow;
    }
  }

  /// Cancel current exposure
  static Future<void> cancelExposure(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('cancelExposure');
    }
    try {
      await gen_api.apiCameraCancelExposure(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error calling native cancelExposure: $e');
      rethrow;
    }
  }

  /// Get last captured image
  static Future<CapturedImageResult?> getLastImage(
      {required String deviceId}) async {
    debugPrint(
        '[Bridge] getLastImage called for device $deviceId, nativeAvailable=$_nativeAvailable');
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getLastImage');
    }
    try {
      debugPrint('[Bridge] Calling crateApiApiGetLastImage...');
      final rustResult = await gen_api.apiGetLastImage(deviceId: deviceId);
      debugPrint(
          '[Bridge] Got result: ${rustResult.width}x${rustResult.height}, displayData size: ${rustResult.displayData.length}');
      return rustResult;
    } catch (e) {
      debugPrint('[Bridge] Error calling native getLastImage: $e');
      rethrow;
    }
  }

  // =========================================================================
  // Mount Control
  // =========================================================================

  /// Get mount status
  static Future<MountStatus> getMountStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getMountStatus');
    }
    try {
      return await gen_api.apiGetMountStatus(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error getting mount status from native: $e');
      rethrow;
    }
  }

  /// Slew the mount to coordinates
  static Future<void> mountSlewToCoordinates(
      String deviceId, double ra, double dec) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSlewToCoordinates');
    }
    try {
      await gen_api.apiMountSlewToCoordinates(
          deviceId: deviceId, ra: ra, dec: dec);
    } catch (e) {
      debugPrint('[Bridge] Error slewing mount via native: $e');
      rethrow;
    }
  }

  /// Sync the mount to coordinates
  static Future<void> mountSync(String deviceId, double ra, double dec) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSync');
    }
    try {
      await gen_api.apiMountSyncToCoordinates(
          deviceId: deviceId, ra: ra, dec: dec);
    } catch (e) {
      debugPrint('[Bridge] Error syncing mount via native: $e');
      rethrow;
    }
  }

  /// Park the mount
  static Future<void> mountPark(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountPark');
    }
    try {
      await gen_api.apiMountPark(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error parking mount via native: $e');
      rethrow;
    }
  }

  /// Unpark the mount
  static Future<void> mountUnpark(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountUnpark');
    }
    try {
      await gen_api.apiMountUnpark(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error unparking mount via native: $e');
      rethrow;
    }
  }

  /// Set mount tracking
  static Future<void> mountSetTracking(String deviceId, bool enabled) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSetTracking');
    }
    try {
      await gen_api.apiMountSetTracking(
          deviceId: deviceId, enabled: enabled ? 1 : 0);
    } catch (e) {
      debugPrint('[Bridge] Error setting mount tracking via native: $e');
      rethrow;
    }
  }

  /// Pulse guide mount
  static Future<void> mountPulseGuide(
      String deviceId, String direction, int durationMs) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountPulseGuide');
    }
    try {
      await gen_api.apiMountPulseGuide(
        deviceId: deviceId,
        direction: direction,
        durationMs: durationMs,
      );
    } catch (e) {
      debugPrint('[Bridge] Error pulse guiding mount via native: $e');
      rethrow;
    }
  }

  /// Set mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
  static Future<void> mountSetTrackingRate(String deviceId, int rate) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSetTrackingRate');
    }
    try {
      await gen_api.mountSetTrackingRate(deviceId: deviceId, rate: rate);
    } catch (e) {
      debugPrint('[Bridge] Error setting tracking rate from native: $e');
      rethrow;
    }
  }

  /// Get mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
  static Future<int> mountGetTrackingRate(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountGetTrackingRate');
    }
    try {
      return await gen_api.mountGetTrackingRate(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error getting tracking rate from native: $e');
      rethrow;
    }
  }

  /// Move mount axis at specified rate (degrees/second)
  /// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
  /// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
  static Future<void> mountMoveAxis(
      String deviceId, int axis, double rate) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountMoveAxis');
    }
    try {
      await gen_api.mountMoveAxis(deviceId: deviceId, axis: axis, rate: rate);
    } catch (e) {
      debugPrint('[Bridge] Error moving axis from native: $e');
      rethrow;
    }
  }

  /// Slew mount to alt/az coordinates
  static Future<void> mountSlewAltAz(
      String deviceId, double altitude, double azimuth) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSlewAltAz');
    }
    try {
      await gen_api.mountSlewAltAz(
          deviceId: deviceId, altitude: altitude, azimuth: azimuth);
    } catch (e) {
      debugPrint('[Bridge] Error slewing mount to alt/az: $e');
      rethrow;
    }
  }

  /// Find mount home position
  static Future<void> mountFindHome(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountFindHome');
    }
    try {
      await gen_api.mountFindHome(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error finding mount home: $e');
      rethrow;
    }
  }

  /// Abort current mount motion
  static Future<void> mountAbort(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountAbort');
    }
    try {
      await gen_api.mountAbort(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error aborting mount motion: $e');
      rethrow;
    }
  }

  // =========================================================================
  // Focuser Control
  // =========================================================================

  /// Get focuser status
  static Future<FocuserStatus> getFocuserStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getFocuserStatus');
    }
    try {
      return await gen_api.apiGetFocuserStatus(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error getting focuser status from native: $e');
      rethrow;
    }
  }

  /// Move focuser to position
  static Future<void> focuserMoveTo(String deviceId, int position) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('focuserMoveTo');
    }
    try {
      await gen_api.apiFocuserMoveTo(deviceId: deviceId, position: position);
    } catch (e) {
      debugPrint('[Bridge] Error moving focuser via native: $e');
      rethrow;
    }
  }

  /// Move focuser by relative amount
  static Future<void> focuserMoveRelative(String deviceId, int delta) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('focuserMoveRelative');
    }
    try {
      await gen_api.apiFocuserMoveRelative(deviceId: deviceId, delta: delta);
    } catch (e) {
      debugPrint('[Bridge] Error moving focuser relative via native: $e');
      rethrow;
    }
  }

  /// Halt focuser
  static Future<void> apiFocuserHalt({required String deviceId}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiFocuserHalt');
    }
    try {
      await gen_api.apiFocuserHalt(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error halting focuser via native: $e');
      rethrow;
    }
  }

  // =========================================================================
  // Filter Wheel Control
  // =========================================================================

  /// Get filter wheel status
  static Future<FilterWheelStatus> getFilterWheelStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getFilterWheelStatus');
    }
    try {
      return await gen_api.apiGetFilterwheelStatus(deviceId: deviceId);
    } catch (e) {
      debugPrint('[Bridge] Error getting filter wheel status from native: $e');
      rethrow;
    }
  }

  /// Set filter wheel position
  static Future<void> filterWheelSetPosition(
      String deviceId, int position) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('filterWheelSetPosition');
    }
    try {
      await gen_api.apiFilterwheelSetPosition(
          deviceId: deviceId, position: position);
    } catch (e) {
      debugPrint('[Bridge] Error setting filter wheel position via native: $e');
      rethrow;
    }
  }

  /// Set filter wheel position (API method)
  static Future<void> apiFilterwheelSetPosition({
    required String deviceId,
    required int position,
  }) async {
    await filterWheelSetPosition(deviceId, position);
  }

  /// Get filter wheel names (API method)
  static Future<List<String>> apiFilterwheelGetNames({
    required String deviceId,
  }) async {
    final status = await getFilterWheelStatus(deviceId);
    return status.filterNames;
  }

  /// Set filter wheel by name (API method)
  static Future<void> apiFilterwheelSetByName({
    required String deviceId,
    required String name,
  }) async {
    final status = await getFilterWheelStatus(deviceId);
    final index = status.filterNames.indexOf(name);
    if (index < 0) {
      throw ArgumentError('Filter "$name" not found on device $deviceId');
    }
    await filterWheelSetPosition(deviceId, index);
  }

  // =========================================================================
  // Session Management
  // =========================================================================

  /// Get current session state
  static Future<NativeSessionState> getSessionState() async {
    return NativeSessionState(
      isActive: false,
      totalExposures: 0,
      completedExposures: 0,
      totalIntegrationSecs: 0.0,
      isGuiding: false,
      isCapturing: false,
      isDithering: false,
    );
  }

  /// Start a new imaging session
  static Future<void> startSession(
      {String? targetName, double? ra, double? dec}) async {
    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.sequencer,
      eventType: 'SessionStarted',
      data: {'target': targetName},
    ));
  }

  /// End the current session
  static Future<void> endSession() async {
    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.sequencer,
      eventType: 'SessionEnded',
      data: {},
    ));
  }

  // =========================================================================
  // Plate Solving
  // =========================================================================

  /// Check if plate solver is available
  static bool isPlateSolverAvailable() {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('isPlateSolverAvailable');
    }
    return gen_api.apiIsPlateSolverAvailable();
  }

  /// Get plate solver path
  static String? getPlateSolverPath() {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getPlateSolverPath');
    }
    return gen_api.apiGetPlateSolverPath();
  }

  /// Plate solve blind
  static Future<PlateSolveResult> plateSolveBlind(String filePath) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('plateSolveBlind');
    }
    return gen_api.apiPlateSolveBlind(filePath: filePath);
  }

  /// Plate solve near coordinates
  static Future<PlateSolveResult> plateSolveNear(
    String filePath,
    double hintRa,
    double hintDec,
    double searchRadius,
  ) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('plateSolveNear');
    }
    return gen_api.apiPlateSolveNear(
      filePath: filePath,
      hintRa: hintRa,
      hintDec: hintDec,
      searchRadius: searchRadius,
    );
  }

  // =========================================================================
  // Autofocus
  // =========================================================================

  /// Run autofocus
  static Future<AutofocusResultApi> apiRunAutofocus({
    required String deviceId,
    required String cameraId,
    required AutofocusConfigApi config,
  }) async {
    if (_nativeAvailable) {
      try {
        return await gen_api.apiRunAutofocus(
          deviceId: deviceId,
          cameraId: cameraId,
          config: config,
        );
      } catch (e) {
        debugPrint('[Bridge] Error running autofocus via native: $e');
        rethrow;
      }
    }
    throw UnsupportedError(_fallbackErrorMessage);
  }

  /// Cancel autofocus
  static Future<void> apiCancelAutofocus() async {
    if (_nativeAvailable) {
      try {
        await gen_api.apiCancelAutofocus();
        return;
      } catch (e) {
        debugPrint('[Bridge] Error cancelling autofocus via native: $e');
        rethrow;
      }
    }
    throw UnsupportedError(_fallbackErrorMessage);
  }

  // =========================================================================
  // PHD2 Guiding
  // =========================================================================

  /// Check if PHD2 is running
  static Future<bool> isPhd2Running(
      {String host = 'localhost', int port = 4400}) async {
    return phd2.checkPhd2Running(host: host, port: port);
  }

  /// Connect to PHD2 (auto-launches if not running on Windows)
  static Future<void> phd2Connect({String? host, int? port}) async {
    final targetHost = host ?? 'localhost';
    final targetPort = port ?? 4400;

    // Check if PHD2 is already running
    bool phd2Running =
        await phd2.checkPhd2Running(host: targetHost, port: targetPort);

    // If PHD2 is not running and we're on localhost, try to launch it
    if (!phd2Running &&
        (targetHost == 'localhost' || targetHost == '127.0.0.1')) {
      debugPrint(
          'DEBUG: PHD2 not running on localhost. Platform.isWindows: ${Platform.isWindows}');
      if (Platform.isWindows) {
        debugPrint('[PHD2] not running, attempting to launch...');
        try {
          // Common PHD2 installation paths on Windows
          final phd2Paths = [
            r'C:\Program Files (x86)\PHDGuiding2\phd2.exe',
            r'C:\Program Files\PHDGuiding2\phd2.exe',
            r'C:\Program Files (x86)\PHD2\phd2.exe',
            r'C:\Program Files\PHD2\phd2.exe',
          ];

          String? phd2Path;
          for (final path in phd2Paths) {
            if (await File(path).exists()) {
              phd2Path = path;
              break;
            }
          }

          if (phd2Path != null) {
            await Process.start(phd2Path, [], mode: ProcessStartMode.detached);
            debugPrint('[PHD2] launched from: $phd2Path');

            // Wait for PHD2 to start and open its server
            for (int i = 0; i < 30; i++) {
              await Future<void>.delayed(const Duration(seconds: 1));
              if (await phd2.checkPhd2Running(
                  host: targetHost, port: targetPort)) {
                phd2Running = true;
                debugPrint('[PHD2] is now running');
                break;
              }
            }

            if (!phd2Running) {
              throw Exception(
                  'PHD2 was launched but did not start its server within 30 seconds');
            }
          } else {
            throw Exception(
                'PHD2 not found. Please install PHD2 from https://openphdguiding.org/');
          }
        } catch (e) {
          debugPrint('[PHD2] Failed to launch: $e');
          throw Exception('Could not launch PHD2: $e');
        }
      } else {
        debugPrint(
            'DEBUG: Not on Windows, cannot auto-launch PHD2. Platform: ${Platform.operatingSystem}');
        throw Exception(
            'PHD2 is not running. Platform: ${Platform.operatingSystem}. Please start PHD2 manually.');
      }
    }

    // Now connect to PHD2
    _phd2Client?.dispose();
    _phd2Client = phd2.Phd2Client(
      host: targetHost,
      port: targetPort,
    );

    await _phd2Client!.connect();

    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.guiding,
      eventType: 'PHD2Connected',
      data: {'host': targetHost, 'port': targetPort},
    ));
  }

  /// Disconnect from PHD2
  static Future<void> phd2Disconnect() async {
    _phd2Client?.disconnect();
    _phd2Client = null;

    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.guiding,
      eventType: 'PHD2Disconnected',
      data: {},
    ));
  }

  /// Start guiding
  static Future<void> phd2StartGuiding({
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected. Connect to PHD2 first.');
    }

    await _phd2Client!.startGuiding(
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );

    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.guiding,
      eventType: 'GuidingStarted',
      data: {},
    ));
  }

  /// Stop guiding
  static Future<void> phd2StopGuiding() async {
    if (_phd2Client != null && _phd2Client!.isConnected) {
      await _phd2Client!.stopGuiding();
    }

    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.guiding,
      eventType: 'GuidingStopped',
      data: {},
    ));
  }

  /// Pause guiding
  static Future<void> phd2PauseGuiding() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.pauseGuiding();
  }

  /// Resume guiding
  static Future<void> phd2ResumeGuiding() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.resumeGuiding();
  }

  /// Dither
  static Future<void> phd2Dither({
    required double amount,
    required bool raOnly,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected. Connect to PHD2 first.');
    }

    await _phd2Client!.dither(
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );

    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.guiding,
      eventType: 'DitherStarted',
      data: {'amount': amount, 'raOnly': raOnly},
    ));
  }

  /// Get PHD2 status
  static Future<Phd2Status> phd2GetStatus() async {
    if (_phd2Client == null) {
      return const Phd2Status(
        connected: false,
        state: 'Disconnected',
        rmsRa: 0,
        rmsDec: 0,
        rmsTotal: 0,
        snr: 0,
        starMass: 0,
        pixelScale: 0,
      );
    }

    return Phd2Status(
      connected: _phd2Client!.isConnected,
      state: _phd2Client!.state.name,
      rmsRa: _phd2Client!.rmsRa,
      rmsDec: _phd2Client!.rmsDec,
      rmsTotal: _phd2Client!.rmsTotal,
      snr: _phd2Client!.snr,
      starMass: _phd2Client!.starMass,
      pixelScale: 0, // Would need to call getPixelScale() separately
    );
  }

  static Future<void> guiderStartGuiding({
    required String deviceId,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderStartGuiding(
        deviceId: normalizedDeviceId,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2StartGuiding(
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    _nativeBridgeRequired('guiderStartGuiding');
  }

  static Future<void> guiderStop({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderStop(deviceId: normalizedDeviceId);
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2StopGuiding();
      return;
    }
    _nativeBridgeRequired('guiderStop');
  }

  static Future<void> guiderDither({
    required String deviceId,
    required double amount,
    required bool raOnly,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderDither(
        deviceId: normalizedDeviceId,
        amount: amount,
        raOnly: raOnly ? 1 : 0,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2Dither(
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );
      return;
    }
    _nativeBridgeRequired('guiderDither');
  }

  static Future<void> guiderLoop({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderLoop(deviceId: normalizedDeviceId);
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2Loop();
      return;
    }
    _nativeBridgeRequired('guiderLoop');
  }

  static Future<(double, double)> guiderFindStar({
    required String deviceId,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      return gen_api.apiGuiderFindStar(deviceId: normalizedDeviceId);
    }
    if (normalizedDeviceId == 'phd2_guider') {
      return phd2FindStar();
    }
    _nativeBridgeRequired('guiderFindStar');
  }

  static Future<void> guiderSetLockPosition({
    required String deviceId,
    required double x,
    required double y,
    bool exact = false,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderSetLockPosition(
        deviceId: normalizedDeviceId,
        x: x,
        y: y,
        exact: exact,
      );
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2SetLockPosition(x: x, y: y, exact: exact);
      return;
    }
    _nativeBridgeRequired('guiderSetLockPosition');
  }

  static Future<(double, double)> guiderGetLockPosition({
    required String deviceId,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      return gen_api.apiGuiderGetLockPosition(deviceId: normalizedDeviceId);
    }
    if (normalizedDeviceId == 'phd2_guider') {
      return phd2GetLockPosition();
    }
    _nativeBridgeRequired('guiderGetLockPosition');
  }

  static Future<void> guiderDeselectStar({required String deviceId}) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      await gen_api.apiGuiderDeselectStar(deviceId: normalizedDeviceId);
      return;
    }
    if (normalizedDeviceId == 'phd2_guider') {
      await phd2DeselectStar();
      return;
    }
    _nativeBridgeRequired('guiderDeselectStar');
  }

  static Future<Phd2StarImage> guiderGetStarImage({
    required String deviceId,
    int size = 50,
  }) async {
    final normalizedDeviceId = _canonicalGuiderDeviceId(deviceId);
    if (_nativeAvailable) {
      return gen_api.apiGuiderGetStarImage(
          deviceId: normalizedDeviceId, size: size);
    }
    if (normalizedDeviceId == 'phd2_guider') {
      return phd2GetStarImage(size: size);
    }
    _nativeBridgeRequired('guiderGetStarImage');
  }

  // =========================================================================
  // Built-in Guider Configuration
  // =========================================================================

  /// Get the built-in guider configuration.
  /// Returns a map with keys matching GuiderConfig fields.
  static Future<Map<String, dynamic>> builtinGuiderGetConfigRaw() async {
    if (_nativeAvailable) {
      final config = await gen_api.apiBuiltinGuiderGetConfig();
      return {
        'exposureSecs': config.exposureSecs,
        'gain': config.gain,
        'offset': config.offset,
        'binning': config.binning,
        'calibrationMs': config.calibrationMs,
        'settleSleepMs': config.settleSleepMs.toInt(),
        'minPulseMs': config.minPulseMs,
        'maxPulseMs': config.maxPulseMs,
      };
    }
    _nativeBridgeRequired('builtinGuiderGetConfig');
  }

  /// Set the built-in guider configuration.
  static Future<void> builtinGuiderSetConfigRaw({
    required double exposureSecs,
    required int gain,
    required int offset,
    required int binning,
    required int calibrationMs,
    required int settleSleepMs,
    required double minPulseMs,
    required double maxPulseMs,
  }) async {
    if (_nativeAvailable) {
      await gen_api.apiBuiltinGuiderSetConfig(
        exposureSecs: exposureSecs,
        gain: gain,
        offset: offset,
        binning: binning,
        calibrationMs: calibrationMs,
        settleSleepMs: BigInt.from(settleSleepMs),
        minPulseMs: minPulseMs,
        maxPulseMs: maxPulseMs,
      );
      return;
    }
    _nativeBridgeRequired('builtinGuiderSetConfig');
  }

  /// Auto-select guide star in PHD2
  static Future<void> phd2AutoSelectStar() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.autoSelectStar();
  }

  /// Start looping exposures in PHD2
  static Future<void> phd2Loop() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.loop();
  }

  /// Get PHD2 star image
  static Future<Phd2StarImage> phd2GetStarImage({int size = 50}) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }

    final result = await _phd2Client!.getStarImage(size: size);

    // PHD2 get_star_image returns:
    //   frame: scalar frame number
    //   width, height: top-level integers
    //   star_pos: [x, y] array (if star is selected)
    //   pixels: base64-encoded pixel data
    final frame = (result['frame'] as num?)?.toInt() ?? 0;
    final width = (result['width'] as num?)?.toInt() ?? size;
    final height = (result['height'] as num?)?.toInt() ?? size;

    // star_pos is a positional array [x, y], not a named map
    final starPos = result['star_pos'] as List?;
    final starX = (starPos != null && starPos.length >= 1)
        ? (starPos[0] as num).toDouble()
        : width / 2.0;
    final starY = (starPos != null && starPos.length >= 2)
        ? (starPos[1] as num).toDouble()
        : height / 2.0;

    // Decode base64 pixel data
    final pixelsB64 = result['pixels'] as String?;
    if (pixelsB64 == null) {
      throw Exception('No pixel data in PHD2 star image response');
    }
    final pixels = base64Decode(pixelsB64);

    return Phd2StarImage(
      frame: frame,
      width: width,
      height: height,
      starX: starX,
      starY: starY,
      pixels: pixels,
    );
  }

  /// Get PHD2 algorithm parameter names
  static Future<List<String>> phd2GetAlgoParamNames(
      {required String axis}) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.getAlgoParamNames(axis: axis);
  }

  /// Get PHD2 algorithm parameter value
  static Future<double> phd2GetAlgoParam({
    required String axis,
    required String name,
  }) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.getAlgoParam(axis: axis, name: name);
  }

  /// Set PHD2 algorithm parameter
  static Future<void> phd2SetAlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.setAlgoParam(axis: axis, name: name, value: value);
  }

  /// Set PHD2 paused state
  static Future<void> phd2SetPaused({required bool paused}) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    if (paused) {
      await _phd2Client!.pauseGuiding();
    } else {
      await _phd2Client!.resumeGuiding();
    }
  }

  /// Clear PHD2 calibration
  static Future<void> phd2ClearCalibration({String which = 'both'}) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.clearCalibration(which: which);
  }

  /// Flip PHD2 calibration (for meridian flip)
  static Future<void> phd2FlipCalibration() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.flipCalibration();
  }

  /// Get PHD2 calibration data
  static Future<gen_api.Phd2CalibrationData> phd2GetCalibrationData() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }

    // Query PHD2 for calibration data
    final result = await _phd2Client!.getCalibrationData();

    // PHD2 returns null if not calibrated
    if (result == null) {
      return const gen_api.Phd2CalibrationData(
        isCalibrated: false,
        raAngle: null,
        decAngle: null,
        raRate: null,
        decRate: null,
      );
    }

    // Extract calibration parameters from PHD2's response
    // PHD2 returns xAngle/yAngle for RA/Dec rotation angles
    // and xRate/yRate for guide rates in pixels/second
    final xAngle = (result['xAngle'] as num?)?.toDouble();
    final yAngle = (result['yAngle'] as num?)?.toDouble();
    final xRate = (result['xRate'] as num?)?.toDouble();
    final yRate = (result['yRate'] as num?)?.toDouble();

    return gen_api.Phd2CalibrationData(
      isCalibrated: true,
      raAngle: xAngle,
      decAngle: yAngle,
      raRate: xRate,
      decRate: yRate,
    );
  }

  /// Find a guide star in PHD2
  static Future<(double, double)> phd2FindStar() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.findStar();
  }

  /// Set PHD2 lock position
  static Future<void> phd2SetLockPosition({
    required double x,
    required double y,
    bool exact = false,
  }) async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.setLockPosition(x: x, y: y, exact: exact);
  }

  /// Get PHD2 lock position
  static Future<(double, double)> phd2GetLockPosition() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    return await _phd2Client!.getLockPosition();
  }

  /// Deselect star in PHD2
  static Future<void> phd2DeselectStar() async {
    if (_phd2Client == null || !_phd2Client!.isConnected) {
      throw Exception('PHD2 not connected');
    }
    await _phd2Client!.deselectStar();
  }

  // =========================================================================
  // Sequencer API
  // =========================================================================

  /// Sequencer state
  static SequencerState _sequencerState = SequencerState.idle;
  static String? _loadedSequenceJson;
  static bool _sequencerEventsSubscribed = false;
  static CameraStatus? get cameraStatus => _cameraStatus;
  static FocuserStatus? get focuserStatus => _focuserStatus;
  static FilterWheelStatus? get filterWheelStatus => _filterWheelStatus;
  static String? get loadedSequenceJson => _loadedSequenceJson;

  /// Subscribe to sequencer events (must be called to receive sequencer events)
  /// This sets up the event forwarding from the Rust sequencer to the main event stream
  static Future<void> sequencerSubscribeEvents() async {
    if (_sequencerEventsSubscribed) return; // Already subscribed

    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSubscribeEvents');
    }

    try {
      await gen_api.apiSequencerSubscribeEvents();
      _sequencerEventsSubscribed = true;
      debugPrint('[Bridge] Subscribed to sequencer events via native');
    } catch (e) {
      debugPrint('[Bridge] Error subscribing to sequencer events: $e');
      rethrow;
    }
  }

  /// Load a sequence from JSON
  static Future<void> sequencerLoadJson(String json) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerLoadJson');
    }

    try {
      await gen_api.apiSequencerLoadJson(json: json);
      _loadedSequenceJson = json;
    } catch (e) {
      debugPrint('[Bridge] Error loading sequence via native: $e');
      rethrow;
    }
  }

  /// Set connected devices for the sequencer
  static Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetDevices');
    }

    try {
      await gen_api.apiSequencerSetDevices(
        cameraId: cameraId,
        mountId: mountId,
        focuserId: focuserId,
        filterwheelId: filterwheelId,
        rotatorId: rotatorId,
        filterNames: filterNames,
        filterFocusOffsets: filterFocusOffsets,
      );
      debugPrint(
          '[Bridge] Set sequencer devices: camera=$cameraId, mount=$mountId, focuser=$focuserId, filterwheel=$filterwheelId, rotator=$rotatorId, filterNames=$filterNames, filterFocusOffsets=$filterFocusOffsets');
    } catch (e) {
      debugPrint('[Bridge] Error setting sequencer devices: $e');
      rethrow;
    }
  }

  /// Set the safety fail mode for the sequencer
  static Future<void> sequencerSetSafetyFailMode(String mode) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSafetyFailMode');
    }

    try {
      await gen_api.apiSequencerSetSafetyFailMode(mode: mode);
      debugPrint('[Bridge] Set sequencer safety fail mode: $mode');
    } catch (e) {
      debugPrint('[Bridge] Error setting sequencer safety fail mode: $e');
      rethrow;
    }
  }

  /// Set the save path for sequencer images
  static Future<void> sequencerSetSavePath({String? path}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSavePath');
    }

    try {
      await gen_api.apiSequencerSetSavePath(path: path);
      debugPrint('[Bridge] Set sequencer save path: ${path ?? "<none>"}');
    } catch (e) {
      debugPrint('[Bridge] Error setting sequencer save path: $e');
      rethrow;
    }
  }

  /// Update dither configuration on the running sequencer
  static Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateDitherConfig');
    }

    try {
      await gen_api.apiSequencerUpdateDitherConfig(
        pixels: pixels,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
        raOnly: raOnly,
      );
      debugPrint(
          '[Bridge] Updated sequencer dither config: pixels=$pixels, settlePixels=$settlePixels, settleTime=$settleTime, settleTimeout=$settleTimeout, raOnly=$raOnly');
    } catch (e) {
      debugPrint('[Bridge] Error updating sequencer dither config: $e');
      rethrow;
    }
  }

  /// Update location on the running sequencer
  static Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateLocation');
    }

    try {
      await gen_api.apiSequencerUpdateLocation(
        latitude: latitude,
        longitude: longitude,
      );
      debugPrint(
          '[Bridge] Updated sequencer location: lat=$latitude, lon=$longitude');
    } catch (e) {
      debugPrint('[Bridge] Error updating sequencer location: $e');
      rethrow;
    }
  }

  /// Update filter focus offsets on the running sequencer
  static Future<void> sequencerUpdateFilterOffsets(
      {required Map<String, int> offsets}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateFilterOffsets');
    }

    try {
      await gen_api.apiSequencerUpdateFilterOffsets(offsets: offsets);
      debugPrint('[Bridge] Updated sequencer filter offsets: $offsets');
    } catch (e) {
      debugPrint('[Bridge] Error updating sequencer filter offsets: $e');
      rethrow;
    }
  }

  /// Start the loaded sequence
  static Future<void> sequencerStart() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerStart');
    }

    // Ensure event subscription is set up before starting
    await sequencerSubscribeEvents();

    try {
      await gen_api.apiSequencerStart();
      _sequencerState = SequencerState.running;
    } catch (e) {
      debugPrint('[Bridge] Error starting sequence via native: $e');
      rethrow;
    }
  }

  /// Pause the running sequence
  static Future<void> sequencerPause() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerPause');
    }

    try {
      await gen_api.apiSequencerPause();
      _sequencerState = SequencerState.paused;
    } catch (e) {
      debugPrint('[Bridge] Error pausing sequence via native: $e');
      rethrow;
    }
  }

  /// Resume a paused sequence
  static Future<void> sequencerResume() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerResume');
    }

    try {
      await gen_api.apiSequencerResume();
      _sequencerState = SequencerState.running;
    } catch (e) {
      debugPrint('[Bridge] Error resuming sequence via native: $e');
      rethrow;
    }
  }

  /// Stop the running sequence
  static Future<void> sequencerStop() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerStop');
    }

    try {
      await gen_api.apiSequencerStop();
      _sequencerState = SequencerState.idle;
      _loadedSequenceJson = null;
    } catch (e) {
      debugPrint('[Bridge] Error stopping sequence via native: $e');
      rethrow;
    }
  }

  /// Skip the current node
  static Future<void> sequencerSkip() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSkip');
    }

    try {
      await gen_api.apiSequencerSkip();
    } catch (e) {
      debugPrint('[Bridge] Error skipping node via native: $e');
      rethrow;
    }
  }

  /// Reset the sequencer
  static Future<void> sequencerReset() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerReset');
    }

    try {
      await gen_api.apiSequencerReset();
      _sequencerState = SequencerState.idle;
      _loadedSequenceJson = null;
    } catch (e) {
      debugPrint('[Bridge] Error resetting sequencer via native: $e');
      rethrow;
    }
  }

  /// Get the current sequencer state
  static SequencerState getSequencerState() => _sequencerState;

  /// Subscribe to sequencer events
  /// Returns a stream of sequencer events
  static Stream<NightshadeEvent> sequencerEventStream() {
    if (!_nativeAvailable) {
      return Stream<NightshadeEvent>.error(
        UnsupportedError(
          'Operation "sequencerEventStream" requires the native bridge.\n$_fallbackErrorMessage',
        ),
      );
    }

    return gen_api
        .apiEventStream()
        .where((event) => event.category == gen_event.EventCategory.sequencer);
  }

  static bool _simulationMode = false;

  /// Set simulation mode (use mock devices instead of real hardware)
  static Future<void> sequencerSetSimulationMode(bool enabled) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSimulationMode');
    }

    try {
      await gen_api.apiSequencerSetSimulationMode(enabled: enabled);
      _simulationMode = enabled;
      debugPrint(
          '[Bridge] Simulation mode via native: ${enabled ? "enabled" : "disabled"}');
    } catch (e) {
      debugPrint('[Bridge] Error setting simulation mode via native: $e');
      rethrow;
    }
  }

  /// Check if simulation mode is enabled
  static bool isSimulationMode() => _simulationMode;

  /// Get sequencer status
  static Future<SequencerStatus> sequencerGetStatus() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerGetStatus');
    }

    try {
      final nativeState = await gen_api.apiSequencerGetState();
      // Calculate progress from exposures
      final progress = nativeState.totalExposures > 0
          ? nativeState.completedExposures / nativeState.totalExposures
          : 0.0;
      return SequencerStatus(
        state: nativeState.state,
        currentNodeId: nativeState.currentNodeId,
        currentNodeName: nativeState.currentNodeName,
        progress: progress,
        message: nativeState.message,
      );
    } catch (e) {
      debugPrint('[Bridge] Error getting sequencer status via native: $e');
      rethrow;
    }
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  /// Set the checkpoint directory
  static Future<void> sequencerSetCheckpointDir(String path) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetCheckpointDir');
    }

    try {
      await gen_api.apiSequencerSetCheckpointDir(path: path);
    } catch (e) {
      debugPrint('[Bridge] Error setting checkpoint dir via native: $e');
      rethrow;
    }
  }

  /// Check if a checkpoint exists
  static Future<bool> sequencerHasCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerHasCheckpoint');
    }

    try {
      return await gen_api.apiSequencerHasCheckpoint();
    } catch (e) {
      debugPrint('[Bridge] Error checking checkpoint via native: $e');
      rethrow;
    }
  }

  /// Get checkpoint info
  static Future<CheckpointInfoApi?> sequencerGetCheckpointInfo() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerGetCheckpointInfo');
    }

    try {
      final nativeInfo = await gen_api.apiSequencerGetCheckpointInfo();
      if (nativeInfo == null) return null;
      // Map from FRB-generated type to local type
      return CheckpointInfoApi(
        sequenceName: nativeInfo.sequenceName,
        timestamp: nativeInfo.timestamp,
        completedExposures: nativeInfo.completedExposures,
        completedIntegrationSecs: nativeInfo.completedIntegrationSecs,
        canResume: nativeInfo.canResume,
        ageSeconds: nativeInfo.ageSeconds.toInt(),
      );
    } catch (e) {
      debugPrint('[Bridge] Error getting checkpoint info via native: $e');
      rethrow;
    }
  }

  /// Resume from checkpoint
  static Future<void> sequencerResumeFromCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerResumeFromCheckpoint');
    }

    try {
      await gen_api.apiSequencerResumeFromCheckpoint();
      _sequencerState = SequencerState.running;
    } catch (e) {
      debugPrint('[Bridge] Error resuming from checkpoint via native: $e');
      rethrow;
    }
  }

  /// Discard checkpoint
  static Future<void> sequencerDiscardCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerDiscardCheckpoint');
    }

    try {
      await gen_api.apiSequencerClearCheckpoint();
    } catch (e) {
      debugPrint('[Bridge] Error discarding checkpoint via native: $e');
      rethrow;
    }
  }

  /// Save checkpoint
  static Future<void> sequencerSaveCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSaveCheckpoint');
    }

    try {
      await gen_api.apiSequencerSaveCheckpoint();
    } catch (e) {
      debugPrint('[Bridge] Error saving checkpoint via native: $e');
      rethrow;
    }
  }

  // =========================================================================
  // Rotator Control (API methods)
  // =========================================================================

  /// Move rotator to absolute angle
  static Future<void> apiRotatorMoveTo({
    required String deviceId,
    required double angle,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiRotatorMoveTo');
    }
    await gen_api.apiRotatorMoveTo(deviceId: deviceId, angle: angle);
  }

  /// Move rotator by relative amount
  static Future<void> apiRotatorMoveRelative({
    required String deviceId,
    required double delta,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiRotatorMoveRelative');
    }
    await gen_api.apiRotatorMoveRelative(deviceId: deviceId, delta: delta);
  }

  /// Get rotator status
  static Future<RotatorStatus> apiGetRotatorStatus({
    required String deviceId,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiGetRotatorStatus');
    }
    return gen_api.apiGetRotatorStatus(deviceId: deviceId);
  }

  /// Halt rotator movement
  static Future<void> apiRotatorHalt({
    required String deviceId,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiRotatorHalt');
    }
    await gen_api.apiRotatorHalt(deviceId: deviceId);
  }

  // =========================================================================
  // Equipment Profiles (API methods)
  // =========================================================================

  /// Get all profiles
  static Future<List<EquipmentProfile>> apiGetProfiles() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiGetProfiles');
    }
    return gen_api.apiGetProfiles();
  }

  /// Save a profile
  static Future<void> apiSaveProfile({
    required EquipmentProfile profile,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiSaveProfile');
    }
    gen_api.apiSaveProfile(profile: profile);
  }

  /// Delete a profile
  static Future<void> apiDeleteProfile({
    required String profileId,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiDeleteProfile');
    }
    gen_api.apiDeleteProfile(profileId: profileId);
  }

  /// Load a profile
  static Future<void> apiLoadProfile({
    required String profileId,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiLoadProfile');
    }
    await gen_api.apiLoadProfile(profileId: profileId);
  }

  /// Get active profile
  static Future<EquipmentProfile?> apiGetActiveProfile() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiGetActiveProfile');
    }
    return gen_api.apiGetActiveProfile();
  }

  // =========================================================================
  // Settings (API methods)
  // =========================================================================

  /// Initialize profile storage
  static Future<void> apiInitProfileStorage(
      {required String storagePath}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiInitProfileStorage');
    }
    gen_api.apiInitProfileStorage(storagePath: storagePath);
  }

  /// Initialize settings storage
  static Future<void> apiInitSettingsStorage(
      {required String storagePath}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiInitSettingsStorage');
    }
    gen_api.apiInitSettingsStorage(storagePath: storagePath);
  }

  /// Get application settings
  static Future<AppSettings> apiGetSettings() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiGetSettings');
    }
    return gen_api.apiGetSettings();
  }

  /// Update application settings
  static Future<void> apiUpdateSettings({
    required AppSettings settings,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiUpdateSettings');
    }
    gen_api.apiUpdateSettings(settings: settings);
  }

  // =========================================================================
  // Location (API methods)
  // =========================================================================

  /// Get observer location
  static Future<ObserverLocation?> apiGetLocation() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiGetLocation');
    }
    return gen_api.apiGetLocation();
  }

  /// Set observer location
  static Future<void> apiSetLocation({
    ObserverLocation? location,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiSetLocation');
    }
    gen_api.apiSetLocation(location: location);
  }

  // =========================================================================
  // Image Processing (API methods)
  // =========================================================================

  /// Get image statistics
  static Future<ImageStats> apiGetImageStats({
    required int width,
    required int height,
    required Uint16List data,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiGetImageStats');
    }
    final native =
        gen_api.apiGetImageStats(width: width, height: height, data: data);
    return ImageStats(
      min: native.min,
      max: native.max,
      mean: native.mean,
      median: native.median,
      stdDev: native.stdDev,
      mad: native.stdDev,
    );
  }

  /// Auto-stretch image
  static Future<Uint8List> apiAutoStretchImage({
    required int width,
    required int height,
    required Uint16List data,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiAutoStretchImage');
    }
    return gen_api.apiAutoStretchImage(
        width: width, height: height, data: data);
  }

  /// Debayer image
  static Future<Uint8List> apiDebayerImage({
    required int width,
    required int height,
    required Uint16List data,
    required String patternStr,
    required String algoStr,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiDebayerImage');
    }
    return gen_api.apiDebayerImage(
      width: width,
      height: height,
      data: data,
      patternStr: patternStr,
      algoStr: algoStr,
    );
  }

  // =========================================================================
  // Cleanup
  // =========================================================================

  /// Dispose of resources
  static void dispose() {
    _eventController.close();
  }
}

// SequencerState is now a typedef pointing to gen_api.SequencerState (defined at top of file)
