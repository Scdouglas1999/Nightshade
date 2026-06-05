// EXACTLY-ONCE CANARY (architecture-unification, Subsystem 3).
//
// This is the guard that must be GREEN before the triple mobile-push feed
// is collapsed onto the single router-authoritative path. It pins, for
// every critical event the unattended-night operator must not miss, that:
//
//   * the event classifies to the expected NotificationCategory (the ONE
//     shared classifier the router and the mobile-push service both use);
//   * driving it through the NotificationRouter produces EXACTLY ONE mobile
//     push on the PushNotificationService stream (via SystemPushTransport)
//     — never zero, never two;
//   * the same event also produces EXACTLY ONE in-app dispatch;
//   * the per-category routing toggle is honoured — disabling the category
//     suppresses both the push and the in-app dispatch;
//   * the master push `enabled` gate suppresses the mobile push.
//
// Why this lives here (core) and not only in the app-package
// critical_events_bridge_test: that test exercises the DASHBOARD-BRIDGE
// producer (bridge-typed events). This one exercises the ROUTER producer
// (core-typed events) — the path the plan makes authoritative. The two
// producers are the two halves of the triple feed; the collapse removes one
// of them, and whichever survives must keep THIS contract.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart';
import 'package:nightshade_core/src/models/notification/notification_categories.dart';
import 'package:nightshade_core/src/services/notification/event_classifier.dart';
import 'package:nightshade_core/src/services/notification/notification_router.dart';
import 'package:nightshade_core/src/services/notification/transports/notification_transport.dart';
import 'package:nightshade_core/src/services/notification/transports/system_push_transport.dart';
import 'package:nightshade_core/src/services/push_notification_service.dart';

/// Records every send so we can count in-app dispatches per event.
class _RecordingTransport extends NotificationTransport {
  @override
  final NotificationTransportKind kind;
  final List<NotificationCategory> sentCategories = [];

  _RecordingTransport(this.kind);

  @override
  String get name => kind.label;

  @override
  bool get isConfigured => true;

  @override
  Future<NotificationResult> send({
    required NotificationCategory category,
    required String title,
    required String body,
  }) async {
    sentCategories.add(category);
    return NotificationResult.ok();
  }
}

NightshadeEvent _evt(
  EventCategory cat,
  String type,
  EventSeverity sev, [
  Map<String, dynamic> data = const {},
]) =>
    NightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: sev,
      category: cat,
      eventType: type,
      data: data,
    );

/// The eight critical canary events, each as a core-typed [NightshadeEvent]
/// paired with the [NotificationCategory] it must classify to.
final _criticalCases = <String, ({NightshadeEvent event, NotificationCategory category})>{
  'sequenceFailed': (
    event: _evt(EventCategory.sequencer, 'Error', EventSeverity.error,
        {'message': 'boom'}),
    category: NotificationCategory.sequenceFailed,
  ),
  'weatherUnsafe': (
    event: _evt(EventCategory.safety, 'WeatherUnsafe', EventSeverity.error,
        {'reason': 'clouds'}),
    category: NotificationCategory.weatherUnsafe,
  ),
  'guidingLost': (
    event: _evt(EventCategory.guiding, 'StarLost', EventSeverity.error),
    category: NotificationCategory.guidingLost,
  ),
  'exposureFailed': (
    event: _evt(EventCategory.imaging, 'ExposureFailed', EventSeverity.error,
        {'error': 'camera timeout'}),
    category: NotificationCategory.exposureFailed,
  ),
  'equipmentDisconnected': (
    event: _evt(EventCategory.equipment, 'Disconnected', EventSeverity.error,
        {'device_type': 'Mount', 'device_id': 'm1'}),
    category: NotificationCategory.equipmentDisconnected,
  ),
  'recoveryGaveUp': (
    event:
        _evt(EventCategory.sequencer, 'RecoveryGaveUp', EventSeverity.critical),
    category: NotificationCategory.recoveryGaveUp,
  ),
  'diskSpaceLow': (
    event: _evt(EventCategory.system, 'DiskSpaceLow', EventSeverity.error),
    category: NotificationCategory.diskSpaceLow,
  ),
  'autofocusFailed': (
    event: _evt(EventCategory.sequencer, 'NodeCompleted', EventSeverity.error,
        {'node_type': 'autofocus', 'success': false}),
    category: NotificationCategory.autofocusFailed,
  ),
};

