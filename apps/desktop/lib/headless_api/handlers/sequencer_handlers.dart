import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../command_correlator.dart';
import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for sequencer control endpoints
class SequencerHandlers {
  final ProviderContainer container;

  /// P1-4: optional command correlator. When set, every action POST
  /// generates a UUID v4 commandId and includes it in the response.
  final CommandCorrelator? commandCorrelator;

  SequencerHandlers(this.container, {this.commandCorrelator});

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SequencerHandlers');

  Future<Response> handleSequencerStatus(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final status = await backend.sequencerGetStatus();

    return jsonOk({
      'state': status.state,
      'currentNodeId': status.currentNodeId,
      'currentNodeName': status.currentNodeName,
      'progress': status.progress,
      'message': status.message,
    });
  }

  /// Start the sequencer via the canonical [SequenceExecutor.start] path.
  ///
  /// Audit C3 â€” historical bug: this handler called
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
    final executor = container.read(sequenceExecutorProvider);
    try {
      await executor.start();
    } on SequenceValidationException catch (e) {
      _logInfo(
        '[API] POST /api/sequencer/start rejected: '
        '${e.result.errorCount} validation errors',
      );
      return jsonBadRequest(e.toJsonBody());
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
  /// Audit C3 â€” historical bug: this handler bypassed the executor and
  /// only called `backend.sequencerStop()`, leaving the session row, run
  /// row, and progress timers dangling. It also discarded the checkpoint
  /// unconditionally with no way for the operator to opt out.
  ///
  /// The new wire contract accepts an optional `preserveCheckpoint`
  /// boolean (defaults to `true` for parity with the desktop Stop
  /// button â€” operator-initiated stops keep the resume point). Callers
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
        // Legacy clients post an empty / non-JSON body â€” we silently
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
  /// Why: Pack A's UI lets the operator right-click a node in the tree and say
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
    return jsonOk({'status': 'reset'});
  }

  Future<Response> handleSequencerLoad(Request request) async {
    _logInfo('[API] POST /api/sequencer/load');
    final payload = await readJsonObject(request);
    final json = requireString(payload, 'json');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerLoadJson(json);
    return jsonOk({'status': 'loaded'});
  }

