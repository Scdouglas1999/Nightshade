// THROWAWAY refuter probe — RECENT EVENTS stop fold + time-windowed collapse.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/run_dashboard/run_dashboard_providers.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as be;
import 'package:nightshade_core/nightshade_core.dart';

final _t0 = DateTime(2026, 8, 13, 1, 54, 26);

be.NightshadeEvent _error(int id, String message, DateTime at) =>
    be.NightshadeEvent(
      eventId: BigInt.from(id),
      timestamp: at.millisecondsSinceEpoch,
      severity: be.EventSeverity.error,
      category: be.EventCategory.sequencer,
      payload: be.EventPayload.sequencer(
        be.SequencerEvent.error(message: message),
      ),
    );

be.NightshadeEvent _decision(int id, String summary, DateTime at) =>
    be.NightshadeEvent(
      eventId: BigInt.from(id),
      timestamp: at.millisecondsSinceEpoch,
      severity: be.EventSeverity.info,
      category: be.EventCategory.sequencer,
      payload: be.EventPayload.sequencer(
        be.SequencerEvent.decisionLogged(
          timestampIso: at.toUtc().toIso8601String(),
          category: 'system_event',
          summary: summary,
          detailsJson: '{"phase":"cancelled"}',
          sequenceRunId: 15,
        ),
      ),
    );

be.NightshadeEvent _stopped(int id, DateTime at) => be.NightshadeEvent(
  eventId: BigInt.from(id),
  timestamp: at.millisecondsSinceEpoch,
  severity: be.EventSeverity.info,
  category: be.EventCategory.sequencer,
  payload: const be.EventPayload.sequencer(be.SequencerEvent.stopped()),
);

be.NightshadeEvent _started(int id, DateTime at) => be.NightshadeEvent(
  eventId: BigInt.from(id),
  timestamp: at.millisecondsSinceEpoch,
  severity: be.EventSeverity.info,
  category: be.EventCategory.sequencer,
  payload: be.EventPayload.sequencer(
    be.SequencerEvent.started(sequenceName: 'Tonight'),
  ),
);

