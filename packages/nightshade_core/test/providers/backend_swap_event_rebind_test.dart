// CONC-002 regression: polarAlignmentStateProvider and autofocusOverlayProvider
// historically bound to a single backend.eventStream in their constructor and
// never re-bound when the active backend was swapped (local FFI <-> network).
// After a reconnect they went deaf. These tests swap the backend and assert
// events from the NEW backend still drive the notifiers.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/backend/event_types.dart';
import 'package:nightshade_core/src/providers/autofocus_progress_provider.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/polar_alignment_provider.dart';

import '../mocks/mock_backend.dart';

class _SwappableBackendNotifier extends BackendNotifier {
  _SwappableBackendNotifier(super.ref, NightshadeBackend initial) : super() {
    state = initial;
  }

  void swapTo(NightshadeBackend backend) => state = backend;
}

NightshadeEvent _polarEvent() => NightshadeEvent(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  severity: EventSeverity.info,
  category: EventCategory.polarAlignment,
  eventType: 'PolarAlignment',
  data: const {
    'azimuth_error': 1.5,
    'altitude_error': -0.75,
    'total_error': 1.68,
  },
);

NightshadeEvent _autofocusEvent() => NightshadeEvent(
  timestamp: DateTime.now().millisecondsSinceEpoch,
  severity: EventSeverity.info,
  category: EventCategory.equipment,
  eventType: 'AutofocusProgress',
  // No 'detail' payload -> the notifier routes to onAutofocusFailed, which is
  // an observable state change proving the event was received.
  data: const {},
);

Future<void> _pump() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late StreamController<NightshadeEvent> oldEvents;
  late StreamController<NightshadeEvent> newEvents;
  late MockBackend oldBackend;
  late MockBackend newBackend;

  setUp(() {
    oldEvents = StreamController<NightshadeEvent>.broadcast();
    newEvents = StreamController<NightshadeEvent>.broadcast();
    oldBackend = MockBackend();
    newBackend = MockBackend();
    when(() => oldBackend.eventStream).thenAnswer((_) => oldEvents.stream);
    when(() => newBackend.eventStream).thenAnswer((_) => newEvents.stream);
  });

  tearDown(() async {
    await oldEvents.close();
    await newEvents.close();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => _SwappableBackendNotifier(ref, oldBackend),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'polar alignment re-binds to the swapped backend event stream',
    () async {
      final container = buildContainer();
      container.read(polarAlignmentStateProvider.notifier);
      await _pump();

      // Swap the active backend, then emit from the NEW backend.
      (container.read(backendProvider.notifier) as _SwappableBackendNotifier)
          .swapTo(newBackend);
      await _pump();

      expect(
        container.read(polarAlignmentStateProvider).currentError,
        isNull,
        reason: 'no event delivered yet',
      );

      newEvents.add(_polarEvent());
      await _pump();

      final error = container.read(polarAlignmentStateProvider).currentError;
      expect(error, isNotNull);
      expect(error!.totalError, closeTo(1.68, 1e-9));
    },
  );

  test(
    'autofocus overlay re-binds to the swapped backend event stream',
    () async {
      final container = buildContainer();
      container.read(autofocusOverlayProvider.notifier);
      await _pump();

      (container.read(backendProvider.notifier) as _SwappableBackendNotifier)
          .swapTo(newBackend);
      await _pump();

      expect(container.read(autofocusOverlayProvider).hasError, isFalse);

      newEvents.add(_autofocusEvent());
      await _pump();

      expect(container.read(autofocusOverlayProvider).hasError, isTrue);
    },
  );
}
