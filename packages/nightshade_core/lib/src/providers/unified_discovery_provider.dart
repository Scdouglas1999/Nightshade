import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equipment/unified_device.dart';
import '../models/equipment/discovery_state.dart';
import '../services/device_service.dart';
import '../services/device_matching_service.dart';
import 'settings_provider.dart';

/// Provider for the device matching service
final deviceMatchingServiceProvider = Provider<DeviceMatchingService>((ref) {
  return DeviceMatchingService();
});

/// Provider for unified device discovery state
final unifiedDiscoveryProvider =
    StateNotifierProvider<UnifiedDiscoveryNotifier, UnifiedDiscoveryState>((ref) {
  return UnifiedDiscoveryNotifier(ref);
});

/// Notifier for managing unified device discovery across all backends
class UnifiedDiscoveryNotifier extends StateNotifier<UnifiedDiscoveryState> {
  final Ref _ref;
  bool _cancelled = false;

  UnifiedDiscoveryNotifier(this._ref) : super(const UnifiedDiscoveryState());

  /// Discover devices from all available backends in parallel
  ///
  /// This will:
  /// 1. Start discovery on all available backends simultaneously
  /// 2. Track progress per-backend
  /// 3. Group discovered devices using fuzzy matching
  /// 4. Update state as results come in
  Future<void> discoverAll() async {
    _cancelled = false;

    // Get backends that are available on this platform
    final backends = _getAvailableBackends();

    // Initialize backend states
    final initialStates = <DriverBackend, BackendDiscoveryState>{};
    for (final backend in backends) {
      initialStates[backend] = BackendDiscoveryState(
        backend: backend,
        status: DiscoveryStatus.discovering,
      );
    }

    state = UnifiedDiscoveryState(
      backendStates: initialStates,
      rawDevices: [],
      groupedDevices: [],
    );

    // Discover from all backends in parallel
    final futures = <Future<_BackendResult>>[];
    for (final backend in backends) {
      futures.add(_discoverBackend(backend));
    }

    // Process results as they complete
    final results = await Future.wait(futures);

    if (_cancelled) return;

    // Collect all devices
    final allDevices = <AvailableDevice>[];
    final updatedStates = <DriverBackend, BackendDiscoveryState>{};

    for (final result in results) {
      updatedStates[result.backend] = BackendDiscoveryState(
        backend: result.backend,
        status: result.error != null
            ? DiscoveryStatus.error
            : DiscoveryStatus.completed,
        error: result.error,
        devices: result.devices,
        completedAt: DateTime.now(),
      );

      allDevices.addAll(result.devices);
    }

    // Group devices using fuzzy matching
    final matchingService = _ref.read(deviceMatchingServiceProvider);
    final groupedDevices = matchingService.groupDevices(allDevices);

    state = state.copyWith(
      backendStates: updatedStates,
      rawDevices: allDevices,
      groupedDevices: groupedDevices,
    );
  }

  /// Discover from a specific backend only
  ///
  /// Useful for adding servers manually (INDI/Alpaca)
  Future<void> discoverBackend(
    DriverBackend backend, {
    String? host,
    int? port,
  }) async {
    _cancelled = false;

    // Update state to show this backend is discovering
    final currentStates = Map<DriverBackend, BackendDiscoveryState>.from(state.backendStates);
    currentStates[backend] = BackendDiscoveryState(
      backend: backend,
      status: DiscoveryStatus.discovering,
    );
    state = state.copyWith(backendStates: currentStates);

    // Discover
    final result = await _discoverBackend(backend, host: host, port: port);

    if (_cancelled) return;

    // Update state with results
    final updatedStates = Map<DriverBackend, BackendDiscoveryState>.from(state.backendStates);
    updatedStates[backend] = BackendDiscoveryState(
      backend: backend,
      status: result.error != null
          ? DiscoveryStatus.error
          : DiscoveryStatus.completed,
      error: result.error,
      devices: result.devices,
      completedAt: DateTime.now(),
    );

    // Rebuild raw devices from all backends
    final allDevices = <AvailableDevice>[];
    for (final backendState in updatedStates.values) {
      allDevices.addAll(backendState.devices);
    }

    // Re-group devices
    final matchingService = _ref.read(deviceMatchingServiceProvider);
    final groupedDevices = matchingService.groupDevices(allDevices);

    state = state.copyWith(
      backendStates: updatedStates,
      rawDevices: allDevices,
      groupedDevices: groupedDevices,
    );
  }

