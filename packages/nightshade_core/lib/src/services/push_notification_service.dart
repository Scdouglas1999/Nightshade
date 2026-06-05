import 'dart:async';
import 'dart:developer' as developer;
import '../models/backend/event_types.dart';
import '../models/notification/notification_categories.dart';
import 'notification/event_classifier.dart';

/// Priority level for push notifications sent to mobile devices
enum PushNotificationPriority {
  /// Low priority - informational events
  low,

  /// Normal priority - standard completion events
  normal,

  /// High priority - errors and safety events requiring attention
  high,

  /// Critical priority - immediate attention required (weather unsafe, guiding lost)
  critical,
}

/// A push notification ready to be sent to connected mobile devices
class PushNotification {
  final String title;
  final String body;
  final PushNotificationPriority priority;
  final String eventType;
  final EventCategory category;
  final DateTime timestamp;

  const PushNotification({
    required this.title,
    required this.body,
    required this.priority,
    required this.eventType,
    required this.category,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'type': 'push_notification',
        'title': title,
        'body': body,
        'priority': priority.name,
        'eventType': eventType,
        'category': category.name,
        'timestamp': timestamp.millisecondsSinceEpoch,
      };
}

/// Configuration for which events should generate push notifications
class PushNotificationConfig {
  final bool enabled;
  final bool notifySequenceCompleted;
  final bool notifySequenceFailed;
  final bool notifyMeridianFlip;
  final bool notifyWeatherUnsafe;
  final bool notifyGuidingLost;
  final bool notifyExposureFailed;
  final bool notifyAutofocusFailed;
  final bool notifyEquipmentDisconnected;

  const PushNotificationConfig({
    this.enabled = true,
    this.notifySequenceCompleted = true,
    this.notifySequenceFailed = true,
    this.notifyMeridianFlip = true,
    this.notifyWeatherUnsafe = true,
    this.notifyGuidingLost = true,
    this.notifyExposureFailed = true,
    this.notifyAutofocusFailed = true,
    this.notifyEquipmentDisconnected = false,
  });

  PushNotificationConfig copyWith({
    bool? enabled,
    bool? notifySequenceCompleted,
    bool? notifySequenceFailed,
    bool? notifyMeridianFlip,
    bool? notifyWeatherUnsafe,
    bool? notifyGuidingLost,
    bool? notifyExposureFailed,
    bool? notifyAutofocusFailed,
    bool? notifyEquipmentDisconnected,
  }) {
    return PushNotificationConfig(
      enabled: enabled ?? this.enabled,
      notifySequenceCompleted:
          notifySequenceCompleted ?? this.notifySequenceCompleted,
      notifySequenceFailed:
          notifySequenceFailed ?? this.notifySequenceFailed,
      notifyMeridianFlip: notifyMeridianFlip ?? this.notifyMeridianFlip,
      notifyWeatherUnsafe:
          notifyWeatherUnsafe ?? this.notifyWeatherUnsafe,
      notifyGuidingLost: notifyGuidingLost ?? this.notifyGuidingLost,
      notifyExposureFailed:
          notifyExposureFailed ?? this.notifyExposureFailed,
      notifyAutofocusFailed:
          notifyAutofocusFailed ?? this.notifyAutofocusFailed,
      notifyEquipmentDisconnected:
          notifyEquipmentDisconnected ?? this.notifyEquipmentDisconnected,
    );
  }
}

/// Service that filters backend events and creates push notifications for mobile devices.
///
/// This service subscribes to the backend event stream, identifies critical events,
/// and emits PushNotification objects via its own stream. The provider layer is
/// responsible for broadcasting these to connected WebSocket clients.
class PushNotificationService {
  final Stream<NightshadeEvent> _eventStream;
  PushNotificationConfig _config;

  StreamSubscription<NightshadeEvent>? _subscription;
  final StreamController<PushNotification> _notificationController =
      StreamController<PushNotification>.broadcast();

  PushNotificationService({
    required Stream<NightshadeEvent> eventStream,
    PushNotificationConfig config = const PushNotificationConfig(),
  })  : _eventStream = eventStream,
        _config = config;

  /// Stream of push notifications to broadcast to mobile clients
  Stream<PushNotification> get notifications => _notificationController.stream;

  /// Current configuration
  PushNotificationConfig get config => _config;

  /// Update configuration
  void updateConfig(PushNotificationConfig config) {
    _config = config;
    if (config.enabled && _subscription == null) {
      start();
    } else if (!config.enabled && _subscription != null) {
      stop();
    }
  }

  /// Start listening to the event stream
  void start() {
    if (!_config.enabled) return;
    _subscription?.cancel();
    _subscription = _eventStream.listen(
      _handleEvent,
      onError: (error) {
        developer.log(
            '[PushNotificationService] Event stream error: $error',
            name: 'PushNotificationService',
            level: 1000,
            error: error);
      },
    );
    developer.log('[PushNotificationService] Started listening for events',
        name: 'PushNotificationService', level: 800);
  }

