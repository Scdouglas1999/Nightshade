part of '../ffi_backend.dart';

mixin _FfiSequencerRecoveryOperations on _FfiBackendBase {
// =========================================================================
// Sequencer Control
// =========================================================================

  @override
  Future<void> sequencerStart() async {
    await bridge.NativeBridge.sequencerStart();
  }

  @override
  Future<void> sequencerStop() async {
    await bridge.NativeBridge.sequencerStop();
  }

  @override
  Future<void> sequencerPause() async {
    await bridge.NativeBridge.sequencerPause();
  }

  @override
  Future<void> sequencerResume() async {
    await bridge.NativeBridge.sequencerResume();
  }

  @override
  Future<void> sequencerSkip() async {
    await bridge.NativeBridge.sequencerSkip();
  }

  @override
  Future<void> sequencerSkipToNode(String nodeId) async {
    // Wave 1.5 Pack A: routes to the new `api_sequencer_skip_to_node` FRB
    // binding; preceding siblings of `nodeId` are marked Skipped and the
    // executor jumps forward on its next tree-walk step.
    await bridge.NativeBridge.sequencerSkipToNode(nodeId: nodeId);
  }

  @override
  Future<void> sequencerPluginNodeFinished({
    required String nodeId,
    required bool success,
    String? message,
    String? structuredDetailJson,
  }) async {
    // Wave 6 Pack P: routes to `api_sequencer_plugin_node_finished`,
    // which resolves the matching pending oneshot inside the Rust
    // executor. The awaiting `PluginNodeInstruction::execute` returns
    // Success / Failure based on `success`.
    await bridge.NativeBridge.sequencerPluginNodeFinished(
      nodeId: nodeId,
      success: success,
      message: message,
      structuredDetailJson: structuredDetailJson,
    );
  }

  @override
  Future<void> sequencerReset() async {
    await bridge.NativeBridge.sequencerReset();
  }

  @override
  Future<void> sequencerLoadJson(String json) async {
    await bridge.NativeBridge.sequencerLoadJson(json);
  }

  @override
  Future<void> sequencerSetSimulationMode(bool enabled) async {
    await bridge.NativeBridge.sequencerSetSimulationMode(enabled);
  }

  @override
  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    await bridge.NativeBridge.sequencerSetDevices(
      cameraId: cameraId,
      mountId: mountId,
      focuserId: focuserId,
      filterwheelId: filterwheelId,
      rotatorId: rotatorId,
      filterNames: filterNames,
      filterFocusOffsets: filterFocusOffsets,
    );
  }

  @override
  Future<void> sequencerSetSafetyFailMode(String mode) async {
    await bridge.NativeBridge.sequencerSetSafetyFailMode(mode);
  }

  @override
  Future<void> sequencerSetSafetyCheckIntervalSeconds(int seconds) async {
    await bridge.NativeBridge.sequencerSetSafetyCheckIntervalSeconds(seconds);
  }

  @override
  Future<void> sequencerSetSavePath(String? path) async {
    await bridge.NativeBridge.sequencerSetSavePath(path: path);
  }

  @override
  Future<void> sequencerSetActiveSequenceRunId(int? sequenceRunId) async {
    await bridge.NativeBridge.sequencerSetActiveSequenceRunId(
      sequenceRunId: sequenceRunId,
    );
  }

  @override
  Future<void> sequencerSetDecisionLoggingEnabled(bool enabled) async {
    await bridge.NativeBridge.sequencerSetDecisionLoggingEnabled(
      enabled: enabled,
    );
  }

  @override
  Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  }) async {
    await bridge.NativeBridge.sequencerUpdateDitherConfig(
      pixels: pixels,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
      raOnly: raOnly,
    );
  }

  @override
  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    await bridge.NativeBridge.sequencerUpdateLocation(
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  Future<void> sequencerUpdateFilterOffsets(Map<String, int> offsets) async {
    await bridge.NativeBridge.sequencerUpdateFilterOffsets(offsets: offsets);
  }

  @override
  Future<void> sequencerUpdatePendingIntegrationCarryOver(
    Map<String, Map<String, double>> carryOver,
  ) async {
    // Wave 7.5 — staged on the executor's RuntimeConfig; consumed once
    // when the spawned executor task is created at the top of start().
    await bridge.NativeBridge.sequencerUpdatePendingIntegrationCarryOver(
      carryOver: carryOver,
    );
  }

  @override
  Future<void> sequencerUpdateAutofocusInterval(int everyNFrames) async {
    // Wave 1.5 Pack A: pushes the cadence into the live executor's
    // standard `AutofocusInterval` trigger via the new FRB binding.
    // The bridge rejects 0; pass >= 1.
    await bridge.NativeBridge.sequencerUpdateAutofocusInterval(
      everyNFrames: everyNFrames,
    );
  }

  @override
  Future<void> sequencerUpdateDefaultQualityCheck({
    double? hfrThreshold,
    double? hfrBaselinePercent,
    double? eccentricityThreshold,
    int? starCountMin,
    required int maxConsecutiveRejects,
    required bool enabled,
  }) async {
    // Pack G — pushes the global image-grading thresholds into the
    // executor's RuntimeConfig.default_quality_check so the next
    // exposure honours the user's choices. Disabled => None pushed.
    await bridge.NativeBridge.sequencerUpdateDefaultQualityCheck(
      hfrThreshold: hfrThreshold,
      hfrBaselinePercent: hfrBaselinePercent,
      eccentricityThreshold: eccentricityThreshold,
      starCountMin: starCountMin,
      maxConsecutiveRejects: maxConsecutiveRejects,
      enabled: enabled,
    );
  }

  @override
  Future<void> sequencerUpdateRejectFolderPath(String? path) async {
    // Pack G — pushes the reject-folder override into the executor.
    // Empty / null => fall back to <save_path>/Reject/.
    await bridge.NativeBridge.sequencerUpdateRejectFolderPath(path: path);
  }

  @override
  Future<void> sequencerUpdateObserverProfile({
    String? observerName,
    double? siteElevationM,
    String? cameraMake,
    String? cameraModel,
    String? telescopeName,
    double? telescopeFocalLengthMm,
    double? telescopeApertureMm,
  }) async {
    // Pack G — pushes observer / equipment identification into the
    // executor so the next FITS save stamps OBSERVER, TELESCOP, FOCALLEN,
    // APTDIA, INSTRUME, SITEELEV with real values.
    await bridge.NativeBridge.sequencerUpdateObserverProfile(
      observerName: observerName,
      siteElevationM: siteElevationM,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      telescopeName: telescopeName,
      telescopeFocalLengthMm: telescopeFocalLengthMm,
      telescopeApertureMm: telescopeApertureMm,
    );
  }

  @override
  Future<void> sequencerUpdateCloudMotion({
    double? currentCoverPercent,
    double? predictedArrivalMinutes,
    double? predictedOpeningMinutes,
    double? predictedOpeningDurationSecs,
    double? predictedClearSkyAlt,
    double? predictedClearSkyAz,
  }) async {
    // Wave 5 Agent 4 — push the cloud-motion analyzer reading into the
    // Rust trigger state. Drives the CloudArrivingIn / CloudOpeningIn /
    // CloudCoverThreshold triggers in the live executor.
    await bridge_api.apiSequencerUpdateCloudMotion(
      currentCoverPercent: currentCoverPercent,
      predictedArrivalMinutes: predictedArrivalMinutes,
      predictedOpeningMinutes: predictedOpeningMinutes,
      predictedOpeningDurationSecs: predictedOpeningDurationSecs,
      predictedClearSkyAlt: predictedClearSkyAlt,
      predictedClearSkyAz: predictedClearSkyAz,
    );
  }

  @override
  Future<void> sequencerUpdateWeatherVerdict({bool? unsafeOverride}) async {
    // Full-night audit 2026-06-04 (defense-in-depth) — push the Dart-side
    // weather-safety verdict into the Rust trigger state so the in-sequencer
    // WeatherUnsafe trigger reacts even on rigs without a hardware safety
    // device. Folded OR-of-unsafe with the hardware reading (never less safe).
    await bridge_api.apiSequencerUpdateWeatherVerdict(
      unsafeOverride: unsafeOverride,
    );
  }

  @override
  Future<String?> sequencerGetCloudMotionJson() async {
    // Wave 5 Agent 4 — JSON-serialised cloud-motion snapshot for the run
    // dashboard. Returns null until the first push has been received.
    return await bridge_api.apiSequencerGetCloudMotionJson();
  }

  @override
  Future<void> sequencerUpdateConditionsScore(ConditionsScore? score) async {
    final weights = score?.weights ?? const ConditionsScoreWeights();
    final generatedAt = score?.generatedAt.toUtc() ?? DateTime.now().toUtc();
    await bridge_api.apiSequencerUpdateConditionsScore(
      score: score?.score,
      transparencyScore: score?.transparencyScore,
      seeingScore: score?.seeingScore,
      cloudScore: score?.cloudScore,
      windScore: score?.windScore,
      transparencyWeight: weights.transparencyWeight,
      seeingWeight: weights.seeingWeight,
      cloudWeight: weights.cloudWeight,
      windWeight: weights.windWeight,
      generatedUnixSecs: generatedAt.millisecondsSinceEpoch ~/ 1000,
    );
  }

  @override
  Future<AdaptiveSwapSnapshot?> sequencerGetAdaptiveSwapSnapshot() async {
    final raw = await bridge_api.apiSequencerGetAdaptiveSwapJson();
    return AdaptiveSwapDriver.decodeSnapshotJson(raw);
  }

  @override
  Future<void> sequencerUpdateSkyBrightness({required double? mag}) async {
    // Wave 5 Agent 2 — push the live SkyBrightnessTracker reading to the
    // executor.
    await bridge_api.apiSequencerUpdateSkyBrightness(mag: mag);
  }

  @override
  Future<void> sequencerUpdateDefaultAdaptiveExposure({
    required bool enabled,
    required double targetSnr,
    required double referenceSkyBrightnessMag,
    required double minExposureSecs,
    required double maxExposureSecs,
    required Map<String, bool> perFilterEnabled,
    required Map<String, double> perFilterMinSecs,
    required Map<String, double> perFilterMaxSecs,
  }) async {
    // Wave 5 Agent 2 — push the global default adaptive exposure config.
    // FRB cannot bridge `Map<String, T>` directly, so we flatten to
    // parallel (keys, values) lists matching the Rust API.
    await bridge_api.apiSequencerUpdateDefaultAdaptiveExposure(
      enabled: enabled,
      targetSnr: targetSnr,
      referenceSkyBrightnessMag: referenceSkyBrightnessMag,
      minExposureSecs: minExposureSecs,
      maxExposureSecs: maxExposureSecs,
      perFilterEnabledKeys: perFilterEnabled.keys.toList(),
      perFilterEnabledValues: perFilterEnabled.values.toList(),
      perFilterMinKeys: perFilterMinSecs.keys.toList(),
      perFilterMinValues: perFilterMinSecs.values.toList(),
      perFilterMaxKeys: perFilterMaxSecs.keys.toList(),
      perFilterMaxValues: perFilterMaxSecs.values.toList(),
    );
  }

  @override
  Future<void> sequencerClearDefaultAdaptiveExposure() async {
    await bridge_api.apiSequencerClearDefaultAdaptiveExposure();
  }

// =========================================================================
// Wave 4 Recovery Mode
// =========================================================================
//
// The Rust bridge exposes:
//   * `sequencer_recovery_try_now()` -> Result<(), NightshadeError>
//   * `sequencer_recovery_abort()`   -> Result<(), NightshadeError>
//   * `sequencer_update_recovery_config(update)` -> Result<(), …>
//   * `sequencer_get_current_recovery_json()` -> Result<Option<String>, …>
//   * `sequencer_get_recovery_history_json()` -> Result<String, …>
//
// These are reachable via the typed FRB-generated `bridge_api.apiSequencer*`
// wrappers (Wave 4.5 migration replaced the Wave 4 dynamic-dispatch shims).

  @override
  Future<void> recoveryTryNow() async {
    // Wave 4.5: typed FRB binding (apiSequencerRecoveryTryNow) replaces the
    // Wave 4 dynamic-dispatch shim that intercepted NoSuchMethodError while
    // bindings were pending.
    await bridge_api.apiSequencerRecoveryTryNow();
  }

  @override
  Future<void> recoveryAbort() async {
    await bridge_api.apiSequencerRecoveryAbort();
  }

  @override
  Future<void> updateRecoveryConfig({
    required double retryIntervalSecs,
    required double maxDurationSecs,
    required bool stopTrackingDuringRecovery,
    required bool abortOnMeridian,
    required bool audibleAlertWhenEntered,
  }) async {
    await bridge_api.apiSequencerUpdateRecoveryConfig(
      update: bridge.RecoveryConfigUpdate(
        retryIntervalSecs: retryIntervalSecs,
        maxDurationSecs: maxDurationSecs,
        stopTrackingDuringRecovery: stopTrackingDuringRecovery,
        abortOnMeridian: abortOnMeridian,
        audibleAlertWhenEntered: audibleAlertWhenEntered,
      ),
    );
  }

  @override
  Future<String?> getCurrentRecoveryJson() async {
    return await bridge_api.apiSequencerGetCurrentRecoveryJson();
  }

  @override
  Future<String> getRecoveryHistoryJson() async {
    return await bridge_api.apiSequencerGetRecoveryHistoryJson();
  }

  @override
  Future<SequencerStatus> sequencerGetStatus() async {
    final dynamic status = await bridge.NativeBridge.sequencerGetStatus();

    // FRB now returns SequencerState (no progress); bridge_stub returns SequencerStatus (with progress).
    // Support both to keep mobile stubs working.
    if (status is bridge.SequencerState) {
      final progress = status.totalExposures > 0
          ? status.completedExposures / status.totalExposures
          : (status.totalIntegrationSecs > 0
              ? status.elapsedSecs / status.totalIntegrationSecs
              : 0.0);

      return SequencerStatus(
        state: status.state,
        currentNodeId: status.currentNodeId,
        currentNodeName: status.currentNodeName,
        progress: progress.clamp(0.0, 1.0),
        message: status.message,
      );
    }

    if (status is bridge.SequencerStatus) {
      return SequencerStatus(
        state: status.state,
        currentNodeId: status.currentNodeId,
        currentNodeName: status.currentNodeName,
        progress: status.progress,
        message: status.message,
      );
    }

    // Unknown shape; fall back to zero progress.
    return const SequencerStatus(
      state: 'unknown',
      currentNodeId: null,
      currentNodeName: null,
      progress: 0.0,
      message: null,
    );
  }

// =========================================================================
// Checkpoint / Crash Recovery
// =========================================================================

  @override
  Future<void> sequencerSetCheckpointDir(String path) async {
    await bridge.NativeBridge.sequencerSetCheckpointDir(path);
  }

  @override
  Future<bool> hasCheckpoint() async {
    return await bridge.NativeBridge.sequencerHasCheckpoint();
  }

  @override
  Future<CheckpointInfo?> getCheckpointInfo() async {
    final info = await bridge.NativeBridge.sequencerGetCheckpointInfo();
    if (info == null) return null;

    return CheckpointInfo(
      sequenceName: info.sequenceName,
      timestamp: DateTime.parse(info.timestamp),
      completedExposures: info.completedExposures,
      completedIntegrationSecs: info.completedIntegrationSecs,
      canResume: info.canResume,
      ageSeconds: info.ageSeconds.toInt(),
    );
  }

  @override
  Future<void> resumeFromCheckpoint() async {
    await bridge.NativeBridge.sequencerResumeFromCheckpoint();
  }

  @override
  Future<void> performMeridianFlip({
    required String mountId,
    String? cameraId,
    String? focuserId,
    String? coverCalibratorId,
    required String targetName,
    required double targetRaHours,
    required double targetDecDegrees,
    required bool pauseGuiding,
    required bool autoCenter,
    required bool refocusAfter,
    required bool resumeGuiding,
    required double settleTimeSecs,
  }) async {
    await bridge.NativeBridge.performMeridianFlip(
      mountId: mountId,
      cameraId: cameraId,
      focuserId: focuserId,
      coverCalibratorId: coverCalibratorId,
      targetName: targetName,
      targetRaHours: targetRaHours,
      targetDecDegrees: targetDecDegrees,
      pauseGuiding: pauseGuiding,
      autoCenter: autoCenter,
      refocusAfter: refocusAfter,
      resumeGuiding: resumeGuiding,
      settleTimeSecs: settleTimeSecs,
    );
  }

  @override
  Future<void> discardCheckpoint() async {
    await bridge.NativeBridge.sequencerDiscardCheckpoint();
  }

  @override
  Future<void> saveCheckpoint() async {
    await bridge.NativeBridge.sequencerSaveCheckpoint();
  }

  @override
  Future<LocationSettings> getLocationFromInternet() async {
    try {
      final response = await http.get(Uri.parse('http://ip-api.com/json'));
      if (response.statusCode == 200) {
        // Why: ip-api.com returns a free-form JSON body. Validate it is a
        // map before indexing, and run each numeric field through
        // [safelyCastOpt] so a malformed payload surfaces a structured
        // CastFailureException (audit-rust §1.4, CLAUDE.md "errors are a
        // feature") instead of a bare TypeError or silent 0.0.
        final decoded = jsonDecode(response.body);
        final data = safelyCast<Map<String, dynamic>>(
          decoded,
          context: 'ip-api.com response body',
        );
        final lat = safelyCastOpt<num>(
          data['lat'],
          context: 'ip-api.com response["lat"]',
        );
        final lon = safelyCastOpt<num>(
          data['lon'],
          context: 'ip-api.com response["lon"]',
        );
        return LocationSettings(
          latitude: lat?.toDouble() ?? 0.0,
          longitude: lon?.toDouble() ?? 0.0,
          elevation: 0.0,
        );
      }
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'Failed to fetch location: HTTP ${response.statusCode}',
        isRecoverable: true,
      );
    } catch (e) {
      if (e is dart_error.NightshadeError) rethrow;
      throw dart_error.NightshadeError(
        category: dart_error.BackendErrorCategory.io,
        message: 'Error fetching location: $e',
        isRecoverable: true,
      );
    }
  }
}
