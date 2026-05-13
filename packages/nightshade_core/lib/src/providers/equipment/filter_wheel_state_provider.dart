import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/src/api.dart' as bridge_api;
import '../../models/equipment/equipment_models.dart';
import '../../services/device_service.dart';
import '../profiles_provider.dart';
import 'equipment_retry_defaults.dart';

// Note: All async callbacks and stream listeners check `mounted`
// before updating state to prevent updates after disposal.

/// Filter wheel state provider
final filterWheelStateProvider =
    StateNotifierProvider<FilterWheelStateNotifier, FilterWheelState>((ref) {
  return FilterWheelStateNotifier(ref);
});

class FilterWheelStateNotifier extends StateNotifier<FilterWheelState> {
  final Ref _ref;
  int _retryAttempts = 0;

  FilterWheelStateNotifier(this._ref) : super(const FilterWheelState()) {
    // Watch for profile changes and re-sync filter names when the active
    // profile's filter names are updated (e.g. user edits profile and saves).
    _ref.listen<EquipmentProfileModel?>(activeEquipmentProfileProvider,
        (previous, next) {
      if (!mounted) return;
      if (state.connectionState != DeviceConnectionState.connected) return;
      if (state.deviceId == null) return;

      // Only re-sync if filter names actually changed
      final previousNames = previous?.filterNames ?? [];
      final nextNames = next?.filterNames ?? [];
      if (_filterNamesEqual(previousNames, nextNames)) return;

      debugPrint(
          'FilterWheelStateNotifier: Active profile filter names changed, re-syncing');
      _syncProfileFilterNamesToDriver(state.deviceId!);
    });
  }

  /// Compare two filter name lists for equality
  static bool _filterNamesEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> connect(String deviceId,
      {int maxRetries = kDefaultMaxRetries}) async {
    _retryAttempts = 0;
    await _connectWithRetry(deviceId, maxRetries);
  }

  Future<void> _connectWithRetry(String deviceId, int maxRetries) async {
    try {
      setConnecting(deviceId);
      final deviceService = _ref.read(deviceServiceProvider);
      // DeviceService.connectFilterWheel handles:
      // 1. Connecting to the hardware
      // 2. Populating filter names from the driver
      // 3. Syncing profile/session filter names to the driver
      await deviceService.connectFilterWheel(deviceId);
      if (!mounted) return;
      _retryAttempts = 0;
    } catch (e) {
      if (!mounted) return;
      _retryAttempts++;
      final error = DeviceError.fromException(
        e,
        deviceId: deviceId,
        retryAttempts: _retryAttempts,
      );

      if (error.recoverable && _retryAttempts < maxRetries) {
        state = state.copyWith(lastError: error);
        await Future.delayed(kDefaultRetryDelay * _retryAttempts);
        if (!mounted) return;
        await _connectWithRetry(deviceId, maxRetries);
      } else {
        state = state.copyWith(
          connectionState: DeviceConnectionState.error,
          lastError: error,
        );
      }
    }
  }

  /// Re-sync filter names to the native driver when the active profile changes
  /// while the filter wheel is already connected.
  ///
  /// Called by the _ref.listen callback in the constructor when profile filter
  /// names are updated (e.g., user edits profile and saves).
  ///
  /// Initial sync on connection is handled by DeviceService.connectFilterWheel.
  Future<void> _syncProfileFilterNamesToDriver(String deviceId) async {
    try {
      // Priority 1: Check active profile filter names
      final activeProfile = _ref.read(activeEquipmentProfileProvider);
      if (activeProfile != null && activeProfile.filterNames.isNotEmpty) {
        final profileFilterNames = activeProfile.filterNames;
        final driverNames = state.filterNames;
        debugPrint(
            'FilterWheelStateNotifier: Profile has ${profileFilterNames.length} names, driver has ${driverNames.length} slots');

        // Pad profile names to match the wheel's actual slot count so no slots are lost
        final List<String> syncedNames;
        if (profileFilterNames.length < driverNames.length) {
          syncedNames = [
            ...profileFilterNames,
            ...driverNames.sublist(profileFilterNames.length),
          ];
          debugPrint(
              'FilterWheelStateNotifier: Padded profile names to ${syncedNames.length}: $syncedNames');
        } else {
          syncedNames = profileFilterNames.length > driverNames.length
              ? profileFilterNames.sublist(0, driverNames.length)
              : profileFilterNames;
        }

        await bridge_api.apiFilterwheelSetFilterNames(
          deviceId: deviceId,
          names: syncedNames,
        );

        state = state.copyWith(filterNames: syncedNames);
        debugPrint(
            'FilterWheelStateNotifier: Profile filter names synced successfully');
        return;
      }

      // Priority 2: Check session filter names
      final sessionFilterNames = _ref.read(sessionFilterNamesProvider);
      if (sessionFilterNames != null && sessionFilterNames.isNotEmpty) {
        final driverNames = state.filterNames;
        debugPrint(
            'FilterWheelStateNotifier: Session has ${sessionFilterNames.length} names, driver has ${driverNames.length} slots');

        // Pad session names to match the wheel's actual slot count
        final List<String> syncedNames;
        if (sessionFilterNames.length < driverNames.length) {
          syncedNames = [
            ...sessionFilterNames,
            ...driverNames.sublist(sessionFilterNames.length),
          ];
        } else {
          syncedNames = sessionFilterNames.length > driverNames.length
              ? sessionFilterNames.sublist(0, driverNames.length)
              : sessionFilterNames;
        }

        await bridge_api.apiFilterwheelSetFilterNames(
          deviceId: deviceId,
          names: syncedNames,
        );

        state = state.copyWith(filterNames: syncedNames);
        debugPrint(
            'FilterWheelStateNotifier: Session filter names synced successfully');
        return;
      }

      // Priority 3: Use driver-reported names (no sync needed, they're already there)
      debugPrint(
          'FilterWheelStateNotifier: No profile or session filter names - using driver-reported names');
    } catch (e) {
      // Don't fail connection if filter name sync fails - log and continue
      debugPrint('FilterWheelStateNotifier: Failed to sync filter names: $e');
    }
  }

