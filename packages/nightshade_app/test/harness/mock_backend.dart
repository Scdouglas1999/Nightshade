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
///
/// Tests that need to drive backend events post-pump use [emitEvent] /
/// [emitPolarAlignmentEvent]. Those forward to internal broadcast controllers
/// that the harness wires into the mocked stream getters; widgets listening
/// to `backend.eventStream` will see whatever the test pushes here.
class MockBackend extends Mock implements NightshadeBackend {
  // Why nullable + late-bound: the controllers are owned by [mockBackend]
  // (the factory), not the constructor — mocktail's `Mock` requires a
  // zero-arg constructor and adding a constructor argument here would
  // require every existing test that does `class MyMock extends MockBackend`
  // to forward it. The factory assigns these immediately after
  // construction; calls to [emitEvent] before that point throw a clear
  // StateError instead of producing silent no-ops.
  StreamController<NightshadeEvent>? _eventController;
  StreamController<Map<String, dynamic>>? _polarAlignController;

  /// Push a [NightshadeEvent] onto the mocked `eventStream`.
  ///
  /// Throws [StateError] if the backend was constructed directly rather than
  /// via [mockBackend] — without the factory's wiring there is no controller
  /// to push to and silently no-op'ing would hide bugs.
  void emitEvent(NightshadeEvent event) {
    final c = _eventController;
    if (c == null) {
      throw StateError(
        'MockBackend.emitEvent called before the event controller was wired. '
        'Construct via mockBackend() instead of `MockBackend()` directly.',
      );
    }
    c.add(event);
  }

  /// Push a polar-alignment data frame onto `polarAlignmentEvents`.
  ///
  /// Same wiring contract as [emitEvent]; see that doc comment.
  void emitPolarAlignmentEvent(Map<String, dynamic> event) {
    final c = _polarAlignController;
    if (c == null) {
      throw StateError(
        'MockBackend.emitPolarAlignmentEvent called before the controller '
        'was wired. Construct via mockBackend() instead of `MockBackend()` '
        'directly.',
      );
    }
    c.add(event);
  }
}

/// Build a [MockBackend] with the minimum stubs every widget test needs:
///
/// - `eventStream` -> broadcast stream backed by an internal controller that
///   [MockBackend.emitEvent] forwards to.
/// - `polarAlignmentEvents` -> broadcast stream backed by an internal
///   controller that [MockBackend.emitPolarAlignmentEvent] forwards to.
/// - `dispose` -> closes both controllers (called when the harness tears
///   down).
///
/// Tests that need richer behaviour can chain additional `when(...)` calls
/// on the returned mock:
///
/// ```dart
/// final backend = mockBackend();
/// when(() => backend.getConnectedDevices()).thenAnswer(
///   (_) async => [DeviceInfo(id: 'cam-1', ...)],
/// );
/// // Later, drive an event onto the stream:
/// backend.emitEvent(NightshadeEvent(
///   timestamp: 0,
///   severity: EventSeverity.error,
///   category: EventCategory.equipment,
///   eventType: 'camera_fault',
///   data: const {'message': 'shutter stuck'},
/// ));
/// ```
MockBackend mockBackend() {
  final backend = MockBackend();
  // Why broadcast: the production backends expose broadcast streams and
  // several widgets subscribe more than once (e.g. a controller + a status
  // chip). A single-subscription stream would throw on the second listen.
  final eventController = StreamController<NightshadeEvent>.broadcast();
  final polarAlignController =
      StreamController<Map<String, dynamic>>.broadcast();
  // Why assign-then-stub: tests call backend.emitEvent(...) directly via
  // the instance, and stream listeners read the same controllers' .stream
  // through the mocked getters. Keeping both pointed at the same controller
  // is what makes the round-trip work.
  backend._eventController = eventController;
  backend._polarAlignController = polarAlignController;

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
