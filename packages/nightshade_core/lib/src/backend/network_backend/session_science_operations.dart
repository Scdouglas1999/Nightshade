part of '../network_backend.dart';

mixin _NetworkBackendSessionScienceOperations on _NetworkBackendTransport {
  // =========================================================================
  // Sessions & Analytics
  // =========================================================================

  /// Get all imaging sessions
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    final response = await _get('sessions');
    final sessionsList = response['sessions'] as List? ?? [];
    return sessionsList.cast<Map<String, dynamic>>();
  }

  /// Get active session
  Future<Map<String, dynamic>?> getActiveSession() async {
    try {
      final response = await _get('sessions/active');
      return response['session'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log(
        'Failed to get active session: $e',
        name: 'NetworkBackend',
        level: 1000,
        error: e,
      );
      return null;
    }
  }

  /// Get session by ID
  Future<Map<String, dynamic>?> getSessionById(int id) async {
    try {
      final response = await _get('sessions/$id');
      return response['session'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log(
        'Failed to get session $id: $e',
        name: 'NetworkBackend',
        level: 1000,
        error: e,
      );
      return null;
    }
  }

  /// Create a new session
  Future<int> createSession(Map<String, dynamic> session) async {
    final response = await _post('sessions', session);
    return response['id'] as int;
  }

  /// Update session fields (stats, notes, status).
  Future<void> updateSession(int id, Map<String, dynamic> body) async {
    await _put('sessions/$id', body);
  }

  /// End a session with the given status.
  Future<void> endSession(int id, {String status = 'completed'}) async {
    await _post('sessions/$id/end', {'status': status});
  }

  /// Sessions for a target.
  Future<List<Map<String, dynamic>>> getSessionsForTarget(int targetId) async {
    final response = await _get('sessions/target/$targetId');
    final sessions = response['sessions'] as List? ?? [];
    return sessions.cast<Map<String, dynamic>>();
  }

  /// Create a captured-image metadata row on the host.
  Future<int> createCapturedImage(Map<String, dynamic> image) async {
    final response = await _post('images', image);
    return response['id'] as int;
  }

  /// Patch captured-image metadata on the host.
  Future<void> updateCapturedImage(int id, Map<String, dynamic> patch) async {
    await _put('images/$id', patch);
  }

  /// Fetch one captured-image row by id.
  Future<Map<String, dynamic>?> getCapturedImageById(int id) async {
    try {
      final response = await _get('images/$id');
      return response['image'] as Map<String, dynamic>?;
    } catch (e) {
      developer.log(
        'Failed to get image $id: $e',
        name: 'NetworkBackend',
        level: 1000,
        error: e,
      );
      return null;
    }
  }

  /// Images for a target.
  Future<List<Map<String, dynamic>>> getImagesForTarget(int targetId) async {
    final response = await _get('images', {'targetId': targetId.toString()});
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  /// Thumbnail-strip rows for a producing exposure node.
  Future<List<Map<String, dynamic>>> getImagesByProducingNode(
    String producingNodeId, {
    String? producingRunId,
    int? limit,
  }) async {
    final params = <String, String>{
      'producingNodeId': producingNodeId,
      if (producingRunId != null) 'producingRunId': producingRunId,
      if (limit != null) 'limit': limit.toString(),
    };
    final response = await _get('images', params);
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  /// Get session statistics
  Future<Map<String, dynamic>> getSessionStats(int sessionId) async {
    final response = await _get('sessions/$sessionId/stats');
    return response['stats'] as Map<String, dynamic>? ?? {};
  }

  Future<Uint8List> downloadSessionExport(int sessionId, String format) async {
    return _downloadBytes('sessions/$sessionId/export/$format');
  }

  Future<List<PsfFieldTileRow>> getSessionPsfTiles(int sessionId) async {
    final response = await _get('sessions/$sessionId/psf-tiles');
    final tiles = response['psfTiles'] as List? ?? [];
    return tiles
        .cast<Map<String, dynamic>>()
        .map(_psfFieldTileFromJson)
        .toList();
  }

  Future<List<AstrometryResidualVectorRow>> getSessionResidualVectors(
    int sessionId,
  ) async {
    final response = await _get('sessions/$sessionId/residuals');
    final residuals = response['residuals'] as List? ?? [];
    return residuals
        .cast<Map<String, dynamic>>()
        .map(_residualVectorFromJson)
        .toList();
  }

  /// Get analytics summary
  Future<Map<String, dynamic>> getAnalyticsSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, dynamic>{};
    if (startDate != null) {
      params['startDate'] = startDate.millisecondsSinceEpoch.toString();
    }
    if (endDate != null) {
      params['endDate'] = endDate.millisecondsSinceEpoch.toString();
    }
    final response = await _get(
      'analytics/summary',
      params.isEmpty ? null : params,
    );
    return response;
  }

  /// Get total integration time
  Future<Map<String, dynamic>> getTotalIntegrationTime({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final params = <String, dynamic>{};
    if (startDate != null) {
      params['startDate'] = startDate.millisecondsSinceEpoch.toString();
    }
    if (endDate != null) {
      params['endDate'] = endDate.millisecondsSinceEpoch.toString();
    }
    final response = await _get(
      'analytics/integration-time',
      params.isEmpty ? null : params,
    );
    return response;
  }

  // =========================================================================
  // Weather & Radar
  // =========================================================================

  /// Get weather radar data
  Future<Map<String, dynamic>> getWeatherRadar(
    double lat,
    double lon, {
    bool forceRefresh = false,
  }) async {
    final response = await _get('weather/radar', {
      'lat': lat.toString(),
      'lon': lon.toString(),
      if (forceRefresh) 'refresh': 'true',
    });
    return response;
  }

  /// Get weather alerts
  Future<List<Map<String, dynamic>>> getWeatherAlerts() async {
    final response = await _get('weather/alerts');
    final alertsList = response['alerts'] as List? ?? [];
    return alertsList.cast<Map<String, dynamic>>();
  }

  /// Check safe imaging conditions
  Future<Map<String, dynamic>> checkSafeImaging() async {
    final response = await _get('weather/safe-imaging');
    return response;
  }

  /// Get weather settings
  Future<Map<String, dynamic>> getWeatherSettings() async {
    final response = await _get('weather/settings');
    return response['settings'] as Map<String, dynamic>? ?? {};
  }

  /// Update weather settings
  Future<void> updateWeatherSettings(Map<String, dynamic> settings) async {
    await _post('weather/settings', settings);
  }

  /// Clear weather cache
  Future<void> clearWeatherCache() async {
    await _post('weather/clear-cache');
  }

  // =========================================================================
  // Target Suggestions
  // =========================================================================

  /// Get target suggestions for tonight
  Future<Map<String, dynamic>> getSuggestionsForTonight({
    double? minAltitude,
    double? minScore,
    int? maxResults,
    String? sortMode,
    bool? prioritizeIncomplete,
    List<String>? objectTypes,
  }) async {
    final params = <String, dynamic>{};
    if (minAltitude != null) params['minAltitude'] = minAltitude.toString();
    if (minScore != null) params['minScore'] = minScore.toString();
    if (maxResults != null) params['maxResults'] = maxResults.toString();
    if (sortMode != null) params['sortMode'] = sortMode;
    if (prioritizeIncomplete != null) {
      params['prioritizeIncomplete'] = prioritizeIncomplete.toString();
    }
    if (objectTypes != null && objectTypes.isNotEmpty) {
      params['objectTypes'] = objectTypes.join(',');
    }
    final response = await _get(
      'suggestions/tonight',
      params.isEmpty ? null : params,
    );
    return response;
  }

  /// Get target score
  Future<Map<String, dynamic>> getTargetScore(int targetId) async {
    final response = await _get('suggestions/score/$targetId');
    return response;
  }

  // =========================================================================
  // Transient Alerts
  // =========================================================================

  /// Get active transient alerts
  Future<Map<String, dynamic>> getActiveTransients() async {
    final response = await _get('transients');
    return response;
  }

  /// Get transient settings
  Future<Map<String, dynamic>> getTransientSettings() async {
    final response = await _get('transients/settings');
    return response['settings'] as Map<String, dynamic>? ?? {};
  }

  /// Update transient settings
  Future<void> updateTransientSettings(Map<String, dynamic> settings) async {
    await _post('transients/settings', settings);
  }

  /// Queue a transient for observation
  Future<void> queueTransient(String transientId) async {
    await _post('transients/$transientId/queue');
  }

  /// Dismiss a transient
  Future<void> dismissTransient(String transientId) async {
    await _post('transients/$transientId/dismiss');
  }

  /// Refresh transient alerts
  Future<void> refreshTransientAlerts() async {
    await _post('transients/refresh');
  }

  /// Get queued transients
  Future<Map<String, dynamic>> getQueuedTransients() async {
    final response = await _get('transients/queued');
    return response;
  }

  // =========================================================================
  // Backup & Restore
  // =========================================================================

  /// List available backups
  Future<List<Map<String, dynamic>>> listBackups() async {
    final response = await _get('backup/list');
    final backupsList = response['backups'] as List? ?? [];
    return backupsList.cast<Map<String, dynamic>>();
  }

  /// Create a new backup
  Future<Map<String, dynamic>> createBackup({
    String? customPath,
    bool autoSave = false,
  }) async {
    final response = await _post('backup/create', {
      if (customPath != null) 'customPath': customPath,
      'autoSave': autoSave,
    });
    return response;
  }

  /// Restore from a backup
  Future<Map<String, dynamic>> restoreBackup(
    String filePath, {
    bool replaceExisting = false,
  }) async {
    final response = await _post('backup/restore', {
      'filePath': filePath,
      'replaceExisting': replaceExisting,
    });
    return response;
  }

  /// Delete a backup
  Future<void> deleteBackup(String backupId) async {
    await _delete('backup/$backupId');
  }

  /// Get backup metadata
  Future<Map<String, dynamic>> getBackupMetadata(String backupId) async {
    final response = await _get('backup/$backupId/metadata');
    return response;
  }

  /// Download backup file bytes
  Future<Uint8List> downloadBackup(String backupId) async {
    return _downloadBytes('backup/$backupId/download');
  }

  Future<Map<String, dynamic>> uploadBackupAndRestore(
    Uint8List bytes,
    String fileName, {
    bool replaceExisting = false,
  }) async {
    return _postRaw(
      'backup/upload-restore',
      {'fileName': fileName, 'replaceExisting': replaceExisting},
      bytes,
      contentType: 'application/octet-stream',
    );
  }

  Future<RemoteScienceBundle> getScienceSessionBundle(int sessionId) async {
    final response = await _get('science/session/$sessionId/bundle');
    return RemoteScienceBundle(
      photometry: _rowsFromJson<PhotometryMeasurementRow>(
        response['photometry'],
        PhotometryMeasurementRow.fromJson,
      ),
      calibrations: _rowsFromJson<FramePhotometricCalibrationRow>(
        response['calibrations'],
        FramePhotometricCalibrationRow.fromJson,
      ),
      transparency: _rowsFromJson<TransparencySampleRow>(
        response['transparency'],
        TransparencySampleRow.fromJson,
      ),
      psfTiles: _rowsFromJson<PsfFieldTileRow>(
        response['psfTiles'],
        PsfFieldTileRow.fromJson,
      ),
      frameQuality: _rowsFromJson<ScienceFrameQualityMetricsRow>(
        response['frameQuality'],
        ScienceFrameQualityMetricsRow.fromJson,
      ),
      tileMetrics: _rowsFromJson<ScienceTileMetricRow>(
        response['tileMetrics'],
        ScienceTileMetricRow.fromJson,
      ),
      residuals: _rowsFromJson<AstrometryResidualVectorRow>(
        response['residuals'],
        AstrometryResidualVectorRow.fromJson,
      ),
      movingObjects: _rowsFromJson<MovingObjectCandidateRow>(
        response['movingObjects'],
        MovingObjectCandidateRow.fromJson,
      ),
      lineRatios: _rowsFromJson<LineRatioProductRow>(
        response['lineRatios'],
        LineRatioProductRow.fromJson,
      ),
    );
  }

  Future<RemoteScienceBundle> getSessionlessScienceBundle() async {
    final response = await _get('science/sessionless/recent');
    return RemoteScienceBundle(
      photometry: _rowsFromJson<PhotometryMeasurementRow>(
        response['photometry'],
        PhotometryMeasurementRow.fromJson,
      ),
      calibrations: _rowsFromJson<FramePhotometricCalibrationRow>(
        response['calibrations'],
        FramePhotometricCalibrationRow.fromJson,
      ),
      transparency: _rowsFromJson<TransparencySampleRow>(
        response['transparency'],
        TransparencySampleRow.fromJson,
      ),
      psfTiles: _rowsFromJson<PsfFieldTileRow>(
        response['psfTiles'],
        PsfFieldTileRow.fromJson,
      ),
      frameQuality: _rowsFromJson<ScienceFrameQualityMetricsRow>(
        response['frameQuality'],
        ScienceFrameQualityMetricsRow.fromJson,
      ),
      tileMetrics: _rowsFromJson<ScienceTileMetricRow>(
        response['tileMetrics'],
        ScienceTileMetricRow.fromJson,
      ),
      residuals: _rowsFromJson<AstrometryResidualVectorRow>(
        response['residuals'],
        AstrometryResidualVectorRow.fromJson,
      ),
      movingObjects: _rowsFromJson<MovingObjectCandidateRow>(
        response['movingObjects'],
        MovingObjectCandidateRow.fromJson,
      ),
      lineRatios: _rowsFromJson<LineRatioProductRow>(
        response['lineRatios'],
        LineRatioProductRow.fromJson,
      ),
    );
  }

  Future<List<PhotometricTransformRow>> getPhotometricTransforms({
    int? profileId,
  }) async {
    final response = await _get(
      'science/transforms',
      profileId == null ? null : {'profileId': profileId.toString()},
    );
    return _rowsFromJson<PhotometricTransformRow>(
      response['transforms'],
      PhotometricTransformRow.fromJson,
    );
  }

  Future<List<CatalogStarMatch>> matchPhotometricCalibrationStars(
    int imageId,
  ) async {
    final response = await _post(
      'science/calibration/image/$imageId/match-stars',
      const {},
    );
    return _rowsFromJson<CatalogStarMatch>(
      response['starMatches'],
      CatalogStarMatch.fromJson,
    );
  }

  Future<PhotometricTransformCoefficients?> computePhotometricTransform({
    required List<CatalogStarMatch> starMatches,
    required String filterName,
    int? equipmentProfileId,
  }) async {
    final response = await _post('science/calibration/compute-transform', {
      'starMatches': starMatches.map((match) => match.toJson()).toList(),
      'filterName': filterName,
      if (equipmentProfileId != null) 'equipmentProfileId': equipmentProfileId,
    });
    final coefficients = response['coefficients'];
    if (coefficients is Map<String, dynamic>) {
      return PhotometricTransformCoefficients.fromJson(coefficients);
    }
    if (coefficients is Map) {
      return PhotometricTransformCoefficients.fromJson(
        coefficients.cast<String, dynamic>(),
      );
    }
    return null;
  }

  Future<int> savePhotometricTransform(
    PhotometricTransformCoefficients coefficients,
  ) async {
    final response = await _post('science/calibration/save-transform', {
      'coefficients': coefficients.toJson(),
    });
    return (response['id'] as num?)?.toInt() ?? 0;
  }

  Future<Map<String, dynamic>> generateSessionLineRatios(int sessionId) async {
    return _post('science/session/$sessionId/generate-line-ratios', {});
  }

  Future<Map<String, String>> getScienceSettings() async {
    final response = await _get('science/settings');
    return (response['settings'] as Map? ?? const {})
        .cast<String, dynamic>()
        .map((key, value) => MapEntry(key, value.toString()));
  }

  Future<void> updateScienceSettings(Map<String, String> settings) async {
    await _post('science/settings', {'settings': settings});
  }

  Future<ScienceSessionConfig?> getScienceSessionConfig(int sessionId) async {
    final response = await _get('science/session/$sessionId/config');
    final config = response['config'];
    if (config is Map<String, dynamic>) {
      return ScienceSessionConfig.fromJson(config);
    }
    if (config is Map) {
      return ScienceSessionConfig.fromJson(config.cast<String, dynamic>());
    }
    return null;
  }

  Future<void> updateScienceSessionConfig(
    int sessionId,
    ScienceSessionConfig config,
  ) async {
    await _post('science/session/$sessionId/config', {
      'config': config.toJson(),
    });
  }

  Future<Uint8List> exportSessionAavso(
    int sessionId, {
    required String targetStarName,
    String? filterBand,
    String? chartId,
  }) async {
    return _postRawBytes('science/session/$sessionId/export/aavso', {
      'targetStarName': targetStarName,
      if (filterBand != null && filterBand.isNotEmpty) 'filterBand': filterBand,
      if (chartId != null && chartId.isNotEmpty) 'chartId': chartId,
    });
  }

  Future<Uint8List> generateObservationReport(int sessionId) async {
    return _downloadBytes('science/session/$sessionId/report/pdf');
  }

  // =========================================================================
  // Remote Filesystem
  // =========================================================================

  Future<RemoteDirectoryListing> browseRemoteDirectories({String? path}) async {
    final response = await _get(
      'files/browse',
      path == null || path.isEmpty ? null : {'path': path},
    );
    return RemoteDirectoryListing.fromJson(response);
  }

  Future<Map<String, dynamic>> validateRemoteDirectory(
    String path, {
    bool mustExist = false,
    bool mustBeWritable = false,
  }) async {
    return _post('files/validate', {
      'path': path,
      'mustExist': mustExist,
      'mustBeWritable': mustBeWritable,
    });
  }

  PsfFieldTileRow _psfFieldTileFromJson(Map<String, dynamic> json) {
    return PsfFieldTileRow(
      id: json['id'] as int,
      capturedImageId: json['capturedImageId'] as int?,
      sessionId: json['sessionId'] as int?,
      tileRow: json['tileRow'] as int? ?? 0,
      tileCol: json['tileCol'] as int? ?? 0,
      starCount: json['starCount'] as int? ?? 0,
      medianFwhm: (json['medianFwhm'] as num?)?.toDouble() ?? 0.0,
      medianHfr: (json['medianHfr'] as num?)?.toDouble() ?? 0.0,
      medianEccentricity:
          (json['medianEccentricity'] as num?)?.toDouble() ?? 0.0,
      roundness: (json['roundness'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
    );
  }

  AstrometryResidualVectorRow _residualVectorFromJson(
    Map<String, dynamic> json,
  ) {
    return AstrometryResidualVectorRow(
      id: json['id'] as int,
      capturedImageId: json['capturedImageId'] as int?,
      sessionId: json['sessionId'] as int?,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      dxArcsec: (json['dxArcsec'] as num?)?.toDouble() ?? 0.0,
      dyArcsec: (json['dyArcsec'] as num?)?.toDouble() ?? 0.0,
      magnitudeArcsec: (json['magnitudeArcsec'] as num?)?.toDouble() ?? 0.0,
      recommendationCode: json['recommendationCode'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['timestamp'] as int? ?? 0,
      ),
    );
  }
}
