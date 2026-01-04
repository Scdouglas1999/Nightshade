import 'package:equatable/equatable.dart';
import '../../services/device_service.dart';

/// Priority order for driver backends (lower = higher priority)
const Map<DriverBackend, int> _backendPriority = {
  DriverBackend.native: 0,
  DriverBackend.ascom: 1,
  DriverBackend.alpaca: 2,
  DriverBackend.indi: 3,
  DriverBackend.simulator: 4,
};

/// Represents a single physical device that may be available through multiple backends.
///
/// For example, a ZWO ASI294MC Pro camera might be discoverable via:
/// - Native SDK (highest priority)
/// - ASCOM driver
/// - Alpaca remote connection
/// - INDI server
///
/// This class groups all those discovery results into a single logical device,
/// allowing the user to choose which backend to use for connection.
class UnifiedDevice extends Equatable {
  /// Canonical name for the device (cleaned/normalized for matching)
  final String canonicalName;

  /// Display name (most descriptive name from available backends)
  final String displayName;

  /// Device type (camera, mount, focuser, etc.)
  final NightshadeDeviceType type;

  /// Map of backend -> device info for all available backends
  final Map<DriverBackend, AvailableDevice> availableBackends;

  /// The currently selected backend (user choice, or null for default)
  final DriverBackend? selectedBackend;

  const UnifiedDevice({
    required this.canonicalName,
    required this.displayName,
    required this.type,
    required this.availableBackends,
    this.selectedBackend,
  });

  /// The recommended backend based on static priority (Native > ASCOM > Alpaca > INDI > Simulator)
  /// For capability-aware selection, use [recommendedBackendForCapabilities] instead.
  DriverBackend get recommendedBackend {
    if (availableBackends.isEmpty) {
      return DriverBackend.simulator; // Fallback, shouldn't happen
    }

    DriverBackend best = availableBackends.keys.first;
    int bestPriority = _backendPriority[best] ?? 99;

    for (final backend in availableBackends.keys) {
      final priority = _backendPriority[backend] ?? 99;
      if (priority < bestPriority) {
        best = backend;
        bestPriority = priority;
      }
    }

    return best;
  }

  /// Get recommended backend considering capability requirements.
  /// 
  /// Capability-aware selection considers:
  /// - [requireRemoteOperation]: Prefer network-capable backends (Alpaca, INDI)
  /// - [preferLinuxCompatible]: Prefer cross-platform backends (INDI, Native, Alpaca)
  /// - [requireFullFeatureSet]: Prefer backends with complete feature support (Native, ASCOM)
  /// 
  /// Falls back to [recommendedBackend] if no backends match the requirements.
  DriverBackend recommendedBackendForCapabilities({
    bool requireRemoteOperation = false,
    bool preferLinuxCompatible = false,
    bool requireFullFeatureSet = false,
  }) {
    if (availableBackends.isEmpty) {
      return DriverBackend.simulator;
    }

    // Score each backend based on requirements
    final scoredBackends = <DriverBackend, int>{};
    
    for (final backend in availableBackends.keys) {
      int score = 100 - ((_backendPriority[backend] ?? 99) * 10); // Base score from priority
      
      // Remote operation capability (Alpaca and INDI support remote)
      if (requireRemoteOperation) {
        if (backend == DriverBackend.alpaca || backend == DriverBackend.indi) {
          score += 50; // Strongly prefer remote-capable
        } else {
          score -= 100; // Heavily penalize non-remote backends
        }
      }
      
      // Linux/cross-platform compatibility
      if (preferLinuxCompatible) {
        switch (backend) {
          case DriverBackend.ascom:
            score -= 30; // ASCOM is Windows-only
            break;
          case DriverBackend.indi:
          case DriverBackend.native:
          case DriverBackend.alpaca:
            score += 20; // Cross-platform friendly
            break;
          case DriverBackend.simulator:
            score += 10; // Simulator works everywhere
            break;
        }
      }
      
      // Full feature set (Native and ASCOM typically have best feature support)
      if (requireFullFeatureSet) {
        switch (backend) {
          case DriverBackend.native:
            score += 30; // Native SDK usually has all features
            break;
          case DriverBackend.ascom:
            score += 25; // ASCOM also comprehensive
            break;
          case DriverBackend.alpaca:
            score += 15; // Alpaca mirrors ASCOM
            break;
          case DriverBackend.indi:
            score += 10; // INDI varies by driver
            break;
          case DriverBackend.simulator:
            score += 5; // Simulator has limited features
            break;
        }
      }
      
      scoredBackends[backend] = score;
    }
    
    // Find the highest scoring backend
    DriverBackend best = availableBackends.keys.first;
    int bestScore = scoredBackends[best] ?? 0;
    
    for (final entry in scoredBackends.entries) {
      if (entry.value > bestScore) {
        best = entry.key;
        bestScore = entry.value;
      }
    }
    
    return best;
  }

