// The overnight driver for the delivery retry sweep.
//
// The failure this guards against is a timer that arms twice (two passes over
// one journal, each writing the other's rows) or one that keeps ticking after
// the server it belongs to has stopped. Both are invisible until a destination
// starts receiving the same file twice.
//
// And the failure that made the retry ladder fiction: with one 15-minute tick,
// a row due 60 seconds after a failed attempt waited for the tick. Measured
// against the release bundle, a share that came back 20 seconds after the
// attempt still had nothing written to it 320 seconds past the row's due time.
// The due check is what makes the documented 1 m / 3 m / 9 m real.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/daos/delivery_journal_dao.dart';
import 'package:nightshade_core/src/database/daos/delivery_targets_dao.dart';
import 'package:nightshade_core/src/database/database.dart';

/// A delivery service whose sweep is counted and can be held open.
class _CountingDelivery extends DeliveryService {
  _CountingDelivery(NightshadeDatabase db)
    : super(
        targets: DeliveryTargetsDao(db),
        journal: DeliveryJournalDao(db),
        transportFactory: (destination, jobId) =>
            throw StateError('no destination is configured in this test'),
      );

  int sweeps = 0;

  /// How many times the short cadence asked whether anything is due.
  int dueChecks = 0;

  /// What the journal says the sweeper's due check should find.
  bool due = false;

  /// Held by a test that needs a pass to still be in flight on the next tick.
  Completer<void>? gate;

  /// Raised by a test that needs the sweep to fail outright.
  Object? failWith;

  /// Raised by a test that needs the journal read behind the due check to fail.
  Object? dueCheckFailsWith;

  @override
  Future<DeliveryRunReport> sweepDueRetries({
    DeliveryCancellation? isCancelled,
  }) async {
    sweeps++;
    final held = gate;
    if (held != null) await held.future;
    final failure = failWith;
    if (failure != null) throw failure;
    return const DeliveryRunReport(jobId: null, destinations: []);
  }