  /// Discover devices only if results are missing or stale.
  ///
  /// Backends whose last successful discovery completed within [maxAge] are
  /// skipped.  Backends that have never completed or whose results are older
  /// than [maxAge] are rediscovered.  If *all* backends are fresh, this method
  /// returns immediately without any network I/O.
  Future<void> discoverIfNeeded({
    Duration maxAge = const Duration(seconds: 30),
  }) async {
    final now = DateTime.now();
    final backends = _getAvailableBackends();

    final staleBackends = <DriverBackend>[];
    for (final backend in backends) {
      final bs = state.backendStates[backend];
      if (bs == null ||
          !bs.isSuccess ||
          bs.completedAt == null ||
          now.difference(bs.completedAt!) > maxAge) {
        staleBackends.add(backend);
      }
    }

    if (staleBackends.isEmpty) return;

    // If all backends are stale, just do a full discovery
    if (staleBackends.length == backends.length) {
      await discoverAll();
      return;
    }

    // Otherwise, selectively rediscover only the stale backends
    _cancelled = false;

    // Mark stale backends as discovering
    final currentStates =
        Map<DriverBackend, BackendDiscoveryState>.from(state.backendStates);
    for (final backend in staleBackends) {
      currentStates[backend] = BackendDiscoveryState(
        backend: backend,
        status: DiscoveryStatus.discovering,
      );
    }
    state = state.copyWith(backendStates: currentStates);

    // Discover stale backends in parallel
    final futures = <Future<_BackendResult>>[];
    for (final backend in staleBackends) {
      futures.add(_discoverBackend(backend));
    }
    final results = await Future.wait(futures);

    if (_cancelled) return;

    // Merge results into existing state
    final updatedStates =
        Map<DriverBackend, BackendDiscoveryState>.from(state.backendStates);
    for (final result in results) {
      updatedStates[result.backend] = BackendDiscoveryState(
        backend: result.backend,
        status: result.error != null
            ? DiscoveryStatus.error
            : DiscoveryStatus.completed,
        error: result.error,
        devices: result.devices,
        completedAt: DateTime.now(),
      );
    }

    // Rebuild raw devices from all backends
    final allDevices = <AvailableDevice>[];
    for (final backendState in updatedStates.values) {
      allDevices.addAll(backendState.devices);
    }

    // Re-group devices
    final matchingService = _ref.read(deviceMatchingServiceProvider);
    final groupedDevices = matchingService.groupDevices(allDevices);

    state = state.copyWith(
      backendStates: updatedStates,
      rawDevices: allDevices,
      groupedDevices: groupedDevices,
    );
  }

  /// Refresh discovery for all backends
  Future<void> refresh() async {
    await discoverAll();
  }

  /// Cancel ongoing discovery
  void cancel() {
    _cancelled = true;
  }

  /// Clear all discovery results
  void clear() {
    state = const UnifiedDiscoveryState();
  }

  /// Get list of backends available on this platform
  List<DriverBackend> _getAvailableBackends() {
    final backends = <DriverBackend>[
      // Simulator always available
      DriverBackend.simulator,
      // Native always available (may find no devices)
      DriverBackend.native,
      // Alpaca available on all platforms
      DriverBackend.alpaca,
      // INDI available on all platforms
      DriverBackend.indi,
    ];

    // ASCOM only on Windows
    if (Platform.isWindows) {
      backends.insert(1, DriverBackend.ascom);
    }

    return backends;
  }

  /// Discover devices from a specific backend
  Future<_BackendResult> _discoverBackend(
    DriverBackend backend, {
    String? host,
    int? port,
  }) async {
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      final settings = await _ref.read(appSettingsProvider.future);

      List<AvailableDevice> devices = [];

      switch (backend) {
        case DriverBackend.ascom:
        case DriverBackend.native:
        case DriverBackend.simulator:
          // Discover all device types in PARALLEL for faster discovery
          final typeFutures = NightshadeDeviceType.values.map((type) async {
            try {
              final typeDevices = await deviceService.discoverDevices(type);
              // Filter to only include devices from this backend
              return typeDevices.where((d) => d.backend == backend).toList();
            } catch (e) {
              // Log but continue with other types
              return <AvailableDevice>[];
            }
          });
          final results = await Future.wait(typeFutures);
          for (final typeDevices in results) {
            devices.addAll(typeDevices);
          }
          break;

        case DriverBackend.indi:
          final indiHost = host ?? settings.indiServerHost;
          final indiPort = port ?? settings.indiServerPort;
          if (indiHost.isNotEmpty) {
            try {
              devices = await deviceService.discoverIndiAtAddress(indiHost, indiPort);
            } catch (e) {
              return _BackendResult(
                backend: backend,
                devices: [],
                error: 'INDI server connection failed: ${e.toString()}',
              );
            }
          }
          break;

        case DriverBackend.alpaca:
          final alpacaHost = host ?? settings.alpacaServerHost;
          final alpacaPort = port ?? settings.alpacaServerPort;
          if (alpacaHost.isNotEmpty) {
            try {
              devices = await deviceService.discoverAlpacaAtAddress(alpacaHost, alpacaPort);
            } catch (e) {
              return _BackendResult(
                backend: backend,
                devices: [],
                error: 'Alpaca server connection failed: ${e.toString()}',
              );
            }
          }
          break;
      }

      return _BackendResult(backend: backend, devices: devices);
    } catch (e) {
      return _BackendResult(
        backend: backend,
        devices: [],
        error: e.toString(),
      );
    }
  }
}

/// Internal result class for backend discovery
class _BackendResult {
  final DriverBackend backend;
  final List<AvailableDevice> devices;
  final String? error;

  const _BackendResult({
    required this.backend,
    required this.devices,
    this.error,
  });
}

// ============================================================================
// Convenience Providers for Grouped Devices by Type
// ============================================================================

/// Provider for unified cameras (grouped by physical device)
final unifiedCamerasProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.camera);
});

/// Provider for unified mounts
final unifiedMountsProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.mount);
});

/// Provider for unified focusers
final unifiedFocusersProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.focuser);
});

/// Provider for unified filter wheels
final unifiedFilterWheelsProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.filterWheel);
});

/// Provider for unified guiders
final unifiedGuidersProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.guider);
});

/// Provider for unified rotators
final unifiedRotatorsProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.rotator);
});

/// Provider for unified domes
final unifiedDomesProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.dome);
});

/// Provider for unified weather stations
final unifiedWeatherProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.weather);
});

/// Provider for unified safety monitors
final unifiedSafetyMonitorsProvider = Provider<List<UnifiedDevice>>((ref) {
  final discovery = ref.watch(unifiedDiscoveryProvider);
  return discovery.getDevicesByType(NightshadeDeviceType.safetyMonitor);
});