RunDashboardEvent _row(String title, String message, DateTime at) =>
    RunDashboardEvent(
      eventId: BigInt.from(at.millisecondsSinceEpoch),
      time: at,
      severity: RunDashboardEventSeverity.warning,
      category: 'Guiding',
      title: title,
      message: message,
      isCritical: false,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  setUp(() => db = NightshadeDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    return c;
  }

  void pressStop(ProviderContainer c, {required int base, DateTime? at}) {
    final when = at ?? _t0;
    final h = c.read(eventHistoryProvider.notifier);
    h.addEvent(_error(base, kSequenceCancelledNotice, when));
    h.addEvent(_decision(base + 1, kSequenceCancelledNotice, when));
    h.addEvent(_stopped(base + 2, when));
    h.addEvent(_stopped(base + 3, when));
  }

  // ---------------------------------------------------------------- (c) window

  test('C1 a genuine repeat storm spaced 60 s apart stays ONE row', () {
    // A flapping condition that re-reports every minute for 25 minutes. Every
    // neighbouring pair is 60 s apart, so by the stated rule ("identical rows
    // further apart than 10 minutes are separate happenings") this is one
    // happening, still going.
    final rows = <RunDashboardEvent>[
      for (var i = 0; i < 26; i++)
        _row(
          'Guider disconnected',
          'Guider · reconnecting',
          _t0.subtract(Duration(minutes: i)),
        ),
    ];
    final out = collapseRepeatedEvents(rows);
    expect(
      out,
      hasLength(1),
      reason:
          'got ${out.length} rows: '
          '${out.map((e) => '${e.time.toIso8601String()} x${e.repeatCount}').toList()}',
    );
  });

  test('C2 two identical rows 20 minutes apart stay two rows', () {
    final out = collapseRepeatedEvents([
      _row('Sequence stopped', 'Stopped by request', _t0),
      _row(
        'Sequence stopped',
        'Stopped by request',
        _t0.subtract(const Duration(minutes: 20)),
      ),
    ]);
    expect(out, hasLength(2));
  });

  test('C3 two stops of two different runs, 5 minutes apart', () {
    final c = makeContainer();
    final firstStop = _t0.subtract(const Duration(minutes: 5));
    pressStop(c, base: 1, at: firstStop);
    // run 2 starts and is stopped five minutes later
    c
        .read(eventHistoryProvider.notifier)
        .addEvent(_started(20, firstStop.add(const Duration(minutes: 1))));
    pressStop(c, base: 30, at: _t0);

    final recent = c.read(runDashboardRecentEventsProvider(10));
    expect(
      recent.where((e) => e.title == 'Sequence stopped').length,
      2,
      reason:
          'two operator decisions five minutes apart. Got: '
          '${recent.map((e) => '${e.title}/${e.message}/x${e.repeatCount}').toList()}',
    );
  });

  test('C4 the same two stops with NO event between them', () {
    final c = makeContainer();
    pressStop(c, base: 1, at: _t0.subtract(const Duration(minutes: 5)));
    pressStop(c, base: 30, at: _t0);

    final recent = c.read(runDashboardRecentEventsProvider(10));
    expect(
      recent.map((e) => '${e.title} x${e.repeatCount}').toList(),
      ['Sequence stopped x1', 'Sequence stopped x1'],
      reason: 'two stops five minutes apart with nothing between them',
    );
  });

  // ------------------------------------------------------------- (d) stop fold

  test('D1 one press of Stop is one row (baseline)', () {
    final c = makeContainer();
    pressStop(c, base: 1);
    final recent = c.read(runDashboardRecentEventsProvider(5));
    expect(recent, hasLength(1));
    expect(recent.single.title, 'Sequence stopped');
    expect(recent.single.repeatCount, 1);
  });

  test('D2 a real error 3 s AFTER the stop survives', () {
    final c = makeContainer();
    pressStop(c, base: 1);
    c.read(eventHistoryProvider.notifier).addEvent(
      _error(
        50,
        'Failed to park mount: limit switch',
        _t0.add(const Duration(seconds: 3)),
      ),
    );
    final recent = c.read(runDashboardRecentEventsProvider(5));
    expect(
      recent.any((e) => e.message.contains('limit switch')),
      isTrue,
      reason: 'rows: ${recent.map((e) => '${e.title}/${e.message}').toList()}',
    );
    expect(recent.where((e) => e.title == 'Sequence stopped'), hasLength(1));
  });

  test('D3 a real error 3 s BEFORE the stop survives', () {
    final c = makeContainer();
    c.read(eventHistoryProvider.notifier).addEvent(
      _error(
        50,
        'Guide star lost past the limit',
        _t0.subtract(const Duration(seconds: 3)),
      ),
    );
    pressStop(c, base: 1);
    final recent = c.read(runDashboardRecentEventsProvider(5));
    expect(recent.any((e) => e.message.contains('Guide star lost')), isTrue);
    expect(recent.where((e) => e.title == 'Sequence stopped'), hasLength(1));
  });

  test('D4 a real error INSIDE the stop family (interleaved) — one stop row?', () {
    // Producers 3 and 4 are separated by the whole safing/park teardown, so a
    // device/park event landing between them is the normal live case.
    final c = makeContainer();
    final h = c.read(eventHistoryProvider.notifier);
    h.addEvent(_error(1, kSequenceCancelledNotice, _t0));
    h.addEvent(_decision(2, kSequenceCancelledNotice, _t0));
    h.addEvent(_stopped(3, _t0));
    h.addEvent(
      _error(
        4,
        'Dome shutter failed to close',
        _t0.add(const Duration(seconds: 2)),
      ),
    );
    h.addEvent(_stopped(5, _t0.add(const Duration(seconds: 4))));

    final recent = c.read(runDashboardRecentEventsProvider(5));
    expect(
      recent.any((e) => e.message.contains('Dome shutter')),
      isTrue,
      reason: 'the real error must never be eaten',
    );
    expect(
      recent.where((e) => e.title == 'Sequence stopped'),
      hasLength(1),
      reason:
          'one press of Stop. Got: '
          '${recent.map((e) => '${e.title}/${e.message}').toList()}',
    );
  });

  test('D5 a fault-driven abort must not read as "Stopped by request"', () {
    // No operator Stop: a real fault ends the run, and the executor still
    // publishes the Stopped state change.
    final c = makeContainer();
    final h = c.read(eventHistoryProvider.notifier);
    h.addEvent(_error(1, 'Mount tracking lost; sequence aborted', _t0));
    h.addEvent(_stopped(2, _t0.add(const Duration(seconds: 1))));

    final recent = c.read(runDashboardRecentEventsProvider(5));
    final stopRows = recent.where((e) => e.title == 'Sequence stopped');
    expect(
      stopRows.every((e) => e.message != 'Stopped by request'),
      isTrue,
      reason:
          'rows: '
          '${recent.map((e) => '${e.severity.name} ${e.title}/${e.message}').toList()}',
    );
  });

  test('D6 a genuine repeat storm of stops is not silently thinned', () {
    // Four presses of Stop, one every 3 s (an operator mashing Stop while the
    // run refuses to end). Each press is a real event the log must show.
    final c = makeContainer();
    for (var i = 0; i < 4; i++) {
      pressStop(
        c,
        base: 1 + i * 10,
        at: _t0.add(Duration(seconds: 3 * i)),
      );
    }
    final recent = c.read(runDashboardRecentEventsProvider(10));
    expect(
      recent.where((e) => e.title == 'Sequence stopped').length,
      greaterThan(1),
      reason:
          'four presses in 9 s collapsed to '
          '${recent.map((e) => '${e.title} x${e.repeatCount}').toList()}',
    );
  });
}
