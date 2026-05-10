import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for PHD2 guiding endpoints
class GuidingHandlers {
  final ProviderContainer container;

  GuidingHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'GuidingHandlers');

  Future<Response> handlePhd2Connect(Request request) async {
    _logInfo('[API] POST /api/phd2/connect');
    final payload = await readJsonObject(request);
    final host = optionalString(payload, 'host') ?? 'localhost';
    final port = optionalInt(payload, 'port') ?? 4400;

    final backend = container.read(backendProvider);
    await backend.phd2Connect(host: host, port: port);

    return jsonOk({"status": "connected"});
  }

  Future<Response> handlePhd2Disconnect(Request request) async {
    _logInfo('[API] POST /api/phd2/disconnect');
    final backend = container.read(backendProvider);
    await backend.phd2Disconnect();

    return jsonOk({"status": "disconnected"});
  }

  Future<Response> handlePhd2StartGuiding(Request request) async {
    _logInfo('[API] POST /api/phd2/start-guiding');
    final payload = await readJsonObject(request);
    final settlePixels = optionalDouble(payload, 'settlePixels') ?? 1.0;
    final settleTime = optionalDouble(payload, 'settleTime') ?? 10.0;
    final settleTimeout = optionalDouble(payload, 'settleTimeout') ?? 60.0;

    final backend = container.read(backendProvider);
    await backend.phd2StartGuiding(
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );

    return jsonOk({"status": "guiding"});
  }

  Future<Response> handlePhd2StopGuiding(Request request) async {
    _logInfo('[API] POST /api/phd2/stop-guiding');
    final backend = container.read(backendProvider);
    await backend.phd2StopGuiding();

    return jsonOk({"status": "stopped"});
  }

  Future<Response> handlePhd2Dither(Request request) async {
    _logInfo('[API] POST /api/phd2/dither');
    final payload = await readJsonObject(request);
    final amount = optionalDouble(payload, 'amount') ?? 5.0;
    final raOnly = optionalBool(payload, 'raOnly') ?? false;
    final settlePixels = optionalDouble(payload, 'settlePixels') ?? 1.0;
    final settleTime = optionalDouble(payload, 'settleTime') ?? 10.0;
    final settleTimeout = optionalDouble(payload, 'settleTimeout') ?? 60.0;

    final backend = container.read(backendProvider);
    await backend.phd2Dither(
      amount: amount,
      raOnly: raOnly,
      settlePixels: settlePixels,
      settleTime: settleTime,
      settleTimeout: settleTimeout,
    );

    return jsonOk({"status": "dithering"});
  }

  Future<Response> handlePhd2GetStatus(Request request) async {
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
  }

  Future<Response> handlePhd2SetPaused(Request request) async {
    _logInfo('[API] POST /api/phd2/pause');
    final payload = await readJsonObject(request);
    final paused = requireBool(payload, 'paused');

    final backend = container.read(backendProvider);
    await backend.phd2SetPaused(paused);

    return jsonOk({"status": "ok"});
  }

  Future<Response> handlePhd2ClearCalibration(Request request) async {
    _logInfo('[API] POST /api/phd2/clear-calibration');
    final payload = await readJsonObject(request);
    final which = optionalString(payload, 'which') ?? 'both';

    final backend = container.read(backendProvider);
    await backend.phd2ClearCalibration(which: which);

    return jsonOk({"status": "ok"});
  }

  Future<Response> handlePhd2FlipCalibration(Request request) async {
    _logInfo('[API] POST /api/phd2/flip-calibration');
    final backend = container.read(backendProvider);
    await backend.phd2FlipCalibration();

    return jsonOk({"status": "ok"});
  }

  Future<Response> handlePhd2GetCalibrationData(Request request) async {
    _logInfo('[API] POST /api/phd2/get-calibration-data');
    final backend = container.read(backendProvider);
    final data = await backend.phd2GetCalibrationData();

    return jsonOk({
      "isCalibrated": data.isCalibrated,
      "raAngle": data.rotationAngle,
      "raRate": data.raRate,
      "decRate": data.decRate,
    });
  }

  Future<Response> handlePhd2FindStar(Request request) async {
    _logInfo('[API] POST /api/phd2/find-star');
    final backend = container.read(backendProvider);
    final (x, y) = await backend.phd2FindStar();

    return jsonOk({"x": x, "y": y});
  }

  Future<Response> handlePhd2SetLockPosition(Request request) async {
    _logInfo('[API] POST /api/phd2/set-lock-position');
    final payload = await readJsonObject(request);
    final x = requireDouble(payload, 'x');
    final y = requireDouble(payload, 'y');
    final exact = optionalBool(payload, 'exact') ?? false;

    final backend = container.read(backendProvider);
    await backend.phd2SetLockPosition(x: x, y: y, exact: exact);

    return jsonOk({"status": "ok"});
  }

  Future<Response> handlePhd2GetLockPosition(Request request) async {
    final backend = container.read(backendProvider);
    final (x, y) = await backend.phd2GetLockPosition();

    return jsonOk({"x": x, "y": y});
  }

  Future<Response> handlePhd2Loop(Request request) async {
    _logInfo('[API] POST /api/phd2/loop');
    final backend = container.read(backendProvider);
    await backend.phd2Loop();

    return jsonOk({"status": "ok"});
  }

  Future<Response> handlePhd2DeselectStar(Request request) async {
    _logInfo('[API] POST /api/phd2/deselect-star');
    final backend = container.read(backendProvider);
    await backend.phd2DeselectStar();

    return jsonOk({"status": "ok"});
  }

  Future<Response> handlePhd2GetStarImage(Request request) async {
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
  }

  Future<Response> handlePhd2GetAlgoParamNames(Request request) async {
    final axis = request.url.queryParameters['axis'];
    if (axis == null || (axis != 'ra' && axis != 'dec')) {
      throw BadRequestError(
        field: 'axis',
        expected: "'ra' or 'dec'",
        message: "Missing or invalid 'axis' query parameter",
      );
    }

    final backend = container.read(backendProvider);
    final names = await backend.phd2GetAlgoParamNames(axis: axis);

    return jsonOk({"axis": axis, "names": names});
  }

  Future<Response> handlePhd2GetAlgoParam(Request request) async {
    final axis = request.url.queryParameters['axis'];
    final name = request.url.queryParameters['name'];

    if (axis == null || (axis != 'ra' && axis != 'dec')) {
      throw BadRequestError(
        field: 'axis',
        expected: "'ra' or 'dec'",
        message: "Missing or invalid 'axis' query parameter",
      );
    }

    if (name == null || name.isEmpty) {
      throw BadRequestError(
        field: 'name',
        expected: 'string',
        message: "Missing 'name' query parameter",
      );
    }

    final backend = container.read(backendProvider);
    final value = await backend.phd2GetAlgoParam(axis: axis, name: name);

    return jsonOk({"axis": axis, "name": name, "value": value});
  }

  Future<Response> handlePhd2SetAlgoParam(Request request) async {
    _logInfo('[API] POST /api/phd2/algo-param');
    final payload = await readJsonObject(request);
    final axis = requireString(payload, 'axis');
    if (axis != 'ra' && axis != 'dec') {
      throw BadRequestError(
        field: 'axis',
        expected: "'ra' or 'dec'",
      );
    }
    final name = requireString(payload, 'name');
    final value = requireDouble(payload, 'value');

    final backend = container.read(backendProvider);
    await backend.phd2SetAlgoParam(axis: axis, name: name, value: value);

    return jsonOk(
      {"status": "ok", "axis": axis, "name": name, "value": value},
    );
  }

  Future<Response> handleGuiderStartGuiding(Request request) async {
    _logInfo('[API] POST /api/guider/start-guiding');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.guiderStartGuiding(
      deviceId: deviceId,
      settlePixels: optionalDouble(payload, 'settlePixels') ?? 1.0,
      settleTime: optionalDouble(payload, 'settleTime') ?? 10.0,
      settleTimeout: optionalDouble(payload, 'settleTimeout') ?? 60.0,
    );

    return jsonOk({"status": "guiding", "deviceId": deviceId});
  }

  Future<Response> handleGuiderStopGuiding(Request request) async {
    _logInfo('[API] POST /api/guider/stop-guiding');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.guiderStopGuiding(deviceId: deviceId);

    return jsonOk({"status": "stopped", "deviceId": deviceId});
  }

  Future<Response> handleGuiderDither(Request request) async {
    _logInfo('[API] POST /api/guider/dither');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.guiderDither(
      deviceId: deviceId,
      amount: optionalDouble(payload, 'amount') ?? 5.0,
      raOnly: optionalBool(payload, 'raOnly') ?? false,
      settlePixels: optionalDouble(payload, 'settlePixels') ?? 1.0,
      settleTime: optionalDouble(payload, 'settleTime') ?? 10.0,
      settleTimeout: optionalDouble(payload, 'settleTimeout') ?? 60.0,
    );

    return jsonOk({"status": "dithering", "deviceId": deviceId});
  }

  Future<Response> handleGuiderLoop(Request request) async {
    _logInfo('[API] POST /api/guider/loop');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.guiderLoop(deviceId: deviceId);

    return jsonOk({"status": "looping", "deviceId": deviceId});
  }

  Future<Response> handleGuiderFindStar(Request request) async {
    _logInfo('[API] POST /api/guider/find-star');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    final (x, y) = await backend.guiderFindStar(deviceId: deviceId);

    return jsonOk({"x": x, "y": y, "deviceId": deviceId});
  }

  Future<Response> handleGuiderSetLockPosition(Request request) async {
    _logInfo('[API] POST /api/guider/set-lock-position');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final x = requireDouble(payload, 'x');
    final y = requireDouble(payload, 'y');

    final backend = container.read(backendProvider);
    await backend.guiderSetLockPosition(
      deviceId: deviceId,
      x: x,
      y: y,
      exact: optionalBool(payload, 'exact') ?? false,
    );

    return jsonOk({"status": "ok", "deviceId": deviceId, "x": x, "y": y});
  }

  Future<Response> handleGuiderGetLockPosition(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'];
    if (deviceId == null || deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }

    final backend = container.read(backendProvider);
    final (x, y) = await backend.guiderGetLockPosition(deviceId: deviceId);
    return jsonOk({"x": x, "y": y, "deviceId": deviceId});
  }

  Future<Response> handleGuiderDeselectStar(Request request) async {
    _logInfo('[API] POST /api/guider/deselect-star');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');

    final backend = container.read(backendProvider);
    await backend.guiderDeselectStar(deviceId: deviceId);
    return jsonOk({"status": "ok", "deviceId": deviceId});
  }

  Future<Response> handleGuiderGetStarImage(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'];
    if (deviceId == null || deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }
    final size = int.tryParse(request.url.queryParameters['size'] ?? '') ?? 50;

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
  }

  Future<Response> handleBuiltinGuiderGetConfig(Request request) async {
    _logInfo('[API] GET /api/builtin-guider/config');
    final backend = container.read(backendProvider);
    final config = await backend.builtinGuiderGetConfig();
    return jsonOk(config.toJson());
  }

  Future<Response> handleBuiltinGuiderSetConfig(Request request) async {
    _logInfo('[API] POST /api/builtin-guider/config');
    final payload = await readJsonObject(request);
    final backend = container.read(backendProvider);
    await backend
        .builtinGuiderSetConfig(BuiltinGuiderConfig.fromJson(payload));
    return jsonOk({"status": "ok"});
  }
}
