/// The overnight driver for [DeliveryService.sweepDueRetries].
///
/// The sweep itself is a pure function of the journal: it reads every row whose
/// next attempt is due and re-attempts it. What it has never had is anything to
/// call it. A destination that was unreachable when the dawn job ran — a laptop
/// asleep, a NAS rebooting, an SFTP host mid-upgrade — leaves rows marked
/// `retrying` with a due time in the future, and without this timer that due
/// time passes with nobody watching until the operator happens to start another
/// job.
///
/// **Re-entrancy is the hazard.** One sweep can span minutes (an SFTP upload of
/// a full linear master over a domestic uplink), so a naive timer would start a
/// second pass over the same rows while the first still holds them. The
/// [_sweeping] latch makes the periodic tick a no-op while a pass is in flight;
/// the journal's own due-time bookkeeping makes a pass that runs twice
/// harmless, and this latch keeps it from happening in the first place.
///
/// **The sweep never throws out of here.** It already answers with a report
/// rather than an exception, and the one thing that must not happen at 4am is a
/// timer callback that kills the isolate over a destination that is merely
/// offline.
///
/// **Two cadences, because the ladder is finer than the heartbeat.**
/// [DeliveryRetryPolicy] documents 1 m, 3 m, 9 m, 27 m, then 30 m — and a
/// single 15-minute tick made every one of those rungs read 15 minutes in a
/// live process. Measured against the release bundle: a share that came back
/// 20 seconds after a failed attempt still had nothing written to it 320
/// seconds past the row's due time, because the only thing that could notice
/// was the next heartbeat. So the timer that decides *when to look* is not the
/// timer that decides *how often to sweep*:
///
///   * the **due check** runs every [dueCheckInterval] (30 s by default, half
///     the policy's shortest rung) and asks the journal one indexed question —
///     is anything due? It sweeps only when the answer is yes, so a quiet
///     night costs one SELECT every 30 seconds and writes nothing to the log.
///     "Due" means a row a sweep would actually re-attempt: rows held by a
///     switched-off destination, and rows a paired desktop has not pulled yet,
///     are the standing state the heartbeat reports, not work this rig owes —
///     see [DeliveryService.earliestRetryDueAt]. Counting an unpulled peer file
///     made every night with one turn this check into a full sweep and one INFO
///     line every 30 seconds until the desktop woke up.
///   * the **heartbeat** runs every [interval] (15 minutes) and sweeps
///     regardless, which is what keeps the pass that reports a destination's
///     standing state — suspended rows, rows awaiting a pull — arriving on a
///     cadence an operator can recognise in the log.
library;

import 'dart:async';

import '../logging_service.dart';
import 'delivery_service.dart';

/// Periodically re-attempts the delivery rows whose retry is due, so an
/// overnight destination that comes back online is used without the operator
/// starting anything.
class DeliveryRetrySweeper {
  DeliveryRetrySweeper({
    required DeliveryService delivery,
    required LoggingService logger,
    Duration interval = const Duration(minutes: 15),
    Duration dueCheckInterval = const Duration(seconds: 30),
  }) : _delivery = delivery,
       _logger = logger,
       _interval = interval,
       _dueCheckInterval = dueCheckInterval;

  final DeliveryService _delivery;
  final LoggingService _logger;

  /// How often a pass runs whether or not anything is due. Injected so a test
  /// drives the cadence instead of waiting out the production interval.
  final Duration _interval;

  /// How often the journal is asked whether a row has come due. Finer than the
  /// policy's shortest backoff, which is what makes that rung real.
  final Duration _dueCheckInterval;

  static const _logSource = 'DeliveryRetrySweeper';

  Timer? _timer;

  /// The short-cadence due check. Armed and cancelled with [_timer].
  Timer? _dueTimer;

  /// Guards a whole pass so a slow [sweepOnce] never overlaps the next tick.
  bool _sweeping = false;

  /// True once [start] has armed the periodic sweep and [stop] has not
  /// cancelled it.
  bool get isRunning => _timer != null;

  /// True while a pass is in flight.
  bool get isSweeping => _sweeping;

  /// Arm the periodic sweep. Idempotent — a second call while running keeps the
  /// original timer rather than arming a second one over the same journal.
  ///
  /// Does not fire immediately: the retry policy's own backoff means nothing is
  /// due in the instant after start, and the startup one-shot the bootstraps run
  /// already covers the rows that were due while the process was down.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_interval, (_) => unawaited(sweepOnce()));
    _dueTimer = Timer.periodic(
      _dueCheckInterval,
      (_) => unawaited(sweepIfDue()),
    );
    _logger.info(
      'Started the Darkroom delivery retry sweep (due rows are looked for '
      'every ${_dueCheckInterval.inSeconds}s, and a pass runs every '
      '${_interval.inSeconds}s regardless).',
      source: _logSource,
    );
  }

  /// Cancel both timers. A pass already in flight runs to its end — it owns
  /// journal rows it must finish writing — and only the scheduling stops.
  /// Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _dueTimer?.cancel();
    _dueTimer = null;
  }

  /// Ask the journal whether a row has come due, and sweep only if one has.
  ///
  /// This is what makes the policy's 1 m / 3 m / 9 m ladder real: the answer
  /// costs one SELECT, so it can be asked far more often than a sweep — which
  /// re-reads every source file and opens a transport — could be run.
  ///
  /// A pass already in flight owns the rows this one would look at, so the
  /// journal is not even read; the running pass is the answer.
  Future<DeliveryRunReport?> sweepIfDue() async {
    if (_sweeping) return null;
    final bool due;
    try {
      due = await _delivery.hasDueRetries();
    } on Object catch (error, stack) {
      // The journal itself would not answer. Say so and leave the timers
      // armed: the heartbeat pass still runs, and the next check is the retry.
      _logger.warning(
        'The Darkroom delivery due-retry check could not read the journal: '
        '$error',
        source: _logSource,
        fields: {'stack': '$stack'},
      );
      return null;
    }
    if (!due) return null;
    return sweepOnce();
  }

  /// Run one pass. Returns null when a pass was already in flight, so a caller
  /// can tell "nothing was due" from "somebody else is already doing it".
  Future<DeliveryRunReport?> sweepOnce() async {
    if (_sweeping) return null;
    _sweeping = true;
    try {
      final report = await _delivery.sweepDueRetries();
      if (report.destinations.isNotEmpty) {
        _logger.info(
          'Delivery retry sweep: ${report.summary}',
          source: _logSource,
          fields: {
            'delivered': report.delivered,
            'awaitingPull': report.awaitingPull,
            'retrying': report.retrying,
            'failed': report.failed,
          },
        );
      }
      return report;
    } on Object catch (error, stack) {
      // The sweep answers with a report rather than an exception, so anything
      // arriving here is the journal or a transport factory failing outright.
      // Say so and leave the timer armed: the next tick is the retry.
      _logger.warning(
        'The Darkroom delivery retry sweep failed: $error',
        source: _logSource,
        fields: {'stack': '$stack'},
      );
      return null;
    } finally {
      _sweeping = false;
    }
  }
}
