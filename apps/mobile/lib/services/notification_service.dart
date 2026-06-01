import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

part 'notification_service/contracts.dart';

class MobileNotificationService implements MobileNotificationSink {
  static final MobileNotificationService _instance =
      MobileNotificationService._internal();
  factory MobileNotificationService() => _instance;
  MobileNotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// True after [initialize] confirms the user has granted Critical Alert
  /// authorization on iOS. Stays false on Android (where the concept does
  /// not exist) and on iOS builds without the
  /// `com.apple.developer.usernotifications.critical-alerts` entitlement
  /// (in which case the permission prompt never even appears). Consumed by
  /// the iOS background banner so it can tell the operator whether
  /// safety/guiding/equipment alerts will actually wake them.
  bool _criticalAlertsAuthorized = false;
  bool get criticalAlertsAuthorized => _criticalAlertsAuthorized;

  /// True after [initialize] confirms the Android runtime
  /// `POST_NOTIFICATIONS` permission is granted (Android 13+ / API 33+).
  /// Stays true on Android <=12 (where the permission grant is implicit at
  /// install time) and on non-Android platforms (where this provider is
  /// not consumed). Read by the Android notifications banner so it can
  /// nag the operator into granting the permission before a sequence
  /// runs. See P1-16a / audit §7 bug 3.
  bool _androidNotificationsAuthorized = true;
  bool get androidNotificationsAuthorized => _androidNotificationsAuthorized;

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
  // P1-2/P1-3 job-failure notifications. Distinct IDs so a plate-solve
  // failure during a center-on-target sequence doesn't replace the
  // higher-level centering failure (the user wants to see both).
  static const int _plateSolveFailedId = 112;
  static const int _centeringFailedId = 113;
  static const int _polarAlignmentFailedId = 114;
  // P1-5 session ownership notifications.
  static const int _ownershipTakenOverId = 115;
  static const int _ownershipAutoReleasedId = 116;

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
    // requestCriticalPermission triggers the iOS Critical Alerts prompt at
    // initialization time. The prompt only ever appears if the build is
    // signed with a provisioning profile that carries the
    // `com.apple.developer.usernotifications.critical-alerts` entitlement
    // (granted by Apple after a written request — see
    // apps/mobile/ios/CRITICAL_ALERTS_SETUP.md). Without the entitlement,
    // iOS silently accepts the call as a no-op and notifications fall
    // back to default interruption level.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      requestCriticalPermission: true,
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
      // Android 13+ (API 33) requires a runtime POST_NOTIFICATIONS grant
      // before *any* local notification will display. Without it,
      // sequence-failed / guiding-lost / safety alerts vanish silently
      // (no exception, no log). Request it explicitly at app startup so
      // the operator sees the system prompt before any sequence runs.
      // See P1-16a / audit §7 bug 3.
      await _requestAndroidNotificationPermission();
    }

    // Request permissions for iOS
    if (Platform.isIOS) {
      final ios = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      // Re-request explicitly so the `critical` flag is included even when
      // a previous app version initialized without it. iOS only shows the
      // critical-alerts prompt once; subsequent calls return the cached
      // decision without prompting again.
      await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
        critical: true,
      );
      // Read back the authorized state so callers (e.g. the iOS background
      // banner) can adapt their copy. `checkPermissions` returns null on
      // older iOS versions; treat null as "not authorized".
      final status = await ios?.checkPermissions();
      _criticalAlertsAuthorized = status?.isCriticalEnabled ?? false;
    }

    _initialized = true;
  }

  /// Ask Android for the runtime POST_NOTIFICATIONS permission and stash
  /// the result. Safe to call on any API level — the plugin returns
  /// `true` without prompting on Android <=12 (API 32 and below), where
  /// the permission is implicitly granted at install time.
  ///
  /// We intentionally do NOT swallow failures: a `null` return from the
  /// platform channel means the call didn't reach Android (plugin mis-
  /// registration, missing AndroidManifest entry, etc.) and that is an
  /// error worth surfacing — the audit's no-silent-fallback rule. We
  /// log it and treat it as denied so the banner pops up and the
  /// operator notices something is wrong.
  Future<bool> _requestAndroidNotificationPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      // Plugin not registered on Android — would only happen if the
      // package was installed wrong. Surface loudly.
      developer.log(
        '[MobileNotificationService] AndroidFlutterLocalNotificationsPlugin '
        'unavailable; POST_NOTIFICATIONS cannot be requested.',
        name: 'MobileNotificationService',
        level: 1000,
      );
      _androidNotificationsAuthorized = false;
      return false;
    }
    final granted = await android.requestNotificationsPermission();
    if (granted == null) {
      developer.log(
        '[MobileNotificationService] requestNotificationsPermission '
        'returned null — treating as denied.',
        name: 'MobileNotificationService',
        level: 1000,
      );
      _androidNotificationsAuthorized = false;
      return false;
    }
    _androidNotificationsAuthorized = granted;
    if (!granted) {
      developer.log(
        '[MobileNotificationService] POST_NOTIFICATIONS was denied by '
        'the user. Sequence/safety alerts will be silenced until the '
        'user enables notifications in system settings.',
        name: 'MobileNotificationService',
        level: 900,
      );
    }
    return granted;
  }

  /// Re-query the current Android notification authorization state
  /// without re-prompting the user. Used by the Android banner to
  /// reflect permission grants that happen after first launch (e.g. the
  /// operator toggled notifications on in system settings and came back
  /// to the app). Returns the freshly-read state.
  Future<bool> refreshAndroidNotificationsAuthorization() async {
    if (!Platform.isAndroid) {
      // Non-Android platforms have no equivalent gate — the consumer of
      // this provider only watches it on Android, but be explicit.
      _androidNotificationsAuthorized = true;
      return true;
    }
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) {
      _androidNotificationsAuthorized = false;
      return false;
    }
    final enabled = await android.areNotificationsEnabled();
    _androidNotificationsAuthorized = enabled ?? false;
    return _androidNotificationsAuthorized;
  }

  /// Re-query the current iOS notification authorization state without
  /// re-prompting the user. Used by the iOS background banner to reflect
  /// permission grants that happen after first launch (e.g. the operator
  /// toggled Critical Alerts on in Settings).
  Future<bool> refreshCriticalAlertsAuthorization() async {
    if (!Platform.isIOS) {
      _criticalAlertsAuthorized = false;
      return false;
    }
    final ios = _notifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final status = await ios?.checkPermissions();
    _criticalAlertsAuthorized = status?.isCriticalEnabled ?? false;
    return _criticalAlertsAuthorized;
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
      case 'plate_solve_failed':
      case 'centering_failed':
        // Both job-failure paths land on the imaging viewport because that
        // screen exposes the "solve again" / "re-center" actions.
        return '/imaging';
      case 'polar_alignment_failed':
        // Polar align has its own dedicated screen; route there directly.
        return '/polar-alignment';
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
      case 'ownership_taken_over':
      case 'ownership_auto_released':
        // Session ownership state lives on the dashboard banner; that's
        // where the user resolves the take-over.
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

  // ---------------------------------------------------------------------------
  // Job-failure notifications (Wave 3 / P1-2 P1-3)
  //
  // These map onto specific `JobFailed` events that the headless server
  // emits for long-running jobs. We don't surface JobStarted/JobProgress/
  // JobCompleted at all — a sequence emits dozens of progress events for
  // a single plate-solve and we are not in the business of buzzing the
  // operator's phone every tick. Only terminal failures get a ping.
  // ---------------------------------------------------------------------------

  @override
  Future<void> notifyPlateSolveFailed(String errorMessage) async {
    await _notifications.show(
      _plateSolveFailedId,
      'Plate Solve Failed',
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
      payload: 'plate_solve_failed',
    );
  }

  @override
  Future<void> notifyCenteringFailed(String errorMessage) async {
    await _notifications.show(
      _centeringFailedId,
      'Centering Failed',
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
      payload: 'centering_failed',
    );
  }

  @override
  Future<void> notifyPolarAlignmentFailed(String errorMessage) async {
    await _notifications.show(
      _polarAlignmentFailedId,
      'Polar Alignment Failed',
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
      payload: 'polar_alignment_failed',
    );
  }

  // ---------------------------------------------------------------------------
  // Session ownership notifications (Wave 3 / P1-5)
  // ---------------------------------------------------------------------------

  @override
  Future<void> notifyOwnershipTakenOver({
    String? displacingClientName,
    String? reason,
  }) async {
    final who = displacingClientName?.trim().isNotEmpty == true
        ? displacingClientName!
        : 'Another client';
    final body = reason != null && reason.isNotEmpty
        ? '$who took over control ($reason).'
        : '$who took over control.';
    await _notifications.show(
      _ownershipTakenOverId,
      'Control Taken Over',
      body,
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
      payload: 'ownership_taken_over',
    );
  }

  @override
  Future<void> notifyOwnershipAutoReleased(String reason) async {
    await _notifications.show(
      _ownershipAutoReleasedId,
      'Session Released',
      'Your session was released due to inactivity ($reason).',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nightshade_info',
          'Information',
          channelDescription: 'General information like meridian flips',
          importance: Importance.defaultImportance,
          priority: Priority.low,
          playSound: false,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
          interruptionLevel: InterruptionLevel.passive,
        ),
      ),
      payload: 'ownership_auto_released',
    );
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
  }
}
