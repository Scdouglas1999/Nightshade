// Per-transport configuration models.
//
// Each transport has its own settings (Pushover needs user+token,
// Telegram needs bot+chat, etc.). These types serialise to JSON.
//
// Storage split:
//   * Non-secret fields (SMTP host/port, MQTT topic, From-address, etc.)
//     → key-value SettingsDao under `notification_transport_<kind>`.
//   * Secret fields (passwords, tokens, webhook URLs) → flutter_secure_storage
//     via [SecretsStore] (one entry per logical secret).
//
// These config classes still carry the secret as a String field so the
// in-memory shape stays simple; the per-transport Riverpod notifier
// rebuilds the live config by reading the non-secret blob from the DAO,
// reading the secret from the keyring, and stitching them back together.
// On save the inverse split happens.
//
// Plaintext-secret blobs from before that migration are migrated on first run
// via [SecretsStore.migrateFromPlaintext] — one-shot, idempotent.

import 'package:equatable/equatable.dart';

/// Common shape for every transport config.
abstract class NotificationTransportConfig {
  bool get isConfigured;
  Map<String, dynamic> toJson();
}

// ---------------------------------------------------------------------------
// Email (SMTP)
// ---------------------------------------------------------------------------

class EmailTransportConfig extends Equatable
    implements NotificationTransportConfig {
  final String smtpHost;
  final int smtpPort;
  final String username;
  final String password; // secret
  final bool useTls;
  final String fromAddress;
  final String toAddress;

  const EmailTransportConfig({
    this.smtpHost = '',
    this.smtpPort = 587,
    this.username = '',
    this.password = '',
    this.useTls = true,
    this.fromAddress = '',
    this.toAddress = '',
  });

  @override
  bool get isConfigured =>
      smtpHost.isNotEmpty && fromAddress.isNotEmpty && toAddress.isNotEmpty;

  EmailTransportConfig copyWith({
    String? smtpHost,
    int? smtpPort,
    String? username,
    String? password,
    bool? useTls,
    String? fromAddress,
    String? toAddress,
  }) => EmailTransportConfig(
    smtpHost: smtpHost ?? this.smtpHost,
    smtpPort: smtpPort ?? this.smtpPort,
    username: username ?? this.username,
    password: password ?? this.password,
    useTls: useTls ?? this.useTls,
    fromAddress: fromAddress ?? this.fromAddress,
    toAddress: toAddress ?? this.toAddress,
  );

  @override
  Map<String, dynamic> toJson() => {
    'smtpHost': smtpHost,
    'smtpPort': smtpPort,
    'username': username,
    'password': password,
    'useTls': useTls,
    'fromAddress': fromAddress,
    'toAddress': toAddress,
  };

  factory EmailTransportConfig.fromJson(Map<String, dynamic> json) =>
      EmailTransportConfig(
        smtpHost: json['smtpHost'] as String? ?? '',
        smtpPort: (json['smtpPort'] as num?)?.toInt() ?? 587,
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        useTls: json['useTls'] as bool? ?? true,
        fromAddress: json['fromAddress'] as String? ?? '',
        toAddress: json['toAddress'] as String? ?? '',
      );

  @override
  List<Object?> get props => [
    smtpHost,
    smtpPort,
    username,
    password,
    useTls,
    fromAddress,
    toAddress,
  ];
}

// ---------------------------------------------------------------------------
// Generic webhook
// ---------------------------------------------------------------------------

class WebhookTransportConfig extends Equatable
    implements NotificationTransportConfig {
  final String url;
  final Map<String, String> headers;
  final String? bodyTemplate;

  const WebhookTransportConfig({
    this.url = '',
    this.headers = const {},
    this.bodyTemplate,
  });

  @override
  bool get isConfigured => url.isNotEmpty;

  WebhookTransportConfig copyWith({
    String? url,
    Map<String, String>? headers,
    String? bodyTemplate,
    bool clearBodyTemplate = false,
  }) => WebhookTransportConfig(
    url: url ?? this.url,
    headers: headers ?? this.headers,
    bodyTemplate: clearBodyTemplate
        ? null
        : (bodyTemplate ?? this.bodyTemplate),
  );

  @override
  Map<String, dynamic> toJson() => {
    'url': url,
    'headers': headers,
    'bodyTemplate': bodyTemplate,
  };

  factory WebhookTransportConfig.fromJson(Map<String, dynamic> json) {
    final headersRaw = json['headers'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      headersRaw.forEach((k, v) {
        if (k is String && v != null) headers[k] = v.toString();
      });
    }
    return WebhookTransportConfig(
      url: json['url'] as String? ?? '',
      headers: headers,
      bodyTemplate: json['bodyTemplate'] as String?,
    );
  }

  @override
  List<Object?> get props => [url, headers, bodyTemplate];
}

// ---------------------------------------------------------------------------
// Pushover
// ---------------------------------------------------------------------------

