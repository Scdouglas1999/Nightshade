import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for device control endpoints (camera, mount, focuser, filter wheel, rotator)
class DeviceHandlers {
  final ProviderContainer container;
  DeviceHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'DeviceHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'DeviceHandlers');

  // ===========================================================================
  // Camera Control
  // ===========================================================================

  Future<Response> handleCameraExpose(Request request) async {
    _logInfo('[API] POST /api/camera/expose');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final exposureTime = (payload['exposureTime'] as num).toDouble();
      final frameTypeStr = payload['frameType'] as String? ?? 'light';
      final frameType = _parseFrameType(frameTypeStr);

      final backend = container.read(backendProvider);
      await backend.cameraStartExposure(
        deviceId: deviceId,
        exposureTime: exposureTime,
        frameType: frameType,
        gain: payload['gain'] as int?,
        offset: payload['offset'] as int?,
        binX: payload['binX'] as int? ?? 1,
        binY: payload['binY'] as int? ?? 1,
        x: payload['x'] as int?,
        y: payload['y'] as int?,
        width: payload['width'] as int?,
        height: payload['height'] as int?,
      );

      return jsonOk({"status": "exposing"});
    } catch (e) {
      _logError('[API] Camera expose error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleCameraAbort(Request request) async {
    _logInfo('[API] POST /api/camera/abort');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.cameraAbortExposure(deviceId);

      return jsonOk({"status": "aborted"});
    } catch (e) {
      _logError('[API] Camera abort error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleCameraGetLastImage(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final image = await backend.cameraGetLastImage(deviceId);

      if (image == null) {
        return jsonOk({"image": null});
      }

      return jsonOk({
        "image": {
          "width": image.width,
          "height": image.height,
          "displayData": image.displayData,
          "histogram": image.histogram,
          "stats": {
            "min": image.stats.min,
            "max": image.stats.max,
            "mean": image.stats.mean,
            "median": image.stats.median,
            "stdDev": image.stats.stdDev,
            "hfr": image.stats.hfr,
            "starCount": image.stats.starCount,
          },
          "exposureTime": image.exposureTime,
          "timestamp": image.timestamp,
          "isColor": image.isColor,
        }
      });
    } catch (e) {
      _logError('[API] Camera get last image error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleCameraSetCooling(Request request) async {
    _logInfo('[API] POST /api/camera/cooling');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final enabled = payload['enabled'] as bool;
      final targetTemp = (payload['targetTemp'] as num?)?.toDouble();

      final backend = container.read(backendProvider);
      await backend.cameraSetCooling(
        deviceId: deviceId,
        enabled: enabled,
        targetTemp: targetTemp,
      );

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Camera set cooling error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleCameraSetReadoutMode(Request request) async {
    _logInfo('[API] POST /api/camera/readoutMode');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final modeIndex = payload['modeIndex'] as int;

      final backend = container.read(backendProvider);
      await backend.cameraSetReadoutMode(deviceId, modeIndex);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Camera set readout mode error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleCameraSetGain(Request request) async {
    _logInfo('[API] POST /api/camera/gain');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final gain = payload['gain'] as int;

      final backend = container.read(backendProvider);
      await backend.cameraSetGain(deviceId, gain);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Camera set gain error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleCameraSetOffset(Request request) async {
    _logInfo('[API] POST /api/camera/offset');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final offset = payload['offset'] as int;

      final backend = container.read(backendProvider);
      await backend.cameraSetOffset(deviceId, offset);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Camera set offset error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Mount Control
  // ===========================================================================

  Future<Response> handleMountSlew(Request request) async {
    _logInfo('[API] POST /api/mount/slew');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountSlewToCoordinates(deviceId, ra, dec);

      return jsonOk({"status": "slewing"});
    } catch (e) {
      _logError('[API] Mount slew error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountSync(Request request) async {
    _logInfo('[API] POST /api/mount/sync');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountSync(deviceId, ra, dec);

      return jsonOk({"status": "synced"});
    } catch (e) {
      _logError('[API] Mount sync error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountPark(Request request) async {
    _logInfo('[API] POST /api/mount/park');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountPark(deviceId);

      return jsonOk({"status": "parking"});
    } catch (e) {
      _logError('[API] Mount park error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountUnpark(Request request) async {
    _logInfo('[API] POST /api/mount/unpark');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountUnpark(deviceId);

      return jsonOk({"status": "unparked"});
    } catch (e) {
      _logError('[API] Mount unpark error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountSetTracking(Request request) async {
    _logInfo('[API] POST /api/mount/tracking');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final enabled = payload['enabled'] as bool;

      final backend = container.read(backendProvider);
      await backend.mountSetTracking(deviceId, enabled);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Mount set tracking error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountPulseGuide(Request request) async {
    _logInfo('[API] POST /api/mount/pulse-guide');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final direction = payload['direction'] as String;
      final durationMs = payload['durationMs'] as int;

      final backend = container.read(backendProvider);
      await backend.mountPulseGuide(
        deviceId: deviceId,
        direction: direction,
        durationMs: durationMs,
      );

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Mount pulse guide error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountAbort(Request request) async {
    _logInfo('[API] POST /api/mount/abort');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountAbort(deviceId);

      return jsonOk({"status": "aborted"});
    } catch (e) {
      _logError('[API] Mount abort error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountGetStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final status = await backend.mountGetStatus(deviceId);

      return jsonOk(status);
    } catch (e) {
      _logError('[API] Mount get status error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountSetTrackingRate(Request request) async {
    _logInfo('[API] POST /api/mount/set-tracking-rate');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final rate = payload['rate'] as int;

      final backend = container.read(backendProvider);
      await backend.mountSetTrackingRate(deviceId, rate);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Mount set tracking rate error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountMoveAxis(Request request) async {
    _logInfo('[API] POST /api/mount/move-axis');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final axis = payload['axis'] as int;
      final rate = (payload['rate'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountMoveAxis(deviceId, axis, rate);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Mount move axis error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountSlewAltAz(Request request) async {
    _logInfo('[API] POST /api/mount/slew-alt-az');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final altitude = (payload['altitude'] as num).toDouble();
      final azimuth = (payload['azimuth'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountSlewAltAz(deviceId, altitude, azimuth);

      return jsonOk({"status": "slewing"});
    } catch (e) {
      _logError('[API] Mount slew alt/az error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleMountFindHome(Request request) async {
    _logInfo('[API] POST /api/mount/find-home');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountFindHome(deviceId);

      return jsonOk({"status": "finding_home"});
    } catch (e) {
      _logError('[API] Mount find home error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Focuser Control
  // ===========================================================================

  Future<Response> handleFocuserMoveTo(Request request) async {
    _logInfo('[API] POST /api/focuser/move-to');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final position = payload['position'] as int;

      final backend = container.read(backendProvider);
      await backend.focuserMoveTo(deviceId, position);

      return jsonOk({"status": "moving"});
    } catch (e) {
      _logError('[API] Focuser move to error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleFocuserMoveRelative(Request request) async {
    _logInfo('[API] POST /api/focuser/move-relative');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final delta = payload['delta'] as int;

      final backend = container.read(backendProvider);
      await backend.focuserMoveRelative(deviceId, delta);

      return jsonOk({"status": "moving"});
    } catch (e) {
      _logError('[API] Focuser move relative error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleFocuserHalt(Request request) async {
    _logInfo('[API] POST /api/focuser/halt');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.focuserHalt(deviceId);

      return jsonOk({"status": "halted"});
    } catch (e) {
      _logError('[API] Focuser halt error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleAutofocusStart(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/start');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final cameraId = payload['cameraId'] as String;
      final exposureTime = (payload['exposureTime'] as num).toDouble();
      final stepSize = payload['stepSize'] as int;
      final stepsOut = payload['stepsOut'] as int;
      final method = payload['method'] as String? ?? 'VCurve';
      final binning = payload['binning'] as int? ?? 1;

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
    } catch (e) {
      _logError('[API] Autofocus start error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleAutofocusCancel(Request request) async {
    _logInfo('[API] POST /api/focuser/autofocus/cancel');
    try {
      final backend = container.read(backendProvider);
      await backend.autofocusCancel();

      return jsonOk({"status": "cancelled"});
    } catch (e) {
      _logError('[API] Autofocus cancel error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================

  Future<Response> handleFilterWheelSetPosition(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/position');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final position = payload['position'] as int;

      final backend = container.read(backendProvider);
      await backend.filterWheelSetPosition(deviceId, position);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Filter wheel set position error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleFilterWheelGetNames(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final names = await backend.filterWheelGetNames(deviceId);

      return jsonOk({"names": names});
    } catch (e) {
      _logError('[API] Filter wheel get names error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleFilterWheelSetByName(Request request) async {
    _logInfo('[API] POST /api/filter-wheel/set-by-name');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final name = payload['name'] as String;

      final backend = container.read(backendProvider);
      await backend.filterWheelSetByName(deviceId, name);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Filter wheel set by name error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Rotator Control
  // ===========================================================================

  Future<Response> handleRotatorMoveTo(Request request) async {
    _logInfo('[API] POST /api/rotator/move-to');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final angle = (payload['angle'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.rotatorMoveTo(deviceId, angle);

      return jsonOk({"status": "moving"});
    } catch (e) {
      _logError('[API] Rotator move to error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleRotatorMoveRelative(Request request) async {
    _logInfo('[API] POST /api/rotator/move-relative');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final delta = (payload['delta'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.rotatorMoveRelative(deviceId, delta);

      return jsonOk({"status": "moving"});
    } catch (e) {
      _logError('[API] Rotator move relative error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleRotatorGetStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final angle = await backend.rotatorGetAngle(deviceId);

      return jsonOk({"position": angle});
    } catch (e) {
      _logError('[API] Rotator get status error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleRotatorHalt(Request request) async {
    _logInfo('[API] POST /api/rotator/halt');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.rotatorHalt(deviceId);

      return jsonOk({"status": "halted"});
    } catch (e) {
      _logError('[API] Rotator halt error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
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
