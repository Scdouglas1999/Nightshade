import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/backend/device_capabilities.dart';
import 'backend_provider.dart';

/// Provider to fetch camera capabilities for a device
/// Returns null if the device is not connected or doesn't support capabilities
final cameraCapabilitiesProvider = FutureProvider.family<CameraCapabilities?, String>((ref, deviceId) async {
  if (deviceId.isEmpty) return null;
  final backend = ref.watch(backendProvider);
  return backend.getCameraCapabilities(deviceId);
});

/// Provider to fetch mount capabilities for a device
/// Returns null if the device is not connected or doesn't support capabilities
final mountCapabilitiesProvider = FutureProvider.family<MountCapabilities?, String>((ref, deviceId) async {
  if (deviceId.isEmpty) return null;
  final backend = ref.watch(backendProvider);
  return backend.getMountCapabilities(deviceId);
});

/// Provider to fetch focuser capabilities for a device
/// Returns null if the device is not connected or doesn't support capabilities
final focuserCapabilitiesProvider = FutureProvider.family<FocuserCapabilities?, String>((ref, deviceId) async {
  if (deviceId.isEmpty) return null;
  final backend = ref.watch(backendProvider);
  return backend.getFocuserCapabilities(deviceId);
});

/// Provider to fetch filter wheel capabilities for a device
/// Returns null if the device is not connected or doesn't support capabilities
final filterWheelCapabilitiesProvider = FutureProvider.family<FilterWheelCapabilities?, String>((ref, deviceId) async {
  if (deviceId.isEmpty) return null;
  final backend = ref.watch(backendProvider);
  return backend.getFilterWheelCapabilities(deviceId);
});

/// Provider to fetch rotator capabilities for a device
/// Returns null if the device is not connected or doesn't support capabilities
final rotatorCapabilitiesProvider = FutureProvider.family<RotatorCapabilities?, String>((ref, deviceId) async {
  if (deviceId.isEmpty) return null;
  final backend = ref.watch(backendProvider);
  return backend.getRotatorCapabilities(deviceId);
});

/// Default binning options when no capabilities are available
const List<String> defaultBinningOptions = ['1x1', '2x2', '3x3', '4x4'];

/// Generate binning options based on camera capabilities
///
/// If capabilities are null or canBin is false, returns default options.
/// Otherwise, generates options up to maxBinX/maxBinY.
/// If canAsymmetricBin is true, includes asymmetric options (e.g., 1x2, 2x1).
List<String> getBinningOptionsFromCapabilities(CameraCapabilities? capabilities) {
  // If no capabilities or binning not supported, return defaults
  if (capabilities == null || !capabilities.canBin) {
    return defaultBinningOptions;
  }

  final maxBinX = capabilities.maxBinX;
  final maxBinY = capabilities.maxBinY;

  // If max values are unreasonable, return defaults
  if (maxBinX < 1 || maxBinY < 1 || maxBinX > 8 || maxBinY > 8) {
    return defaultBinningOptions;
  }

  final options = <String>[];

  if (capabilities.canAsymmetricBin) {
    // Generate all valid combinations
    for (var x = 1; x <= maxBinX; x++) {
      for (var y = 1; y <= maxBinY; y++) {
        options.add('${x}x$y');
      }
    }
  } else {
    // Only symmetric binning (NxN)
    final maxBin = maxBinX < maxBinY ? maxBinX : maxBinY;
    for (var n = 1; n <= maxBin; n++) {
      options.add('${n}x$n');
    }
  }

  // Ensure at least 1x1 is present
  if (options.isEmpty) {
    options.add('1x1');
  }

  return options;
}

/// Provider to get available binning options for a camera
/// Watches camera capabilities and returns appropriate binning options
final cameraBinningOptionsProvider = Provider.family<List<String>, String>((ref, deviceId) {
  if (deviceId.isEmpty) return defaultBinningOptions;

  final capabilitiesAsync = ref.watch(cameraCapabilitiesProvider(deviceId));
  return capabilitiesAsync.when(
    data: (capabilities) => getBinningOptionsFromCapabilities(capabilities),
    loading: () => defaultBinningOptions,
    error: (_, __) => defaultBinningOptions,
  );
});
