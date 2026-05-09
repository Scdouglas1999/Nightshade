import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/phd2_models.dart';
import 'package:nightshade_core/src/providers/autofocus_progress_provider.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/equipment_provider.dart';
import 'package:nightshade_core/src/providers/guiding_provider.dart';

import '../mocks/mock_backend.dart';

class TestBackendNotifier extends BackendNotifier {
  TestBackendNotifier(Ref ref, NightshadeBackend backend) : super(ref) {
    state = backend;
  }
}

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
            .overrideWith((ref) => TestBackendNotifier(ref, mockBackend)),
      ],
    );
  });

  tearDown(() async {
    await eventStreamController.close();
    container.dispose();
  });

  test('autofocus overlay surfaces malformed progress events as errors',
      () async {
    container.read(autofocusOverlayProvider.notifier).onAutofocusStarted();

    eventStreamController.add(
      NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.warning,
        category: EventCategory.equipment,
        eventType: 'AutofocusProgress',
        data: const {'detail': 'not valid autofocus progress'},
      ),
    );

    await Future<void>.delayed(Duration.zero);

    final state = container.read(autofocusOverlayProvider);
    expect(state.hasError, isTrue);
    expect(state.status, contains('could not be parsed'));
  });

  test('calibration complete refreshes calibration data through public API',
      () async {
    var fetchCount = 0;
    when(() => mockBackend.phd2GetCalibrationData()).thenAnswer((_) async {
      fetchCount++;
      return const Phd2CalibrationData(
        isCalibrated: true,
        rotationAngle: 12.5,
        raRate: 1.45,
      );
    });

    container.read(phd2ControllerProvider);
    final guiderNotifier = container.read(guiderStateProvider.notifier);
    guiderNotifier.setConnecting('phd2_guider', 'PHD2');
    guiderNotifier.setConnected();

    eventStreamController.add(
      NightshadeEvent(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'CalibrationComplete',
        data: const <String, dynamic>{},
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(fetchCount, greaterThan(0));
    final state = container.read(calibrationStateProvider);
    expect(state.isCalibrated, isTrue);
  });
}
