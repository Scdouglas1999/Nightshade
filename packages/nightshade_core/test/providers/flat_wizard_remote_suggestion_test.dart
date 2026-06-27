// Regression coverage for the remote flat-suggestion fallback in
// `FlatWizardNotifier.loadFiltersFromWheel` (W07 / DEFENSE-001).
//
// On a remote client the local `flat_history` table is empty, so the wizard
// derives a suggested exposure from the master via `NetworkBackend.listFlats`.
// That call legitimately throws on transport/host faults. The wizard must
// still load — it falls back to a null suggestion so the user can enter
// exposures manually — but a fault must NOT be silently conflated with an
// empty history: it is logged as a diagnostic (see `_remoteSuggestedExposure`).
//
// These tests assert the user-visible contract that the brief pins down:
//   - a throwing `listFlats` does not escape and break wizard init; the
//     filter's `suggestedExposure` ends up null (manual-entry fallback);
//   - an empty host history yields the same null suggestion.
//
// The diagnostic itself is emitted via `dart:developer`'s `developer.log`,
// which writes to the Dart VM service and is not interceptable by the
// standard `runZoned`/print capture used in unit tests (the same constraint
// documented in network_backend_seq_test.dart). The presence of the log line
// is verified by inspection of `_remoteSuggestedExposure`; here we lock in the
// behavioural contract — load succeeds, no rethrow, null fallback.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:nightshade_core/nightshade_core.dart';

import '../mocks/mock_database.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// Filter-wheel notifier seeded with a fixed set of filter names. The
/// override slot requires the concrete `FilterWheelStateNotifier`, so we
/// extend it and just seed the state — the inherited profile listener is
/// inert here (it only acts when a wheel is connected).
class _SeededFilterWheelNotifier extends FilterWheelStateNotifier {
  _SeededFilterWheelNotifier(super.ref, List<String> names) {
    state = FilterWheelState(filterNames: names);
  }
}

void main() {
  late NightshadeDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  ProviderContainer makeContainer(NightshadeBackend backend) {
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        activeEquipmentProfileProvider.overrideWithValue(null),
        backendProvider.overrideWith(
          (ref) => _FixedBackendNotifier(ref, backend),
        ),
        filterWheelStateProvider.overrideWith(
          (ref) => _SeededFilterWheelNotifier(ref, const ['L']),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'remote listFlats throwing does not break wizard init; suggestion is null',
    () async {
      final backend = _MockNetworkBackend();
      when(
        () => backend.listFlats(
          filter: any(named: 'filter'),
          equipmentProfileId: any(named: 'equipmentProfileId'),
          limit: any(named: 'limit'),
        ),
      ).thenThrow(Exception('host unreachable'));

      final container = makeContainer(backend);
      final notifier = container.read(flatWizardProvider.notifier);

      // Must complete without the transport exception escaping.
      await notifier.loadFiltersFromWheel();

      final settings = container.read(flatWizardProvider).filterSettings;
      expect(settings, hasLength(1));
      expect(settings.single.filterName, 'L');
      expect(
        settings.single.suggestedExposure,
        isNull,
        reason: 'fault falls back to manual entry (null suggestion)',
      );
    },
  );

  test('empty remote history yields a null suggestion (no fault)', () async {
    final backend = _MockNetworkBackend();
    when(
      () => backend.listFlats(
        filter: any(named: 'filter'),
        equipmentProfileId: any(named: 'equipmentProfileId'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => const []);

    final container = makeContainer(backend);
    final notifier = container.read(flatWizardProvider.notifier);

    await notifier.loadFiltersFromWheel();

    final settings = container.read(flatWizardProvider).filterSettings;
    expect(settings, hasLength(1));
    expect(settings.single.suggestedExposure, isNull);
  });
}
