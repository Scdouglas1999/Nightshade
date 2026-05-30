import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../job_manager.dart';
import '../response_helpers.dart';
import '../validation.dart';
import 'device_handlers.dart' show requestPrefersLegacyBlocking;

/// Handlers for polar alignment and session/image endpoints
class SessionHandlers {
  final ProviderContainer container;

  /// P1-2 / P1-3: optional job manager. When wired, polar-alignment
  /// endpoints return `{jobId, status: queued}` immediately. The actual
  /// alignment routine streams progress via WS events.
  final JobManager? jobManager;

  SessionHandlers(this.container, {this.jobManager});

  LoggingService get _logger => container.read(loggingServiceProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'SessionHandlers');

  /// Parse an integer ID from a URL path segment, raising BadRequestError on
  /// malformed input. Without this, `int.parse` throws FormatException and the
  /// middleware would surface a 500 â€” but the caller's mistake is a 400.
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

    final mgr = jobManager;
    final preferLegacy = requestPrefersLegacyBlocking(request);
    if (mgr != null && !preferLegacy) {
      // The backend `startPolarAlignment` already returns immediately
      // (it kicks off an async session). Wrapping it in a Job gives
      // clients a stable identifier they can correlate with subsequent
      // `polarAlignmentEvents` and use to detect session-completion via
      // the JobCompleted broadcast.
      final job = mgr.start(
        operation: 'polar-alignment.start',
        deviceId: null,
        work: (sink, cancellation) async {
          sink.update(null, 'Starting polar alignment');
          final backend = container.read(imagingBackendProvider);
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
          return {'status': 'started'};
        },
      );
      return jsonOk({
        'jobId': job.jobId,
        'status': job.state.wireName,
        'operation': job.operation,
      });
    }

