import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart';
import 'package:nightshade_core/src/models/notification/notification_categories.dart';
import 'package:nightshade_core/src/services/notification/notification_router.dart';
import 'package:nightshade_core/src/services/notification/transports/notification_transport.dart';

/// In-memory transport that records every send call. Used by all the
/// router tests; never touches the network.
class _RecordingTransport extends NotificationTransport {
  @override
  final NotificationTransportKind kind;
  final List<_SentMessage> sent = [];
  bool configured;
  bool failNext;

  _RecordingTransport(this.kind, {this.configured = true, this.failNext = false});

  @override
  String get name => kind.label;

  @override
  bool get isConfigured => configured;

  @override
  Future<NotificationResult> send({
    required NotificationCategory category,
    required String title,
    required String body,
  }) async {
    sent.add(_SentMessage(category: category, title: title, body: body));
    if (failNext) {
      failNext = false;
      return NotificationResult.fail('synthetic failure');
    }
    return NotificationResult.ok();
  }
}

class _SentMessage {
  final NotificationCategory category;
  final String title;
  final String body;
  _SentMessage({required this.category, required this.title, required this.body});
}

NightshadeEvent _evt({
  required EventCategory cat,
  required String type,
  EventSeverity severity = EventSeverity.info,
  Map<String, dynamic> data = const {},
}) =>
    NightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: severity,
      category: cat,
      eventType: type,
      data: data,
    );

