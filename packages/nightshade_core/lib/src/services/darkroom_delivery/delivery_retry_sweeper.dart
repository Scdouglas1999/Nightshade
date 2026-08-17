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
  }) : _delivery = delivery,
       _logger = logger,
       _interval = interval;

  final DeliveryService _delivery;
  final LoggingService _logger;

  /// How often a due row is looked for. Injected so a test drives the cadence
  /// instead of waiting out the production interval.
  final Duration _interval;

  static const _logSource = 'DeliveryRetrySweeper';

  Timer? _timer;

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
    _logger.info(
      'Started the Darkroom delivery retry sweep (every '
      '${_interval.inSeconds}s).',
      source: _logSource,
    );
  }

  /// Cancel the periodic sweep. A pass already in flight runs to its end — it
  /// owns journal rows it must finish writing — and only the scheduling stops.
  /// Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
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
