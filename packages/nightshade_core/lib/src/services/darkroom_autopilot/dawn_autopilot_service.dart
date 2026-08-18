/// The dawn autopilot: what happens between the last sub of the night and the
/// message that wakes the operator.
///
/// The integration half has already run by the time this starts — masters exist
/// as linear FITS in the library. This service owns the interpretation half:
/// queue a durable job, compose a first-draft recipe for every master, persist
/// it, render the draft the operator wakes up to, write the night report, hand
/// the artifacts to delivery, and send one honest morning message.
///
/// **The job row is the unit of work, not this object.** Every step is bounded
/// by a `darkroom_jobs` row that survives a force quit; the open-time crash
/// recovery re-queues a row a dead process left `running`, and [drainQueue]
/// picks it up on the next start. The inputs are re-derived from the session
/// each time, so a resumed job and a fresh job run the same code.
///
/// **Cancellation is two flags, not one.** A render is a single synchronous FFI
/// descent, so Dart can only ask the engine's loops to stop; [requestCancel]
/// raises the engine's flag AND this service's own, and the second one is what
/// stops the pipeline moving on to the next master after the engine has
/// released the first.
///
/// **Delivery never fails the job.** A destination that is unreachable at 4am
/// is a line in the morning report and a row in the journal; the masters and
/// the draft are already on the rig's own disk.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../database/daos/darkroom_jobs_dao.dart';
import '../../database/daos/integrated_masters_dao.dart';
import '../../database/daos/recipes_dao.dart';
import '../../database/daos/targets_dao.dart';
import '../../models/darkroom/darkroom_job.dart';
import '../../models/darkroom/delivery.dart';
import '../../models/darkroom/recipe.dart';
import '../darkroom_delivery/delivery_artifact.dart';
import '../darkroom_delivery/delivery_failure.dart';
import '../darkroom_delivery/delivery_service.dart';
import '../logging_service.dart';
import 'darkroom_seam.dart';
import 'dawn_draft_builder.dart';
import 'dawn_job_report.dart';
import 'dawn_master_resolver.dart';
import 'dawn_morning_notifier.dart';
import 'dawn_photometry.dart';

/// What one dawn job did.
class DawnJobOutcome {
  /// The `darkroom_jobs.id` this outcome belongs to.
  final int jobId;

  /// The job's final state.
  final DarkroomJobState state;

  /// The morning report, or null when the job stopped before one could be
  /// composed.
  final DawnJobReport? report;

  /// Absolute path of the written night report, or null when none was written.
  final String? reportPath;

  /// Why the job failed, or null when it did not.
  final String? failure;

  const DawnJobOutcome({
    required this.jobId,
    required this.state,
    required this.report,
    required this.reportPath,
    required this.failure,
  });

  /// True when the job ran to the end.
  bool get succeeded => state == DarkroomJobState.done;
}

/// The dawn pipeline stopped because cancellation was requested.
///
/// Distinct from a failure: the operator asked, and the job obeyed. It is
/// internal to the pipeline — callers read [DawnJobOutcome.state].
class _DawnCancelled implements Exception {
  final String where;

  const _DawnCancelled(this.where);

  @override
  String toString() => 'The dawn job stopped during $where on request';
}

/// Orchestrates the dawn Darkroom pass over a night's masters.
class DawnAutopilotService {
  final DarkroomJobsDao _jobs;
  final RecipesDao _recipes;
  final IntegratedMastersDao _masters;
  final TargetsDao _targets;
  final DawnMasterResolver _resolver;
  final DawnDraftBuilder _drafts;
  final DarkroomSeam _darkroom;
  final DawnPhotometryResolver _photometry;
  final DeliveryService _delivery;
  final DawnMorningNotifier _notifier;
  final Future<String> Function() _outputDirectory;
  final LoggingService? _logger;
  final DateTime Function() _clock;

  /// Job ids the operator has asked to stop. Membership outlives any one
  /// native render, which is what stops the pipeline advancing to the next
  /// master after the engine has released its own flag.
  final Set<int> _cancelRequested = <int>{};

  /// The stage each running job is in, in the words the failure sentence uses.
  /// The catch-all cannot see where in the descent an exception came from, so
  /// the pipeline records where it is as it goes.
  final Map<int, String> _stage = <int, String>{};

  /// How many times a state-mark write is retried after a refusal before the
  /// failure is let out.
  static const int _markRetryAttempts = 5;

  /// The first retry delay; it doubles on each further attempt, so five
  /// retries span a little under eight seconds in total.
  static const Duration _markRetryFirstDelay = Duration(milliseconds: 250);

  /// Longest error detail carried into the operator-facing failure text, and
  /// how that budget splits either side of the elision when it is exceeded.
  static const int _failureDetailLimit = 160;
  static const int _failureDetailHead = 100;
  static const int _failureDetailTail =
      _failureDetailLimit - _failureDetailHead - 1;

  DawnAutopilotService({
    required DarkroomJobsDao jobs,
    required RecipesDao recipes,
    required IntegratedMastersDao masters,
    required TargetsDao targets,
    required DawnMasterResolver resolver,
    required DawnDraftBuilder drafts,
    required DarkroomSeam darkroom,
    required DawnPhotometryResolver photometry,
    required DeliveryService delivery,
    required DawnMorningNotifier notifier,
    required Future<String> Function() outputDirectory,
    LoggingService? logger,
    DateTime Function()? clock,
  }) : _jobs = jobs,
       _recipes = recipes,
       _masters = masters,
       _targets = targets,
       _resolver = resolver,
       _drafts = drafts,
       _darkroom = darkroom,
       _photometry = photometry,
       _delivery = delivery,
       _notifier = notifier,
       _outputDirectory = outputDirectory,
       _logger = logger,
       _clock = clock ?? DateTime.now;

