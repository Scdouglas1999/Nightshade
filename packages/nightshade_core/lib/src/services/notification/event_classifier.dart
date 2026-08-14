// Single source of truth: backend event -> NotificationCategory.
//
// Before this file existed, the same "which NotificationCategory does this
// raw event belong to" logic was hand-written THREE times with subtly
// different coverage:
//
//   * NotificationRouter._categoryForEvent / _classify*Event
//   * PushNotificationService._eventToNotification / _handle*Event
//   * (bridge-typed) run_dashboard isCriticalEvent / _toDashboardEvent
//
// The first two operated on the core [NightshadeEvent] (string `eventType`
// + `data` map). They are unified here as the ONE classifier.
//
// Architecture-unification, Subsystem 3 (collapsed): the mobile-push feed no
// longer classifies at all — [PushNotificationService] is now a pure
// broadcaster and the [NotificationRouter] is the single producer of every
// transport (in-app, mobile push, and the external ones). The router is the
// sole caller of this classifier; the per-category mobile-push toggle now
// lives in [SystemPushTransport] keyed off the SAME category this classifier
// assigns, so a routing rule and a push toggle can never disagree about what
// an event *is*.
//
// The dashboard bridge runs on the freezed bridge-union event (a different
// representation that carries richer typed payloads) and stays in its own
// file; it forwards only the criticals this classifier does NOT route (e.g.
// generic system errors) into the router, and derives criticality from
// [NotificationCategory.isCritical] via the shared matrix so the two never
// drift on *which* events are critical.
//
// This classifier is intentionally pure and side-effect free.

import '../../models/backend/event_types.dart';
import '../../models/notification/notification_categories.dart';

/// The result of classifying a single backend event: the semantic
/// [NotificationCategory], the context key/value pairs the templates need,
/// and the event's [EventSeverity] (carried through unchanged).
class ClassifiedNotification {
  final NotificationCategory category;

  /// Extra, classifier-derived context values (e.g. `target.name`). These
  /// win over the raw scalar fields the router folds in from `event.data`.
  final Map<String, String> context;

  /// The severity of the originating event, carried through verbatim so
  /// the router's min-severity gate and the push priority both see the
  /// same value the backend assigned.
  final EventSeverity severity;

  const ClassifiedNotification({
    required this.category,
    required this.context,
    required this.severity,
  });
}

/// Maps a core [NightshadeEvent] to its [NotificationCategory] (+ context),
/// or `null` when the event is not one the cross-platform notification
/// system surfaces (those events are consumed by dedicated UI surfaces).
///
/// This is the ONE classifier both [NotificationRouter] and
/// [PushNotificationService] call.
class NotificationEventClassifier {
  const NotificationEventClassifier._();

  /// Classify [event]. Returns `null` for events that do not map to a
  /// routed category.
  static ClassifiedNotification? classify(NightshadeEvent event) {
    final mapped = _categoryAndContext(event);
    if (mapped == null) return null;
    return ClassifiedNotification(
      category: mapped.$1,
      context: mapped.$2,
      severity: event.severity,
    );
  }

  static (NotificationCategory, Map<String, String>)? _categoryAndContext(
    NightshadeEvent event,
  ) {
    switch (event.category) {
      case EventCategory.sequencer:
        return _classifySequencer(event);
      case EventCategory.imaging:
        return _classifyImaging(event);
      case EventCategory.guiding:
        return _classifyGuiding(event);
      case EventCategory.safety:
        return (
          event.eventType.toLowerCase().contains('safe') &&
                  !event.eventType.toLowerCase().contains('unsafe')
              ? NotificationCategory.weatherSafeAgain
              : NotificationCategory.weatherUnsafe,
          <String, String>{},
        );
      case EventCategory.equipment:
        return _classifyEquipment(event);
      case EventCategory.system:
        return _classifySystem(event);
      case EventCategory.polarAlignment:
      case EventCategory.job:
      case EventCategory.session:
      case EventCategory.catalog:
        // Consumed via dedicated UI surfaces (job progress toast,
        // session-ownership banner, Catalog management panel); not routed
        // through the cross-platform notification system.
        return null;
    }
  }

