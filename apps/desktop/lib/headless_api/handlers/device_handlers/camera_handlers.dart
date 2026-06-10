part of '../device_handlers.dart';

extension CameraDeviceHandlers on DeviceHandlers {
  // ===========================================================================
  // Camera Control
  // ===========================================================================

  Future<Response> handleCameraExpose(Request request) async {
    _logInfo('[API] POST /api/camera/expose');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final exposureTime = requireDouble(payload, 'exposureTime');
    final frameTypeStr = optionalString(payload, 'frameType') ?? 'light';
    final frameType = _parseFrameType(frameTypeStr);

    // P1-4: register the command BEFORE kicking off the exposure so a
    // FrameAccepted event that arrives during `await
    // backend.cameraStartExposure` (rare but possible on fast cameras) can
    // still be correlated.
    final commandId = commandCorrelator?.beginCommand(
      operation: 'camera.expose',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.cameraStartExposure(
      deviceId: deviceId,
      exposureTime: exposureTime,
      frameType: frameType,
      gain: optionalInt(payload, 'gain'),
      offset: optionalInt(payload, 'offset'),
      binX: optionalInt(payload, 'binX') ?? 1,
      binY: optionalInt(payload, 'binY') ?? 1,
      x: optionalInt(payload, 'x'),
      y: optionalInt(payload, 'y'),
      width: optionalInt(payload, 'width'),
      height: optionalInt(payload, 'height'),
    );

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'exposing',
    });
  }

  Future<Response> handleCameraAbort(Request request) async {
    _logInfo('[API] POST /api/camera/abort');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'camera.abort',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.cameraAbortExposure(deviceId);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'aborted',
    });
  }

  /// GET /api/camera/last-image
  ///
  /// Preferred remote wire format: `?format=jpeg` or
  /// [handleCameraGetLastImageJpeg] (`/api/camera/last-image/jpeg`).
  ///
  /// The default JSON response embeds full RGBA `displayData` and is kept
  /// for backward compatibility only; new remote clients must not rely on it.
  Future<Response> handleCameraGetLastImage(Request request) async {
    final format = request.url.queryParameters['format']?.toLowerCase();
    if (format == 'jpeg' || format == 'jpg') {
      return handleCameraGetLastImageJpeg(request);
    }

    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(deviceBackendProvider);
    final image = await backend.cameraGetLastImage(deviceId);

    if (image == null) {
      return jsonOk({
        'image': null,
        'legacy': true,
        'preferredFormat': 'jpeg',
        'preferredEndpoint': '/api/camera/last-image/jpeg',
      });
    }

    return jsonOk({
      'legacy': true,
      'preferredFormat': 'jpeg',
      'preferredEndpoint': '/api/camera/last-image/jpeg',
      'image': {
        'width': image.width,
        'height': image.height,
        'displayData': image.displayData,
        'histogram': image.histogram,
        'stats': {
          'min': image.stats.min,
          'max': image.stats.max,
          'mean': image.stats.mean,
          'median': image.stats.median,
          'stdDev': image.stats.stdDev,
          'hfr': image.stats.hfr,
          'starCount': image.stats.starCount,
        },
        'exposureTime': image.exposureTime,
        'timestamp': image.timestamp,
        'isColor': image.isColor,
      },
    });
  }

  /// GET /api/camera/last-image/jpeg
  ///
  /// Returns the host-authoritative stretched display buffer as JPEG.
  /// Metadata (stats, histogram, source dimensions) travels in `x-image-meta`.
  Future<Response> handleCameraGetLastImageJpeg(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    if (deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }

    final maxWidth =
        int.tryParse(request.url.queryParameters['maxWidth'] ?? '') ?? 0;
    final quality =
        (int.tryParse(request.url.queryParameters['quality'] ?? '') ?? 85)
            .clamp(1, 100);

    final backend = container.read(deviceBackendProvider);
    final image = await backend.cameraGetLastImage(deviceId);

    if (image == null) {
      return jsonNotFound({
        'error': 'no_image',
        'message': 'No image has been captured yet on this camera.',
      });
    }

    final encoded = encodeCapturedImageDisplayBufferToJpeg(
      image,
      maxWidth: maxWidth,
      quality: quality,
    );
    if (encoded == null) {
      return jsonInternalServerError({
        'error': 'bad_image_buffer',
        'message': 'Display buffer size mismatch.',
      });
    }

    return contentResponse(
      encoded.bytes,
      contentType: 'image/jpeg',
      contentLength: encoded.bytes.length,
      headers: {
        'cache-control': 'no-store, no-cache, must-revalidate',
        'x-image-width': encoded.sourceWidth.toString(),
        'x-image-height': encoded.sourceHeight.toString(),
        'x-image-encoded-width': encoded.encodedWidth.toString(),
        'x-image-encoded-height': encoded.encodedHeight.toString(),
        'x-image-meta': encoded.metaHeaderValue,
        'x-frame-timestamp': image.timestamp,
        'x-frame-exposure-secs': image.exposureTime.toString(),
        if (image.stats.hfr != null) 'x-frame-hfr': image.stats.hfr!.toString(),
        'x-frame-star-count': image.stats.starCount.toString(),
      },
    );
  }

  /// GET /api/camera/live-view/frame
  ///
  /// Returns a JPEG live-view frame from the host-native preview pipeline when
  /// the connected camera driver supports it (gPhoto2 DSLRs, Fujifilm live view).
  ///
  /// Poll this endpoint at 2–5 Hz for a simple remote viewer. For push delivery,
  /// clients may also open `GET /api/run-watch/frame-thumbnail` (last capture) or
  /// subscribe to imaging SSE events on `/api/run-watch/events`.
  ///
  /// Query params:
  ///   deviceId — required connected camera id
  Future<Response> handleCameraLiveViewFrame(Request request) async {
    final deviceId = request.url.queryParameters['deviceId']?.trim() ?? '';
    if (deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }

    final backend = container.read(deviceBackendProvider);
    List<DeviceInfo> connected = [];
    try {
      connected = await backend.getConnectedDevices();
    } catch (e) {
      _logInfo('live-view: getConnectedDevices failed: $e');
    }
    final isCamera = connected.any(
      (d) => d.id == deviceId && d.deviceType == DeviceType.camera,
    );
    if (!isCamera) {
      return jsonNotFound({
        'error': 'camera_not_connected',
        'message': 'Camera $deviceId is not connected.',
        'deviceId': deviceId,
      });
    }

    try {
      final jpeg = await backend.cameraLiveViewFrame(deviceId);
      if (jpeg.isEmpty) {
        return jsonServiceUnavailable({
          'error': 'live_view_unavailable',
          'message': 'Camera returned an empty live-view frame.',
          'deviceId': deviceId,
        });
      }

      return contentResponse(
        jpeg,
        contentType: 'image/jpeg',
        contentLength: jpeg.length,
        headers: {
          'cache-control': 'no-store, no-cache, must-revalidate',
          'x-live-view-source': 'native_preview',
          'x-frame-device-id': deviceId,
        },
      );
    } on bridge_error.NightshadeError catch (e) {
      final message = e.maybeMap(
        operationFailed: (v) => v.field0,
        notSupported: (v) =>
            'Live view is not supported for ${v.deviceId} (${v.operation})',
        orElse: () => 'Live view capture failed',
      );
      _logInfo('live-view unavailable for $deviceId: $message');
      return jsonServiceUnavailable({
        'error': 'live_view_unavailable',
        'message': message,
        'deviceId': deviceId,
        'hint':
            'Use GET /api/run-watch/frame-thumbnail for the last captured frame, '
            'or connect a camera with native preview support (gPhoto2 / Fujifilm).',
      });
    } catch (e) {
      _logInfo('live-view failed for $deviceId: $e');
      return jsonServiceUnavailable({
        'error': 'live_view_unavailable',
        'message': 'Failed to capture live-view frame.',
        'deviceId': deviceId,
      });
    }
  }

  Future<Response> handleCameraSetCooling(Request request) async {
    _logInfo('[API] POST /api/camera/cooling');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final enabled = requireBool(payload, 'enabled');
    final targetTemp = optionalDouble(payload, 'targetTemp');

    final backend = container.read(deviceBackendProvider);
    await backend.cameraSetCooling(
      deviceId: deviceId,
      enabled: enabled,
      targetTemp: targetTemp,
    );

    return jsonOk({'status': 'ok'});
  }

  /// GET /api/camera/cooling — dedicated cooling-state snapshot.
  ///
  /// Why a focused endpoint vs. polling /api/equipment/camera/status: the
  /// cooling panel only needs four fields and we don't want to round-trip the
  /// full sensor/binning/gain payload at the cooling poll cadence. Source of
  /// truth is the same CameraStatus model — we just project the cooling
  /// fields out of it.
  Future<Response> handleCameraGetCooling(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    if (deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }
    final backend = container.read(deviceBackendProvider);
    final status = await backend.getCameraStatus(deviceId);
    return jsonOk({
      'coolerOn': status.coolerOn,
      'targetTemp': status.targetTemp,
      'sensorTemp': status.sensorTemp,
      'coolerPower': status.coolerPower,
      'canCool': status.canCool,
    });
  }

  /// GET /api/camera/readout-modes — list available readout modes.
  ///
  /// Why a focused endpoint vs. /api/equipment/camera/capabilities: the
  /// readout-mode dropdown only needs the string list, not the full
  /// capabilities payload (bayer pattern, sensor geometry, supported binning,
  /// etc.). Source of truth remains CameraCapabilities — we project the
  /// `readoutModes` field out of it.
  Future<Response> handleCameraGetReadoutModes(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    if (deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }
    final backend = container.read(deviceBackendProvider);
    final caps = await backend.getCameraCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk({'readoutModes': caps.readoutModes});
  }

  /// GET /api/camera/recommended-settings — manufacturer-recommended
  /// gain/offset values, when the vendor SDK exposes them.
  ///
  /// Mirrors the FFI shape: the JSON body is the exact projection of
  /// [CameraRecommendedSettings] (unityGain, hcgGain, defaultOffset, notes).
  /// Older remote hosts won't expose this route — the network backend's
  /// fallback handles the resulting 404 by returning an empty recommendation.
  ///
  /// Errors bubble out as the standard `{code, message, ...}` envelope so
  /// network-backend callers can tell "SDK failed" from "route missing".
  Future<Response> handleCameraGetRecommendedSettings(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    if (deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }
    final backend = container.read(deviceBackendProvider);
    final recommended = await backend.cameraGetRecommendedSettings(deviceId);
    return jsonOk({
      'unityGain': recommended.unityGain,
      'hcgGain': recommended.hcgGain,
      'defaultOffset': recommended.defaultOffset,
      'notes': recommended.notes,
    });
  }

  Future<Response> handleCameraSetReadoutMode(Request request) async {
    _logInfo('[API] POST /api/camera/readoutMode');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final modeIndex = requireInt(payload, 'modeIndex');

    final backend = container.read(deviceBackendProvider);
    await backend.cameraSetReadoutMode(deviceId, modeIndex);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleCameraSetGain(Request request) async {
    _logInfo('[API] POST /api/camera/gain');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final gain = requireInt(payload, 'gain');

    final backend = container.read(deviceBackendProvider);
    await backend.cameraSetGain(deviceId, gain);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleCameraSetOffset(Request request) async {
    _logInfo('[API] POST /api/camera/offset');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final offset = requireInt(payload, 'offset');

    final backend = container.read(deviceBackendProvider);
    await backend.cameraSetOffset(deviceId, offset);

    return jsonOk({'status': 'ok'});
  }

  // ===========================================================================
  // Mount Control
  // ===========================================================================
}