    final backend = container.read(imagingBackendProvider);
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
    final backend = container.read(imagingBackendProvider);
    await backend.stopPolarAlignment();
    return jsonOk({"status": "stopped"});
  }

  Future<Response> handleStartAllSkyPolarAlignment(Request request) async {
    _logInfo('[API] POST /api/polar-alignment/all-sky/start');
    final payload = await readJsonObject(request);
    final exposureTime = requireDouble(payload, 'exposure_time');
    final solveTimeout = requireDouble(payload, 'solve_timeout');
    final binning = requireInt(payload, 'binning');
    final isNorth = requireBool(payload, 'is_north');
    final acceptanceThresholdArcsec =
        requireDouble(payload, 'acceptance_threshold_arcsec');
    final iterationCadenceSecs =
        requireDouble(payload, 'iteration_cadence_secs');
    final gain = optionalInt(payload, 'gain');
    final offset = optionalInt(payload, 'offset');

    final mgr = jobManager;
    final preferLegacy = requestPrefersLegacyBlocking(request);
    if (mgr != null && !preferLegacy) {
      final job = mgr.start(
        operation: 'polar-alignment.all-sky.start',
        deviceId: null,
        work: (sink, cancellation) async {
          sink.update(null, 'Starting all-sky polar alignment');
          final backend = container.read(imagingBackendProvider);
          await backend.startAllSkyPolarAlignment(
            exposureTime: exposureTime,
            solveTimeout: solveTimeout,
            binning: binning,
            isNorth: isNorth,
            acceptanceThresholdArcsec: acceptanceThresholdArcsec,
            iterationCadenceSecs: iterationCadenceSecs,
            gain: gain,
            offset: offset,
          );
          return {'status': 'started'};
        },
      );
      return jsonOk({
        'jobId': job.jobId,
        'status': job.state.wireName,
        'operation': job.operation,
      });
    }

    final backend = container.read(imagingBackendProvider);
    await backend.startAllSkyPolarAlignment(
      exposureTime: exposureTime,
      solveTimeout: solveTimeout,
      binning: binning,
      isNorth: isNorth,
      acceptanceThresholdArcsec: acceptanceThresholdArcsec,
      iterationCadenceSecs: iterationCadenceSecs,
      gain: gain,
      offset: offset,
    );
    return jsonOk({"status": "started"});
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
    final producingNodeId = request.url.queryParameters['producingNodeId'];
    final producingRunId = request.url.queryParameters['producingRunId'];
    final targetIdParam = request.url.queryParameters['targetId'];
    final limitParam = request.url.queryParameters['limit'];

    if (producingNodeId != null && producingNodeId.isNotEmpty) {
      final limit = int.tryParse(limitParam ?? '') ?? 100;
      final thumbs = await database.imagesDao.getImagesByProducingNode(
        producingNodeId: producingNodeId,
        producingRunId: producingRunId,
        limit: limit,
      );
      return jsonOk({
        'images': thumbs.map(_producingThumbnailToJson).toList(),
      });
    }

    if (targetIdParam != null) {
      final targetId = int.tryParse(targetIdParam);
      if (targetId == null) {
        throw BadRequestError(
          field: 'targetId',
          expected: 'integer',
          message: 'targetId query parameter must be a valid integer',
        );
      }
      final images = await database.imagesDao.getImagesForTarget(targetId);
      return jsonOk(
          {'images': images.map((image) => image.toJson()).toList()});
    }

    final images = await database.imagesDao.getAllImages();
    return jsonOk({'images': images.map((image) => image.toJson()).toList()});
  }

  Future<Response> handleGetImageById(Request request, String imageId) async {
    _logInfo('[API] GET /api/images/$imageId');
    final iid = _parsePathId(imageId, 'imageId');
    final database = container.read(databaseProvider);
    final image = await database.imagesDao.getImageById(iid);
    if (image == null) {
      return jsonNotFound({'error': 'Image not found: $iid'});
    }
    return jsonOk({'image': image.toJson()});
  }

  Future<Response> handleCreateImage(Request request) async {
    _logInfo('[API] POST /api/images');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);

    final capturedAtMs = payload['capturedAt'];
    final capturedAt = capturedAtMs is int
        ? DateTime.fromMillisecondsSinceEpoch(capturedAtMs)
        : DateTime.tryParse(capturedAtMs?.toString() ?? '') ?? DateTime.now();

    // P0-5 #2 â€” honour fileSize from the payload if supplied; otherwise
    // try to stat the on-disk file. The latter only succeeds when the
    // POSTed filePath happens to be local to the server (e.g. a sidecar
    // helper that wrote the FITS via NFS and then registered the row);
    // when it doesn't exist we leave NULL and the row still goes in.
    int? fileSize = optionalInt(payload, 'fileSize');
    final postedPath = requireString(payload, 'filePath');
    if (fileSize == null && postedPath.isNotEmpty) {
      try {
        final f = File(postedPath);
        if (await f.exists()) {
          fileSize = await f.length();
        }
      } catch (e) {
        // The file exists check passed but length() still failed â€”
        // unusual enough to log so the operator knows the row went in
        // without a size.
        _logger.warning(
          'handleCreateImage: failed to stat $postedPath: $e â€” row will '
          'be inserted with NULL file_size',
          source: 'SessionHandlers',
        );
      }
    }

    final id = await database.imagesDao.createImage(
      CapturedImagesCompanion.insert(
        filePath: postedPath,
        fileName: requireString(payload, 'fileName'),
        fileFormat: Value(optionalString(payload, 'fileFormat') ?? 'fits'),
        fileSize: Value(fileSize),
        sessionId: Value(optionalInt(payload, 'sessionId')),
        targetId: Value(optionalInt(payload, 'targetId')),
        frameType: Value(requireString(payload, 'frameType')),
        exposureDuration: requireDouble(payload, 'exposureDuration'),
        gain: Value(optionalInt(payload, 'gain')),
        offset: Value(optionalInt(payload, 'offset')),
        binX: Value(optionalInt(payload, 'binX') ?? 1),
        binY: Value(optionalInt(payload, 'binY') ?? 1),
        filter: Value(optionalString(payload, 'filter')),
        sensorTemp: Value(optionalDouble(payload, 'sensorTemp')),
        coolerPower: Value(optionalDouble(payload, 'coolerPower')),
        hfr: Value(optionalDouble(payload, 'hfr')),
        starCount: Value(optionalInt(payload, 'starCount')),
        background: Value(optionalDouble(payload, 'background')),
        noise: Value(optionalDouble(payload, 'noise')),
        qualityScore: Value(optionalDouble(payload, 'qualityScore')),
        guidingRmsRa: Value(optionalDouble(payload, 'guidingRmsRa')),
        guidingRmsDec: Value(optionalDouble(payload, 'guidingRmsDec')),
        guidingRmsTotal: Value(optionalDouble(payload, 'guidingRmsTotal')),
        mountRa: Value(optionalDouble(payload, 'mountRa')),
        mountDec: Value(optionalDouble(payload, 'mountDec')),
        mountAltitude: Value(optionalDouble(payload, 'mountAltitude')),
        mountAzimuth: Value(optionalDouble(payload, 'mountAzimuth')),
        focuserPosition: Value(optionalInt(payload, 'focuserPosition')),
        focuserTemp: Value(optionalDouble(payload, 'focuserTemp')),
        rotatorAngle: Value(optionalDouble(payload, 'rotatorAngle')),
        isPlateSolved:
            Value(optionalBool(payload, 'isPlateSolved') ?? false),
        solvedRa: Value(optionalDouble(payload, 'solvedRa')),
        solvedDec: Value(optionalDouble(payload, 'solvedDec')),
        solvedRotation: Value(optionalDouble(payload, 'solvedRotation')),
        solvedPixelScale: Value(optionalDouble(payload, 'solvedPixelScale')),
        capturedAt: capturedAt,
        isAccepted: Value(optionalBool(payload, 'isAccepted') ?? true),
        rejectionReason: Value(optionalString(payload, 'rejectionReason')),
      ),
    );

    final producingNodeId = optionalString(payload, 'producingNodeId');
    if (producingNodeId != null && producingNodeId.isNotEmpty) {
      await database.imagesDao.stampProducingNode(
        imageId: id,
        producingNodeId: producingNodeId,
        producingRunId: optionalString(payload, 'producingRunId'),
        runtimeGrade: optionalString(payload, 'runtimeGrade'),
        eccentricity: optionalDouble(payload, 'eccentricity'),
      );
    }

    // P1-13: schedule fire-and-forget sidecar generation for the new row.
    // Skips when filePath is empty (no FITS to encode) or the file isn't
    // on disk â€” the service logs both cases at warning severity. The
    // capture is fully recorded by this point so a sidecar failure does
    // not impact the response.
    if (postedPath.isNotEmpty) {
      try {
        final sidecarService =
            container.read(thumbnailSidecarServiceProvider);
        sidecarService.scheduleSidecarWrite(
          imageId: id,
          fitsPath: postedPath,
          imagesDao: database.imagesDao,
        );
      } catch (e) {
        _logger.warning(
          'handleCreateImage: failed to schedule sidecar for image $id '
          '($postedPath): $e',
          source: 'SessionHandlers',
        );
      }
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.capturedImage,
      action: HostMutationAction.created,
      entityId: id.toString(),
    );
    return jsonOk({'status': 'created', 'id': id});
  }

  Future<Response> handleUpdateImage(Request request, String imageId) async {
    _logInfo('[API] PUT /api/images/$imageId');
    final iid = _parsePathId(imageId, 'imageId');
    final payload = await readJsonObject(request);
    final database = container.read(databaseProvider);
    final imagesDao = database.imagesDao;

    final existing = await imagesDao.getImageById(iid);
    if (existing == null) {
      return jsonNotFound({'error': 'Image not found: $iid'});
    }

    if (payload.containsKey('filePath')) {
      await imagesDao.updateImageFilePath(
        iid,
        requireString(payload, 'filePath'),
      );
    }

    if (payload.containsKey('isAccepted') &&
        payload['isAccepted'] == false) {
      await imagesDao.rejectImage(
        iid,
        optionalString(payload, 'rejectionReason') ?? 'rejected',
      );
    }

    if (payload.containsKey('isPlateSolved') && payload['isPlateSolved'] == true) {
      await imagesDao.updatePlateSolveResult(
        iid,
        solvedRa: requireDouble(payload, 'solvedRa'),
        solvedDec: requireDouble(payload, 'solvedDec'),
        solvedRotation: requireDouble(payload, 'solvedRotation'),
        solvedPixelScale: requireDouble(payload, 'solvedPixelScale'),
      );
    }

    if (payload.containsKey('producingNodeId') ||
        payload.containsKey('producingRunId') ||
        payload.containsKey('runtimeGrade') ||
        payload.containsKey('eccentricity')) {
      await imagesDao.stampProducingNode(
        imageId: iid,
        producingNodeId: optionalString(payload, 'producingNodeId'),
        producingRunId: optionalString(payload, 'producingRunId'),
        runtimeGrade: optionalString(payload, 'runtimeGrade'),
        eccentricity: optionalDouble(payload, 'eccentricity'),
      );
    }

    publishHostMutationFromContainer(
      container,
      entityType: HostMutationEntity.capturedImage,
      action: HostMutationAction.updated,
      entityId: iid.toString(),
    );
    return jsonOk({'status': 'updated'});
  }

  /// Legacy `/api/images/recent?limit=<n>` for mobile clients that pre-date
  /// the unified `/api/images` route. Why kept: existing pinned mobile builds
  /// hit this URL and we cannot push an update to all installed clients
  /// before the v2.5 release. Returns the same shape the GUI web_server used
  /// (`images` + `count`) so the mobile UI tile counters keep working.
  Future<Response> handleGetRecentImages(Request request) async {
    _logInfo('[API] GET /api/images/recent');
    final limitParam = request.url.queryParameters['limit'];
    final database = container.read(databaseProvider);
    if (limitParam != null) {
      final limit = int.tryParse(limitParam);
      if (limit == null || limit <= 0) {
        throw BadRequestError(
          field: 'limit',
          expected: 'positive integer',
          message: 'limit query parameter must be a positive integer',
        );
      }
      final images = await database.imagesDao
          .getAllImagesPaginated(limit: limit, offset: 0);
      final imagesJson = images.map((image) => image.toJson()).toList();
      return jsonOk({'images': imagesJson, 'count': imagesJson.length});
    }
    final images = await database.imagesDao.getAllImages();
    final imagesJson = images.map((image) => image.toJson()).toList();
    return jsonOk({'images': imagesJson, 'count': imagesJson.length});
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

  /// P1-13: Sidecar-backed thumbnail with ETag caching.
  ///
  /// The capture pipeline writes a `{filePath}.thumb.jpg` next to every
  /// FITS at insert time (best-effort, fire-and-forget). This handler
  /// serves that sidecar with strong-validator ETag headers so repeat
  /// gallery loads from a mobile client hit a `304 Not Modified` instead
  /// of redoing the FITS â†’ JPEG encode.
  ///
  /// Cold-read fallback: when the sidecar is missing (legacy row, or the
  /// fire-and-forget write hasn't landed yet), we synthesise the JPEG via
  /// the FFI path AND persist the result as a sidecar so the next call
  /// is fast. This is the self-healing branch.
  ///
  /// Limitation (documented for ops): if the operator replaces a FITS
  /// out-of-band (e.g. a re-stretched copy), the sidecar's mtime is no
  /// longer a true validator. The `POST /api/images/{id}/regenerate-
  /// thumbnail` endpoint is the escape hatch â€” it forces a re-encode and
  /// rewrites the sidecar so the ETag changes.
  Future<Response> handleGetImageThumbnail(
      Request request, String imageId) async {
    final iid = _parsePathId(imageId, 'imageId');
    final database = container.read(databaseProvider);
    final dbImage = await database.imagesDao.getImageById(iid);
    if (dbImage == null) {
      return jsonNotFound({'error': 'Image not found: $iid'});
    }

    // Ensure the source FITS still exists before any FFI fallback. We do
    // this even when the sidecar is present so a deleted source FITS
    // surfaces as 404 consistently (the sidecar is auxiliary; if the
    // underlying FITS is gone the image entity is effectively
    // un-viewable for science purposes).
    final sourceFile = File(dbImage.filePath);
    if (!await sourceFile.exists()) {
      return jsonNotFound(
          {'error': 'Image file not found: ${dbImage.filePath}'});
    }

    final sidecarPath = await database.imagesDao.getThumbnailPath(iid);
    final canonicalSidecarPath = sidecarPath != null && sidecarPath.isNotEmpty
        ? sidecarPath
        : '${dbImage.filePath}.thumb.jpg';
    final sidecarFile = File(canonicalSidecarPath);

    if (await sidecarFile.exists()) {
      return _serveSidecarFromDisk(
        request: request,
        imageId: iid,
        sidecarFile: sidecarFile,
        dbImage: dbImage,
      );
    }

    // Cold-read fallback: no sidecar on disk. Generate via the FFI path
    // then persist for next time. The DB-row's stamped `thumbnail_path`
    // is also updated (or cleared if generation failed).
    final sidecarService = container.read(thumbnailSidecarServiceProvider);
    final writeResult = await sidecarService.writeSidecarForRow(
      imageId: iid,
      fitsPath: dbImage.filePath,
      imagesDao: database.imagesDao,
    );

    switch (writeResult) {
      case SidecarWritten(:final sidecarFile):
        return _serveSidecarFromDisk(
          request: request,
          imageId: iid,
          sidecarFile: sidecarFile,
          dbImage: dbImage,
        );
      case SidecarSkipped(:final reason):
        // The service already logged this; surface to caller as 404.
        return jsonNotFound({
          'error': 'Thumbnail unavailable',
          'reason': reason,
        });
      case SidecarFailed(:final error):
        _logger.warning(
          'handleGetImageThumbnail: FFI thumbnail generation failed for '
          'image $iid (${dbImage.filePath}): $error',
          source: 'SessionHandlers',
        );
        return jsonInternalServerError({
          'error': 'Failed to generate thumbnail',
          'detail': error.toString(),
        });
    }
  }

  /// Serve a sidecar JPEG with strong ETag + caching headers. Honors
  /// `If-None-Match` for 304 responses.
  Future<Response> _serveSidecarFromDisk({
    required Request request,
    required int imageId,
    required File sidecarFile,
    required DbCapturedImage dbImage,
  }) async {
    final int sidecarLength;
    final DateTime sidecarMtime;
    try {
      sidecarLength = await sidecarFile.length();
      sidecarMtime = await sidecarFile.lastModified();
    } on FileSystemException catch (e) {
      _logger.warning(
        'Failed to stat sidecar for image $imageId at ${sidecarFile.path}: '
        '$e',
        source: 'SessionHandlers',
      );
      return jsonInternalServerError({
        'error': 'Failed to read sidecar metadata',
        // Sanitized: full cause is logged above; not leaked to the caller.
        'detail': 'See server logs for diagnostics.',
      });
    }

    // Strong validator. mtime in ms is the highest portable resolution we
    // get from Dart's File API. Once a sidecar is written its content is
    // effectively immutable (only regenerate-thumbnail rewrites it, which
    // bumps mtime), so the ETag uniquely identifies the bytes.
    final etag = '"$imageId-${sidecarMtime.millisecondsSinceEpoch}"';
    final ifNoneMatch = request.headers['if-none-match'];
    if (ifNoneMatch != null && ifNoneMatch == etag) {
      return Response.notModified(headers: {
        'etag': etag,
        'cache-control': 'private, max-age=86400, immutable',
      });
    }

    final bytes = await sidecarFile.readAsBytes();
    final metaHeader = _buildImageMetaHeader(dbImage, bytes);
    return contentResponse(
      bytes,
      contentType: 'image/jpeg',
      contentLength: sidecarLength,
      headers: {
        'etag': etag,
        'cache-control': 'private, max-age=86400, immutable',
        'x-image-meta': metaHeader,
      },
    );
  }

  /// Build a base64-encoded JSON payload mirroring the live-view
  /// `x-image-meta` schema (`display_buffer_jpeg.dart`). Pulled from the
  /// DB row rather than re-stretching the FITS, because the gallery
  /// thumbnail consumer only needs the lightweight stats (HFR, star
  /// count, exposure) rather than the full histogram.
  String _buildImageMetaHeader(DbCapturedImage row, Uint8List bytes) {
    final meta = <String, Object?>{
      'imageId': row.id,
      'fileName': row.fileName,
      'frameType': row.frameType,
      'exposureTime': row.exposureDuration,
      'filter': row.filter,
      'hfr': row.hfr,
      'starCount': row.starCount,
      'isAccepted': row.isAccepted,
      'capturedAt': row.capturedAt.millisecondsSinceEpoch,
      'sidecarBytes': bytes.length,
    };
    return base64Encode(utf8.encode(jsonEncode(meta)));
  }

  /// P1-13: Force regeneration of the sidecar from the current FITS bytes.
  /// Used by operators when an out-of-band FITS replacement has stale-d
  /// the cached sidecar (the only condition under which the otherwise-
  /// immutable cache becomes incorrect).
  Future<Response> handleRegenerateImageThumbnail(
      Request request, String imageId) async {
    _logInfo('[API] POST /api/images/$imageId/regenerate-thumbnail');
    final iid = _parsePathId(imageId, 'imageId');
    final database = container.read(databaseProvider);
    final dbImage = await database.imagesDao.getImageById(iid);
    if (dbImage == null) {
      return jsonNotFound({'error': 'Image not found: $iid'});
    }
    final source = File(dbImage.filePath);
    if (!await source.exists()) {
      return jsonNotFound(
          {'error': 'Image file not found: ${dbImage.filePath}'});
    }

    final sidecarService = container.read(thumbnailSidecarServiceProvider);
    final result = await sidecarService.writeSidecarForRow(
      imageId: iid,
      fitsPath: dbImage.filePath,
      imagesDao: database.imagesDao,
    );

    switch (result) {
      case SidecarWritten(
          :final sidecarFile,
          :final byteCount,
          :final mtime
        ):
        publishHostMutationFromContainer(
          container,
          entityType: HostMutationEntity.capturedImage,
          action: HostMutationAction.updated,
          entityId: iid.toString(),
        );
        return jsonOk({
          'status': 'regenerated',
          'sidecarPath': sidecarFile.path,
          'byteCount': byteCount,
          'mtime': mtime.toUtc().toIso8601String(),
        });
      case SidecarSkipped(:final reason):
        return jsonNotFound({
          'error': 'Could not regenerate thumbnail',
          'reason': reason,
        });
      case SidecarFailed(:final error):
        return jsonInternalServerError({
          'error': 'Failed to regenerate thumbnail',
          'detail': error.toString(),
        });
    }
  }

  /// P1-13: Backfill thumbnail sidecars for legacy images.
  ///
  /// Returns `{jobId}` immediately. The background job walks every row in
  /// `captured_images` and (a) skips rows whose source FITS is missing
  /// (counted as `skipped`), (b) skips rows whose sidecar already exists
  /// on disk (counted as `already_present`), (c) regenerates the sidecar
  /// for everything else.
  ///
  /// Cancellable via `POST /api/jobs/{jobId}/cancel`. Emits `JobProgress`
  /// events with `{current, total, currentFile}` rate-limited to ~1Hz so
  /// the SSE stream doesn't drown a phone's UI.
  Future<Response> handleBackfillThumbnails(Request request) async {
    _logInfo('[API] POST /api/images/backfill-thumbnails');
    final mgr = jobManager;
    if (mgr == null) {
      // The job manager is constructed by the headless server and wired
      // into SessionHandlers when present. A missing manager means the
      // server was bootstrapped without job support â€” surface a 503 so
      // the operator/client knows to retry against a properly-configured
      // build rather than silently sidestepping cancellation/progress.
      return jsonServiceUnavailable({
        'error': 'Job manager not available',
        'detail': 'Backfill requires the headless job manager.',
      });
    }
    final job = mgr.start(
      operation: 'image.backfill-thumbnails',
      deviceId: null,
      work: (sink, cancellation) async {
        final database = container.read(databaseProvider);
        final sidecarService =
            container.read(thumbnailSidecarServiceProvider);
        final rows =
            await database.imagesDao.listImagesForThumbnailBackfill();

        final total = rows.length;
        sink.update(0.0, 'Scanning $total images');

        int processed = 0;
        int written = 0;
        int alreadyPresent = 0;
        int skippedMissingSource = 0;
        int failed = 0;
        DateTime lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

        for (final row in rows) {
          if (cancellation.isCancelled) {
            throw const JobCancelledException('backfill cancelled');
          }
          processed++;

          // Decide whether the row already has a usable sidecar. We
          // honour any stamped path first; if missing we fall back to
          // the canonical `${filePath}.thumb.jpg` location.
          final stampedSidecar = row.thumbnailPath;
          final canonical = row.filePath.isEmpty
              ? null
              : '${row.filePath}.thumb.jpg';
          final candidatePath = (stampedSidecar != null &&
                  stampedSidecar.isNotEmpty)
              ? stampedSidecar
              : canonical;

          if (candidatePath != null &&
              await File(candidatePath).exists()) {
            // Already-present sidecar â€” make sure the DB stamp matches
            // the on-disk location so subsequent GETs hit it directly.
            if (stampedSidecar != candidatePath) {
              await database.imagesDao
                  .setThumbnailPath(row.id, candidatePath);
            }
            alreadyPresent++;
          } else if (row.filePath.isEmpty) {
            skippedMissingSource++;
          } else if (!await File(row.filePath).exists()) {
            skippedMissingSource++;
            // Stamp clear so the GET handler doesn't waste a FFI call
            // on a row whose source is gone.
            await database.imagesDao.setThumbnailPath(row.id, null);
          } else {
            final result = await sidecarService.writeSidecarForRow(
              imageId: row.id,
              fitsPath: row.filePath,
              imagesDao: database.imagesDao,
            );
            switch (result) {
              case SidecarWritten():
                written++;
              case SidecarSkipped():
                skippedMissingSource++;
              case SidecarFailed():
                failed++;
            }
          }

          // Rate-limit progress emission to ~1 Hz so a session with
          // tens of thousands of rows doesn't flood the SSE stream.
          // Always emit the first and the final tick regardless.
          final now = DateTime.now();
          final timeSinceLast = now.difference(lastEmit);
          if (processed == 1 ||
              processed == total ||
              timeSinceLast >= const Duration(milliseconds: 1000)) {
            sink.update(
              total == 0 ? 1.0 : processed / total,
              'Processed $processed of $total â€” ${row.filePath}',
            );
            lastEmit = now;
          }
        }

        return {
          'total': total,
          'written': written,
          'alreadyPresent': alreadyPresent,
          'skipped': skippedMissingSource,
          'failed': failed,
        };
      },
    );
    return jsonOk({
      'jobId': job.jobId,
      'status': job.state.wireName,
      'operation': job.operation,
    });
  }

  /// P0-5 â€” FITS download with HTTP Range support (RFC 7233).
  ///
  /// Mobile clients on flaky cellular need partial-content resumption;
  /// a 30 MB FITS that dropped at byte 27 MB was previously unrecoverable
  /// because the server only served full bodies. We now parse the
  /// `Range` request header and emit:
  ///   * 200 OK + `accept-ranges: bytes` when no Range header is sent.
  ///   * 206 Partial Content + `content-range` for valid Range requests.
  ///   * 416 Requested Range Not Satisfiable for malformed/unsatisfiable
  ///     specs.
  /// An `etag` of `"<imageId>-<mtime-ms>"` lets the client validate the
  /// resource hasn't changed between resume attempts via `If-Range`.
  /// Multi-range (`bytes=0-499,1000-1499`) is explicitly rejected with
  /// 416 â€” out of scope per P0-5.
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

    // Stat the file. A permission-denied here is a 403; a generic I/O
    // error is a 500. We deliberately surface these rather than letting
    // the middleware turn everything into a 500 (CLAUDE.md: "errors are
    // a feature" â€” distinguish real failure modes).
    final int fileLength;
    final DateTime mtime;
    try {
      fileLength = await file.length();
      mtime = await file.lastModified();
    } on PathAccessException catch (e) {
      _logger.warning(
        'Permission denied reading $imageId: $e',
        source: 'SessionHandlers',
      );
      return jsonForbidden(
          {'error': 'Permission denied', 'path': dbImage.filePath});
    } on FileSystemException catch (e) {
      _logger.error(
        'Failed to stat $imageId: $e',
        source: 'SessionHandlers',
      );
      return jsonInternalServerError(const {
        'error': 'Failed to read file metadata',
        // Sanitized: full cause is logged above; not leaked to the caller.
        'detail': 'See server logs for diagnostics.',
      });
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

    // Build the etag from image id + on-disk mtime (in ms, the highest
    // resolution we can portably get from Dart's File API). This lets
    // a resuming client send `If-Range: "<etag>"` and we'll either
    // honour the range or fall back to a full body if the file changed.
    final etag = '"$iid-${mtime.millisecondsSinceEpoch}"';

    final rangeHeader = request.headers['range'];
    final ifRange = request.headers['if-range'];

    // If the caller passes If-Range but it doesn't match our current
    // etag, RFC 7233 Â§3.2 says we MUST ignore the Range header and
    // return the full body. Strong-validator semantics (etag must match
    // exactly, weak etags like `W/"..."` are deliberately not generated
    // here so we don't have to handle weak matching).
    final ifRangeMatches = ifRange == null || ifRange == etag;
    final shouldHonourRange = rangeHeader != null && ifRangeMatches;

    if (!shouldHonourRange) {
      // 200 full body. We always advertise accept-ranges so clients
      // know to use Range on the next attempt.
      return attachmentResponse(
        file.openRead(),
        fileName: dbImage.fileName,
        contentType: contentType,
        contentLength: fileLength,
        headers: {
          'accept-ranges': 'bytes',
          'etag': etag,
        },
      );
    }

    // Range header is present. Parse it; any failure is a 416.
    final int rangeStart;
    final int rangeEnd;
    try {
      final parsed = parseRangeHeader(rangeHeader, fileLength);
      rangeStart = parsed.start;
      rangeEnd = parsed.end;
    } on FormatException catch (e) {
      _logger.info(
        'Invalid range header "$rangeHeader" for image $iid: ${e.message}',
        source: 'SessionHandlers',
      );
      return rangeNotSatisfiableResponse(fileLength, reason: e.message);
    }

    // File.openRead's `end` parameter is exclusive; the Range header
    // bounds are inclusive â€” convert here.
    final body = file.openRead(rangeStart, rangeEnd + 1);
    return partialContentResponse(
      body,
      start: rangeStart,
      end: rangeEnd,
      totalLength: fileLength,
      contentType: contentType,
      fileName: dbImage.fileName,
      headers: {'etag': etag},
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
      return jsonNotFound({'error': 'Export not found for session $sessionId'});
    }

    final fileLength = await file.length();
    return attachmentResponse(
      file.openRead(),
      fileName: file.uri.pathSegments.last,
      contentType: contentType,
      contentLength: fileLength,
    );
  }

  Map<String, dynamic> _producingThumbnailToJson(ProducingNodeThumbnail thumb) {
    return {
      'id': thumb.id,
      'filePath': thumb.filePath,
      'fileName': thumb.fileName,
      'fileFormat': 'fits',
      'fileSize': null,
      'sessionId': null,
      'targetId': null,
      'frameType': thumb.frameType,
      'exposureDuration': thumb.exposureDuration,
      'gain': null,
      'offset': null,
      'binX': 1,
      'binY': 1,
      'filter': thumb.filter,
      'sensorTemp': null,
      'coolerPower': null,
      'hfr': thumb.hfr,
      'starCount': thumb.starCount,
      'background': null,
      'noise': null,
      'qualityScore': null,
      'guidingRmsRa': null,
      'guidingRmsDec': null,
      'guidingRmsTotal': null,
      'mountRa': null,
      'mountDec': null,
      'mountAltitude': null,
      'mountAzimuth': null,
      'pierSide': null,
      'focuserPosition': null,
      'focuserTemp': null,
      'rotatorAngle': null,
      'isPlateSolved': false,
      'solvedRa': null,
      'solvedDec': null,
      'solvedRotation': null,
      'solvedPixelScale': null,
      'capturedAt': thumb.capturedAt.millisecondsSinceEpoch,
      'createdAt': thumb.capturedAt.millisecondsSinceEpoch,
      'isAccepted': thumb.isAccepted,
      'rejectionReason': thumb.rejectionReason,
      'producingNodeId': thumb.producingNodeId,
      'producingRunId': thumb.producingRunId,
      'runtimeGrade': thumb.runtimeGrade,
      'eccentricity': thumb.eccentricity,
    };
  }
}
