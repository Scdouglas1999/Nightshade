import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/device_service.dart';

/// Provider that tracks user's backend selection per device (by canonical name)
///
/// Key: canonical device name (normalized)
/// Value: selected DriverBackend
///
/// When a user selects a specific backend for a device, it's stored here.
/// If no selection exists, the device uses its recommended backend.
final deviceBackendSelectionProvider =
    StateNotifierProvider<DeviceBackendSelectionNotifier, Map<String, DriverBackend>>((ref) {
  return DeviceBackendSelectionNotifier();
});

class DeviceBackendSelectionNotifier extends StateNotifier<Map<String, DriverBackend>> {
  DeviceBackendSelectionNotifier() : super({});

  /// Select a backend for a device
  void selectBackend(String canonicalName, DriverBackend backend) {
    state = {...state, canonicalName: backend};
  }

  /// Clear selection for a device (will use recommended backend)
  void clearSelection(String canonicalName) {
    final newState = Map<String, DriverBackend>.from(state);
    newState.remove(canonicalName);
    state = newState;
  }

  /// Get the selected backend for a device (null if not explicitly selected)
  DriverBackend? getSelection(String canonicalName) {
    return state[canonicalName];
  }

  /// Clear all selections
  void clearAll() {
    state = {};
  }

  /// Load selections from saved preferences (e.g., from profile)
  void loadSelections(Map<String, DriverBackend> selections) {
    state = Map<String, DriverBackend>.from(selections);
  }

  /// Export selections for saving
  Map<String, DriverBackend> exportSelections() {
    return Map<String, DriverBackend>.from(state);
  }
}

/// Family provider to get the selected backend for a specific device
///
/// Usage: ref.watch(selectedBackendForDeviceProvider('asi294mc pro'))
final selectedBackendForDeviceProvider =
    Provider.family<DriverBackend?, String>((ref, canonicalName) {
  final selections = ref.watch(deviceBackendSelectionProvider);
  return selections[canonicalName];
});

/// Provider to check if a device has an explicit backend selection
final hasExplicitBackendSelectionProvider =
    Provider.family<bool, String>((ref, canonicalName) {
  final selections = ref.watch(deviceBackendSelectionProvider);
  return selections.containsKey(canonicalName);
});
