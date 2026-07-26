// Regression: losing the host must not be terminal.
//
// Observed live on an Android 15 emulator paired to a headless host at
// 192.168.1.20:8080. Airplane mode was enabled; after the 30 s grace period the
// app correctly tore the session down and showed "Connection to server lost.
// Please reconnect." Airplane mode was then disabled — and 4 minutes later the
// app was STILL sitting on that screen. Nothing was retrying: the grace timer's
// callback was the end of the line. A cold start reconnected instantly from the
// same saved server and token, proving the credentials were never the problem.
//
// The fix re-arms the same `_autoConnect()` entry point a cold start uses, on
// the backoff pinned below. These cases lock the schedule's shape: it must ramp
// (so a blip recovers in seconds), it must cap (so it never busy-polls), and it
// must never terminate (so an overnight outage still re-attaches).
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_mobile/main.dart';

void main() {
  group('lostSessionRetryDelay', () {
    test('ramps 5s, 10s, 20s, 30s so a short blip recovers quickly', () {
      expect(lostSessionRetryDelay(0), const Duration(seconds: 5));
      expect(lostSessionRetryDelay(1), const Duration(seconds: 10));
      expect(lostSessionRetryDelay(2), const Duration(seconds: 20));
      expect(lostSessionRetryDelay(3), const Duration(seconds: 30));
    });

    test('caps at 30s instead of backing off toward never', () {
      for (final attempt in [4, 10, 100, 100000]) {
        expect(
          lostSessionRetryDelay(attempt),
          const Duration(seconds: 30),
          reason:
              'attempt $attempt must still be scheduled 30s out — an app that '
              'stops watching the run is the bug this replaced',
        );
      }
    });

    test('never yields a zero or negative delay (no busy-retry loop)', () {
      for (var attempt = 0; attempt < 50; attempt++) {
        expect(
          lostSessionRetryDelay(attempt) > Duration.zero,
          isTrue,
          reason: 'attempt $attempt scheduled a non-positive delay',
        );
      }
    });

    test('is monotonically non-decreasing', () {
      var previous = lostSessionRetryDelay(0);
      for (var attempt = 1; attempt < 20; attempt++) {
        final current = lostSessionRetryDelay(attempt);
        expect(
          current >= previous,
          isTrue,
          reason: 'backoff went backwards at attempt $attempt',
        );
        previous = current;
      }
    });

    test('a defensive negative attempt still schedules a real retry', () {
      expect(lostSessionRetryDelay(-1), const Duration(seconds: 5));
    });
  });
}
