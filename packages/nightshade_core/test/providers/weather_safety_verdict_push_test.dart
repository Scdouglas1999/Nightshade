import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/settings/app_settings.dart';
import 'package:nightshade_core/src/models/weather/weather_models.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';
import 'package:nightshade_core/src/providers/weather_providers.dart';
import 'package:nightshade_core/src/providers/weather_safety_provider.dart';
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/services/safe_rig_service.dart';

import '../mocks/mock_backend.dart';

/// AppSettings fake that resolves immediately so `appSettingsProvider.future`
/// completes without touching the database.
class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);
  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

/// Backend notifier seeded with a fixed (mock) backend.
class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// No-op SafeRig so the unsafe-verdict path does not drag the heavy hardware
/// enforcement (mount park / dome close / critical notification) into this
/// push-wiring test. SafeRig enforcement has its own dedicated tests.
class _NoopSafeRigService extends SafeRigService {
  _NoopSafeRigService(super.ref);

  @override
  Future<SafeRigResult> safeTheRig({
    required String reason,
    bool park = true,
    bool closeDome = false,
    bool closeCover = false,
    bool notify = true,
  }) async =>
      const SafeRigResult();
}

void main() {
  // Full-night audit 2026-06-04 (defense-in-depth): the weather-safety provider
  // must forward its overall verdict to the Rust executor on every evaluation
  // so the in-sequencer `WeatherUnsafe` trigger reacts even on a rig with no
  // hardware safety device. This pins that push wiring.
  group('weatherSafetyProvider pushes verdict to the executor', () {
    late MockBackend backend;

    setUp(() {
      backend = MockBackend();
      when(() => backend.eventStream).thenAnswer((_) => const Stream.empty());
      when(() => backend.sequencerUpdateWeatherVerdict(
            unsafeOverride: any(named: 'unsafeOverride'),
          )).thenAnswer((_) async {});
      // The constructor's cloud-motion / adaptive-conditions push loops also
      // touch the backend on their first microtask; stub them so they no-op
      // instead of throwing (which the provider would swallow anyway).
      when(() => backend.sequencerUpdateCloudMotion(
            currentCoverPercent: any(named: 'currentCoverPercent'),
            predictedArrivalMinutes: any(named: 'predictedArrivalMinutes'),
            predictedOpeningMinutes: any(named: 'predictedOpeningMinutes'),
            predictedOpeningDurationSecs:
                any(named: 'predictedOpeningDurationSecs'),
            predictedClearSkyAlt: any(named: 'predictedClearSkyAlt'),
            predictedClearSkyAz: any(named: 'predictedClearSkyAz'),
          )).thenAnswer((_) async {});
    });

    ProviderContainer buildContainer({required bool safetyEnabled}) {
      final container = ProviderContainer(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
          appSettingsProvider.overrideWith(
            () => _FakeAppSettingsNotifier(
              // failClosed is the default; with no connected weather/safety
              // device and no API alert the evaluator takes the fail-mode path.
              const AppSettingsState(safetyFailMode: SafetyFailMode.failClosed),
            ),
          ),
          weatherSettingsProvider.overrideWithValue(
            WeatherSettings(weatherSafetyEnabled: safetyEnabled),
          ),
          safeRigServiceProvider.overrideWith(
            (ref) => _NoopSafeRigService(ref),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('reports UNSAFE when no data source is available (fail-closed)',
        () async {
      final container = buildContainer(safetyEnabled: true);
      // Construct the notifier; the constructor runs an initial evaluation.
      container.read(weatherSafetyProvider.notifier);
      // Let the appSettings future + the evaluation's unawaited verdict push
      // resolve.
      await container.read(appSettingsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // No connected weather device + no safety monitor + no API alert under
      // fail-closed => the overall verdict is UNSAFE, so the executor must be
      // told `unsafeOverride: true`.
      verify(() => backend.sequencerUpdateWeatherVerdict(unsafeOverride: true))
          .called(greaterThanOrEqualTo(1));
      verifyNever(
        () => backend.sequencerUpdateWeatherVerdict(unsafeOverride: false),
      );
    });

    test('reports SAFE when weather safety is disabled', () async {
      final container = buildContainer(safetyEnabled: false);
      container.read(weatherSafetyProvider.notifier);
      await container.read(appSettingsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Safety disabled => the operator's effective verdict is "do not abort on
      // weather" => SAFE is pushed (the Rust evaluator still ORs in the
      // hardware reading, so a hardware-unsafe device aborts regardless).
      verify(() => backend.sequencerUpdateWeatherVerdict(unsafeOverride: false))
          .called(greaterThanOrEqualTo(1));
      verifyNever(
        () => backend.sequencerUpdateWeatherVerdict(unsafeOverride: true),
      );
    });
  });
}