  /// The cancellation handle the native side knows [jobId] by.
  ///
  /// Derived from the job id alone so a restart can still stop a job it did not
  /// start: the id is in the durable row, not in this process's memory.
  static String renderIdFor(int jobId) => 'darkroom-job-$jobId';

  /// Queue and run the dawn pass for [sessionId].
  ///
  /// The job is `dawn`, so it sends the morning notification when it finishes.
  Future<DawnJobOutcome> runDawnForSession(int sessionId) async {
    final jobId = await _jobs.enqueue(
      sessionId: sessionId,
      kind: DarkroomJobKind.dawn,
      note: 'Queued by the dawn autopilot',
      createdAt: _clock(),
    );
    return runJob(jobId);
  }

  /// Queue and run an operator-requested pass over [sessionId] — the
  /// "process this session now" action.
  ///
  /// The job is `manual`, so it produces the same drafts, the same report and
  /// the same delivery, and sends NO morning notification: the operator is
  /// standing at the machine and does not need to be told what they just asked
  /// for.
  Future<DawnJobOutcome> processSessionNow(int sessionId) async {
    final jobId = await _jobs.enqueue(
      sessionId: sessionId,
      kind: DarkroomJobKind.manual,
      note: 'Queued on request',
      createdAt: _clock(),
    );
    return runJob(jobId);
  }

  /// Run every queued job, oldest first.
  ///
  /// This is what picks up the rows the open-time crash recovery re-queued.
  /// Jobs run one at a time: two Darkroom renders over the same master would
  /// fight for the render cache and for the one cancellation id.
  ///
  /// **One job cannot end the drain.** Every job runs behind its own guard, so
  /// a row this process cannot even record the failure of — a database locked
  /// by another writer is the case that happens — costs that job and nothing
  /// else. The queue behind it still runs.
  ///
  /// **Every id is offered once.** A job whose run threw before it could leave
  /// `queued` is still the oldest queued row, so taking "the oldest" again
  /// would hand back the same job forever. The queue is re-read each pass and
  /// the first id not yet tried is taken, which keeps the oldest-first order,
  /// picks up anything enqueued while the drain ran, and leaves the row that
  /// could not start `queued` for the next open to recover.
  Future<List<DawnJobOutcome>> drainQueue() async {
    final outcomes = <DawnJobOutcome>[];
    final tried = <int>{};
    while (true) {
      int? next;
      for (final job in await _jobs.listByState(DarkroomJobState.queued)) {
        final id = job.id;
        if (id == null || tried.contains(id)) continue;
        next = id;
        break;
      }
      if (next == null) break;
      tried.add(next);
      try {
        outcomes.add(await runJob(next));
      } catch (error, stack) {
        _logger?.error(
          'The dawn job could not be run or recorded; the rest of the queue '
          'still runs',
          source: 'DawnAutopilotService',
          fields: {'jobId': next, 'error': '$error', 'stack': '$stack'},
        );
      }
    }
    return outcomes;
  }

  /// Ask [jobId] to stop.
  ///
  /// A queued job is cancelled outright — no executor holds it, so there is
  /// nothing to wait for. A running job has the engine's flag raised for its
  /// render id and this service's own flag set; the render stops at its next
  /// poll and the pipeline stops before the next master.
  Future<void> requestCancel(int jobId, {String? reason}) async {
    _cancelRequested.add(jobId);
    final job = await _jobs.getById(jobId);
    if (job == null) throw DarkroomJobMissingException(jobId);
    if (job.state.isTerminal) return;

    try {
      await _darkroom.cancel({'op': 'cancel', 'renderId': renderIdFor(jobId)});
    } on DarkroomSeamException catch (error) {
      // The engine could not take the flag. The service's own flag still
      // stops the pipeline between stages, so say what was lost rather than
      // reporting a clean stop: a render already inside Rust runs to its end.
      _logger?.warning(
        'The Darkroom engine did not take the cancellation flag; the job stops '
        'between stages instead of mid-render',
        source: 'DawnAutopilotService',
        fields: {'jobId': jobId, 'error': error.message},
      );
    }

    if (job.state == DarkroomJobState.queued) {
      await _jobs.markCancelled(
        jobId,
        reason: reason ?? 'Cancelled before the job started',
        now: _clock(),
      );
    }
  }

