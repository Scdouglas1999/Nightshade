import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/framing_provider.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';

import '../mocks/mock_backend.dart';

class _TestBackendNotifier extends BackendNotifier {
  _TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
  }
}

// CQ-W1-DISPOSE-DART: verifies long-lived notifiers / providers tear down
// their owned timers and subscriptions when the ProviderContainer is
// disposed. Dart's test binding raises a "Timer is still pending"
// assertion if anything leaks past container teardown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late MockBackend mockBackend;
  late StreamController<NightshadeEvent> eventStreamController;

  setUpAll(() {
    registerMocktailFallbackValues();
  });

  setUp(() {
    mockBackend = MockBackend();
    eventStreamController = StreamController<NightshadeEvent>.broadcast();

    when(() => mockBackend.eventStream)
        .thenAnswer((_) => eventStreamController.stream);
    when(() => mockBackend.polarAlignmentEvents)
        .thenAnswer((_) => const Stream.empty());

    container = ProviderContainer(
      overrides: [
        backendProvider
            .overrideWith((ref) => _TestBackendNotifier(ref, mockBackend)),
      ],
    );
  });

  tearDown(() async {
    await eventStreamController.close();
    container.dispose();
  });

  test(
      'sequenceExecutorProvider runs onDispose hook on container teardown without leaking timers',
      () {
    // Force the executor to instantiate. The dispose hook registered via
    // ref.onDispose must run when the container is disposed below — if any
    // owned timer survives teardown the test binding will raise a
    // "Timer is still pending" assertion.
    final executor = container.read(sequenceExecutorProvider);
    expect(executor, isNotNull);

    // Disposing the container fires ref.onDispose(executor.dispose).
    container.dispose();
  });

  test(
      'TargetSearchNotifier debounce timer is cancelled on dispose so the search closure cannot fire after teardown',
      () async {
    final notifier = container.read(targetSearchProvider.notifier);
    // Kick off a debounced search: this schedules a 300 ms Timer.
    notifier.search('Andromeda');
    expect(container.read(targetSearchProvider).isSearching, isTrue);

    // Dispose before the timer fires.
    container.dispose();

    // Wait longer than the debounce window. If dispose did not cancel the
    // timer, _performSearch would attempt to mutate state on a disposed
    // notifier and the test binding would surface the late update.
    await Future<void>.delayed(const Duration(milliseconds: 500));
  });
}
