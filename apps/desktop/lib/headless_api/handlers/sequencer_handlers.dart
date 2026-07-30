import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_api;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../../headless/host_checkpoint_directory.dart';
import '../command_correlator.dart';
import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for sequencer control endpoints
class SequencerHandlers {
  final ProviderContainer container;

  /// optional command correlator. When set, every action POST
  /// generates a UUID v4 commandId and includes it in the response.
  final CommandCorrelator? commandCorrelator;

  SequencerHandlers(this.container, {this.commandCorrelator});

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SequencerHandlers');

  Future<Response> handleSequencerStatus(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final status = await backend.sequencerGetStatus();

    // Mirror the master's live run-vitals onto the status payload so a slave can
    // reconstruct its Session Vitals tile (the local executor never populates
    // liveSequenceStatsProvider on a slave). Null when no run is active.
    final liveStats = container.read(liveSequenceStatsProvider);
    final Map<String, dynamic>? runVitals = liveStats == null
        ? null
        : {
            'startTime': liveStats.startTime.toIso8601String(),
            if (liveStats.endTime != null)
              'endTime': liveStats.endTime!.toIso8601String(),
            'framesCaptured': liveStats.framesCaptured,
            'framesRejected': liveStats.framesRejected,
            'integrationSecs': liveStats.integrationSecs,
            'triggerFires': liveStats.triggerFires,
            'autofocusRuns': liveStats.autofocusRuns,
            'meridianFlips': liveStats.meridianFlips,
            'ditherCount': liveStats.ditherCount,
            'warningMessages': liveStats.warningMessages,
            // Errors were missing from the mirror, so a remote operator saw a
            // run that looked healthy even after (e.g.) its meridian flip had
            // failed. The vitals must carry the bad news too.
            'errorMessages': liveStats.errorMessages,
          };

    return jsonOk({
      'state': status.state,
      'currentNodeId': status.currentNodeId,
      'currentNodeName': status.currentNodeName,
      'progress': status.progress,
      'message': status.message,
      if (runVitals != null) 'runVitals': runVitals,
    });
  }

  /// GET /api/sequencer/editor-sequence.
  ///
  /// G2 (remote hydration): return the master's currently-open editor sequence
  /// in the SAME payload shape the live editor mirror broadcasts over the WS
  /// `/events` stream (see `master_sequence_editor_mirror.dart` ->
  /// `emitSnapshot`), so a slave connecting mid-session can seed its sequencer
  /// canvas without waiting for the master's next edit. Returns
  /// `{open: false}` when nothing is open in the editor.
  Future<Response> handleSequencerEditorSequence(Request request) async {
    final sequence = container.read(currentSequenceProvider);
    if (sequence == null) {
      return jsonOk({'open': false});
    }
    final Map<String, dynamic> sequenceMap;
    try {
      sequenceMap = container
          .read(sequenceFileServiceProvider)
          .sequenceToMap(sequence);
    } catch (e) {
      // Mirror the live emitter's behavior: a serialization failure must not
      // crash the GET — report "nothing to seed" and let the slave fall back to
      // the next live mirror frame.
      _logInfo(
        '[API] GET /api/sequencer/editor-sequence: serialize failed: $e',
      );
      return jsonOk({'open': false});
    }
    final isDirty = container.read(currentSequenceProvider.notifier).isDirty;
    final owner = container.read(activePlanOwnerProvider);
    return jsonOk({
      'open': true,
      'sequence': sequenceMap,
      if (sequence.databaseId != null) 'databaseId': sequence.databaseId,
      'isDirty': isDirty,
      // Who owns the open plan (manual vs autopilot/Smart Night/mosaic). Lets a
      // slave seeding mid-session learn the owner on connect. Additive; an older
      // slave ignores it.
      'activePlanOwner': owner.wireValue,
    });
  }