  @override
  Future<bool> hasDueRetries() async {
    dueChecks++;
    final failure = dueCheckFailsWith;
    if (failure != null) throw failure;
    return due;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NightshadeDatabase db;
  late _CountingDelivery delivery;
  late LoggingService logger;

  setUp(() {
    db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    delivery = _CountingDelivery(db);
    logger = LoggingService();
  });

  tearDown(() async {
    await db.close();
  });

  DeliveryRetrySweeper build({Duration? interval, Duration? dueCheck}) =>
      DeliveryRetrySweeper(
        delivery: delivery,
        logger: logger,
        interval: interval ?? const Duration(milliseconds: 20),
        // Out of reach unless a test asks for it, so the cases about the
        // heartbeat count the heartbeat's passes and nothing else.
        dueCheckInterval: dueCheck ?? const Duration(minutes: 5),
      );

  test('start is idempotent and does not fire immediately', () async {
    final sweeper = build(interval: const Duration(seconds: 30));
    addTearDown(sweeper.stop);

    sweeper.start();
    expect(sweeper.isRunning, isTrue);
    sweeper.start();
    sweeper.start();

    // Nothing is due in the instant after start: the catch-up pass belongs to
    // the bootstraps, not to the timer's first act.
    expect(delivery.sweeps, 0);
  });

  test('a second start does not arm a second timer', () async {
    final sweeper = build(interval: const Duration(milliseconds: 20));
    addTearDown(sweeper.stop);

    sweeper.start();
    sweeper.start();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    sweeper.stop();

    // Two timers over the same interval would roughly double this. Comparing
    // against a ceiling rather than an exact count keeps the assertion honest
    // on a loaded machine.
    expect(delivery.sweeps, greaterThan(0));
    expect(
      delivery.sweeps,
      lessThanOrEqualTo(4),
      reason: 'a doubled timer would sweep about twice as often',
    );
  });

  test('stop is idempotent and ends the ticking', () async {
    final sweeper = build(interval: const Duration(milliseconds: 20));

    sweeper.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    sweeper.stop();
    sweeper.stop();
    expect(sweeper.isRunning, isFalse);

    final after = delivery.sweeps;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(delivery.sweeps, after, reason: 'a stopped sweeper never ticks');
  });

  test('a pass in flight is not overlapped by the next tick', () async {
    final sweeper = build(interval: const Duration(milliseconds: 10));
    addTearDown(sweeper.stop);
    final gate = Completer<void>();
    delivery.gate = gate;

    final first = sweeper.sweepOnce();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    // A second caller while the first holds the journal answers null rather
    // than starting a competing pass.
    expect(await sweeper.sweepOnce(), isNull);
    expect(delivery.sweeps, 1);

    gate.complete();
    expect(await first, isNotNull);
    expect(sweeper.isSweeping, isFalse);
  });

  test(
    'a throwing sweep releases the latch and leaves the timer armed',
    () async {
      final sweeper = build(interval: const Duration(seconds: 30));
      addTearDown(sweeper.stop);
      sweeper.start();
      delivery.failWith = StateError('the journal is unreadable');

      expect(await sweeper.sweepOnce(), isNull);
      expect(sweeper.isSweeping, isFalse);
      expect(
        sweeper.isRunning,
        isTrue,
        reason: 'the next tick is the retry; a failure must not disarm it',
      );

      delivery.failWith = null;
      expect(await sweeper.sweepOnce(), isNotNull);
    },
  );

  test('a row that comes due is swept without waiting for the heartbeat',
      () async {
    // The heartbeat is put an hour out of reach, so the only thing that can
    // sweep here is the short cadence noticing the row.
    final sweeper = build(
      interval: const Duration(hours: 1),
      dueCheck: const Duration(milliseconds: 10),
    );
    addTearDown(sweeper.stop);

    sweeper.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(
      delivery.dueChecks,
      greaterThan(0),
      reason: 'the journal is asked on the short cadence',
    );
    expect(
      delivery.sweeps,
      0,
      reason: 'nothing is due, so nothing re-reads a file or opens a transport',
    );

    delivery.due = true;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    sweeper.stop();

    expect(
      delivery.sweeps,
      greaterThan(0),
      reason: 'the row was due; waiting out the heartbeat is the defect',
    );
  });

  test('the due check does not start a pass over a pass already running',
      () async {
    final sweeper = build(
      interval: const Duration(hours: 1),
      dueCheck: const Duration(milliseconds: 10),
    );
    addTearDown(sweeper.stop);
    final gate = Completer<void>();
    delivery.gate = gate;
    delivery.due = true;

    final first = sweeper.sweepOnce();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    sweeper.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(delivery.sweeps, 1, reason: 'the running pass owns those rows');
    expect(
      delivery.dueChecks,
      0,
      reason: 'the journal is not even read while a pass holds it',
    );

    gate.complete();
    expect(await first, isNotNull);
  });

  test('a due check the journal refuses leaves both timers armed', () async {
    final sweeper = build(
      interval: const Duration(hours: 1),
      dueCheck: const Duration(milliseconds: 10),
    );
    addTearDown(sweeper.stop);
    delivery.dueCheckFailsWith = StateError('the journal is unreadable');

    sweeper.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(delivery.dueChecks, greaterThan(1), reason: 'it keeps asking');
    expect(delivery.sweeps, 0);
    expect(sweeper.isRunning, isTrue);
  });

  test('stop ends the due check as well as the heartbeat', () async {
    final sweeper = build(
      interval: const Duration(hours: 1),
      dueCheck: const Duration(milliseconds: 10),
    );

    sweeper.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    sweeper.stop();
    final asked = delivery.dueChecks;
    expect(asked, greaterThan(0));

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      delivery.dueChecks,
      asked,
      reason: 'a stopped sweeper reads nothing, on either timer',
    );
  });
}
