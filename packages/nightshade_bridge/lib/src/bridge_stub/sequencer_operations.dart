part of '../bridge_stub.dart';

extension _NativeBridgeSequencerOperations on _NativeBridgeImplementation {
  // =========================================================================
  // Sequencer API
  // =========================================================================

  /// Sequencer state
  CameraStatus? get cameraStatus => _cameraStatus;
  FocuserStatus? get focuserStatus => _focuserStatus;
  FilterWheelStatus? get filterWheelStatus => _filterWheelStatus;
  String? get loadedSequenceJson => _loadedSequenceJson;

  /// Subscribe to sequencer events (must be called to receive sequencer events)
  /// This sets up the event forwarding from the Rust sequencer to the main event stream
  Future<void> sequencerSubscribeEvents() async {
    if (_sequencerEventsSubscribed) return; // Already subscribed

    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSubscribeEvents');
    }

    try {
      await gen_api.apiSequencerSubscribeEvents();
      _sequencerEventsSubscribed = true;
      developer.log(
        '[Bridge] Subscribed to sequencer events via native',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error subscribing to sequencer events: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Load a sequence from JSON
  Future<void> sequencerLoadJson(String json) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerLoadJson');
    }

    try {
      await gen_api.apiSequencerLoadJson(json: json);
      _loadedSequenceJson = json;
    } catch (e) {
      developer.log(
        '[Bridge] Error loading sequence via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Set connected devices for the sequencer
  Future<void> sequencerSetDevices({
    String? cameraId,
    String? mountId,
    String? focuserId,
    String? filterwheelId,
    String? rotatorId,
    List<String>? filterNames,
    Map<String, int>? filterFocusOffsets,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetDevices');
    }

    try {
      await gen_api.apiSequencerSetDevices(
        cameraId: cameraId,
        mountId: mountId,
        focuserId: focuserId,
        filterwheelId: filterwheelId,
        rotatorId: rotatorId,
        filterNames: filterNames,
        filterFocusOffsets: filterFocusOffsets,
      );
      developer.log(
        '[Bridge] Set sequencer devices: camera=$cameraId, mount=$mountId, focuser=$focuserId, filterwheel=$filterwheelId, rotator=$rotatorId, filterNames=$filterNames, filterFocusOffsets=$filterFocusOffsets',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting sequencer devices: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Set the safety fail mode for the sequencer
  Future<void> sequencerSetSafetyFailMode(String mode) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSafetyFailMode');
    }

    try {
      await gen_api.apiSequencerSetSafetyFailMode(mode: mode);
      developer.log(
        '[Bridge] Set sequencer safety fail mode: $mode',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting sequencer safety fail mode: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Set the safety/humidity polling interval for the sequencer
  Future<void> sequencerSetSafetyCheckIntervalSeconds(int seconds) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSafetyCheckIntervalSeconds');
    }

    try {
      await gen_api.apiSequencerSetSafetyCheckIntervalSeconds(seconds: seconds);
      developer.log(
        '[Bridge] Set sequencer safety check interval: ${seconds}s',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting sequencer safety check interval: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Set the save path for sequencer images
  Future<void> sequencerSetSavePath({String? path}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSavePath');
    }

    try {
      await gen_api.apiSequencerSetSavePath(path: path);
      developer.log(
        '[Bridge] Set sequencer save path: ${path ?? "<none>"}',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting sequencer save path: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 8 Replay Debug â€” stamp the active `sequence_runs.id` on the
  /// Rust executor so every emitted `DecisionEvent` carries the FK.
  ///
  /// Wrapper around the FRB-generated `apiSequencerSetActiveSequenceRunId`
  /// in `api/sequencer.dart`, which itself gracefully degrades when the
  /// underlying `RustLib` binding hasn't been regenerated.
  Future<void> sequencerSetActiveSequenceRunId({int? sequenceRunId}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetActiveSequenceRunId');
    }
    try {
      await gen_api.apiSequencerSetActiveSequenceRunId(
        sequenceRunId: sequenceRunId,
      );
      developer.log(
        '[Bridge] Set active sequence_run_id: ${sequenceRunId ?? "<none>"}',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting active sequence_run_id: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 8 Replay Debug â€” runtime toggle for the decision-logging
  /// broadcast channel.
  Future<void> sequencerSetDecisionLoggingEnabled({
    required bool enabled,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetDecisionLoggingEnabled');
    }
    try {
      await gen_api.apiSequencerSetDecisionLoggingEnabled(enabled: enabled);
      developer.log(
        '[Bridge] Set decision logging enabled: $enabled',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting decision logging enabled: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Update dither configuration on the running sequencer
  Future<void> sequencerUpdateDitherConfig({
    required double pixels,
    required double settlePixels,
    required double settleTime,
    required double settleTimeout,
    required bool raOnly,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateDitherConfig');
    }

    try {
      await gen_api.apiSequencerUpdateDitherConfig(
        pixels: pixels,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
        raOnly: raOnly,
      );
      developer.log(
        '[Bridge] Updated sequencer dither config: pixels=$pixels, settlePixels=$settlePixels, settleTime=$settleTime, settleTimeout=$settleTimeout, raOnly=$raOnly',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating sequencer dither config: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Update location on the running sequencer
  Future<void> sequencerUpdateLocation({
    required double latitude,
    required double longitude,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateLocation');
    }

    try {
      await gen_api.apiSequencerUpdateLocation(
        latitude: latitude,
        longitude: longitude,
      );
      developer.log(
        '[Bridge] Updated sequencer location: lat=$latitude, lon=$longitude',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating sequencer location: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Update filter focus offsets on the running sequencer
  Future<void> sequencerUpdateFilterOffsets({
    required Map<String, int> offsets,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateFilterOffsets');
    }

    try {
      await gen_api.apiSequencerUpdateFilterOffsets(offsets: offsets);
      developer.log(
        '[Bridge] Updated sequencer filter offsets: $offsets',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating sequencer filter offsets: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 7.5 â€” stage per-target / per-filter carry-over integration on
  /// the executor so the next sequencerStart() seeds the
  /// IntegrationBudget tracker. See [api_sequencer_update_pending_integration_carry_over]
  /// for semantics; empty inner map zeroes a target's carry-over.
  Future<void> sequencerUpdatePendingIntegrationCarryOver({
    required Map<String, Map<String, double>> carryOver,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdatePendingIntegrationCarryOver');
    }

    try {
      await gen_api.apiSequencerUpdatePendingIntegrationCarryOver(
        carryOver: carryOver,
      );
      developer.log(
        '[Bridge] Staged integration carry-over for ${carryOver.length} targets',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error staging integration carry-over: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 1.5 Pack A: update the autofocus-interval trigger cadence at
  /// runtime. The bridge rejects 0 (the trigger evaluator treats 0 as
  /// disabled; use the per-trigger `enabled` toggle for that intent).
  Future<void> sequencerUpdateAutofocusInterval({
    required int everyNFrames,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateAutofocusInterval');
    }

    try {
      await gen_api.apiSequencerUpdateAutofocusInterval(
        everyNFrames: everyNFrames,
      );
      developer.log(
        '[Bridge] Updated sequencer autofocus-interval cadence: $everyNFrames frames',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating sequencer autofocus-interval cadence: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Pack G â€” update the global default image-grading thresholds. When
  /// `enabled` is false, grading is disabled globally (per-node
  /// `quality_check` on TakeExposure still wins). The four threshold
  /// fields are optional and respected only when enabled.
  Future<void> sequencerUpdateDefaultQualityCheck({
    double? hfrThreshold,
    double? hfrBaselinePercent,
    double? eccentricityThreshold,
    int? starCountMin,
    required int maxConsecutiveRejects,
    required bool enabled,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateDefaultQualityCheck');
    }

    try {
      await gen_api.apiSequencerUpdateDefaultQualityCheck(
        hfrThreshold: hfrThreshold,
        hfrBaselinePercent: hfrBaselinePercent,
        eccentricityThreshold: eccentricityThreshold,
        starCountMin: starCountMin,
        maxConsecutiveRejects: maxConsecutiveRejects,
        enabled: enabled,
      );
      developer.log(
        '[Bridge] Updated default_quality_check: enabled=$enabled, hfr=$hfrThreshold, baseline=$hfrBaselinePercent%, ecc=$eccentricityThreshold, stars=$starCountMin, maxRejects=$maxConsecutiveRejects',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating default_quality_check: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Pack G â€” update the reject-folder override. Pass `null` or empty
  /// string to fall back to `<save_path>/Reject/`.
  Future<void> sequencerUpdateRejectFolderPath({String? path}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateRejectFolderPath');
    }

    try {
      await gen_api.apiSequencerUpdateRejectFolderPath(path: path);
      developer.log(
        '[Bridge] Updated reject_folder_path: ${path ?? "<default>"}',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating reject_folder_path: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Pack G â€” push observer / equipment identification so the next FITS
  /// save stamps real keywords (OBSERVER, TELESCOP, FOCALLEN, APTDIA,
  /// INSTRUME, SITEELEV). Every field is optional â€” empty / null fields
  /// are omitted from FITS rather than emitted as sentinels.
  Future<void> sequencerUpdateObserverProfile({
    String? observerName,
    double? siteElevationM,
    String? cameraMake,
    String? cameraModel,
    String? telescopeName,
    double? telescopeFocalLengthMm,
    double? telescopeApertureMm,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateObserverProfile');
    }

    try {
      await gen_api.apiSequencerUpdateObserverProfile(
        observerName: observerName,
        siteElevationM: siteElevationM,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        telescopeName: telescopeName,
        telescopeFocalLengthMm: telescopeFocalLengthMm,
        telescopeApertureMm: telescopeApertureMm,
      );
      developer.log(
        '[Bridge] Updated observer_profile: observer=$observerName, telescope=$telescopeName, camera=$cameraMake $cameraModel',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating observer_profile: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 5 Agent 2 â€” push the latest live sky-brightness reading
  /// (mag/arcsecÂ²; bigger = darker) to the executor. Drives sky-
  /// brightness adaptive exposure decisions on the next TakeExposure
  /// burst. Pass `null` when the tracker has lost lock.
  Future<void> sequencerUpdateSkyBrightness({required double? mag}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateSkyBrightness');
    }

    try {
      await gen_api.apiSequencerUpdateSkyBrightness(mag: mag);
      developer.log(
        '[Bridge] Updated sky brightness: ${mag?.toStringAsFixed(2) ?? "<none>"} mag/arcsecÂ²',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating sky brightness: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 5 Agent 2 â€” push the global default sky-brightness adaptive
  /// exposure config. Per-node `ExposureNode.adaptiveExposure` overrides
  /// still win; this is the fallback applied to nodes that have none.
  ///
  /// The per-filter overrides are flattened into parallel
  /// (keys, values) lists because FRB cannot bridge `Map<String, T>`
  /// across the boundary.
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
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerUpdateDefaultAdaptiveExposure');
    }

    try {
      await gen_api.apiSequencerUpdateDefaultAdaptiveExposure(
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
      developer.log(
        '[Bridge] Updated default_adaptive_exposure: enabled=$enabled, ref=$referenceSkyBrightnessMag mag, min=${minExposureSecs}s, max=${maxExposureSecs}s, per_filter_enabled=${perFilterEnabled.length}',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error updating default_adaptive_exposure: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 5 Agent 2 â€” disable the global default sky-brightness
  /// adaptive exposure config. Convenience wrapper around the typed
  /// update for the "off" case.
  Future<void> sequencerClearDefaultAdaptiveExposure() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerClearDefaultAdaptiveExposure');
    }

    try {
      await gen_api.apiSequencerClearDefaultAdaptiveExposure();
      developer.log(
        '[Bridge] Cleared default_adaptive_exposure',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error clearing default_adaptive_exposure: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Start the loaded sequence
  Future<void> sequencerStart() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerStart');
    }

    // Ensure event subscription is set up before starting
    await sequencerSubscribeEvents();

    try {
      await gen_api.apiSequencerStart();
      _sequencerState = SequencerState.running;
    } catch (e) {
      developer.log(
        '[Bridge] Error starting sequence via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Pause the running sequence
  Future<void> sequencerPause() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerPause');
    }

    try {
      await gen_api.apiSequencerPause();
      _sequencerState = SequencerState.paused;
    } catch (e) {
      developer.log(
        '[Bridge] Error pausing sequence via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Resume a paused sequence
  Future<void> sequencerResume() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerResume');
    }

    try {
      await gen_api.apiSequencerResume();
      _sequencerState = SequencerState.running;
    } catch (e) {
      developer.log(
        '[Bridge] Error resuming sequence via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Stop the running sequence
  Future<void> sequencerStop() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerStop');
    }

    try {
      await gen_api.apiSequencerStop();
      _sequencerState = SequencerState.idle;
      _loadedSequenceJson = null;
    } catch (e) {
      developer.log(
        '[Bridge] Error stopping sequence via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Skip the current node
  Future<void> sequencerSkip() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSkip');
    }

    try {
      await gen_api.apiSequencerSkip();
    } catch (e) {
      developer.log(
        '[Bridge] Error skipping node via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 1.5 Pack A: jump execution to a specific node id. Preceding
  /// siblings are marked Skipped; the currently-running instruction
  /// completes first. Throws if the executor is not running.
  Future<void> sequencerSkipToNode({required String nodeId}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSkipToNode');
    }

    try {
      await gen_api.apiSequencerSkipToNode(nodeId: nodeId);
    } catch (e) {
      developer.log(
        '[Bridge] Error skipping to node "$nodeId" via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Wave 6 Pack P: report the verdict of a plugin-dispatched
  /// `NodeType::PluginNode` back to the Rust executor. The Rust side
  /// has a pending oneshot keyed on [nodeId]; the verdict resolves it
  /// and the awaiting instruction returns Success / Failure.
  Future<void> sequencerPluginNodeFinished({
    required String nodeId,
    required bool success,
    String? message,
    String? structuredDetailJson,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerPluginNodeFinished');
    }

    try {
      await gen_api.apiSequencerPluginNodeFinished(
        nodeId: nodeId,
        success: success,
        message: message,
        structuredDetailJson: structuredDetailJson,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error delivering plugin node verdict for "$nodeId" via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Reset the sequencer
  Future<void> sequencerReset() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerReset');
    }

    try {
      await gen_api.apiSequencerReset();
      _sequencerState = SequencerState.idle;
      _loadedSequenceJson = null;
    } catch (e) {
      developer.log(
        '[Bridge] Error resetting sequencer via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Get the current sequencer state
  SequencerState getSequencerState() => _sequencerState;

  /// Subscribe to sequencer events
  /// Returns a stream of sequencer events
  Stream<NightshadeEvent> sequencerEventStream() {
    if (!_nativeAvailable) {
      return Stream<NightshadeEvent>.error(
        UnsupportedError(
          'Operation "sequencerEventStream" requires the native bridge.\n$_fallbackErrorMessage',
        ),
      );
    }

    return gen_api.apiEventStream().where(
      (event) => event.category == gen_event.EventCategory.sequencer,
    );
  }

  /// Set simulation mode (use mock devices instead of real hardware)
  Future<void> sequencerSetSimulationMode(bool enabled) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetSimulationMode');
    }

    try {
      await gen_api.apiSequencerSetSimulationMode(enabled: enabled);
      _simulationMode = enabled;
      developer.log(
        '[Bridge] Simulation mode via native: ${enabled ? "enabled" : "disabled"}',
        name: 'NativeBridge',
        level: 800,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error setting simulation mode via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Check if simulation mode is enabled
  bool isSimulationMode() => _simulationMode;

  /// Get sequencer status
  Future<SequencerStatus> sequencerGetStatus() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerGetStatus');
    }

    try {
      final nativeState = await gen_api.apiSequencerGetState();
      // Calculate progress from exposures
      final progress = nativeState.totalExposures > 0
          ? nativeState.completedExposures / nativeState.totalExposures
          : 0.0;
      return SequencerStatus(
        state: nativeState.state,
        currentNodeId: nativeState.currentNodeId,
        currentNodeName: nativeState.currentNodeName,
        progress: progress,
        message: nativeState.message,
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error getting sequencer status via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  // =========================================================================
  // Checkpoint / Crash Recovery
  // =========================================================================

  /// Set the checkpoint directory
  Future<void> sequencerSetCheckpointDir(String path) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSetCheckpointDir');
    }

    try {
      await gen_api.apiSequencerSetCheckpointDir(path: path);
    } catch (e) {
      developer.log(
        '[Bridge] Error setting checkpoint dir via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Check if a checkpoint exists
  Future<bool> sequencerHasCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerHasCheckpoint');
    }

    try {
      return await gen_api.apiSequencerHasCheckpoint();
    } catch (e) {
      developer.log(
        '[Bridge] Error checking checkpoint via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Get checkpoint info
  Future<CheckpointInfoApi?> sequencerGetCheckpointInfo() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerGetCheckpointInfo');
    }

    try {
      final nativeInfo = await gen_api.apiSequencerGetCheckpointInfo();
      if (nativeInfo == null) return null;
      // Map from FRB-generated type to local type
      return CheckpointInfoApi(
        sequenceName: nativeInfo.sequenceName,
        timestamp: nativeInfo.timestamp,
        completedExposures: nativeInfo.completedExposures,
        completedIntegrationSecs: nativeInfo.completedIntegrationSecs,
        canResume: nativeInfo.canResume,
        ageSeconds: nativeInfo.ageSeconds.toInt(),
      );
    } catch (e) {
      developer.log(
        '[Bridge] Error getting checkpoint info via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Resume from checkpoint
  Future<void> sequencerResumeFromCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerResumeFromCheckpoint');
    }

    try {
      await gen_api.apiSequencerResumeFromCheckpoint();
      _sequencerState = SequencerState.running;
    } catch (e) {
      developer.log(
        '[Bridge] Error resuming from checkpoint via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Discard checkpoint
  Future<void> sequencerDiscardCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerDiscardCheckpoint');
    }

    try {
      await gen_api.apiSequencerClearCheckpoint();
    } catch (e) {
      developer.log(
        '[Bridge] Error discarding checkpoint via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }

  /// Save checkpoint
  Future<void> sequencerSaveCheckpoint() async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('sequencerSaveCheckpoint');
    }

    try {
      await gen_api.apiSequencerSaveCheckpoint();
    } catch (e) {
      developer.log(
        '[Bridge] Error saving checkpoint via native: $e',
        name: 'NativeBridge',
        level: 1000,
      );
      rethrow;
    }
  }
}
