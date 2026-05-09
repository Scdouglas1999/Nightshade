import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// Handlers for polar alignment and session/image endpoints
class SessionHandlers {
  final ProviderContainer container;

  SessionHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SessionHandlers');
  void _logError(String message) =>
      _logger.error(message, source: 'SessionHandlers');

  // ===========================================================================
  // Polar Alignment
  // ===========================================================================

  Future<Response> handleStartPolarAlignment(Request request) async {
    _logInfo('[API] POST /api/polar-alignment/start');
    try {
      final payload = jsonDecode(await request.readAsString());
      final exposureTime = (payload['exposure_time'] as num).toDouble();
      final stepSize = (payload['step_size'] as num).toDouble();
      final binning = payload['binning'] as int;
      final isNorth = payload['is_north'] as bool;
      final manualRotation = payload['manual_rotation'] as bool;
      final rotateEast = payload['rotate_east'] as bool;
      final gain = payload['gain'] as int?;
      final offset = payload['offset'] as int?;
      final solveTimeout = (payload['solve_timeout'] as num?)?.toDouble();
      final startFromCurrent = payload['start_from_current'] as bool?;

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
    } catch (e) {
      _logError('[API] Start polar alignment error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleStopPolarAlignment(Request request) async {
    _logInfo('[API] POST /api/polar-alignment/stop');
    try {
      final backend = container.read(backendProvider);
      await backend.stopPolarAlignment();
      return jsonOk({"status": "stopped"});
    } catch (e) {
      _logError('[API] Stop polar alignment error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  // ===========================================================================
  // Session Images
  // ===========================================================================

  Future<Response> handleGetSessionImages(
      Request request, String sessionId) async {
    _logInfo('[API] GET /api/sessions/$sessionId/images');
    try {
      final sid = int.parse(sessionId);
      final database = container.read(databaseProvider);
      final images = await database.imagesDao.getImagesForSession(sid);
      final imagesJson = images.map((image) => image.toJson()).toList();

      return jsonOk({"images": imagesJson});
    } catch (e) {
      _logError('[API] Get session images error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleGetAllImages(Request request) async {
    _logInfo('[API] GET /api/images');
    try {
      final database = container.read(databaseProvider);
      final images = await database.imagesDao.getAllImages();
      return jsonOk({'images': images.map((image) => image.toJson()).toList()});
    } catch (e) {
      _logError('[API] Get all images error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }

  Future<Response> handleGetStandaloneImages(Request request) async {
    _logInfo('[API] GET /api/images/standalone');
    try {
      final database = container.read(databaseProvider);
      final images = await database.imagesDao.getAllImages();
      final standalone = images
          .where((image) => image.sessionId == null)
          .toList(growable: false);
      return jsonOk(
          {'images': standalone.map((image) => image.toJson()).toList()});
    } catch (e) {
      _logError('[API] Get standalone images error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
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
    try {
      final iid = int.parse(imageId);
      final backend = container.read(backendProvider);
      final thumbnail = await backend.getImageThumbnail(iid);

      return contentResponse(
        thumbnail,
        contentType: 'image/jpeg',
        contentLength: thumbnail.length,
      );
    } catch (e) {
      _logError('[API] Get image thumbnail error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
  }

  Future<Response> handleDownloadImage(Request request, String imageId) async {
    try {
      final iid = int.parse(imageId);
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
    } catch (e) {
      _logError('[API] Download image error: $e');
      return jsonInternalServerError({"error": e.toString()});
    }
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
    try {
      final sid = int.parse(sessionId);
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
    } catch (e) {
      _logError('[API] Session export error: $e');
      return jsonInternalServerError({'error': e.toString()});
    }
  }
}
