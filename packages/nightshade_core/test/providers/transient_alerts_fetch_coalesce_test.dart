// CONC-001 regression: activeTransientAlertsProvider previously fired
// fetchAlerts() from three triggers (immediate subscribe, 15-min poll, and
// local-detections-change) with NO in-flight guard, so a burst of triggers
// spawned concurrent fetches and out-of-order completion could overwrite a
// fresher external alert list. The fix coalesces overlapping triggers into a
// single in-flight fetch plus at most one queued follow-up, with newest-wins.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/models/alerts/transient_alert.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/providers/transient_alert_provider.dart';
import 'package:nightshade_core/src/providers/transient_detections_provider.dart';
import 'package:nightshade_core/src/services/logging_service.dart';
import 'package:nightshade_core/src/services/transient_alert_service.dart';

import '../fakes/fakes.dart';

/// Service whose getAllAlerts hands back a controllable completer per call so
/// the test can hold a fetch "in flight" and count how many fetches ran.
class _ControllableService extends TransientAlertService {
  _ControllableService()
    : super(httpClient: FakeNetworkClient(), logger: LoggingService());

  int callCount = 0;
  final List<Completer<List<TransientAlert>>> completers = [];

  @override
  Future<List<TransientAlert>> getAllAlerts(TransientAlertSettings settings) {
    callCount++;
    final completer = Completer<List<TransientAlert>>();
    completers.add(completer);
    return completer.future;
  }
}

TransientAlert _alert(String id) => TransientAlert(
  id: id,
  name: id,
  type: TransientType.supernova,
  raHours: 1,
  decDegrees: 2,
  discoveryTime: DateTime(2026, 1, 1),
  lastUpdated: DateTime(2026, 1, 1),
  source: TransientSource.tns,
);

Future<void> _pump() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late NightshadeDatabase db;
  late _ControllableService service;
  late StreamController<List<TransientDetectionRow>> detections;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    service = _ControllableService();
    detections = StreamController<List<TransientDetectionRow>>.broadcast();
  });

  tearDown(() async {
    await detections.close();
    await db.close();
  });

  test('out-of-order fetch completion never overwrites the freshest data',
      () async {
    final container = ProviderContainer(
      overrides: [
        settingsDaoProvider.overrideWithValue(db.settingsDao),
        transientAlertServiceProvider.overrideWithValue(service),
        allTransientDetectionsProvider.overrideWith((ref) => detections.stream),
      ],
    );
    addTearDown(container.dispose);

    // Subscribe — kicks off the immediate fetch. The provider also rebuilds
    // once when the async settings load resolves, so drain to a quiescent
    // baseline before measuring the burst-coalescing behaviour. Draining
    // completes every in-flight fetch (old rebuilt closures are guarded by
    // `controller.isClosed`) until no fetch is outstanding.
    final sub = container.listen(
      activeTransientAlertsProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(sub.close);
    await _pump();

    Future<void> drain() async {
      while (service.completers.any((c) => !c.isCompleted)) {
        for (final c in service.completers) {
          if (!c.isCompleted) c.complete([_alert('seed')]);
        }
        await _pump();
      }
    }

    await drain();

    // Two external-feed triggers in quick succession, both left in flight.
    detections.add(<TransientDetectionRow>[]);
    await _pump();
    detections.add(<TransientDetectionRow>[]);
    await _pump();

    // The newest in-flight fetch (highest index) is the freshest request.
    // Complete it FIRST with the fresh data.
    final freshIndex = service.completers.length - 1;
    expect(service.completers[freshIndex].isCompleted, isFalse);
    service.completers[freshIndex].complete([_alert('fresh')]);
    await _pump();

    // Now the older, slower fetches resolve LATE with stale data. With the
    // overlap guard in place these out-of-order completions must NOT clobber
    // the fresher result that already landed. (Only older fetches are
    // resolved; any follow-up spawned by the fresh completion is left pending.)
    for (var i = 0; i < freshIndex; i++) {
      if (!service.completers[i].isCompleted) {
        service.completers[i].complete([_alert('stale')]);
      }
    }
    await _pump();

    final value = container.read(activeTransientAlertsProvider).valueOrNull;
    expect(value, isNotNull);
    expect(
      value!.map((a) => a.id),
      equals(['fresh']),
      reason: 'a late stale fetch must not overwrite the freshest result',
    );
  });
}
