part of '../network_backend.dart';

mixin _NetworkBackendSequencerOperations on _NetworkBackendTransport {
  // =========================================================================
  // Plate Solving
  // =========================================================================

  @override
  Future<PlateSolveResult> plateSolve({
    required String imagePath,
    double? ra,
    double? dec,
    double? fovDegrees,
  }) async {
    final response = await _post('plate-solve', {
      'imagePath': imagePath,
      if (ra != null) 'ra': ra,
      if (dec != null) 'dec': dec,
      if (fovDegrees != null) 'fov': fovDegrees,
    });

    return PlateSolveResult(
      success: response['success'] as bool,
      ra: (response['ra'] as num).toDouble(),
      dec: (response['dec'] as num).toDouble(),
      pixelScale: (response['pixelScale'] as num).toDouble(),
      rotation: (response['rotation'] as num).toDouble(),
      fieldWidth: (response['fieldWidth'] as num).toDouble(),
      fieldHeight: (response['fieldHeight'] as num).toDouble(),
      solveTimeSecs: (response['solveTimeSecs'] as num).toDouble(),
      error: response['error'] as String?,
    );
  }

  // =========================================================================
  // Sequencer Control
  // =========================================================================

  @override
  Future<void> sequencerStart() async {
    await _post('sequencer/start');
  }

  @override
  Future<void> sequencerStop() async {
    await _post('sequencer/stop');
  }

  @override
  Future<void> sequencerPause() async {
    await _post('sequencer/pause');
  }

  @override
  Future<void> sequencerResume() async {
    await _post('sequencer/resume');
  }

  @override
  Future<void> sequencerSkip() async {
    await _post('sequencer/skip');
  }

  @override
  Future<void> sequencerSkipToNode(String nodeId) async {
    // Wave 1.5 Pack A: forwarded to the remote host's sequencer.skip-to-node
    // endpoint. Server side maps to api_sequencer_skip_to_node.
    await _post('sequencer/skip-to-node', {'nodeId': nodeId});
  }

  @override
  Future<void> sequencerPluginNodeFinished({
    required String nodeId,
    required bool success,
    String? message,
    String? structuredDetailJson,
  }) async {
    // Wave 6 Pack P: forwarded to the remote host's plugin-node-finished
    // endpoint. Server side maps to `api_sequencer_plugin_node_finished`.
    // The remote backend will likely need to dispatch the plugin on the
    // host side too — Pack P does not yet wire the remote dispatch path
    // (that lands with the Wave 7 remote-protocol pack); for now this
    // is a faithful forwarder so the wire format is stable from day 1.
    await _post('sequencer/plugin-node-finished', {
      'nodeId': nodeId,
      'success': success,
      if (message != null) 'message': message,
      if (structuredDetailJson != null)
        'structuredDetailJson': structuredDetailJson,
    });
  }

  @override
  Future<void> sequencerReset() async {
    await _post('sequencer/reset');
  }

  @override
  Future<void> sequencerLoadJson(String json) async {
    await _post('sequencer/load', {'json': json});
  }

  @override
  Future<void> sequencerSetSimulationMode(bool enabled) async {
    await _post('sequencer/simulation', {'enabled': enabled});
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
    await _post('sequencer/devices', {
      'cameraId': cameraId,
      'mountId': mountId,
      'focuserId': focuserId,
      'filterwheelId': filterwheelId,
      'rotatorId': rotatorId,
      'filterNames': filterNames,
      'filterFocusOffsets': filterFocusOffsets,
    });
  }

  @override
  Future<void> sequencerSetSafetyFailMode(String mode) async {
    await _post('sequencer/safety-fail-mode', {'mode': mode});
  }

  @override
  Future<void> sequencerSetSafetyCheckIntervalSeconds(int seconds) async {
    await _post('sequencer/safety-check-interval', {'seconds': seconds});
  }

  @override
  Future<void> sequencerSetSavePath(String? path) async {
    await _post('sequencer/save-path', {'path': path});
  }

  @override
  Future<void> sequencerSetActiveSequenceRunId(int? sequenceRunId) async {
    // Wave 8 Replay Debug — POST through the standard sequencer
    // sub-API; the network backend just forwards primitives.
    await _post(
      'sequencer/active-sequence-run-id',
      {'sequence_run_id': sequenceRunId},
    );
  }

  @override
  Future<void> sequencerSetDecisionLoggingEnabled(bool enabled) async {
    // Wave 8 Replay Debug — runtime toggle.
    await _post(
      'sequencer/decision-logging-enabled',
      {'enabled': enabled},
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
    await _post('sequencer/update-dither-config', {
      'pixels': pixels,
      'settlePixels': settlePixels,
      'settleTime': settleTime,
      'settleTimeout': settleTimeout,
      'raOnly': raOnly,
    });
  }

  @override
  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    await _post('sequencer/update-location', {
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  @override
  Future<void> sequencerUpdateFilterOffsets(Map<String, int> offsets) async {
    await _post('sequencer/update-filter-offsets', {'offsets': offsets});
  }

  @override
  Future<void> sequencerUpdatePendingIntegrationCarryOver(
    Map<String, Map<String, double>> carryOver,
  ) async {
    // Wave 7.5 — remote staging mirrors the FFI path. The headless API
    // owns the deserialisation; an unrecognised endpoint on an older
    // headless build is surfaced (CLAUDE.md "errors are a feature").
    await _post('sequencer/update-pending-integration-carry-over', {
      'carry_over': carryOver,
    });
  }

  @override
  Future<void> sequencerUpdateAutofocusInterval(int everyNFrames) async {
    // Wave 1.5 Pack A: forwarded to the remote host's runtime-config update
    // endpoint. Server side maps to api_sequencer_update_autofocus_interval.
    await _post(
        'sequencer/update-autofocus-interval', {'everyNFrames': everyNFrames});
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
    // Pack G — forwarded to the remote host. Server side maps to
    // api_sequencer_update_default_quality_check.
    await _post('sequencer/update-default-quality-check', {
      'hfrThreshold': hfrThreshold,
      'hfrBaselinePercent': hfrBaselinePercent,
      'eccentricityThreshold': eccentricityThreshold,
      'starCountMin': starCountMin,
      'maxConsecutiveRejects': maxConsecutiveRejects,
      'enabled': enabled,
    });
  }

  @override
  Future<void> sequencerUpdateRejectFolderPath(String? path) async {
    // Pack G — forwarded to the remote host. Server side maps to
    // api_sequencer_update_reject_folder_path.
    await _post('sequencer/update-reject-folder-path', {'path': path});
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
    // Pack G — forwarded to the remote host. Server side maps to
    // api_sequencer_update_observer_profile.
    await _post('sequencer/update-observer-profile', {
      'observerName': observerName,
      'siteElevationM': siteElevationM,
      'cameraMake': cameraMake,
      'cameraModel': cameraModel,
      'telescopeName': telescopeName,
      'telescopeFocalLengthMm': telescopeFocalLengthMm,
      'telescopeApertureMm': telescopeApertureMm,
    });
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
    // Wave 5 Agent 4 — forwarded to the remote host so the remote rig's
    // executor sees the same analyzer reading the local controller has.
    await _post('sequencer/update-cloud-motion', {
      'currentCoverPercent': currentCoverPercent,
      'predictedArrivalMinutes': predictedArrivalMinutes,
      'predictedOpeningMinutes': predictedOpeningMinutes,
      'predictedOpeningDurationSecs': predictedOpeningDurationSecs,
      'predictedClearSkyAlt': predictedClearSkyAlt,
      'predictedClearSkyAz': predictedClearSkyAz,
    });
  }

  @override
  Future<String?> sequencerGetCloudMotionJson() async {
    // Wave 5 Agent 4 — fetched lazily by the dashboard tick. The remote
    // endpoint mirrors the local FRB call.
    try {
      final response = await _get('sequencer/cloud-motion');
      final json = response['cloud_motion'];
      return json is String ? json : null;
    } catch (_) {
      // The remote endpoint may not be implemented in older headless
      // servers; treat a 404 / parse error as "no data" rather than
      // failing the dashboard tick.
      return null;
    }
  }

  @override
  Future<void> sequencerUpdateConditionsScore(ConditionsScore? score) async {
    await _post('sequencer/update-conditions-score', {
      'score': score?.toJson(),
    });
  }

  @override
  Future<AdaptiveSwapSnapshot?> sequencerGetAdaptiveSwapSnapshot() async {
    final response = await _get('sequencer/adaptive-swap');
    final value = response['adaptive_swap'];
    if (value == null) return null;
    if (value is String) return AdaptiveSwapDriver.decodeSnapshotJson(value);
    if (value is Map<String, dynamic>) {
      return AdaptiveSwapSnapshot.fromJson(value);
    }
    if (value is Map) {
      return AdaptiveSwapSnapshot.fromJson(Map<String, dynamic>.from(value));
    }
    throw StateError(
      'Malformed adaptive_swap response: expected object, string, or null; '
      'got ${value.runtimeType}',
    );
  }

  @override
  Future<void> sequencerUpdateSkyBrightness({required double? mag}) async {
    // Wave 5 Agent 2 — forwarded to the remote host so the remote rig's
    // executor sees the same SkyBrightnessTracker reading the local
    // controller has. Older headless servers may not implement the
    // endpoint; we don't swallow errors here (the user explicitly
    // pushed and would want to know).
    await _post('sequencer/update-sky-brightness', {'mag': mag});
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
    await _post('sequencer/update-default-adaptive-exposure', {
      'enabled': enabled,
      'targetSnr': targetSnr,
      'referenceSkyBrightnessMag': referenceSkyBrightnessMag,
      'minExposureSecs': minExposureSecs,
      'maxExposureSecs': maxExposureSecs,
      'perFilterEnabled': perFilterEnabled,
      'perFilterMinSecs': perFilterMinSecs,
      'perFilterMaxSecs': perFilterMaxSecs,
    });
  }

  @override
  Future<void> sequencerClearDefaultAdaptiveExposure() async {
    await _post('sequencer/clear-default-adaptive-exposure', const {});
  }

  // =========================================================================
  // Wave 4 Recovery Mode
  // =========================================================================

  @override
  Future<void> recoveryTryNow() async {
    await _post('sequencer/recovery/try-now', const {});
  }

  @override
  Future<void> recoveryAbort() async {
    await _post('sequencer/recovery/abort', const {});
  }

  @override
  Future<void> updateRecoveryConfig({
    required double retryIntervalSecs,
    required double maxDurationSecs,
    required bool stopTrackingDuringRecovery,
    required bool abortOnMeridian,
    required bool audibleAlertWhenEntered,
  }) async {
    await _post('sequencer/recovery/update-config', {
      'retryIntervalSecs': retryIntervalSecs,
      'maxDurationSecs': maxDurationSecs,
      'stopTrackingDuringRecovery': stopTrackingDuringRecovery,
      'abortOnMeridian': abortOnMeridian,
      'audibleAlertWhenEntered': audibleAlertWhenEntered,
    });
  }

  @override
  Future<String?> getCurrentRecoveryJson() async {
    final response = await _get('sequencer/recovery/current');
    // The server returns `{"context": null}` for an idle executor or
    // `{"context": "<json>"}` while recovering.
    final ctx = response['context'];
    if (ctx == null) return null;
    return ctx as String;
  }

  @override
  Future<String> getRecoveryHistoryJson() async {
    final response = await _get('sequencer/recovery/history');
    return (response['history'] as String?) ?? '[]';
  }

  @override
  Future<SequencerStatus> sequencerGetStatus() async {
    final response = await _get('sequencer/status');
    return SequencerStatus(
      state: response['state'] as String? ?? 'Idle',
      currentNodeId: response['currentNodeId'] as String?,
      currentNodeName: response['currentNodeName'] as String?,
      progress: (response['progress'] as num?)?.toDouble() ?? 0.0,
      message: response['message'] as String?,
    );
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  @override
  Future<void> sequencerSetCheckpointDir(String path) async {
    await _post('sequencer/checkpoint/dir', {'path': path});
  }

  @override
  Future<bool> hasCheckpoint() async {
    final response = await _get('sequencer/checkpoint/has');
    return response['hasCheckpoint'] as bool? ?? false;
  }

  @override
  Future<CheckpointInfo?> getCheckpointInfo() async {
    final response = await _get('sequencer/checkpoint/info');
    if (response['info'] == null) return null;
    return CheckpointInfo.fromJson(response['info'] as Map<String, dynamic>);
  }

  @override
  Future<void> resumeFromCheckpoint() async {
    await _post('sequencer/checkpoint/resume', {});
  }

  @override
  Future<void> discardCheckpoint() async {
    await _post('sequencer/checkpoint/discard', {});
  }

  @override
  Future<void> saveCheckpoint() async {
    await _post('sequencer/checkpoint/save', {});
  }

  @override
  Future<LocationSettings> getLocationFromInternet() async {
    final response = await _get('location');
    return LocationSettings(
      latitude: (response['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (response['longitude'] as num?)?.toDouble() ?? 0.0,
      elevation: (response['elevation'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // =========================================================================
  // Equipment Status
  // =========================================================================

  @override
  Future<CameraStatus> getCameraStatus(String deviceId) async {
    final response =
        await _get('equipment/camera/status', {'deviceId': deviceId});
    return CameraStatus.fromJson(response);
  }

  @override
  Future<MountStatus> getMountStatus(String deviceId) async {
    final response =
        await _get('equipment/mount/status', {'deviceId': deviceId});
    return MountStatus.fromJson(response);
  }

  @override
  Future<FocuserStatus> getFocuserStatus(String deviceId) async {
    final response =
        await _get('equipment/focuser/status', {'deviceId': deviceId});
    return FocuserStatus.fromJson(response);
  }

  @override
  Future<FilterWheelStatus> getFilterWheelStatus(String deviceId) async {
    final response =
        await _get('equipment/filter-wheel/status', {'deviceId': deviceId});
    return FilterWheelStatus.fromJson(response);
  }

  @override
  Future<RotatorStatus> getRotatorStatus(String deviceId) async {
    final response =
        await _get('equipment/rotator/status', {'deviceId': deviceId});
    return RotatorStatus.fromJson(response);
  }

  // =========================================================================
  // Device Capabilities
  // =========================================================================

  @override
  Future<CameraCapabilities?> getCameraCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/camera/capabilities', {'deviceId': deviceId});
      return CameraCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get camera capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<MountCapabilities?> getMountCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/mount/capabilities', {'deviceId': deviceId});
      return MountCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get mount capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<FocuserCapabilities?> getFocuserCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/focuser/capabilities', {'deviceId': deviceId});
      return FocuserCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get focuser capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<FilterWheelCapabilities?> getFilterWheelCapabilities(
      String deviceId) async {
    try {
      final response = await _get(
          'equipment/filter-wheel/capabilities', {'deviceId': deviceId});
      return FilterWheelCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get filter wheel capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  @override
  Future<RotatorCapabilities?> getRotatorCapabilities(String deviceId) async {
    try {
      final response =
          await _get('equipment/rotator/capabilities', {'deviceId': deviceId});
      return RotatorCapabilities.fromJson(response);
    } catch (e) {
      developer.log('Failed to get rotator capabilities: $e',
          name: 'NetworkBackend', level: 1000, error: e);
      return null;
    }
  }

  // NOTE: The old _parseXxxCapabilities helpers have been removed.
  // Pure Dart types now have fromJson() factory constructors, which keep the
  // remote/network path in sync with new capability fields automatically.
}
