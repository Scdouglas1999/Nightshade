import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for imaging and plate solve endpoints
class ImagingHandlers {
  final ProviderContainer container;

  ImagingHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ImagingHandlers');

  // ===========================================================================
  // Plate Solving
  // ===========================================================================

  Future<Response> handlePlateSolve(Request request) async {
    _logInfo('[API] POST /api/plate-solve');
    final payload = await readJsonObject(request);
    final imagePath = requireString(payload, 'imagePath');
    final ra = optionalDouble(payload, 'ra');
    final dec = optionalDouble(payload, 'dec');
    final fovDegrees = optionalDouble(payload, 'fov');

    final backend = container.read(backendProvider);
    final result = await backend.plateSolve(
      imagePath: imagePath,
      ra: ra,
      dec: dec,
      fovDegrees: fovDegrees,
    );

    return jsonOk({
      'success': result.success,
      'ra': result.ra,
      'dec': result.dec,
      'pixelScale': result.pixelScale,
      'rotation': result.rotation,
      'fieldWidth': result.fieldWidth,
      'fieldHeight': result.fieldHeight,
      'solveTimeSecs': result.solveTimeSecs,
      'error': result.error,
    });
  }

  // ===========================================================================
  // Image Processing
  // ===========================================================================

  Future<Response> handleGetImageStats(Request request) async {
    _logInfo('[API] POST /api/imaging/stats');
    final payload = await readJsonObject(request);
    final width = requireInt(payload, 'width');
    final height = requireInt(payload, 'height');
    final dataList = requireList<int>(payload, 'data');
    final data = Uint16List.fromList(dataList);

    final backend = container.read(backendProvider);
    final stats = await backend.getImageStats(width, height, data);
    return jsonOk({'stats': stats.toJson()});
  }

  Future<Response> handleAutoStretchImage(Request request) async {
    _logInfo('[API] POST /api/imaging/stretch');
    final payload = await readJsonObject(request);
    final width = requireInt(payload, 'width');
    final height = requireInt(payload, 'height');
    final dataList = requireList<int>(payload, 'data');
    final data = Uint16List.fromList(dataList);

    final backend = container.read(backendProvider);
    final stretched = await backend.autoStretchImage(width, height, data);
    return jsonOk({'data': stretched.toList()});
  }

  Future<Response> handleGetStarCrops(Request request) async {
    _logInfo('[API] GET /api/imaging/star-crops');
    final deviceId = request.url.queryParameters['deviceId'];
    final maxCrops =
        int.tryParse(request.url.queryParameters['maxCrops'] ?? '') ?? 5;
    // Why: query param is required for this endpoint, but it's a GET so we
    // validate inline rather than via readJsonObject.
    if (deviceId == null || deviceId.isEmpty) {
      throw BadRequestError(
        field: 'deviceId',
        expected: 'string',
        message: "Missing 'deviceId' query parameter",
      );
    }

    final backend = container.read(backendProvider);
    final crops = await backend.getStarCropsFromLastImage(
      deviceId,
      maxCrops: maxCrops,
    );

    return jsonOk({
      'crops': crops
          .map((crop) => {
                'pixels_base64': crop.pixelsBase64,
                'width': crop.width,
                'height': crop.height,
                'hfr': crop.hfr,
                'snr': crop.snr,
              })
          .toList(),
    });
  }

  Future<Response> handleDebayerImage(Request request) async {
    _logInfo('[API] POST /api/imaging/debayer');
    final payload = await readJsonObject(request);
    final width = requireInt(payload, 'width');
    final height = requireInt(payload, 'height');
    final dataList = requireList<int>(payload, 'data');
    final data = Uint16List.fromList(dataList);
    final pattern = requireString(payload, 'pattern');
    final algorithm = requireString(payload, 'algorithm');

    final backend = container.read(backendProvider);
    final debayered =
        await backend.debayerImage(width, height, data, pattern, algorithm);
    return jsonOk({'data': debayered.toList()});
  }

  Future<Response> handleGetLastRawImageData(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    final backend = container.read(backendProvider);
    final data = await backend.getLastRawImageData(deviceId);

    // Why: raw image data is returned as a binary stream rather than JSON
    // to avoid base64 encoding overhead for large frames.
    return contentResponse(
      Uint8List.fromList(data),
      contentType: 'application/octet-stream',
      contentLength: data.length,
    );
  }

  Future<Response> handleSaveFitsFile(Request request) async {
    _logInfo('[API] POST /api/imaging/save-fits');
    final payload = await readJsonObject(request);
    final filePath = requireString(payload, 'filePath');
    final width = requireInt(payload, 'width');
    final height = requireInt(payload, 'height');
    final dataList = requireList<int>(payload, 'data');
    final headerJson = requireObject(payload, 'headerData');
    final headerData = FitsWriteHeader.fromJson(headerJson);

    final backend = container.read(backendProvider);
    await backend.saveFitsFile(
      filePath: filePath,
      width: width,
      height: height,
      data: dataList,
      headerData: headerData,
    );
    return jsonOk({'status': 'saved'});
  }

  Future<Response> handleSaveFitsFromLastCapture(Request request) async {
    _logInfo('[API] POST /api/imaging/save-fits-from-capture');
    final payload = await readJsonObject(request);
    final deviceId = requireString(payload, 'deviceId');
    final filePath = requireString(payload, 'filePath');
    final headerJson = requireObject(payload, 'headerData');
    final headerData = FitsWriteHeader.fromJson(headerJson);

    final backend = container.read(backendProvider);
    await backend.saveFitsFromLastCapture(
      deviceId: deviceId,
      filePath: filePath,
      headerData: headerData,
    );
    return jsonOk({'status': 'saved'});
  }

  Future<Response> handleClearDeviceImage(
      Request request, String deviceId) async {
    _logInfo('[API] DELETE /api/imaging/device-image/$deviceId');
    final backend = container.read(backendProvider);
    await backend.clearDeviceImage(deviceId);
    return jsonOk({'status': 'cleared'});
  }
}
