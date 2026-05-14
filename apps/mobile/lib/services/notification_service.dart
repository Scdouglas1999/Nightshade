import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

/// Callback the app installs so notification taps can drive go_router.
///
/// The notification plugin fires on a platform thread without access to a
/// BuildContext, so the app supplies a function that performs the navigation
/// via the GoRouter instance it owns (audit §3.8).
typedef NotificationNavigator = void Function(String location);

class MobileNotificationService {
  static final MobileNotificationService _instance =
      MobileNotificationService._internal();
  factory MobileNotificationService() => _instance;
  MobileNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Installed by the app at startup — see [setNavigator].
  NotificationNavigator? _navigator;

  // Notification IDs
  static const int _sequenceCompleteId = 100;
  static const int _sequenceFailedId = 101;
  static const int _meridianFlipId = 102;
  static const int _lowDiskSpaceId = 103;
  static const int _lowBatteryId = 104;

  /// Auto-incrementing ID for push notifications from the desktop
  int _nextPushNotificationId = 200;

  // Notification settings (could be exposed via settings provider)
  bool enableSequenceNotifications = true;
  bool enableMeridianFlipNotifications = true;
  bool enableWarningNotifications = true;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    // Request permissions for iOS
    if (Platform.isIOS) {
      await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    }

    _initialized = true;
  }

  Future<void> _createNotificationChannels() async {
    const sequenceChannel = AndroidNotificationChannel(
      'nightshade_sequence',
      'Sequence Events',
      description: 'Notifications for sequence completion and failures',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const warningChannel = AndroidNotificationChannel(
      'nightshade_warnings',
      'Warnings',
      description: 'Important warnings about battery, disk space, etc.',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    const infoChannel = AndroidNotificationChannel(
      'nightshade_info',
      'Information',
      description: 'General information like meridian flips',
      importance: Importance.defaultImportance,
      playSound: false,
      enableVibration: false,
    );

    const pushChannel = AndroidNotificationChannel(
      'nightshade_push',
      'Desktop Alerts',
      description: 'Push notifications from the connected desktop',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    final androidImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidImplementation?.createNotificationChannel(sequenceChannel);
    await androidImplementation?.createNotificationChannel(warningChannel);
    await androidImplementation?.createNotificationChannel(infoChannel);
    await androidImplementation?.createNotificationChannel(pushChannel);
  }

  /// Register a callback the service uses to deep-link into the app when
  /// a notification is tapped. The app installs this once it has a router.
  void setNavigator(NotificationNavigator navigator) {
    _navigator = navigator;
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final route = _routeForPayload(payload);
    if (route == null) {
      // Unknown payload shape — surfacing it loudly beats silent fallback.
      debugPrint(
          '[MobileNotificationService] Notification payload has no route: $payload');
      return;
    }

    final navigator = _navigator;
    if (navigator == null) {
      // The app hasn't wired up the router yet (cold start path). Record
      // the route so we don't pretend the tap did something.
      debugPrint(
          '[MobileNotificationService] No navigator installed; dropped tap to $route ($payload)');
      return;
    }

    navigator(route);
  }

  /// Map a notification [payload] to a go_router location.
  ///
  /// Payload format follows the conventions used elsewhere in the service:
  ///   `image_ready:<imageId>`           -> `/imaging/preview/<imageId>`
  ///   `sequence_complete:<target>`      -> `/sequencer`
  ///   `sequence_failed:<target>`        -> `/sequencer`
  ///   `meridian_flip:<target>`          -> `/sequencer`
  ///   `low_battery:<percent>`           -> `/dashboard`
  ///   `low_disk_space`                  -> `/dashboard`
  ///   `push:<eventType>`                -> `/dashboard` (desktop pushes
  ///                                        without an obvious target)
  String? _routeForPayload(String payload) {
    final colon = payload.indexOf(':');
    final type = colon == -1 ? payload : payload.substring(0, colon);
    final arg = colon == -1 ? null : payload.substring(colon + 1);

    switch (type) {
      case 'image_ready':
        if (arg == null || arg.isEmpty) return '/imaging';
        return '/imaging/preview/${Uri.encodeComponent(arg)}';
      case 'sequence_complete':
      case 'sequence_failed':
      case 'meridian_flip':
        return '/sequencer';
      case 'low_battery':
      case 'low_disk_space':
        return '/dashboard';
      case 'push':
        return '/dashboard';
      default:
        return null;
    }
  }

  Future<void> notifySequenceComplete(String targetName, int imageCount) async {
    if (!enableSequenceNotifications) return;

    await _notifications.show(
      _sequenceCompleteId,
      'Sequence Complete',
      'Imaging of $targetName finished. $imageCount images captured.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_sequence',
          'Sequence Events',
          channelDescription:
              'Notifications for sequence completion and failures',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'sequence_complete:$targetName',
    );
  }

  Future<void> notifySequenceFailed(
      String targetName, String errorMessage) async {
    if (!enableSequenceNotifications) return;

    await _notifications.show(
      _sequenceFailedId,
      'Sequence Failed',
      'Imaging of $targetName failed: $errorMessage',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_sequence',
          'Sequence Events',
          channelDescription:
              'Notifications for sequence completion and failures',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'sequence_failed:$targetName',
    );
  }

  Future<void> notifyMeridianFlip(String targetName, DateTime flipTime) async {
    if (!enableMeridianFlipNotifications) return;

    final timeStr =
        '${flipTime.hour.toString().padLeft(2, '0')}:${flipTime.minute.toString().padLeft(2, '0')}';

    await _notifications.show(
      _meridianFlipId,
      'Meridian Flip',
      'Performing meridian flip for $targetName at $timeStr',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_info',
          'Information',
          channelDescription: 'General information like meridian flips',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      ),
      payload: 'meridian_flip:$targetName',
    );
  }

  Future<void> notifyLowDiskSpace(double remainingGB) async {
    if (!enableWarningNotifications) return;

    await _notifications.show(
      _lowDiskSpaceId,
      'Low Disk Space',
      'Only ${remainingGB.toStringAsFixed(1)} GB remaining. Consider freeing up space.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_warnings',
          'Warnings',
          channelDescription:
              'Important warnings about battery, disk space, etc.',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'low_disk_space',
    );
  }

  Future<void> notifyLowBattery(int percentage) async {
    if (!enableWarningNotifications) return;

    String message;
    if (percentage <= 10) {
      message =
          'Critical battery level ($percentage%). Sequence will be paused to protect data.';
    } else if (percentage <= 15) {
      message =
          'Very low battery ($percentage%). Consider pausing the sequence.';
    } else {
      message = 'Battery is low ($percentage%). Please connect charger.';
    }

    await _notifications.show(
      _lowBatteryId,
      'Low Battery',
      message,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_warnings',
          'Warnings',
          channelDescription:
              'Important warnings about battery, disk space, etc.',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'low_battery:$percentage',
    );
  }

  /// Display a push notification received from the desktop via WebSocket.
  ///
  /// The [data] map should contain 'title', 'body', and 'priority' fields
  /// as sent by PushNotificationService.toJson().
  Future<void> notifyPush(Map<String, dynamic> data) async {
    final title = data['title'] as String? ?? 'Nightshade';
    final body = data['body'] as String? ?? '';
    final priority = data['priority'] as String? ?? 'normal';
    final eventType = data['eventType'] as String? ?? 'push';

    // Map priority to Android notification importance and sound
    final bool playSound;
    final Importance importance;
    final Priority androidPriority;
    switch (priority) {
      case 'critical':
      case 'high':
        playSound = true;
        importance = Importance.high;
        androidPriority = Priority.high;
      case 'low':
        playSound = false;
        importance = Importance.defaultImportance;
        androidPriority = Priority.defaultPriority;
      default:
        playSound = true;
        importance = Importance.high;
        androidPriority = Priority.high;
    }

    final id = _nextPushNotificationId++;
    // Wrap around to avoid overflow, keeping it above the reserved IDs
    if (_nextPushNotificationId > 9999) {
      _nextPushNotificationId = 200;
    }

    await _notifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_push',
          'Desktop Alerts',
          channelDescription: 'Push notifications from the connected desktop',
          importance: importance,
          priority: androidPriority,
          playSound: playSound,
          enableVibration: playSound,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
        ),
      ),
      payload: 'push:$eventType',
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
