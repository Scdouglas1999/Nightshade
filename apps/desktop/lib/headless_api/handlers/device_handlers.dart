import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for device control endpoints (camera, mount, focuser, filter wheel, rotator)
class DeviceHandlers {
  final ProviderContainer container;
  DeviceHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'DeviceHandlers');

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

    final backend = container.read(backendProvider);
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

    return jsonOk({'status': 'exposing'});
  }

  Future<Response> handleCameraAbort(Request request) async {
    _logInfo('[API] POST /api/camera/abort');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.cameraAbortExposure(deviceId);

    return jsonOk({'status': 'aborted'});
  }

  Future<Response> handleCameraGetLastImage(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(backendProvider);
    final image = await backend.cameraGetLastImage(deviceId);

    if (image == null) {
      return jsonOk({'image': null});
    }

    return jsonOk({
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

  Future<Response> handleCameraSetCooling(Request request) async {
    _logInfo('[API] POST /api/camera/cooling');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final enabled = requireBool(payload, 'enabled');
    final targetTemp = optionalDouble(payload, 'targetTemp');

    final backend = container.read(backendProvider);
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
    final backend = container.read(backendProvider);
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
    final backend = container.read(backendProvider);
    final caps = await backend.getCameraCapabilities(deviceId);
    if (caps == null) {
      return jsonNotFound({
        'error': 'Device not found or capabilities unavailable',
      });
    }
    return jsonOk({'readoutModes': caps.readoutModes});
  }

  Future<Response> handleCameraSetReadoutMode(Request request) async {
    _logInfo('[API] POST /api/camera/readoutMode');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final modeIndex = requireInt(payload, 'modeIndex');

    final backend = container.read(backendProvider);
    await backend.cameraSetReadoutMode(deviceId, modeIndex);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleCameraSetGain(Request request) async {
    _logInfo('[API] POST /api/camera/gain');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final gain = requireInt(payload, 'gain');

    final backend = container.read(backendProvider);
    await backend.cameraSetGain(deviceId, gain);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleCameraSetOffset(Request request) async {
    _logInfo('[API] POST /api/camera/offset');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final offset = requireInt(payload, 'offset');

    final backend = container.read(backendProvider);
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

    final backend = container.read(backendProvider);
    await backend.mountSlewToCoordinates(deviceId, ra, dec);

    return jsonOk({'status': 'slewing'});
  }

  Future<Response> handleMountSync(Request request) async {
    _logInfo('[API] POST /api/mount/sync');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final ra = requireDouble(payload, 'ra');
    final dec = requireDouble(payload, 'dec');

    final backend = container.read(backendProvider);
    await backend.mountSync(deviceId, ra, dec);

    return jsonOk({'status': 'synced'});
  }

  Future<Response> handleMountPark(Request request) async {
    _logInfo('[API] POST /api/mount/park');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.mountPark(deviceId);

    return jsonOk({'status': 'parking'});
  }

  Future<Response> handleMountUnpark(Request request) async {
    _logInfo('[API] POST /api/mount/unpark');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.mountUnpark(deviceId);

    return jsonOk({'status': 'unparked'});
  }

  Future<Response> handleMountSetTracking(Request request) async {
    _logInfo('[API] POST /api/mount/tracking');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final enabled = requireBool(payload, 'enabled');

    final backend = container.read(backendProvider);
    await backend.mountSetTracking(deviceId, enabled);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountPulseGuide(Request request) async {
    _logInfo('[API] POST /api/mount/pulse-guide');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final direction = requireString(payload, 'direction');
    final durationMs = requireInt(payload, 'durationMs');

    final backend = container.read(backendProvider);
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

    final backend = container.read(backendProvider);
    await backend.mountAbort(deviceId);

    return jsonOk({'status': 'aborted'});
  }

  Future<Response> handleMountGetStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(backendProvider);
    final status = await backend.mountGetStatus(deviceId);

    return jsonOk(status);
  }

  Future<Response> handleMountSetTrackingRate(Request request) async {
    _logInfo('[API] POST /api/mount/set-tracking-rate');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final rate = requireInt(payload, 'rate');

    final backend = container.read(backendProvider);
    await backend.mountSetTrackingRate(deviceId, rate);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountMoveAxis(Request request) async {
    _logInfo('[API] POST /api/mount/move-axis');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final axis = requireInt(payload, 'axis');
    final rate = requireDouble(payload, 'rate');

    final backend = container.read(backendProvider);
    await backend.mountMoveAxis(deviceId, axis, rate);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleMountSlewAltAz(Request request) async {
    _logInfo('[API] POST /api/mount/slew-alt-az');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final altitude = requireDouble(payload, 'altitude');
    final azimuth = requireDouble(payload, 'azimuth');

    final backend = container.read(backendProvider);
    await backend.mountSlewAltAz(deviceId, altitude, azimuth);

    return jsonOk({'status': 'slewing'});
  }

  Future<Response> handleMountFindHome(Request request) async {
    _logInfo('[API] POST /api/mount/find-home');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
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

    final backend = container.read(backendProvider);
    await backend.focuserMoveTo(deviceId, position);

    return jsonOk({'status': 'moving'});
  }

  Future<Response> handleFocuserMoveRelative(Request request) async {
    _logInfo('[API] POST /api/focuser/move-relative');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final delta = requireInt(payload, 'delta');

    final backend = container.read(backendProvider);
    await backend.focuserMoveRelative(deviceId, delta);

    return jsonOk({'status': 'moving'});
  }

  Future<Response> handleFocuserHalt(Request request) async {
    _logInfo('[API] POST /api/focuser/halt');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
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

    final backend = container.read(backendProvider);
    final result = await backend.autofocusStart(
      deviceId: deviceId,
      cameraId: cameraId,
      exposureTime: exposureTime,
      stepSize: stepSize,
      stepsOut: stepsOut,
      method: method,
      binning: binning,
    );

    return jsonOk(result.toJson());
  }

  Future<Response> handleAutofocusCancel(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/cancel');
    final backend = container.read(backendProvider);
    await backend.autofocusCancel();

    return jsonOk({'status': 'cancelled'});
  }

  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================

  Future<Response> handleFilterWheelSetPosition(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/position');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final position = requireInt(payload, 'position');

    final backend = container.read(backendProvider);
    await backend.filterWheelSetPosition(deviceId, position);

    return jsonOk({'status': 'ok'});
  }

  Future<Response> handleFilterWheelGetNames(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(backendProvider);
    final names = await backend.filterWheelGetNames(deviceId);

    return jsonOk({'names': names});
  }

  Future<Response> handleFilterWheelSetByName(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/set-by-name');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final name = requireString(payload, 'name');

    final backend = container.read(backendProvider);
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

    final backend = container.read(backendProvider);
    await backend.rotatorMoveTo(deviceId, angle);

    return jsonOk({'status': 'moving'});
  }

  Future<Response> handleRotatorMoveRelative(Request request) async {
    _logInfo('[API] POST /api/rotator/move-relative');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final delta = requireDouble(payload, 'delta');

    final backend = container.read(backendProvider);
    await backend.rotatorMoveRelative(deviceId, delta);

    return jsonOk({'status': 'moving'});
  }

  Future<Response> handleRotatorGetStatus(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';

    final backend = container.read(backendProvider);
    final angle = await backend.rotatorGetAngle(deviceId);

    return jsonOk({'position': angle});
  }

  Future<Response> handleRotatorHalt(Request request) async {
    _logInfo('[API] POST /api/rotator/halt');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.rotatorHalt(deviceId);

    return jsonOk({'status': 'halted'});
  }

  /// POST /api/rotator/sync — sync rotator reported sky angle to the supplied
  /// position angle (degrees) without moving the hardware. Used by the "Sync
  /// to image PA" workflow after a plate solve.
  ///
  /// Why this isn't a synonym for /api/rotator/move-to: ASCOM IRotatorV3
  /// separates Sync (mechanical-vs-sky offset adjustment) from MoveAbsolute
  /// (motion). Conflating them would slew the rotator every time the operator
  /// hit "Sync to image", which is the opposite of the intended effect.
  ///
  /// Body: `{deviceId, positionAngle}` — `positionAngle` is the canonical
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

    final backend = container.read(backendProvider);
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
