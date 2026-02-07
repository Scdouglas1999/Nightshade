import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

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
      return Response.ok(
        jsonEncode({"status": "started"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Start polar alignment error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleStopPolarAlignment(Request request) async {
    _logInfo('[API] POST /api/polar-alignment/stop');
    try {
      final backend = container.read(backendProvider);
      await backend.stopPolarAlignment();
      return Response.ok(
        jsonEncode({"status": "stopped"}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Stop polar alignment error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
      final backend = container.read(backendProvider);
      final images = await backend.getSessionImages(sid);

      // Convert to JSON-serializable format
      final imagesJson = images
          .map((img) => {
                'image_id': img.id,
                'file_path': img.filePath,
                'captured_at': img.capturedAt.millisecondsSinceEpoch ~/ 1000,
                'exposure_duration': img.settings.exposureTime,
                'gain': img.settings.gain,
                'offset': img.settings.offset,
                'bin_x': img.settings.binningX,
                'bin_y': img.settings.binningY,
                'filter': img.settings.filter,
                'frame_type': img.settings.frameType.name,
                'hfr': img.stats?.hfr,
                'star_count': img.stats?.starCount,
                'file_format': img.format.name,
              })
          .toList();

      return Response.ok(
        jsonEncode({"images": imagesJson}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      _logError('[API] Get session images error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Response> handleGetImageThumbnail(
      Request request, String imageId) async {
    try {
      final iid = int.parse(imageId);
      final backend = container.read(backendProvider);
      final thumbnail = await backend.getImageThumbnail(iid);

      return Response.ok(
        thumbnail,
        headers: {
          'content-type': 'image/jpeg',
          'content-length': thumbnail.length.toString(),
        },
      );
    } catch (e) {
      _logError('[API] Get image thumbnail error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
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
        return Response.notFound(
          jsonEncode({"error": "Image not found: $iid"}),
          headers: {'content-type': 'application/json'},
        );
      }

      // Get the file path and check if it exists
      final file = File(dbImage.filePath);
      if (!await file.exists()) {
        return Response.notFound(
          jsonEncode({"error": "Image file not found: ${dbImage.filePath}"}),
          headers: {'content-type': 'application/json'},
        );
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
      return Response.ok(
        file.openRead(),
        headers: {
          'content-type': contentType,
          'content-length': fileLength.toString(),
          'content-disposition': 'attachment; filename="${dbImage.fileName}"',
        },
      );
    } catch (e) {
      _logError('[API] Download image error: $e');
      return Response.internalServerError(
        body: jsonEncode({"error": e.toString()}),
        headers: {'content-type': 'application/json'},
      );
    }
  }
}
