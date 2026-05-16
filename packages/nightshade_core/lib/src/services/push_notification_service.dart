import 'dart:async';
import 'dart:developer' as developer;
import '../models/backend/event_types.dart';

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

  /// Convert an event to a push notification, or null if it should be skipped
  PushNotification? _eventToNotification(NightshadeEvent event) {
    switch (event.category) {
      case EventCategory.sequencer:
        return _handleSequencerEvent(event);
      case EventCategory.imaging:
        return _handleImagingEvent(event);
      case EventCategory.guiding:
        return _handleGuidingEvent(event);
      case EventCategory.safety:
        return _handleSafetyEvent(event);
      case EventCategory.equipment:
        return _handleEquipmentEvent(event);
      case EventCategory.system:
      case EventCategory.polarAlignment:
        return null;
    }
  }

  PushNotification? _handleSequencerEvent(NightshadeEvent event) {
    switch (event.eventType) {
      case 'Completed':
        if (!_config.notifySequenceCompleted) return null;
        return PushNotification(
          title: 'Sequence Complete',
          body: 'Your imaging sequence has finished successfully.',
          priority: PushNotificationPriority.normal,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      case 'Error':
        if (!_config.notifySequenceFailed) return null;
        final message =
            event.data['message'] as String? ?? 'Unknown error';
        return PushNotification(
          title: 'Sequence Error',
          body: 'Sequence encountered an error: $message',
          priority: PushNotificationPriority.high,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      case 'Stopped':
        if (!_config.notifySequenceFailed) return null;
        return PushNotification(
          title: 'Sequence Stopped',
          body: 'The imaging sequence has been stopped.',
          priority: PushNotificationPriority.normal,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      case 'TargetCompleted':
        if (!_config.notifySequenceCompleted) return null;
        final targetName =
            event.data['target_name'] as String? ?? 'Unknown target';
        return PushNotification(
          title: 'Target Complete',
          body: 'Finished imaging target: $targetName',
          priority: PushNotificationPriority.low,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      case 'NodeCompleted':
        // Check if this is an autofocus node that failed
        final success = event.data['success'] as bool? ?? true;
        final nodeType = event.data['node_type'] as String? ?? '';
        if (!success &&
            nodeType.toLowerCase().contains('autofocus') &&
            _config.notifyAutofocusFailed) {
          return PushNotification(
            title: 'Autofocus Failed',
            body: 'Autofocus did not complete successfully.',
            priority: PushNotificationPriority.high,
            eventType: event.eventType,
            category: event.category,
            timestamp: DateTime.now(),
          );
        }
        return null;

      case 'InstructionProgress':
        // Check for meridian flip instruction progress
        final instruction = event.data['instruction'] as String? ?? '';
        if (instruction.toLowerCase().contains('meridian') &&
            _config.notifyMeridianFlip) {
          final detail = event.data['detail'] as String? ?? 'Performing meridian flip';
          return PushNotification(
            title: 'Meridian Flip',
            body: detail,
            priority: PushNotificationPriority.normal,
            eventType: event.eventType,
            category: event.category,
            timestamp: DateTime.now(),
          );
        }
        return null;

      default:
        return null;
    }
  }

  PushNotification? _handleImagingEvent(NightshadeEvent event) {
    switch (event.eventType) {
      case 'ExposureFailed':
        if (!_config.notifyExposureFailed) return null;
        final error = event.data['error'] as String? ??
            event.data['reason'] as String? ??
            'Unknown error';
        return PushNotification(
          title: 'Exposure Failed',
          body: 'Camera exposure failed: $error',
          priority: PushNotificationPriority.high,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      default:
        return null;
    }
  }

  PushNotification? _handleGuidingEvent(NightshadeEvent event) {
    switch (event.eventType) {
      case 'StarLost':
        if (!_config.notifyGuidingLost) return null;
        return PushNotification(
          title: 'Guiding Lost',
          body:
              'Guide star has been lost. Guiding has stopped.',
          priority: PushNotificationPriority.critical,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      case 'Disconnected':
        if (!_config.notifyGuidingLost) return null;
        return PushNotification(
          title: 'Guider Disconnected',
          body:
              'PHD2 guiding has disconnected.',
          priority: PushNotificationPriority.high,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      default:
        return null;
    }
  }

  PushNotification? _handleSafetyEvent(NightshadeEvent event) {
    // All safety events are critical and should always generate notifications
    // if the weather unsafe toggle is enabled
    if (!_config.notifyWeatherUnsafe) return null;

    return PushNotification(
      title: 'Weather Unsafe',
      body: 'Safety monitor reports unsafe conditions. '
          'The mount may be parked to protect equipment.',
      priority: PushNotificationPriority.critical,
      eventType: event.eventType,
      category: event.category,
      timestamp: DateTime.now(),
    );
  }

  PushNotification? _handleEquipmentEvent(NightshadeEvent event) {
    switch (event.eventType) {
      case 'Disconnected':
        if (!_config.notifyEquipmentDisconnected) return null;
        final deviceType =
            event.data['device_type'] as String? ?? 'Unknown';
        final deviceId =
            event.data['device_id'] as String? ?? 'Unknown';
        return PushNotification(
          title: 'Device Disconnected',
          body: '$deviceType device disconnected: $deviceId',
          priority: PushNotificationPriority.high,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

      case 'Error':
        if (!_config.notifyEquipmentDisconnected) return null;
        final message =
            event.data['message'] as String? ?? 'Unknown error';
        final deviceType =
            event.data['device_type'] as String? ?? 'Unknown';
        return PushNotification(
          title: 'Equipment Error',
          body: '$deviceType error: $message',
          priority: PushNotificationPriority.high,
          eventType: event.eventType,
          category: event.category,
          timestamp: DateTime.now(),
        );

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
