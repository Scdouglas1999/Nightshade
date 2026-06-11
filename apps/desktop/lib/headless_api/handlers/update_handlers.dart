// P1-11 — Headless OTA update endpoints.
//
// Closes the `04-storage-image-transfer` §12 audit gap. The desktop GUI
// has had `UpdateService` + `LanPushReceiver` wired through
// `desktop_app_bootstrap.dart` since 2.4, but `main_headless.dart` never
// exposed a REST surface for a paired phone to drive the update flow.
// These handlers expose:
//
//   GET    /api/system/version            — current build info (view)
//   POST   /api/system/update/check       — kick off a check job (admin)
//   GET    /api/system/update/status      — current update phase (view)
//   POST   /api/system/update/download    — start staged download (admin)
//   POST   /api/system/update/apply       — apply staged update (admin)
//   POST   /api/system/update/abort       — cancel in-flight check/download
//   POST   /api/system/update/rollback    — manual rollback (501 if no restore point)
//   GET    /api/system/update/staged      — info about the staged update (view)
//   DELETE /api/system/update/staged      — discard a staged update (admin)
//
// Underlying state changes flow back to clients as `NightshadeEvent`s
// with `category: EventCategory.system`. The bootstrap subscribes
// [UpdateController.events] and forwards each variant to the server's
// broadcast.

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:nightshade_updater/nightshade_updater.dart';
import 'package:shelf/shelf.dart';

import '../job_manager.dart';
import '../response_helpers.dart';
import '../validation.dart';

/// REST surface for the headless OTA update flow.
///
/// The handler is stateless beyond the [UpdateController] / [JobManager]
/// pair it receives. Long-running operations (check, download, apply,
/// rollback) are dispatched through the JobManager so the caller receives
/// a `{jobId, status: 'queued'}` response immediately and tracks progress
/// via the existing `/api/jobs/{id}` endpoints + the WS event stream.
class UpdateHandlers {
  final UpdateController controller;
  final JobManager jobManager;

  UpdateHandlers({required this.controller, required this.jobManager});

  /// `GET /api/system/version` — current build metadata.
  Future<Response> handleGetVersion(Request request) async {
    return jsonOk({
      'currentVersion': controller.currentVersion,
      'buildNumber': controller.currentBuildNumber,
      'channel': controller.channel,
      'platform': _platformName(),
      'dataDir': _resolvedExecutableDir(),
      if (controller.updateServerUrl != null)
        'updateServerUrl': controller.updateServerUrl,
      if (controller.lastUpdateCheck != null)
        'lastUpdateCheck': controller.lastUpdateCheck!
            .toUtc()
            .toIso8601String(),
      if (controller.lastUpdateApplied != null)
        'lastUpdateApplied': controller.lastUpdateApplied!
            .toUtc()
            .toIso8601String(),
    });
  }

  /// `POST /api/system/update/check` — dispatch an async update check.
  /// Body / query may carry an optional `channel` override.
  Future<Response> handleCheckForUpdate(Request request) async {
    final channelOverride = await _readOptionalChannel(request);

    final job = jobManager.start(
      operation: 'system.update.check',
      work: (sink, cancellation) async {
        sink.update(null, 'Querying update server');
        final outcome = await controller.checkForUpdates(
          channelOverride: channelOverride,
        );
        if (cancellation.isCancelled) {
          throw const JobCancelledException('check_cancelled');
        }
        return outcome.toJson();
      },
    );
    return jsonOk({'jobId': job.jobId, 'status': job.state.wireName});
  }

  /// `GET /api/system/update/status` — current update phase snapshot.
  Future<Response> handleGetStatus(Request request) async {
    return jsonOk(controller.status.toJson());
  }

  /// `POST /api/system/update/download` — start streaming the staged
  /// download.
  Future<Response> handleDownload(Request request) async {
    final job = jobManager.start(
      operation: 'system.update.download',
      work: (sink, cancellation) async {
        sink.update(0, 'Downloading update');
        await controller.downloadAndStage(jobId: 'pending');
        if (cancellation.isCancelled) {
          throw const JobCancelledException('download_cancelled');
        }
        return {'status': 'downloaded'};
      },
    );

    // Re-emit DownloadStarted with the real jobId so the WS broadcast
    // matches what the caller polls. The controller emitted the first
    // event with the placeholder 'pending' jobId because we didn't have
    // the real one at the time start() returned; here we don't replay
    // the event, we just hand the caller the jobId for tracking.
    return jsonOk({'jobId': job.jobId, 'status': job.state.wireName});
  }