void main() {
  group('exactly-once classifier contract', () {
    test('every critical canary event classifies to its critical category',
        () {
      for (final entry in _criticalCases.entries) {
        final classified =
            NotificationEventClassifier.classify(entry.value.event);
        expect(classified, isNotNull,
            reason: '${entry.key} must classify to a category');
        expect(classified!.category, entry.value.category,
            reason: '${entry.key} classified to the wrong category');
        expect(classified.category.isCritical, isTrue,
            reason: '${entry.key} must be critical-by-default');
      }
    });
  });

  group('exactly-once router dispatch (mobile push + in-app)', () {
    /// Build a router whose `systemPush` transport feeds a real
    /// PushNotificationService, plus a recording in-app transport. Returns
    /// the router, the push service, and the in-app recorder.
    ({
      NotificationRouter router,
      PushNotificationService push,
      _RecordingTransport inApp,
    }) build({
      bool pushEnabled = true,
      NotificationRoutingMatrix? matrix,
    }) {
      final push = PushNotificationService(
        eventStream: const Stream<NightshadeEvent>.empty(),
        config: PushNotificationConfig(enabled: pushEnabled),
      );
      // We do NOT call push.start(): in this test the router's
      // SystemPushTransport is the only producer, so we can prove the
      // router path fires exactly once with no parallel feed.
      final inApp = _RecordingTransport(NotificationTransportKind.inApp);
      final router = NotificationRouter(
        transports: [inApp, SystemPushTransport(push)],
        matrix: matrix ?? NotificationRoutingMatrix.defaults(),
      );
      return (router: router, push: push, inApp: inApp);
    }

    test('each critical event fires EXACTLY ONE mobile push + ONE in-app',
        () async {
      for (final entry in _criticalCases.entries) {
        final rig = build();
        final pushes = <PushNotification>[];
        final sub = rig.push.notifications.listen(pushes.add);

        rig.router.attachEventStream(Stream.value(entry.value.event));
        // Drain the stream listen + the router's Future.microtask dispatch +
        // the broadcast controller emission.
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(pushes, hasLength(1),
            reason: '${entry.key}: expected exactly one mobile push');
        expect(pushes.first.priority, PushNotificationPriority.critical,
            reason: '${entry.key}: matrix-routed critical push');
        expect(
          rig.inApp.sentCategories.where((c) => c == entry.value.category),
          hasLength(1),
          reason: '${entry.key}: expected exactly one in-app dispatch',
        );

        await sub.cancel();
        await rig.router.dispose();
        rig.push.dispose();
      }
    });

    test('disabling a category suppresses BOTH push and in-app (toggle)',
        () async {
      for (final entry in _criticalCases.entries) {
        final disabledMatrix = NotificationRoutingMatrix.defaults().withRule(
          entry.value.category,
          NotificationRoutingMatrix.defaults()
              .ruleFor(entry.value.category)
              .copyWith(enabled: false),
        );
        final rig = build(matrix: disabledMatrix);
        final pushes = <PushNotification>[];
        final sub = rig.push.notifications.listen(pushes.add);

        rig.router.attachEventStream(Stream.value(entry.value.event));
        await Future<void>.delayed(const Duration(milliseconds: 5));

        expect(pushes, isEmpty,
            reason: '${entry.key}: disabled category must not push');
        expect(rig.inApp.sentCategories, isEmpty,
            reason: '${entry.key}: disabled category must not dispatch in-app');

        await sub.cancel();
        await rig.router.dispose();
        rig.push.dispose();
      }
    });

    test('master push disabled suppresses the mobile push but keeps in-app',
        () async {
      final entry = _criticalCases['weatherUnsafe']!;
      final rig = build(pushEnabled: false);
      final pushes = <PushNotification>[];
      final sub = rig.push.notifications.listen(pushes.add);

      rig.router.attachEventStream(Stream.value(entry.event));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      // The master push `enabled=false` gate swallows the enqueue inside the
      // service, so no phone push — but the in-app transport is independent
      // and still fires.
      expect(pushes, isEmpty);
      expect(
        rig.inApp.sentCategories.where((c) => c == entry.category),
        hasLength(1),
      );

      await sub.cancel();
      await rig.router.dispose();
      rig.push.dispose();
    });
  });

  group('non-critical events do NOT escalate to mobile push by default', () {
    test('a frameCaptured event fires in-app only, never systemPush',
        () async {
      final push = PushNotificationService(
        eventStream: const Stream<NightshadeEvent>.empty(),
        config: const PushNotificationConfig(),
      );
      final inApp = _RecordingTransport(NotificationTransportKind.inApp);
      final router = NotificationRouter(
        transports: [inApp, SystemPushTransport(push)],
        matrix: NotificationRoutingMatrix.defaults(),
      );
      final pushes = <PushNotification>[];
      final sub = push.notifications.listen(pushes.add);

      router.attachEventStream(Stream.value(_evt(
          EventCategory.imaging, 'ExposureCompleted', EventSeverity.info,
          {'frame_number': 3, 'duration_secs': 120})));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(pushes, isEmpty);
      expect(inApp.sentCategories, [NotificationCategory.frameCaptured]);

      await sub.cancel();
      await router.dispose();
      push.dispose();
    });
  });
}
