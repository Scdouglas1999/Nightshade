import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' as bridge;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as path;
import 'package:shelf/shelf.dart';

import '../job_manager.dart';
import '../response_helpers.dart';
import '../validation.dart';
import 'device_handlers.dart' show requestPrefersLegacyBlocking;

/// Handlers for imaging and plate solve endpoints
class ImagingHandlers {
  final ProviderContainer container;

  /// P1-2 / P1-3: optional job manager. When wired, plate-solve returns
  /// `{jobId, status: queued}` immediately and the actual solve runs in
  /// the background. Null in legacy callers / tests that exercise the
  /// blocking shape.
  final JobManager? jobManager;

  ImagingHandlers(this.container, {this.jobManager});

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'ImagingHandlers');

  /// Remote clients must not upload full-frame pixel arrays for host processing.
  static const Map<String, Object> _hostOnlyProcessingBody = {
    'error':
        'Full-frame pixel upload is not supported on the remote API. '
            'Processing runs on the host; use host-authoritative endpoints.',
    'code': 'host_only_processing',
    'hostEndpoints': <String>[
      'POST /api/imaging/save-fits-from-capture',
      'GET /api/camera/last-image/jpeg',
      'GET /api/imaging/raw-data',
    ],
  };

  Response _rejectClientPixelUpload(String operation) {
    _logInfo('[API] $operation rejected (host-only processing)');
    return jsonBadRequest({
      ..._hostOnlyProcessingBody,
      'operation': operation,
    });
  }

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

    final mgr = jobManager;
    final preferLegacy = requestPrefersLegacyBlocking(request);
    if (mgr != null && !preferLegacy) {
      final job = mgr.start(
        operation: 'plate-solve',
        deviceId: null,
        work: (sink, cancellation) async {
          sink.update(null, 'Solving $imagePath');
          final backend = container.read(backendProvider);
          final workFuture = backend.plateSolve(
            imagePath: imagePath,
            ra: ra,
            dec: dec,
            fovDegrees: fovDegrees,
          );
          final result = await Future.any<dynamic>([
            workFuture,
            cancellation.whenCancelled.then((_) => _PlateSolveCancelled.instance),
          ]);
          if (result is _PlateSolveCancelled) {
            throw const JobCancelledException(
              'Plate-solve cancellation requested by client',
            );
          }
          final solve = result as PlateSolveResult;
          return {
            'success': solve.success,
            'ra': solve.ra,
            'dec': solve.dec,
            'pixelScale': solve.pixelScale,
            'rotation': solve.rotation,
            'fieldWidth': solve.fieldWidth,
            'fieldHeight': solve.fieldHeight,
            'solveTimeSecs': solve.solveTimeSecs,
            'error': solve.error,
          };
        },
      );
      return jsonOk({
        'jobId': job.jobId,
        'status': job.state.wireName,
        'operation': job.operation,
      });
    }

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
    return _rejectClientPixelUpload('POST /api/imaging/stats');
  }

  Future<Response> handleAutoStretchImage(Request request) async {
    return _rejectClientPixelUpload('POST /api/imaging/stretch');
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
    return _rejectClientPixelUpload('POST /api/imaging/debayer');
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
    return _rejectClientPixelUpload('POST /api/imaging/save-fits');
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

  Future<Response> handleCalibrateImageFile(Request request) async {
    _logInfo('[API] POST /api/imaging/calibrate-file');
    final payload = await readJsonObject(request);
    final lightPath = requireString(payload, 'lightPath');
    final darkPath = optionalString(payload, 'darkPath');
    final flatPath = optionalString(payload, 'flatPath');
    final biasPath = optionalString(payload, 'biasPath');
    final outputPath = requireString(payload, 'outputPath');

    if (darkPath == null && flatPath == null && biasPath == null) {
      throw BadRequestError(
        field: 'calibrationFrames',
        expected: 'at least one of darkPath, flatPath, biasPath',
        message: 'No calibration frames provided',
      );
    }

    for (final entry in [
      ('dark', darkPath),
      ('flat', flatPath),
      ('bias', biasPath),
    ]) {
      final framePath = entry.$2;
      if (framePath != null && !File(framePath).existsSync()) {
        throw BadRequestError(
          field: '${entry.$1}Path',
          expected: 'existing host file',
          message: '${entry.$1} frame file not found: $framePath',
        );
      }
    }

    if (!File(lightPath).existsSync()) {
      throw BadRequestError(
        field: 'lightPath',
        expected: 'existing host file',
        message: 'Light frame file not found: $lightPath',
      );
    }

    final outDir = Directory(path.dirname(outputPath));
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    await bridge.apiCalibrateImageFile(
      lightPath: lightPath,
      darkPath: darkPath,
      flatPath: flatPath,
      biasPath: biasPath,
      outputPath: outputPath,
    );

    return jsonOk({
      'outputPath': outputPath,
      'darkApplied': darkPath != null,
      'flatApplied': flatPath != null,
      'biasApplied': biasPath != null,
      'darkUsed': darkPath,
      'flatUsed': flatPath,
      'biasUsed': biasPath,
    });
  }
}

/// Sentinel marking the cancellation branch of a Future.any race against
/// a long-running plate-solve. Library-private to this file; the analogous
/// sentinel in device_handlers is similarly private (a shared one would
/// pull device_handlers into the imaging-only test path).
class _PlateSolveCancelled {
  const _PlateSolveCancelled._();
  static const _PlateSolveCancelled instance = _PlateSolveCancelled._();
}
