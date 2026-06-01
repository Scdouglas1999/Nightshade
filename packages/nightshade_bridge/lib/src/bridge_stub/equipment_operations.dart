part of '../bridge_stub.dart';

extension _NativeBridgeEquipmentOperations on _NativeBridgeImplementation {
  // =========================================================================
  // Camera Control
  // =========================================================================

  /// Get camera status
  Future<CameraStatus> getCameraStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getCameraStatus');
    }
    try {
      return await gen_api.getCameraStatus(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error getting camera status from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set camera cooler
  Future<void> setCameraCooler(
      String deviceId, bool enabled, double? targetTemp) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraCooler');
    }
    try {
      await gen_api.setCameraCooler(
        deviceId: deviceId,
        enabled: enabled ? 1 : 0,
        targetTemp: targetTemp,
      );
    } catch (e) {
      developer.log('[Bridge] Error setting camera cooler from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set camera gain
  Future<void> setCameraGain(String deviceId, int gain) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraGain');
    }
    try {
      await gen_api.setCameraGain(deviceId: deviceId, gain: gain);
    } catch (e) {
      developer.log('[Bridge] Error setting camera gain from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set camera offset
  Future<void> setCameraOffset(String deviceId, int offset) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraOffset');
    }
    try {
      await gen_api.setCameraOffset(deviceId: deviceId, offset: offset);
    } catch (e) {
      developer.log('[Bridge] Error setting camera offset from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set camera binning
  Future<void> setCameraBinning(String deviceId, int binX, int binY) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setCameraBinning');
    }
    try {
      await gen_api.apiSetCameraBinning(
          deviceId: deviceId, binX: binX, binY: binY);
    } catch (e) {
      developer.log('[Bridge] Error setting camera binning from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set camera readout mode by index
  /// modeIndex: 0 = default/high quality, 1 = fast readout, etc.
  Future<void> setReadoutMode({
    required String deviceId,
    required int modeIndex,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('setReadoutMode');
    }
    try {
      await gen_api.apiCameraSetReadoutMode(
        deviceId: deviceId,
        modeIndex: modeIndex,
      );
    } catch (e) {
      developer.log('[Bridge] Error calling native setReadoutMode: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Start a camera exposure
  Future<void> startExposure({
    required String deviceId,
    required double durationSecs,
    required int gain,
    required int offset,
    required int binX,
    required int binY,
  }) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('startExposure');
    }
    try {
      await gen_api.apiCameraStartExposure(
        deviceId: deviceId,
        durationSecs: durationSecs,
        gain: gain,
        offset: offset,
        binX: binX,
        binY: binY,
      );
    } catch (e) {
      developer.log('[Bridge] Error calling native startExposure: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Cancel current exposure
  Future<void> cancelExposure(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('cancelExposure');
    }
    try {
      await gen_api.apiCameraCancelExposure(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error calling native cancelExposure: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Get last captured image
  Future<CapturedImageResult?> getLastImage({required String deviceId}) async {
    // Why: trace-level (debug 500) â€” these three lines are diagnostic only
    // and were originally `debugPrint` for tracing the FRB getLastImage round
    // trip. Promoted into the structured logger so they participate in level
    // filtering / file rotation like the rest of the bridge.
    developer.log(
        '[Bridge] getLastImage called for device $deviceId, nativeAvailable=$_nativeAvailable',
        name: 'NativeBridge',
        level: 500);
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getLastImage');
    }
    try {
      developer.log('[Bridge] Calling crateApiApiGetLastImage...',
          name: 'NativeBridge', level: 500);
      final rustResult = await gen_api.apiGetLastImage(deviceId: deviceId);
      developer.log(
          '[Bridge] Got result: ${rustResult.width}x${rustResult.height}, displayData size: ${rustResult.displayData.length}',
          name: 'NativeBridge',
          level: 500);
      return rustResult;
    } catch (e) {
      developer.log('[Bridge] Error calling native getLastImage: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  // =========================================================================
  // Mount Control
  // =========================================================================

  /// Get mount status
  Future<MountStatus> getMountStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getMountStatus');
    }
    try {
      return await gen_api.apiGetMountStatus(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error getting mount status from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Slew the mount to coordinates
  Future<void> mountSlewToCoordinates(
      String deviceId, double ra, double dec) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSlewToCoordinates');
    }
    try {
      await gen_api.apiMountSlewToCoordinates(
          deviceId: deviceId, ra: ra, dec: dec);
    } catch (e) {
      developer.log('[Bridge] Error slewing mount via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Sync the mount to coordinates
  Future<void> mountSync(String deviceId, double ra, double dec) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSync');
    }
    try {
      await gen_api.apiMountSyncToCoordinates(
          deviceId: deviceId, ra: ra, dec: dec);
    } catch (e) {
      developer.log('[Bridge] Error syncing mount via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Park the mount
  Future<void> mountPark(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountPark');
    }
    try {
      await gen_api.apiMountPark(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error parking mount via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Unpark the mount
  Future<void> mountUnpark(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountUnpark');
    }
    try {
      await gen_api.apiMountUnpark(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error unparking mount via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set mount tracking
  Future<void> mountSetTracking(String deviceId, bool enabled) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSetTracking');
    }
    try {
      await gen_api.apiMountSetTracking(
          deviceId: deviceId, enabled: enabled ? 1 : 0);
    } catch (e) {
      developer.log('[Bridge] Error setting mount tracking via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Pulse guide mount
  Future<void> mountPulseGuide(
      String deviceId, String direction, int durationMs) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountPulseGuide');
    }
    try {
      await gen_api.apiMountPulseGuide(
        deviceId: deviceId,
        direction: direction,
        durationMs: durationMs,
      );
    } catch (e) {
      developer.log('[Bridge] Error pulse guiding mount via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Set mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
  Future<void> mountSetTrackingRate(String deviceId, int rate) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSetTrackingRate');
    }
    try {
      await gen_api.mountSetTrackingRate(deviceId: deviceId, rate: rate);
    } catch (e) {
      developer.log('[Bridge] Error setting tracking rate from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Get mount tracking rate (0=Sidereal, 1=Lunar, 2=Solar, 3=King)
  Future<int> mountGetTrackingRate(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountGetTrackingRate');
    }
    try {
      return await gen_api.mountGetTrackingRate(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error getting tracking rate from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Move mount axis at specified rate (degrees/second)
  /// axis: 0=RA/Azimuth (primary), 1=Dec/Altitude (secondary)
  /// rate: degrees per second (positive = N/E, negative = S/W), 0 to stop
  Future<void> mountMoveAxis(String deviceId, int axis, double rate) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountMoveAxis');
    }
    try {
      await gen_api.mountMoveAxis(deviceId: deviceId, axis: axis, rate: rate);
    } catch (e) {
      developer.log('[Bridge] Error moving axis from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Slew mount to alt/az coordinates
  Future<void> mountSlewAltAz(
      String deviceId, double altitude, double azimuth) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountSlewAltAz');
    }
    try {
      await gen_api.mountSlewAltAz(
          deviceId: deviceId, altitude: altitude, azimuth: azimuth);
    } catch (e) {
      developer.log('[Bridge] Error slewing mount to alt/az: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Find mount home position
  Future<void> mountFindHome(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountFindHome');
    }
    try {
      await gen_api.mountFindHome(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error finding mount home: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Abort current mount motion
  Future<void> mountAbort(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('mountAbort');
    }
    try {
      await gen_api.mountAbort(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error aborting mount motion: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  // =========================================================================
  // Focuser Control
  // =========================================================================

  /// Get focuser status
  Future<FocuserStatus> getFocuserStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getFocuserStatus');
    }
    try {
      return await gen_api.apiGetFocuserStatus(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error getting focuser status from native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Move focuser to position
  Future<void> focuserMoveTo(String deviceId, int position) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('focuserMoveTo');
    }
    try {
      await gen_api.apiFocuserMoveTo(deviceId: deviceId, position: position);
    } catch (e) {
      developer.log('[Bridge] Error moving focuser via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Move focuser by relative amount
  Future<void> focuserMoveRelative(String deviceId, int delta) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('focuserMoveRelative');
    }
    try {
      await gen_api.apiFocuserMoveRelative(deviceId: deviceId, delta: delta);
    } catch (e) {
      developer.log('[Bridge] Error moving focuser relative via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  /// Halt focuser
  Future<void> apiFocuserHalt({required String deviceId}) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('apiFocuserHalt');
    }
    try {
      await gen_api.apiFocuserHalt(deviceId: deviceId);
    } catch (e) {
      developer.log('[Bridge] Error halting focuser via native: $e',
          name: 'NativeBridge', level: 1000);
      rethrow;
    }
  }

  // =========================================================================
  // Filter Wheel Control
  // =========================================================================

  /// Get filter wheel status
  Future<FilterWheelStatus> getFilterWheelStatus(String deviceId) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getFilterWheelStatus');
    }
    try {
      return await gen_api.apiGetFilterwheelStatus(deviceId: deviceId);
    } catch (e) {
      developer.log(
          '[Bridge] Error getting filter wheel status from native: $e',
          name: 'NativeBridge',
          level: 1000);
      rethrow;
    }
  }

  /// Set filter wheel position
  Future<void> filterWheelSetPosition(String deviceId, int position) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('filterWheelSetPosition');
    }
    try {
      await gen_api.apiFilterwheelSetPosition(
          deviceId: deviceId, position: position);
    } catch (e) {
      developer.log(
          '[Bridge] Error setting filter wheel position via native: $e',
          name: 'NativeBridge',
          level: 1000);
      rethrow;
    }
  }

  /// Set filter wheel position (API method)
  Future<void> apiFilterwheelSetPosition({
    required String deviceId,
    required int position,
  }) async {
    await filterWheelSetPosition(deviceId, position);
  }

  /// Get filter wheel names (API method)
  Future<List<String>> apiFilterwheelGetNames({
    required String deviceId,
  }) async {
    final status = await getFilterWheelStatus(deviceId);
    return status.filterNames;
  }

  /// Set filter wheel by name (API method)
  Future<void> apiFilterwheelSetByName({
    required String deviceId,
    required String name,
  }) async {
    final status = await getFilterWheelStatus(deviceId);
    final index = status.filterNames.indexOf(name);
    if (index < 0) {
      throw ArgumentError('Filter "$name" not found on device $deviceId');
    }
    await filterWheelSetPosition(deviceId, index);
  }

  // =========================================================================
  // Session Management
  // =========================================================================

  /// Get current session state
  Future<NativeSessionState> getSessionState() async {
    return NativeSessionState(
      isActive: false,
      totalExposures: 0,
      completedExposures: 0,
      totalIntegrationSecs: 0.0,
      isGuiding: false,
      isCapturing: false,
      isDithering: false,
    );
  }

  /// Start a new imaging session
  Future<void> startSession(
      {String? targetName, double? ra, double? dec}) async {
    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.sequencer,
      eventType: 'SessionStarted',
      data: {'target': targetName},
    ));
  }

  /// End the current session
  Future<void> endSession() async {
    _eventController.add(_FallbackNightshadeEvent(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      severity: EventSeverity.info,
      category: EventCategory.sequencer,
      eventType: 'SessionEnded',
      data: {},
    ));
  }

  // =========================================================================
  // Plate Solving
  // =========================================================================

  /// Check if plate solver is available
  bool isPlateSolverAvailable() {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('isPlateSolverAvailable');
    }
    return gen_api.apiIsPlateSolverAvailable();
  }

  /// Get plate solver path
  String? getPlateSolverPath() {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('getPlateSolverPath');
    }
    return gen_api.apiGetPlateSolverPath();
  }

  /// Plate solve blind
  Future<PlateSolveResult> plateSolveBlind(String filePath) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('plateSolveBlind');
    }
    return gen_api.apiPlateSolveBlind(filePath: filePath);
  }

  /// Plate solve near coordinates
  Future<PlateSolveResult> plateSolveNear(
    String filePath,
    double hintRa,
    double hintDec,
    double searchRadius,
  ) async {
    if (!_nativeAvailable) {
      _nativeBridgeRequired('plateSolveNear');
    }
    return gen_api.apiPlateSolveNear(
      filePath: filePath,
      hintRa: hintRa,
      hintDec: hintDec,
      searchRadius: searchRadius,
    );
  }

  // =========================================================================
  // Autofocus
  // =========================================================================

  /// Run autofocus
  Future<AutofocusResultApi> apiRunAutofocus({
    required String deviceId,
    required String cameraId,
    required AutofocusConfigApi config,
  }) async {
    if (_nativeAvailable) {
      try {
        return await gen_api.apiRunAutofocus(
          deviceId: deviceId,
          cameraId: cameraId,
          config: config,
        );
      } catch (e) {
        developer.log('[Bridge] Error running autofocus via native: $e',
            name: 'NativeBridge', level: 1000);
        rethrow;
      }
    }
    throw UnsupportedError(_fallbackErrorMessage);
  }

  /// Cancel autofocus
  Future<void> apiCancelAutofocus() async {
    if (_nativeAvailable) {
      try {
        await gen_api.apiCancelAutofocus();
        return;
      } catch (e) {
        developer.log('[Bridge] Error cancelling autofocus via native: $e',
            name: 'NativeBridge', level: 1000);
        rethrow;
      }
    }
    throw UnsupportedError(_fallbackErrorMessage);
  }
}
