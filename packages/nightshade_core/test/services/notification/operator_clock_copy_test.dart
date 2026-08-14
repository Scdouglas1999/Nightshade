// WF-STOP-N5 — operator copy still carried a machine token.
//
// The stop toast read
//
//   Sequence stopped by request at 2026-08-14T00:13:25.206940.
//
// A raw ISO-8601 microsecond timestamp is a wire format, not something an
// operator reads off a toast at 2am. Every built-in notification body that
// names a time now renders a plain local clock time.
//
// The same change is what makes the WF-N4 collapse possible at all: three
// producers of one Stop rendered three DIFFERENT bodies because each captured
// its own microsecond, so no content key could ever have matched.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _RecordingTransport extends NotificationTransport {
  final List<({String title, String body})> sent = [];

  @override
  NotificationTransportKind get kind => NotificationTransportKind.inApp;

  @override
  String get name => 'Recording';

  @override
  bool get isConfigured => true;

  @override
  Future<NotificationResult> send({
    required NotificationCategory category,
    required String title,
    required String body,
  }) async {
    sent.add((title: title, body: body));
    return NotificationResult.ok();
  }
}

final _isoTimestamp = RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');

void main() {
  test(
    'the stop notification names a clock time, not an ISO timestamp',
    () async {
      final transport = _RecordingTransport();
      final router = NotificationRouter(
        transports: [transport],
        matrix: const NotificationRoutingMatrix(
          enabled: true,
          rules: {
            NotificationCategory.sequenceStopped: NotificationRoutingRule(
              transports: [NotificationTransportKind.inApp],
            ),
          },
        ),
        clock: () => DateTime(2026, 8, 14, 0, 13, 25, 206, 940),
      );
      addTearDown(router.dispose);

      router.route(NotificationCategory.sequenceStopped, const {});
      await Future<void>.delayed(Duration.zero);

      expect(transport.sent, hasLength(1));
      expect(
        transport.sent.single.body,
        'Sequence stopped by request at 00:13.',
      );
      expect(transport.sent.single.body, isNot(matches(_isoTimestamp)));
    },
  );

  test('no built-in notification body renders a raw ISO timestamp', () async {
    // Every category with a time-bearing default template, not just the stop.
    for (final category in NotificationCategory.values) {
      final transport = _RecordingTransport();
      final router = NotificationRouter(
        transports: [transport],
        matrix: NotificationRoutingMatrix(
          enabled: true,
          rules: {
            category: const NotificationRoutingRule(
              transports: [NotificationTransportKind.inApp],
            ),
          },
        ),
        clock: () => DateTime(2026, 8, 14, 0, 13, 25, 206, 940),
      );
      addTearDown(router.dispose);

      router.route(category, const {});
      await Future<void>.delayed(Duration.zero);

      expect(transport.sent, hasLength(1), reason: category.name);
      expect(
        transport.sent.single.body,
        isNot(matches(_isoTimestamp)),
        reason: '${category.name} body leaks a machine timestamp',
      );
    }
  });

  test(
    r'the catalog variable ${time.local} keeps its documented ISO meaning',
    () {
      // `time.local` is a Rust-canonical catalog variable (its description in
      // `interpolation_catalog.dart` promises ISO-8601 with offset, and the
      // Rust drift test pins the pair). The operator-copy fix must NOT have
      // redefined it — a user template that asks for it still gets ISO.
      final rendered = renderNotificationTemplate(
        r'${time.local}',
        const NotificationContext({}),
      );
      expect(rendered, matches(_isoTimestamp));
    },
  );
}
