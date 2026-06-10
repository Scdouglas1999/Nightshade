import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_provider.dart';
import '../services/push_notification_service.dart';

/// Notifier that manages push notification configuration, persisted to database
class PushNotificationConfigNotifier
    extends AsyncNotifier<PushNotificationConfig> {
  @override
  Future<PushNotificationConfig> build() async {
    final dao = ref.read(settingsDaoProvider);
    final json = await dao.getSetting('push_notification_config');
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        return PushNotificationConfig(
          enabled: map['enabled'] as bool? ?? true,
          notifySequenceCompleted:
              map['notifySequenceCompleted'] as bool? ?? true,
          notifySequenceFailed: map['notifySequenceFailed'] as bool? ?? true,
          notifyMeridianFlip: map['notifyMeridianFlip'] as bool? ?? true,
          notifyWeatherUnsafe: map['notifyWeatherUnsafe'] as bool? ?? true,
          notifyGuidingLost: map['notifyGuidingLost'] as bool? ?? true,
          notifyExposureFailed: map['notifyExposureFailed'] as bool? ?? true,
          notifyAutofocusFailed: map['notifyAutofocusFailed'] as bool? ?? true,
          notifyEquipmentDisconnected:
              map['notifyEquipmentDisconnected'] as bool? ?? false,
        );
      } catch (e) {
        developer.log(
          '[PushNotificationConfig] Failed to parse config: $e',
          name: 'PushNotificationConfig',
          level: 1000,
          error: e,
        );
        return const PushNotificationConfig();
      }
    }
    return const PushNotificationConfig();
  }

  Future<void> _persist(PushNotificationConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    final json = jsonEncode({
      'enabled': config.enabled,
      'notifySequenceCompleted': config.notifySequenceCompleted,
      'notifySequenceFailed': config.notifySequenceFailed,
      'notifyMeridianFlip': config.notifyMeridianFlip,
      'notifyWeatherUnsafe': config.notifyWeatherUnsafe,
      'notifyGuidingLost': config.notifyGuidingLost,
      'notifyExposureFailed': config.notifyExposureFailed,
      'notifyAutofocusFailed': config.notifyAutofocusFailed,
      'notifyEquipmentDisconnected': config.notifyEquipmentDisconnected,
    });
    await dao.setSetting('push_notification_config', json);
  }

  Future<void> setEnabled(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(enabled: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifySequenceCompleted(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifySequenceCompleted: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifySequenceFailed(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifySequenceFailed: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifyMeridianFlip(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifyMeridianFlip: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifyWeatherUnsafe(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifyWeatherUnsafe: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifyGuidingLost(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifyGuidingLost: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifyExposureFailed(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifyExposureFailed: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifyAutofocusFailed(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifyAutofocusFailed: value);
    state = AsyncData(updated);
    await _persist(updated);
  }

  Future<void> setNotifyEquipmentDisconnected(bool value) async {
    final current = state.valueOrNull ?? const PushNotificationConfig();
    final updated = current.copyWith(notifyEquipmentDisconnected: value);
    state = AsyncData(updated);
    await _persist(updated);
  }
}

/// Provider for push notification config (persisted)
final pushNotificationConfigProvider =
    AsyncNotifierProvider<
      PushNotificationConfigNotifier,
      PushNotificationConfig
    >(PushNotificationConfigNotifier.new);

/// Provider for the PushNotificationService instance.
///
/// Architecture-unification, Subsystem 3 (collapsed): this service is now a
/// pure mobile-push *broadcaster*. It no longer subscribes to the backend
/// event stream or classifies events — the [NotificationRouter]'s
/// [SystemPushTransport] is the single producer of mobile pushes and calls
/// `enqueue` on this service. The service's stream is consumed by the
/// embedded web server to broadcast to connected mobile WebSocket clients.
///
/// The [PushNotificationConfig] remains the one config store for the
/// systemPush feed (its per-event toggles + master `enabled` gate are read by
/// [SystemPushTransport] / enforced in `enqueue`); config changes are applied
/// in-place via [PushNotificationService.updateConfig].
final pushNotificationServiceProvider = Provider<PushNotificationService>((
  ref,
) {
  // Read (don't watch) config for initial value -- changes are handled via
  // ref.listen below so the broadcaster instance (and the web server's
  // subscription to its stream) survives a config toggle.
  final configAsync = ref.read(pushNotificationConfigProvider);
  final config = configAsync.valueOrNull ?? const PushNotificationConfig();

  final service = PushNotificationService(config: config);

  ref.listen<AsyncValue<PushNotificationConfig>>(
    pushNotificationConfigProvider,
    (previous, next) {
      final newConfig = next.valueOrNull;
      if (newConfig != null) {
        service.updateConfig(newConfig);
      }
    },
  );

  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Stream provider that exposes push notifications for consumption by the web server.
///
/// The web server should listen to this stream and broadcast each notification
/// to all connected WebSocket clients.
final pushNotificationStreamProvider = StreamProvider<PushNotification>((ref) {
  final service = ref.watch(pushNotificationServiceProvider);
  return service.notifications;
});
