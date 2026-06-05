// P1 — Remote/mobile settings coverage + fail-loud.
//
// Covers the cluster's Finding #2 fixes:
//   * Settings the remote wire model CAN carry (Wave 3 Image Grading,
//     Wave 5 adaptive exposure) now round-trip through `_toRemoteSettings`
//     instead of being silently dropped when saved over a NetworkBackend.
//   * Settings the wire model CANNOT carry (e.g. park-on-unsafe-weather)
//     FAIL LOUD on a remote save instead of silently no-op'ing.
//   * Inbound `settings.changed` events for the newly-mapped keys are
//     applied in-place.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_core/src/backend/network_backend.dart';
import 'package:nightshade_core/src/backend/nightshade_backend.dart';
import 'package:nightshade_core/src/models/settings/app_settings.dart'
    as models;
import 'package:nightshade_core/src/providers/backend_provider.dart';
import 'package:nightshade_core/src/providers/settings_provider.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) {
    state = backend;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const models.AppSettings());
  });

  /// Wire a mock NetworkBackend that records the last `updateSettings*`
  /// payload so a test can assert what actually crossed the wire.
  ({
    _MockNetworkBackend backend,
    StreamController<NightshadeEvent> events,
    List<models.AppSettings> writes,
  }) buildBackend(models.AppSettings initial) {
    final controller = StreamController<NightshadeEvent>.broadcast();
    final backend = _MockNetworkBackend();
    final writes = <models.AppSettings>[];
    when(() => backend.eventStream).thenAnswer((_) => controller.stream);
    when(() => backend.getSettings()).thenAnswer((_) async => initial);
    when(() => backend.updateSettingsWithCommandId(any(),
        commandId: any(named: 'commandId'))).thenAnswer((invocation) async {
      writes.add(invocation.positionalArguments.first as models.AppSettings);
    });
    when(() => backend.updateSettings(any())).thenAnswer((invocation) async {
      writes.add(invocation.positionalArguments.first as models.AppSettings);
    });
    return (backend: backend, events: controller, writes: writes);
  }

  ProviderContainer containerFor(_MockNetworkBackend backend) {
    return ProviderContainer(
      overrides: [
        backendProvider.overrideWith(
          (ref) => _FixedBackendNotifier(ref, backend),
        ),
      ],
    );
  }

  test('image grading enable round-trips through the remote wire model',
      () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setEnableImageGrading(true);

    expect(h.writes, isNotEmpty,
        reason: 'a remote save must forward the change to the host');
    expect(h.writes.last.enableImageGrading, isTrue,
        reason: 'grading flag must be carried by the wire model, not dropped');
  });

  test('adaptive-exposure enable round-trips through the remote wire model',
      () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setAdaptiveExposureEnabled(true);

    expect(h.writes.last.adaptiveExposureEnabled, isTrue);
  });

  test('non-remotable setting FAILS LOUD on a remote save', () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    // dark_library_min_coverage is NOT carried by models.AppSettings, so
    // saving it over a network backend would silently vanish. The guard
    // must throw. (Long-tail settings like this remain deferred; the
    // fail-loud guard keeps them honest until carried.)
    await expectLater(
      container
          .read(appSettingsProvider.notifier)
          .setDarkLibraryMinCoverage(25),
      throwsA(isA<UnsupportedError>()),
    );

    expect(h.writes, isEmpty,
        reason: 'a non-remotable key must never reach the host');
  });

  // Full-night audit 2026-06-04 follow-up — the high-value unattended-night
  // knobs (autofocus / dither / weather-safety / recovery) are now carried by
  // models.AppSettings, so a remote save round-trips instead of failing loud.
  test('park-on-unsafe-weather round-trips through the remote wire model',
      () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setParkOnUnsafeWeather(false);

    expect(h.writes, isNotEmpty,
        reason: 'a remote save must forward the change to the host');
    expect(h.writes.last.parkOnUnsafeWeather, isFalse,
        reason: 'park-on-unsafe-weather must be carried, not dropped');
  });

  test('dither enable + scale round-trip through the remote wire model',
      () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    await container.read(appSettingsProvider.notifier).setDitherEnabled(false);
    await container.read(appSettingsProvider.notifier).setDitherScale('Large');

    expect(h.writes.last.ditherEnabled, isFalse);
    expect(h.writes.last.ditherScale, 'Large');
  });

  test('autofocus disable-guiding round-trips through the remote wire model',
      () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setAfDisableGuidingDuringAf(true);

    expect(h.writes.last.afDisableGuidingDuringAf, isTrue);
  });

  test('recovery max-duration round-trips through the remote wire model',
      () async {
    final h = buildBackend(const models.AppSettings());
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setRecoveryDefaultMaxDurationMins(120.0);

    expect(h.writes.last.recoveryDefaultMaxDurationMins, 120.0);
  });

  test('inbound settings.changed for ditherScale is applied in-place',
      () async {
    final h = buildBackend(const models.AppSettings(ditherScale: 'Medium'));
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    final initial = await container.read(appSettingsProvider.future);
    expect(initial.ditherScale, 'Medium');

    h.events.add(NightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.system,
      eventType: settingsChangedEventType,
      data: const {
        'key': 'ditherScale',
        'value': 'Large',
      },
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final after = container.read(appSettingsProvider).valueOrNull;
    expect(after!.ditherScale, 'Large');
  });

  test('inbound settings.changed for enableImageGrading is applied in-place',
      () async {
    final h = buildBackend(const models.AppSettings(enableImageGrading: false));
    addTearDown(h.events.close);
    final container = containerFor(h.backend);
    addTearDown(container.dispose);

    final initial = await container.read(appSettingsProvider.future);
    expect(initial.enableImageGrading, isFalse);

    h.events.add(NightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.system,
      eventType: settingsChangedEventType,
      data: const {
        'key': 'enableImageGrading',
        'value': true,
      },
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final after = container.read(appSettingsProvider).valueOrNull;
    expect(after!.enableImageGrading, isTrue);
  });
}