  static (NotificationCategory, Map<String, String>)? _classifySequencer(
    NightshadeEvent event,
  ) {
    switch (event.eventType) {
      case 'Started':
        return (NotificationCategory.sequenceStarted, <String, String>{});
      case 'Completed':
        return (NotificationCategory.sequenceCompleted, <String, String>{});
      case 'Stopped':
        return (NotificationCategory.sequenceStopped, <String, String>{});
      case 'Error':
        return (NotificationCategory.sequenceFailed, <String, String>{});
      case 'Paused':
        return (NotificationCategory.sequencePaused, <String, String>{});
      case 'Resumed':
        return (NotificationCategory.sequenceResumed, <String, String>{});
      case 'TargetStarted':
        return (
          NotificationCategory.targetStarted,
          <String, String>{
            'target.name': (event.data['target_name'] as String?) ?? '',
            'target.id': (event.data['target_id'] as String?) ?? '',
          },
        );
      case 'TargetCompleted':
        return (
          NotificationCategory.targetCompleted,
          <String, String>{
            'target.name': (event.data['target_name'] as String?) ?? '',
            'target.id': (event.data['target_id'] as String?) ?? '',
          },
        );
      case 'NodeCompleted':
        // The verdict is `status` — a string ('success' / 'failed' /
        // 'cancelled' / 'skipped'), see `SequencerEvent.nodeCompleted`. This
        // read a `success` BOOL that no producer emits and defaulted it to
        // TRUE, so had this branch ever fired for a failed autofocus it would
        // have pushed "Autofocus Completed" to the operator's phone — the worst
        // possible direction for an alert you are asleep for. Anything that is
        // not an explicit success is treated as a failure here; an absent
        // status is not evidence of success.
        final nodeType = (event.data['node_type'] as String? ?? '')
            .toLowerCase();
        if (nodeType.isEmpty) {
          // `NodeCompleted` carries only `node_id` + `status` on the wire (see
          // `ffi_backend/event_mapping.dart`), so this branch is inert today
          // and no autofocus-specific notification is raised from it. A failed
          // autofocus still reaches the operator: the instruction failure is
          // emitted separately as a sequencer `Error`, which classifies
          // critical below. Populating `node_type` on the event (producer-side)
          // is all that is needed to light this up.
          return null;
        }
        final status = event.data['status'] as String?;
        final succeeded =
            status == 'success' ||
            // Legacy bool from an older producer.
            (status == null && event.data['success'] == true);
        if (nodeType.contains('autofocus')) {
          return (
            succeeded
                ? NotificationCategory.autofocusCompleted
                : NotificationCategory.autofocusFailed,
            <String, String>{},
          );
        }
        return null;
      case 'InstructionProgress':
        final instr = (event.data['instruction'] as String? ?? '')
            .toLowerCase();
        if (instr.contains('meridian')) {
          return (
            NotificationCategory.meridianFlipPerformed,
            <String, String>{},
          );
        }
        return null;
      case 'TriggerFired':
        return (
          NotificationCategory.triggerFired,
          <String, String>{
            'trigger.name': (event.data['trigger_name'] as String?) ?? '',
          },
        );
      case 'RecoveryStarted':
        return (NotificationCategory.recoveryStarted, <String, String>{});
      case 'RecoveryRecovered':
        return (NotificationCategory.recoveryRecovered, <String, String>{});
      case 'RecoveryGaveUp':
        return (NotificationCategory.recoveryGaveUp, <String, String>{});
      case 'FrameRejected':
        return (
          NotificationCategory.frameRejected,
          <String, String>{
            'frame.reason': (event.data['reason'] as String?) ?? '',
          },
        );
    }
    return null;
  }

  static (NotificationCategory, Map<String, String>)? _classifyImaging(
    NightshadeEvent event,
  ) {
    switch (event.eventType) {
      case 'ExposureCompleted':
        return (
          NotificationCategory.frameCaptured,
          <String, String>{
            'frame': '${event.data['frame_number'] ?? ''}',
            'exposure.duration': '${event.data['duration_secs'] ?? ''}',
          },
        );
      case 'ExposureFailed':
        return (
          NotificationCategory.exposureFailed,
          <String, String>{
            'frame.reason':
                (event.data['error'] as String?) ??
                (event.data['reason'] as String?) ??
                '',
          },
        );
    }
    return null;
  }

  static (NotificationCategory, Map<String, String>)? _classifyGuiding(
    NightshadeEvent event,
  ) {
    switch (event.eventType) {
      case 'StarLost':
      case 'Disconnected':
        return (NotificationCategory.guidingLost, <String, String>{});
      case 'StarRecovered':
      case 'Reconnected':
        return (NotificationCategory.guidingRecovered, <String, String>{});
    }
    return null;
  }

  static (NotificationCategory, Map<String, String>)? _classifyEquipment(
    NightshadeEvent event,
  ) {
    if (event.eventType == 'Disconnected' || event.eventType == 'Error') {
      return (
        NotificationCategory.equipmentDisconnected,
        <String, String>{
          'equipment.device_type': (event.data['device_type'] as String?) ?? '',
          'equipment.device_id': (event.data['device_id'] as String?) ?? '',
        },
      );
    }
    return null;
  }

  static (NotificationCategory, Map<String, String>)? _classifySystem(
    NightshadeEvent event,
  ) {
    if (event.eventType.toLowerCase().contains('disk')) {
      return (NotificationCategory.diskSpaceLow, <String, String>{});
    }
    return null;
  }
}
