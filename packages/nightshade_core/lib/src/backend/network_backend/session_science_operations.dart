part of '../network_backend.dart';

mixin _NetworkBackendSessionScienceOperations on _NetworkBackendTransport {
  /// True pixel dimensions of a host FITS file. Used by the photometric
  /// calibration wizard to size images exactly on a remote client instead of
  /// estimating from the detected-star bounding box. Returns null if the host
  /// has no such file.
  Future<({int width, int height})?> getFitsDimensions(String hostPath) async {
    try {
      final response = await _get('imaging/fits-dimensions', {
        'path': hostPath,
      });
      return (
        width: (response['width'] as num).toInt(),
        height: (response['height'] as num).toInt(),
      );
    } catch (_) {
      return null;
    }
  }

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

  /// Count "untracked" library targets eligible for the Analytics cleanup
  /// (no integration goal, not a favorite, no captured subs, no integration
  /// time, not referenced by any session). The session-aware predicate runs
  /// against the host DB, so a remote client asks the host instead of guessing.
  Future<int> countUntrackedTargets() async {
    final response = await _get('analytics/untracked-targets/count');
    return (response['count'] as num?)?.toInt() ?? 0;
  }

  /// Permanently remove every untracked library target on the host and return
  /// the number deleted. Irreversible — the caller confirms with the user first.
  Future<int> removeUntrackedTargets() async {
    final response = await _post(
      'analytics/untracked-targets/remove',
      const {},
    );
    return (response['deleted'] as num?)?.toInt() ?? 0;
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
  // Night Narrator feed (read-only)
  // =========================================================================

  /// Fetch the appliance's narrator feed for a session (pinned-first,
  /// newest-first). Returns the raw event maps; callers reconstruct
  /// `NarratorEvent` via `narratorEventFromWireJson`. The narrator runs on the
  /// host, so a remote client reads its feed here instead of the local DB.
  Future<List<Map<String, dynamic>>> getNarratorFeed(int sessionId) async {
    final json = await _get('narrator/feed', {
      'sessionId': sessionId.toString(),
    });
    return _narratorEventsList(json);
  }

  /// Fetch the appliance's sessionless recent narrator feed.
  Future<List<Map<String, dynamic>>> getRecentNarratorFeed({
    int limit = 50,
  }) async {
    final json = await _get('narrator/recent', {'limit': limit.toString()});
    return _narratorEventsList(json);
  }

  List<Map<String, dynamic>> _narratorEventsList(Map<String, dynamic> json) {
    final raw = json['events'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  // =========================================================================
  // First Light — difference-imaging transient discovery (read + triage)
  // =========================================================================

  /// Fetch the appliance's First Light transient detections (newest-first).
  /// Pass [sessionId] for a single session, or null for the across-sessions
  /// feed. The difference pipeline runs on the host, so a remote client reads
  /// its persisted candidates here instead of the local DB. Callers
  /// reconstruct rows via `transientDetectionFromWireJson`.
  Future<List<Map<String, dynamic>>> getFirstLightCandidates({
    int? sessionId,
  }) async {
    final json = await _get(
      'firstlight/candidates',
      sessionId == null ? null : {'sessionId': sessionId.toString()},
    );
    final raw = json['candidates'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Fetch the host's cross-night history for one transient: every persisted
  /// detection within [radiusDeg] of ([raDeg], [decDeg]), oldest-first. Backs
  /// the multi-night light-curve detail view so the same source seen over
  /// several nights groups into one Δmag-vs-time history on a slave too.
  Future<List<Map<String, dynamic>>> getFirstLightHistory({
    required double raDeg,
    required double decDeg,
    double radiusDeg = 0.02,
  }) async {
    final json = await _get('firstlight/near', {
      'ra': raDeg.toString(),
      'dec': decDeg.toString(),
      'radius': radiusDeg.toString(),
    });
    final raw = json['detections'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Mark a First Light detection reviewed (confirmed) on the host.
  Future<void> reviewFirstLightCandidate(int id) async {
    await _post('firstlight/$id/review');
  }

  /// Dismiss a First Light detection as a triaged artefact on the host so the
  /// next difference scan suppresses the same position.
  Future<void> dismissFirstLightCandidate(int id) async {
    await _post('firstlight/$id/dismiss');
  }

  /// Fetch a REAL per-detection pixel postage stamp (PNG bytes) for detection
  /// [id], [stage] = `template` | `science` | `residual`. The host re-derives the
  /// deterministic crop filename from the persisted detection row and streams the
  /// PNG the difference pass wrote, so a companion tablet sees the actual pixels
  /// around the candidate — not a host-local file path. Maps to the advertised
  /// `GET /api/firstlight/<id>/crops/<stage>`.
  Future<Uint8List> getFirstLightCrop(int id, String stage) {
    return _downloadBytes('firstlight/$id/crops/$stage');
  }

  /// Trigger a REAL TNS submission for detection [id] ON THE HOST. The host
  /// holds the bot credentials + api key (the api key never crosses the wire);
  /// the slave only triggers and surfaces the result. Returns the host's
  /// `{success, atName?, reportId?, message}` payload.
  Future<Map<String, dynamic>> submitFirstLightToTns(int id) async {
    return _post('firstlight/$id/submit/tns');
  }

  /// Ask the host to generate an ingestible AAVSO Extended File Format report
  /// for detection [id] and return the bytes (the slave saves / share-sheets
  /// them — there is no per-observer AAVSO upload API; WebObs upload is manual).
  /// [magZeroPoint] is required (a calibrated magnitude); the host returns 400
  /// if unavailable.
  Future<Uint8List> exportFirstLightAavso(
    int id, {
    required double magZeroPoint,
    String? standardBand,
  }) async {
    return _postRawBytes('firstlight/$id/export/aavso', {
      'magZeroPoint': magZeroPoint,
      if (standardBand != null && standardBand.isNotEmpty)
        'standardBand': standardBand,
    });
  }

  /// Ask the host to generate an MPC ADES PSV astrometry report for detection
  /// [id] and return the bytes (MPC submission is via the web form / email).
  Future<Uint8List> exportFirstLightMpc(int id) async {
    return _postRawBytes('firstlight/$id/export/mpc', const {});
  }

  // =========================================================================
  // Sky Atlas — Pillar A ("Your Sky") personal atlas (read-only)
  // =========================================================================

  /// Fetch the host's persisted atlas regions (the "Your Sky" browser list).
  /// The imaging pipeline that folds frames into the atlas runs on the host, so
  /// a remote client reads its regions here instead of its (empty) local store.
  /// Callers reconstruct rows via `skyAtlasRegionFromWireJson`.
  Future<List<Map<String, dynamic>>> getAtlasRegions() async {
    final json = await _get('atlas/regions');
    final raw = json['regions'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Fetch the host's per-tile atlas coverage (deepest first) — the heat-overlay
  /// / gallery feed and the source of the Constellation "your contribution" sum.
  /// The native coverage query runs on the host. Callers reconstruct rows via
  /// `AtlasTileCoverage.fromJson`.
  Future<List<Map<String, dynamic>>> getAtlasCoverage() async {
    final json = await _get('atlas/coverage');
    final raw = json['tiles'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Fetch one region's detail from the host: its row (`region`), live native
  /// cone coverage (`coverage`) and the region's tiles (`tiles`). Backs the
  /// companion's region-detail screen, which reads an empty local store on a
  /// slave and so must branch here. Maps to the already-advertised
  /// `GET /api/atlas/region/<id>` route (no catalog change).
  Future<Map<String, dynamic>> getAtlasRegion(int regionId) async {
    return _get('atlas/region/$regionId');
  }

  /// Fetch a region's fold timeline (`folds`) + deepening growth curve
  /// (`growth`) from the host — the scrubber stops + contributing-frames list on
  /// a slave. Maps to the advertised `GET /api/atlas/region/<id>/timeline`.
  Future<Map<String, dynamic>> getAtlasRegionTimeline(int regionId) async {
    return _get('atlas/region/$regionId/timeline');
  }

  /// Fetch the co-added region cone as PNG bytes (latest depth) so the companion
  /// renders the cutout via `Image.memory` — the host-local file path the FFI
  /// path uses is not portable over the wire. Maps to the advertised
  /// `GET /api/atlas/region/<id>/cutout`.
  Future<Uint8List> getAtlasRegionCutout(
    int regionId, {
    int outPixels = 2048,
    String? interp,
  }) {
    return _downloadBytes('atlas/region/$regionId/cutout', {
      'outPixels': outPixels.toString(),
      if (interp != null) 'interp': interp,
    });
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