void main() {
  test('matrix disabled drops every event', () async {
    final t = _RecordingTransport(NotificationTransportKind.pushover);
    final router = NotificationRouter(
      transports: [t],
      matrix: const NotificationRoutingMatrix(enabled: false),
    );
    router.route(NotificationCategory.sequenceCompleted, const {},
        severity: EventSeverity.info);
    await Future<void>.delayed(Duration.zero);
    expect(t.sent, isEmpty);
    await router.dispose();
  });

  test('routes to every transport listed in the rule', () async {
    final pushover = _RecordingTransport(NotificationTransportKind.pushover);
    final discord = _RecordingTransport(NotificationTransportKind.discord);
    final telegram = _RecordingTransport(NotificationTransportKind.telegram);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.targetCompleted,
      const NotificationRoutingRule(transports: [
        NotificationTransportKind.pushover,
        NotificationTransportKind.discord,
      ]),
    );
    final router = NotificationRouter(
      transports: [pushover, discord, telegram],
      matrix: matrix,
    );
    router.route(NotificationCategory.targetCompleted, const {'target.name': 'NGC 7000'});
    await Future<void>.delayed(Duration.zero);
    expect(pushover.sent.length, 1);
    expect(discord.sent.length, 1);
    expect(telegram.sent, isEmpty);
    expect(pushover.sent.first.body, contains('NGC 7000'));
    await router.dispose();
  });

  test('respects minSeverity', () async {
    final t = _RecordingTransport(NotificationTransportKind.discord);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.targetCompleted,
      const NotificationRoutingRule(
        transports: [NotificationTransportKind.discord],
        minSeverity: EventSeverity.warning,
      ),
    );
    final router = NotificationRouter(transports: [t], matrix: matrix);
    router.route(NotificationCategory.targetCompleted, const {},
        severity: EventSeverity.info);
    await Future<void>.delayed(Duration.zero);
    expect(t.sent, isEmpty);

    router.route(NotificationCategory.targetCompleted, const {},
        severity: EventSeverity.warning);
    await Future<void>.delayed(Duration.zero);
    expect(t.sent.length, 1);
    await router.dispose();
  });

  test('debounce blocks repeated fires inside the window', () async {
    final t = _RecordingTransport(NotificationTransportKind.discord);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.frameCaptured,
      const NotificationRoutingRule(
        transports: [NotificationTransportKind.discord],
        debounceSeconds: 60,
      ),
    );
    final router = NotificationRouter(transports: [t], matrix: matrix);
    router.route(NotificationCategory.frameCaptured, const {});
    router.route(NotificationCategory.frameCaptured, const {});
    router.route(NotificationCategory.frameCaptured, const {});
    await Future<void>.delayed(Duration.zero);
    expect(t.sent.length, 1);
    await router.dispose();
  });

  test('rate limit caps fires per window', () async {
    final t = _RecordingTransport(NotificationTransportKind.discord);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.frameCaptured,
      const NotificationRoutingRule(
        transports: [NotificationTransportKind.discord],
        maxPerHour: 2,
      ),
    );
    final router = NotificationRouter(transports: [t], matrix: matrix);
    for (var i = 0; i < 5; i++) {
      router.route(NotificationCategory.frameCaptured, const {});
    }
    await Future<void>.delayed(Duration.zero);
    expect(t.sent.length, 2);
    await router.dispose();
  });

  test('templates interpolate context', () async {
    final t = _RecordingTransport(NotificationTransportKind.discord);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.targetCompleted,
      const NotificationRoutingRule(
        transports: [NotificationTransportKind.discord],
        titleTemplate: r'Done: ${target.name}',
        bodyTemplate: r'Finished ${target.name} (id=${target.id})',
      ),
    );
    final router = NotificationRouter(transports: [t], matrix: matrix);
    router.route(NotificationCategory.targetCompleted,
        const {'target.name': 'M31', 'target.id': 'abc'});
    await Future<void>.delayed(Duration.zero);
    expect(t.sent.first.title, 'Done: M31');
    expect(t.sent.first.body, 'Finished M31 (id=abc)');
    await router.dispose();
  });

  test('skips transports that are not configured', () async {
    final ready = _RecordingTransport(NotificationTransportKind.discord);
    final pending = _RecordingTransport(NotificationTransportKind.pushover,
        configured: false);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.sequenceCompleted,
      const NotificationRoutingRule(
        transports: [
          NotificationTransportKind.pushover,
          NotificationTransportKind.discord,
        ],
      ),
    );
    final router =
        NotificationRouter(transports: [ready, pending], matrix: matrix);
    router.route(NotificationCategory.sequenceCompleted, const {});
    await Future<void>.delayed(Duration.zero);
    expect(ready.sent.length, 1);
    expect(pending.sent, isEmpty);
    await router.dispose();
  });

  test('event stream → category classification', () async {
    final t = _RecordingTransport(NotificationTransportKind.discord);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.targetCompleted,
      const NotificationRoutingRule(
          transports: [NotificationTransportKind.discord]),
    );
    final router = NotificationRouter(transports: [t], matrix: matrix);
    final controller = StreamController<NightshadeEvent>();
    router.attachEventStream(controller.stream);

    controller.add(_evt(
      cat: EventCategory.sequencer,
      type: 'TargetCompleted',
      data: const {'target_name': 'NGC 281'},
    ));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(t.sent.length, 1);
    expect(t.sent.first.category, NotificationCategory.targetCompleted);
    expect(t.sent.first.body, contains('NGC 281'));

    await controller.close();
    await router.dispose();
  });

  test('sequence-level override beats global matrix', () async {
    final global = _RecordingTransport(NotificationTransportKind.discord);
    final perSeq = _RecordingTransport(NotificationTransportKind.telegram);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.targetCompleted,
      const NotificationRoutingRule(
          transports: [NotificationTransportKind.discord]),
    );
    final router = NotificationRouter(
      transports: [global, perSeq],
      matrix: matrix,
    );
    router.setActiveSequence('public-observatory');
    router.setSequenceOverrides('public-observatory', {
      NotificationCategory.targetCompleted:
          const NotificationRoutingRule(transports: [
        NotificationTransportKind.telegram,
      ]),
    });
    router.route(NotificationCategory.targetCompleted, const {});
    await Future<void>.delayed(Duration.zero);
    expect(global.sent, isEmpty);
    expect(perSeq.sent.length, 1);
    await router.dispose();
  });

  test('sendTest returns transport result and records it', () async {
    final t = _RecordingTransport(NotificationTransportKind.pushover);
    final router = NotificationRouter(transports: [t]);
    final res =
        await router.sendTest(NotificationTransportKind.pushover);
    expect(res.success, isTrue);
    expect(t.sent.length, 1);
    expect(router.lastResults[NotificationTransportKind.pushover]?.success,
        isTrue);
    await router.dispose();
  });

  test('sendTest surfaces transport failure', () async {
    final t = _RecordingTransport(NotificationTransportKind.pushover,
        failNext: true);
    final router = NotificationRouter(transports: [t]);
    final res =
        await router.sendTest(NotificationTransportKind.pushover);
    expect(res.success, isFalse);
    expect(res.error, contains('synthetic'));
    await router.dispose();
  });

  test('routeNotificationNode honours explicit transports', () async {
    final tA = _RecordingTransport(NotificationTransportKind.discord);
    final tB = _RecordingTransport(NotificationTransportKind.telegram);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.custom,
      const NotificationRoutingRule(
          transports: [NotificationTransportKind.discord]),
    );
    final router = NotificationRouter(transports: [tA, tB], matrix: matrix);
    router.routeNotificationNode(
      title: 'Custom T',
      body: 'Custom B',
      explicitTransports: const [NotificationTransportKind.telegram],
    );
    await Future<void>.delayed(Duration.zero);
    expect(tA.sent, isEmpty);
    expect(tB.sent.length, 1);
    expect(tB.sent.first.body, 'Custom B');
    await router.dispose();
  });

  test(
      'sequencer Notification event with explicit_transports overrides matrix',
      () async {
    final discord = _RecordingTransport(NotificationTransportKind.discord);
    final telegram = _RecordingTransport(NotificationTransportKind.telegram);
    // Matrix says custom → discord, but the event carries
    // explicit_transports: [telegram] so the router must send via
    // telegram only.
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.custom,
      const NotificationRoutingRule(
          transports: [NotificationTransportKind.discord]),
    );
    final router =
        NotificationRouter(transports: [discord, telegram], matrix: matrix);
    final ctrl = StreamController<NightshadeEvent>();
    router.attachEventStream(ctrl.stream);

    ctrl.add(_evt(
      cat: EventCategory.sequencer,
      type: 'Notification',
      data: {
        'title': 'Custom T',
        'message': 'Custom B',
        'explicit_transports': ['telegram'],
      },
    ));
    await Future<void>.delayed(Duration.zero);
    expect(discord.sent, isEmpty);
    expect(telegram.sent.length, 1);
    expect(telegram.sent.first.title, 'Custom T');
    expect(telegram.sent.first.body, 'Custom B');

    await ctrl.close();
    await router.dispose();
  });

  test('sequencer Notification event with no explicit_transports uses matrix',
      () async {
    final discord = _RecordingTransport(NotificationTransportKind.discord);
    final telegram = _RecordingTransport(NotificationTransportKind.telegram);
    final matrix = NotificationRoutingMatrix.defaults().withRule(
      NotificationCategory.custom,
      const NotificationRoutingRule(
          transports: [NotificationTransportKind.discord]),
    );
    final router =
        NotificationRouter(transports: [discord, telegram], matrix: matrix);
    final ctrl = StreamController<NightshadeEvent>();
    router.attachEventStream(ctrl.stream);

    ctrl.add(_evt(
      cat: EventCategory.sequencer,
      type: 'Notification',
      data: {
        'title': 'T',
        'message': 'B',
      },
    ));
    await Future<void>.delayed(Duration.zero);
    expect(discord.sent.length, 1);
    expect(telegram.sent, isEmpty);

    await ctrl.close();
    await router.dispose();
  });

  test('updateMatrix swaps the live routing in-place', () async {
    final t = _RecordingTransport(NotificationTransportKind.discord);
    final router = NotificationRouter(transports: [t]);
    router.route(NotificationCategory.targetCompleted, const {});
    await Future<void>.delayed(Duration.zero);
    final initialCount = t.sent.length;
    router.updateMatrix(NotificationRoutingMatrix.defaults().copyWith(
      enabled: false,
    ));
    router.route(NotificationCategory.targetCompleted, const {});
    await Future<void>.delayed(Duration.zero);
    expect(t.sent.length, initialCount);
    await router.dispose();
  });
}
