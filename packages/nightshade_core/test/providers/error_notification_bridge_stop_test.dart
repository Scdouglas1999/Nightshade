// PRODUCER 4 of the stop pipeline.
//
// Without the cancellation check here, one operator Stop raises TWO toasts: the
// info "Sequence stopped / Sequence stopped by request at 01:54." AND a RED
// "Sequence Error / Sequence cancelled" beside it.
//
// `errorNotificationBridgeProvider` (providers/event_provider.dart) forwards
// EVERY error-severity backend event straight to `uiNotificationProvider` with a
// title built from the event's category, which for a sequencer event is
// literally "Sequence Error". It never goes through the NotificationRouter, so
// neither the router's classification nor its content dedupe can reach it —
// the check has to be asked for here, as the other producers ask it.
//
// The counter-input is the REAL wire shape, taken from the FFI mapper
// (`backend/ffi_backend/event_mapping.dart:490` — `SequencerEvent_Error` maps to
// eventType 'Error' with `{'message': …}`) at the severity the bridge stamps
// (`bridge/src/api/sequencer/event_bridge.rs:374` — `EventSeverity::Error`).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockFfiBackend extends Mock implements FfiBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// The exact event the native executor's cancelled arm produces.
NightshadeEvent _sequencerError(String message) => NightshadeEvent(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  severity: EventSeverity.error,
  category: EventCategory.sequencer,
  eventType: 'Error',
  data: {'message': message},
);

Future<(ProviderContainer, StreamController<NightshadeEvent>)> _bridge() async {
  final backend = _MockFfiBackend();
  final controller = StreamController<NightshadeEvent>.broadcast();
  when(() => backend.eventStream).thenAnswer((_) => controller.stream);
  final container = ProviderContainer(
    overrides: [
      backendProvider.overrideWith(
        (ref) => _FixedBackendNotifier(ref, backend),
      ),
    ],
  );
  // The bridge is a side-effecting Provider<void>; the shell watches it.
  container.read(errorNotificationBridgeProvider);
  return (container, controller);
}

void main() {
  test('an operator Stop raises no red toast from the error bridge', () async {
    final (container, controller) = await _bridge();
    addTearDown(container.dispose);
    addTearDown(controller.close);

    controller.add(_sequencerError('Sequence cancelled'));
    await pumpEventQueue();

    expect(
      container.read(uiNotificationProvider),
      isEmpty,
      reason:
          'the stop already has its INFO "Sequence stopped" toast; this '
          'producer added a second, RED "Sequence Error / Sequence cancelled" '
          'card beside it',
    );
  });

  test('the American spelling is the same notice', () async {
    final (container, controller) = await _bridge();
    addTearDown(container.dispose);
    addTearDown(controller.close);

    controller.add(_sequencerError('Sequence canceled'));
    await pumpEventQueue();

    expect(container.read(uiNotificationProvider), isEmpty);
  });

  // The counter-inputs that make the match EXACT rather than a substring test.
  // A real fault whose text merely contains "cancelled" must still reach the
  // operator — swallowing it would be the worse bug.
  test('a real fault that merely contains the word still toasts', () async {
    final (container, controller) = await _bridge();
    addTearDown(container.dispose);
    addTearDown(controller.close);

    controller.add(_sequencerError('Temperature compensation cancelled'));
    controller.add(_sequencerError('Focuser lost communication'));
    await pumpEventQueue();

    final shown = container.read(uiNotificationProvider);
    expect(shown.length, 2);
    expect(shown.every((n) => n.level == UiNotificationLevel.error), isTrue);
    expect(shown.first.title, 'Sequence Error');
    expect(shown.map((n) => n.message).toList(), [
      'Temperature compensation cancelled',
      'Focuser lost communication',
    ]);
  });
}
