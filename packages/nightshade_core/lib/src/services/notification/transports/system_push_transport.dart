// System (mobile) push transport.
//
// Wraps the existing PushNotificationService so the routing matrix can
// fire mobile-push for any category. The legacy service has its own
// enqueue path for events the bridge doesn't classify as critical; we
// reuse that path so paired phones see notifications via the same
// WebSocket broadcast they already listen to.

import '../../../models/backend/event_types.dart' as core;
import '../../../models/notification/notification_categories.dart';
import '../../push_notification_service.dart';
import 'notification_transport.dart';

class SystemPushTransport extends NotificationTransport {
  final PushNotificationService _service;

  SystemPushTransport(this._service);

  @override
  NotificationTransportKind get kind => NotificationTransportKind.systemPush;

  @override
  String get name => 'Mobile push';

  /// Always configured: the legacy push service is part of the runtime.
  /// If the user disabled push entirely the legacy service's enabled
  /// flag swallows the enqueue call, so we still claim configured to
  /// avoid greying out the test-send button when the user simply hasn't
  /// reopened settings yet.
  @override
  bool get isConfigured => true;

  @override
  Future<NotificationResult> send({
    required NotificationCategory category,
    required String title,
    required String body,
  }) async {
    final eventCategory = _mapCategory(category);
    _service.enqueueCriticalNotification(
      title: title,
      body: body,
      eventType: category.storageKey,
      category: eventCategory,
    );
    return NotificationResult.ok();
  }

  core.EventCategory _mapCategory(NotificationCategory category) {
    switch (category) {
      case NotificationCategory.sequenceStarted:
      case NotificationCategory.sequenceCompleted:
      case NotificationCategory.sequenceFailed:
      case NotificationCategory.sequencePaused:
      case NotificationCategory.sequenceResumed:
      case NotificationCategory.targetStarted:
      case NotificationCategory.targetCompleted:
      case NotificationCategory.meridianFlipPerformed:
      case NotificationCategory.autofocusCompleted:
      case NotificationCategory.autofocusFailed:
      case NotificationCategory.frameCaptured:
      case NotificationCategory.frameRejected:
      case NotificationCategory.recoveryStarted:
      case NotificationCategory.recoveryRecovered:
      case NotificationCategory.recoveryGaveUp:
      case NotificationCategory.triggerFired:
        return core.EventCategory.sequencer;
      case NotificationCategory.exposureFailed:
        return core.EventCategory.imaging;
      case NotificationCategory.guidingLost:
      case NotificationCategory.guidingRecovered:
        return core.EventCategory.guiding;
      case NotificationCategory.weatherUnsafe:
      case NotificationCategory.weatherSafeAgain:
      case NotificationCategory.cloudArriving:
      case NotificationCategory.cloudOpening:
        return core.EventCategory.safety;
      case NotificationCategory.equipmentDisconnected:
        return core.EventCategory.equipment;
      case NotificationCategory.diskSpaceLow:
      case NotificationCategory.custom:
        return core.EventCategory.system;
    }
  }
}