class PushoverTransportConfig extends Equatable
    implements NotificationTransportConfig {
  final String apiToken; // secret
  final String userKey; // secret
  final String? device;
  final int priority; // -2..2

  const PushoverTransportConfig({
    this.apiToken = '',
    this.userKey = '',
    this.device,
    this.priority = 0,
  });

  @override
  bool get isConfigured => apiToken.isNotEmpty && userKey.isNotEmpty;

  PushoverTransportConfig copyWith({
    String? apiToken,
    String? userKey,
    String? device,
    int? priority,
    bool clearDevice = false,
  }) => PushoverTransportConfig(
    apiToken: apiToken ?? this.apiToken,
    userKey: userKey ?? this.userKey,
    device: clearDevice ? null : (device ?? this.device),
    priority: priority ?? this.priority,
  );

  @override
  Map<String, dynamic> toJson() => {
    'apiToken': apiToken,
    'userKey': userKey,
    'device': device,
    'priority': priority,
  };

  factory PushoverTransportConfig.fromJson(Map<String, dynamic> json) =>
      PushoverTransportConfig(
        apiToken: json['apiToken'] as String? ?? '',
        userKey: json['userKey'] as String? ?? '',
        device: json['device'] as String?,
        priority: (json['priority'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [apiToken, userKey, device, priority];
}

// ---------------------------------------------------------------------------
// Telegram
// ---------------------------------------------------------------------------

class TelegramTransportConfig extends Equatable
    implements NotificationTransportConfig {
  final String botToken; // secret
  final String chatId;
  final bool disableNotification;

  const TelegramTransportConfig({
    this.botToken = '',
    this.chatId = '',
    this.disableNotification = false,
  });

  @override
  bool get isConfigured => botToken.isNotEmpty && chatId.isNotEmpty;

  TelegramTransportConfig copyWith({
    String? botToken,
    String? chatId,
    bool? disableNotification,
  }) => TelegramTransportConfig(
    botToken: botToken ?? this.botToken,
    chatId: chatId ?? this.chatId,
    disableNotification: disableNotification ?? this.disableNotification,
  );

  @override
  Map<String, dynamic> toJson() => {
    'botToken': botToken,
    'chatId': chatId,
    'disableNotification': disableNotification,
  };

  factory TelegramTransportConfig.fromJson(Map<String, dynamic> json) =>
      TelegramTransportConfig(
        botToken: json['botToken'] as String? ?? '',
        chatId: json['chatId'] as String? ?? '',
        disableNotification: json['disableNotification'] as bool? ?? false,
      );

  @override
  List<Object?> get props => [botToken, chatId, disableNotification];
}

// ---------------------------------------------------------------------------
// Discord
// ---------------------------------------------------------------------------

class DiscordTransportConfig extends Equatable
    implements NotificationTransportConfig {
  final String webhookUrl; // secret
  final String? username;
  final String? avatarUrl;

  const DiscordTransportConfig({
    this.webhookUrl = '',
    this.username,
    this.avatarUrl,
  });

  @override
  bool get isConfigured => webhookUrl.isNotEmpty;

  DiscordTransportConfig copyWith({
    String? webhookUrl,
    String? username,
    String? avatarUrl,
    bool clearUsername = false,
    bool clearAvatarUrl = false,
  }) => DiscordTransportConfig(
    webhookUrl: webhookUrl ?? this.webhookUrl,
    username: clearUsername ? null : (username ?? this.username),
    avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
  );

  @override
  Map<String, dynamic> toJson() => {
    'webhookUrl': webhookUrl,
    'username': username,
    'avatarUrl': avatarUrl,
  };

  factory DiscordTransportConfig.fromJson(Map<String, dynamic> json) =>
      DiscordTransportConfig(
        webhookUrl: json['webhookUrl'] as String? ?? '',
        username: json['username'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
      );

  @override
  List<Object?> get props => [webhookUrl, username, avatarUrl];
}

// ---------------------------------------------------------------------------
// MQTT
// ---------------------------------------------------------------------------

class MqttTransportConfig extends Equatable
    implements NotificationTransportConfig {
  final String host;
  final int port;
  final String? username;
  final String? password; // secret
  final String topic;
  final int qos; // 0/1/2
  final bool retain;
  final bool useTls;
  final String clientId;

  const MqttTransportConfig({
    this.host = '',
    this.port = 1883,
    this.username,
    this.password,
    this.topic = 'nightshade/notifications',
    this.qos = 0,
    this.retain = false,
    this.useTls = false,
    this.clientId = 'nightshade',
  });

  @override
  bool get isConfigured => host.isNotEmpty && topic.isNotEmpty;

  MqttTransportConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? topic,
    int? qos,
    bool? retain,
    bool? useTls,
    String? clientId,
    bool clearUsername = false,
    bool clearPassword = false,
  }) => MqttTransportConfig(
    host: host ?? this.host,
    port: port ?? this.port,
    username: clearUsername ? null : (username ?? this.username),
    password: clearPassword ? null : (password ?? this.password),
    topic: topic ?? this.topic,
    qos: qos ?? this.qos,
    retain: retain ?? this.retain,
    useTls: useTls ?? this.useTls,
    clientId: clientId ?? this.clientId,
  );

  @override
  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'username': username,
    'password': password,
    'topic': topic,
    'qos': qos,
    'retain': retain,
    'useTls': useTls,
    'clientId': clientId,
  };

  factory MqttTransportConfig.fromJson(Map<String, dynamic> json) =>
      MqttTransportConfig(
        host: json['host'] as String? ?? '',
        port: (json['port'] as num?)?.toInt() ?? 1883,
        username: json['username'] as String?,
        password: json['password'] as String?,
        topic: json['topic'] as String? ?? 'nightshade/notifications',
        qos: (json['qos'] as num?)?.toInt() ?? 0,
        retain: json['retain'] as bool? ?? false,
        useTls: json['useTls'] as bool? ?? false,
        clientId: json['clientId'] as String? ?? 'nightshade',
      );

  @override
  List<Object?> get props => [
    host,
    port,
    username,
    password,
    topic,
    qos,
    retain,
    useTls,
    clientId,
  ];
}