  /// Run the job [jobId] holds.
  ///
  /// Never throws: every ending — done, cancelled, failed — is recorded on the
  /// row and returned. A thrown pipeline would leave the row `running` with no
  /// executor, which the crash recovery would then re-queue as though the
  /// process had died.
  Future<DawnJobOutcome> runJob(int jobId) async {
    final job = await _jobs.getById(jobId);
    if (job == null) throw DarkroomJobMissingException(jobId);
    if (_cancelRequested.contains(jobId)) {
      final cancelled = await _jobs.markCancelled(
        jobId,
        reason: 'Cancelled before the job started',
        now: _clock(),
      );
      return DawnJobOutcome(
        jobId: jobId,
        state: cancelled.state,
        report: null,
        reportPath: null,
        failure: cancelled.errorText,
      );
    }

    // The row is taken BEFORE the inputs are checked, because a job with no
    // session is a spent attempt like any other: `queued` may only become
    // `running` or `cancelled`, and a failure that never ran would have to
    // pretend the job was never picked up.
    final startedAt = _clock();
    await _jobs.markRunning(jobId, now: startedAt);

    _stage[jobId] = 'reading the job row';
    final sessionId = job.sessionId;
    if (sessionId == null) {
      final failed = await _markFailed(
        jobId,
        'This job names no imaging session, so there is nothing to process',
      );
      return DawnJobOutcome(
        jobId: jobId,
        state: failed.state,
        report: null,
        reportPath: null,
        failure: failed.errorText,
      );
    }

    try {
      return await _drive(
        jobId: jobId,
        kind: job.kind,
        sessionId: sessionId,
        startedAt: startedAt,
      );
    } on _DawnCancelled catch (stop) {
      final cancelled = await _jobs.markCancelled(
        jobId,
        reason: 'Stopped on request during ${stop.where}',
        now: _clock(),
      );
      return DawnJobOutcome(
        jobId: jobId,
        state: cancelled.state,
        report: null,
        reportPath: null,
        failure: cancelled.errorText,
      );
    } on DarkroomCancelledOutcome catch (stop) {
      final cancelled = await _jobs.markCancelled(
        jobId,
        reason: 'Stopped on request during the ${stop.phase} phase',
        now: _clock(),
      );
      return DawnJobOutcome(
        jobId: jobId,
        state: cancelled.state,
        report: null,
        reportPath: null,
        failure: cancelled.errorText,
      );
    } on DarkroomJobNotRunningException catch (lost) {
      // Something else moved the row out from under this executor. Report it;
      // do not write over whatever decided the job's fate.
      _logger?.warning(
        'The dawn job left this executor before it finished',
        source: 'DawnAutopilotService',
        fields: {'jobId': jobId, 'state': lost.state.wire},
      );
      return DawnJobOutcome(
        jobId: jobId,
        state: lost.state,
        report: null,
        reportPath: null,
        failure: '$lost',
      );
    } catch (error, stack) {
      final stage = _stage[jobId] ?? 'running the dawn pass';
      // The exception, its type and its stack go here — the log is where a
      // `SqliteException` with its causing statement belongs. The row gets the
      // sentence below, which names the stage that stopped.
      _logger?.error(
        'The dawn job failed while $stage',
        source: 'DawnAutopilotService',
        fields: {
          'jobId': jobId,
          'stage': stage,
          'errorType': error.runtimeType.toString(),
          'error': '$error',
          'stack': '$stack',
        },
      );
      final failed = await _markFailed(jobId, _failureSentence(stage, error));
      return DawnJobOutcome(
        jobId: jobId,
        state: failed.state,
        report: null,
        reportPath: null,
        failure: failed.errorText,
      );
    } finally {
      _cancelRequested.remove(jobId);
      _stage.remove(jobId);
    }
  }

  /// The operator-facing sentence for a stopped job: the stage that stopped,
  /// and the error's own opening line.
  ///
  /// Only the first line, and only up to [_failureDetailLimit] characters of
  /// it. A raw `SqliteException` carries its causing SQL statement and every
  /// bound parameter on the following lines, which is diagnostic text for the
  /// log, not something to hand an operator reading a job row at 7am. The whole
  /// exception is logged beside this, so nothing is lost.
  ///
  /// An over-long line is elided in the MIDDLE, not cut off at the end: the
  /// head carries the exception's own name and the tail carries what a message
  /// built around a long path ends with — `(OS Error: Permission denied)` —
  /// which is the half that says what to do about it.
  static String _failureSentence(String stage, Object error) {
    final first = '$error'.split('\n').first.trim();
    final detail = first.length <= _failureDetailLimit
        ? first
        : '${first.substring(0, _failureDetailHead)}…'
              '${first.substring(first.length - _failureDetailTail)}';
    if (detail.isEmpty) {
      return 'The dawn pass stopped while $stage; the log records the error.';
    }
    return 'The dawn pass stopped while $stage: $detail. '
        'The log records the full error.';
  }

  /// Fail [jobId] with [errorText], retrying the write while it is refused.
  ///
  /// The mark is the only record that the attempt ended. A transient refusal —
  /// another writer holding the database — would otherwise leave the row
  /// `running` with an empty error for as long as this process lives, which
  /// reads exactly like a job still working.
  Future<DarkroomJob> _markFailed(int jobId, String errorText) =>
      _withWriteRetry(
        jobId,
        'record the failure',
        () => _jobs.markFailed(jobId, errorText, now: _clock()),
      );

  /// Finish [jobId], retrying the write while it is refused — the same reason
  /// as [_markFailed]: a finished job left `running` is a job the operator is
  /// told is still going.
  Future<DarkroomJob> _markDone(int jobId, String note) => _withWriteRetry(
    jobId,
    'record the completion',
    () => _jobs.markDone(jobId, note: note, now: _clock()),
  );