  /// Stop listening to the event stream
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    developer.log('[PushNotificationService] Stopped',
        name: 'PushNotificationService', level: 800);
  }

  /// Inject a push notification that did NOT originate from the backend
  /// event stream. Used by the Run Dashboard critical-events bridge to
  /// dispatch a high-priority push when the user has enabled
  /// `pushCriticalAlerts` in settings.
  ///
  /// Why a separate path: [_handleEvent] only fires for events the service
  /// recognises via [_eventToNotification]; many critical events flagged by
  /// `bridge_event.isCriticalEvent` (e.g. equipment errors, FITS save
  /// failures, etc.) don't match those handlers. The bridge knows the full
  /// criticality classification and explicitly forwards them here. The
  /// `enabled` gate still applies — if the user has disabled push entirely,
  /// nothing is broadcast.
  void enqueueCriticalNotification({
    required String title,
    required String body,
    required String eventType,
    required EventCategory category,
  }) {
    if (!_config.enabled) return;
    _notificationController.add(PushNotification(
      title: title,
      body: body,
      priority: PushNotificationPriority.critical,
      eventType: eventType,
      category: category,
      timestamp: DateTime.now(),
    ));
  }

  /// Emit a test push notification
  void sendTestNotification() {
    _notificationController.add(PushNotification(
      title: 'Test Notification',
      body:
          'Push notifications are working! This is a test from Nightshade.',
      priority: PushNotificationPriority.normal,
      eventType: 'Test',
      category: EventCategory.system,
      timestamp: DateTime.now(),
    ));
  }

  /// Process an event and emit a push notification if it matches the config
  void _handleEvent(NightshadeEvent event) {
    if (!_config.enabled) return;

    final notification = _eventToNotification(event);
    if (notification != null) {
      _notificationController.add(notification);
      developer.log(
          '[PushNotificationService] Push notification: ${notification.title}',
          name: 'PushNotificationService',
          level: 800);
    }
  }

  /// Convert an event to a push notification, or null if it should be skipped.
  ///
  /// Classification is delegated to the shared [NotificationEventClassifier]
  /// (the same one [NotificationRouter] uses) so the router and the mobile
  /// push feed can never disagree about what an event *is*. This service
  /// then applies its own per-event-type [PushNotificationConfig] toggle,
  /// priority, and copy on top of that classification — preserving exactly
  /// the subset of events it historically pushed.
  PushNotification? _eventToNotification(NightshadeEvent event) {
    // P1-11 — OTA update is a system event the shared classifier does not
    // route (it is operator-driven, not a notification category). Handle it
    // first so it still surfaces as a phone push.
    if (event.category == EventCategory.system &&
        event.eventType == 'UpdateAvailable') {
      final latest = event.data['latestVersion'] as String? ?? 'a new version';
      final current =
          event.data['currentVersion'] as String? ?? 'the current build';
      return PushNotification(
        title: 'Nightshade $latest available',
        body:
            'Open Settings > Updates to install the new build (currently on $current).',
        priority: PushNotificationPriority.normal,
        eventType: event.eventType,
        category: event.category,
        timestamp: DateTime.now(),
      );
    }

    final classified = NotificationEventClassifier.classify(event);
    if (classified == null) return null;

    final spec = _pushSpecFor(classified.category);
    if (spec == null) return null; // category this feed doesn't push
    if (!spec.enabled(_config)) return null; // per-event toggle off

    // A folded category (e.g. guidingLost = StarLost + Disconnected) may
    // carry an eventType-specific priority/title/body override.
    final override = spec.override?.call(event);

    return PushNotification(
      title: override?.title ?? spec.title,
      body: override?.body ?? spec.body(event),
      priority: override?.priority ?? spec.priority,
      eventType: event.eventType,
      category: event.category,
      timestamp: DateTime.now(),
    );
  }