  /// `POST /api/system/update/apply` — apply the staged update.
  ///
  /// The job's work invokes `UpdateController.applyStagedUpdate`, which
  /// in production calls `exit(0)` on success — the host process is
  /// replaced by the updater binary. Clients should treat
  /// `JobApplyStarted` + `UpdateApplied` as terminal signals and
  /// reconnect after the WS drops.
  Future<Response> handleApply(Request request) async {
    final job = jobManager.start(
      operation: 'system.update.apply',
      work: (sink, cancellation) async {
        sink.update(null, 'Applying staged update');
        await controller.applyStagedUpdate(jobId: 'pending');
        // applyStagedUpdate typically exits the process; reaching here
        // means the apply returned without restart, which is rare but
        // surface it explicitly.
        return {
          'status': 'apply_returned_without_restart',
          'restartRequired': true,
        };
      },
    );
    return jsonOk({
      'jobId': job.jobId,
      'status': job.state.wireName,
      'restartRequired': true,
      'message':
          'Server may restart imminently. Clients should reconnect after WS drops.',
    });
  }

  /// `POST /api/system/update/abort` — cancel an in-flight check or
  /// download. 409 when nothing is in flight.
  Future<Response> handleAbort(Request request) async {
    try {
      controller.abortInFlight();
    } on StateError catch (e) {
      return jsonConflict({
        'error': 'no_update_in_flight',
        'message': e.message,
      });
    }

    // Cancel any matching jobs so the caller's polling loop terminates
    // promptly.
    final cancelled = <String>[];
    for (final job in jobManager.list()) {
      if (job.operation == 'system.update.check' ||
          job.operation == 'system.update.download') {
        if (!job.state.isTerminal) {
          try {
            jobManager.cancel(job.jobId);
            cancelled.add(job.jobId);
          } on StateError {
            // Raced terminal — fine, the job already completed.
          }
        }
      }
    }
    return jsonOk({'aborted': true, 'cancelledJobs': cancelled});
  }

  /// `POST /api/system/update/rollback` — admin-only rollback of the
  /// last applied update. Returns 501 when no restore point is currently
  /// available (no update applied, or the boot verifier already confirmed
  /// the current build healthy and reclaimed the backup).
  Future<Response> handleRollback(Request request) async {
    if (!await controller.rollbackSupported()) {
      return jsonNotImplemented({
        'error': 'rollback_unavailable',
        'message':
            'No restore point is available to roll back to. A manual rollback '
            'is only possible after an update is applied and before the next '
            'launch confirms it healthy; the boot verifier reclaims the backup '
            'once the new build proves stable.',
      });
    }
    final job = jobManager.start(
      operation: 'system.update.rollback',
      work: (sink, cancellation) async {
        sink.update(null, 'Rolling back last applied update');
        await controller.rollback(jobId: 'pending');
        return {'status': 'rolled_back'};
      },
    );
    return jsonOk({'jobId': job.jobId, 'status': job.state.wireName});
  }

  /// `GET /api/system/update/staged` — info about the staged update.
  /// 200 with body even when no staged update is present (body is null
  /// in that case so clients distinguish "no staged" from "request
  /// failed").
  Future<Response> handleGetStaged(Request request) async {
    final staged = await controller.stagedUpdate();
    if (staged == null) {
      return jsonOk({'staged': null});
    }
    return jsonOk({'staged': staged.toJson()});
  }

  /// `DELETE /api/system/update/staged` — discard the staged update.
  /// 204-style 200 with `{discarded: true}` so the client can confirm
  /// the operation took effect even when no staged update existed.
  Future<Response> handleDiscardStaged(Request request) async {
    await controller.discardStaged();
    return jsonOk({'discarded': true});
  }

  /// Honour `?channel=` query param OR a JSON body `{ "channel": ... }`.
  /// Both are accepted because the audit spec calls out the query form
  /// and operators reaching for `curl` will more naturally pass it as a
  /// body field.
  Future<String?> _readOptionalChannel(Request request) async {
    final fromQuery = request.url.queryParameters['channel'];
    if (fromQuery != null && fromQuery.trim().isNotEmpty) {
      return fromQuery.trim();
    }
    final method = request.method.toUpperCase();
    if (method != 'POST' && method != 'PUT' && method != 'PATCH') {
      return null;
    }
    final contentLength = request.contentLength ?? 0;
    if (contentLength <= 0) return null;
    // readJsonObject throws on malformed bodies; we want a missing
    // optional channel to be silent, so peek the body and route around
    // the validator when empty.
    try {
      final payload = await readJsonObject(request);
      return optionalString(payload, 'channel');
    } on BadRequestError {
      rethrow;
    }
  }

  String _platformName() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return Platform.operatingSystem;
  }

  String _resolvedExecutableDir() {
    try {
      final exe = Platform.resolvedExecutable;
      final sep = Platform.pathSeparator;
      final idx = exe.lastIndexOf(sep);
      return idx >= 0 ? exe.substring(0, idx) : exe;
    } on Object catch (e) {
      // Why: best-effort install-dir resolution; fall back to the OS name
      // rather than failing the request if the executable path can't be parsed.
      developer.log(
        'Update handler: could not resolve executable dir, '
        'falling back to OS name: $e',
        name: 'nightshade.headless',
      );
      return Platform.operatingSystem;
    }
  }
}