  /// Run [write], retrying a refusal a bounded number of times with a doubling
  /// delay, then letting the last failure out.
  ///
  /// The bound is what makes this honest: the write is retried, never assumed.
  /// When every attempt is refused the caller still sees the exception and the
  /// row keeps whatever state it had, which the open-time crash recovery picks
  /// up on the next start.
  Future<T> _withWriteRetry<T>(
    int jobId,
    String what,
    Future<T> Function() write,
  ) async {
    var delay = _markRetryFirstDelay;
    for (var attempt = 1; ; attempt++) {
      try {
        return await write();
      } on DarkroomJobMissingException {
        rethrow;
      } on DarkroomJobTransitionException {
        rethrow;
      } catch (error) {
        if (attempt > _markRetryAttempts) {
          _logger?.error(
            'The dawn job could not $what after $attempt attempts; the row '
            'keeps its current state for the next start to recover',
            source: 'DawnAutopilotService',
            fields: {'jobId': jobId, 'error': '$error'},
          );
          rethrow;
        }
        _logger?.warning(
          'The dawn job could not $what; retrying',
          source: 'DawnAutopilotService',
          fields: {
            'jobId': jobId,
            'attempt': attempt,
            'retryInMs': delay.inMilliseconds,
            'error': '$error',
          },
        );
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  Future<DawnJobOutcome> _drive({
    required int jobId,
    required DarkroomJobKind kind,
    required int sessionId,
    required DateTime startedAt,
  }) async {
    final renderId = renderIdFor(jobId);
    _stopIfCancelled(jobId, 'the master lookup');

    _stage[jobId] = "looking up the night's masters";
    final set = await _resolver.resolve(sessionId);
    _stage[jobId] = 'preparing the Darkroom output directory';
    final baseDirectory = await _darkroomDirectory();

    var reports = <DawnMasterReport>[];

    for (var index = 0; index < set.masters.length; index++) {
      _stopIfCancelled(jobId, 'master ${index + 1} of ${set.masters.length}');
      final master = set.masters[index];
      await _reportProgress(
        jobId,
        // Drafting occupies the first four fifths of the job; delivery and the
        // report take the rest.
        0.8 * index / (set.masters.isEmpty ? 1 : set.masters.length),
        'Drafting ${master.name}',
      );
      reports.add(
        await _draftOneMaster(
          jobId: jobId,
          sessionId: sessionId,
          master: master,
          renderId: renderId,
          directory: baseDirectory,
        ),
      );
    }

    // PER-MASTER ACCOUNTING, IN TWO READINGS. Only the masters whose pixels
    // this pass actually read go to a destination; a truncated or vanished FITS
    // is excluded and named in the report, because copying it out would put a
    // file the pipeline has just called unreadable in the operator's hands
    // under the name of the night's result. The excluded master costs nobody
    // else's draft: the rest of the set still delivers.
    //
    // `pixelsWereRead` is the reading taken while the draft was composed, which
    // is minutes before anything is copied. `_stageForDelivery` takes the
    // second reading, of the files as they are NOW, and withholds any master
    // that is no longer the file this pass measured. It runs HERE, before the
    // night report is written, because that report is itself one of the
    // delivered artifacts and has to carry the exclusion it caused; the instant
    // between this reading and the copy is covered by delivery's own stat and
    // checksum of every source it takes.
    reports = await _stageForDelivery(jobId, reports);

    final linearMasters = <String>[
      for (final master in reports)
        if (master.deliverable) master.master.masterFitsPath,
    ];
    final draftRenders = <String>[
      for (final master in reports)
        if (master.draftRenderPath != null) master.draftRenderPath!,
    ];
    final excluded = <String>[
      for (final master in reports)
        if (master.notDeliveredBecause != null)
          '${master.master.name} was not delivered: '
              '${master.notDeliveredBecause}.',
    ];

    _stopIfCancelled(jobId, 'the night report');
    await _reportProgress(jobId, 0.85, 'Writing the night report');

    // THE COPY DELIVERY ITSELF SHIPS. The night report is one of the delivered
    // artifacts, so it has to be on disk before delivery runs — which means
    // this copy can never carry delivery's own outcome, nor the notification
    // that follows it. It is also the copy the operator keeps: delivery names
    // each artifact once and never overwrites a name it has handed over, so
    // the rewrite below reaches the rig's copy and not this one.
    //
    // It therefore states the gap instead of implying one. `running` was the
    // row's word borrowed for a moment the row's vocabulary cannot describe:
    // printed beside a `finishedAt` and two null outcome blocks it read as a
    // job that had stopped without finishing — the one thing that had not
    // happened — while the headline over it announced the drafts as ready.
    // `delivering` plus `pending` says what is true: the drafting is over,
    // these are its masters and drafts, the copying is still going, and the
    // rig's copy carries how it ended.
    var report = DawnJobReport(
      jobId: jobId,
      kind: kind.wire,
      sessionId: sessionId,
      startedAt: startedAt,
      finishedAt: _clock(),
      state: DawnJobReport.deliveringState,
      masters: reports,
      withoutFile: set.withoutFile,
      delivery: null,
      deliveryProblems: excluded,
      notification: null,
      failure: null,
      pending: DawnReportPending.beforeDelivery,
    );
    final reportPath = await _writeReport(baseDirectory, jobId, report);

    _stopIfCancelled(jobId, 'delivery');
    await _reportProgress(jobId, 0.9, 'Delivering the night');
    final delivered = await _deliver(
      jobId: jobId,
      linearMasters: linearMasters,
      draftRenders: draftRenders,
      reportPath: reportPath,
    );

    // A stop that landed WHILE delivery was running ends the job here, as the
    // stop it is. `_stopIfCancelled` above only covers the instant before the
    // pass starts; a stop that arrived while the files were being copied used
    // to fall straight through to `done`, so the row, the report and the
    // morning notification all announced a finished night over a delivery the
    // operator had halted part-way. The report is still written — with the
    // delivery counts, so what is outstanding is on the record — and the row
    // is marked cancelled rather than done. Nothing is lost: the files the
    // pass did not reach are owed in the journal and the retry sweep takes
    // them.
    if (_cancelRequested.contains(jobId)) {
      final pending = delivered.report?.stoppedPending ?? 0;
      final stoppedBecause = pending == 0
          ? 'Stopped on request during delivery.'
          : 'Stopped on request during delivery; $pending file'
                '${pending == 1 ? '' : 's'} are still owed and the retry '
                'sweep resumes them.';
      final stoppedReport = DawnJobReport(
        jobId: jobId,
        kind: kind.wire,
        sessionId: sessionId,
        startedAt: startedAt,
        finishedAt: _clock(),
        state: DarkroomJobState.cancelled.wire,
        masters: reports,
        withoutFile: set.withoutFile,
        delivery: delivered.report,
        deliveryProblems: [...excluded, ...delivered.problems],
        notification: null,
        failure: stoppedBecause,
      );
      final stoppedPath = await _writeReport(
        baseDirectory,
        jobId,
        stoppedReport,
      );
      final cancelled = await _jobs.markCancelled(
        jobId,
        reason: stoppedBecause,
        now: _clock(),
      );
      return DawnJobOutcome(
        jobId: jobId,
        state: cancelled.state,
        report: stoppedReport,
        reportPath: stoppedPath,
        failure: cancelled.errorText,
      );
    }

    report = DawnJobReport(
      jobId: jobId,
      kind: kind.wire,
      sessionId: sessionId,
      startedAt: startedAt,
      finishedAt: _clock(),
      state: DarkroomJobState.done.wire,
      masters: reports,
      withoutFile: set.withoutFile,
      delivery: delivered.report,
      deliveryProblems: [...excluded, ...delivered.problems],
      notification: null,
      failure: null,
    );

    // A pass that rendered NO draft did not do the thing a Darkroom pass is
    // for, so it does not end `done`. Recorded as `done` with an empty
    // `error_text` the outcome was invisible everywhere: the Session Review
    // banner paints only an ending the operator has to act on, so a night whose
    // masters were all unreadable read as "a clean night — no problems
    // detected" with nothing on the screen saying the drafting and the delivery
    // had not produced a draft. Ending it `failed` is what puts the reason on
    // the row, in the banner, and in the report — and no queue re-runs it,
    // because `drainQueue` only takes rows still `queued`.
    final zeroDraft = report.draftsRendered == 0
        ? _zeroDraftFailure(report)
        : null;
    if (zeroDraft != null) {
      report = report.withEnding(
        state: DarkroomJobState.failed.wire,
        failure: zeroDraft,
      );
    }

    await _reportProgress(jobId, 0.95, 'Sending the morning report');
    // The morning notification still goes out on a zero-draft pass: its
    // headline is already written for the empty hand ("no draft was rendered"),
    // and the pass the operator most needs told about is the one that produced
    // nothing.
    final decision = kind == DarkroomJobKind.dawn
        ? await _announce(jobId, report)
        : const DawnNotificationDecision(
            sent: false,
            reason:
                'This pass was started by hand, so it does not send a morning '
                'notification.',
          );

    report = DawnJobReport(
      jobId: jobId,
      kind: kind.wire,
      sessionId: sessionId,
      startedAt: startedAt,
      finishedAt: _clock(),
      state: zeroDraft == null
          ? DarkroomJobState.done.wire
          : DarkroomJobState.failed.wire,
      masters: reports,
      withoutFile: set.withoutFile,
      delivery: delivered.report,
      deliveryProblems: [...excluded, ...delivered.problems],
      notification: decision,
      failure: zeroDraft,
    );

    // The row is closed BEFORE the report that announces the ending is
    // written. The report is the artifact the operator reads; a report saying
    // `done` over a row that never got there is a contradiction they have no
    // way to resolve. When the mark cannot be made the report is rewritten as
    // the stop it is, and the failure path records it.
    _stage[jobId] = 'closing the job row';
    try {
      if (zeroDraft == null) {
        await _markDone(jobId, _completionNote(report));
      } else {
        // `markFailed` writes no note, and the row's note still names the last
        // stage that ran ("Sending the morning report") — which the Session
        // Review banner reads as the stage that stopped. The completion note
        // goes on while the row is still `running`, at the progress the attempt
        // actually reached, so the banner's second sentence is the ending.
        await _jobs.updateProgress(jobId, 0.95, note: _completionNote(report));
        await _markFailed(jobId, zeroDraft);
      }
    } catch (error) {
      await _writeReport(
        baseDirectory,
        jobId,
        report.withEnding(
          state: DarkroomJobState.failed.wire,
          failure: _failureSentence('closing the job row', error),
        ),
      );
      rethrow;
    }
    // Rewrite the rig's copy with the two outcomes the delivered copy was
    // written too early to hold. That copy is not rewritten — it left under a
    // name delivery has already handed over — which is why it names this one
    // as where its `delivery` and `notification` blocks live.
    final finalPath = await _writeReport(baseDirectory, jobId, report);

    return DawnJobOutcome(
      jobId: jobId,
      state: zeroDraft == null
          ? DarkroomJobState.done
          : DarkroomJobState.failed,
      report: report,
      reportPath: finalPath,
      failure: zeroDraft,
    );
  }

  /// Why a pass that rendered no draft ended where it did, built only from
  /// reasons already on the record.
  ///
  /// Each master carries the failure that stopped its own draft and the
  /// resolver names every master it could not hand over a file for; those
  /// sentences are the reason, so the ending repeats them rather than composing
  /// a cause of its own. When neither has anything to say — a session with no
  /// integrated master at all — that is what it says.
  static String _zeroDraftFailure(DawnJobReport report) {
    final reasons = <String>[
      for (final master in report.masters)
        if (master.failure != null) '${master.master.name}: ${master.failure}',
      for (final missing in report.withoutFile)
        '${missing.name}: ${missing.reason}',
    ];
    if (reasons.isEmpty) {
      return 'The Darkroom pass rendered no draft. This night has no '
          'integrated master to draft from — integrate it in Session Review, '
          'then run the pass again.';
    }
    return 'The Darkroom pass rendered no draft: ${reasons.join('; ')}.';
  }

  /// Compose, persist and render one master's first draft.
  ///
  /// A master that cannot be drafted produces a report line naming the reason
  /// and the job continues: one unreadable master must not cost the operator
  /// the drafts of every other filter. Whether the master itself is delivered
  /// is decided by the caller from [DawnMasterReport.deliverable], never here —
  /// this method's business is the draft. What it does contribute to that
  /// decision is [DawnMasterReport.sourceAtRead]: the file as it stood at the
  /// instant these pixels were read, which delivery staging compares against.
  Future<DawnMasterReport> _draftOneMaster({
    required int jobId,
    required int sessionId,
    required DawnMaster master,
    required String renderId,
    required String directory,
  }) async {
    final row = await _masters.getById(master.masterId);
    final stats = row == null
        ? DawnMasterStats.unrecorded
        : DawnMasterStats.parse(row.statsJson);
    final targetName = await _targetName(master.targetId);

    // The file as it is at the moment the pass is about to read its pixels.
    // Delivery stages the same path minutes later and compares the two; see
    // `_stageForDelivery`.
    final sourceAtRead = await DawnSourceStat.of(master.masterFitsPath);

    DawnMasterReport failed(String reason) => DawnMasterReport(
      master: master,
      targetName: targetName,
      stats: stats,
      draft: null,
      recipeId: null,
      draftRenderPath: null,
      failure: reason,
      sourceAtRead: sourceAtRead,
    );

    final photometry = row == null
        ? const DawnPhotometry.unavailable(
            'the master library row is gone, so its astrometry cannot be read',
          )
        : await _photometry.resolve(
            master: master,
            wcs: overlayFromMasterWcs(
              crval1: row.wcsCrval1,
              crval2: row.wcsCrval2,
              crpix1: row.wcsCrpix1,
              crpix2: row.wcsCrpix2,
              cd11: row.wcsCd1_1,
              cd12: row.wcsCd1_2,
              cd21: row.wcsCd2_1,
              cd22: row.wcsCd2_2,
            ),
          );

    final DawnDraft draft;
    try {
      draft = await _drafts.build(
        master: master,
        recipeId: 'job-$jobId-master-${master.masterId}',
        photometry: photometry,
        renderId: renderId,
      );
    } on DawnDraftException catch (error) {
      return failed(error.message);
    } on DarkroomSeamException catch (error) {
      return failed(error.message);
    }

    if (draft.isEmpty) {
      return DawnMasterReport(
        master: master,
        targetName: targetName,
        stats: stats,
        draft: draft,
        recipeId: null,
        draftRenderPath: null,
        failure:
            'no operation in this build could be measured from these pixels, '
            'so the draft would have been an empty stack',
        sourceAtRead: sourceAtRead,
      );
    }

    final recipeId = await _persistDraftRecipe(
      sessionId: sessionId,
      master: master,
      name: _draftName(targetName: targetName, master: master),
      stepsJson: draft.encodeStepsJson(),
      draftNotes: draft.notes,
    );

    final draftPath = p.join(
      directory,
      'job_${jobId}_master_${master.masterId}_draft.jpg',
    );
    try {
      await _darkroom.renderExport(
        recipeJson: draft.encodeRecipeJson('$recipeId'),
        args: {
          'masterPath': master.masterFitsPath,
          'renderId': renderId,
          'stage': {'kind': 'final'},
          'outputs': [
            {'format': 'jpeg', 'path': draftPath, 'quality': 92},
          ],
          'sidecarPath': '$draftPath.nsrecipe',
          'writeSidecar': true,
          // A draft whose stack never left the linear stage has no display
          // mapping of its own; this asks the engine for its own auto stretch
          // and the reply states that it did so. It changes nothing when the
          // draft ends stretched, which is the normal case.
          'screenTransfer': true,
          'catalogStars': photometry.stars,
        },
      );
    } on DarkroomSeamException catch (error) {
      return DawnMasterReport(
        master: master,
        targetName: targetName,
        stats: stats,
        draft: draft,
        recipeId: recipeId,
        draftRenderPath: null,
        failure:
            'the recipe was saved but the draft image could not be rendered: '
            '${error.message}',
        sourceAtRead: sourceAtRead,
      );
    }

    return DawnMasterReport(
      master: master,
      targetName: targetName,
      stats: stats,
      draft: draft,
      recipeId: recipeId,
      draftRenderPath: draftPath,
      failure: null,
      sourceAtRead: sourceAtRead,
    );
  }

  /// The name a first draft carries, from the target and the filter it covers.
  ///
  /// A library where every autopilot row reads `Draft` is a library the
  /// operator cannot pick a night out of. The target names the field and the
  /// filter names the channel; with no target row the master's own name
  /// already carries the filter, so it is used whole rather than repeated.
  static String _draftName({
    required String? targetName,
    required DawnMaster master,
  }) {
    final target = targetName?.trim();
    if (target == null || target.isEmpty) return '${master.name} draft';
    final filter = master.filter?.trim();
    if (filter == null || filter.isEmpty) return '$target draft';
    return '$target $filter draft';
  }

  /// Write this pass's draft for [master], superseding the row a dead attempt
  /// left behind rather than adding a second one.
  ///
  /// **Why supersede and not delete.** The recipes table records no job id, so
  /// "the rows the dead attempt created" can only be identified by what they
  /// are: the autopilot's own root draft over this master, for this session.
  /// That row is re-derived from the same master by the resumed attempt, so
  /// rewriting its steps says exactly what happened — one draft per master,
  /// carrying this attempt's measurements. Deleting instead would break every
  /// deep link the earlier attempt's notification already sent, and
  /// [RecipesDao.deleteRecipe] refuses a row with branches anyway.
  ///
  /// **A branched row is never touched.** Once the operator has branched from a
  /// draft, its step list is the base their branch's `divergence_index` counts
  /// into; rewriting it would leave the branch describing a lineage that never
  /// happened. Those get a fresh row, which is the honest record of a second
  /// draft existing.
  ///
  /// The write is three statements — the steps, the name, then the draft's own
  /// account — because the DAO exposes them separately and none is worth a
  /// transaction the DAO does not offer: the steps are what the draft IS, and a
  /// name or an account that lags them by a statement is describing the same
  /// pass a moment later.
  ///
  /// [draftNotes] rides with the row rather than only into the night report.
  /// The report is a file on disk that the editor never opens, so until this
  /// was persisted the dawn draft arrived in the Darkroom with every reason it
  /// had recorded — including why a mono master got no colour calibration —
  /// stripped off.
  Future<int> _persistDraftRecipe({
    required int sessionId,
    required DawnMaster master,
    required String name,
    required String stepsJson,
    required List<DawnDraftNote> draftNotes,
  }) async {
    final now = _clock();
    for (final existing in await _recipes.listForMaster(
      master.masterFitsPath,
    )) {
      final id = existing.id;
      if (id == null) continue;
      if (existing.createdBy != RecipeAuthor.autopilot) continue;
      if (existing.sessionId != sessionId) continue;
      if (existing.parentRecipeId != null) continue;
      if ((await _recipes.childrenOf(id)).isNotEmpty) continue;
      await _recipes.updateSteps(
        id,
        stepsJson,
        schemaVersion: kRecipeSchemaVersion,
        now: now,
      );
      await _recipes.rename(id, name, now: now);
      await _recipes.setDraftNotes(id, _recipeNotes(draftNotes), now: now);
      return id;
    }
    return _recipes.create(
      targetId: master.targetId,
      sessionId: sessionId,
      masterId: master.masterId,
      baseMasterPath: master.masterFitsPath,
      name: name,
      stepsJson: stepsJson,
      createdBy: RecipeAuthor.autopilot,
      draftNotes: _recipeNotes(draftNotes),
      schemaVersion: kRecipeSchemaVersion,
      createdAt: now,
    );
  }

  /// The draft's account in the shape the recipe row stores.
  ///
  /// Every note is carried, `included` ones as well: the account is the record
  /// of what the composing pass DECIDED, and a row that carries one is a row
  /// the registry composed — which is how the editor can say a stack was
  /// drafted rather than written by hand, however many operations it left out.
  static List<RecipeDraftNote> _recipeNotes(List<DawnDraftNote> notes) => [
    for (final note in notes)
      RecipeDraftNote(
        opId: note.opId,
        outcome: note.outcome,
        reason: note.reason,
      ),
  ];

  /// Take the second reading of every master this pass would deliver, and
  /// withhold the ones that are no longer the file the pass measured.
  ///
  /// **Why a second reading exists at all.** The draft stage opens a master,
  /// reads its pixels and composes from them; delivery copies the bytes that
  /// are on disk when it runs, which is a separate instant. Between the two the
  /// file can be truncated, replaced or removed — by a disk filling up, by an
  /// operator tidying a captures folder, by a sync tool — and the pass's draft
  /// verdict says nothing about that. Without this reading such a master rode
  /// out under the night's name with a checksum of bytes nothing had measured,
  /// and the report called the delivery clean.
  ///
  /// **What counts as changed.** Size or modification time, either one. Both
  /// come from one `stat`, neither can be read as "probably still fine", and a
  /// dawn pass has no legitimate writer of its own masters — so a difference is
  /// the file having become a different file, and it is stated as exactly that.
  /// A master that cannot be stat-ed at all in either reading is named for that
  /// instead of being guessed at.
  ///
  /// Only masters the draft stage already cleared are read again: one that
  /// failed there is out for its own reason and re-reading it would replace a
  /// precise sentence with a vaguer one.
  Future<List<DawnMasterReport>> _stageForDelivery(
    int jobId,
    List<DawnMasterReport> reports,
  ) async {
    final staged = <DawnMasterReport>[];
    for (final report in reports) {
      if (!report.pixelsWereRead) {
        staged.add(report);
        continue;
      }
      final path = report.master.masterFitsPath;
      final atRead = report.sourceAtRead;
      final now = await DawnSourceStat.of(path);
      final String? refusal;
      if (now == null) {
        refusal =
            'it is no longer on disk at $path, so the pass has nothing to '
            'deliver under this name';
      } else if (atRead == null) {
        refusal =
            'the pass could not measure $path when it read its pixels, so '
            'there is nothing to check the ${now.bytes} bytes now on disk '
            'against';
      } else if (!atRead.matches(now)) {
        refusal =
            'the file changed after the pass read it ($path was '
            '${atRead.bytes} bytes, modified '
            '${atRead.modified.toUtc().toIso8601String()}, when its pixels '
            'were read and is ${now.bytes} bytes, modified '
            '${now.modified.toUtc().toIso8601String()}, now), so what is on '
            'disk is not what this pass measured';
      } else {
        refusal = null;
      }
      if (refusal == null) {
        staged.add(report);
        continue;
      }
      _logger?.warning(
        'A master changed between the draft that measured it and delivery, so '
        'it is withheld from every destination',
        source: 'DawnAutopilotService',
        fields: {
          'jobId': jobId,
          'master': report.master.name,
          'path': path,
          'bytesAtRead': atRead?.bytes,
          'bytesAtStaging': now?.bytes,
          'reason': refusal,
        },
      );
      staged.add(report.withheldAtStaging(refusal));
    }
    return staged;
  }

  /// Hand the night's artifacts to delivery.
  ///
  /// Never throws and never fails the job: [DeliveryService] answers with a
  /// report rather than an exception, and a source file that vanished between
  /// integration and delivery is reported here as the problem it is.
  ///
  /// **One missing file costs only itself.** [DeliveryArtifactSet.build] stats
  /// and hashes every source and raises on the first it cannot read, which
  /// would take the good drafts and the night report down with one master that
  /// went missing after it was drafted. Each artifact is described on its own
  /// here, so the set that reaches delivery is exactly the files that are
  /// there, and the ones that are not are named. The set keeps
  /// [DeliveryArtifactSet.build]'s order — by artifact class, then by the order
  /// listed — so two runs of one job deliver in the same order.
  Future<({DeliveryRunReport? report, List<String> problems})> _deliver({
    required int jobId,
    required List<String> linearMasters,
    required List<String> draftRenders,
    required String? reportPath,
  }) async {
    final sources = <ArtifactContent, List<String>>{
      ArtifactContent.linearMasters: linearMasters,
      ArtifactContent.draftRender: draftRenders,
      if (reportPath != null) ArtifactContent.nightReport: [reportPath],
    };
    final artifacts = <DeliveryArtifact>[];
    final problems = <String>[];
    for (final content in ArtifactContent.values) {
      for (final path in sources[content] ?? const <String>[]) {
        try {
          artifacts.add(
            await DeliveryArtifact.describeArtifact(
              content: content,
              path: path,
            ),
          );
        } on DeliveryFailure catch (error) {
          problems.add(
            '${p.basename(path)} was not delivered: '
            '${error.message}.',
          );
          _logger?.warning(
            'A dawn artifact could not be handed to delivery; the rest of the '
            'set still goes',
            source: 'DawnAutopilotService',
            fields: {
              'jobId': jobId,
              'path': path,
              'content': content.wire,
              'error': error.message,
            },
          );
        }
      }
    }
    if (artifacts.isEmpty) {
      return (
        report: null,
        problems: <String>[
          ...problems,
          'Nothing was delivered: this job produced no file that could be '
              'read at delivery time.',
        ],
      );
    }

    final report = await _delivery.deliverJobArtifacts(
      DeliveryArtifactSet(jobId: jobId, artifacts: artifacts),
      isCancelled: () => _cancelRequested.contains(jobId),
    );
    return (
      report: report,
      problems: <String>[
        ...problems,
        // Pass-level problems first: an unreadable destination list means the
        // per-destination list below is empty for a reason, not because
        // nothing is configured.
        ...report.problems,
        for (final destination in report.destinations) ...destination.problems,
      ],
    );
  }

  /// Send the morning message, letting a notification failure be a line in the
  /// report rather than the end of a job whose artifacts already exist.
  Future<DawnNotificationDecision> _announce(
    int jobId,
    DawnJobReport report,
  ) async {
    try {
      return await _notifier.announce(report);
    } catch (error) {
      _logger?.warning(
        'The morning notification could not be sent',
        source: 'DawnAutopilotService',
        fields: {'jobId': jobId, 'error': '$error'},
      );
      return DawnNotificationDecision(
        sent: false,
        reason: 'The morning message could not be sent: $error',
      );
    }
  }

  /// Write the night report beside the drafts, returning its path or null when
  /// the disk refused it.
  Future<String?> _writeReport(
    String directory,
    int jobId,
    DawnJobReport report,
  ) async {
    final path = p.join(directory, 'job_${jobId}_report.json');
    try {
      await File(path).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
      );
      return path;
    } on FileSystemException catch (error) {
      _logger?.warning(
        'The night report could not be written',
        source: 'DawnAutopilotService',
        fields: {'jobId': jobId, 'path': path, 'error': error.message},
      );
      return null;
    }
  }

  /// The directory the job's drafts and report land in, created if absent.
  Future<String> _darkroomDirectory() async {
    final base = await _outputDirectory();
    final directory = p.join(base, 'darkroom');
    await Directory(directory).create(recursive: true);
    return directory;
  }

  Future<String?> _targetName(int? targetId) async {
    if (targetId == null) return null;
    final target = await _targets.getTargetById(targetId);
    return target?.name;
  }

  /// Advance the job's progress, treating a row that has left this executor as
  /// the stop it is.
  ///
  /// The note doubles as the stage a failure sentence names, so the two can
  /// never describe different steps.
  Future<void> _reportProgress(int jobId, double progress, String note) async {
    _stage[jobId] = note.isEmpty
        ? 'running the dawn pass'
        : '${note[0].toLowerCase()}${note.substring(1)}';
    await _jobs.updateProgress(jobId, progress.clamp(0.0, 1.0), note: note);
  }

  void _stopIfCancelled(int jobId, String where) {
    if (_cancelRequested.contains(jobId)) throw _DawnCancelled(where);
  }

  /// The one line the job row carries after it finishes: what was drafted,
  /// what was held back, and where the first draft image is, because the row
  /// has no artifact column.
  static String _completionNote(DawnJobReport report) {
    final withheld = report.masters.where((m) => !m.deliverable).length;
    final tail = withheld == 0
        ? ''
        : '; $withheld master${withheld == 1 ? '' : 's'} '
              '${withheld == 1 ? 'was' : 'were'} not delivered — see the '
              'night report';
    final first = report.masters.firstWhere(
      (master) => master.hasDraft,
      orElse: () => report.masters.isEmpty ? _noMasters : report.masters.first,
    );
    final path = first.draftRenderPath;
    if (path == null) {
      // A FINISHED sentence, because `draftRenderPath == null` here means
      // `draftsRendered == 0`, which is the ending that now fails — and the
      // Session Review banner prints a failed row's note as the pass's own
      // second sentence. It frames a note without terminal punctuation as the
      // stage the pass stopped at ("It was <note> when it stopped"), which for
      // a pass that ran every stage would name a stop that never happened.
      // It also does not repeat the failure line above it: that names which
      // master stopped and why, so this one points at the artifact instead.
      return 'No draft came out of the pass; the night report carries the '
          'per-master detail.';
    }
    return '${report.draftsRendered} '
        'draft${report.draftsRendered == 1 ? '' : 's'} ready; '
        'first at $path$tail';
  }

  static const DawnMasterReport _noMasters = DawnMasterReport(
    master: DawnMaster(
      masterId: 0,
      targetId: null,
      name: 'no master',
      filter: null,
      masterFitsPath: '',
      channels: 0,
      width: 0,
      height: 0,
      frameCount: 0,
      totalIntegrationSeconds: 0.0,
    ),
    targetName: null,
    stats: DawnMasterStats.unrecorded,
    draft: null,
    recipeId: null,
    draftRenderPath: null,
    failure: 'the session produced no linear master',
  );
}
