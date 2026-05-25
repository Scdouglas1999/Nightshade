// Riverpod wiring for the Wave 5 NotificationRouter.
//
// Storage layout:
//   * Non-secret config (host, port, from-address, etc.) → key-value
//     `SettingsDao` blob per transport.
//   * Secret config (passwords, tokens, webhook URLs, user-keys) →
//     `flutter_secure_storage` via [SecretsStore].
//
// Key-value DAO entries:
//   * `notification_routing_matrix`       -> NotificationRoutingMatrix.toJson()
//   * `notification_transport_email`      -> EmailTransportConfig.toJson() (no password)
//   * `notification_transport_webhook`    -> WebhookTransportConfig.toJson()
//   * `notification_transport_pushover`   -> PushoverTransportConfig.toJson() (no tokens)
//   * `notification_transport_telegram`   -> TelegramTransportConfig.toJson() (no bot token)
//   * `notification_transport_discord`    -> DiscordTransportConfig.toJson() (no webhook URL)
//   * `notification_transport_mqtt`       -> MqttTransportConfig.toJson() (no password)
//   * `notification_secrets_migrated_v1`  -> 'true' once one-shot migration done.
//
// We deliberately keep one key per transport so a corrupt blob in one
// (say, the user pasted invalid JSON into a webhook header field) only
// disables that one transport rather than the whole routing system.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notification/notification_categories.dart';
import '../models/notification/transport_configs.dart';
import '../services/notification/notification_router.dart';
import '../services/notification/secrets_store.dart';
import '../services/notification/transports/discord_transport.dart';
import '../services/notification/transports/email_transport.dart';
import '../services/notification/transports/in_app_transport.dart';
import '../services/notification/transports/mqtt_transport.dart';
import '../services/notification/transports/notification_transport.dart';
import '../services/notification/transports/pushover_transport.dart';
import '../services/notification/transports/system_push_transport.dart';
import '../services/notification/transports/telegram_transport.dart';
import '../services/notification/transports/webhook_transport.dart';
import 'backend_provider.dart';
import 'database_provider.dart';
import 'push_notification_provider.dart';
import 'ui_notification_provider.dart';

const String _kRoutingMatrixSettingKey = 'notification_routing_matrix';

String _transportSettingKey(NotificationTransportKind kind) =>
    'notification_transport_${kind.storageKey}';

// ---------------------------------------------------------------------------
// Secrets store provider
// ---------------------------------------------------------------------------

/// Overridable provider for the platform secrets store. Production
/// (apps/desktop, apps/mobile) uses [SecretsStore.platformDefault]; tests
/// override this with a fake backing store.
final secretsStoreProvider = Provider<SecretsStore>((ref) {
  return SecretsStore.platformDefault();
});

/// One-shot migration: moves plaintext secrets out of `app_settings`
/// blobs and into the secure store. Runs on first `notificationRouter`
/// build and is idempotent. Exposed as a provider so the app shell can
/// `ref.read` it during startup if it wants to surface migration
/// progress / errors.
final notificationSecretsMigrationProvider =
    FutureProvider<bool>((ref) async {
  final dao = ref.read(settingsDaoProvider);
  final store = ref.read(secretsStoreProvider);
  return store.migrateFromPlaintext(dao);
});

// ---------------------------------------------------------------------------
// Per-transport config notifiers
// ---------------------------------------------------------------------------

class EmailConfigNotifier extends AsyncNotifier<EmailTransportConfig> {
  @override
  Future<EmailTransportConfig> build() async {
    // Trigger one-shot migration before reading any blob — if a legacy
    // plaintext blob still has the password in it, we want it moved
    // before we hand the config back to anyone.
    await ref.read(notificationSecretsMigrationProvider.future);

    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    final raw = await dao
        .getSetting(_transportSettingKey(NotificationTransportKind.email));
    EmailTransportConfig base;
    if (raw == null) {
      base = const EmailTransportConfig();
    } else {
      try {
        base = EmailTransportConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        developer.log('[NotificationProviders] Bad email config: $e',
            name: 'NotificationProviders', level: 900);
        base = const EmailTransportConfig();
      }
    }
    final password = await secrets.read(SecretField.emailPassword);
    return base.copyWith(password: password);
  }

