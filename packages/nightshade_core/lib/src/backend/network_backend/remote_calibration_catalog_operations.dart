part of '../network_backend.dart';

mixin _NetworkBackendRemoteCalibrationCatalogOperations
    on _NetworkBackendTransport {
  // =========================================================================
  // P1-10 — Remote calibration library management.
  // =========================================================================

  /// GET /api/calibration/darks — filtered listing.
  Future<List<RemoteDarkLibraryEntry>> listDarks({
    double? exposureSeconds,
    int? gain,
    double? temperatureCelsius,
    int? limit,
  }) async {
    final params = <String, dynamic>{};
    if (exposureSeconds != null) params['exposureSeconds'] = exposureSeconds;
    if (gain != null) params['gain'] = gain;
    if (temperatureCelsius != null) {
      params['temperatureC'] = temperatureCelsius;
    }
    if (limit != null) params['limit'] = limit;
    final response =
        await _get('calibration/darks', params.isEmpty ? null : params);
    return _rowsFromJson(response['darks'], RemoteDarkLibraryEntry.fromJson);
  }

  /// GET /api/calibration/darks/{id}.
  Future<RemoteDarkLibraryEntry> getDark(int id) async {
    final response = await _get('calibration/darks/$id');
    final row = response['dark'];
    if (row is! Map) {
      throw StateError('Malformed darks/{id} response: missing `dark` field');
    }
    return RemoteDarkLibraryEntry.fromJson(row.cast<String, dynamic>());
  }

  /// POST /api/calibration/darks — register an already-on-disk file.
  Future<RemoteDarkLibraryEntry> registerDark({
    required String filePath,
    required double exposureDuration,
    double? sensorTempC,
    int gain = 0,
    int offset = 0,
    int binX = 1,
    int binY = 1,
    String frameType = 'dark',
    int? width,
    int? height,
    int? frameCount,
    String? masterPath,
  }) async {
    final body = <String, dynamic>{
      'filePath': filePath,
      'exposureDuration': exposureDuration,
      if (sensorTempC != null) 'sensorTempC': sensorTempC,
      'gain': gain,
      'offset': offset,
      'binX': binX,
      'binY': binY,
      'frameType': frameType,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (frameCount != null) 'frameCount': frameCount,
      if (masterPath != null) 'masterPath': masterPath,
    };
    final response = await _post('calibration/darks', body);
    return RemoteDarkLibraryEntry.fromJson(
        (response['dark'] as Map).cast<String, dynamic>());
  }

  /// POST /api/calibration/darks/upload — upload a FITS file with metadata.
  ///
  /// The server stores the file under `$DATA_DIR/calibration/darks/` and
  /// inserts a row referencing it. We send the FITS as the raw body and
  /// the metadata as a JSON-encoded `meta` query parameter.
  Future<RemoteDarkLibraryEntry> uploadDark({
    required File darkFile,
    required DarkUploadMetadata metadata,
    String? fileName,
  }) async {
    final bytes = await darkFile.readAsBytes();
    final name = fileName ?? p.basename(darkFile.path);
    final meta = jsonEncode(metadata.toJson());
    final response = await _postRaw(
      'calibration/darks/upload',
      {'meta': meta, 'fileName': name},
      bytes,
      contentType: 'application/octet-stream',
    );
    return RemoteDarkLibraryEntry.fromJson(
        (response['dark'] as Map).cast<String, dynamic>());
  }

  /// POST /api/calibration/darks/find-match.
  Future<RemoteDarkLibraryEntry?> findMatchingDark({
    required double exposureDuration,
    int gain = 0,
    int offset = 0,
    int binX = 1,
    int binY = 1,
    double? sensorTempC,
    String frameType = 'dark',
    Map<String, dynamic>? tolerances,
  }) async {
    final body = <String, dynamic>{
      'exposureDuration': exposureDuration,
      'gain': gain,
      'offset': offset,
      'binX': binX,
      'binY': binY,
      if (sensorTempC != null) 'sensorTempC': sensorTempC,
      'frameType': frameType,
      if (tolerances != null) 'tolerances': tolerances,
    };
    try {
      final response = await _post('calibration/darks/find-match', body);
      return RemoteDarkLibraryEntry.fromJson(
          (response['dark'] as Map).cast<String, dynamic>());
    } on ServerError catch (e) {
      // [Wave 6D error parsing] — handler returns 404 + the structured
      // envelope {code: 'no_matching_dark'} when no dark satisfies the
      // requested parameters. Treating it as the legitimate "no match"
      // outcome (null) instead of an exception.
      if (e.code == 'no_matching_dark' ||
          (e.httpStatus == 404 && e.code.contains('no_matching'))) {
        return null;
      }
      rethrow;
    } on dart_error.NightshadeError catch (e) {
      // The handler returns 404 with `error: no_matching_dark` when no
      // dark matches the requested capture parameters. `_parseErrorResponse`
      // collapses the 404 into the `connection` category and stuffs the
      // server-side `error` field into the message, so we sniff for the
      // sentinel string to map the legitimate non-error outcome to null.
      if (e.category == dart_error.BackendErrorCategory.connection &&
          e.message.contains('no_matching_dark')) {
        return null;
      }
      rethrow;
    }
  }

  /// DELETE /api/calibration/darks/{id}?deleteFile=<bool>.
  Future<void> deleteDark(int id, {bool deleteFile = false}) async {
    if (deleteFile) {
      await _delete('calibration/darks/$id?deleteFile=true');
    } else {
      await _delete('calibration/darks/$id');
    }
  }

  /// POST /api/calibration/darks/backfill-sizes.
  ///
  /// Returns the raw counts map; callers usually only need to display the
  /// totals, so we don't bother wrapping in a typed model.
  Future<Map<String, int>> verifyDarkSizes() async {
    final response = await _post('calibration/darks/backfill-sizes');
    return {
      for (final entry in response.entries)
        if (entry.value is num) entry.key: (entry.value as num).toInt(),
    };
  }

  /// GET /api/calibration/flats — filtered listing.
  Future<List<RemoteFlatHistoryEntry>> listFlats({
    String? filter,
    int? equipmentProfileId,
    int? gain,
    DateTime? since,
    int? limit,
  }) async {
    final params = <String, dynamic>{};
    if (filter != null) params['filter'] = filter;
    if (equipmentProfileId != null) {
      params['equipmentProfileId'] = equipmentProfileId;
    }
    if (gain != null) params['gain'] = gain;
    if (since != null) params['since'] = since.toUtc().toIso8601String();
    if (limit != null) params['limit'] = limit;
    final response =
        await _get('calibration/flats', params.isEmpty ? null : params);
    return _rowsFromJson(response['flats'], RemoteFlatHistoryEntry.fromJson);
  }

  /// GET /api/calibration/flats/{id}.
  Future<RemoteFlatHistoryEntry> getFlat(int id) async {
    final response = await _get('calibration/flats/$id');
    return RemoteFlatHistoryEntry.fromJson(
        (response['flat'] as Map).cast<String, dynamic>());
  }

  /// POST /api/calibration/flats — record a flat-history entry.
  Future<RemoteFlatHistoryEntry> recordFlat({
    required String filter,
    required double exposureDuration,
    required int adu,
    double histogramTarget = 50.0,
    int gain = 0,
    int binning = 1,
    int? panelBrightness,
    double? skyAduRate,
    String? twilightPhase,
    int? equipmentProfileId,
  }) async {
    final body = <String, dynamic>{
      'filter': filter,
      'exposureDuration': exposureDuration,
      'adu': adu,
      'histogramTarget': histogramTarget,
      'gain': gain,
      'binning': binning,
      if (panelBrightness != null) 'panelBrightness': panelBrightness,
      if (skyAduRate != null) 'skyAduRate': skyAduRate,
      if (twilightPhase != null) 'twilightPhase': twilightPhase,
      if (equipmentProfileId != null) 'equipmentProfileId': equipmentProfileId,
    };
    final response = await _post('calibration/flats', body);
    return RemoteFlatHistoryEntry.fromJson(
        (response['flat'] as Map).cast<String, dynamic>());
  }

  /// DELETE /api/calibration/flats/{id}.
  Future<void> deleteFlat(int id) async {
    await _delete('calibration/flats/$id');
  }

  /// GET /api/calibration/flats/recommendation. Returns null when no
  /// matching history row is found.
  Future<RemoteFlatRecommendation?> getFlatRecommendation({
    required String filter,
    int? equipmentProfileId,
    int? gain,
  }) async {
    final params = <String, dynamic>{'filter': filter};
    if (equipmentProfileId != null) {
      params['equipmentProfileId'] = equipmentProfileId;
    }
    if (gain != null) params['gain'] = gain;
    final response = await _get('calibration/flats/recommendation', params);
    final recommended = response['recommended'];
    if (recommended == null || recommended is! Map) return null;
    final basedOn = recommended['basedOn'] as Map?;
    return RemoteFlatRecommendation(
      exposureDuration:
          (recommended['exposureDuration'] as num?)?.toDouble() ?? 0.0,
      basedOnFlatId: (basedOn?['flatId'] as num?)?.toInt() ?? 0,
      ageDays: (basedOn?['ageDays'] as num?)?.toInt() ?? 0,
      confidence: basedOn?['confidence'] as String? ?? 'low',
    );
  }

  /// GET /api/calibration/defect-maps — filtered list (no BLOB).
  Future<List<RemoteDefectMap>> listDefectMaps({
    String? cameraId,
    int? width,
    int? height,
    int? temperatureBucketDecicelsius,
  }) async {
    final params = <String, dynamic>{};
    if (cameraId != null) params['cameraId'] = cameraId;
    if (width != null) params['width'] = width;
    if (height != null) params['height'] = height;
    if (temperatureBucketDecicelsius != null) {
      params['temperatureBucketDecicelsius'] = temperatureBucketDecicelsius;
    }
    final response = await _get(
      'calibration/defect-maps',
      params.isEmpty ? null : params,
    );
    return _rowsFromJson(response['defectMaps'], RemoteDefectMap.fromJson);
  }

  /// GET /api/calibration/defect-maps/{id}?format=binary — fetch the
  /// packed bitmap as raw bytes.
  Future<Uint8List> getDefectMapBitmap(int id) async {
    return _downloadBytes('calibration/defect-maps/$id', {'format': 'binary'});
  }

  /// POST /api/calibration/defect-maps — register a defect map by metadata
  /// + base64 bitmap.
  Future<RemoteDefectMap> registerDefectMap({
    required String cameraId,
    required int width,
    required int height,
    required int temperatureBucketDecicelsius,
    required Uint8List bitmap,
    required int defectCount,
    String? sourceFilePath,
  }) async {
    final body = <String, dynamic>{
      'cameraId': cameraId,
      'width': width,
      'height': height,
      'temperatureBucketDecicelsius': temperatureBucketDecicelsius,
      'bitmap': base64Encode(bitmap),
      'defectCount': defectCount,
      if (sourceFilePath != null) 'sourceFilePath': sourceFilePath,
    };
    final response = await _post('calibration/defect-maps', body);
    return RemoteDefectMap.fromJson(
        (response['defectMap'] as Map).cast<String, dynamic>());
  }

  /// DELETE /api/calibration/defect-maps/{id}?deleteFile=<bool>.
  Future<void> deleteDefectMap(int id, {bool deleteFile = false}) async {
    if (deleteFile) {
      await _delete('calibration/defect-maps/$id?deleteFile=true');
    } else {
      await _delete('calibration/defect-maps/$id');
    }
  }

  /// POST /api/calibration/defect-maps/{id}/regenerate.
  Future<Map<String, dynamic>> regenerateDefectMap(int id) async {
    return _post('calibration/defect-maps/$id/regenerate');
  }

  // =========================================================================
  // P1-12 — Remote catalog management.
  // =========================================================================

  /// GET /api/catalog/status. Returns the on-disk state of every known
  /// catalog on the *server*. The mobile/desktop remote client surfaces
  /// this in the catalog management UI so a freshly-imaged server can be
  /// detected ("plate-solve will fail until you download a star catalog").
  Future<RemoteCatalogStatusResponse> getCatalogStatus() async {
    final response = await _get('catalog/status');
    return RemoteCatalogStatusResponse.fromJson(response);
  }

  /// GET /api/catalog/available. Returns the manifest of catalogs the
  /// server knows how to download. Cached server-side for 1 hour.
  Future<List<RemoteAvailableCatalog>> listAvailableCatalogs() async {
    final response = await _get('catalog/available');
    final raw = response['available'];
    if (raw is! List) {
      throw StateError('Malformed /catalog/available response: missing list');
    }
    return raw
        .whereType<Map>()
        .map((m) => RemoteAvailableCatalog.fromJson(m.cast<String, dynamic>()))
        .toList(growable: false);
  }

  /// POST /api/catalog/download. Returns the job handle; the actual
  /// download runs in the background and progress is broadcast as
  /// `catalog`-category events on the WS stream.
  Future<RemoteJob> downloadCatalog(String name) async {
    final response = await _post('catalog/download', {'name': name});
    return RemoteJob.fromJson(response);
  }

  /// POST /api/catalog/upload. Sends the file body with `name` + `sha256`
  /// as query parameters. The server verifies the SHA-256 before
  /// installing.
  Future<RemoteCatalogInstallResult> uploadCatalog(
    File archive, {
    required String name,
    required String sha256,
  }) async {
    final bytes = await archive.readAsBytes();
    final response = await _postRaw(
      'catalog/upload',
      {'name': name, 'sha256': sha256},
      bytes,
      contentType: 'application/octet-stream',
    );
    final installed = response['installed'];
    if (installed is! Map) {
      throw StateError(
          'Malformed /catalog/upload response: missing `installed` field');
    }
    return RemoteCatalogInstallResult.fromJson(
        installed.cast<String, dynamic>());
  }

  /// POST /api/catalog/verify. Recomputes SHA-256 over every (or one)
  /// installed catalog and returns the per-name verification result.
  Future<Map<String, RemoteCatalogVerifyResult>> verifyCatalog({
    String? name,
  }) async {
    final response =
        await _post('catalog/verify', name == null ? null : {'name': name});
    final verified = response['verified'];
    if (verified is! Map) {
      throw StateError(
          'Malformed /catalog/verify response: missing `verified` field');
    }
    return verified.map((key, value) {
      if (value is! Map) {
        throw StateError('Malformed verify result for `$key`: expected object');
      }
      return MapEntry(
        key.toString(),
        RemoteCatalogVerifyResult.fromJson(value.cast<String, dynamic>()),
      );
    });
  }

  /// DELETE /api/catalog/{name}.
  Future<void> uninstallCatalog(String name) async {
    await _delete('catalog/$name');
  }

  /// POST /api/catalog/reload. Drops the server's cached catalog loaders
  /// so subsequent searches re-parse the on-disk files.
  Future<void> reloadCatalogs() async {
    await _post('catalog/reload');
  }

  // =========================================================================
  // P2-8 — read-only DB endpoints. Each returns a paginated `{items, total}`
  // envelope. Methods live on NetworkBackend (not the NightshadeBackend
  // interface) because the local FfiBackend already exposes these via Drift
  // DAOs; the network path is the only one that needs an explicit GET.
  // =========================================================================
}
