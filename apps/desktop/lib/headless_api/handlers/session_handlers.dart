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

part 'session_handlers/thumbnail_handlers.dart';

/// Handlers for polar alignment and session/image endpoints
class SessionHandlers {
  final ProviderContainer container;

  /// optional job manager. When wired, polar-alignment
  /// endpoints return `{jobId, status: queued}` immediately. The actual
  /// alignment routine streams progress via WS events.
  final JobManager? jobManager;

  SessionHandlers(this.container, {this.jobManager});

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
    final acceptanceThresholdArcsec = requireDouble(
      payload,
      'acceptance_threshold_arcsec',
    );
    final iterationCadenceSecs = requireDouble(
      payload,
      'iteration_cadence_secs',
    );
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
    Request request,
    String sessionId,
  ) async {
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
      return jsonOk({'images': thumbs.map(_producingThumbnailToJson).toList()});
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
      return jsonOk({'images': images.map((image) => image.toJson()).toList()});
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

    // #2 — honour fileSize from the payload if supplied; otherwise
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
        // The file exists check passed but length() still failed —
        // unusual enough to log so the operator knows the row went in
        // without a size.
        _logger.warning(
          'handleCreateImage: failed to stat $postedPath: $e — row will '
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
        isPlateSolved: Value(optionalBool(payload, 'isPlateSolved') ?? false),
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

    // schedule fire-and-forget sidecar generation for the new row.
    // Skips when filePath is empty (no FITS to encode) or the file isn't
    // on disk — the service logs both cases at warning severity. The
    // capture is fully recorded by this point so a sidecar failure does
    // not impact the response.
    if (postedPath.isNotEmpty) {
      try {
        final sidecarService = container.read(thumbnailSidecarServiceProvider);
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

    if (payload.containsKey('isAccepted') && payload['isAccepted'] == false) {
      await imagesDao.rejectImage(
        iid,
        optionalString(payload, 'rejectionReason') ?? 'rejected',
      );
    }

    if (payload.containsKey('isPlateSolved') &&
        payload['isPlateSolved'] == true) {
      // Route through the repository (NOT the DAO directly) so the solve-persist
      // event fires onSolvedFrameFold — the appliance is the authoritative atlas
      // host, so a solve arriving via the headless API must fold into Your Sky
      // and run the First Light difference scan, exactly like the desktop path.
      // Accept + persist the full CD matrix + SIP so the fold and difference scan
      // use the real distortion rather than CD-from-scale geometry.
      final cd11 = optionalDouble(payload, 'solvedCd1_1');
      final cd12 = optionalDouble(payload, 'solvedCd1_2');
      final cd21 = optionalDouble(payload, 'solvedCd2_1');
      final cd22 = optionalDouble(payload, 'solvedCd2_2');
      await container
          .read(imagingRecordsRepositoryProvider)
          .updatePlateSolveResult(
            iid,
            solvedRa: requireDouble(payload, 'solvedRa'),
            solvedDec: requireDouble(payload, 'solvedDec'),
            solvedRotation: requireDouble(payload, 'solvedRotation'),
            solvedPixelScale: requireDouble(payload, 'solvedPixelScale'),
            solvedCd1_1: cd11,
            solvedCd1_2: cd12,
            solvedCd2_1: cd21,
            solvedCd2_2: cd22,
            solvedSip: optionalString(payload, 'solvedSip'),
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
      final images = await database.imagesDao.getAllImagesPaginated(
        limit: limit,
        offset: 0,
      );
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
    return jsonOk({
      'images': standalone.map((image) => image.toJson()).toList(),
    });
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

  /// Sidecar-backed thumbnail with ETag caching.
  ///
  /// The capture pipeline writes a `{filePath}.thumb.jpg` next to every
  /// FITS at insert time (best-effort, fire-and-forget). This handler
  /// serves that sidecar with strong-validator ETag headers so repeat
  /// gallery loads from a mobile client hit a `304 Not Modified` instead
  /// of redoing the FITS → JPEG encode.
  ///
  /// Cold-read fallback: when the sidecar is missing (legacy row, or the
  /// fire-and-forget write hasn't landed yet), we synthesise the JPEG via
  /// the FFI path AND persist the result as a sidecar so the next call
  /// is fast. This is the self-healing branch.
  ///
  /// Limitation (documented for ops): if the operator replaces a FITS
  /// out-of-band (e.g. a re-stretched copy), the sidecar's mtime is no
  /// longer a true validator. The `POST /api/images/{id}/regenerate-
  /// thumbnail` endpoint is the escape hatch — it forces a re-encode and
  /// rewrites the sidecar so the ETag changes.
  Future<Response> _exportSessionFile(
    Request request,
    String sessionId, {
    required String fileType,
    required Future<String> Function(
      SessionExportService service,
      int sessionId,
    )
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