  Future<void> save(EmailTransportConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    // Split: write the secret to the keyring, blob to the DAO without
    // the secret.
    await secrets.write(SecretField.emailPassword, config.password);
    final nonSecret = config.copyWith(password: '');
    await dao.setSetting(_transportSettingKey(NotificationTransportKind.email),
        jsonEncode(nonSecret.toJson()));
    state = AsyncData(config);
  }
}

class WebhookConfigNotifier extends AsyncNotifier<WebhookTransportConfig> {
  @override
  Future<WebhookTransportConfig> build() async {
    final dao = ref.read(settingsDaoProvider);
    final raw = await dao.getSetting(
        _transportSettingKey(NotificationTransportKind.webhookGeneric));
    if (raw == null) return const WebhookTransportConfig();
    try {
      return WebhookTransportConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      developer.log('[NotificationProviders] Bad webhook config: $e',
          name: 'NotificationProviders', level: 900);
      return const WebhookTransportConfig();
    }
  }

  Future<void> save(WebhookTransportConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(
        _transportSettingKey(NotificationTransportKind.webhookGeneric),
        jsonEncode(config.toJson()));
    state = AsyncData(config);
  }
}

class PushoverConfigNotifier extends AsyncNotifier<PushoverTransportConfig> {
  @override
  Future<PushoverTransportConfig> build() async {
    await ref.read(notificationSecretsMigrationProvider.future);
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    final raw = await dao
        .getSetting(_transportSettingKey(NotificationTransportKind.pushover));
    PushoverTransportConfig base;
    if (raw == null) {
      base = const PushoverTransportConfig();
    } else {
      try {
        base = PushoverTransportConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        developer.log('[NotificationProviders] Bad pushover config: $e',
            name: 'NotificationProviders', level: 900);
        base = const PushoverTransportConfig();
      }
    }
    final apiToken = await secrets.read(SecretField.pushoverApiToken);
    final userKey = await secrets.read(SecretField.pushoverUserKey);
    return base.copyWith(apiToken: apiToken, userKey: userKey);
  }

  Future<void> save(PushoverTransportConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    await secrets.write(SecretField.pushoverApiToken, config.apiToken);
    await secrets.write(SecretField.pushoverUserKey, config.userKey);
    final nonSecret = config.copyWith(apiToken: '', userKey: '');
    await dao.setSetting(
        _transportSettingKey(NotificationTransportKind.pushover),
        jsonEncode(nonSecret.toJson()));
    state = AsyncData(config);
  }
}

class TelegramConfigNotifier extends AsyncNotifier<TelegramTransportConfig> {
  @override
  Future<TelegramTransportConfig> build() async {
    await ref.read(notificationSecretsMigrationProvider.future);
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    final raw = await dao
        .getSetting(_transportSettingKey(NotificationTransportKind.telegram));
    TelegramTransportConfig base;
    if (raw == null) {
      base = const TelegramTransportConfig();
    } else {
      try {
        base = TelegramTransportConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        developer.log('[NotificationProviders] Bad telegram config: $e',
            name: 'NotificationProviders', level: 900);
        base = const TelegramTransportConfig();
      }
    }
    final botToken = await secrets.read(SecretField.telegramBotToken);
    return base.copyWith(botToken: botToken);
  }

  Future<void> save(TelegramTransportConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    await secrets.write(SecretField.telegramBotToken, config.botToken);
    final nonSecret = config.copyWith(botToken: '');
    await dao.setSetting(
        _transportSettingKey(NotificationTransportKind.telegram),
        jsonEncode(nonSecret.toJson()));
    state = AsyncData(config);
  }
}

