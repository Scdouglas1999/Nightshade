import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for device control endpoints (camera, mount, focuser, filter wheel, rotator)
class DeviceHandlers {
  final ProviderContainer container;

  DeviceHandlers(this.container);

  // ===========================================================================
  // Camera Control
  // ===========================================================================

  Future<Response> handleCameraExpose(Request request) async {
    print('[API] POST /api/camera/expose');
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

      return Response.ok(
        jsonEncode({"status": "exposing"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera expose error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleCameraAbort(Request request) async {
    print('[API] POST /api/camera/abort');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.cameraAbortExposure(deviceId);

      return Response.ok(
        jsonEncode({"status": "aborted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera abort error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleCameraGetLastImage(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final image = await backend.cameraGetLastImage(deviceId);

      if (image == null) {
        return Response.ok(
          jsonEncode({"image": null}),
          headers: {'content-type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({
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
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera get last image error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleCameraSetCooling(Request request) async {
    print('[API] POST /api/camera/cooling');
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

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera set cooling error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleCameraSetGain(Request request) async {
    print('[API] POST /api/camera/gain');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final gain = payload['gain'] as int;

      final backend = container.read(backendProvider);
      await backend.cameraSetGain(deviceId, gain);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera set gain error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleCameraSetOffset(Request request) async {
    print('[API] POST /api/camera/offset');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final offset = payload['offset'] as int;

      final backend = container.read(backendProvider);
      await backend.cameraSetOffset(deviceId, offset);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Camera set offset error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Mount Control
  // ===========================================================================

  Future<Response> handleMountSlew(Request request) async {
    print('[API] POST /api/mount/slew');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountSlewToCoordinates(deviceId, ra, dec);

      return Response.ok(
        jsonEncode({"status": "slewing"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount slew error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountSync(Request request) async {
    print('[API] POST /api/mount/sync');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final ra = (payload['ra'] as num).toDouble();
      final dec = (payload['dec'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountSync(deviceId, ra, dec);

      return Response.ok(
        jsonEncode({"status": "synced"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount sync error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountPark(Request request) async {
    print('[API] POST /api/mount/park');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountPark(deviceId);

      return Response.ok(
        jsonEncode({"status": "parking"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount park error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountUnpark(Request request) async {
    print('[API] POST /api/mount/unpark');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountUnpark(deviceId);

      return Response.ok(
        jsonEncode({"status": "unparked"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount unpark error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountSetTracking(Request request) async {
    print('[API] POST /api/mount/tracking');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final enabled = payload['enabled'] as bool;

      final backend = container.read(backendProvider);
      await backend.mountSetTracking(deviceId, enabled);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount set tracking error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountPulseGuide(Request request) async {
    print('[API] POST /api/mount/pulse-guide');
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

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount pulse guide error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountAbort(Request request) async {
    print('[API] POST /api/mount/abort');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.mountAbort(deviceId);

      return Response.ok(
        jsonEncode({"status": "aborted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount abort error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountGetStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final status = await backend.mountGetStatus(deviceId);

      return Response.ok(
        jsonEncode(status),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount get status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountSetTrackingRate(Request request) async {
    print('[API] POST /api/mount/set-tracking-rate');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final rate = payload['rate'] as int;

      final backend = container.read(backendProvider);
      await backend.mountSetTrackingRate(deviceId, rate);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount set tracking rate error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleMountMoveAxis(Request request) async {
    print('[API] POST /api/mount/move-axis');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final axis = payload['axis'] as int;
      final rate = (payload['rate'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.mountMoveAxis(deviceId, axis, rate);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Mount move axis error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Focuser Control
  // ===========================================================================

  Future<Response> handleFocuserMoveTo(Request request) async {
    print('[API] POST /api/focuser/move-to');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final position = payload['position'] as int;

      final backend = container.read(backendProvider);
      await backend.focuserMoveTo(deviceId, position);

      return Response.ok(
        jsonEncode({"status": "moving"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Focuser move to error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFocuserMoveRelative(Request request) async {
    print('[API] POST /api/focuser/move-relative');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final delta = payload['delta'] as int;

      final backend = container.read(backendProvider);
      await backend.focuserMoveRelative(deviceId, delta);

      return Response.ok(
        jsonEncode({"status": "moving"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Focuser move relative error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFocuserHalt(Request request) async {
    print('[API] POST /api/focuser/halt');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.focuserHalt(deviceId);

      return Response.ok(
        jsonEncode({"status": "halted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Focuser halt error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleAutofocusStart(Request request) async {
    print('[API] POST /api/focuser/autofocus/start');
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

      return Response.ok(
        jsonEncode(result.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Autofocus start error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleAutofocusCancel(Request request) async {
    print('[API] POST /api/focuser/autofocus/cancel');
    try {
      final backend = container.read(backendProvider);
      await backend.autofocusCancel();

      return Response.ok(
        jsonEncode({"status": "cancelled"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Autofocus cancel error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Filter Wheel Control
  // ===========================================================================

  Future<Response> handleFilterWheelSetPosition(Request request) async {
    print('[API] POST /api/filter-wheel/position');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final position = payload['position'] as int;

      final backend = container.read(backendProvider);
      await backend.filterWheelSetPosition(deviceId, position);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Filter wheel set position error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFilterWheelGetNames(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final names = await backend.filterWheelGetNames(deviceId);

      return Response.ok(
        jsonEncode({"names": names}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Filter wheel get names error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleFilterWheelSetByName(Request request) async {
    print('[API] POST /api/filter-wheel/set-by-name');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final name = payload['name'] as String;

      final backend = container.read(backendProvider);
      await backend.filterWheelSetByName(deviceId, name);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Filter wheel set by name error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Rotator Control
  // ===========================================================================

  Future<Response> handleRotatorMoveTo(Request request) async {
    print('[API] POST /api/rotator/move-to');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final angle = (payload['angle'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.rotatorMoveTo(deviceId, angle);

      return Response.ok(
        jsonEncode({"status": "moving"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Rotator move to error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleRotatorMoveRelative(Request request) async {
    print('[API] POST /api/rotator/move-relative');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final delta = (payload['delta'] as num).toDouble();

      final backend = container.read(backendProvider);
      await backend.rotatorMoveRelative(deviceId, delta);

      return Response.ok(
        jsonEncode({"status": "moving"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Rotator move relative error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleRotatorGetStatus(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';

      final backend = container.read(backendProvider);
      final angle = await backend.rotatorGetAngle(deviceId);

      return Response.ok(
        jsonEncode({"position": angle}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Rotator get status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleRotatorHalt(Request request) async {
    print('[API] POST /api/rotator/halt');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;

      final backend = container.read(backendProvider);
      await backend.rotatorHalt(deviceId);

      return Response.ok(
        jsonEncode({"status": "halted"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] Rotator halt error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  FrameType _parseFrameType(String type) {
    switch (type.toLowerCase()) {
      case 'light': return FrameType.light;
      case 'dark': return FrameType.dark;
      case 'flat': return FrameType.flat;
      case 'bias': return FrameType.bias;
      case 'darkflat': return FrameType.darkFlat;
      default: return FrameType.light;
    }
  }
}
