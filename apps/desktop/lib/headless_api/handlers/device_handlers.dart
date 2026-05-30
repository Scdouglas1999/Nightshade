import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge_error;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../command_correlator.dart';
import '../display_buffer_jpeg.dart';
import '../job_manager.dart';
import '../response_helpers.dart';
import '../utils/device_type_parser.dart';
import '../validation.dart';

/// MIME-style `Accept` header value that opts the caller into the
/// pre-P1-2 synchronous response shape for autofocus / plate-solve /
/// center-on-target / polar-alignment. New clients should not send this;
/// the audit's spec keeps the legacy path so pinned mobile builds stay
/// functional during the rollout.
const String legacyBlockingAcceptType =
    'application/x.nightshade.legacy-blocking';

/// True when the request's `Accept` header explicitly opts into the
/// legacy synchronous response shape.
bool requestPrefersLegacyBlocking(Request request) {
  final accept = request.headers['accept'] ?? '';
  if (accept.isEmpty) return false;
  // Accept may be a comma-separated list; do a case-insensitive contains
  // check against the documented opt-in type.
  return accept.toLowerCase().contains(legacyBlockingAcceptType);
}

/// Handlers for device control endpoints (camera, mount, focuser, filter wheel, rotator)
class DeviceHandlers {
  final ProviderContainer container;

  /// P1-4: optional command correlator. When set, every action POST
  /// generates a UUID v4 commandId and includes it in the response. The
  /// later NightshadeEvent that completes the command picks the id back
  /// up via `correlatingCommandId`. Null in unit tests that don't care
  /// about correlation (those tests still validate the legacy response
  /// shape).
  final CommandCorrelator? commandCorrelator;

  /// P1-2 / P1-3: optional job manager. When set, long-running endpoints
  /// (currently autofocus) return `{jobId, status: queued, commandId}`
  /// immediately and surface progress via the WS event stream. When null
  /// (unit tests / legacy callers), the handler falls back to the
  /// blocking response shape.
  final JobManager? jobManager;