  Future<void> retryConnection() async {
    if (state.deviceId != null) {
      await connect(state.deviceId!);
    }
  }

  void clearError() {
    state = state.clearError();
  }

  Future<void> disconnect() async {
    if (state.deviceId == null) return;
    try {
      final deviceService = _ref.read(deviceServiceProvider);
      await deviceService.disconnectFilterWheel();
      setDisconnected();
    } catch (e) {
      state = state.copyWith(
        lastError: DeviceError.fromException(e, deviceId: state.deviceId),
      );
    }
  }

  void setConnecting(String deviceId, [String? deviceName]) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connecting,
      deviceId: deviceId,
      deviceName: deviceName ?? state.deviceName ?? deviceId,
      clearError: true,
    );
  }

  void setConnected({List<String>? filterNames}) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      filterNames: filterNames,
      clearError: true,
    );
  }

  void setDeviceName(String deviceName) {
    state = state.copyWith(deviceName: deviceName);
  }

  void setDisconnected() {
    state = const FilterWheelState();
  }

  void updatePosition(int position) {
    state = state.copyWith(currentPosition: position);
  }

  void setMoving(bool moving) {
    state = state.copyWith(isMoving: moving);
  }

  void setError(Object error) {
    state = state.copyWith(
      connectionState: DeviceConnectionState.error,
      lastError: DeviceError.fromException(error, deviceId: state.deviceId),
    );
  }

  /// Set session-level filter names (without requiring an equipment profile).
  ///
  /// This allows users to name their filters for the current session without
  /// creating or modifying an equipment profile. The names are stored in
  /// [sessionFilterNamesProvider] and will be used when:
  /// - No equipment profile is active, OR
  /// - The active equipment profile has no filter names configured
  ///
  /// If [syncToDriver] is true and a filter wheel is connected, the names
  /// will be immediately synced to the native driver.
  Future<void> setSessionFilterNames(
    List<String> names, {
    bool syncToDriver = true,
  }) async {
    // Store in the session provider
    _ref.read(sessionFilterNamesProvider.notifier).state = names;

    // Update local state
    state = state.copyWith(filterNames: names);

    // Optionally sync to driver if connected
    if (syncToDriver &&
        state.connectionState == DeviceConnectionState.connected &&
        state.deviceId != null) {
      try {
        debugPrint(
            'FilterWheelStateNotifier: Syncing session filter names to driver: $names');
        await bridge_api.apiFilterwheelSetFilterNames(
          deviceId: state.deviceId!,
          names: names,
        );
        debugPrint(
            'FilterWheelStateNotifier: Session filter names synced to driver');
      } catch (e) {
        debugPrint(
            'FilterWheelStateNotifier: Failed to sync session filter names to driver: $e');
        // Don't throw - the names are still stored locally
      }
    }
  }

  /// Clear session-level filter names.
  ///
  /// This will cause the filter wheel to fall back to profile names (if available)
  /// or driver-reported names on the next connection.
  void clearSessionFilterNames() {
    _ref.read(sessionFilterNamesProvider.notifier).state = null;
  }
}

// =============================================================================
// Session Filter Names Provider
// =============================================================================

/// Session-only filter names (no profile required).
///
/// These are used when no equipment profile is active but user wants to name filters.
/// When a filter wheel connects, filter names are resolved in this priority order:
/// 1. Active profile filter names (if profile exists and has filter names configured)
/// 2. Session filter names (if set via this provider)
/// 3. Driver-reported names (from the backend/hardware)
///
/// This allows users to set filter names without creating an equipment profile,
/// which is useful for quick sessions or testing.
final sessionFilterNamesProvider = StateProvider<List<String>?>((ref) => null);
