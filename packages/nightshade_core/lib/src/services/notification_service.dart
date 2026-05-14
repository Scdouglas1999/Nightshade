import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../providers/settings_provider.dart';

/// Notification event types
enum NotificationEvent {
  sequenceComplete,
  error,
  meridianFlip,
  captureComplete,
  autofocusComplete,
  custom,
}

/// Notification priority levels for Pushover
enum NotificationPriority {
  lowest(-2),
  low(-1),
  normal(0),
  high(1),
  emergency(2);

  final int value;
  const NotificationPriority(this.value);
}

/// Service for sending notifications via Discord and Pushover
class NotificationService {
  static const Duration defaultRequestTimeout = Duration(seconds: 15);

  final Ref? _ref;
  final AppSettingsState? Function()? _settingsReader;
  final http.Client _httpClient;
  final Duration _requestTimeout;
  final bool _ownsHttpClient;

  NotificationService(
    Ref ref, {
    http.Client? httpClient,
    Duration requestTimeout = defaultRequestTimeout,
  })  : _ref = ref,
        _settingsReader = null,
        _httpClient = httpClient ?? http.Client(),
        _requestTimeout = requestTimeout,
        _ownsHttpClient = httpClient == null;

  NotificationService.testing({
    required AppSettingsState? Function() settingsReader,
    http.Client? httpClient,
    Duration requestTimeout = defaultRequestTimeout,
  })  : _ref = null,
        _settingsReader = settingsReader,
        _httpClient = httpClient ?? http.Client(),
        _requestTimeout = requestTimeout,
        _ownsHttpClient = httpClient == null;

  void dispose() {
    if (_ownsHttpClient) {
      _httpClient.close();
    }
  }

  AppSettingsState? _readSettings() {
    return _settingsReader?.call() ??
        _ref?.read(appSettingsProvider).valueOrNull;
  }

