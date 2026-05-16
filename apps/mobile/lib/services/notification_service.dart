import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Callback the app installs so notification taps can drive go_router.
///
/// The notification plugin fires on a platform thread without access to a
/// BuildContext, so the app supplies a function that performs the navigation
/// via the GoRouter instance it owns (audit §3.8).
typedef NotificationNavigator = void Function(String location);

/// Surface area of [MobileNotificationService] consumed by mobile-side
/// subscribers (battery, foreground service, mobile-direct event notifier).
///
/// Extracted so unit tests can supply a recording double without touching
/// the flutter_local_notifications plugin (which has no in-test host
/// implementation). Production code continues to use the singleton
/// [MobileNotificationService] directly; the abstraction exists purely for
/// dependency injection at test boundaries.
abstract class MobileNotificationSink {
  Future<void> notifySequenceComplete(String targetName, int imageCount);
  Future<void> notifySequenceFailed(String targetName, String errorMessage);
  Future<void> notifyMeridianFlip(String targetName, DateTime flipTime);
  Future<void> notifyLowDiskSpace(double remainingGB);
  Future<void> notifyLowBattery(int percentage);
  Future<void> notifySafety({
    required String title,
    required String body,
    String? eventType,
  });
  Future<void> notifyMountParked(String reason);
  Future<void> notifyGuidingLost(String reason);
  Future<void> notifyExposureFailed(String errorMessage);
  Future<void> notifyAutofocusFailed();
  Future<void> notifyEquipmentDisconnected(String deviceType, String deviceId);
  Future<void> notifyTargetCompleted(String targetName);
  Future<void> notifyPush(Map<String, dynamic> data);
}

class MobileNotificationService implements MobileNotificationSink {
  static final MobileNotificationService _instance =
      MobileNotificationService._internal();
  factory MobileNotificationService() => _instance;
  MobileNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Installed by the app at startup — see [setNavigator].
  NotificationNavigator? _navigator;

  // Reserved notification IDs (stable across app launches so a re-fire of
  // the same kind of event replaces the prior notification instead of
  // stacking).
  static const int _sequenceCompleteId = 100;
  static const int _sequenceFailedId = 101;
  static const int _meridianFlipId = 102;
  static const int _lowDiskSpaceId = 103;
  static const int _lowBatteryId = 104;
  static const int _safetyId = 105;
  static const int _guidingLostId = 106;
  static const int _exposureFailedId = 107;
  static const int _autofocusFailedId = 108;
  static const int _equipmentDisconnectedId = 109;
  static const int _targetCompletedId = 110;
  static const int _mountParkedId = 111;

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

    // Critical/safety events get a dedicated channel so users can grant it
    // bypass-Do-Not-Disturb access while leaving info channels muted.
    const criticalChannel = AndroidNotificationChannel(
      'nightshade_critical',
      'Critical Alerts',
      description:
          'Safety, guiding loss, and equipment failures during a running sequence',
      importance: Importance.max,
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
    await androidImplementation?.createNotificationChannel(criticalChannel);
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
      developer.log(
          '[MobileNotificationService] Notification payload has no route: $payload',
          name: 'MobileNotificationService',
          level: 900);
      return;
    }

    final navigator = _navigator;
    if (navigator == null) {
      // The app hasn't wired up the router yet (cold start path). Record
      // the route so we don't pretend the tap did something.
      developer.log(
          '[MobileNotificationService] No navigator installed; dropped tap to $route ($payload)',
          name: 'MobileNotificationService',
          level: 900);
      return;
    }

    navigator(route);
  }

  /// Map a notification [payload] to a go_router location.
  ///
  /// Payload format follows the convention `type[:arg]`. Each route below is
  /// chosen so a tap lands on the screen most relevant to the firing event:
  /// safety/guiding goes to the dashboard summary, exposure failure goes to
  /// the imaging viewport, etc.
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
      case 'target_completed':
      case 'autofocus_failed':
        return '/sequencer';
      case 'exposure_failed':
        return '/imaging';
      case 'guiding_lost':
        return '/guiding';
      case 'safety':
      case 'mount_parked':
        return '/weather';
      case 'equipment_disconnected':
        return '/equipment';
      case 'low_battery':
      case 'low_disk_space':
        return '/dashboard';
      case 'push':
        return '/dashboard';
      default:
        return null;
    }
  }

  @override
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

  @override
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

  @override
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

  @override
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

  @override
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

  // ---------------------------------------------------------------------------
  // Critical-event notifications (added v2.5 polish)
  //
  // These are the events that can occur silently in the middle of an
  // unattended sequence. Until v2.5.0-hardening, the mobile app only fired
  // notifications for sequence-state transitions (complete/failed) and
  // power events — it relied on the desktop's PushNotificationService to
  // surface safety / guiding / equipment failures. That made notifications
  // dependent on a feature config and a healthy desktop-side process; the
  // mobile companion now drives them directly from the WS event stream so
  // the user is paged even if push is disabled on the desktop.
  // ---------------------------------------------------------------------------

  @override
  Future<void> notifySafety({
    required String title,
    required String body,
    String? eventType,
  }) async {
    await _notifications.show(
      _safetyId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_critical',
          'Critical Alerts',
          channelDescription:
              'Safety, guiding loss, and equipment failures during a running sequence',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: eventType == 'mount_parked' ? 'mount_parked' : 'safety',
    );
  }

  @override
  Future<void> notifyMountParked(String reason) async {
    await _notifications.show(
      _mountParkedId,
      'Mount Parked',
      'Mount has been parked: $reason',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_critical',
          'Critical Alerts',
          channelDescription:
              'Safety, guiding loss, and equipment failures during a running sequence',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: 'mount_parked',
    );
  }

  @override
  Future<void> notifyGuidingLost(String reason) async {
    await _notifications.show(
      _guidingLostId,
      'Guiding Lost',
      reason,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_critical',
          'Critical Alerts',
          channelDescription:
              'Safety, guiding loss, and equipment failures during a running sequence',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: 'guiding_lost',
    );
  }

  @override
  Future<void> notifyExposureFailed(String errorMessage) async {
    await _notifications.show(
      _exposureFailedId,
      'Exposure Failed',
      errorMessage,
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
      payload: 'exposure_failed',
    );
  }

  @override
  Future<void> notifyAutofocusFailed() async {
    await _notifications.show(
      _autofocusFailedId,
      'Autofocus Failed',
      'Autofocus did not complete successfully.',
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
      payload: 'autofocus_failed',
    );
  }

  @override
  Future<void> notifyEquipmentDisconnected(
      String deviceType, String deviceId) async {
    await _notifications.show(
      _equipmentDisconnectedId,
      'Device Disconnected',
      '$deviceType disconnected: $deviceId',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_critical',
          'Critical Alerts',
          channelDescription:
              'Safety, guiding loss, and equipment failures during a running sequence',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.critical,
        ),
      ),
      payload: 'equipment_disconnected:$deviceType',
    );
  }

  @override
  Future<void> notifyTargetCompleted(String targetName) async {
    await _notifications.show(
      _targetCompletedId,
      'Target Complete',
      'Finished imaging target: $targetName',
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
      payload: 'target_completed:$targetName',
    );
  }

  /// Display a push notification received from the desktop via WebSocket.
  ///
  /// The [data] map should contain 'title', 'body', and 'priority' fields
  /// as sent by PushNotificationService.toJson().
  @override
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
