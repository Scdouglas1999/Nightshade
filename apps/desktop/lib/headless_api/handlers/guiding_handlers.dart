import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for PHD2 guiding endpoints
class GuidingHandlers {
  final ProviderContainer container;

  GuidingHandlers(this.container);

  Future<Response> handlePhd2Connect(Request request) async {
    print('[API] POST /api/phd2/connect');
    try {
      final payload = jsonDecode(await request.readAsString());
      final host = payload['host'] as String? ?? 'localhost';
      final port = payload['port'] as int? ?? 4400;

      final backend = container.read(backendProvider);
      await backend.phd2Connect(host: host, port: port);

      return Response.ok(
        jsonEncode({"status": "connected"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 connect error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2Disconnect(Request request) async {
    print('[API] POST /api/phd2/disconnect');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2Disconnect();

      return Response.ok(
        jsonEncode({"status": "disconnected"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 disconnect error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2StartGuiding(Request request) async {
    print('[API] POST /api/phd2/start-guiding');
    try {
      final payload = jsonDecode(await request.readAsString());
      final settlePixels = (payload['settlePixels'] as num?)?.toDouble() ?? 1.0;
      final settleTime = (payload['settleTime'] as num?)?.toDouble() ?? 10.0;
      final settleTimeout = (payload['settleTimeout'] as num?)?.toDouble() ?? 60.0;

      final backend = container.read(backendProvider);
      await backend.phd2StartGuiding(
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );

      return Response.ok(
        jsonEncode({"status": "guiding"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 start guiding error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2StopGuiding(Request request) async {
    print('[API] POST /api/phd2/stop-guiding');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2StopGuiding();

      return Response.ok(
        jsonEncode({"status": "stopped"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 stop guiding error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2Dither(Request request) async {
    print('[API] POST /api/phd2/dither');
    try {
      final payload = jsonDecode(await request.readAsString());
      final amount = (payload['amount'] as num?)?.toDouble() ?? 5.0;
      final raOnly = payload['raOnly'] as bool? ?? false;
      final settlePixels = (payload['settlePixels'] as num?)?.toDouble() ?? 1.0;
      final settleTime = (payload['settleTime'] as num?)?.toDouble() ?? 10.0;
      final settleTimeout = (payload['settleTimeout'] as num?)?.toDouble() ?? 60.0;

      final backend = container.read(backendProvider);
      await backend.phd2Dither(
        amount: amount,
        raOnly: raOnly,
        settlePixels: settlePixels,
        settleTime: settleTime,
        settleTimeout: settleTimeout,
      );

      return Response.ok(
        jsonEncode({"status": "dithering"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 dither error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2GetStatus(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final status = await backend.phd2GetStatus();

      return Response.ok(
        jsonEncode({
          "state": status.state,
          "connected": status.connected,
          "rmsRa": status.rmsRa,
          "rmsDec": status.rmsDec,
          "rmsTotal": status.rmsTotal,
          "snr": status.snr,
          "starMass": status.starMass,
          "avgDistance": status.avgDistance,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 get status error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2SetPaused(Request request) async {
    print('[API] POST /api/phd2/pause');
    try {
      final payload = jsonDecode(await request.readAsString());
      final paused = payload['paused'] as bool;

      final backend = container.read(backendProvider);
      await backend.phd2SetPaused(paused);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 set paused error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2ClearCalibration(Request request) async {
    print('[API] POST /api/phd2/clear-calibration');
    try {
      final payload = jsonDecode(await request.readAsString());
      final which = payload['which'] as String? ?? 'both';

      final backend = container.read(backendProvider);
      await backend.phd2ClearCalibration(which: which);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 clear calibration error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2FlipCalibration(Request request) async {
    print('[API] POST /api/phd2/flip-calibration');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2FlipCalibration();

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 flip calibration error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2GetCalibrationData(Request request) async {
    print('[API] POST /api/phd2/get-calibration-data');
    try {
      final backend = container.read(backendProvider);
      final data = await backend.phd2GetCalibrationData();

      return Response.ok(
        jsonEncode({
          "isCalibrated": data.isCalibrated,
          "raAngle": data.rotationAngle,
          "raRate": data.raRate,
          "decRate": data.decRate,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 get calibration data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2FindStar(Request request) async {
    print('[API] POST /api/phd2/find-star');
    try {
      final backend = container.read(backendProvider);
      final (x, y) = await backend.phd2FindStar();

      return Response.ok(
        jsonEncode({"x": x, "y": y}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 find star error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2SetLockPosition(Request request) async {
    print('[API] POST /api/phd2/set-lock-position');
    try {
      final payload = jsonDecode(await request.readAsString());
      final x = (payload['x'] as num).toDouble();
      final y = (payload['y'] as num).toDouble();
      final exact = payload['exact'] as bool? ?? false;

      final backend = container.read(backendProvider);
      await backend.phd2SetLockPosition(x: x, y: y, exact: exact);

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 set lock position error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2GetLockPosition(Request request) async {
    try {
      final backend = container.read(backendProvider);
      final (x, y) = await backend.phd2GetLockPosition();

      return Response.ok(
        jsonEncode({"x": x, "y": y}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 get lock position error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2Loop(Request request) async {
    print('[API] POST /api/phd2/loop');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2Loop();

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 loop error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2DeselectStar(Request request) async {
    print('[API] POST /api/phd2/deselect-star');
    try {
      final backend = container.read(backendProvider);
      await backend.phd2DeselectStar();

      return Response.ok(
        jsonEncode({"status": "ok"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 deselect star error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2GetStarImage(Request request) async {
    try {
      final sizeStr = request.url.queryParameters['size'];
      final size = sizeStr != null ? int.tryParse(sizeStr) ?? 50 : 50;

      final backend = container.read(backendProvider);
      final starImage = await backend.phd2GetStarImage(size: size);

      // Return the star image data as JSON with base64-encoded pixels
      return Response.ok(
        jsonEncode({
          "frame": starImage.frame,
          "width": starImage.width,
          "height": starImage.height,
          "starX": starImage.starX,
          "starY": starImage.starY,
          "pixels": base64Encode(starImage.pixels),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 get star image error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2GetAlgoParamNames(Request request) async {
    try {
      final axis = request.url.queryParameters['axis'];
      if (axis == null || (axis != 'ra' && axis != 'dec')) {
        return Response.badRequest(
          body: jsonEncode({
            "error": "Missing or invalid 'axis' parameter. Must be 'ra' or 'dec'."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      final backend = container.read(backendProvider);
      final names = await backend.phd2GetAlgoParamNames(axis: axis);

      return Response.ok(
        jsonEncode({"axis": axis, "names": names}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 get algo param names error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2GetAlgoParam(Request request) async {
    try {
      final axis = request.url.queryParameters['axis'];
      final name = request.url.queryParameters['name'];

      if (axis == null || (axis != 'ra' && axis != 'dec')) {
        return Response.badRequest(
          body: jsonEncode({
            "error": "Missing or invalid 'axis' parameter. Must be 'ra' or 'dec'."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (name == null || name.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing 'name' parameter."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final backend = container.read(backendProvider);
      final value = await backend.phd2GetAlgoParam(axis: axis, name: name);

      return Response.ok(
        jsonEncode({"axis": axis, "name": name, "value": value}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 get algo param error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handlePhd2SetAlgoParam(Request request) async {
    print('[API] POST /api/phd2/algo-param');
    try {
      final payload = jsonDecode(await request.readAsString());
      final axis = payload['axis'] as String?;
      final name = payload['name'] as String?;
      final value = (payload['value'] as num?)?.toDouble();

      if (axis == null || (axis != 'ra' && axis != 'dec')) {
        return Response.badRequest(
          body: jsonEncode({
            "error": "Missing or invalid 'axis' parameter. Must be 'ra' or 'dec'."
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (name == null || name.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing 'name' parameter."}),
          headers: {'content-type': 'application/json'},
        );
      }

      if (value == null) {
        return Response.badRequest(
          body: jsonEncode({"error": "Missing 'value' parameter."}),
          headers: {'content-type': 'application/json'},
        );
      }

      final backend = container.read(backendProvider);
      await backend.phd2SetAlgoParam(axis: axis, name: name, value: value);

      return Response.ok(
        jsonEncode({"status": "ok", "axis": axis, "name": name, "value": value}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      print('[API] PHD2 set algo param error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