  /// Get backends sorted by capability score for a given set of requirements.
  /// Useful for UI to show users ranked backend options.
  List<DriverBackend> getSortedBackendsForCapabilities({
    bool requireRemoteOperation = false,
    bool preferLinuxCompatible = false,
    bool requireFullFeatureSet = false,
  }) {
    final backends = availableBackends.keys.toList();
    
    backends.sort((a, b) {
      final scoreA = _getCapabilityScore(a, requireRemoteOperation, preferLinuxCompatible, requireFullFeatureSet);
      final scoreB = _getCapabilityScore(b, requireRemoteOperation, preferLinuxCompatible, requireFullFeatureSet);
      return scoreB.compareTo(scoreA); // Higher score first
    });
    
    return backends;
  }

  int _getCapabilityScore(
    DriverBackend backend,
    bool requireRemote,
    bool preferLinux,
    bool requireFeatures,
  ) {
    int score = 100 - ((_backendPriority[backend] ?? 99) * 10);
    
    if (requireRemote) {
      score += (backend == DriverBackend.alpaca || backend == DriverBackend.indi) ? 50 : -100;
    }
    if (preferLinux) {
      score += backend == DriverBackend.ascom ? -30 : 20;
    }
    if (requireFeatures) {
      score += backend == DriverBackend.native ? 30 : backend == DriverBackend.ascom ? 25 : 10;
    }
    return score;
  }

  /// The active backend (selected by user, or recommended if not selected)
  DriverBackend get activeBackend => selectedBackend ?? recommendedBackend;

  /// Get the device ID for the active backend
  String get activeDeviceId => availableBackends[activeBackend]!.id;

  /// Get the AvailableDevice for the active backend
  AvailableDevice get activeDevice => availableBackends[activeBackend]!;

  /// Check if a specific backend is available for this device
  bool hasBackend(DriverBackend backend) => availableBackends.containsKey(backend);

  /// Get the device ID for a specific backend (null if not available)
  String? getDeviceIdForBackend(DriverBackend backend) =>
      availableBackends[backend]?.id;

  /// List of all available backends, sorted by priority
  List<DriverBackend> get sortedBackends {
    final backends = availableBackends.keys.toList();
    backends.sort((a, b) =>
        (_backendPriority[a] ?? 99).compareTo(_backendPriority[b] ?? 99));
    return backends;
  }

  /// Create a copy with a different selected backend
  UnifiedDevice withSelectedBackend(DriverBackend? backend) {
    return UnifiedDevice(
      canonicalName: canonicalName,
      displayName: displayName,
      type: type,
      availableBackends: availableBackends,
      selectedBackend: backend,
    );
  }

  /// Add a backend to this unified device
  UnifiedDevice withBackend(DriverBackend backend, AvailableDevice device) {
    return UnifiedDevice(
      canonicalName: canonicalName,
      displayName: displayName,
      type: type,
      availableBackends: {...availableBackends, backend: device},
      selectedBackend: selectedBackend,
    );
  }

  @override
  List<Object?> get props => [
        canonicalName,
        displayName,
        type,
        availableBackends,
        selectedBackend,
      ];

  @override
  String toString() =>
      'UnifiedDevice($displayName, backends: ${availableBackends.keys.map((b) => b.displayName).join(", ")})';
}

/// Extension to get human-readable backend descriptions
extension DriverBackendDescription on DriverBackend {
  /// Get a description of this backend for tooltips
  String get description {
    switch (this) {
      case DriverBackend.native:
        return 'Direct SDK connection - best performance and lowest latency';
      case DriverBackend.ascom:
        return 'Windows ASCOM driver - industry standard, well-tested';
      case DriverBackend.alpaca:
        return 'ASCOM Alpaca over network - enables remote operation';
      case DriverBackend.indi:
        return 'INDI protocol - cross-platform, works on Linux/macOS';
      case DriverBackend.simulator:
        return 'Simulated device for testing';
    }
  }

  /// Get a short label for chips
  String get shortLabel {
    switch (this) {
      case DriverBackend.native:
        return 'Native';
      case DriverBackend.ascom:
        return 'ASCOM';
      case DriverBackend.alpaca:
        return 'Alpaca';
      case DriverBackend.indi:
        return 'INDI';
      case DriverBackend.simulator:
        return 'Sim';
    }
  }
}
