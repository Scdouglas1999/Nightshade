// Provider tests for the built-in multi-star guider's UI data path
// (Phase F, guider-ui):
//
//   1. guideGraphProvider — the SAME graph the PHD2 path uses must populate for
//      the internal guider too. The internal guider publishes `Correction`
//      events, which the backend maps to `GuideStep` (RADistanceRaw /
//      DECDistanceRaw). This test pins that a GuideStep event flows into
//      `guideGraphProvider` as a graph point, so the panel graph is no longer
//      empty under the internal guider.
//
//   2. guideStarsProvider — polls the guiding status (which now carries the
//      per-star `trackedStars` list) while the internal guider is looping/
//      guiding, and exposes the list to the star-list UI. It must stay empty
//      for PHD2 (which reports no per-star list).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show Phd2State;
import 'package:nightshade_core/nightshade_core.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

const _builtinGuiderId = 'native:builtin_guider:multi_star';

ProviderContainer _container(NightshadeBackend backend) {
  final container = ProviderContainer(
    overrides: [
      backendProvider.overrideWith((ref) => _FixedBackendNotifier(ref, backend)),
      loggingServiceProvider.overrideWithValue(LoggingService()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A guiding `GuideStep`-equivalent event (the internal guider's `Correction`
/// maps to this on both transports).
NightshadeEvent _guideStepEvent({required double ra, required double dec}) {
  return NightshadeEvent(
    severity: EventSeverity.info,
    category: EventCategory.guiding,
    eventType: 'GuideStep',
    data: {
      'RADistanceRaw': ra,
      'DECDistanceRaw': dec,
    },
    timestamp: DateTime.now().millisecondsSinceEpoch,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Stream<NightshadeEvent>.empty());
  });

  group('guideGraphProvider (shared graph)', () {
    test('a GuideStep event adds a point with the mapped RA/Dec', () async {
      final controller = StreamController<NightshadeEvent>.broadcast();
      addTearDown(controller.close);

      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer((_) => controller.stream);

      final container = _container(backend);

      // Materialize the provider so its event binding subscribes.
      expect(container.read(guideGraphProvider), isEmpty);

      controller.add(_guideStepEvent(ra: 1.5, dec: -0.75));
      await Future<void>.delayed(Duration.zero);

      final points = container.read(guideGraphProvider);
      expect(points, hasLength(1));
      expect(points.single.ra, 1.5);
      expect(points.single.dec, -0.75);
    });

    test('GuidingStopped clears the graph', () async {
      final controller = StreamController<NightshadeEvent>.broadcast();
      addTearDown(controller.close);

      final backend = _MockNetworkBackend();
      when(() => backend.eventStream).thenAnswer((_) => controller.stream);

      final container = _container(backend);
      container.read(guideGraphProvider);

      controller.add(_guideStepEvent(ra: 1.0, dec: 1.0));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(guideGraphProvider), hasLength(1));

      controller.add(NightshadeEvent(
        severity: EventSeverity.info,
        category: EventCategory.guiding,
        eventType: 'GuidingStopped',
        data: const {},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(guideGraphProvider), isEmpty);
    });
  });

  group('guideStarsProvider (internal multi-star list)', () {
    test('populates from status poll when the built-in guider is looping',
        () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream)
          .thenAnswer((_) => const Stream<NightshadeEvent>.empty());
      when(() => backend.phd2GetStatus()).thenAnswer(
        (_) async => const Phd2Status(
          state: 'Guiding',
          connected: true,
          trackedStars: [
            GuideStar(id: 0, x: 10, y: 12, snr: 18, isLock: true, residual: 0.4),
            GuideStar(id: 1, x: 60, y: 64, snr: 9, residual: 0.9),
          ],
        ),
      );

      final container = _container(backend);

      // Mark the built-in guider as the active, connected guider.
      container.read(guiderStateProvider.notifier)
        ..setConnecting(_builtinGuiderId)
        ..setConnected();
      // Materialize the provider so its listeners attach before we drive state.
      container.read(guideStarsProvider);
      expect(container.read(isBuiltinGuiderProvider), isTrue);

      // Looping/Guiding triggers the immediate poll.
      container.read(phd2StateProvider.notifier).state = Phd2State.guiding;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final stars = container.read(guideStarsProvider);
      expect(stars, hasLength(2));
      expect(stars.first.isLock, isTrue);
      expect(stars.first.residual, 0.4);
      expect(stars[1].snr, 9);
    });

    test('stays empty for PHD2 (no per-star list) and never polls', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream)
          .thenAnswer((_) => const Stream<NightshadeEvent>.empty());
      when(() => backend.phd2GetStatus()).thenAnswer(
        (_) async => const Phd2Status(state: 'Guiding', connected: true),
      );

      final container = _container(backend);

      // PHD2 guider — NOT the built-in id.
      container.read(guiderStateProvider.notifier)
        ..setConnecting('phd2_guider')
        ..setConnected();
      container.read(guideStarsProvider);
      expect(container.read(isBuiltinGuiderProvider), isFalse);

      container.read(phd2StateProvider.notifier).state = Phd2State.guiding;
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(container.read(guideStarsProvider), isEmpty);
      verifyNever(() => backend.phd2GetStatus());
    });

    test('setStars seeds the list (UI/test hook)', () async {
      final backend = _MockNetworkBackend();
      when(() => backend.eventStream)
          .thenAnswer((_) => const Stream<NightshadeEvent>.empty());

      final container = _container(backend);
      container.read(guideStarsProvider.notifier).setStars(const [
        GuideStar(id: 0, x: 1, y: 2, snr: 5, isLock: true),
      ]);

      expect(container.read(guideStarsProvider), hasLength(1));
      expect(container.read(guideStarsProvider).single.isLock, isTrue);
    });
  });
}
