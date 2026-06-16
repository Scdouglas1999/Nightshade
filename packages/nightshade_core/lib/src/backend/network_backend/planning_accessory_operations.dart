part of '../network_backend.dart';

mixin _NetworkBackendPlanningAccessoryOperations on _NetworkBackendTransport {
  // =========================================================================
  // Framing & Centering
  // =========================================================================

  /// Slew to target coordinates
  Future<void> slewToTarget(double ra, double dec) async {
    await _post('framing/slew-to-target', {'ra': ra, 'dec': dec});
  }

  /// Center on target with plate solving
  Future<Map<String, dynamic>> centerOnTarget({
    required double ra,
    required double dec,
    int? maxIterations,
    double? toleranceArcsec,
    double? exposureTime,
    int? binning,
    int? gain,
    bool? syncMount,
  }) async {
    final response = await _post('framing/center-on-target', {
      'ra': ra,
      'dec': dec,
      if (maxIterations != null) 'maxIterations': maxIterations,
      if (toleranceArcsec != null) 'toleranceArcsec': toleranceArcsec,
      if (exposureTime != null) 'exposureTime': exposureTime,
      if (binning != null) 'binning': binning,
      if (gain != null) 'gain': gain,
      if (syncMount != null) 'syncMount': syncMount,
    });
    return response;
  }

  /// Sync mount to coordinates
  Future<void> syncMountToCoordinates(double ra, double dec) async {
    await _post('framing/sync', {'ra': ra, 'dec': dec});
  }

  /// Get current mount position
  Future<Map<String, dynamic>> getCurrentPosition() async {
    final response = await _get('framing/current-position');
    return response;
  }

  /// Rotate to angle
  Future<void> rotateTo(double angle) async {
    await _post('framing/rotate-to', {'angle': angle});
  }

  /// Abort current slew
  Future<void> abortSlew() async {
    await _post('framing/abort-slew');
  }

  /// Park the mount
  Future<void> parkMountFraming() async {
    await _post('framing/park');
  }

  /// Unpark the mount
  Future<void> unparkMountFraming() async {
    await _post('framing/unpark');
  }

  /// Push a framing target to the imaging host (Plan Tonight handoff).
  Future<void> framingSetTarget({
    required double ra,
    required double dec,
    required String name,
  }) async {
    await _post('framing/set-target', {'ra': ra, 'dec': dec, 'name': name});
  }

  // ===========================================================================
  // Dome Control
  // ===========================================================================

  /// Open dome shutter
  Future<void> domeOpen() async {
    await _post('dome/open');
  }

  /// Close dome shutter
  Future<void> domeClose() async {
    await _post('dome/close');
  }

  /// Slew dome to azimuth
  Future<void> domeSlew(double azimuth) async {
    await _post('dome/slew', {'azimuth': azimuth});
  }

  /// Enable/disable dome-mount sync
  Future<void> domeSync(bool enable) async {
    await _post('dome/sync', {'enable': enable});
  }

  /// Park dome
  Future<void> domePark() async {
    await _post('dome/park');
  }

  /// Move dome to home position
  Future<void> domeHome() async {
    await _post('dome/home');
  }

  /// Halt dome movement
  Future<void> domeHalt() async {
    await _post('dome/halt');
  }

  /// Get dome status
  Future<Map<String, dynamic>> getDomeStatus() async {
    return await _get('dome/status');
  }

  /// Get dome capabilities
  Future<Map<String, dynamic>> getDomeCapabilities() async {
    return await _get('dome/capabilities');
  }

  // ===========================================================================
  // Safety Monitor
  // ===========================================================================

  /// Get safety status
  Future<Map<String, dynamic>> getSafetyStatus({String? deviceId}) async {
    return await _get(
      'safety/status',
      deviceId != null ? {'deviceId': deviceId} : null,
    );
  }

  /// Get safety settings
  Future<Map<String, dynamic>> getSafetySettings() async {
    return await _get('safety/settings');
  }

  /// Update safety settings
  Future<void> updateSafetySettings(Map<String, dynamic> settings) async {
    await _post('safety/settings', settings);
  }

  /// Acknowledge unsafe condition
  Future<void> acknowledgeSafetyCondition({
    required String reason,
    int? durationMinutes,
  }) async {
    await _post('safety/acknowledge', {
      'reason': reason,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
    });
  }

  // ===========================================================================
  // Switch Control
  // ===========================================================================

  /// Get switch states.
  ///
  /// Pass [deviceId] to scope to a single device — that returns the
  /// `{switchCount, switches:[...]}` single-device shape the per-channel UI
  /// consumes. Omit it for the all-devices summary
  /// (`{devicesConnected, devices:[...]}`).
  Future<Map<String, dynamic>> getSwitchStatus({String? deviceId}) async {
    return await _get('switch/status', {
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
    });
  }

  /// Set a switch value. [deviceId] is required by the server
  /// (`POST /api/switch/set`); [value] is a `bool` for boolean switches or a
  /// `num` for analog ones.
  Future<void> setSwitch({
    required String deviceId,
    required int switchId,
    required dynamic value,
  }) async {
    await _post('switch/set', {
      'deviceId': deviceId,
      'switchId': switchId,
      'value': value,
    });
  }

  // ===========================================================================
  // Cover Calibrator
  // ===========================================================================

  /// Get cover calibrator status
  Future<Map<String, dynamic>> getCoverStatus() async {
    return await _get('cover/status');
  }

  /// Open cover
  Future<void> coverOpen() async {
    await _post('cover/open');
  }

  /// Close cover
  Future<void> coverClose() async {
    await _post('cover/close');
  }

  /// Set calibrator brightness
  Future<void> setCoverBrightness(int brightness) async {
    await _post('cover/brightness', {'brightness': brightness});
  }

  /// Turn calibrator on
  Future<void> calibratorOn({int? brightness}) async {
    await _post('cover/calibrator-on', {
      if (brightness != null) 'brightness': brightness,
    });
  }

  /// Turn calibrator off
  Future<void> calibratorOff() async {
    await _post('cover/calibrator-off');
  }

  // ===========================================================================
  // Scheduler (Astronomical Calculations)
  // ===========================================================================

  /// Calculate altitude of object at given time
  Future<Map<String, dynamic>> getAltitude({
    required double ra,
    required double dec,
    DateTime? time,
  }) async {
    return await _get('scheduler/altitude', {
      'ra': ra,
      'dec': dec,
      if (time != null) 'time': time.toIso8601String(),
    });
  }

  /// Get transit time for object
  Future<Map<String, dynamic>> getTransitTime({
    required double ra,
    required double dec,
  }) async {
    return await _get('scheduler/transit-time', {'ra': ra, 'dec': dec});
  }

  /// Get rise and set times for object
  Future<Map<String, dynamic>> getRiseSetTimes({
    required double ra,
    required double dec,
    double? minAltitude,
  }) async {
    return await _get('scheduler/rise-set', {
      'ra': ra,
      'dec': dec,
      if (minAltitude != null) 'minAltitude': minAltitude,
    });
  }

  /// Get hours object is above altitude
  Future<Map<String, dynamic>> getHoursAboveHorizon({
    required double ra,
    required double dec,
    double minAltitude = 30.0,
  }) async {
    return await _get('scheduler/hours-above-horizon', {
      'ra': ra,
      'dec': dec,
      'minAltitude': minAltitude,
    });
  }

  /// Optimize target order for imaging
  Future<Map<String, dynamic>> optimizeTargets({
    required List<int> targetIds,
    String strategy = 'transit',
    double minAltitude = 30.0,
  }) async {
    return await _post('scheduler/optimize-targets', {
      'targetIds': targetIds,
      'strategy': strategy,
      'minAltitude': minAltitude,
    });
  }

  /// Get twilight times for tonight
  Future<Map<String, dynamic>> getTwilightTimes({DateTime? date}) async {
    return await _get(
      'scheduler/twilight-times',
      date != null ? {'date': date.toIso8601String()} : null,
    );
  }

  /// Get moon information
  Future<Map<String, dynamic>> getMoonInfo({DateTime? date}) async {
    return await _get(
      'scheduler/moon-info',
      date != null ? {'date': date.toIso8601String()} : null,
    );
  }

  // ===========================================================================
  // Focus Model
  // ===========================================================================

  /// Get all focus data points
  Future<Map<String, dynamic>> getFocusModelData() async {
    return await _get('focus-model/data');
  }

  /// Add a focus data point
  Future<void> addFocusDataPoint({
    required double temperature,
    required int position,
    double? hfr,
    String? filter,
  }) async {
    await _post('focus-model/add-point', {
      'temperature': temperature,
      'position': position,
      if (hfr != null) 'hfr': hfr,
      if (filter != null) 'filter': filter,
    });
  }

  /// Clear all focus data points
  Future<void> clearFocusModelData() async {
    await _delete('focus-model/clear');
  }

  /// Get current focus model
  Future<Map<String, dynamic>> getFocusModel() async {
    return await _get('focus-model/model');
  }

  /// Predict focus position for temperature
  Future<Map<String, dynamic>> predictFocusPosition({
    required double temperature,
    String? filter,
  }) async {
    return await _get('focus-model/predict', {
      'temperature': temperature,
      if (filter != null) 'filter': filter,
    });
  }

  /// Get per-filter focus offsets
  Future<Map<String, dynamic>> getFilterFocusOffsets() async {
    return await _get('focus-model/filter-offsets');
  }

  /// Set per-filter focus offsets
  Future<void> setFilterFocusOffsets({
    required String referenceFilter,
    required Map<String, int> offsets,
  }) async {
    await _post('focus-model/filter-offsets', {
      'referenceFilter': referenceFilter,
      'offsets': offsets,
    });
  }

  /// Check if refocus needed based on temperature drift
  Future<Map<String, dynamic>> shouldRefocus({
    required double currentTemp,
    required double lastFocusTemp,
    int? maxDriftSteps,
  }) async {
    return await _get('focus-model/should-refocus', {
      'currentTemp': currentTemp,
      'lastFocusTemp': lastFocusTemp,
      if (maxDriftSteps != null) 'maxDriftSteps': maxDriftSteps,
    });
  }

  /// Export focus data as JSON
  Future<Map<String, dynamic>> exportFocusModel() async {
    return await _get('focus-model/export');
  }

  /// Import focus data from JSON
  Future<void> importFocusModel(Map<String, dynamic> data) async {
    await _post('focus-model/import', data);
  }

  // ===========================================================================
  // PHD2 Additional Endpoints
  // ===========================================================================

  /// Get PHD2 star image
  Future<Map<String, dynamic>> getPhd2StarImage({int size = 50}) async {
    return await _get('phd2/star-image', {'size': size});
  }

  /// Get PHD2 algorithm parameter names
  Future<List<String>> getPhd2AlgoParamNames(String axis) async {
    final response = await _get('phd2/algo-params', {'axis': axis});
    return (response['parameters'] as List).cast<String>();
  }

  /// Get PHD2 algorithm parameter value
  Future<double> getPhd2AlgoParam({
    required String axis,
    required String name,
  }) async {
    final response = await _get('phd2/algo-param', {
      'axis': axis,
      'name': name,
    });
    return (response['value'] as num).toDouble();
  }

  /// Set PHD2 algorithm parameter
  Future<void> setPhd2AlgoParam({
    required String axis,
    required String name,
    required double value,
  }) async {
    await _post('phd2/algo-param', {
      'axis': axis,
      'name': name,
      'value': value,
    });
  }

  // ===========================================================================
  // Planetarium Support
  // ===========================================================================

  /// Get current mount position for planetarium FOV overlay
  Future<Map<String, dynamic>> getPlanetariumMountPosition() async {
    return await _get('planetarium/mount-position');
  }

  /// Get FOV configuration for planetarium
  Future<Map<String, dynamic>> getPlanetariumFovConfig() async {
    return await _get('planetarium/fov-config');
  }

  /// Slew to coordinates from planetarium
  Future<void> planetariumSlewTo({
    required double ra,
    required double dec,
  }) async {
    await _post('planetarium/slew-to', {'ra': ra, 'dec': dec});
  }

  /// Center on coordinates from planetarium with plate solving
  Future<Map<String, dynamic>> planetariumCenterOn({
    required double ra,
    required double dec,
    int? maxIterations,
    double? toleranceArcsec,
  }) async {
    return await _post('planetarium/center-on', {
      'ra': ra,
      'dec': dec,
      if (maxIterations != null) 'maxIterations': maxIterations,
      if (toleranceArcsec != null) 'toleranceArcsec': toleranceArcsec,
    });
  }

  /// Sync mount to coordinates from planetarium
  Future<void> planetariumSyncTo({
    required double ra,
    required double dec,
  }) async {
    await _post('planetarium/sync-to', {'ra': ra, 'dec': dec});
  }

  /// Search catalog for objects
  Future<Map<String, dynamic>> planetariumCatalogSearch(String query) async {
    return await _get('planetarium/catalog/search', {'query': query});
  }

  /// Get objects in a region
  Future<Map<String, dynamic>> planetariumCatalogRegion({
    required double ra,
    required double dec,
    required double radius,
    double? minMagnitude,
    double? maxMagnitude,
    int? limit,
  }) async {
    return await _get('planetarium/catalog/region', {
      'ra': ra,
      'dec': dec,
      'radius': radius,
      if (minMagnitude != null) 'minMagnitude': minMagnitude,
      if (maxMagnitude != null) 'maxMagnitude': maxMagnitude,
      if (limit != null) 'limit': limit,
    });
  }

  /// Get detailed object info
  Future<Map<String, dynamic>> planetariumGetObject(String objectId) async {
    return await _get(
      'planetarium/catalog/object/${Uri.encodeComponent(objectId)}',
    );
  }

  /// Get WebSocket subscription info for real-time updates
  Future<Map<String, dynamic>> getPlanetariumSubscribeInfo() async {
    return await _get('planetarium/subscribe-info');
  }

  /// Get observer location for planetarium calculations
  Future<Map<String, dynamic>> getPlanetariumLocation() async {
    return await _get('planetarium/location');
  }
}
