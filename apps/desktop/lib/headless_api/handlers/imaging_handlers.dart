import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

/// Handlers for imaging and plate solve endpoints
class ImagingHandlers {
  final ProviderContainer container;

  ImagingHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ImagingHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'ImagingHandlers');

  // ===========================================================================
  // Plate Solving
  // ===========================================================================

  Future<Response> handlePlateSolve(Request request) async {
    _logInfo('[API] POST /api/plate-solve');
    try {
      final payload = jsonDecode(await request.readAsString());
      final imagePath = payload['imagePath'] as String;
      final ra = (payload['ra'] as num?)?.toDouble();
      final dec = (payload['dec'] as num?)?.toDouble();
      final fovDegrees = (payload['fov'] as num?)?.toDouble();

      final backend = container.read(backendProvider);
      final result = await backend.plateSolve(
        imagePath: imagePath,
        ra: ra,
        dec: dec,
        fovDegrees: fovDegrees,
      );

      return Response.ok(
        jsonEncode({
          "success": result.success,
          "ra": result.ra,
          "dec": result.dec,
          "pixelScale": result.pixelScale,
          "rotation": result.rotation,
          "fieldWidth": result.fieldWidth,
          "fieldHeight": result.fieldHeight,
          "solveTimeSecs": result.solveTimeSecs,
          "error": result.error,
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Plate solve error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ===========================================================================
  // Image Processing
  // ===========================================================================

  Future<Response> handleGetImageStats(Request request) async {
    _logInfo('[API] POST /api/imaging/stats');
    try {
      final payload = jsonDecode(await request.readAsString());
      final width = payload['width'] as int;
      final height = payload['height'] as int;
      final dataList = (payload['data'] as List).cast<int>();
      final data = Uint16List.fromList(dataList);

      final backend = container.read(backendProvider);
      final stats = await backend.getImageStats(width, height, data);
      return Response.ok(
        jsonEncode({"stats": stats.toJson()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Get image stats error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleAutoStretchImage(Request request) async {
    _logInfo('[API] POST /api/imaging/stretch');
    try {
      final payload = jsonDecode(await request.readAsString());
      final width = payload['width'] as int;
      final height = payload['height'] as int;
      final dataList = (payload['data'] as List).cast<int>();
      final data = Uint16List.fromList(dataList);

      final backend = container.read(backendProvider);
      final stretched = await backend.autoStretchImage(width, height, data);
      return Response.ok(
        jsonEncode({"data": stretched.toList()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Auto stretch error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleDebayerImage(Request request) async {
    _logInfo('[API] POST /api/imaging/debayer');
    try {
      final payload = jsonDecode(await request.readAsString());
      final width = payload['width'] as int;
      final height = payload['height'] as int;
      final dataList = (payload['data'] as List).cast<int>();
      final data = Uint16List.fromList(dataList);
      final pattern = payload['pattern'] as String;
      final algorithm = payload['algorithm'] as String;

      final backend = container.read(backendProvider);
      final debayered =
          await backend.debayerImage(width, height, data, pattern, algorithm);
      return Response.ok(
        jsonEncode({"data": debayered.toList()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Debayer error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleGetLastRawImageData(Request request) async {
    try {
      final deviceId = request.url.queryParameters['deviceId'] ?? '';
      final backend = container.read(backendProvider);
      final data = await backend.getLastRawImageData(deviceId);

      // Return as binary response for efficiency
      return Response.ok(
        Uint8List.fromList(data),
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': data.length.toString(),
        },
      );
    } catch (e) {
      _logError('[API] Get raw image data error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSaveFitsFile(Request request) async {
    _logInfo('[API] POST /api/imaging/save-fits');
    try {
      final payload = jsonDecode(await request.readAsString());
      final filePath = payload['filePath'] as String;
      final width = payload['width'] as int;
      final height = payload['height'] as int;
      final dataList = (payload['data'] as List).cast<int>();
      final headerJson = payload['headerData'] as Map<String, dynamic>;
      final headerData = FitsWriteHeader.fromJson(headerJson);

      final backend = container.read(backendProvider);
      await backend.saveFitsFile(
        filePath: filePath,
        width: width,
        height: height,
        data: dataList,
        headerData: headerData,
      );
      return Response.ok(
        jsonEncode({"status": "saved"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Save FITS file error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleSaveFitsFromLastCapture(Request request) async {
    _logInfo('[API] POST /api/imaging/save-fits-from-capture');
    try {
      final payload = jsonDecode(await request.readAsString());
      final deviceId = payload['deviceId'] as String;
      final filePath = payload['filePath'] as String;
      final headerJson = payload['headerData'] as Map<String, dynamic>;
      final headerData = FitsWriteHeader.fromJson(headerJson);

      final backend = container.read(backendProvider);
      await backend.saveFitsFromLastCapture(
        deviceId: deviceId,
        filePath: filePath,
        headerData: headerData,
      );
      return Response.ok(
        jsonEncode({"status": "saved"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Save FITS from capture error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleClearDeviceImage(
      Request request, String deviceId) async {
    _logInfo('[API] DELETE /api/imaging/device-image/$deviceId');
    try {
      final backend = container.read(backendProvider);
      await backend.clearDeviceImage(deviceId);
      return Response.ok(
        jsonEncode({"status": "cleared"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Clear device image error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