  /// Per-category push spec: the toggle gate, priority, title, and body
  /// builder for each [NotificationCategory] this mobile feed escalates.
  /// Returns `null` for categories the mobile feed intentionally does NOT
  /// push (matching the historical [PushNotificationService] coverage).
  _PushSpec? _pushSpecFor(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.sequenceCompleted:
        return _PushSpec(
          enabled: (c) => c.notifySequenceCompleted,
          priority: PushNotificationPriority.normal,
          title: 'Sequence Complete',
          body: (_) => 'Your imaging sequence has finished successfully.',
        );
      case NotificationCategory.sequenceFailed:
        // The classifier folds both `Error` and `Stopped` into
        // sequenceFailed. Preserve the original per-eventType copy +
        // priority (Error = high w/ message, Stopped = normal).
        return _PushSpec(
          enabled: (c) => c.notifySequenceFailed,
          priority: PushNotificationPriority.high,
          title: 'Sequence Error',
          body: (e) => 'Sequence encountered an error: '
              '${e.data['message'] as String? ?? 'Unknown error'}',
          override: (e) => e.eventType == 'Stopped'
              ? const _PushOverride(
                  priority: PushNotificationPriority.normal,
                  title: 'Sequence Stopped',
                  body: 'The imaging sequence has been stopped.',
                )
              : null,
        );
      case NotificationCategory.targetCompleted:
        return _PushSpec(
          enabled: (c) => c.notifySequenceCompleted,
          priority: PushNotificationPriority.low,
          title: 'Target Complete',
          body: (e) =>
              'Finished imaging target: '
              '${e.data['target_name'] as String? ?? 'Unknown target'}',
        );
      case NotificationCategory.autofocusFailed:
        return _PushSpec(
          enabled: (c) => c.notifyAutofocusFailed,
          priority: PushNotificationPriority.high,
          title: 'Autofocus Failed',
          body: (_) => 'Autofocus did not complete successfully.',
        );
      case NotificationCategory.meridianFlipPerformed:
        return _PushSpec(
          enabled: (c) => c.notifyMeridianFlip,
          priority: PushNotificationPriority.normal,
          title: 'Meridian Flip',
          body: (e) =>
              e.data['detail'] as String? ?? 'Performing meridian flip',
        );
      case NotificationCategory.exposureFailed:
        return _PushSpec(
          enabled: (c) => c.notifyExposureFailed,
          priority: PushNotificationPriority.high,
          title: 'Exposure Failed',
          body: (e) => 'Camera exposure failed: '
              '${e.data['error'] as String? ?? e.data['reason'] as String? ?? 'Unknown error'}',
        );
      case NotificationCategory.guidingLost:
        // The classifier folds StarLost + Disconnected into guidingLost.
        // Preserve the original priority split (StarLost = critical,
        // Disconnected = high) and copy.
        return _PushSpec(
          enabled: (c) => c.notifyGuidingLost,
          priority: PushNotificationPriority.critical,
          title: 'Guiding Lost',
          body: (_) => 'Guide star has been lost. Guiding has stopped.',
          override: (e) => e.eventType == 'Disconnected'
              ? const _PushOverride(
                  priority: PushNotificationPriority.high,
                  title: 'Guider Disconnected',
                  body: 'PHD2 guiding has disconnected.',
                )
              : null,
        );
      case NotificationCategory.weatherUnsafe:
        return _PushSpec(
          enabled: (c) => c.notifyWeatherUnsafe,
          priority: PushNotificationPriority.critical,
          title: 'Weather Unsafe',
          body: (_) => 'Safety monitor reports unsafe conditions. '
              'The mount may be parked to protect equipment.',
        );
      case NotificationCategory.equipmentDisconnected:
        // Classifier folds Disconnected + Error into equipmentDisconnected.
        return _PushSpec(
          enabled: (c) => c.notifyEquipmentDisconnected,
          priority: PushNotificationPriority.high,
          title: 'Device Disconnected',
          body: (e) =>
              '${e.data['device_type'] as String? ?? 'Unknown'} device '
              'disconnected: ${e.data['device_id'] as String? ?? 'Unknown'}',
          override: (e) => e.eventType == 'Error'
              ? _PushOverride(
                  priority: PushNotificationPriority.high,
                  title: 'Equipment Error',
                  body: '${e.data['device_type'] as String? ?? 'Unknown'} '
                      'error: ${e.data['message'] as String? ?? 'Unknown error'}',
                )
              : null,
        );
      // Categories the mobile push feed intentionally does NOT escalate
      // (they surface in-app only): sequence start/pause/resume, target
      // start, frame captured/rejected, trigger fired, recovery lifecycle,
      // weather-safe-again, cloud, disk, autofocus-completed, etc.
      default:
        return null;
    }
  }

  /// Dispose of resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _notificationController.close();
  }
}

/// How a single [NotificationCategory] is escalated to a mobile push: which
/// config toggle gates it, its default priority, and the title/body copy.
/// The [override] callback handles folded categories whose individual
/// eventTypes need different priority/copy (e.g. guidingLost covers both a
/// critical StarLost and a high-priority guider Disconnected).
class _PushSpec {
  final bool Function(PushNotificationConfig) enabled;
  final PushNotificationPriority priority;
  final String title;
  final String Function(NightshadeEvent) body;
  final _PushOverride? Function(NightshadeEvent)? override;

  const _PushSpec({
    required this.enabled,
    required this.priority,
    required this.title,
    required this.body,
    this.override,
  });
}

/// A per-eventType override of the priority/title/body within a folded
/// [NotificationCategory].
class _PushOverride {
  final PushNotificationPriority priority;
  final String title;
  final String body;

  const _PushOverride({
    required this.priority,
    required this.title,
    required this.body,
  });
}
