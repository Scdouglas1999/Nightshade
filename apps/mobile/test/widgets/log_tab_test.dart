// Wave 6D / P2-5 — LogTab clears its event buffer on backend swap.
//
// Before the fix, switching backends (FFI → Network, or reconnecting to
// a different server) left the previously-collected NightshadeEvents in
// the LogTab buffer, so the operator saw events that had nothing to do
// with the rig they were currently controlling.
//
// We exercise the fix by overriding [backendProvider] with two distinct
// fake backends and asserting:
//   1. Events from backend A are visible while A is active.
//   2. After we swap the override to backend B, the buffer is empty
//      until backend B emits its own events.
//
// We can't import the private _LogTabState; instead we assert on the
// visible event rows. The "Waiting for events" empty-state message is
// the canonical signal that the buffer is empty.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_mobile/screens/dashboard/tabs/log_tab.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Minimal NightshadeBackend stub that only exposes the streams LogTab
/// reads. Every other method throws — the LogTab implementation should
/// not call any of them and the test will fail loudly if it does.
class _StubBackend implements NightshadeBackend {
  _StubBackend(this.label);

  final String label;
  final StreamController<NightshadeEvent> _events =
      StreamController<NightshadeEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _polar =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Stream<NightshadeEvent> get eventStream => _events.stream;

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents => _polar.stream;

  @override
  bool get dispatchPluginNodesLocally => false;

  void emit(NightshadeEvent event) => _events.add(event);

  // Part of the NightshadeBackend contract (DiagnosticsBackend.dispose).
  // BackendNotifier calls state.dispose() on provider teardown and
  // oldBackend.dispose() on a backend swap, so a faithful double must
  // implement it. Tests drive the actual stream teardown via close().
  @override
  void dispose() {}

  Future<void> close() async {
    await _events.close();
    await _polar.close();
  }

  // Every other backend method is a fail-loud no-op — LogTab never calls
  // anything except eventStream/polarAlignmentEvents.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'StubBackend($label) caught unexpected ${invocation.memberName}',
    );
  }
}

NightshadeEvent _makeEvent(String message) {
  return NightshadeEvent(
    timestamp: DateTime.now().millisecondsSinceEpoch,
    severity: EventSeverity.info,
    category: EventCategory.system,
    eventType: 'test.event',
    data: {'message': message},
  );
}

Future<void> _pumpLogTab(
  WidgetTester tester, {
  required NightshadeBackend backend,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWith((ref) {
          return _OverrideBackendNotifier(ref, backend);
        }),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: const [NightshadeColors.dark]),
        home: const Scaffold(body: LogTab()),
      ),
    ),
  );
  await tester.pump();
}

class _OverrideBackendNotifier extends BackendNotifier {
  _OverrideBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }

  /// Simulate a backend swap by publishing a new state, exactly as a real
  /// reconnect would. Watchers (LogTab) see the new identity and re-subscribe.
  void swapTo(NightshadeBackend backend) => state = backend;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LogTab clears events when the backend identity changes', (
    tester,
  ) async {
    final backendA = _StubBackend('A');
    final backendB = _StubBackend('B');

    // Start with backend A. Capture the notifier so the test can publish a
    // backend swap through its state (a stable-key ProviderScope does NOT
    // re-apply a changed override closure, so mutating state is the faithful
    // way to simulate a reconnect to a different host).
    late _OverrideBackendNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith((ref) {
            notifier = _OverrideBackendNotifier(ref, backendA);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: const [NightshadeColors.dark]),
          home: const Scaffold(body: LogTab()),
        ),
      ),
    );
    await tester.pump();

    // Emit an event from backend A; the LogTab subscription should land it.
    backendA.emit(_makeEvent('event-from-A'));
    await tester.pump(); // flush the broadcast-stream microtask
    await tester.pump(); // rebuild with the delivered event

    expect(
      find.text('event-from-A'),
      findsOneWidget,
      reason: 'Backend A event must be visible while A is active.',
    );

    // Swap to backend B by publishing a new backend identity; LogTab must
    // flush its buffer when the watched backend changes.
    notifier.swapTo(backendB);
    await tester.pump();
    await tester.pump(); // let _ensureSubscription run on the next frame

    // The A event must be gone; LogTab should be empty and showing the
    // "Waiting for events" empty state.
    expect(
      find.text('event-from-A'),
      findsNothing,
      reason: 'Buffer must clear when the backend identity changes.',
    );
    expect(
      find.text('Waiting for events'),
      findsOneWidget,
      reason: 'Empty-state message must appear after a backend swap.',
    );

    // Verify the new backend's events land normally.
    backendB.emit(_makeEvent('event-from-B'));
    await tester.pump(); // flush the broadcast-stream microtask
    await tester.pump(); // rebuild with the delivered event
    expect(find.text('event-from-B'), findsOneWidget);

    await backendA.close();
    await backendB.close();
  });

  testWidgets('LogTab keeps events when rebuild does not change backend', (
    tester,
  ) async {
    final backend = _StubBackend('only');
    await _pumpLogTab(tester, backend: backend);

    backend.emit(_makeEvent('keep-me'));
    await tester.pump(); // flush the broadcast-stream microtask
    await tester.pump(); // rebuild with the delivered event
    expect(find.text('keep-me'), findsOneWidget);

    // Rebuild the tree with the SAME backend instance — the buffer must
    // not flush. Identity check is identical(_subscribedBackend, backend).
    await tester.pump();
    expect(
      find.text('keep-me'),
      findsOneWidget,
      reason: 'Identical-backend rebuild must not clear the buffer.',
    );

    await backend.close();
  });
}
