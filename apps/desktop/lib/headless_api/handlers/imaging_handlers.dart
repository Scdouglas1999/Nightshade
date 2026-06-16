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

  /// optional job manager. When wired, plate-solve returns
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
    return jsonBadRequest({..._hostOnlyProcessingBody, 'operation': operation});
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
          final backend = container.read(imagingBackendProvider);
          final workFuture = backend.plateSolve(
            imagePath: imagePath,
            ra: ra,
            dec: dec,
            fovDegrees: fovDegrees,
          );
          final result = await Future.any<dynamic>([
            workFuture,
            cancellation.whenCancelled.then(
              (_) => _PlateSolveCancelled.instance,
            ),
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

    final backend = container.read(imagingBackendProvider);
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
  // Plate Solver Setup
  // ===========================================================================
  //
  // These run on the HOST, which owns the solver binaries + catalog. Remote
  // (phone) clients route their settings-page detect/verify/get/set calls
  // here so they operate on the host's filesystem and persist host config —
  // not the phone's. The host implementation goes through the imaging
  // backend (FfiBackend), which calls the Rust `api_platesolve_*`.

  /// GET /api/imaging/fits-dimensions?path=&lt;hostPath&gt;
  ///
  /// Returns the exact pixel dimensions of a host FITS file. Lets a remote
  /// client (e.g. the photometric-calibration wizard) get true width/height
  /// instead of estimating them from a star bounding box — the host reads the
  /// real header. Host paths only.
  Future<Response> handleGetFitsDimensions(Request request) async {
    final filePath = request.url.queryParameters['path'] ?? '';
    if (filePath.isEmpty) {
      throw BadRequestError(
        field: 'path',
        expected: 'string',
        message: "Missing 'path' query parameter (host FITS file path)",
      );
    }
    if (!await File(filePath).exists()) {
      return jsonNotFound({
        'error': 'fits_not_found',
        'message': 'No FITS file at host path: $filePath',
      });
    }
    final fits = await bridge.apiReadFitsFile(filePath: filePath);
    return jsonOk({'width': fits.width, 'height': fits.height});
  }

  Future<Response> handleDetectPlateSolvers(Request request) async {
    _logInfo('[API] GET /api/plate-solver/detect');
    final backend = container.read(imagingBackendProvider);
    final detection = await backend.detectPlateSolvers();
    return jsonOk({
      'astapPath': detection.astapPath,
      'astrometryPath': detection.astrometryPath,
      'catalogName': detection.catalogName,
      'catalogMagnitudeLimit': detection.catalogMagnitudeLimit,
      'catalogPath': detection.catalogPath,
    });
  }

  Future<Response> handleVerifyPlateSolver(Request request) async {
    _logInfo('[API] POST /api/plate-solver/verify');
    final payload = await readJsonObject(request);
    final executablePath = requireString(payload, 'executablePath');

    final backend = container.read(imagingBackendProvider);
    final info = await backend.verifyPlateSolver(executablePath);
    return jsonOk({
      'path': info.path,
      'flavour': info.flavour,
      'versionLine': info.versionLine,
    });
  }

  Future<Response> handleGetPlateSolverConfig(Request request) async {
    _logInfo('[API] GET /api/plate-solver/config');
    final backend = container.read(imagingBackendProvider);
    final pref = await backend.getPlateSolverConfig();
    return jsonOk({
      'astapPath': pref.astapPath,
      'astrometryPath': pref.astrometryPath,
      'catalogPath': pref.catalogPath,
      'solverChoice': pref.choice.serialized,
    });
  }

  Future<Response> handleSetPlateSolverConfig(Request request) async {
    _logInfo('[API] POST /api/plate-solver/config');
    final payload = await readJsonObject(request);
    final pref = PlateSolverPreference(
      astapPath: requireString(payload, 'astapPath'),
      astrometryPath: requireString(payload, 'astrometryPath'),
      catalogPath: requireString(payload, 'catalogPath'),
      choice: PlateSolverChoice.fromSerialized(
        requireString(payload, 'solverChoice'),
      ),
    );

    final backend = container.read(imagingBackendProvider);
    await backend.setPlateSolverConfig(pref);
    return jsonOk({'status': 'saved'});
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

    final backend = container.read(imagingBackendProvider);
    final crops = await backend.getStarCropsFromLastImage(
      deviceId,
      maxCrops: maxCrops,
    );

    return jsonOk({
      'crops': crops
          .map(
            (crop) => {
              'pixels_base64': crop.pixelsBase64,
              'width': crop.width,
              'height': crop.height,
              'hfr': crop.hfr,
              'snr': crop.snr,
            },
          )
          .toList(),
    });
  }

  Future<Response> handleDebayerImage(Request request) async {
    return _rejectClientPixelUpload('POST /api/imaging/debayer');
  }

  Future<Response> handleGetLastRawImageData(Request request) async {
    final deviceId = request.url.queryParameters['deviceId'] ?? '';
    // getLastRawImageData lives on DeviceBackend (raw pixels come from the
    // camera driver, not the imaging pipeline).
    final backend = container.read(deviceBackendProvider);
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

    final backend = container.read(imagingBackendProvider);
    await backend.saveFitsFromLastCapture(
      deviceId: deviceId,
      filePath: filePath,
      headerData: headerData,
    );
    return jsonOk({'status': 'saved'});
  }

  Future<Response> handleClearDeviceImage(
    Request request,
    String deviceId,
  ) async {
    _logInfo('[API] DELETE /api/imaging/device-image/$deviceId');
    // clearDeviceImage lives on DeviceBackend (operates on the camera
    // driver's last-image cache).
    final backend = container.read(deviceBackendProvider);
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