  Future<Response> handleSequencerSetSimulationMode(Request request) async {
    _logInfo('[API] POST /api/sequencer/simulation');
    final payload = await readJsonObject(request);
    final enabled = requireBool(payload, 'enabled');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetSimulationMode(enabled);
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
        throw BadRequestError(
          field: 'filterFocusOffsets',
          expected: 'object',
        );
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
      Request request) async {
    _logInfo('[API] POST /api/sequencer/safety-check-interval');
    final payload = await readJsonObject(request);
    final seconds = requireInt(payload, 'seconds', min: 5, max: 3600);

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetSafetyCheckIntervalSeconds(seconds);
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerSetSavePath(Request request) async {
    _logInfo('[API] POST /api/sequencer/save-path');
    final payload = await readJsonObject(request);
    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetSavePath(optionalString(payload, 'path'));
    return jsonOk({'status': 'ok'});
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
    // Why: same as set-devices â€” Dart's Map<String,int> can't be expressed
    // through requireList; we validate per-entry to give callers a precise
    // error path rather than a generic ClassCastException.
    final offsets = <String, int>{};
    if (rawOffsets != null) {
      if (rawOffsets is! Map) {
        throw BadRequestError(field: 'offsets', expected: 'object');
      }
      rawOffsets.forEach((key, value) {
        if (value is! num) {
          throw BadRequestError(
            field: 'offsets.$key',
            expected: 'integer',
          );
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
      Request request) async {
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
      maxConsecutiveRejects:
          requireInt(payload, 'maxConsecutiveRejects', min: 1),
      enabled: requireBool(payload, 'enabled'),
    );
    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleSequencerUpdateRejectFolderPath(
      Request request) async {
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

  Future<Response> handleSequencerSetCheckpointDir(Request request) async {
    _logInfo('[API] POST /api/sequencer/checkpoint/dir');
    final payload = await readJsonObject(request);
    final path = requireString(payload, 'path');

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerSetCheckpointDir(path);
    return jsonOk({'status': 'ok'});
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
    final backend = container.read(sequencerBackendProvider);
    await backend.resumeFromCheckpoint();
    return jsonOk({'status': 'resumed'});
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
  // Wave 4 Recovery Mode â€” HTTP handlers
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
    final stopTrackingDuringRecovery =
        requireBool(payload, 'stopTrackingDuringRecovery');
    final abortOnMeridian = requireBool(payload, 'abortOnMeridian');
    final audibleAlertWhenEntered =
        requireBool(payload, 'audibleAlertWhenEntered');

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

  /// GET â€” snapshot the current in-flight recovery context as a JSON
  /// string. Returns `{"context": null}` when not recovering and
  /// `{"context": "<json>"}` while recovering. The wrapped-string shape
  /// matches what `NetworkBackend.getCurrentRecoveryJson` expects.
  Future<Response> handleSequencerGetCurrentRecovery(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final ctx = await backend.getCurrentRecoveryJson();
    return jsonOk({'context': ctx});
  }

  /// GET â€” dump every completed recovery loop in the current run. Returns
  /// `{"history": "<json-array-string>"}`. Empty array `[]` when no
  /// recoveries have completed yet.
  Future<Response> handleSequencerGetRecoveryHistory(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final history = await backend.getRecoveryHistoryJson();
    return jsonOk({'history': history});
  }

  /// Wave 5 Agent 4 â€” POST /api/sequencer/update-cloud-motion.
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
      predictedArrivalMinutes:
          _readNullableDouble(payload, 'predictedArrivalMinutes'),
      predictedOpeningMinutes:
          _readNullableDouble(payload, 'predictedOpeningMinutes'),
      predictedOpeningDurationSecs:
          _readNullableDouble(payload, 'predictedOpeningDurationSecs'),
      predictedClearSkyAlt:
          _readNullableDouble(payload, 'predictedClearSkyAlt'),
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

  /// Wave 5 Agent 4 â€” GET /api/sequencer/cloud-motion.
  ///
  /// Returns `{"cloud_motion": "<json>"}` (or `null`) so the remote run
  /// dashboard can render the same panel as the local one.
  Future<Response> handleSequencerGetCloudMotion(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final json = await backend.sequencerGetCloudMotionJson();
    return jsonOk({'cloud_motion': json});
  }

  /// Wave 8 â€” POST /api/sequencer/update-conditions-score.
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
    } else if (rawScore is Map<String, dynamic>) {
      score = ConditionsScore.fromJson(rawScore);
    } else if (rawScore is Map) {
      score = ConditionsScore.fromJson(Map<String, dynamic>.from(rawScore));
    } else {
      throw BadRequestError(field: 'score', expected: 'object or null');
    }

    final backend = container.read(sequencerBackendProvider);
    await backend.sequencerUpdateConditionsScore(score);
    return jsonOk({'status': 'ok'});
  }

  /// Wave 8 â€” GET /api/sequencer/adaptive-swap.
  ///
  /// Returns a structured snapshot so remote dashboards do not have to parse
  /// the native JSON string format.
  Future<Response> handleSequencerGetAdaptiveSwap(Request request) async {
    final backend = container.read(sequencerBackendProvider);
    final snapshot = await backend.sequencerGetAdaptiveSwapSnapshot();
    return jsonOk({'adaptive_swap': snapshot?.toJson()});
  }

  /// Wave 5 Agent 4 â€” narrow helper: pull an optional double out of the
  /// JSON payload, accepting either `num` or `null`. Lives next to the
  /// handler that needs it instead of in the shared helpers because no
  /// other endpoint currently surfaces optional doubles.
  double? _readNullableDouble(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw FormatException('Expected number for $key, got ${value.runtimeType}');
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