  DeviceHandlers(
    this.container, {
    this.commandCorrelator,
    this.jobManager,
  });

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'DeviceHandlers');

  void _logWarning(String message) =>
      _logger.warning(message, source: 'DeviceHandlers');

  // ===========================================================================
  // Connection lifecycle
  //
  // Audit DEV-P0-2: the previous headless implementation called
  // `backend.connectDevice` / `backend.disconnectDevice` directly. That
  // shipped a "connected" response to remote clients while skipping the
  // full per-device-type connect flow that the desktop UI runs through
  // `DeviceService`:
  //
  //   * cameras: cool-on-connect, target-temp seeding, recommended-gain
  //     auto-apply, temperature polling, heartbeat monitoring
  //   * mounts: initial status snapshot (RA/Dec/Alt/Az + park/track flags),
  //     heartbeat monitoring
  //   * focusers: status snapshot (position, max position, temperature)
  //   * filter wheels: position settling poll, filter-name sync to driver
  //     from active profile / session
  //   * guiders: PHD2 handshake when applicable
  //
  // It also left the per-device-type StateNotifier (`cameraStateProvider`,
  // `mountStateProvider`, ...) untouched, so any local UI listening to the
  // Riverpod state still believed nothing was connected â€” exactly the same
  // failure mode we just fixed for sequencer start (audit C3).
  //
  // The fix routes every connect through `DeviceService.connect<Type>` so
  // remote clients are first-class consumers of the same code path the
  // desktop UI uses.
  // ===========================================================================

  /// POST /api/devices/connect
  ///
  /// Body: `{deviceId, deviceType}`. The `deviceType` value must match one
  /// of [DeviceType]'s names (case-insensitive). Returns
  /// `{status: "connected", deviceId, deviceType}` on success and surfaces
  /// validation/state errors as 4xx with a structured body so a remote
  /// dashboard can render the same "device not found" / "no profile active"
  /// hints the desktop dialog does.
  Future<Response> handleConnectDevice(Request request) async {
    _logInfo('[API] POST /api/devices/connect');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final deviceTypeStr = requireString(payload, 'deviceType');
    final deviceType = parseDeviceType(deviceTypeStr);
    if (deviceType == null) {
      throw BadRequestError(
        field: 'deviceType',
        expected: validDeviceTypeList(),
        message: 'Unknown device type: $deviceTypeStr',
      );
    }

    final service = container.read(deviceServiceProvider);
    try {
      await _dispatchConnect(service, deviceType, deviceId);
    } on _DeviceNotFoundFailure catch (e) {
      throw HandlerFailure(
        code: 'device_not_found',
        message: e.message,
        statusCode: 404,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
      );
    } catch (e, stackTrace) {
      // The connect threw after passing discovery â€” most likely the
      // underlying driver refused (cable unplugged, ASCOM driver not
      // installed, INDI server unreachable, etc.). Surface a 502 with the
      // service's own message so the remote operator sees the same
      // diagnostic the desktop UI would have surfaced via a snackbar.
      _logWarning(
        '[API] POST /api/devices/connect failed for ${deviceType.name} '
        '$deviceId: $e',
      );
      throw HandlerFailure(
        code: 'device_connect_failed',
        message: _sanitizeConnectErrorMessage(e),
        statusCode: 502,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
        cause: e,
        stackTrace: stackTrace,
      );
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.equipment,
      action: HostMutationAction.connected,
      entityId: deviceId,
      extra: {
        'deviceType': deviceType.name,
        'deviceId': deviceId,
      },
    );

    return jsonOk({
      'status': 'connected',
      'deviceId': deviceId,
      'deviceType': deviceType.name,
    });
  }

  /// POST /api/devices/disconnect
  ///
  /// Body: `{deviceId, deviceType}`. The disconnect path always operates on
  /// the device currently held in the matching StateNotifier; we still
  /// require `deviceId` so the caller cannot silently disconnect a
  /// different device than they think they are. If the supplied `deviceId`
  /// does not match the currently-connected one, we return 409 rather than
  /// guess.
  Future<Response> handleDisconnectDevice(Request request) async {
    _logInfo('[API] POST /api/devices/disconnect');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final deviceTypeStr = requireString(payload, 'deviceType');
    final deviceType = parseDeviceType(deviceTypeStr);
    if (deviceType == null) {
      throw BadRequestError(
        field: 'deviceType',
        expected: validDeviceTypeList(),
        message: 'Unknown device type: $deviceTypeStr',
      );
    }

    final connectedId = _connectedDeviceIdFor(deviceType);
    if (connectedId == null || connectedId.isEmpty) {
      throw HandlerFailure(
        code: 'device_not_connected',
        message: 'No ${deviceType.name} is currently connected',
        statusCode: 409,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
      );
    }
    if (connectedId != deviceId) {
      throw HandlerFailure(
        code: 'device_id_mismatch',
        message:
            'Requested deviceId does not match the currently-connected ${deviceType.name}',
        statusCode: 409,
        details: {
          'requestedDeviceId': deviceId,
          'connectedDeviceId': connectedId,
          'deviceType': deviceType.name,
        },
      );
    }

    final service = container.read(deviceServiceProvider);
    try {
      await _dispatchDisconnect(service, deviceType);
    } catch (e, stackTrace) {
      _logWarning(
        '[API] POST /api/devices/disconnect failed for ${deviceType.name} '
        '$deviceId: $e',
      );
      throw HandlerFailure(
        code: 'device_disconnect_failed',
        message: _sanitizeConnectErrorMessage(e),
        statusCode: 502,
        details: {
          'deviceId': deviceId,
          'deviceType': deviceType.name,
        },
        cause: e,
        stackTrace: stackTrace,
      );
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.equipment,
      action: HostMutationAction.disconnected,
      entityId: deviceId,
      extra: {
        'deviceType': deviceType.name,
        'deviceId': deviceId,
      },
    );

    return jsonOk({
      'status': 'disconnected',
      'deviceId': deviceId,
      'deviceType': deviceType.name,
    });
  }

  /// Dispatches connect by [DeviceType] to the matching `DeviceService`
  /// method. The DeviceService methods do all the bookkeeping (state
  /// notifier transitions, cool-on-connect, recommended-gain auto-apply,
  /// heartbeat start, filter-name sync, ...).
  ///
  /// DEV-P2-1 brought switches in line with every other device type:
  /// `DeviceService.connectSwitch` / `disconnectSwitch` drive the
  /// `switchStateProvider` notifier and own the auto-reconnect loop, so
  /// the dispatcher routes switches through the service like everything
  /// else.
  Future<void> _dispatchConnect(
    DeviceService service,
    DeviceType type,
    String deviceId,
  ) async {
    try {
      switch (type) {
        case DeviceType.camera:
          await service.connectCamera(deviceId);
          break;
        case DeviceType.mount:
          await service.connectMount(deviceId);
          break;
        case DeviceType.focuser:
          await service.connectFocuser(deviceId);
          break;
        case DeviceType.filterWheel:
          await service.connectFilterWheel(deviceId);
          break;
        case DeviceType.guider:
          await service.connectGuider(deviceId);
          break;
        case DeviceType.rotator:
          await service.connectRotator(deviceId);
          break;
        case DeviceType.dome:
          await service.connectDome(deviceId);
          break;
        case DeviceType.weather:
          await service.connectWeather(deviceId);
          break;
        case DeviceType.safetyMonitor:
          await service.connectSafetyMonitor(deviceId);
          break;
        case DeviceType.coverCalibrator:
          await service.connectCoverCalibrator(deviceId);
          break;
        case DeviceType.switch_:
          await service.connectSwitch(deviceId);
          break;
      }
    } on Exception catch (e) {
      // DeviceService throws `Exception('<Kind> not found: <id>')` when
      // discovery doesn't surface the requested device. Translate that
      // into a structured 404 so remote clients can distinguish
      // "you asked for a device that does not exist" from
      // "the driver failed to open the device".
      // Internal use only: the curated "<Kind> not found: <id>" service
      // message is matched here and re-thrown as a structured 404 below —
      // the raw exception object itself is never serialized.
      final message = '$e';
      if (message.contains('not found:')) {
        throw _DeviceNotFoundFailure(message.replaceFirst('Exception: ', ''));
      }
      rethrow;
    }
  }

  Future<void> _dispatchDisconnect(
    DeviceService service,
    DeviceType type,
  ) async {
    switch (type) {
      case DeviceType.camera:
        await service.disconnectCamera();
        break;
      case DeviceType.mount:
        await service.disconnectMount();
        break;
      case DeviceType.focuser:
        await service.disconnectFocuser();
        break;
      case DeviceType.filterWheel:
        await service.disconnectFilterWheel();
        break;
      case DeviceType.guider:
        await service.disconnectGuider();
        break;
      case DeviceType.rotator:
        await service.disconnectRotator();
        break;
      case DeviceType.dome:
        await service.disconnectDome();
        break;
      case DeviceType.weather:
        await service.disconnectWeather();
        break;
      case DeviceType.safetyMonitor:
        await service.disconnectSafetyMonitor();
        break;
      case DeviceType.coverCalibrator:
        await service.disconnectCoverCalibrator();
        break;
      case DeviceType.switch_:
        await service.disconnectSwitch();
        break;
    }
  }

  /// Reads the deviceId currently held by the matching equipment
  /// StateNotifier. Used by the disconnect endpoint to verify that the
  /// caller is asking to disconnect the device that is actually connected.
  String? _connectedDeviceIdFor(DeviceType type) {
    switch (type) {
      case DeviceType.camera:
        return container.read(cameraStateProvider).deviceId;
      case DeviceType.mount:
        return container.read(mountStateProvider).deviceId;
      case DeviceType.focuser:
        return container.read(focuserStateProvider).deviceId;
      case DeviceType.filterWheel:
        return container.read(filterWheelStateProvider).deviceId;
      case DeviceType.guider:
        return container.read(guiderStateProvider).deviceId;
      case DeviceType.rotator:
        return container.read(rotatorStateProvider).deviceId;
      case DeviceType.dome:
        return container.read(domeStateProvider).deviceId;
      case DeviceType.weather:
        return container.read(weatherStateProvider).deviceId;
      case DeviceType.safetyMonitor:
        return container.read(safetyMonitorStateProvider).deviceId;
      case DeviceType.coverCalibrator:
        return container.read(coverCalibratorStateProvider).deviceId;
      case DeviceType.switch_:
        return container.read(switchStateProvider).deviceId;
    }
  }

  /// Strips the leading `Exception: ` Dart prepends so the wire message
  /// reads cleanly to a remote operator. Internal type names and stacks
  /// stay in the structured log via [HandlerFailure.cause].
  String _sanitizeConnectErrorMessage(Object error) {
    final raw = error.toString();
    if (raw.startsWith('Exception: ')) {
      return raw.substring('Exception: '.length);
    }
    return raw;
  }

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
  /// Poll this endpoint at 2â€“5 Hz for a simple remote viewer. For push delivery,
  /// clients may also open `GET /api/run-watch/frame-thumbnail` (last capture) or
  /// subscribe to imaging SSE events on `/api/run-watch/events`.
  ///
  /// Query params:
  ///   deviceId â€” required connected camera id
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
        'hint': 'Use GET /api/run-watch/frame-thumbnail for the last captured frame, '
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

  /// GET /api/camera/cooling â€” dedicated cooling-state snapshot.
  ///
  /// Why a focused endpoint vs. polling /api/equipment/camera/status: the
  /// cooling panel only needs four fields and we don't want to round-trip the
  /// full sensor/binning/gain payload at the cooling poll cadence. Source of
  /// truth is the same CameraStatus model â€” we just project the cooling
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

  /// GET /api/camera/readout-modes â€” list available readout modes.
  ///
  /// Why a focused endpoint vs. /api/equipment/camera/capabilities: the
  /// readout-mode dropdown only needs the string list, not the full
  /// capabilities payload (bayer pattern, sensor geometry, supported binning,
  /// etc.). Source of truth remains CameraCapabilities â€” we project the
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

  /// GET /api/camera/recommended-settings â€” manufacturer-recommended
  /// gain/offset values, when the vendor SDK exposes them.
  ///
  /// Mirrors the FFI shape: the JSON body is the exact projection of
  /// [CameraRecommendedSettings] (unityGain, hcgGain, defaultOffset, notes).
  /// Older remote hosts won't expose this route â€” the network backend's
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

  Future<Response> handleMountSlew(Request request) async {
    _logInfo('[API] POST /api/mount/slew');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.slew',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountSlewToCoordinates(deviceId, ra, dec);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'slewing',
    });
  }

  Future<Response> handleMountSync(Request request) async {
    _logInfo('[API] POST /api/mount/sync');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');

    final backend = container.read(deviceBackendProvider);
    await backend.mountSync(deviceId, ra, dec);

    return jsonOk({'status': 'synced'});
  }

  Future<Response> handleMountPark(Request request) async {
    _logInfo('[API] POST /api/mount/park');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.park',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountPark(deviceId);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'parking',
    });
  }

  Future<Response> handleMountUnpark(Request request) async {
    _logInfo('[API] POST /api/mount/unpark');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.unpark',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountUnpark(deviceId);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'unparked',
    });
  }

  Future<Response> handleMountSetTracking(Request request) async {
    _logInfo('[API] POST /api/mount/tracking');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final enabled = requireBool(payload, 'enabled');

    final backend = container.read(deviceBackendProvider);
    await backend.mountSetTracking(deviceId, enabled);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountPulseGuide(Request request) async {
    _logInfo('[API] POST /api/mount/pulse-guide');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final direction = requireString(payload, 'direction');
    final durationMs = requireInt(payload, 'durationMs');

    final backend = container.read(deviceBackendProvider);
    await backend.mountPulseGuide(
      deviceId: deviceId,
      direction: direction,
      durationMs: durationMs,
    );

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountAbort(Request request) async {
    _logInfo('[API] POST /api/mount/abort');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.mountAbort(deviceId);

    return jsonOk({'status': 'aborted'});
  }

  Future<Response> handleMountGetStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(deviceBackendProvider);
    final status = await backend.mountGetStatus(deviceId);

    return jsonOk(status);
  }

  Future<Response> handleMountSetTrackingRate(Request request) async {
    _logInfo('[API] POST /api/mount/set-tracking-rate');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final rate = requireInt(payload, 'rate');

    final backend = container.read(deviceBackendProvider);
    await backend.mountSetTrackingRate(deviceId, rate);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountMoveAxis(Request request) async {
    _logInfo('[API] POST /api/mount/move-axis');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final axis = requireInt(payload, 'axis');
    final rate = requireDouble(payload, 'rate');

    final backend = container.read(deviceBackendProvider);
    await backend.mountMoveAxis(deviceId, axis, rate);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountSlewAltAz(Request request) async {
    _logInfo('[API] POST /api/mount/slew-alt-az');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final altitude = requireDouble(payload, 'altitude');
    final azimuth = requireDouble(payload, 'azimuth');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'mount.slew-alt-az',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.mountSlewAltAz(deviceId, altitude, azimuth);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'slewing',
    });
  }

  Future<Response> handleMountFindHome(Request request) async {
    _logInfo('[API] POST /api/mount/find-home');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.mountFindHome(deviceId);

    return jsonOk({'status': 'finding_home'});
  }

  // ===========================================================================
  // Focuser Control
  // ===========================================================================

  Future<Response> handleFocuserMoveTo(Request request) async {
    _logInfo('[API] POST /api/focuser/move-to');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final position = requireInt(payload, 'position');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.move-to',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.focuserMoveTo(deviceId, position);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'moving',
    });
  }

  Future<Response> handleFocuserMoveRelative(Request request) async {
    _logInfo('[API] POST /api/focuser/move-relative');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final delta = requireInt(payload, 'delta');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.move-relative',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.focuserMoveRelative(deviceId, delta);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'moving',
    });
  }

  Future<Response> handleFocuserHalt(Request request) async {
    _logInfo('[API] POST /api/focuser/halt');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.focuserHalt(deviceId);

    return jsonOk({'status': 'halted'});
  }

  Future<Response> handleAutofocusStart(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/start');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final cameraId = requireString(payload, 'cameraId');
    final exposureTime = requireDouble(payload, 'exposureTime');
    final stepSize = requireInt(payload, 'stepSize');
    final stepsOut = requireInt(payload, 'stepsOut');
    final method = optionalString(payload, 'method') ?? 'VCurve';
    final binning = optionalInt(payload, 'binning') ?? 1;

    // P1-4: register the command so any later event with a matching
    // operation kind picks up `correlatingCommandId`. We still register
    // even in the new job-model path because the event correlator's
    // matching is independent of the job's own jobId â€” they evolve in
    // parallel (the audit's Â§3 lays out the rationale).
    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.autofocus.start',
      deviceId: deviceId,
    );

    // P1-2 / P1-3: when a JobManager is wired up and the client has
    // NOT opted into the legacy synchronous shape, return `{jobId,
    // status: queued, commandId}` immediately and run the autofocus
    // work in the background. Progress + completion arrive via WS
    // events (category=job).
    final mgr = jobManager;
    final preferLegacy = requestPrefersLegacyBlocking(request);
    if (mgr != null && !preferLegacy) {
      final job = mgr.start(
        operation: 'focuser.autofocus',
        deviceId: deviceId,
        commandId: commandId,
        work: (sink, cancellation) async {
          sink.update(null, 'Starting autofocus');
          final backend = container.read(deviceBackendProvider);
          // The backend call is currently a long synchronous FFI
          // operation â€” see audit Q6 â€” so cooperative cancellation has
          // to wait for it to return. We race the work against the
          // cancellation token so the JobManager can flag the job as
          // cancelled even though the FFI side keeps running. A future
          // wave will plumb cancellation into Rust.
          final workFuture = backend.autofocusStart(
            deviceId: deviceId,
            cameraId: cameraId,
            exposureTime: exposureTime,
            stepSize: stepSize,
            stepsOut: stepsOut,
            method: method,
            binning: binning,
          );
          final result = await Future.any<dynamic>([
            workFuture,
            cancellation.whenCancelled.then((_) => _CancelledMarker.instance),
          ]);
          if (result is _CancelledMarker) {
            throw const JobCancelledException(
              'Autofocus cancellation requested by client',
            );
          }
          final typed = result as AutofocusResult;
          return typed.toJson();
        },
      );
      return jsonOk({
        'jobId': job.jobId,
        'status': job.state.wireName,
        if (commandId != null) 'commandId': commandId,
        'operation': job.operation,
      });
    }

    // Legacy fallback (no JobManager wired or client opted into
    // synchronous shape). Existing behaviour preserved.
    final backend = container.read(deviceBackendProvider);
    final result = await backend.autofocusStart(
      deviceId: deviceId,
      cameraId: cameraId,
      exposureTime: exposureTime,
      stepSize: stepSize,
      stepsOut: stepsOut,
      method: method,
      binning: binning,
    );

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      ...result.toJson(),
    });
  }

  Future<Response> handleAutofocusCancel(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/cancel');
    final commandId = commandCorrelator?.beginCommand(
      operation: 'focuser.autofocus.cancel',
    );
    final backend = container.read(deviceBackendProvider);
    await backend.autofocusCancel();

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'cancelled',
    });
  }

  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================

  Future<Response> handleFilterWheelSetPosition(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/position');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final position = requireInt(payload, 'position');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'filter-wheel.set-position',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.filterWheelSetPosition(deviceId, position);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'ok',
    });
  }

  Future<Response> handleFilterWheelGetNames(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(deviceBackendProvider);
    final names = await backend.filterWheelGetNames(deviceId);

    return jsonOk({'names': names});
  }

  Future<Response> handleFilterWheelSetNames(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/names');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final names = requireList<String>(payload, 'names');

    final backend = container.read(deviceBackendProvider);
    await backend.filterWheelSetNames(deviceId, names);

    return jsonOk({'status': 'ok'});
  }

  /// P2-7 â€” remote GET for the current filter-wheel position/state.
  ///
  /// Reads from `filterWheelStateProvider` which the device-service
  /// keeps in sync with the underlying driver via the position-settle
  /// poll. Why this provider (not a backend call): the StateNotifier
  /// already aggregates the position, the slot-name table, and the
  /// `isMoving` flag in one place. Going directly to the backend would
  /// give us the integer but miss the resolved filter name and the
  /// move-in-progress flag, which is exactly what mobile callers need.
  ///
  /// The response shape matches the task spec:
  ///   { "position": int|null, "name": string|null, "isMoving": bool }
  /// Position is null when the wheel is disconnected or has not yet
  /// reported a starting slot. Name is null when no slot label is
  /// available for the current position (driver returned a short array
  /// or the wheel is disconnected).
  Future<Response> handleFilterWheelGetPosition(Request request) async {
    _logInfo('[API] GET /api/filter-wheel/position');
    final state = container.read(filterWheelStateProvider);
    return jsonOk({
      'position': state.currentPosition,
      'name': state.currentFilterName,
      'isMoving': state.isMoving,
    });
  }

  Future<Response> handleFilterWheelSetByName(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/set-by-name');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final name = requireString(payload, 'name');

    final backend = container.read(deviceBackendProvider);
    await backend.filterWheelSetByName(deviceId, name);

    return jsonOk({'status': 'ok'});
  }

  // ===========================================================================
  // Rotator Control
  // ===========================================================================

  Future<Response> handleRotatorMoveTo(Request request) async {
    _logInfo('[API] POST /api/rotator/move-to');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final angle = requireDouble(payload, 'angle');

    final commandId = commandCorrelator?.beginCommand(
      operation: 'rotator.move-to',
      deviceId: deviceId,
    );

    final backend = container.read(deviceBackendProvider);
    await backend.rotatorMoveTo(deviceId, angle);

    return jsonOk({
      if (commandId != null) 'commandId': commandId,
      'status': 'moving',
    });
  }

  Future<Response> handleRotatorMoveRelative(Request request) async {
    _logInfo('[API] POST /api/rotator/move-relative');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final delta = requireDouble(payload, 'delta');

    final backend = container.read(deviceBackendProvider);
    await backend.rotatorMoveRelative(deviceId, delta);

    return jsonOk({'status': 'moving'});
  }

  Future<Response> handleRotatorGetStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(deviceBackendProvider);
    final angle = await backend.rotatorGetAngle(deviceId);

    return jsonOk({'position': angle});
  }

  Future<Response> handleRotatorHalt(Request request) async {
    _logInfo('[API] POST /api/rotator/halt');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(deviceBackendProvider);
    await backend.rotatorHalt(deviceId);

    return jsonOk({'status': 'halted'});
  }

  /// POST /api/rotator/sync â€” sync rotator reported sky angle to the supplied
  /// position angle (degrees) without moving the hardware. Used by the "Sync
  /// to image PA" workflow after a plate solve.
  ///
  /// Why this isn't a synonym for /api/rotator/move-to: ASCOM IRotatorV3
  /// separates Sync (mechanical-vs-sky offset adjustment) from MoveAbsolute
  /// (motion). Conflating them would slew the rotator every time the operator
  /// hit "Sync to image", which is the opposite of the intended effect.
  ///
  /// Body: `{deviceId, positionAngle}` â€” `positionAngle` is the canonical
  /// field; `angle` is accepted as an alias for compatibility with older
  /// clients that mirrored the move-to body shape.
  Future<Response> handleRotatorSync(Request request) async {
    _logInfo('[API] POST /api/rotator/sync');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    // Why accept both `positionAngle` and `angle`: the canonical field name
    // is `positionAngle` (matches plate-solve terminology), but the move-to
    // endpoint uses `angle` and earlier dashboard builds reused that key.
    final pa = optionalDouble(payload, 'positionAngle') ??
        optionalDouble(payload, 'angle');
    if (pa == null) {
      throw BadRequestError(
        field: 'positionAngle',
        expected: 'number',
        message: "Body must include 'positionAngle' (degrees)",
      );
    }

    final backend = container.read(deviceBackendProvider);
    await backend.rotatorSyncToPa(deviceId, pa);

    return jsonOk({'status': 'synced'});
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  FrameType _parseFrameType(String type) {
    switch (type.toLowerCase()) {
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
}

/// Internal sentinel raised by `_dispatchConnect` when the requested
/// device id does not match anything `DeviceService.discoverDevices`
/// returned. The connect handler translates this into a structured
/// `device_not_found` HTTP 404 with the original service message.
class _DeviceNotFoundFailure implements Exception {
  final String message;
  _DeviceNotFoundFailure(this.message);
  @override
  String toString() => message;
}

/// Sentinel used to flag the cancellation branch of a `Future.any` race
/// against a long-running backend call. We can't pass `null` because the
/// race's result type is non-nullable; a sentinel keeps the type system
/// happy without requiring a wrapper class on every result type.
class _CancelledMarker {
  const _CancelledMarker._();
  static const _CancelledMarker instance = _CancelledMarker._();
}
