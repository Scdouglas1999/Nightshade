part of '../network_backend.dart';

mixin _NetworkBackendImagingProfileOperations on _NetworkBackendTransport {
  // =========================================================================
  // Equipment Profiles
  // =========================================================================

  @override
  Future<List<EquipmentProfile>> getProfiles() async {
    final response = await _get('profiles');
    return (response['profiles'] as List)
        .map((p) => EquipmentProfile.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveProfile(EquipmentProfile profile) async {
    await _post('profiles', {'profile': profile.toJson()});
  }

  @override
  Future<void> deleteProfile(String profileId) async {
    await _delete('profiles/$profileId');
  }

  @override
  Future<void> loadProfile(String profileId) async {
    await _post('profiles/$profileId/load');
  }

  @override
  Future<EquipmentProfile?> getActiveProfile() async {
    final response = await _get('profiles/active');
    if (response['profile'] == null) return null;
    return EquipmentProfile.fromJson(
      response['profile'] as Map<String, dynamic>,
    );
  }

  // =========================================================================
  // Settings & Location
  // =========================================================================

  @override
  Future<models.AppSettings> getSettings() async {
    final json = await _get('settings');
    final settingsJson = json['settings'];
    if (settingsJson is! Map<String, dynamic>) {
      throw StateError(
        'GET /api/settings returned no settings object (HTTP 200)',
      );
    }
    return models.AppSettings.fromJson(settingsJson);
  }

  @override
  Future<void> updateSettings(models.AppSettings settings) async {
    // [Wave 6B settings sync] forward through the dedicated overload so
    // origin-filtering callers can stamp a command id without changing
    // the public interface of NightshadeBackend.
    return updateSettingsWithCommandId(settings, commandId: null);
  }

  /// [Wave 6B settings sync] Variant of [updateSettings] that stamps the
  /// outgoing POST with an `X-Nightshade-Command-Id` header so the
  /// `settings.changed` events that come back over the WS carry the
  /// `correlatingCommandId` and the calling client can ignore its own
  /// echo. Callers track the same id locally; un-paired clients can
  /// continue to call [updateSettings] and accept the echo as a no-op
  /// (the diff against in-memory state will already be empty).
  Future<void> updateSettingsWithCommandId(
    models.AppSettings settings, {
    required String? commandId,
  }) async {
    final extraHeaders = commandId == null
        ? null
        : <String, String>{'X-Nightshade-Command-Id': commandId};
    await _post('settings', {'settings': settings.toJson()}, extraHeaders);
  }

  @override
  Future<models.ObserverLocation?> getLocation() async {
    final json = await _get('settings/location');
    if (json['location'] == null) return null;
    return models.ObserverLocation.fromJson(
      json['location'] as Map<String, dynamic>,
    );
  }

  @override
  Future<void> setLocation(models.ObserverLocation? location) async {
    await _post('settings/location', {'location': location?.toJson()});
  }

  // =========================================================================
  // Image Processing
  // =========================================================================

  @override
  Future<List<StarCrop>> getStarCropsFromLastImage(
    String deviceId, {
    int maxCrops = 5,
  }) async {
    final response = await _get('imaging/star-crops', {
      'deviceId': deviceId,
      'maxCrops': maxCrops,
    });
    final crops = response['crops'] as List<dynamic>;
    return crops
        .map((crop) => StarCrop.fromJson(crop as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> calibrateImageFile({
    required String lightPath,
    String? darkPath,
    String? flatPath,
    String? biasPath,
    required String outputPath,
  }) async {
    await _post('imaging/calibrate-file', {
      'lightPath': lightPath,
      if (darkPath != null) 'darkPath': darkPath,
      if (flatPath != null) 'flatPath': flatPath,
      if (biasPath != null) 'biasPath': biasPath,
      'outputPath': outputPath,
    });
  }

  // =========================================================================
  // Polar Alignment
  // =========================================================================

  @override
  Stream<Map<String, dynamic>> get polarAlignmentEvents =>
      _polarAlignController.stream;

  @override
  Future<void> startPolarAlignment({
    required double exposureTime,
    required double stepSize,
    required int binning,
    required bool isNorth,
    required bool manualRotation,
    required bool rotateEast,
    int? gain,
    int? offset,
    double? solveTimeout,
    bool? startFromCurrent,
    double? autoCompleteThreshold,
  }) async {
    await _post('polar-alignment/start', {
      'exposure_time': exposureTime,
      'step_size': stepSize,
      'binning': binning,
      'is_north': isNorth,
      'manual_rotation': manualRotation,
      'rotate_east': rotateEast,
      if (gain != null) 'gain': gain,
      if (offset != null) 'offset': offset,
      if (solveTimeout != null) 'solve_timeout': solveTimeout,
      if (startFromCurrent != null) 'start_from_current': startFromCurrent,
      if (autoCompleteThreshold != null)
        'auto_complete_threshold': autoCompleteThreshold,
    });
  }

  @override
  Future<void> stopPolarAlignment() async {
    await _post('polar-alignment/stop', {});
  }

  @override
  Future<void> startAllSkyPolarAlignment({
    required double exposureTime,
    required double solveTimeout,
    required int binning,
    required bool isNorth,
    required double acceptanceThresholdArcsec,
    required double iterationCadenceSecs,
    int? gain,
    int? offset,
  }) async {
    await _post('polar-alignment/all-sky/start', {
      'exposure_time': exposureTime,
      'solve_timeout': solveTimeout,
      'binning': binning,
      'is_north': isNorth,
      'acceptance_threshold_arcsec': acceptanceThresholdArcsec,
      'iteration_cadence_secs': iterationCadenceSecs,
      if (gain != null) 'gain': gain,
      if (offset != null) 'offset': offset,
    });
  }

  // =========================================================================
  // Image Download (for Mobile)
  // =========================================================================

  @override
  Future<List<CapturedImage>> getSessionImages(int sessionId) async {
    final imagesList = await getSessionImageRows(sessionId);

    return imagesList.map((img) {
      return CapturedImage(
        id: img['image_id'].toString(),
        filePath: img['file_path'] as String,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          (img['captured_at'] as int) * 1000,
        ),
        settings: ExposureSettings(
          exposureTime: (img['exposure_duration'] as num).toDouble(),
          gain: img['gain'] as int? ?? 0,
          offset: img['offset'] as int? ?? 0,
          binningX: img['bin_x'] as int? ?? 1,
          binningY: img['bin_y'] as int? ?? 1,
          filter: img['filter'] as String?,
          frameType: _parseFrameType(img['frame_type'] as String),
        ),
        stats: img['hfr'] != null
            ? ImageStats(
                hfr: (img['hfr'] as num?)?.toDouble(),
                starCount: img['star_count'] as int?,
              )
            : null,
        targetName: null, // Not included in basic metadata
        format: _parseImageFormat(img['file_format'] as String),
      );
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getSessionImageRows(int sessionId) async {
    final response = await _get('sessions/$sessionId/images');
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getAllImageRows() async {
    final response = await _get('images');
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getStandaloneImageRows() async {
    final response = await _get('images/standalone');
    final images = response['images'] as List? ?? [];
    return images.cast<Map<String, dynamic>>();
  }

  @override
  Future<Uint8List> getImageThumbnail(int imageId) async {
    final uri = _apiUri('images/$imageId/thumbnail');

    final request = await _httpClient.getUrl(uri);
    final response = await request.close();

    if (response.statusCode != 200) {
      throw IoException(
        message: 'HTTP ${response.statusCode}: Failed to get thumbnail',
        userMessage: 'Failed to download the image thumbnail',
      );
    }

    final bytes = await consolidateHttpClientResponseBytes(response);
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> downloadImage(
    int imageId,
    String localPath, {
    void Function(double)? onProgress,
  }) async {
    final uri = _apiUri('images/$imageId/download');

    // P0-5 — opportunistic resume. If a partial file already exists at
    // [localPath] from a prior aborted attempt, send `Range: bytes=N-`
    // to ask the server to continue. A server that supports Range
    // (post-P0-5 Nightshade) replies with 206 + `content-range`; an
    // older/naive server ignores the header and returns 200 with the
    // entire body — we detect that and start over from byte 0.
    final file = File(localPath);
    await file.parent.create(recursive: true);

    int resumeOffset = 0;
    if (await file.exists()) {
      try {
        resumeOffset = await file.length();
      } on FileSystemException catch (e) {
        // Existing file is unreadable — surface it instead of pretending
        // to start from zero. CLAUDE.md: errors are a feature.
        throw IoException(
          message: 'Failed to stat partial download at $localPath: $e',
          userMessage: 'Could not read the partially downloaded file',
        );
      }
    }

    final request = await _httpClient.getUrl(uri);
    if (resumeOffset > 0) {
      request.headers.set('range', 'bytes=$resumeOffset-');
    }
    final response = await request.close();

    // Server can answer:
    //   * 206 Partial Content — honoured the Range, append to the file.
    //   * 200 OK + content-range absent — full body, truncate the file
    //     and write from scratch.
    //   * 416 — our resume offset is past EOF on the server (e.g. the
    //     file was replaced). Truncate and retry without Range.
    //   * anything else — propagate.
    final statusCode = response.statusCode;
    final contentRange = response.headers.value('content-range');
    final bool isPartial = statusCode == 206 && contentRange != null;

    if (statusCode == 416 && resumeOffset > 0) {
      // The server says our partial is invalid (file changed / shrunk).
      // Drop the partial and retry from scratch with a fresh request.
      developer.log(
        '[NetworkBackend] Server returned 416 for resume offset '
        '$resumeOffset; discarding partial and retrying from byte 0',
        name: 'NetworkBackend',
        level: 900,
      );
      await response.drain<void>();
      await file.delete();
      // Recursive single-shot retry (resumeOffset will be 0 next call
      // because the file was deleted). This is bounded — a 416 on the
      // retry would mean the server has nothing at all to serve, which
      // we let propagate.
      return downloadImage(imageId, localPath, onProgress: onProgress);
    }

    if (statusCode != 200 && statusCode != 206) {
      await response.drain<void>();
      throw IoException(
        message: 'HTTP $statusCode: Failed to download image',
        userMessage: 'Failed to download the image',
      );
    }

    // Get total length for progress tracking. For 206 the response
    // content-length is the *slice* length, but we want total bytes
    // for the progress fraction; pull the total from `content-range:
    // bytes START-END/TOTAL`.
    int totalLength = response.contentLength;
    if (isPartial) {
      final slash = contentRange.lastIndexOf('/');
      if (slash > 0 && slash < contentRange.length - 1) {
        final totalStr = contentRange.substring(slash + 1);
        if (totalStr != '*') {
          totalLength = int.tryParse(totalStr) ?? totalLength;
        }
      }
    }

    // Open the sink in the correct mode: append for 206, write
    // (truncate) for 200. If we asked for a range but got 200, the
    // server doesn't support Range — discard whatever was already on
    // disk and start over.
    final IOSink sink;
    int bytesReceived;
    if (isPartial) {
      sink = file.openWrite(mode: FileMode.append);
      bytesReceived = resumeOffset;
    } else {
      sink = file.openWrite();
      bytesReceived = 0;
    }

    try {
      await for (final chunk in response) {
        sink.add(chunk);
        bytesReceived += chunk.length;

        if (onProgress != null && totalLength > 0) {
          onProgress(bytesReceived / totalLength);
        }
      }
    } finally {
      await sink.close();
    }

    developer.log(
      '[NetworkBackend] Downloaded image $imageId to $localPath '
      '($bytesReceived bytes${isPartial ? ', resumed from $resumeOffset' : ''})',
      name: 'NetworkBackend',
      level: 800,
    );
  }

  FrameType _parseFrameType(String str) {
    switch (str.toLowerCase()) {
      case 'light':
        return FrameType.light;
      case 'dark':
        return FrameType.dark;
      case 'flat':
        return FrameType.flat;
      case 'bias':
        return FrameType.bias;
      case 'darkflat':
        return FrameType.darkFlat;
      default:
        return FrameType.light;
    }
  }

  ImageFileFormat _parseImageFormat(String str) {
    switch (str.toLowerCase()) {
      case 'fits':
        return ImageFileFormat.fits;
      case 'xisf':
        return ImageFileFormat.xisf;
      case 'tiff':
        return ImageFileFormat.tiff;
      case 'png':
        return ImageFileFormat.png;
      case 'jpeg':
      case 'jpg':
        return ImageFileFormat.jpeg;
      default:
        return ImageFileFormat.fits;
    }
  }

  // =========================================================================
  // Device Health Monitoring
  // =========================================================================

  @override
  Future<void> startDeviceHeartbeat({
    required DeviceType deviceType,
    required String deviceId,
    required int intervalMs,
  }) async {
    await _post('device/heartbeat/start', {
      'device_type': deviceType.name,
      'device_id': deviceId,
      'interval_ms': intervalMs,
    });
  }

  @override
  Future<void> stopDeviceHeartbeat(String deviceId) async {
    await _post('device/heartbeat/stop', {'device_id': deviceId});
  }

  @override
  Future<(int, bool)> getDeviceHealth(String deviceId) async {
    final response = await _get('device/health/$deviceId');
    final lastComm = response['last_successful_comm'] as int;
    final isHealthy = response['is_healthy'] as bool;
    return (lastComm, isHealthy);
  }

  // =========================================================================
  // Raw Image Data
  // =========================================================================

  @override
  Future<List<int>> getLastRawImageData(String deviceId) async {
    return _retryableRequest(() async {
      final uri = _apiUri('imaging/raw-data', {'deviceId': deviceId});

      final request = await _httpClient.getUrl(uri);

      // Add authentication headers
      final headers = _addAuthHeaders({}, endpoint: 'imaging/raw-data');
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close();

      // Check for transient status codes
      if (_isTransientStatusCode(response.statusCode)) {
        throw Exception(
          'HTTP ${response.statusCode}: Transient failure for GET imaging/raw-data',
        );
      }

      if (response.statusCode != 200) {
        throw IoException(
          message:
              'HTTP ${response.statusCode}: Failed to GET imaging/raw-data',
          userMessage: 'Failed to retrieve the raw image data',
        );
      }

      // Read binary data
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes;
    });
  }

  @override
  Future<void> saveFitsFromLastCapture({
    required String deviceId,
    required String filePath,
    required FitsWriteHeader headerData,
  }) async {
    // Use the optimized endpoint that saves from server-side stored image
    // No raw pixel data needs to be transferred
    return _retryableRequest(() async {
      final uri = _apiUri('imaging/save-fits-from-capture');

      final request = await _httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;

      // Add authentication headers
      final headers = _addAuthHeaders(
        {},
        endpoint: 'imaging/save-fits-from-capture',
      );
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });

      // Build request body - file path, device ID, and header (no pixel data)
      // Use pure Dart type's toJson() for header serialization
      final body = {
        'deviceId': deviceId,
        'filePath': filePath,
        'headerData': headerData.toJson(),
      };

      request.write(jsonEncode(body));

      final response = await request.close();

      // Check for transient status codes
      if (_isTransientStatusCode(response.statusCode)) {
        throw Exception(
          'HTTP ${response.statusCode}: Transient failure for POST imaging/save-fits-from-capture',
        );
      }

      if (response.statusCode != 200) {
        throw IoException(
          message:
              'HTTP ${response.statusCode}: Failed to POST imaging/save-fits-from-capture',
          userMessage: 'Failed to save the FITS file on the server',
        );
      }

      // Consume response body to complete the request
      await response.transform(utf8.decoder).join();
    });
  }

  @override
  Future<void> clearDeviceImage(String deviceId) async {
    await _delete('imaging/device-image/${Uri.encodeComponent(deviceId)}');
  }
}
