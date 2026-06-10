part of '../guiding_provider.dart';

// =============================================================================
// PHD2 LOCK POSITION PROVIDER
// =============================================================================

/// Provider for current guide star lock position
final lockPositionProvider =
    StateNotifierProvider<LockPositionNotifier, ({double x, double y})?>((ref) {
      return LockPositionNotifier(ref);
    });

/// Notifier that tracks guide star lock position
class LockPositionNotifier extends StateNotifier<({double x, double y})?> {
  final Ref ref;
  StreamSubscription? _sub;

  LockPositionNotifier(this.ref) : super(null) {
    final backend = ref.read(backendProvider);
    _sub = backend.eventStream.listen((event) {
      if (!mounted) return; // Guard against updates after disposal
      if (event.category == EventCategory.guiding) {
        if (event.eventType == 'StarSelected' ||
            event.eventType == 'LockPositionSet') {
          final x = (event.data['X'] ?? event.data['x'] ?? 0).toDouble();
          final y = (event.data['Y'] ?? event.data['y'] ?? 0).toDouble();
          state = (x: x, y: y);
        } else if (event.eventType == 'StarLost') {
          // Keep the last known position but could mark as lost
        }
      }
    });
  }

  /// Set a new lock position
  Future<void> setLockPosition(double x, double y, {bool exact = false}) async {
    final backend = ref.read(backendProvider);
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    await backend.guiderSetLockPosition(
      deviceId: guiderId,
      x: x,
      y: y,
      exact: exact,
    );
    state = (x: x, y: y);
  }

  /// Find a star automatically
  Future<void> findStar() async {
    final backend = ref.read(backendProvider);
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    final pos = await backend.guiderFindStar(deviceId: guiderId);
    state = (x: pos.$1, y: pos.$2);
  }

  /// Deselect the current star
  Future<void> deselectStar() async {
    final backend = ref.read(backendProvider);
    final guiderId = ref.read(guiderStateProvider).deviceId ?? 'phd2_guider';
    await backend.guiderDeselectStar(deviceId: guiderId);
    state = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// =============================================================================
// BUILT-IN GUIDER CONFIG PROVIDER
// =============================================================================

/// The device ID used by the built-in multi-star guider.
const String builtinGuiderDeviceId = 'native:builtin_guider:multi_star';

/// Provider that exposes whether the currently connected guider is the built-in
/// guider (as opposed to PHD2 or another external guider).
final isBuiltinGuiderProvider = Provider<bool>((ref) {
  final guiderState = ref.watch(guiderStateProvider);
  return guiderState.deviceId == builtinGuiderDeviceId;
});

/// Provider for the built-in guider configuration.
/// Fetches the config from the Rust backend and allows updating it.
final builtinGuiderConfigProvider =
    StateNotifierProvider<
      BuiltinGuiderConfigNotifier,
      AsyncValue<BuiltinGuiderConfig>
    >((ref) {
      return BuiltinGuiderConfigNotifier(ref);
    });

class BuiltinGuiderConfigNotifier
    extends StateNotifier<AsyncValue<BuiltinGuiderConfig>> {
  final Ref ref;
  LoggingService get _logger => ref.read(loggingServiceProvider);

  BuiltinGuiderConfigNotifier(this.ref) : super(const AsyncValue.loading()) {
    // Auto-fetch when the built-in guider is connected
    final isBuiltin = ref.read(isBuiltinGuiderProvider);
    if (isBuiltin) {
      fetch();
    }

    // Listen for guider changes to fetch/clear config
    ref.listen<bool>(isBuiltinGuiderProvider, (previous, next) {
      if (next && previous != true) {
        fetch();
      } else if (!next) {
        state = const AsyncValue.loading();
      }
    });
  }

  /// Fetch the current config from the Rust backend.
  Future<void> fetch() async {
    if (!mounted) return;
    state = const AsyncValue.loading();

    try {
      final backend = ref.read(backendProvider);
      final config = await backend.builtinGuiderGetConfig();
      if (mounted) {
        state = AsyncValue.data(config);
      }
    } catch (e) {
      _logger.error(
        'Failed to fetch built-in guider config: $e',
        source: 'BuiltinGuiderConfig',
      );
      if (mounted) {
        // Fall back to defaults so the UI is still usable
        state = const AsyncValue.data(BuiltinGuiderConfig.defaults);
      }
    }
  }

  /// Update the full config and push to the backend.
  Future<void> updateConfig(BuiltinGuiderConfig newConfig) async {
    if (!mounted) return;

    final previousState = state;
    state = AsyncValue.data(newConfig);

    try {
      final backend = ref.read(backendProvider);
      await backend.builtinGuiderSetConfig(newConfig);
    } catch (e) {
      _logger.error(
        'Failed to set built-in guider config: $e',
        source: 'BuiltinGuiderConfig',
      );
      // Revert on failure
      if (mounted) {
        state = previousState;
      }
      rethrow;
    }
  }

  /// Reset config to defaults.
  Future<void> resetToDefaults() async {
    await updateConfig(BuiltinGuiderConfig.defaults);
  }
}