  /// Send a notification based on the event type
  /// Returns true if at least one notification was sent successfully
  Future<bool> notify({
    required NotificationEvent event,
    required String title,
    required String message,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    final settings = _readSettings();
    if (settings == null || !settings.notificationsEnabled) {
      return false;
    }

    if (!_shouldNotifyForEvent(event, settings)) {
      return false;
    }

    final results = await Future.wait([
      _sendDiscordNotification(title, message, event, settings),
      _sendPushoverNotification(title, message, priority, settings),
    ]);

    return results.any((success) => success);
  }

  /// Send a notification for sequence completion
  Future<bool> notifySequenceComplete({
    required String sequenceName,
    required int imagesCapured,
    required Duration totalTime,
    String? targetName,
  }) async {
    final timeStr = _formatDuration(totalTime);
    final message = targetName != null
        ? 'Target: $targetName\nImages: $imagesCapured\nTotal time: $timeStr'
        : 'Images: $imagesCapured\nTotal time: $timeStr';

    return notify(
      event: NotificationEvent.sequenceComplete,
      title: 'Sequence Complete: $sequenceName',
      message: message,
    );
  }

  /// Send a notification for errors
  Future<bool> notifyError({
    required String errorTitle,
    required String errorMessage,
    String? source,
  }) async {
    final message =
        source != null ? 'Source: $source\n$errorMessage' : errorMessage;

    return notify(
      event: NotificationEvent.error,
      title: 'Error: $errorTitle',
      message: message,
      priority: NotificationPriority.high,
    );
  }

  /// Send a notification for meridian flip
  Future<bool> notifyMeridianFlip({
    required bool isStarting,
    String? targetName,
  }) async {
    final title =
        isStarting ? 'Meridian Flip Starting' : 'Meridian Flip Complete';
    final message = targetName != null
        ? 'Target: $targetName'
        : isStarting
            ? 'Mount is flipping...'
            : 'Mount flip completed successfully';

    return notify(
      event: NotificationEvent.meridianFlip,
      title: title,
      message: message,
    );
  }

  /// Send a custom notification
  Future<bool> notifyCustom({
    required String title,
    required String message,
    NotificationPriority priority = NotificationPriority.normal,
  }) async {
    return notify(
      event: NotificationEvent.custom,
      title: title,
      message: message,
      priority: priority,
    );
  }

  bool _shouldNotifyForEvent(NotificationEvent event, AppSettingsState settings) {
    switch (event) {
      case NotificationEvent.sequenceComplete:
        return settings.notifyOnSequenceComplete;
      case NotificationEvent.error:
        return settings.notifyOnError;
      case NotificationEvent.meridianFlip:
        return settings.notifyOnMeridianFlip;
      case NotificationEvent.captureComplete:
      case NotificationEvent.autofocusComplete:
      case NotificationEvent.custom:
        return true;
    }
  }

  /// Send a Discord webhook notification
  Future<bool> _sendDiscordNotification(
    String title,
    String message,
    NotificationEvent event,
    AppSettingsState settings,
  ) async {
    if (settings.discordWebhook.isEmpty) {
      return false;
    }

    try {
      final response = await _httpClient
          .post(
            Uri.parse(settings.discordWebhook),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'embeds': [
                {
                  'title': title,
                  'description': message,
                  'color': _getDiscordColor(event),
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                  'footer': {'text': 'Nightshade 2.0'},
                },
              ],
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[Notification] Discord notification sent successfully');
        return true;
      }

      debugPrint(
          '[Notification] Discord notification failed: ${response.statusCode} ${response.body}');
      return false;
    } on TimeoutException {
      debugPrint(
          '[Notification] Discord notification timed out after ${_requestTimeout.inSeconds}s');
      return false;
    } catch (e) {
      debugPrint('[Notification] Discord notification error: $e');
      return false;
    }
  }

  /// Send a Pushover notification
  Future<bool> _sendPushoverNotification(
    String title,
    String message,
    NotificationPriority priority,
    AppSettingsState settings,
  ) async {
    if (settings.pushoverKey.isEmpty || settings.pushoverUser.isEmpty) {
      return false;
    }

    try {
      final response = await _httpClient.post(
        Uri.parse('https://api.pushover.net/1/messages.json'),
        body: {
          'token': settings.pushoverKey,
          'user': settings.pushoverUser,
          'title': title,
          'message': message,
          'priority': priority.value.toString(),
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        debugPrint('[Notification] Pushover notification sent successfully');
        return true;
      }

      debugPrint(
          '[Notification] Pushover notification failed: ${response.statusCode} ${response.body}');
      return false;
    } on TimeoutException {
      debugPrint(
          '[Notification] Pushover notification timed out after ${_requestTimeout.inSeconds}s');
      return false;
    } catch (e) {
      debugPrint('[Notification] Pushover notification error: $e');
      return false;
    }
  }

  int _getDiscordColor(NotificationEvent event) {
    switch (event) {
      case NotificationEvent.sequenceComplete:
        return 0x22C55E;
      case NotificationEvent.error:
        return 0xEF4444;
      case NotificationEvent.meridianFlip:
        return 0x3B82F6;
      case NotificationEvent.captureComplete:
        return 0x6366F1;
      case NotificationEvent.autofocusComplete:
        return 0x8B5CF6;
      case NotificationEvent.custom:
        return 0x6366F1;
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  /// Test Discord webhook connection
  Future<bool> testDiscordWebhook(String webhookUrl) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'embeds': [
                {
                  'title': 'Test Notification',
                  'description':
                      'This is a test notification from Nightshade 2.0. If you see this, your Discord webhook is configured correctly!',
                  'color': 0x22C55E,
                  'timestamp': DateTime.now().toUtc().toIso8601String(),
                  'footer': {'text': 'Nightshade 2.0 - Test'},
                },
              ],
            }),
          )
          .timeout(_requestTimeout);

      return response.statusCode >= 200 && response.statusCode < 300;
    } on TimeoutException {
      debugPrint(
          '[Notification] Discord test timed out after ${_requestTimeout.inSeconds}s');
      return false;
    } catch (e) {
      debugPrint('[Notification] Discord test failed: $e');
      return false;
    }
  }

  /// Test Pushover connection
  Future<bool> testPushover(String token, String user) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('https://api.pushover.net/1/messages.json'),
        body: {
          'token': token,
          'user': user,
          'title': 'Test Notification',
          'message':
              'This is a test notification from Nightshade 2.0. If you see this, your Pushover is configured correctly!',
          'priority': '0',
        },
      ).timeout(_requestTimeout);

      return response.statusCode == 200;
    } on TimeoutException {
      debugPrint(
          '[Notification] Pushover test timed out after ${_requestTimeout.inSeconds}s');
      return false;
    } catch (e) {
      debugPrint('[Notification] Pushover test failed: $e');
      return false;
    }
  }
}

/// Provider for the notification service
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(ref);
  ref.onDispose(service.dispose);
  return service;
});
