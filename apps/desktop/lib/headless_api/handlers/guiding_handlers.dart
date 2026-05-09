import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for PHD2 guiding endpoints
class GuidingHandlers {
  final ProviderContainer container;

  GuidingHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'GuidingHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'GuidingHandlers');

  Future<Response> handlePhd2Connect(Request request) async {
    _logInfo('[API] POST /api/phd2/connect');
    try {
      final payload = jsonDecode(await request.readAsString());
      final host = payload['host'] as String? ?? 'localhost';
      final port = payload['port'] as int? ?? 4400;

      final backend = container.read(backendProvider);
      await backend.phd2Connect(host: host, port: port);

      return jsonOk({"status": "connected"});
    } catch (e) {
      _logError('[API] PHD2 connect error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2Disconnect(Request request) async {
    _logInfo('[API] POST /api/phd2/disconnect');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2Disconnect();

      return jsonOk({"status": "disconnected"});
    } catch (e) {
      _logError('[API] PHD2 disconnect error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2StartGuiding(Request request) async {
    _logInfo('[API] POST /api/phd2/start-guiding');
    try {
      final payload = jsonDecode(await request.readAsString());
      final settlePixels = (payload['settlePixels'] as num?)?.toDouble() ?? 1.0;
      final settleTime = (payload['settleTime'] as num?)?.toDouble() ?? 10.0;
      final settleTimeout =
          (payload['settleTimeout'] as num?)?.toDouble() ?? 60.0;

      final backend = container.read(backendProvider);
      await backend.phd2StartGuiding(
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );

      return jsonOk({"status": "guiding"});
    } catch (e) {
      _logError('[API] PHD2 start guiding error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2StopGuiding(Request request) async {
    _logInfo('[API] POST /api/phd2/stop-guiding');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2StopGuiding();

      return jsonOk({"status": "stopped"});
    } catch (e) {
      _logError('[API] PHD2 stop guiding error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2Dither(Request request) async {
    _logInfo('[API] POST /api/phd2/dither');
    try {
      final payload = jsonDecode(await request.readAsString());
      final amount = (payload['amount'] as num?)?.toDouble() ?? 5.0;
      final raOnly = payload['raOnly'] as bool? ?? false;
      final settlePixels = (payload['settlePixels'] as num?)?.toDouble() ?? 1.0;
      final settleTime = (payload['settleTime'] as num?)?.toDouble() ?? 10.0;
      final settleTimeout =
          (payload['settleTimeout'] as num?)?.toDouble() ?? 60.0;

      final backend = container.read(backendProvider);
      await backend.phd2Dither(
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );

      return jsonOk({"status": "dithering"});
    } catch (e) {
      _logError('[API] PHD2 dither error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2GetStatus(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final status = await backend.phd2GetStatus();

      return jsonOk({
        "state": status.state,
        "connected": status.connected,
        "rmsRa": status.rmsRa,
        "rmsDec": status.rmsDec,
        "rmsTotal": status.rmsTotal,
        "snr": status.snr,
        "starMass": status.starMass,
        "avgDistance": status.avgDistance,
      });
    } catch (e) {
      _logError('[API] PHD2 get status error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2SetPaused(Request request) async {
    _logInfo('[API] POST /api/phd2/pause');
    try {
      final payload = jsonDecode(await request.readAsString());
      final paused = payload['paused'] as bool;

      final backend = container.read(backendProvider);
      await backend.phd2SetPaused(paused);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] PHD2 set paused error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2ClearCalibration(Request request) async {
    _logInfo('[API] POST /api/phd2/clear-calibration');
    try {
      final payload = jsonDecode(await request.readAsString());
      final which = payload['which'] as String? ?? 'both';

      final backend = container.read(backendProvider);
      await backend.phd2ClearCalibration(which: which);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] PHD2 clear calibration error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2FlipCalibration(Request request) async {
    _logInfo('[API] POST /api/phd2/flip-calibration');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2FlipCalibration();

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] PHD2 flip calibration error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2GetCalibrationData(Request request) async {
    _logInfo('[API] POST /api/phd2/get-calibration-data');
    try {
      final backend = container.read(backendProvider);
      final data = await backend.phd2GetCalibrationData();

      return jsonOk({
        "isCalibrated": data.isCalibrated,
        "raAngle": data.rotationAngle,
        "raRate": data.raRate,
        "decRate": data.decRate,
      });
    } catch (e) {
      _logError('[API] PHD2 get calibration data error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2FindStar(Request request) async {
    _logInfo('[API] POST /api/phd2/find-star');
    try {
      final backend = container.read(backendProvider);
      final (x, y) = await backend.phd2FindStar();

      return jsonOk({"x": x, "y": y});
    } catch (e) {
      _logError('[API] PHD2 find star error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2SetLockPosition(Request request) async {
    _logInfo('[API] POST /api/phd2/set-lock-position');
    try {
      final payload = jsonDecode(await request.readAsString());
      final x = (payload['x'] as num).toDouble();
      final y = (payload['y'] as num).toDouble();
      final exact = payload['exact'] as bool? ?? false;

      final backend = container.read(backendProvider);
      await backend.phd2SetLockPosition(x: x, y: y, exact: exact);

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] PHD2 set lock position error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2GetLockPosition(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final (x, y) = await backend.phd2GetLockPosition();

      return jsonOk({"x": x, "y": y});
    } catch (e) {
      _logError('[API] PHD2 get lock position error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2Loop(Request request) async {
    _logInfo('[API] POST /api/phd2/loop');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2Loop();

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] PHD2 loop error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2DeselectStar(Request request) async {
    _logInfo('[API] POST /api/phd2/deselect-star');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2DeselectStar();

      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] PHD2 deselect star error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2GetStarImage(Request request) async {
    try {
      final sizeStr = request.url.queryParameters['size'];
      final size = sizeStr != null ? int.tryParse(sizeStr) ?? 50 : 50;

      final backend = container.read(backendProvider);
      final starImage = await backend.phd2GetStarImage(size: size);

      // Return the star image data as JSON with base64-encoded pixels
      return jsonOk({
        "frame": starImage.frame,
        "width": starImage.width,
        "height": starImage.height,
        "starX": starImage.starX,
        "starY": starImage.starY,
        "pixels": base64Encode(starImage.pixels),
      });
    } catch (e) {
      _logError('[API] PHD2 get star image error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2GetAlgoParamNames(Request request) async {
    try {
      final axis = request.url.queryParameters['axis'];
      if (axis == null || (axis != 'ra' && axis != 'dec')) {
        return jsonBadRequest({
          "error": "Missing or invalid 'axis' parameter. Must be 'ra' or 'dec'."
        });
      }

      final backend = container.read(backendProvider);
      final names = await backend.phd2GetAlgoParamNames(axis: axis);

      return jsonOk({"axis": axis, "names": names});
    } catch (e) {
      _logError('[API] PHD2 get algo param names error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2GetAlgoParam(Request request) async {
    try {
      final axis = request.url.queryParameters['axis'];
      final name = request.url.queryParameters['name'];

      if (axis == null || (axis != 'ra' && axis != 'dec')) {
        return jsonBadRequest({
          "error": "Missing or invalid 'axis' parameter. Must be 'ra' or 'dec'."
        });
      }

      if (name == null || name.isEmpty) {
        return jsonBadRequest({"error": "Missing 'name' parameter."});
      }

      final backend = container.read(backendProvider);
      final value = await backend.phd2GetAlgoParam(axis: axis, name: name);

      return jsonOk({"axis": axis, "name": name, "value": value});
    } catch (e) {
      _logError('[API] PHD2 get algo param error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handlePhd2SetAlgoParam(Request request) async {
    _logInfo('[API] POST /api/phd2/algo-param');
    try {
      final payload = jsonDecode(await request.readAsString());
      final axis = payload['axis'] as String?;
      final name = payload['name'] as String?;
      final value = (payload['value'] as num?)?.toDouble();

      if (axis == null || (axis != 'ra' && axis != 'dec')) {
        return jsonBadRequest({
          "error": "Missing or invalid 'axis' parameter. Must be 'ra' or 'dec'."
        });
      }

      if (name == null || name.isEmpty) {
        return jsonBadRequest({"error": "Missing 'name' parameter."});
      }

      if (value == null) {
        return jsonBadRequest({"error": "Missing 'value' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.phd2SetAlgoParam(axis: axis, name: name, value: value);

      return jsonOk(
        {"status": "ok", "axis": axis, "name": name, "value": value},
      );
    } catch (e) {
      _logError('[API] PHD2 set algo param error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderStartGuiding(Request request) async {
    _logInfo('[API] POST /api/guider/start-guiding');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.guiderStartGuiding(
        deviceId: deviceId,
        settlePixels: (payload['settlePixels'] as num?)?.toDouble() ?? 1.0,
        settleTime: (payload['settleTime'] as num?)?.toDouble() ?? 10.0,
        settleTimeout: (payload['settleTimeout'] as num?)?.toDouble() ?? 60.0,
      );

      return jsonOk({"status": "guiding", "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider start error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderStopGuiding(Request request) async {
    _logInfo('[API] POST /api/guider/stop-guiding');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.guiderStopGuiding(deviceId: deviceId);

      return jsonOk({"status": "stopped", "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider stop error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderDither(Request request) async {
    _logInfo('[API] POST /api/guider/dither');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.guiderDither(
        deviceId: deviceId,
        amount: (payload['amount'] as num?)?.toDouble() ?? 5.0,
        raOnly: payload['raOnly'] as bool? ?? false,
        settlePixels: (payload['settlePixels'] as num?)?.toDouble() ?? 1.0,
        settleTime: (payload['settleTime'] as num?)?.toDouble() ?? 10.0,
        settleTimeout: (payload['settleTimeout'] as num?)?.toDouble() ?? 60.0,
      );

      return jsonOk({"status": "dithering", "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider dither error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderLoop(Request request) async {
    _logInfo('[API] POST /api/guider/loop');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.guiderLoop(deviceId: deviceId);

      return jsonOk({"status": "looping", "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider loop error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderFindStar(Request request) async {
    _logInfo('[API] POST /api/guider/find-star');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      final (x, y) = await backend.guiderFindStar(deviceId: deviceId);

      return jsonOk({"x": x, "y": y, "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider find star error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderSetLockPosition(Request request) async {
    _logInfo('[API] POST /api/guider/set-lock-position');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final x = (payload['x'] as num?)?.toDouble();
      final y = (payload['y'] as num?)?.toDouble();
      if (x == null || y == null) {
        return jsonBadRequest({"error": "Missing 'x' or 'y' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.guiderSetLockPosition(
        deviceId: deviceId,
        x: x,
        y: y,
        exact: payload['exact'] as bool? ?? false,
      );

      return jsonOk({"status": "ok", "deviceId": deviceId, "x": x, "y": y});
    } catch (e) {
      _logError('[API] Guider set lock position error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderGetLockPosition(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'];
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      final (x, y) = await backend.guiderGetLockPosition(deviceId: deviceId);
      return jsonOk({"x": x, "y": y, "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider get lock position error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderDeselectStar(Request request) async {
    _logInfo('[API] POST /api/guider/deselect-star');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final deviceId = payload['deviceId'] as String?;
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }

      final backend = container.read(backendProvider);
      await backend.guiderDeselectStar(deviceId: deviceId);
      return jsonOk({"status": "ok", "deviceId": deviceId});
    } catch (e) {
      _logError('[API] Guider deselect star error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGuiderGetStarImage(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'];
      if (deviceId == null || deviceId.isEmpty) {
        return jsonBadRequest({"error": "Missing 'deviceId' parameter."});
      }
      final size =
          int.tryParse(request.url.queryParameters['size'] ?? '') ?? 50;

      final backend = container.read(backendProvider);
      final image =
          await backend.guiderGetStarImage(deviceId: deviceId, size: size);

      return jsonOk({
        "frame": image.frame,
        "width": image.width,
        "height": image.height,
        "starX": image.starX,
        "starY": image.starY,
        "pixels": base64Encode(image.pixels),
        "deviceId": deviceId,
      });
    } catch (e) {
      _logError('[API] Guider get star image error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleBuiltinGuiderGetConfig(Request request) async {
    _logInfo('[API] GET /api/builtin-guider/config');
    try {
      final backend = container.read(backendProvider);
      final config = await backend.builtinGuiderGetConfig();
      return jsonOk(config.toJson());
    } catch (e) {
      _logError('[API] Built-in guider config get error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleBuiltinGuiderSetConfig(Request request) async {
    _logInfo('[API] POST /api/builtin-guider/config');
    try {
      final payload =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final backend = container.read(backendProvider);
      await backend
          .builtinGuiderSetConfig(BuiltinGuiderConfig.fromJson(payload));
      return jsonOk({"status": "ok"});
    } catch (e) {
      _logError('[API] Built-in guider config set error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }
}
