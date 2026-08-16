// The morning message is gated by the operator's own event flags, and the job
// records which flag decided.
//
// The failure this guards against is the opposite of a missing notification: a
// pipeline that notices the gate is closed and reroutes through an ungated
// event family so the message arrives anyway. That silently overrides a switch
// the operator set, and the report would still say the message was sent.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';
import 'package:nightshade_core/src/services/notification_service.dart';

DawnJobReport _report() => DawnJobReport(
  jobId: 1,
  kind: 'dawn',
  sessionId: 7,
  startedAt: DateTime.utc(2026, 8, 16, 4),
  finishedAt: DateTime.utc(2026, 8, 16, 5),
  state: 'done',
  masters: const [],
  withoutFile: const [],
  delivery: null,
  deliveryProblems: const [],
  notification: null,
  failure: null,
);

/// A notifier over a service whose webhook posts are counted.
({NotificationServiceDawnNotifier notifier, int Function() posts}) _build(
  AppSettingsState? settings,
) {
  var posts = 0;
  final service = NotificationService.testing(
    settingsReader: () => settings,
    httpClient: MockClient((_) async {
      posts++;
      return http.Response('ok', 200);
    }),
    soundPlayer: () async {},
  );
  addTearDown(service.dispose);
  return (
    notifier: NotificationServiceDawnNotifier(
      notifications: service,
      settings: () => settings,
    ),
    posts: () => posts,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the master notifications switch silences the morning message',
    () async {
      final built = _build(
        const AppSettingsState(
          notificationsEnabled: false,
          notifyOnSequenceComplete: true,
        ),
      );
      final decision = await built.notifier.announce(_report());

      expect(decision.sent, isFalse);
      expect(decision.reason, contains('switched off in Settings'));
      expect(built.posts(), 0);
    },
  );

  test(
    'the Sequence Complete flag silences the morning message and is named',
    () async {
      final built = _build(
        const AppSettingsState(
          notificationsEnabled: true,
          notifyOnSequenceComplete: false,
        ),
      );
      final decision = await built.notifier.announce(_report());

      expect(decision.sent, isFalse);
      expect(decision.reason, contains('"Sequence Complete"'));
      expect(built.posts(), 0);
    },
  );

  test(
    'settings that have not loaded stop the message rather than guessing',
    () async {
      final built = _build(null);
      final decision = await built.notifier.announce(_report());

      expect(decision.sent, isFalse);
      expect(decision.reason, contains('have not loaded'));
      expect(built.posts(), 0);
    },
  );

  test('an open gate dispatches the message through the router', () async {
    final built = _build(
      const AppSettingsState(
        notificationsEnabled: true,
        notifyOnSequenceComplete: true,
        soundEnabled: false,
        discordWebhook: 'https://discord.com/api/webhooks/test',
      ),
    );
    final decision = await built.notifier.announce(_report());

    expect(decision.sent, isTrue);
    expect(decision.reason, contains('notification router'));
    expect(built.posts(), greaterThan(0));
  });

  test(
    'a dispatch no webhook accepted says so instead of claiming delivery',
    () async {
      final built = _build(
        const AppSettingsState(
          notificationsEnabled: true,
          notifyOnSequenceComplete: true,
          soundEnabled: false,
        ),
      );
      final decision = await built.notifier.announce(_report());

      expect(decision.sent, isTrue);
      expect(decision.reason, contains('no Discord or Pushover webhook'));
      expect(built.posts(), 0);
    },
  );
}
