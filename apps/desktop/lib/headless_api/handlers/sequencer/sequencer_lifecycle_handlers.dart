part of '../sequencer_handlers.dart';

/// Lifecycle verbs: status/editor-sequence reads, start, stop, pause,
/// resume, skip, reset, load and load-and-start.
extension _SequencerLifecycle on SequencerHandlers {
  Future<Response> _handleSequencerStatus(Request request) async {
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
  Future<Response> _handleSequencerEditorSequence(Request request) async {
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
  Future<Response> _handleSequencerStart(Request request) async {
    _logInfo('[API] POST /api/sequencer/start');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'sequencer.start',
    );
    // Editor sequences use the Dart executor and lifecycle hooks. Headless
    // sequences are validated by handleSequencerLoad before entering the native
    // executor, so this branch may start the already-loaded tree directly.
    final hasInEditorSequence = container.read(currentSequenceProvider) != null;
    // Set immediately before the native `sequencerStart()` await and nowhere
    // else, so the catch below can tell a refusal raised BY the native
    // pre-flight from a failure in the setup calls that precede it. Only the
    // former is an operator-fixable rejection.
    var nativeStartAttempted = false;
    // True between opening this start's `imaging_sessions` row and the native
    // executor accepting the run. A start the executor then REFUSES must not
    // leave the row behind: measured on the live rig 2026-08-09, a start whose
    // sequence had failed to load answered `409 no_sequence_loaded` and still
    // left session id 3 — name copied from an earlier run, zero exposures,
    // status completed — sitting in `GET /api/sessions` as a night that never
    // happened. Cleared once `sequencerStart()` returns, because from then on
    // the run owns the row and finalization closes it.
    var openedSessionForThisStart = false;
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
        // Wire the session's CONNECTED devices into the native executor. The
        // Dart-orchestrated start path does this from the device-state
        // providers; this bare path did not, so `executor.camera_id` stayed
        // null and the first TakeExposure failed "No camera connected" — a
        // string the executor classifies as a device *disconnect*, which sent
        // the run into the recovery loop waiting for hardware that was never
        // assigned. Reproduced on the live rig 2026-08-09: start answered
        // `{"status":"started"}`, the run sat at
        // `recovering / Device disconnected, progress 0.0` with no frames, and
        // `GET /api/devices/connected` listed the camera the whole time.
        await _wireConnectedDevicesIntoNativeExecutor(backend);
        await _restoreNativeSavePath(backend);
        // Refuse, before anything is opened, a run that needs a guider, dome
        // or cover calibrator this rig does not have. See
        // [_refuseUnassignableRoles] — the native pre-flight cannot see these
        // three, so this is the only gate they have.
        final roleRefusal = await _refuseUnassignableRoles();
        if (roleRefusal != null) return roleRefusal;
        // Give the run the two host-side pieces `executor.start()` would have
        // set up. Order matters: the session row must exist before the first
        // frame event arrives, or that frame is stamped with a null
        // `session_id`. See [_openSessionRowForNativeRun].
        openedSessionForThisStart = await _openSessionRowForNativeRun(backend);
        await _attachHostListenersForNativeRun();
        nativeStartAttempted = true;
        await backend.sequencerStart();
        // The run owns the row from here; nothing below may close it.
        openedSessionForThisStart = false;
      }
    } on SequenceValidationException catch (e) {
      await _closeSessionOpenedForRefusedStart(openedSessionForThisStart);
      _logInfo(
        '[API] POST /api/sequencer/start rejected: '
        '${e.result.errorCount} validation errors',
      );
      return jsonBadRequest(e.toJsonBody());
    } catch (error) {
      await _closeSessionOpenedForRefusedStart(openedSessionForThisStart);
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
      if (nativeStartAttempted) {
        return _nativeStartRefusal(error);
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
  Future<Response> _handleSequencerStop(Request request) async {
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

  Future<Response> _handleSequencerPause(Request request) async {
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

  Future<Response> _handleSequencerResume(Request request) async {
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

  Future<Response> _handleSequencerSkip(Request request) async {
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
  Future<Response> _handleSequencerSkipToNode(Request request) async {
    _logInfo('[API] POST /api/sequencer/skip-to-node');
    final payload = await readJsonObject(request);
    final nodeId = requireString(payload, 'nodeId');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSkipToNode(nodeId);
    return jsonOk({'status': 'skipped', 'nodeId': nodeId});
  }

  Future<Response> _handleSequencerPluginNodeFinished(Request request) async {
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

  Future<Response> _handleSequencerReset(Request request) async {
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

  /// Load a native-wire sequence into the executor.
  ///
  /// This is the headless path into the native executor, so wire validation
  /// must reject unset target coordinates before the tree is loaded.
  Future<Response> _handleSequencerLoad(Request request) async {
    _logInfo('[API] POST /api/sequencer/load');
    final payload = await readJsonObject(request);
    final json = requireString(payload, 'json');

    // Drop the previous load's summary FIRST. A load that is then rejected —
    // by the wire validator or by the native deserializer — must not leave the
    // last successful sequence's name and targets behind for the next start to
    // label a run with. Live rig 2026-08-09: a `load` that failed on a missing
    // field was followed by a `start`, and the start opened a session named
    // after a sequence from twenty minutes earlier.
    _lastLoadedWire = null;

    final rejection = _rejectInvalidWireSequence(json);
    if (rejection != null) return rejection;

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerLoadJson(json);
    // Keep what the start path needs to open a session row. The native
    // executor owns the tree from here on and exposes no way to ask it for the
    // sequence name or its targets, so if this is dropped the headless run has
    // nothing to label a session with. See [_openSessionRowForNativeRun].
    _lastLoadedWire = _WireSequenceSummary.parse(json);
    return jsonOk({'status': 'loaded'});
  }

  /// Load a persisted sequence through the canonical Dart editor and start it.
  ///
  /// Database DTOs do not share Rust's `SequenceDefinition` schema, so saved
  /// sequences must be hydrated and serialized on the host. This also keeps
  /// validation, sessions, runtime settings, and checkpoints on the same
  /// lifecycle path as a desktop-initiated run.
  Future<Response> _handleSequencerLoadAndStart(Request request) async {
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
}
