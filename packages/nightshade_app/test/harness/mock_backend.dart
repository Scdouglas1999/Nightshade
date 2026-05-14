// MockBackend for nightshade_app widget tests.
//
// Why mocktail's `Mock` rather than a hand-rolled implements stub:
// `NightshadeBackend` is ~700 LoC of abstract method declarations. Restating
// every one of them just to throw `UnimplementedError` would (a) double the
// maintenance cost every time the interface grows and (b) be functionally
// indistinguishable from the noSuchMethod-based default mocktail gives us.
// Tests stub the specific methods they care about via `when(() => ...)` and
// rely on the default null/empty returns for the rest. Test authors who need
// loud failures on unmocked calls can wrap MockBackend in their own
// strict-mode subclass — the harness should not impose that policy.
//
// Why NOT delegate to `FakeNativeBridge` (the sibling agent's work):
// `FakeNativeBridge` lives at the FFI boundary one layer below `FfiBackend`.
// A test that wants to exercise the `NightshadeBackend` contract directly
// (e.g. `dashboardScreen` reading `backend.discoverDevices(...)`) needs a
// fake at the backend layer, not the bridge layer. After CQ-W5-FAKE-BRIDGE
// lands, an `FfiBackend(bridge: FakeNativeBridge(...))` construction will
// also be available as a higher-fidelity alternative, but the cheap
// MockBackend remains useful for tests that only need a couple of stubs.
//
// See: docs/code-quality/audit-tests.md §6.

import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';

/// A mocktail-based [NightshadeBackend] stand-in for widget tests.
///
/// Returns null/empty/zero for any method that wasn't explicitly stubbed.
/// Use [stubDefaults] (or [mockBackend]) to wire up the streams `eventStream`
/// and `polarAlignmentEvents` — those are read by the framework code path
/// before the widget tree even renders, so leaving them un-stubbed throws.
class MockBackend extends Mock implements NightshadeBackend {}

/// Build a [MockBackend] with the minimum stubs every widget test needs:
///
/// - `eventStream` -> empty broadcast stream (so `listen` returns immediately
///   without throwing; tests can override with their own controller).
/// - `polarAlignmentEvents` -> empty broadcast stream.
/// - `dispose` -> no-op (called when the harness tears down).
///
/// Tests that need richer behaviour can chain additional `when(...)` calls
/// on the returned mock:
///
/// ```dart
/// final backend = mockBackend();
/// when(() => backend.getConnectedDevices()).thenAnswer(
///   (_) async => [DeviceInfo(id: 'cam-1', ...)],
/// );
/// ```
MockBackend mockBackend() {
  final backend = MockBackend();
  // Why broadcast: the production backends expose broadcast streams and
  // several widgets subscribe more than once (e.g. a controller + a status
  // chip). A single-subscription stream would throw on the second listen.
  final eventController = StreamController<NightshadeEvent>.broadcast();
  final polarAlignController =
      StreamController<Map<String, dynamic>>.broadcast();

  when(() => backend.eventStream).thenAnswer((_) => eventController.stream);
  when(() => backend.polarAlignmentEvents)
      .thenAnswer((_) => polarAlignController.stream);
  // dispose() returns void; mocktail won't auto-stub void getters/setters but
  // void methods are fine. Still, set up explicitly so `verify(() => ...)`
  // works for tests that want to assert disposal.
  when(() => backend.dispose()).thenAnswer((_) {
    eventController.close();
    polarAlignController.close();
  });

  return backend;
}
