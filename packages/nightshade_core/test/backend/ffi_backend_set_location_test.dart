// Regression guard for `FfiBackend.setLocation` honoring its `Future<void>`
// contract.
//
// The bug this pins: `setLocation` invoked `apiSetLocation(...)` WITHOUT
// awaiting it, so the returned `Future<void>` completed before the native
// write resolved. A failed observer-location write surfaced only as a dropped,
// unhandled async error — never to the caller — and an await-then-read pair
// could observe stale state.
//
// These tests drive the REAL `FfiBackend` (NOT a mock backend), so the seam
// cannot silently regress. In the no-native test runtime the bridge's
// `apiSetLocation` rejects (the native library is required and absent). The
// fixed, awaited `setLocation` therefore propagates that rejection out of
// `await backend.setLocation(...)`. Under the old dropped-Future code the same
// call completed normally and the rejection vanished — so this test fails
// closed if the `await` is ever removed again.

import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FfiBackend.setLocation await/error-propagation contract', () {
    test(
      'a native write failure propagates out of await setLocation',
      () async {
        final backend = FfiBackend();

        const location = ObserverLocation(
          latitude: 45.5,
          longitude: -122.6,
          elevation: 100.0,
        );

        // The real native write rejects in the no-native runtime. Because
        // `setLocation` now awaits it, the rejection must surface to the caller
        // rather than being swallowed as an unhandled async error.
        await expectLater(
          backend.setLocation(location),
          throwsA(isA<Object>()),
        );
      },
    );

    test('clearing the location (null) also awaits the native write', () async {
      final backend = FfiBackend();

      await expectLater(backend.setLocation(null), throwsA(isA<Object>()));
    });
  });
}
