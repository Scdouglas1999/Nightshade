/// Delivers a finished dawn job's artifacts to every enabled destination, and
/// keeps trying overnight for the ones that did not land.
///
/// Three invariants govern everything here:
///
/// * **Delivery never fails the pipeline.** The master row commits before any
///   of this runs. A NAS that is unplugged at 06:00 is a fact about the
///   network, so every failure is caught at this boundary, written to the
///   journal, and returned in the report. [deliverJobArtifacts] and
///   [sweepDueRetries] do not throw.
/// * **The journal is the only state.** Retries are decided from
///   `delivery_journal` rows — `attempts` and `updated_at` — never from
///   anything held in memory, so a rig that reboots at 04:00 resumes exactly
///   the schedule the dead process was on.
/// * **Nightshade copies, it does not move.** No source file is renamed,
///   deleted, or truncated by delivery, on any transport, on any outcome.
library;

import 'dart:async';

import '../../database/daos/delivery_journal_dao.dart';
import '../../database/daos/delivery_targets_dao.dart';
import '../../models/darkroom/delivery.dart';
import '../logging_service.dart';
import 'artifact_transport.dart';
import 'delivery_artifact.dart';
import 'delivery_failure.dart';
import 'delivery_retry_policy.dart';
import 'delivery_transport_factory.dart';

/// Whether the caller has asked to stop. Checked between files, because a
/// transport that is mid-upload owns its own timeout.
typedef DeliveryCancellation = bool Function();

/// Whether [isCancelled] says to stop.
///
/// A caller that passed none has not asked to stop; that reading is stated
/// here once rather than as a fallback at each call site.
bool _stopRequested(DeliveryCancellation? isCancelled) =>
    isCancelled != null && isCancelled();

/// What happened to one destination on one pass.
class DeliveryDestinationReport {
  /// The destination row's id.
  final int targetId;

  /// The destination's operator-facing name, as the morning report prints it.
  final String name;

  /// The transport it delivers over.
  final ArtifactDestinationKind kind;

  /// Files that arrived and verified on this pass.
  final int delivered;

  /// Files published for a paired desktop that has not pulled them yet.
  final int awaitingPull;

  /// Files that did not land and are due another attempt.
  final int retrying;

  /// Files whose attempts are spent, or whose failure no retry can change.
  final int failed;

  /// One sentence per problem, each naming the mechanism.
  final List<String> problems;

  const DeliveryDestinationReport({
    required this.targetId,
    required this.name,
    required this.kind,
    required this.delivered,
    required this.awaitingPull,
    required this.retrying,
    required this.failed,
    required this.problems,
  });

  /// Total files this destination was asked to take on this pass.
  int get attempted => delivered + awaitingPull + retrying + failed;

  /// The morning report's line for this destination.
  String get summary {
    if (attempted == 0) return '$name: nothing selected';
    final parts = <String>[
      if (delivered > 0) '$delivered delivered',
      if (awaitingPull > 0) '$awaitingPull awaiting pull',
      if (retrying > 0) '$retrying retrying',
      if (failed > 0) '$failed failed',
    ];
    return '$name: ${parts.join(', ')}';
  }
}

/// What happened on one delivery pass.
class DeliveryRunReport {
  /// The job the pass was for, or null for a sweep spanning jobs.
  final int? jobId;

  /// One entry per destination the pass touched.
  final List<DeliveryDestinationReport> destinations;

  const DeliveryRunReport({required this.jobId, required this.destinations});

  /// Files that arrived and verified.
  int get delivered => destinations.fold<int>(0, (sum, d) => sum + d.delivered);

  /// Files published for a peer that has not pulled them yet.
  int get awaitingPull =>
      destinations.fold<int>(0, (sum, d) => sum + d.awaitingPull);

  /// Files due another attempt.
  int get retrying => destinations.fold<int>(0, (sum, d) => sum + d.retrying);

  /// Files that will not be attempted again.
  int get failed => destinations.fold<int>(0, (sum, d) => sum + d.failed);

  /// True when every file this pass touched reached a destination.
  bool get everythingLanded => retrying == 0 && failed == 0;

  /// The morning report's paragraph.
  String get summary => destinations.isEmpty
      ? 'No delivery destination is enabled'
      : destinations.map((d) => d.summary).join('; ');
}