  /// Start the sequencer via the canonical [SequenceExecutor.start] path.
  ///
  /// Audit C3 — historical bug: this handler called
  /// `backend.sequencerStart()` directly, bypassing the executor entirely.
  /// That skipped pre-flight validation, the session row, the
  /// sequence_runs row, the checkpoint timer, the disk-space watchdog,
  /// and the session-lifecycle hooks. Headless clients were the lowest-
  /// rigor start path in the whole app.
  ///
  /// Now the handler reaches the same `SequenceExecutor` instance the
  /// UI does. Validation errors come back as a structured 400 with the
  /// full issue list (no first-error truncation) so a remote dashboard
  /// can render the same pre-flight panel the desktop dialog does.
  Future<Response> handleSequencerStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/start');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.start',
    );
    // Two start paths converge here:
    //
    //  * In-editor sequence present (a graphical desktop host driving its own
    //    `currentSequenceProvider`): run the full Dart [SequenceExecutor.start]
    //    so pre-flight validation, the session row, the sequence_runs row, the
    //    checkpoint timer and lifecycle hooks all fire (Audit C3).
    //
    //  * No in-editor sequence (the headless Pi appliance — nothing ever wires
    //    an editor into `currentSequenceProvider` there): the sequence was
    //    loaded straight into the native executor via POST /api/sequencer/load.
    //    Start THAT one directly. Without this branch the canonical remote flow
    //    (load → start) always failed with "No sequence loaded", which meant a
    //    tablet/desktop client could not run an imaging sequence on the rig at
    //    all — the appliance's core purpose.
    final hasInEditorSequence = container.read(currentSequenceProvider) != null;
    try {
      if (hasInEditorSequence) {
        final executor = container.read(sequenceExecutorProvider);
        await executor.start();
      } else {
        _logInfo(
          '[API] POST /api/sequencer/start: no in-editor sequence; starting '
          'the natively-loaded sequence (headless load->start path)',
        );
        final backend = container.read(sequencerBackendProvider);
        // Wire real-hardware device ops onto the native executor before
        // starting. The Dart-orchestrated start path does this via
        // sequencerSetSimulationMode(false) (UnifiedDeviceOps); the bare
        // load->start path otherwise hits "No device operations configured".
        // Passing `false` is always permitted (only enabling simulation is
        // gated off in release builds).
        await backend.sequencerSetSimulationMode(false);
        // Weather-safety-off gating: this bare path skips the Dart executor's
        // runtime-config sync (which pushes the effective fail mode), so mirror
        // it here. With weather safety disabled the always-armed Rust
        // WeatherUnsafe trigger would otherwise fail-closed on a rig with no
        // safety-monitor device and abort the run (see _startNativeExecution).
        final weatherSafetyEnabled = container
            .read(weatherSettingsProvider)
            .weatherSafetyEnabled;
        if (!weatherSafetyEnabled) {
          await backend.sequencerSetSafetyFailMode('fail_open');
        }
        await backend.sequencerStart();
      }
    } on SequenceValidationException catch (e) {
      _logInfo(
        '[API] POST /api/sequencer/start rejected: '
        '${e.result.errorCount} validation errors',
      );
      return jsonBadRequest(e.toJsonBody());
    } catch (error) {
      // Pressing Start with nothing loaded is an ordinary operator mistake, not
      // a server fault. Every other sequencer verb (pause/resume/stop/skip)
      // already answers cleanly when idle; this one surfaced a 500.
      //
      // `Executor::start()` returns the bare string "No sequence loaded"
      // (sequencer/src/executor/mod.rs), which `sequencer_api::sequencer_start`
      // wraps as `OperationFailed`. Match that typed variant first; the
      // stringified fallback only covers a chained network backend that
      // re-raises the host message untyped. Neither value reaches the response
      // body — it selects the status code and nothing more.
      const marker = 'No sequence loaded';
      final isNoSequenceLoaded =
          (error is bridge_api.NightshadeError &&
              error.maybeMap(
                operationFailed: (failure) => failure.field0.contains(marker),
                orElse: () => false,
              )) ||
          error.toString().contains(marker);
      if (isNoSequenceLoaded) {
        _logInfo(
          '[API] POST /api/sequencer/start rejected: no sequence loaded',
        );
        return jsonConflict({
          'error': 'no_sequence_loaded',
          'message':
              'No sequence is loaded. Load one first (POST /api/sequencer/load, '
              'or open a sequence in the editor) before starting.',
        });
      }
      rethrow;
    }
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.sequencer,
      action: HostMutationAction.started,
    );
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'started',
    });
  }

  /// Stop the sequencer via the canonical [SequenceExecutor.stop] path.
  ///
  /// Audit C3 — historical bug: this handler bypassed the executor and
  /// only called `backend.sequencerStop()`, leaving the session row, run
  /// row, and progress timers dangling. It also discarded the checkpoint
  /// unconditionally with no way for the operator to opt out.
  ///
  /// The new wire contract accepts an optional `preserveCheckpoint`
  /// boolean (defaults to `true` for parity with the desktop Stop
  /// button — operator-initiated stops keep the resume point). Callers
  /// that want a destructive reset-style stop pass `false`.
  Future<Response> handleSequencerStop(Request request) async {
    _logInfo('[API] POST /api/sequencer/stop');
    bool preserveCheckpoint = true;
    final body = await request.readAsString();
    if (body.isNotEmpty) {
      Object? decoded;
      try {
        decoded = jsonDecode(body);
      } on FormatException {
        // Legacy clients post an empty / non-JSON body — we silently
        // fall back to the default so the wire contract stays
        // backward-compatible. Any caller intending to set the flag
        // must send a JSON object.
        decoded = null;
      }
      if (decoded is Map<String, dynamic>) {
        final raw = decoded['preserveCheckpoint'];
        if (raw is bool) {
          preserveCheckpoint = raw;
        } else if (raw != null) {
          throw BadRequestError(
            field: 'preserveCheckpoint',
            expected: 'boolean',
          );
        }
      }
    }
    // Shared stop/abort no-op contract — see [kWasRunningField]. Observed live
    // with the sequencer idle:
    //   POST /api/sequencer/stop -> 200 {"status":"stopped","preserveCheckpoint":true}
    // which reports a run stopped when none was in flight.
    //
    // Fail SAFE, not merely honest: a failed status read still runs the stop,
    // because a stop that silently declines to act is worse than a redundant
    // one.
    //
    // This is a DENY-list of terminal/idle states, not an allow-list of active
    // ones, and that direction is deliberate. `ExecutorState` also contains
    // `Stopping` and `Recovering`, both of which are runs very much in flight
    // — a sequence sitting in `recovering` (retrying after unsafe weather, a
    // lost guide star, a failed slew) is exactly what an operator hits Stop
    // for. An allow-list of {running, paused} answered `wasRunning: false` for
    // it, which is the one lie this whole change exists to remove: telling the
    // operator nothing was running when something was. Caught by driving a
    // real run on the local instance, which reported `state: "recovering"`.
    // Any state added later therefore counts as running until it is
    // explicitly listed as terminal here.
    var wasRunning = true;
    try {
      final status = await container
          .read(sequencerBackendProvider)
          .sequencerGetStatus();
      const terminalStates = {
        'idle',
        'completed',
        'failed',
        'cancelled',
        'stopped',
        'error',
      };
      wasRunning = !terminalStates.contains(status.state.toLowerCase());
    } catch (error) {
      _logInfo(
        'sequencer stop precondition check skipped: status read failed ($error)',
      );
    }

    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.stop',
    );
    final executor = container.read(sequenceExecutorProvider);
    await executor.stop(preserveCheckpoint: preserveCheckpoint);
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.sequencer,
      action: HostMutationAction.stopped,
    );
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'stopped',
      'preserveCheckpoint': preserveCheckpoint,
      kWasRunningField: wasRunning,
      if (!wasRunning) 'message': 'No sequence was running; nothing to stop.',
    });
  }

  Future<Response> handleSequencerPause(Request request) async {
    _logInfo('[API] POST /api/sequencer/pause');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.pause',
    );
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerPause();
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.sequencer,
      action: HostMutationAction.paused,
    );
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'paused',
    });
  }

  Future<Response> handleSequencerResume(Request request) async {
    _logInfo('[API] POST /api/sequencer/resume');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.resume',
    );
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerResume();
    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.sequencer,
      action: HostMutationAction.resumed,
    );
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'resumed',
    });
  }

  Future<Response> handleSequencerSkip(Request request) async {
    _logInfo('[API] POST /api/sequencer/skip');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.skip',
    );
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSkip();
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'skipped',
    });
  }

  /// Jump the executor forward to a specific node by id.
  ///
  /// Why: 's UI lets the operator right-click a node in the tree and say
  /// "skip directly to this". The Dart NetworkBackend POSTs here; the FRB
  /// binding marks every preceding sibling Skipped so the executor's next
  /// tree-walk lands on `nodeId`. Empty/missing `nodeId` is a structured 400.
  Future<Response> handleSequencerSkipToNode(Request request) async {
    _logInfo('[API] POST /api/sequencer/skip-to-node');
    final payload = await readJsonObject(request);
    final nodeId = requireString(payload, 'nodeId');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSkipToNode(nodeId);
    return jsonOk({'status': 'skipped', 'nodeId': nodeId});
  }

  Future<Response> handleSequencerPluginNodeFinished(Request request) async {
    _logInfo('[API] POST /api/sequencer/plugin-node-finished');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerPluginNodeFinished(
      nodeId: requireString(payload, 'nodeId'),
      success: requireBool(payload, 'success'),
      message: optionalString(payload, 'message'),
      structuredDetailJson: optionalString(payload, 'structuredDetailJson'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerReset(Request request) async {
    _logInfo('[API] POST /api/sequencer/reset');
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerReset();

    // Also close a durable session that no run owns any more.
    //
    // Reset clears the executor, but the `imaging_sessions` row survived it. A
    // run that failed early left its row `active`, so EVERY later start was
    // refused with "Imaging session N is already active" — and reset, the
    // obvious recovery, did not help. The sequencer was then wedged for the
    // night with no in-app way out (reproduced end-to-end: a run that aborted on
    // frame 1 blocked all subsequent starts). Only abort the session when the
    // executor is genuinely idle, so this can never tear down a live run.
    int? abortedSessionId;
    try {
      final status = await backend.sequencerGetStatus();
      final running =
          status.state.toLowerCase() == 'running' ||
          status.state.toLowerCase() == 'paused';
      // Prefer the in-memory id, but fall back to the DAO: after an app
      // restart the orphaned row survives in `imaging_sessions` while the
      // in-memory `dbSessionId` is null, which is exactly the wedged state a
      // user hits the morning after a failed run.
      var sessionId = container.read(sessionStateProvider).dbSessionId;
      if (sessionId == null) {
        final active = await container
            .read(databaseProvider)
            .sessionsDao
            .getActiveSessions();
        sessionId = active.isEmpty ? null : active.first.id;
      }
      if (!running && sessionId != null) {
        await container
            .read(sessionServiceProvider)
            .markSessionAborted(sessionId);
        abortedSessionId = sessionId;
        _logInfo(
          '[API] sequencer reset closed stale imaging session $sessionId',
        );
      }
    } catch (e) {
      // Never fail the reset itself over session bookkeeping — reset is the
      // recovery path and must always succeed.
      _logger.warning(
        'Sequencer reset could not close the stale session: $e',
        source: 'SequencerHandlers',
      );
    }

    return jsonOk({
      'status': 'reset',
      if (abortedSessionId != null) 'closedSessionId': abortedSessionId,
    });
  }

  Future<Response> handleSequencerLoad(Request request) async {
    _logInfo('[API] POST /api/sequencer/load');
    final payload = await readJsonObject(request);
    final json = requireString(payload, 'json');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerLoadJson(json);
    return jsonOk({'status': 'loaded'});
  }

  /// Load a persisted sequence through the canonical Dart editor and start it.
  ///
  /// Database DTOs do not share Rust's `SequenceDefinition` schema, so saved
  /// sequences must be hydrated and serialized on the host. This also keeps
  /// validation, sessions, runtime settings, and checkpoints on the same
  /// lifecycle path as a desktop-initiated run.
  Future<Response> handleSequencerLoadAndStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/load-and-start');
    final payload = await readJsonObject(request);
    final sequenceId = requireInt(payload, 'sequenceId');
    if (sequenceId < 1) {
      throw BadRequestError(
        field: 'sequenceId',
        expected: 'positive integer',
        message: 'sequenceId must be a positive integer',
      );
    }

    final sequence = await container
        .read(sequenceRepositoryProvider)
        .loadSequence(sequenceId);
    if (sequence == null) {
      return jsonNotFound({
        'error': 'sequence_not_found',
        'message': 'Sequence $sequenceId was not found.',
      });
    }

    final editor = container.read(currentSequenceProvider.notifier);
    try {
      editor.loadCopyForEditing(sequence);
    } on UnsavedChangesException catch (e) {
      return jsonConflict({
        'error': 'unsaved_sequence_changes',
        'message': e.message,
      });
    } on SequenceLockedException catch (e) {
      return jsonConflict({
        'error': 'sequence_editor_locked',
        'message': e.message,
      });
    }

    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.load-and-start',
    );
    try {
      await container.read(sequenceExecutorProvider).start();
    } on SequenceValidationException catch (e) {
      return jsonBadRequest(e.toJsonBody());
    } on ActiveImagingSessionException catch (e) {
      // A previous run can leave its durable session row `active` (seen after a
      // run that failed on its first frame), and every later start is then
      // refused. That refusal used to surface as `500 internal_error`, which
      // reads as a host crash and tells the caller nothing about the way out.
      // Match the shape `analytics_handlers` already uses for this exception and
      // name the recovery.
      return jsonConflict({
        'error': 'active_session_exists',
        'message':
            '$e. Reset the sequencer (POST /api/sequencer/reset) to '
            'close the stale session before starting a new run.',
        'activeSessionId': e.sessionId,
      });
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.sequencer,
      action: HostMutationAction.started,
    );
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'started',
      'sequenceId': sequenceId,
    });
  }

  Future<Response> handleSequencerSetSimulationMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/simulation');
    final payload = await readJsonObject(request);
    final enabled = requireBool(payload, 'enabled');

    final backend = container.read(sequencerBackendProvider);
    try {
      await backend.sequencerSetSimulationMode(enabled);
    } catch (e) {
      // Release/production appliance builds deliberately refuse simulation mode
      // (NightshadeError.NotSupported) so a shipped rig never drives mock
      // hardware. Surface that as a clean 400 with an actionable message rather
      // than an opaque 500 internal_error a remote client can't interpret.
      _logInfo('[API] POST /api/sequencer/simulation rejected: $e');
      return jsonBadRequest({
        'error': 'simulation_mode_unavailable',
        'message':
            'Simulation mode is not available on this build (production '
            'appliances run real hardware only).',
      });
    }
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetDevices(Request request) async {
    _logInfo('[API] POST /api/sequencer/devices');
    final payload = await readJsonObject(request);

    // Why: filterFocusOffsets has dynamic-typed JSON object keys; validate
    // each value is numeric since requireList can't express map<string,int>
    // and we want a precise per-key error path instead of a ClassCastException.
    Map<String, int>? filterFocusOffsets;
    final rawOffsets = payload['filterFocusOffsets'];
    if (rawOffsets != null) {
      if (rawOffsets is! Map) {
        throw BadRequestError(field: 'filterFocusOffsets', expected: 'object');
      }
      filterFocusOffsets = <String, int>{};
      rawOffsets.forEach((key, value) {
        if (value is! num) {
          throw BadRequestError(
            field: 'filterFocusOffsets.$key',
            expected: 'integer',
          );
        }
        filterFocusOffsets![key.toString()] = value.toInt();
      });
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetDevices(
      cameraId: optionalString(payload, 'cameraId'),
      mountId: optionalString(payload, 'mountId'),
      focuserId: optionalString(payload, 'focuserId'),
      filterwheelId: optionalString(payload, 'filterwheelId'),
      rotatorId: optionalString(payload, 'rotatorId'),
      filterNames: optionalList<String>(payload, 'filterNames'),
      filterFocusOffsets: filterFocusOffsets,
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetSafetyFailMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/safety-fail-mode');
    final payload = await readJsonObject(request);
    final mode = requireString(payload, 'mode');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetSafetyFailMode(mode);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetSafetyCheckInterval(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/safety-check-interval');
    final payload = await readJsonObject(request);
    final seconds = requireInt(payload, 'seconds', min: 5, max: 3600);

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetSafetyCheckIntervalSeconds(seconds);
    return jsonOk({'status': 'ok'});
  }

  /// POST /api/sequencer/save-path.
  ///
  /// The save path is where a run's science frames land, so an unusable value
  /// is data loss with a delay: the endpoint used to answer `ok` to the empty
  /// string, to an uncreatable directory and to a read-only one, and the
  /// sequencer then captured a full run and discarded every frame. Nothing is
  /// forwarded to the backend until this host has proved it can write there.
  Future<Response> handleSequencerSetSavePath(Request request) async {
    _logInfo('[API] POST /api/sequencer/save-path');
    final payload = await readJsonObject(request);
    final requested = optionalString(payload, 'path')?.trim();
    if (requested == null || requested.isEmpty) {
      return jsonBadRequest({
        'error':
            'path is required and must name a directory this host can write '
            'to. Captured frames are written there; without it a run would '
            'discard every frame.',
        'code': 'save_path_required',
      });
    }

    final directory = Directory(requested);
    try {
      await directory.create(recursive: true);
      final probe = File(
        '${directory.path}${Platform.pathSeparator}'
        '.nightshade-write-probe-${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException catch (error) {
      return jsonBadRequest({
        'error':
            'Save path "$requested" is not usable: ${error.message}. Choose a '
            'directory this host can write to.',
        'code': 'save_path_unwritable',
      });
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetSavePath(requested);
    return jsonOk({'status': 'ok', 'path': requested});
  }

  Future<Response> handleSequencerSetActiveSequenceRunId(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/active-sequence-run-id');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetActiveSequenceRunId(
      optionalInt(payload, 'sequence_run_id'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetDecisionLoggingEnabled(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/decision-logging-enabled');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetDecisionLoggingEnabled(
      requireBool(payload, 'enabled'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateDitherConfig(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-dither-config');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateDitherConfig(
      pixels: requireDouble(payload, 'pixels'),
      settlePixels: requireDouble(payload, 'settlePixels'),
      settleTime: requireDouble(payload, 'settleTime'),
      settleTimeout: requireDouble(payload, 'settleTimeout'),
      raOnly: optionalBool(payload, 'raOnly') ?? false,
    );
    return jsonOk({'status': 'ok'});
  }

  /// POST /api/sequencer/update-meridian-flip-config.
  ///
  /// Lets a paired controller push the operator's meridian-flip settings onto
  /// the master's `meridian_flip` trigger, which otherwise runs on Rust
  /// defaults for the whole night regardless of the Settings panel.
  Future<Response> handleSequencerUpdateMeridianFlipConfig(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/update-meridian-flip-config');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateMeridianFlipConfig(
      requireString(payload, 'configJson'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateLocation(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-location');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateLocation(
      latitude: requireDouble(payload, 'latitude'),
      longitude: requireDouble(payload, 'longitude'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateFilterOffsets(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-filter-offsets');
    final payload = await readJsonObject(request);
    final rawOffsets = payload['offsets'];
    // Why: same as set-devices — Dart's Map<String,int> can't be expressed
    // through requireList; we validate per-entry to give callers a precise
    // error path rather than a generic ClassCastException.
    final offsets = <String, int>{};
    if (rawOffsets != null) {
      if (rawOffsets is! Map) {
        throw BadRequestError(field: 'offsets', expected: 'object');
      }
      rawOffsets.forEach((key, value) {
        if (value is! num) {
          throw BadRequestError(field: 'offsets.$key', expected: 'integer');
        }
        offsets[key.toString()] = value.toInt();
      });
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateFilterOffsets(offsets);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdatePendingIntegrationCarryOver(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/update-pending-integration-carry-over');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdatePendingIntegrationCarryOver(
      _readNestedDoubleMap(payload, 'carry_over'),
    );
    return jsonOk({'status': 'ok'});
  }

  /// Push the live autofocus cadence into the running executor.
  ///
  /// Why: the Settings UI's autofocus-cadence field calls this through
  /// `backend.sequencerUpdateAutofocusInterval`; the standard AutofocusInterval
  /// trigger reads its target frame count from `RuntimeConfig` and the running
  /// sequencer must be told to re-evaluate without restarting. Values < 1 are
  /// rejected as a structured 400 (the Rust bridge enforces the same gate).
  Future<Response> handleSequencerUpdateAutofocusInterval(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/update-autofocus-interval');
    final payload = await readJsonObject(request);
    final everyNFrames = requireInt(payload, 'everyNFrames', min: 1);

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateAutofocusInterval(everyNFrames);
    return jsonOk({'status': 'ok', 'everyNFrames': everyNFrames});
  }

  Future<Response> handleSequencerUpdateDefaultQualityCheck(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/update-default-quality-check');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateDefaultQualityCheck(
      hfrThreshold: optionalDouble(payload, 'hfrThreshold'),
      hfrBaselinePercent: optionalDouble(payload, 'hfrBaselinePercent'),
      eccentricityThreshold: optionalDouble(payload, 'eccentricityThreshold'),
      starCountMin: optionalInt(payload, 'starCountMin', min: 0),
      maxConsecutiveRejects: requireInt(
        payload,
        'maxConsecutiveRejects',
        min: 1,
      ),
      enabled: requireBool(payload, 'enabled'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateRejectFolderPath(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/update-reject-folder-path');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateRejectFolderPath(
      optionalString(payload, 'path'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateObserverProfile(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-observer-profile');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateObserverProfile(
      observerName: optionalString(payload, 'observerName'),
      siteElevationM: optionalDouble(payload, 'siteElevationM'),
      cameraMake: optionalString(payload, 'cameraMake'),
      cameraModel: optionalString(payload, 'cameraModel'),
      telescopeName: optionalString(payload, 'telescopeName'),
      telescopeFocalLengthMm: optionalDouble(payload, 'telescopeFocalLengthMm'),
      telescopeApertureMm: optionalDouble(payload, 'telescopeApertureMm'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateSkyBrightness(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-sky-brightness');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateSkyBrightness(
      mag: _readNullableDouble(payload, 'mag'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateDefaultAdaptiveExposure(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/update-default-adaptive-exposure');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateDefaultAdaptiveExposure(
      enabled: requireBool(payload, 'enabled'),
      targetSnr: requireDouble(payload, 'targetSnr', min: 0),
      referenceSkyBrightnessMag: requireDouble(
        payload,
        'referenceSkyBrightnessMag',
      ),
      minExposureSecs: requireDouble(payload, 'minExposureSecs', min: 0),
      maxExposureSecs: requireDouble(payload, 'maxExposureSecs', min: 0),
      perFilterEnabled: _readStringBoolMap(payload, 'perFilterEnabled'),
      perFilterMinSecs: _readStringDoubleMap(payload, 'perFilterMinSecs'),
      perFilterMaxSecs: _readStringDoubleMap(payload, 'perFilterMaxSecs'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerClearDefaultAdaptiveExposure(
    Request request,
  ) async {
    _logInfo('[API] POST /api/sequencer/clear-default-adaptive-exposure');
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerClearDefaultAdaptiveExposure();
    return jsonOk({'status': 'ok'});
  }

  /// POST /api/sequencer/checkpoint/dir.
  ///
  /// The host owns its crash-recovery storage layout. A paired client used to
  /// be able to push its own documents directory here, which replaced the
  /// host's checkpoint directory with a path that does not exist on the rig —
  /// every subsequent checkpoint write failed and a mid-night crash became
  /// unrecoverable. A client-supplied path is now refused; an empty body
  /// re-asserts the host's own directory.
  Future<Response> handleSequencerSetCheckpointDir(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/dir');
    final payload = await readJsonObject(request);
    final requested = optionalString(payload, 'path')?.trim();
    if (requested != null && requested.isNotEmpty) {
      _logger.warning(
        'Refused client-supplied checkpoint directory "$requested" — the host '
        'owns its crash-recovery storage layout',
        source: 'SequencerHandlers',
        fields: {'requestedPath': requested},
      );
      return jsonForbidden({
        'error':
            'The host owns its crash-recovery checkpoint directory; a client '
            'cannot set it. Omit "path" to re-assert the host directory.',
        'code': 'checkpoint_dir_host_owned',
      });
    }

    final Directory directory;
    try {
      directory = await resolveHostCheckpointDirectory();
    } on FileSystemException catch (error) {
      return jsonBadRequest({
        'error':
            'The host checkpoint directory is not usable: ${error.message}. '
            'Crash recovery is disabled until it can be written to.',
        'code': 'checkpoint_dir_unwritable',
      });
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetCheckpointDir(directory.path);
    return jsonOk({'status': 'ok', 'path': directory.path});
  }

  Future<Response> handleSequencerHasCheckpoint(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final hasCheckpoint = await backend.hasCheckpoint();
    return jsonOk({'hasCheckpoint': hasCheckpoint});
  }

  Future<Response> handleSequencerGetCheckpointInfo(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final info = await backend.getCheckpointInfo();
    return jsonOk({'info': info?.toJson()});
  }

  Future<Response> handleSequencerResumeFromCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/resume');
    // Route through the SequenceExecutor provider — it re-seeds the runtime
    // config from current settings and issues the sequencerStart() that
    // actually begins execution. The raw backend resumeFromCheckpoint()
    // only prepares the native tree and leaves the executor idle.
    await container.read(sequenceExecutorProvider).resumeFromCheckpoint();
    return jsonOk({'status': 'resumed'});
  }

  Future<Response> handlePerformMeridianFlip(Request request) async {
    _logInfo('[API] POST /api/sequencer/meridian-flip');
    final payload = await readJsonObject(request);
    final mountId = requireString(payload, 'mountId', maxLength: 512).trim();
    final targetName = requireString(
      payload,
      'targetName',
      maxLength: 512,
    ).trim();
    if (mountId.isEmpty || targetName.isEmpty) {
      throw BadRequestError(
        field: mountId.isEmpty ? 'mountId' : 'targetName',
        expected: 'non-empty string',
        message: 'Device and target identifiers must not be blank',
      );
    }
    String? optionalDeviceId(String field) {
      final value = optionalString(payload, field, maxLength: 512)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.performMeridianFlip(
      mountId: mountId,
      cameraId: optionalDeviceId('cameraId'),
      focuserId: optionalDeviceId('focuserId'),
      coverCalibratorId: optionalDeviceId('coverCalibratorId'),
      targetName: targetName,
      targetRaHours: requireDouble(payload, 'targetRaHours', min: 0, max: 24),
      targetDecDegrees: requireDouble(
        payload,
        'targetDecDegrees',
        min: -90,
        max: 90,
      ),
      pauseGuiding: optionalBool(payload, 'pauseGuiding') ?? true,
      autoCenter: optionalBool(payload, 'autoCenter') ?? true,
      refocusAfter: optionalBool(payload, 'refocusAfter') ?? false,
      resumeGuiding: optionalBool(payload, 'resumeGuiding') ?? true,
      settleTimeSecs:
          optionalDouble(payload, 'settleTimeSecs', min: 0, max: 3600) ?? 10.0,
    );
    return jsonOk({'status': 'flipped'});
  }

  Future<Response> handleSequencerDiscardCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/discard');
    final backend = container.read(sequencerBackendProvider);
    await backend.discardCheckpoint();
    return jsonOk({'status': 'discarded'});
  }

  Future<Response> handleSequencerSaveCheckpoint(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/save');
    final backend = container.read(sequencerBackendProvider);
    await backend.saveCheckpoint();
    return jsonOk({'status': 'saved'});
  }

  // ==========================================================================
  // Recovery Mode — HTTP handlers
  // ==========================================================================
  //
  // These mirror the NetworkBackend client calls in
  // `network_backend.dart > recoveryTryNow/recoveryAbort/updateRecoveryConfig/
  // getCurrentRecoveryJson/getRecoveryHistoryJson`. The shape of the JSON
  // wire payload here is what `_post`/`_get` produces / expects on the
  // client side; do not change one without changing the other.

  /// Operator pressed "Try Now" remotely (mobile companion, web dashboard).
  /// Punches through the wait timer and forces the next recovery attempt
  /// immediately. No-op when the executor is not in `Recovering`.
  Future<Response> handleSequencerRecoveryTryNow(Request request) async {
    _logInfo('[API] POST /api/sequencer/recovery/try-now');
    final backend = container.read(sequencerBackendProvider);
    await backend.recoveryTryNow();
    return jsonOk({'status': 'try_now_requested'});
  }

  /// Operator pressed "Abort" remotely. Exits the recovery loop and
  /// transitions the executor to `Failed`. No-op when not in `Recovering`.
  Future<Response> handleSequencerRecoveryAbort(Request request) async {
    _logInfo('[API] POST /api/sequencer/recovery/abort');
    final backend = container.read(sequencerBackendProvider);
    await backend.recoveryAbort();
    return jsonOk({'status': 'abort_requested'});
  }

  /// Push updated recovery defaults from a remote settings UI. All five
  /// fields are required; the Rust side validates positivity gates and
  /// returns a structured InvalidParameter on a non-positive interval /
  /// duration. We surface those via the existing translateHandlerErrors
  /// middleware.
  Future<Response> handleSequencerUpdateRecoveryConfig(Request request) async {
    _logInfo('[API] POST /api/sequencer/recovery/update-config');
    final payload = await readJsonObject(request);
    final retryIntervalSecs = requireDouble(payload, 'retryIntervalSecs');
    final maxDurationSecs = requireDouble(payload, 'maxDurationSecs');
    final stopTrackingDuringRecovery = requireBool(
      payload,
      'stopTrackingDuringRecovery',
    );
    final abortOnMeridian = requireBool(payload, 'abortOnMeridian');
    final audibleAlertWhenEntered = requireBool(
      payload,
      'audibleAlertWhenEntered',
    );

    final backend = container.read(sequencerBackendProvider);
    await backend.updateRecoveryConfig(
      retryIntervalSecs: retryIntervalSecs,
      maxDurationSecs: maxDurationSecs,
      stopTrackingDuringRecovery: stopTrackingDuringRecovery,
      abortOnMeridian: abortOnMeridian,
      audibleAlertWhenEntered: audibleAlertWhenEntered,
    );
    return jsonOk({'status': 'ok'});
  }

  /// GET — snapshot the current in-flight recovery context as a JSON
  /// string. Returns `{"context": null}` when not recovering and
  /// `{"context": "<json>"}` while recovering. The wrapped-string shape
  /// matches what `NetworkBackend.getCurrentRecoveryJson` expects.
  Future<Response> handleSequencerGetCurrentRecovery(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final ctx = await backend.getCurrentRecoveryJson();
    return jsonOk({'context': ctx});
  }

  /// GET — dump every completed recovery loop in the current run. Returns
  /// `{"history": "<json-array-string>"}`. Empty array `[]` when no
  /// recoveries have completed yet.
  Future<Response> handleSequencerGetRecoveryHistory(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final history = await backend.getRecoveryHistoryJson();
    return jsonOk({'history': history});
  }

  /// POST /api/sequencer/update-cloud-motion.
  ///
  /// Mirrors `NetworkBackend.sequencerUpdateCloudMotion`. Forwards the
  /// payload into the local executor; remote controllers running the
  /// app as a thin client push their analyzer output here so the
  /// remote rig's cloud-aware triggers see fresh data.
  Future<Response> handleSequencerUpdateCloudMotion(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-cloud-motion');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateCloudMotion(
      currentCoverPercent: _readNullableDouble(payload, 'currentCoverPercent'),
      predictedArrivalMinutes: _readNullableDouble(
        payload,
        'predictedArrivalMinutes',
      ),
      predictedOpeningMinutes: _readNullableDouble(
        payload,
        'predictedOpeningMinutes',
      ),
      predictedOpeningDurationSecs: _readNullableDouble(
        payload,
        'predictedOpeningDurationSecs',
      ),
      predictedClearSkyAlt: _readNullableDouble(
        payload,
        'predictedClearSkyAlt',
      ),
      predictedClearSkyAz: _readNullableDouble(payload, 'predictedClearSkyAz'),
    );
    return jsonOk({'status': 'ok'});
  }

  /// Full-night audit 2026-06-04 (defense-in-depth) — POST
  /// /api/sequencer/update-weather-verdict.
  ///
  /// Mirrors `NetworkBackend.sequencerUpdateWeatherVerdict`. Forwards the
  /// Dart-side weather-safety verdict into the local executor so a remote
  /// controller running as a thin client drives the remote rig's in-sequencer
  /// `WeatherUnsafe` trigger the same way the local controller does.
  Future<Response> handleSequencerUpdateWeatherVerdict(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-weather-verdict');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateWeatherVerdict(
      unsafeOverride: _readNullableBool(payload, 'unsafeOverride'),
    );
    return jsonOk({'status': 'ok'});
  }

  /// GET /api/sequencer/cloud-motion.
  ///
  /// Returns `{"cloud_motion": "<json>"}` (or `null`) so the remote run
  /// dashboard can render the same panel as the local one.
  Future<Response> handleSequencerGetCloudMotion(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final json = await backend.sequencerGetCloudMotionJson();
    return jsonOk({'cloud_motion': json});
  }

  /// POST /api/sequencer/update-conditions-score.
  ///
  /// Remote controllers push the same composite sky-conditions score the
  /// local adaptive-swap driver would send through FFI. `score: null`
  /// deliberately clears telemetry in the executor.
  Future<Response> handleSequencerUpdateConditionsScore(Request request) async {
    _logInfo('[API] POST /api/sequencer/update-conditions-score');
    final payload = await readJsonObject(request);
    final rawScore = payload['score'];
    final ConditionsScore? score;
    if (rawScore == null) {
      score = null;
    } else if (rawScore is Map) {
      // ConditionsScore requires `score` AND the snake_case
      // `generated_unix_secs`; both are hard `as num` casts. Its own comment
      // justifies that by "the Rust producer always emits this field", which is
      // true of the FFI path and false of this HTTP handler — a caller sending
      // the obvious {"score": {"score": 75.0}} got a 500. Report it as the
      // client error it is.
      try {
        score = ConditionsScore.fromJson(
          rawScore is Map<String, dynamic>
              ? rawScore
              : Map<String, dynamic>.from(rawScore),
        );
      } on Object {
        throw BadRequestError(
          field: 'score',
          expected: 'object with numeric score and generated_unix_secs',
          message: 'Malformed conditions-score payload',
        );
      }
    } else {
      throw BadRequestError(field: 'score', expected: 'object or null');
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateConditionsScore(score);
    return jsonOk({'status': 'ok'});
  }

  /// GET /api/sequencer/adaptive-swap.
  ///
  /// Returns a structured snapshot so remote dashboards do not have to parse
  /// the native JSON string format.
  Future<Response> handleSequencerGetAdaptiveSwap(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final snapshot = await backend.sequencerGetAdaptiveSwapSnapshot();
    return jsonOk({'adaptive_swap': snapshot?.toJson()});
  }

  // ===========================================================================
  // Dual-rig / secondary (piggyback) camera — monitoring + control.
  //
  // Lets a remote dashboard observe and drive the secondary capture loop. The
  // dither coordination is enforced natively (the primary's dither call sites
  // gate on the shared barrier), so these endpoints are thin wrappers over the
  // FRB bindings.
  // ===========================================================================

  /// GET /api/sequencer/secondary-rig — live status snapshot of the secondary
  /// rig (or `{armed: false}` when none is running).
  Future<Response> handleSecondaryRigStatus(Request request) async {
    final s = await bridge_api.apiSecondaryRigGetStatus();
    return jsonOk({
      'armed': s.armed,
      'running': s.running,
      'cameraId': s.cameraId,
      'rigLabel': s.rigLabel,
      'framesCaptured': s.framesCaptured,
      'framesAborted': s.framesAborted,
      'plannedFrames': s.plannedFrames,
      'waitingForDither': s.waitingForDither,
      'exposing': s.exposing,
      'ditherPending': s.ditherPending,
      'forcedProceeds': s.forcedProceeds,
      'lastError': s.lastError,
    });
  }

  /// POST /api/sequencer/secondary-rig/start — arm + start the secondary loop.
  ///
  /// Body: { cameraId (required), exposureSecs (required), gain?, offset?,
  /// binX?, binY?, frameCount?, filterName?, targetTempC?, rigLabel?,
  /// ditherMaxWaitSecs?, inFlightPolicy?, saveBasePath?, targetName?,
  /// targetRaHours?, targetDecDegrees? }.
  Future<Response> handleSecondaryRigStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/secondary-rig/start');
    final body = await request.readAsString();
    final decoded = body.isEmpty ? null : jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw BadRequestError(field: 'body', expected: 'JSON object');
    }
    final cameraId = decoded['cameraId'];
    if (cameraId is! String || cameraId.trim().isEmpty) {
      throw BadRequestError(field: 'cameraId', expected: 'non-empty string');
    }
    final exposure = _readNullableDouble(decoded, 'exposureSecs');
    if (exposure == null ||
        !exposure.isFinite ||
        exposure < 0.001 ||
        exposure > 86400) {
      throw BadRequestError(
        field: 'exposureSecs',
        expected: 'finite number from 0.001 to 86400',
      );
    }
    final saveBasePath = decoded['saveBasePath'];
    if (saveBasePath is! String || saveBasePath.trim().isEmpty) {
      throw BadRequestError(
        field: 'saveBasePath',
        expected: 'non-empty host directory path',
      );
    }
    final binX = _readOptionalInteger(decoded, 'binX') ?? 1;
    final binY = _readOptionalInteger(decoded, 'binY') ?? 1;
    if (binX < 1 || binX > 16 || binY < 1 || binY > 16) {
      throw BadRequestError(
        field: 'binX/binY',
        expected: 'integers from 1 to 16',
      );
    }
    final frameCount = _readOptionalInteger(decoded, 'frameCount');
    if (frameCount != null && frameCount < 1) {
      throw BadRequestError(field: 'frameCount', expected: 'positive integer');
    }
    final ditherMaxWait =
        _readNullableDouble(decoded, 'ditherMaxWaitSecs') ?? 30.0;
    if (!ditherMaxWait.isFinite || ditherMaxWait < 0.1 || ditherMaxWait > 600) {
      throw BadRequestError(
        field: 'ditherMaxWaitSecs',
        expected: 'finite number from 0.1 to 600',
      );
    }
    final rawInFlightPolicy = decoded['inFlightPolicy'];
    if (rawInFlightPolicy != null && rawInFlightPolicy is! String) {
      throw BadRequestError(field: 'inFlightPolicy', expected: 'string');
    }
    final inFlightPolicy =
        (rawInFlightPolicy as String?) ?? 'complete_if_short';
    if (inFlightPolicy != 'complete_if_short' &&
        inFlightPolicy != 'abort_immediately') {
      throw BadRequestError(
        field: 'inFlightPolicy',
        expected: 'complete_if_short or abort_immediately',
      );
    }
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.secondaryRig.start',
    );
    await bridge_api.apiSecondaryRigStart(
      config: bridge_api.SecondaryRigConfigApi(
        cameraId: cameraId,
        exposureSecs: exposure,
        gain: _readOptionalInteger(decoded, 'gain'),
        offset: _readOptionalInteger(decoded, 'offset'),
        binX: binX,
        binY: binY,
        frameCount: frameCount,
        filterName: decoded['filterName'] as String?,
        targetTempC: _readNullableDouble(decoded, 'targetTempC'),
        rigLabel: (decoded['rigLabel'] as String?) ?? 'Secondary',
        ditherMaxWaitSecs: ditherMaxWait,
        inFlightPolicy: inFlightPolicy,
        saveBasePath: saveBasePath,
        targetName: decoded['targetName'] as String?,
        targetRaHours: _readNullableDouble(decoded, 'targetRaHours'),
        targetDecDegrees: _readNullableDouble(decoded, 'targetDecDegrees'),
        observerName: decoded['observerName'] as String?,
        siteLatitudeDeg: _readNullableDouble(decoded, 'siteLatitudeDeg'),
        siteLongitudeDeg: _readNullableDouble(decoded, 'siteLongitudeDeg'),
        siteElevationM: _readNullableDouble(decoded, 'siteElevationM'),
      ),
    );
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'started',
    });
  }

  /// POST /api/sequencer/secondary-rig/stop — stop the secondary loop.
  Future<Response> handleSecondaryRigStop(Request request) async {
    _logInfo('[API] POST /api/sequencer/secondary-rig/stop');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.secondaryRig.stop',
    );
    await bridge_api.apiSecondaryRigStop();
    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'stopped',
    });
  }

  /// narrow helper: pull an optional double out of the
  /// JSON payload, accepting either `num` or `null`. Lives next to the
  /// handler that needs it instead of in the shared helpers because no
  /// other endpoint currently surfaces optional doubles.
  double? _readNullableDouble(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw FormatException('Expected number for $key, got ${value.runtimeType}');
  }

  int? _readOptionalInteger(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw BadRequestError(field: key, expected: 'integer');
  }

  bool? _readNullableBool(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is bool) return value;
    throw FormatException('Expected bool for $key, got ${value.runtimeType}');
  }

  Map<String, double> _readStringDoubleMap(
    Map<String, dynamic> payload,
    String key,
  ) {
    final value = payload[key];
    if (value == null) return const {};
    if (value is! Map) {
      throw BadRequestError(field: key, expected: 'object');
    }
    final parsed = <String, double>{};
    value.forEach((mapKey, mapValue) {
      if (mapValue is! num) {
        throw BadRequestError(field: '$key.$mapKey', expected: 'number');
      }
      parsed[mapKey.toString()] = mapValue.toDouble();
    });
    return parsed;
  }

  Map<String, bool> _readStringBoolMap(
    Map<String, dynamic> payload,
    String key,
  ) {
    final value = payload[key];
    if (value == null) return const {};
    if (value is! Map) {
      throw BadRequestError(field: key, expected: 'object');
    }
    final parsed = <String, bool>{};
    value.forEach((mapKey, mapValue) {
      if (mapValue is! bool) {
        throw BadRequestError(field: '$key.$mapKey', expected: 'boolean');
      }
      parsed[mapKey.toString()] = mapValue;
    });
    return parsed;
  }

  Map<String, Map<String, double>> _readNestedDoubleMap(
    Map<String, dynamic> payload,
    String key,
  ) {
    final value = payload[key];
    if (value == null) return const {};
    if (value is! Map) {
      throw BadRequestError(field: key, expected: 'object');
    }
    final parsed = <String, Map<String, double>>{};
    value.forEach((targetKey, filterMap) {
      if (filterMap is! Map) {
        throw BadRequestError(field: '$key.$targetKey', expected: 'object');
      }
      final filters = <String, double>{};
      filterMap.forEach((filterKey, seconds) {
        if (seconds is! num) {
          throw BadRequestError(
            field: '$key.$targetKey.$filterKey',
            expected: 'number',
          );
        }
        filters[filterKey.toString()] = seconds.toDouble();
      });
      parsed[targetKey.toString()] = filters;
    });
    return parsed;
  }
}