class DiscordConfigNotifier extends AsyncNotifier<DiscordTransportConfig> {
  @override
  Future<DiscordTransportConfig> build() async {
    await ref.read(notificationSecretsMigrationProvider.future);
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    final raw = await dao
        .getSetting(_transportSettingKey(NotificationTransportKind.discord));
    DiscordTransportConfig base;
    if (raw == null) {
      base = const DiscordTransportConfig();
    } else {
      try {
        base = DiscordTransportConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        developer.log('[NotificationProviders] Bad discord config: $e',
            name: 'NotificationProviders', level: 900);
        base = const DiscordTransportConfig();
      }
    }
    final webhookUrl = await secrets.read(SecretField.discordWebhookUrl);
    return base.copyWith(webhookUrl: webhookUrl);
  }

  Future<void> save(DiscordTransportConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    await secrets.write(SecretField.discordWebhookUrl, config.webhookUrl);
    final nonSecret = config.copyWith(webhookUrl: '');
    await dao.setSetting(
        _transportSettingKey(NotificationTransportKind.discord),
        jsonEncode(nonSecret.toJson()));
    state = AsyncData(config);
  }
}

class MqttConfigNotifier extends AsyncNotifier<MqttTransportConfig> {
  @override
  Future<MqttTransportConfig> build() async {
    await ref.read(notificationSecretsMigrationProvider.future);
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    final raw = await dao
        .getSetting(_transportSettingKey(NotificationTransportKind.mqtt));
    MqttTransportConfig base;
    if (raw == null) {
      base = const MqttTransportConfig();
    } else {
      try {
        base = MqttTransportConfig.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      } catch (e) {
        developer.log('[NotificationProviders] Bad mqtt config: $e',
            name: 'NotificationProviders', level: 900);
        base = const MqttTransportConfig();
      }
    }
    final password = await secrets.read(SecretField.mqttPassword);
    return base.copyWith(password: password.isEmpty ? null : password);
  }

  Future<void> save(MqttTransportConfig config) async {
    final dao = ref.read(settingsDaoProvider);
    final secrets = ref.read(secretsStoreProvider);
    await secrets.write(SecretField.mqttPassword, config.password ?? '');
    final nonSecret = config.copyWith(clearPassword: true);
    await dao.setSetting(_transportSettingKey(NotificationTransportKind.mqtt),
        jsonEncode(nonSecret.toJson()));
    state = AsyncData(config);
  }
}

class RoutingMatrixNotifier extends AsyncNotifier<NotificationRoutingMatrix> {
  @override
  Future<NotificationRoutingMatrix> build() async {
    final dao = ref.read(settingsDaoProvider);
    final raw = await dao.getSetting(_kRoutingMatrixSettingKey);
    if (raw == null) return NotificationRoutingMatrix.defaults();
    try {
      return NotificationRoutingMatrix.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      developer.log('[NotificationProviders] Bad routing matrix: $e',
          name: 'NotificationProviders', level: 900);
      return NotificationRoutingMatrix.defaults();
    }
  }

  Future<void> save(NotificationRoutingMatrix matrix) async {
    final dao = ref.read(settingsDaoProvider);
    await dao.setSetting(
        _kRoutingMatrixSettingKey, jsonEncode(matrix.toJson()));
    state = AsyncData(matrix);
  }

  Future<void> setEnabled(bool enabled) async {
    final current =
        state.valueOrNull ?? NotificationRoutingMatrix.defaults();
    await save(current.copyWith(enabled: enabled));
  }

  Future<void> setRule(
    NotificationCategory category,
    NotificationRoutingRule rule,
  ) async {
    final current =
        state.valueOrNull ?? NotificationRoutingMatrix.defaults();
    await save(current.withRule(category, rule));
  }
}

// ---------------------------------------------------------------------------
// Public providers
// ---------------------------------------------------------------------------

final emailTransportConfigProvider =
    AsyncNotifierProvider<EmailConfigNotifier, EmailTransportConfig>(
        EmailConfigNotifier.new);

final webhookTransportConfigProvider =
    AsyncNotifierProvider<WebhookConfigNotifier, WebhookTransportConfig>(
        WebhookConfigNotifier.new);

final pushoverTransportConfigProvider =
    AsyncNotifierProvider<PushoverConfigNotifier, PushoverTransportConfig>(
        PushoverConfigNotifier.new);

