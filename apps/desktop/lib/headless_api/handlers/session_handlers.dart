import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for polar alignment and session/image endpoints
class SessionHandlers {
  final ProviderContainer container;

  SessionHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SessionHandlers');

  /// Parse an integer ID from a URL path segment, raising BadRequestError on
  /// malformed input. Without this, `int.parse` throws FormatException and the
  /// middleware would surface a 500 — but the caller's mistake is a 400.
  int _parsePathId(String value, String field) {
    final id = int.tryParse(value);
    if (id == null) {
      throw BadRequestError(
        field: field,
        expected: 'integer',
        message: 'Path segment is not a valid integer',
      );
    }
    return id;
  }

  // ===========================================================================
  // Polar Alignment
  // ===========================================================================

  Future<Response> handleStartPolarAlignment(Request request) async {
    _logInfo('[API] POST /api/polar-alignment/start');
    final payload = await readJsonObject(request);
    final exposureTime = requireDouble(payload, 'exposure_time');
    final stepSize = requireDouble(payload, 'step_size');
    final binning = requireInt(payload, 'binning');
    final isNorth = requireBool(payload, 'is_north');
    final manualRotation = requireBool(payload, 'manual_rotation');
    final rotateEast = requireBool(payload, 'rotate_east');
    final gain = optionalInt(payload, 'gain');
    final offset = optionalInt(payload, 'offset');
    final solveTimeout = optionalDouble(payload, 'solve_timeout');
    final startFromCurrent = optionalBool(payload, 'start_from_current');

    final backend = container.read(backendProvider);
    await backend.startPolarAlignment(
      exposureTime: exposureTime,
      stepSize: stepSize,
      binning: binning,
      isNorth: isNorth,
      manualRotation: manualRotation,
      rotateEast: rotateEast,
      gain: gain,
      offset: offset,
      solveTimeout: solveTimeout,
      startFromCurrent: startFromCurrent,
    );
    return jsonOk({"status": "started"});
  }

  Future<Response> handleStopPolarAlignment(Request request) async {
    _logInfo('[API] POST /api/polar-alignment/stop');
    final backend = container.read(backendProvider);
    await backend.stopPolarAlignment();
    return jsonOk({"status": "stopped"});
  }

  // ===========================================================================
  // Session Images
  // ===========================================================================

  Future<Response> handleGetSessionImages(
      Request request, String sessionId) async {
    _logInfo('[API] GET /api/sessions/$sessionId/images');
    final sid = _parsePathId(sessionId, 'sessionId');
    final database = container.read(databaseProvider);
    final images = await database.imagesDao.getImagesForSession(sid);
    final imagesJson = images.map((image) => image.toJson()).toList();

    return jsonOk({"images": imagesJson});
  }

  Future<Response> handleGetAllImages(Request request) async {
    _logInfo('[API] GET /api/images');
    final database = container.read(databaseProvider);
    final images = await database.imagesDao.getAllImages();
    return jsonOk({'images': images.map((image) => image.toJson()).toList()});
  }

  Future<Response> handleGetStandaloneImages(Request request) async {
    _logInfo('[API] GET /api/images/standalone');
    final database = container.read(databaseProvider);
    final images = await database.imagesDao.getAllImages();
    final standalone = images
        .where((image) => image.sessionId == null)
        .toList(growable: false);
    return jsonOk(
        {'images': standalone.map((image) => image.toJson()).toList()});
  }

  Future<Response> handleExportSessionJson(
    Request request,
    String sessionId,
  ) async {
    return _exportSessionFile(
      request,
      sessionId,
      fileType: 'json',
      exportAction: (service, sid) => service.exportToJson(sid),
      contentType: jsonContentType,
    );
  }

  Future<Response> handleExportSessionCsv(
    Request request,
    String sessionId,
  ) async {
    return _exportSessionFile(
      request,
      sessionId,
      fileType: 'csv',
      exportAction: (service, sid) => service.exportToCsv(sid),
      contentType: 'text/csv; charset=utf-8',
    );
  }

  Future<Response> handleExportSessionHtml(
    Request request,
    String sessionId,
  ) async {
    return _exportSessionFile(
      request,
      sessionId,
      fileType: 'html',
      exportAction: (service, sid) => service.exportToHtml(sid),
      contentType: 'text/html; charset=utf-8',
    );
  }

  Future<Response> handleExportSession(
    Request request,
    String sessionId,
    String format,
  ) async {
    switch (format.toLowerCase()) {
      case 'json':
        return handleExportSessionJson(request, sessionId);
      case 'csv':
        return handleExportSessionCsv(request, sessionId);
      case 'html':
        return handleExportSessionHtml(request, sessionId);
      default:
        return jsonBadRequest({
          'error': 'Unsupported export format',
          'supportedFormats': ['json', 'csv', 'html'],
        });
    }
  }

  Future<Response> handleGetImageThumbnail(
      Request request, String imageId) async {
    final iid = _parsePathId(imageId, 'imageId');
    final backend = container.read(backendProvider);
    final thumbnail = await backend.getImageThumbnail(iid);

    return contentResponse(
      thumbnail,
      contentType: 'image/jpeg',
      contentLength: thumbnail.length,
    );
  }

  Future<Response> handleDownloadImage(Request request, String imageId) async {
    final iid = _parsePathId(imageId, 'imageId');
    _logInfo('[API] GET /api/images/$iid/download');

    // Look up the image from the database
    final database = container.read(databaseProvider);
    final imagesDao = database.imagesDao;
    final dbImage = await imagesDao.getImageById(iid);

    if (dbImage == null) {
      return jsonNotFound({"error": "Image not found: $iid"});
    }

    // Get the file path and check if it exists
    final file = File(dbImage.filePath);
    if (!await file.exists()) {
      return jsonNotFound(
          {"error": "Image file not found: ${dbImage.filePath}"});
    }

    // Determine content type based on file extension
    final ext = dbImage.filePath.toLowerCase();
    String contentType;
    if (ext.endsWith('.fits') || ext.endsWith('.fit')) {
      contentType = 'application/fits';
    } else if (ext.endsWith('.xisf')) {
      contentType = 'application/x-xisf';
    } else if (ext.endsWith('.png')) {
      contentType = 'image/png';
    } else if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
      contentType = 'image/jpeg';
    } else if (ext.endsWith('.tif') || ext.endsWith('.tiff')) {
      contentType = 'image/tiff';
    } else {
      contentType = 'application/octet-stream';
    }

    // Stream the file
    final fileLength = await file.length();
    return attachmentResponse(
      file.openRead(),
      fileName: dbImage.fileName,
      contentType: contentType,
      contentLength: fileLength,
    );
  }

  Future<Response> _exportSessionFile(
    Request request,
    String sessionId, {
    required String fileType,
    required Future<String> Function(
            SessionExportService service, int sessionId)
        exportAction,
    required String contentType,
  }) async {
    _logInfo('[API] GET /api/sessions/$sessionId/export/$fileType');
    final sid = _parsePathId(sessionId, 'sessionId');
    final database = container.read(databaseProvider);
    final service = SessionExportService(
      sessionsDao: database.sessionsDao,
      imagesDao: database.imagesDao,
    );
    final filePath = await exportAction(service, sid);
    final file = File(filePath);

    if (!await file.exists()) {
      return jsonNotFound(
          {'error': 'Export not found for session $sessionId'});
    }

    final fileLength = await file.length();
    return attachmentResponse(
      file.openRead(),
      fileName: file.uri.pathSegments.last,
      contentType: contentType,
      contentLength: fileLength,
    );
  }
}