/// Runs deliveries and owns the journal that records them.
class DeliveryService {
  final DeliveryTargetsDao _targets;
  final DeliveryJournalDao _journal;
  final ArtifactTransportFactory _transportFactory;
  final DeliveryRetryPolicy _policy;
  final LoggingService? _logger;
  final DateTime Function() _clock;

  DeliveryService({
    required DeliveryTargetsDao targets,
    required DeliveryJournalDao journal,
    required ArtifactTransportFactory transportFactory,
    DeliveryRetryPolicy policy = DeliveryRetryPolicy.standard,
    LoggingService? logger,
    DateTime Function()? clock,
  }) : _targets = targets,
       _journal = journal,
       _transportFactory = transportFactory,
       _policy = policy,
       _logger = logger,
       _clock = clock ?? DateTime.now;

  /// Deliver [set] to every enabled destination that selected each artifact.
  ///
  /// Returns what happened. Never throws: a destination that fails is a line
  /// in the report and a row in the journal.
  Future<DeliveryRunReport> deliverJobArtifacts(
    DeliveryArtifactSet set, {
    DeliveryCancellation? isCancelled,
  }) async {
    final List<ArtifactDestination> destinations;
    try {
      destinations = await _targets.listEnabled();
    } catch (error, stack) {
      // The destination list is unreadable, so nothing can be delivered and
      // nothing can be journalled. The pipeline still finishes: this is
      // reported, not raised.
      _logger?.error(
        'Delivery could not read its destination list: $error',
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
      return DeliveryRunReport(jobId: set.jobId, destinations: const []);
    }

    final reports = <DeliveryDestinationReport>[];
    for (final destination in destinations) {
      final selected = set.selectedFor(destination);
      if (selected.isEmpty) continue;
      reports.add(
        await _runDestination(
          destination: destination,
          jobId: set.jobId,
          files: selected,
          isCancelled: isCancelled,
        ),
      );
    }
    return DeliveryRunReport(jobId: set.jobId, destinations: reports);
  }

  /// Re-attempt every journal row that is due, across every job.
  ///
  /// This is the overnight sweep. It reads its whole work list out of the
  /// journal, so it makes the same decisions after a restart that the process
  /// that died would have made, and it re-reads each source file from disk
  /// because the journal records the path, not the bytes.
  Future<DeliveryRunReport> sweepDueRetries({
    DeliveryCancellation? isCancelled,
  }) async {
    final now = _clock().toUtc();
    final List<DeliveryJournalEntry> pending;
    try {
      pending = await _journal.listPendingRetry();
    } catch (error, stack) {
      _logger?.error(
        'The delivery retry sweep could not read the journal: $error',
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
      return const DeliveryRunReport(jobId: null, destinations: []);
    }

    final byTarget = <int, List<DeliveryJournalEntry>>{};
    for (final entry in pending) {
      byTarget.putIfAbsent(entry.targetId, () => []).add(entry);
    }

    final reports = <DeliveryDestinationReport>[];
    for (final targetId in byTarget.keys) {
      final destination = await _targets.getById(targetId);
      if (destination == null) continue;
      final rows = byTarget[targetId]!;
      reports.add(
        await _sweepDestination(
          destination: destination,
          rows: rows,
          now: now,
          isCancelled: isCancelled,
        ),
      );
    }
    return DeliveryRunReport(jobId: null, destinations: reports);
  }

  Future<DeliveryDestinationReport> _runDestination({
    required ArtifactDestination destination,
    required int jobId,
    required List<DeliveryFile> files,
    required DeliveryCancellation? isCancelled,
  }) async {
    final targetId = destination.id;
    if (targetId == null) {
      return DeliveryDestinationReport(
        targetId: 0,
        name: destination.name,
        kind: destination.kind,
        delivered: 0,
        awaitingPull: 0,
        retrying: 0,
        failed: files.length,
        problems: const [
          'This destination has no database row, so nothing about it can be '
              'journalled',
        ],
      );
    }

    final tally = _Tally(destination, targetId);
    final transport = _transportFactory(destination, jobId);
    try {
      await transport.open(files);
    } catch (error, stack) {
      final failure = _asFailure(error, destination);
      _log(failure, destination, stack);
      for (final file in files) {
        await _recordOutcome(
          targetId: targetId,
          jobId: jobId,
          filePath: file.sourcePath,
          bytes: file.bytes,
          failure: failure,
          tally: tally,
        );
      }
      await _closeQuietly(transport, tally);
      return tally.build();
    }

    for (final file in files) {
      if (_stopRequested(isCancelled)) {
        await _recordOutcome(
          targetId: targetId,
          jobId: jobId,
          filePath: file.sourcePath,
          bytes: file.bytes,
          failure: const DeliveryFailure(
            DeliveryFailureKind.cancelled,
            'Delivery stopped before this file was sent',
          ),
          tally: tally,
        );
        continue;
      }
      await _deliverOne(
        transport: transport,
        targetId: targetId,
        jobId: jobId,
        file: file,
        destination: destination,
        tally: tally,
      );
    }

    await _closeQuietly(transport, tally);
    return tally.build();
  }

  Future<DeliveryDestinationReport> _sweepDestination({
    required ArtifactDestination destination,
    required List<DeliveryJournalEntry> rows,
    required DateTime now,
    required DeliveryCancellation? isCancelled,
  }) async {
    final targetId = destination.id ?? rows.first.targetId;
    final tally = _Tally(destination, targetId);

    if (destination.kind == ArtifactDestinationKind.peer) {
      // A peer row is published and waiting for the desktop to pull it, not
      // owed another attempt. Counting it as a retry would burn the budget on
      // work the rig is not the one doing.
      tally.awaitingPull += rows.length;
      return tally.build();
    }
    if (!destination.enabled) {
      tally.retrying += rows.length;
      tally.problems.add(
        '${rows.length} file(s) are paused: ${destination.name} is switched '
        'off, so no attempt was made and no attempt was spent',
      );
      return tally.build();
    }

    final due = rows.where((row) => _policy.isDue(row, now)).toList();
    tally.retrying += rows.length - due.length;
    if (due.isEmpty) return tally.build();

    final files = <DeliveryFile>[];
    for (final row in due) {
      try {
        files.add(await DeliveryFile.describe(row.filePath));
      } catch (error, stack) {
        final failure = _asFailure(error, destination);
        _log(failure, destination, stack);
        await _recordOutcome(
          targetId: targetId,
          jobId: row.jobId,
          filePath: row.filePath,
          bytes: row.bytes,
          failure: failure,
          tally: tally,
        );
      }
    }
    if (files.isEmpty) return tally.build();

    final jobIdByPath = <String, int>{
      for (final row in due) row.filePath: row.jobId,
    };
    final transport = _transportFactory(destination, due.first.jobId);
    try {
      await transport.open(files);
    } catch (error, stack) {
      final failure = _asFailure(error, destination);
      _log(failure, destination, stack);
      for (final file in files) {
        await _recordOutcome(
          targetId: targetId,
          jobId: jobIdByPath[file.sourcePath]!,
          filePath: file.sourcePath,
          bytes: file.bytes,
          failure: failure,
          tally: tally,
        );
      }
      await _closeQuietly(transport, tally);
      return tally.build();
    }

    for (final file in files) {
      if (_stopRequested(isCancelled)) {
        tally.retrying++;
        continue;
      }
      await _deliverOne(
        transport: transport,
        targetId: targetId,
        jobId: jobIdByPath[file.sourcePath]!,
        file: file,
        destination: destination,
        tally: tally,
      );
    }

    await _closeQuietly(transport, tally);
    return tally.build();
  }

  Future<void> _deliverOne({
    required ArtifactTransport transport,
    required int targetId,
    required int jobId,
    required DeliveryFile file,
    required ArtifactDestination destination,
    required _Tally tally,
  }) async {
    // The attempt is recorded BEFORE the bytes move. A process killed
    // mid-transfer therefore leaves a row that the sweep re-picks, rather than
    // a file nothing remembers trying.
    final DeliveryJournalEntry attempt;
    try {
      attempt = await _journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: file.sourcePath,
        bytes: file.bytes,
        now: _clock(),
      );
    } catch (error, stack) {
      _logger?.error(
        'The delivery journal could not record an attempt for '
        '${file.sourcePath}: $error',
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
      tally.retrying++;
      tally.problems.add(
        'The journal refused an attempt row for ${file.fileName}, so this '
        'file was not sent',
      );
      return;
    }

    try {
      final outcome = await transport.deliver(file);
      if (outcome.disposition == DeliveryDisposition.awaitingPull) {
        tally.awaitingPull++;
        return;
      }
      await _journal.markDelivered(
        targetId: targetId,
        jobId: jobId,
        filePath: file.sourcePath,
        checksum: outcome.checksum,
        bytes: file.bytes,
        now: _clock(),
      );
      tally.delivered++;
    } catch (error, stack) {
      final failure = _asFailure(error, destination);
      _log(failure, destination, stack);
      await _recordJournalOutcome(
        targetId: targetId,
        jobId: jobId,
        filePath: file.sourcePath,
        attempts: attempt.attempts,
        failure: failure,
        tally: tally,
      );
    }
  }

  /// Count an attempt for one file and record why it failed.
  ///
  /// The attempt is counted even when the whole destination failed to open:
  /// the budget is per file per destination, and a file whose attempts never
  /// increment is a file that retries until the end of time.
  Future<void> _recordOutcome({
    required int targetId,
    required int jobId,
    required String filePath,
    required int bytes,
    required DeliveryFailure failure,
    required _Tally tally,
  }) async {
    final DeliveryJournalEntry attempt;
    try {
      attempt = await _journal.recordAttempt(
        targetId: targetId,
        jobId: jobId,
        filePath: filePath,
        bytes: bytes,
        now: _clock(),
      );
    } catch (error, stack) {
      _logger?.error(
        'The delivery journal could not record an attempt for $filePath: '
        '$error',
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
      tally.retrying++;
      return;
    }
    await _recordJournalOutcome(
      targetId: targetId,
      jobId: jobId,
      filePath: filePath,
      attempts: attempt.attempts,
      failure: failure,
      tally: tally,
    );
  }

  Future<void> _recordJournalOutcome({
    required int targetId,
    required int jobId,
    required String filePath,
    required int attempts,
    required DeliveryFailure failure,
    required _Tally tally,
  }) async {
    final exhausted = _policy.isExhausted(attempts);
    final terminal = !failure.retryable || exhausted;
    final text = exhausted && failure.retryable
        ? '${failure.journalText} (after $attempts attempts)'
        : failure.journalText;
    try {
      if (terminal) {
        await _journal.markFailed(
          targetId: targetId,
          jobId: jobId,
          filePath: filePath,
          error: text,
          now: _clock(),
        );
        tally.failed++;
      } else {
        await _journal.markRetrying(
          targetId: targetId,
          jobId: jobId,
          filePath: filePath,
          error: text,
          now: _clock(),
        );
        tally.retrying++;
      }
    } catch (error, stack) {
      _logger?.error(
        'The delivery journal could not record the outcome for $filePath: '
        '$error',
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
      tally.retrying++;
    }
    tally.problems.add(text);
  }

  Future<void> _closeQuietly(ArtifactTransport transport, _Tally tally) async {
    try {
      await transport.close();
    } catch (error, stack) {
      // Releasing the transport failed after the deliveries were already
      // decided. The outcomes above stand; this is recorded so a leaked key
      // file or connection is visible in the report.
      _logger?.warning(
        'Closing the ${tally.destination.kind.wire} transport for '
        '${tally.destination.name} failed: $error',
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
      tally.problems.add(
        'Releasing the connection to ${tally.destination.name} failed: $error',
      );
    }
  }

  DeliveryFailure _asFailure(Object error, ArtifactDestination destination) {
    if (error is DeliveryFailure) return error;
    return DeliveryFailure(
      DeliveryFailureKind.transportFailure,
      'Delivery to ${destination.name} raised $error',
      cause: error,
    );
  }

  void _log(
    DeliveryFailure failure,
    ArtifactDestination destination,
    StackTrace stack,
  ) {
    final message =
        'Delivery to ${destination.name} (${destination.kind.wire}): '
        '${failure.journalText}';
    if (failure.retryable) {
      _logger?.warning(message, source: 'DeliveryService');
    } else {
      _logger?.error(
        message,
        source: 'DeliveryService',
        fields: {'stack': stack.toString()},
      );
    }
  }
}

/// Running counts for one destination on one pass.
class _Tally {
  final ArtifactDestination destination;

  /// The row id every journal write in this pass uses, resolved by the caller
  /// before any file is touched.
  final int targetId;

  int delivered = 0;
  int awaitingPull = 0;
  int retrying = 0;
  int failed = 0;
  final List<String> problems = [];

  _Tally(this.destination, this.targetId);

  DeliveryDestinationReport build() => DeliveryDestinationReport(
    targetId: targetId,
    name: destination.name,
    kind: destination.kind,
    delivered: delivered,
    awaitingPull: awaitingPull,
    retrying: retrying,
    failed: failed,
    problems: List<String>.unmodifiable(problems),
  );
}