final telegramTransportConfigProvider =
    AsyncNotifierProvider<TelegramConfigNotifier, TelegramTransportConfig>(
        TelegramConfigNotifier.new);

final discordTransportConfigProvider =
    AsyncNotifierProvider<DiscordConfigNotifier, DiscordTransportConfig>(
        DiscordConfigNotifier.new);

final mqttTransportConfigProvider =
    AsyncNotifierProvider<MqttConfigNotifier, MqttTransportConfig>(
        MqttConfigNotifier.new);

final notificationRoutingMatrixProvider = AsyncNotifierProvider<
    RoutingMatrixNotifier, NotificationRoutingMatrix>(
  RoutingMatrixNotifier.new,
);

/// The NotificationRouter singleton.
///
/// Rebuilds when the backend changes (so it re-attaches to the new
/// event stream). Config changes from individual transport providers
/// are forwarded in-place via `updateConfig` to avoid tearing the
/// router down for every setting toggle.
final notificationRouterProvider = Provider<NotificationRouter>((ref) {
  final backend = ref.watch(backendProvider);
  final uiNotifier = ref.read(uiNotificationProvider.notifier);
  final pushService = ref.read(pushNotificationServiceProvider);

  // Resolve initial configs synchronously (each provider returns its
  // default value before the DB read completes). The router applies the
  // real persisted values via the listeners registered below as soon as
  // they arrive.
  final emailCfg = ref.read(emailTransportConfigProvider).valueOrNull ??
      const EmailTransportConfig();
  final webhookCfg = ref.read(webhookTransportConfigProvider).valueOrNull ??
      const WebhookTransportConfig();
  final pushoverCfg = ref.read(pushoverTransportConfigProvider).valueOrNull ??
      const PushoverTransportConfig();
  final telegramCfg = ref.read(telegramTransportConfigProvider).valueOrNull ??
      const TelegramTransportConfig();
  final discordCfg = ref.read(discordTransportConfigProvider).valueOrNull ??
      const DiscordTransportConfig();
  final mqttCfg = ref.read(mqttTransportConfigProvider).valueOrNull ??
      const MqttTransportConfig();

  final inApp = InAppTransport(uiNotifier);
  final systemPush = SystemPushTransport(pushService);
  final email = EmailTransport(config: emailCfg);
  final webhook = WebhookTransport(config: webhookCfg);
  final pushover = PushoverTransport(config: pushoverCfg);
  final telegram = TelegramTransport(config: telegramCfg);
  final discord = DiscordTransport(config: discordCfg);
  final mqtt = MqttTransport(config: mqttCfg);

  final transports = <NotificationTransport>[
    inApp,
    systemPush,
    email,
    webhook,
    pushover,
    telegram,
    discord,
    mqtt,
  ];

  final matrix = ref.read(notificationRoutingMatrixProvider).valueOrNull ??
      NotificationRoutingMatrix.defaults();
  final router = NotificationRouter(transports: transports, matrix: matrix);
  router.attachEventStream(backend.eventStream);

  // Listen for transport-config changes and forward in-place.
  ref.listen(emailTransportConfigProvider, (prev, next) {
    next.whenData(email.updateConfig);
  });
  ref.listen(webhookTransportConfigProvider, (prev, next) {
    next.whenData(webhook.updateConfig);
  });
  ref.listen(pushoverTransportConfigProvider, (prev, next) {
    next.whenData(pushover.updateConfig);
  });
  ref.listen(telegramTransportConfigProvider, (prev, next) {
    next.whenData(telegram.updateConfig);
  });
  ref.listen(discordTransportConfigProvider, (prev, next) {
    next.whenData(discord.updateConfig);
  });
  ref.listen(mqttTransportConfigProvider, (prev, next) {
    next.whenData(mqtt.updateConfig);
  });
  ref.listen(notificationRoutingMatrixProvider, (prev, next) {
    next.whenData(router.updateMatrix);
  });

  ref.onDispose(() {
    // Don't await — provider disposal is synchronous.
    unawaited(router.dispose());
  });

  return router;
});
