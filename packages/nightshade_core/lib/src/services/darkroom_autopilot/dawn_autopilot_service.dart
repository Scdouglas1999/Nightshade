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
  Future<List<DawnJobOutcome>> drainQueue() async {
    final outcomes = <DawnJobOutcome>[];
    while (true) {
      final next = await _jobs.nextQueued();
      if (next == null) break;
      final id = next.id;
      if (id == null) break;
      outcomes.add(await runJob(id));
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

    final sessionId = job.sessionId;
    if (sessionId == null) {
      final failed = await _jobs.markFailed(
        jobId,
        'This job names no imaging session, so there is nothing to process',
        now: _clock(),
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
      _logger?.error(
        'The dawn job failed',
        source: 'DawnAutopilotService',
        fields: {'jobId': jobId, 'error': '$error', 'stack': '$stack'},
      );
      final failed = await _jobs.markFailed(jobId, '$error', now: _clock());
      return DawnJobOutcome(
        jobId: jobId,
        state: failed.state,
        report: null,
        reportPath: null,
        failure: failed.errorText,
      );
    } finally {
      _cancelRequested.remove(jobId);
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

    final set = await _resolver.resolve(sessionId);
    final baseDirectory = await _darkroomDirectory();

    final reports = <DawnMasterReport>[];
    final linearMasters = <String>[];
    final draftRenders = <String>[];

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
          linearMasters: linearMasters,
          draftRenders: draftRenders,
        ),
      );
    }

    _stopIfCancelled(jobId, 'the night report');
    await _reportProgress(jobId, 0.85, 'Writing the night report');

    var report = DawnJobReport(
      jobId: jobId,
      kind: kind.wire,
      sessionId: sessionId,
      startedAt: startedAt,
      finishedAt: _clock(),
      state: DarkroomJobState.running.wire,
      masters: reports,
      withoutFile: set.withoutFile,
      delivery: null,
      deliveryProblems: const [],
      notification: null,
      failure: null,
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
      deliveryProblems: delivered.problems,
      notification: null,
      failure: null,
    );

    await _reportProgress(jobId, 0.95, 'Sending the morning report');
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
      state: DarkroomJobState.done.wire,
      masters: reports,
      withoutFile: set.withoutFile,
      delivery: delivered.report,
      deliveryProblems: delivered.problems,
      notification: decision,
      failure: null,
    );
    // Rewrite the report so the delivered copy and the local copy differ only
    // in that the delivered one was read a moment earlier.
    final finalPath = await _writeReport(baseDirectory, jobId, report);

    await _jobs.markDone(jobId, note: _completionNote(report), now: _clock());
    return DawnJobOutcome(
      jobId: jobId,
      state: DarkroomJobState.done,
      report: report,
      reportPath: finalPath,
      failure: null,
    );
  }

  /// Compose, persist and render one master's first draft.
  ///
  /// A master that cannot be drafted produces a report line naming the reason
  /// and the job continues: one unreadable master must not cost the operator
  /// the drafts of every other filter.
  Future<DawnMasterReport> _draftOneMaster({
    required int jobId,
    required int sessionId,
    required DawnMaster master,
    required String renderId,
    required String directory,
    required List<String> linearMasters,
    required List<String> draftRenders,
  }) async {
    linearMasters.add(master.masterFitsPath);
    final row = await _masters.getById(master.masterId);
    final stats = row == null
        ? DawnMasterStats.unrecorded
        : DawnMasterStats.parse(row.statsJson);
    final targetName = await _targetName(master.targetId);

    DawnMasterReport failed(String reason) => DawnMasterReport(
      master: master,
      targetName: targetName,
      stats: stats,
      draft: null,
      recipeId: null,
      draftRenderPath: null,
      failure: reason,
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
      );
    }

    final recipeId = await _recipes.create(
      targetId: master.targetId,
      sessionId: sessionId,
      masterId: master.masterId,
      baseMasterPath: master.masterFitsPath,
      name: 'Draft',
      stepsJson: draft.encodeStepsJson(),
      createdBy: RecipeAuthor.autopilot,
      schemaVersion: kRecipeSchemaVersion,
      createdAt: _clock(),
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
      );
    }

    draftRenders.add(draftPath);
    return DawnMasterReport(
      master: master,
      targetName: targetName,
      stats: stats,
      draft: draft,
      recipeId: recipeId,
      draftRenderPath: draftPath,
      failure: null,
    );
  }

  /// Hand the night's artifacts to delivery.
  ///
  /// Never throws and never fails the job: [DeliveryService] answers with a
  /// report rather than an exception, and a source file that vanished between
  /// integration and delivery is reported here as the problem it is.
  Future<({DeliveryRunReport? report, List<String> problems})> _deliver({
    required int jobId,
    required List<String> linearMasters,
    required List<String> draftRenders,
    required String? reportPath,
  }) async {
    final DeliveryArtifactSet set;
    try {
      set = await DeliveryArtifactSet.build(
        jobId: jobId,
        sources: {
          ArtifactContent.linearMasters: linearMasters,
          ArtifactContent.draftRender: draftRenders,
          if (reportPath != null) ArtifactContent.nightReport: [reportPath],
        },
      );
    } on DeliveryFailure catch (error) {
      return (
        report: null,
        problems: <String>['Nothing was delivered: ${error.message}.'],
      );
    }

    final report = await _delivery.deliverJobArtifacts(
      set,
      isCancelled: () => _cancelRequested.contains(jobId),
    );
    return (
      report: report,
      problems: <String>[
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
  Future<void> _reportProgress(int jobId, double progress, String note) async {
    await _jobs.updateProgress(jobId, progress.clamp(0.0, 1.0), note: note);
  }

  void _stopIfCancelled(int jobId, String where) {
    if (_cancelRequested.contains(jobId)) throw _DawnCancelled(where);
  }

  /// The one line the job row carries after it finishes: what was drafted and
  /// where the first draft image is, because the row has no artifact column.
  static String _completionNote(DawnJobReport report) {
    final first = report.masters.firstWhere(
      (master) => master.hasDraft,
      orElse: () => report.masters.isEmpty ? _noMasters : report.masters.first,
    );
    final path = first.draftRenderPath;
    if (path == null) {
      return 'No draft was rendered; see the night report for the reason';
    }
    return '${report.draftsRendered} draft(s) ready; first at $path';
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
