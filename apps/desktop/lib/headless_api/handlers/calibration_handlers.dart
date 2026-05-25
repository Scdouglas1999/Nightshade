// P1-10 — Remote calibration library management.
//
// Exposes CRUD + upload endpoints for the three calibration data stores
// (dark_library, flat_history, defect_maps) that previously had no
// REST surface. Operators running a headless Pi/embedded host can now
// manage their calibration library from a remote client without SSH.
//
// Endpoints (all under /api/calibration):
//
//   Dark library:
//     GET  /api/calibration/darks                    — list (filters)
//     GET  /api/calibration/darks/<id>               — single
//     POST /api/calibration/darks                    — register by path
//     POST /api/calibration/darks/upload             — multipart upload
//     GET  /api/calibration/darks/<id>/download      — stream FITS (Range)
//     DELETE /api/calibration/darks/<id>             — delete row (file?)
//     POST /api/calibration/darks/find-match         — best dark for params
//     POST /api/calibration/darks/backfill-sizes     — verify on-disk state
//
//   Flat history:
//     GET  /api/calibration/flats                    — list (filters)
//     GET  /api/calibration/flats/<id>               — single
//     POST /api/calibration/flats                    — record entry
//     DELETE /api/calibration/flats/<id>             — delete row
//     GET  /api/calibration/flats/recommendation     — exposure suggestion
//
//   Defect maps:
//     GET  /api/calibration/defect-maps              — list (no BLOB)
//     GET  /api/calibration/defect-maps/<id>         — single (binary|json)
//     POST /api/calibration/defect-maps              — register row
//     DELETE /api/calibration/defect-maps/<id>       — delete row (file?)
//     POST /api/calibration/defect-maps/<id>/regenerate — recompute from FITS

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../route_metadata.dart' show backupUploadMaxRequestBodyBytes;
import '../validation.dart';

/// P1-10 — calibration library handlers.
class CalibrationHandlers {
  /// Same 256 MB cap as the backup-upload path. A dark master frame from a
  /// modern full-frame camera is typically 100–200 MB so this is a snug
  /// upper bound that still rejects accidental large-blob uploads.
  static const int _maxDarkUploadBytes = backupUploadMaxRequestBodyBytes;

  /// Default limit on listing endpoints. Picked to fit comfortably in a
  /// single response payload — 100 rows is roughly 20 KB of JSON, well
  /// under the typical 1 MB mobile read budget.
  static const int _defaultListLimit = 100;
  static const int _maxListLimit = 500;

  final ProviderContainer container;

  /// Override the data-root resolution. Used by tests so we don't depend on
  /// `path_provider` being wired up in the widget-test binding.
  final Future<Directory> Function()? dataDirectoryOverride;

  CalibrationHandlers(this.container, {this.dataDirectoryOverride});

  LoggingService get _logger => container.read(loggingServiceProvider);
  NightshadeDatabase get _database => container.read(databaseProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'CalibrationHandlers');
  void _logWarning(String message) =>
      _logger.warning(message, source: 'CalibrationHandlers');

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

  /// Resolve the calibration directory ($DATA_DIR/calibration/darks).
  /// Created on first use. Honors `NIGHTSHADE_DATA_DIR` (see
  /// `desktop_logging_init.dart`) so headless deployments under custom
  /// paths land in the right place.
  Future<Directory> _calibrationDarksDir() async {
    final dataDir = await _resolveDataDirectory();
    final dir = Directory(p.join(dataDir.path, 'calibration', 'darks'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _resolveDataDirectory() async {
    if (dataDirectoryOverride != null) {
      return dataDirectoryOverride!();
    }
    final envOverride =
        Platform.environment['NIGHTSHADE_DATA_DIR']?.trim();
    if (envOverride != null && envOverride.isNotEmpty) {
      return Directory(envOverride);
    }
    return getApplicationSupportDirectory();
  }

  // ===========================================================================
  // Dark library
  // ===========================================================================

  /// GET /api/calibration/darks
  Future<Response> handleListDarks(Request request) async {
    _logInfo('[API] GET /api/calibration/darks');
    final params = request.url.queryParameters;

    final exposureSeconds = _parseDoubleParam(params, 'exposureSeconds');
    final temperatureC = _parseDoubleParam(params, 'temperatureC');
    final gain = _parseIntParam(params, 'gain');
    final limit = _parseListLimit(params);

    final entries = await _database.darkLibraryDao.listFiltered(
      exposureSeconds: exposureSeconds,
      gain: gain,
      temperatureCelsius: temperatureC,
      limit: limit,
    );

    final json = <Map<String, dynamic>>[];
    for (final entry in entries) {
      json.add(await _darkEntryToWire(entry));
    }
    return jsonOk({'darks': json, 'count': json.length});
  }

  /// GET /api/calibration/darks/{id}
  Future<Response> handleGetDark(Request request, String id) async {
    _logInfo('[API] GET /api/calibration/darks/$id');
    final iid = _parsePathId(id, 'id');
    final entry = await _database.darkLibraryDao.getEntryById(iid);
    if (entry == null) {
      return jsonNotFound({
        'error': 'dark_not_found',
        'message': 'No dark library entry with id $iid',
      });
    }
    return jsonOk({'dark': await _darkEntryToWire(entry)});
  }

  /// POST /api/calibration/darks  — register an existing file by path.
  Future<Response> handleRegisterDark(Request request) async {
    _logInfo('[API] POST /api/calibration/darks');
    final payload = await readJsonObject(request);

    final filePath = requireString(payload, 'filePath');
    final exposureDuration =
        requireDouble(payload, 'exposureDuration', min: 0);
    final gain = optionalInt(payload, 'gain') ?? 0;
    final offset = optionalInt(payload, 'offset') ?? 0;
    final binX = optionalInt(payload, 'binX', min: 1) ?? 1;
    final binY = optionalInt(payload, 'binY', min: 1) ?? 1;
    final sensorTempC = optionalDouble(payload, 'sensorTempC');
    final frameType = optionalString(payload, 'frameType') ?? 'dark';
    final frameCount = optionalInt(payload, 'frameCount');
    final masterPath = optionalString(payload, 'masterPath');
    final width = optionalInt(payload, 'width');
    final height = optionalInt(payload, 'height');

    if (frameType != 'dark' && frameType != 'bias') {
      throw BadRequestError(
        field: 'frameType',
        expected: '"dark" or "bias"',
        message: 'frameType must be "dark" or "bias", got "$frameType"',
      );
    }

    final file = File(filePath);
    if (!await file.exists()) {
      return jsonBadRequest({
        'error': 'dark_file_not_found',
        'message': 'No file exists at $filePath',
        'filePath': filePath,
      });
    }

    final companion = DarkLibraryCompanion.insert(
      filePath: filePath,
      exposureTime: exposureDuration,
      temperature: Value(sensorTempC),
      gain: Value(gain),
      offset: Value(offset),
      binX: Value(binX),
      binY: Value(binY),
      frameType: Value(frameType),
      width: Value(width),
      height: Value(height),
      masterDarkPath: Value(masterPath),
      masterFrameCount: Value(frameCount),
    );

    final id = await _database.darkLibraryDao.addEntry(companion);
    final entry = await _database.darkLibraryDao.getEntryById(id);
    if (entry == null) {
      // Should not happen — we just inserted, but treat as a HandlerFailure
      // so the operator sees a structured error rather than a generic 500.
      throw HandlerFailure(
        code: 'dark_register_failed',
        message: 'Failed to read back newly-created dark library entry',
      );
    }
    return jsonCreated({'dark': await _darkEntryToWire(entry)});
  }

  /// POST /api/calibration/darks/upload — multipart-ish (FITS body + JSON
  /// metadata in query params).
  ///
  /// We deliberately don't pull a full MIME multipart parser into the
  /// dependency closure (the `shelf` ecosystem has no canonical multipart
  /// helper at our minor version). Instead we accept the binary FITS as
  /// the raw request body and the metadata as JSON-encoded query
  /// parameters in a `meta` field. This matches the existing
  /// `/api/imaging/save-fits` flow.
  Future<Response> handleUploadDark(Request request) async {
    _logInfo('[API] POST /api/calibration/darks/upload');

    final contentLength =
        int.tryParse(request.headers['content-length'] ?? '');
    if (contentLength != null && contentLength > _maxDarkUploadBytes) {
      return jsonTooLarge({
        'error': 'dark_upload_too_large',
        'maxBytes': _maxDarkUploadBytes,
      });
    }

    final metaParam = request.url.queryParameters['meta'];
    if (metaParam == null || metaParam.isEmpty) {
      throw BadRequestError(
        field: 'meta',
        expected: 'url-encoded JSON object',
        message:
            'POST /api/calibration/darks/upload requires a `meta` query '
            'parameter containing the JSON dark metadata',
      );
    }
    Map<String, dynamic> meta;
    try {
      final decoded = jsonDecode(metaParam);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('meta is not a JSON object');
      }
      meta = decoded;
    } on FormatException catch (e) {
      throw BadRequestError(
        field: 'meta',
        expected: 'url-encoded JSON object',
        message: 'Failed to parse `meta` query parameter: ${e.message}',
      );
    }

    final exposureDuration = requireDouble(meta, 'exposureDuration', min: 0);
    final sensorTempC = optionalDouble(meta, 'sensorTempC');
    final gain = optionalInt(meta, 'gain') ?? 0;
    final offset = optionalInt(meta, 'offset') ?? 0;
    final binX = optionalInt(meta, 'binX', min: 1) ?? 1;
    final binY = optionalInt(meta, 'binY', min: 1) ?? 1;
    final frameType = optionalString(meta, 'frameType') ?? 'dark';
    final width = optionalInt(meta, 'width');
    final height = optionalInt(meta, 'height');
    final frameCount = optionalInt(meta, 'frameCount');

    if (frameType != 'dark' && frameType != 'bias') {
      throw BadRequestError(
        field: 'frameType',
        expected: '"dark" or "bias"',
        message: 'frameType must be "dark" or "bias", got "$frameType"',
      );
    }

    final requestedName =
        request.url.queryParameters['fileName'] ?? 'upload.fits';
    final sanitized = _sanitizeDarkFileName(requestedName);
    if (sanitized == null) {
      return jsonBadRequest({
        'error': 'invalid_filename',
        'message':
            'Filename must end in .fits, .fit, or .xisf and contain no '
                'path separators',
      });
    }

    final dir = await _calibrationDarksDir();
    final destination = await _resolveUniquePath(dir, sanitized);

    // Stream the body straight to disk; we track size as we go so a body
    // that lies about its Content-Length still gets truncated.
    final sink = destination.openWrite();
    int bytesWritten = 0;
    bool oversized = false;
    try {
      await for (final chunk in request.read()) {
        bytesWritten += chunk.length;
        if (bytesWritten > _maxDarkUploadBytes) {
          oversized = true;
          break;
        }
        sink.add(chunk);
      }
    } finally {
      await sink.flush();
      await sink.close();
    }

    if (oversized) {
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
      } catch (e) {
        _logWarning(
          'Failed to remove oversized dark upload at '
          '${destination.path}: $e',
        );
      }
      return jsonTooLarge({
        'error': 'dark_upload_too_large',
        'maxBytes': _maxDarkUploadBytes,
      });
    }

    if (bytesWritten == 0) {
      try {
        if (await destination.exists()) {
          await destination.delete();
        }
      } catch (_) {}
      throw BadRequestError(
        field: 'body',
        expected: 'FITS payload',
        message: 'Upload body was empty',
      );
    }

    final companion = DarkLibraryCompanion.insert(
      filePath: destination.path,
      exposureTime: exposureDuration,
      temperature: Value(sensorTempC),
      gain: Value(gain),
      offset: Value(offset),
      binX: Value(binX),
      binY: Value(binY),
      frameType: Value(frameType),
      width: Value(width),
      height: Value(height),
      masterFrameCount: Value(frameCount),
    );

    final id = await _database.darkLibraryDao.addEntry(companion);
    final entry = await _database.darkLibraryDao.getEntryById(id);
    if (entry == null) {
      throw HandlerFailure(
        code: 'dark_register_failed',
        message: 'Failed to read back newly-created dark library entry',
      );
    }
    return jsonCreated({
      'dark': await _darkEntryToWire(entry),
      'bytesWritten': bytesWritten,
    });
  }

  /// GET /api/calibration/darks/{id}/download — stream with Range support.
  Future<Response> handleDownloadDark(Request request, String id) async {
    _logInfo('[API] GET /api/calibration/darks/$id/download');
    final iid = _parsePathId(id, 'id');

    final entry = await _database.darkLibraryDao.getEntryById(iid);
    if (entry == null) {
      return jsonNotFound({
        'error': 'dark_not_found',
        'message': 'No dark library entry with id $iid',
      });
    }
    final file = File(entry.filePath);
    if (!await file.exists()) {
      return jsonNotFound({
        'error': 'dark_file_not_found',
        'message': 'On-disk file is missing for dark $iid',
        'filePath': entry.filePath,
      });
    }

    final int fileLength;
    final DateTime mtime;
    try {
      fileLength = await file.length();
      mtime = await file.lastModified();
    } on PathAccessException catch (e) {
      _logWarning('Permission denied reading dark $iid: $e');
      return jsonForbidden({
        'error': 'permission_denied',
        'path': entry.filePath,
      });
    } on FileSystemException catch (e) {
      return jsonInternalServerError({
        'error': 'stat_failed',
        'detail': e.message,
      });
    }

    final fileName = p.basename(entry.filePath);
    final lower = fileName.toLowerCase();
    String contentType;
    if (lower.endsWith('.fits') || lower.endsWith('.fit')) {
      contentType = 'application/fits';
    } else if (lower.endsWith('.xisf')) {
      contentType = 'application/x-xisf';
    } else {
      contentType = 'application/octet-stream';
    }

    final etag = '"dark-$iid-${mtime.millisecondsSinceEpoch}"';
    final rangeHeader = request.headers['range'];
    final ifRange = request.headers['if-range'];
    final ifRangeMatches = ifRange == null || ifRange == etag;
    final shouldHonourRange = rangeHeader != null && ifRangeMatches;

    if (!shouldHonourRange) {
      return attachmentResponse(
        file.openRead(),
        fileName: fileName,
        contentType: contentType,
        contentLength: fileLength,
        headers: {
          'accept-ranges': 'bytes',
          'etag': etag,
        },
      );
    }

    final int rangeStart;
    final int rangeEnd;
    try {
      final parsed = parseRangeHeader(rangeHeader, fileLength);
      rangeStart = parsed.start;
      rangeEnd = parsed.end;
    } on FormatException catch (e) {
      return rangeNotSatisfiableResponse(fileLength, reason: e.message);
    }

    return partialContentResponse(
      file.openRead(rangeStart, rangeEnd + 1),
      start: rangeStart,
      end: rangeEnd,
      totalLength: fileLength,
      contentType: contentType,
      fileName: fileName,
      headers: {'etag': etag},
    );
  }

  /// DELETE /api/calibration/darks/{id}?deleteFile=true
  Future<Response> handleDeleteDark(Request request, String id) async {
    _logInfo('[API] DELETE /api/calibration/darks/$id');
    final iid = _parsePathId(id, 'id');
    final deleteFile =
        request.url.queryParameters['deleteFile']?.toLowerCase() == 'true';

    final entry = await _database.darkLibraryDao.getEntryById(iid);
    if (entry == null) {
      return jsonNotFound({
        'error': 'dark_not_found',
        'message': 'No dark library entry with id $iid',
      });
    }

    bool fileDeleted = false;
    if (deleteFile) {
      try {
        final file = File(entry.filePath);
        if (await file.exists()) {
          await file.delete();
          fileDeleted = true;
        }
      } on PathAccessException catch (e) {
        _logWarning('Permission denied deleting dark $iid file: $e');
        return jsonForbidden({
          'error': 'permission_denied',
          'message': 'Could not delete on-disk dark file',
          'path': entry.filePath,
        });
      } on FileSystemException catch (e) {
        _logWarning('Failed to delete dark $iid file: ${e.message}');
        // The DB row still gets removed below; we surface the file-side
        // failure in the response so the caller can decide whether to
        // clean up manually.
        await _database.darkLibraryDao.deleteEntry(iid);
        return jsonOk({
          'deleted': true,
          'fileDeleted': false,
          'fileError': e.message,
        });
      }
    }

    final rowsAffected = await _database.darkLibraryDao.deleteEntry(iid);
    return jsonOk({
      'deleted': rowsAffected > 0,
      'fileDeleted': fileDeleted,
    });
  }

  /// POST /api/calibration/darks/find-match
  Future<Response> handleFindMatchingDark(Request request) async {
    _logInfo('[API] POST /api/calibration/darks/find-match');
    final payload = await readJsonObject(request);

    final exposureDuration =
        requireDouble(payload, 'exposureDuration', min: 0);
    final gain = optionalInt(payload, 'gain') ?? 0;
    final offset = optionalInt(payload, 'offset') ?? 0;
    final binX = optionalInt(payload, 'binX', min: 1) ?? 1;
    final binY = optionalInt(payload, 'binY', min: 1) ?? 1;
    final sensorTempC = optionalDouble(payload, 'sensorTempC');
    final frameType = optionalString(payload, 'frameType') ?? 'dark';

    DarkLibraryMatchTolerances tolerances =
        DarkLibraryMatchTolerances.defaults;
    final tolMap = optionalObject(payload, 'tolerances');
    if (tolMap != null) {
      final exposureRatio = optionalDouble(tolMap, 'exposureSecondsRatio');
      final exposureAbs = optionalDouble(tolMap, 'exposureSeconds');
      final temperatureTol = optionalDouble(tolMap, 'temperatureCelsius');
      double exposureSecs = tolerances.exposureSecs;
      if (exposureAbs != null) {
        exposureSecs = exposureAbs;
      } else if (exposureRatio != null) {
        exposureSecs = exposureDuration * exposureRatio;
      }
      tolerances = DarkLibraryMatchTolerances.validated(
        exposureSecs: exposureSecs,
        temperatureC: temperatureTol ?? tolerances.temperatureC,
      );
    }

    final match = await _database.darkLibraryDao.findBestMatch(
      exposureTime: exposureDuration,
      gain: gain,
      offset: offset,
      binX: binX,
      binY: binY,
      temperature: sensorTempC,
      tolerances: tolerances,
      frameType: frameType,
    );
    if (match == null) {
      return jsonNotFound({
        'error': 'no_matching_dark',
        'message':
            'No dark library entry matches the requested capture parameters',
      });
    }
    return jsonOk({'dark': await _darkEntryToWire(match)});
  }

  /// POST /api/calibration/darks/backfill-sizes
  ///
  /// Note: the `dark_library` schema has no `file_size` column, so this
  /// endpoint performs the closest equivalent — a verification pass that
  /// stats every row, returning counts of present/missing/error rows and
  /// the total on-disk byte usage. Mirrors the spirit of the
  /// `captured_images.fileSize` backfill (which DOES update a column).
  Future<Response> handleVerifyDarkSizes(Request request) async {
    _logInfo('[API] POST /api/calibration/darks/backfill-sizes');
    final stats = await _database.darkLibraryDao.verifyOnDiskState(
      logger: _logger,
    );
    return jsonOk({
      'verified': stats['total'],
      'present': stats['present'],
      'missing': stats['missing'],
      'errors': stats['errors'],
      'totalBytes': stats['totalBytes'],
      // For symmetry with /images backfill: no rows are mutated by this
      // endpoint (no file_size column on dark_library), so we surface zero
      // here so clients can use the same code path.
      'updated': 0,
      'skipped': stats['missing'],
    });
  }

  // ===========================================================================
  // Flat history
  // ===========================================================================

  /// GET /api/calibration/flats
  Future<Response> handleListFlats(Request request) async {
    _logInfo('[API] GET /api/calibration/flats');
    final params = request.url.queryParameters;

    final filter = params['filter'];
    final equipmentProfileId =
        _parseIntParam(params, 'equipmentProfileId');
    final gain = _parseIntParam(params, 'gain');
    final since = _parseDateParam(params, 'since');
    final limit = _parseListLimit(params);

    final entries = await _database.flatHistoryDao.listFiltered(
      filterName: filter,
      equipmentProfileId: equipmentProfileId,
      gain: gain,
      since: since,
      limit: limit,
    );

    final json = entries.map(_flatEntryToJson).toList(growable: false);
    return jsonOk({'flats': json, 'count': json.length});
  }

  /// GET /api/calibration/flats/{id}
  Future<Response> handleGetFlat(Request request, String id) async {
    final iid = _parsePathId(id, 'id');
    _logInfo('[API] GET /api/calibration/flats/$iid');
    final entry = await _database.flatHistoryDao.getById(iid);
    if (entry == null) {
      return jsonNotFound({
        'error': 'flat_not_found',
        'message': 'No flat history entry with id $iid',
      });
    }
    return jsonOk({'flat': _flatEntryToJson(entry)});
  }

  /// POST /api/calibration/flats
  Future<Response> handleRecordFlat(Request request) async {
    _logInfo('[API] POST /api/calibration/flats');
    final payload = await readJsonObject(request);

    final filterName = requireString(payload, 'filter');
    final exposureDuration =
        requireDouble(payload, 'exposureDuration', min: 0);
    final adu = requireInt(payload, 'adu', min: 0);
    final histogramTarget = optionalDouble(payload, 'histogramTarget') ?? 50.0;
    final gain = optionalInt(payload, 'gain') ?? 0;
    final binning = optionalInt(payload, 'binning', min: 1) ?? 1;
    final panelBrightness =
        optionalInt(payload, 'panelBrightness', min: 0, max: 255);
    final skyAduRate = optionalDouble(payload, 'skyAduRate');
    final twilightPhase = optionalString(payload, 'twilightPhase');
    final equipmentProfileId = optionalInt(payload, 'equipmentProfileId');

    final id = await _database.flatHistoryDao.insertEntry(
      FlatHistoryCompanion.insert(
        filterName: filterName,
        exposureTime: exposureDuration,
        histogramTarget: histogramTarget,
        actualAdu: adu,
        gain: Value(gain),
        binning: Value(binning),
        panelBrightness: Value(panelBrightness),
        skyAduRate: Value(skyAduRate),
        twilightPhase: Value(twilightPhase),
        equipmentProfileId: Value(equipmentProfileId),
      ),
    );
    final entry = await _database.flatHistoryDao.getById(id);
    if (entry == null) {
      throw HandlerFailure(
        code: 'flat_record_failed',
        message: 'Failed to read back newly-recorded flat history entry',
      );
    }
    return jsonCreated({'flat': _flatEntryToJson(entry)});
  }

  /// DELETE /api/calibration/flats/{id}
  Future<Response> handleDeleteFlat(Request request, String id) async {
    final iid = _parsePathId(id, 'id');
    _logInfo('[API] DELETE /api/calibration/flats/$iid');
    final rows = await _database.flatHistoryDao.deleteById(iid);
    if (rows == 0) {
      return jsonNotFound({
        'error': 'flat_not_found',
        'message': 'No flat history entry with id $iid',
      });
    }
    return jsonOk({'deleted': true});
  }

  /// GET /api/calibration/flats/recommendation
  Future<Response> handleFlatRecommendation(Request request) async {
    _logInfo('[API] GET /api/calibration/flats/recommendation');
    final params = request.url.queryParameters;
    final filter = params['filter'];
    if (filter == null || filter.isEmpty) {
      throw BadRequestError(
        field: 'filter',
        expected: 'non-empty string',
        message: 'filter query parameter is required',
      );
    }
    final equipmentProfileId =
        _parseIntParam(params, 'equipmentProfileId');
    final gain = _parseIntParam(params, 'gain');

    final entry = await _database.flatHistoryDao.findMostRecentMatch(
      filterName: filter,
      equipmentProfileId: equipmentProfileId,
      gain: gain,
    );
    if (entry == null) {
      return jsonOk({
        'recommended': null,
        'reason': 'no_matching_history',
      });
    }
    final ageDays =
        DateTime.now().toUtc().difference(entry.timestamp.toUtc()).inDays;
    final confidence =
        ageDays <= 7 ? 'high' : (ageDays <= 30 ? 'medium' : 'low');
    return jsonOk({
      'recommended': {
        'exposureDuration': entry.exposureTime,
        'basedOn': {
          'flatId': entry.id,
          'ageDays': ageDays,
          'confidence': confidence,
        },
      },
    });
  }

  // ===========================================================================
  // Defect maps
  // ===========================================================================

  /// GET /api/calibration/defect-maps
  Future<Response> handleListDefectMaps(Request request) async {
    _logInfo('[API] GET /api/calibration/defect-maps');
    final params = request.url.queryParameters;

    final cameraId = params['cameraId'];
    final width = _parseIntParam(params, 'width');
    final height = _parseIntParam(params, 'height');
    final bucket =
        _parseIntParam(params, 'temperatureBucketDecicelsius');

    final db = _database;
    var query = db.select(db.defectMaps);
    if (cameraId != null) {
      query = query..where((t) => t.cameraId.equals(cameraId));
    }
    if (width != null) {
      query = query..where((t) => t.width.equals(width));
    }
    if (height != null) {
      query = query..where((t) => t.height.equals(height));
    }
    if (bucket != null) {
      query = query
        ..where((t) => t.temperatureBucketDecicelsius.equals(bucket));
    }
    query = query
      ..orderBy([(t) => OrderingTerm.desc(t.lastRebuiltAt)]);

    final rows = await query.get();
    final list = <Map<String, dynamic>>[];
    for (final row in rows) {
      list.add(await _defectMapMetadataToJson(row));
    }
    return jsonOk({'defectMaps': list, 'count': list.length});
  }

  /// GET /api/calibration/defect-maps/{id}
  ///
  /// `?format=binary` (default) — returns the BLOB bitmap with
  /// `content-type: application/octet-stream`, `accept-ranges: bytes`, and
  /// metadata headers (`x-defect-map-camera-id`, `-width`, `-height`,
  /// `-temperature-bucket-decicelsius`, `-defective-pixel-count`).
  ///
  /// `?format=json` — returns metadata + base64 bitmap in a JSON wrapper.
  Future<Response> handleGetDefectMap(Request request, String id) async {
    final iid = _parsePathId(id, 'id');
    final format = (request.url.queryParameters['format'] ?? 'binary')
        .toLowerCase();
    _logInfo('[API] GET /api/calibration/defect-maps/$iid?format=$format');

    final db = _database;
    final row = await (db.select(db.defectMaps)
          ..where((t) => t.id.equals(iid)))
        .getSingleOrNull();
    if (row == null) {
      return jsonNotFound({
        'error': 'defect_map_not_found',
        'message': 'No defect map with id $iid',
      });
    }

    if (format == 'json') {
      final meta = await _defectMapMetadataToJson(row);
      return jsonOk({
        'defectMap': {
          ...meta,
          'bitmapBase64': base64Encode(row.bitmap),
        },
      });
    }
    if (format != 'binary') {
      throw BadRequestError(
        field: 'format',
        expected: '"binary" or "json"',
        message: 'Unsupported format "$format"',
      );
    }

    return Response.ok(
      row.bitmap,
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': row.bitmap.length.toString(),
        'accept-ranges': 'bytes',
        'x-defect-map-id': row.id.toString(),
        'x-defect-map-camera-id': row.cameraId,
        'x-defect-map-width': row.width.toString(),
        'x-defect-map-height': row.height.toString(),
        'x-defect-map-temperature-bucket-decicelsius':
            row.temperatureBucketDecicelsius.toString(),
        'x-defect-map-defective-pixel-count':
            row.defectivePixelCount.toString(),
      },
    );
  }

  /// POST /api/calibration/defect-maps — register a new map by metadata +
  /// base64 bitmap. The Rust defect-map service is the usual producer; this
  /// endpoint exists for restore + cross-machine sync.
  Future<Response> handleRegisterDefectMap(Request request) async {
    _logInfo('[API] POST /api/calibration/defect-maps');
    final payload = await readJsonObject(request);

    final cameraId = requireString(payload, 'cameraId');
    final width = requireInt(payload, 'width', min: 1);
    final height = requireInt(payload, 'height', min: 1);
    final bucket = requireInt(payload, 'temperatureBucketDecicelsius');
    final defectCount = requireInt(payload, 'defectCount', min: 0);
    final sourceFilePath = optionalString(payload, 'sourceFilePath');

    final bitmapField = requireString(payload, 'bitmap');
    Uint8List bitmap;
    try {
      bitmap = base64Decode(bitmapField);
    } on FormatException {
      throw BadRequestError(
        field: 'bitmap',
        expected: 'base64-encoded bytes',
        message: 'bitmap field is not valid base64',
      );
    }

    final expectedLength = ((width * height) + 7) ~/ 8;
    if (bitmap.length != expectedLength) {
      throw BadRequestError(
        field: 'bitmap',
        expected: 'bytes of length $expectedLength',
        message:
            'bitmap byte-length (${bitmap.length}) does not match width × '
                'height = $width × $height (expected $expectedLength bytes)',
      );
    }

    final db = _database;
    final id = await db.into(db.defectMaps).insert(
          DefectMapsCompanion.insert(
            cameraId: cameraId,
            width: width,
            height: height,
            temperatureBucketDecicelsius: bucket,
            bitmap: bitmap,
            defectivePixelCount: defectCount,
            filePath: Value(sourceFilePath),
          ),
        );
    final row = await (db.select(db.defectMaps)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw HandlerFailure(
        code: 'defect_map_register_failed',
        message: 'Failed to read back newly-registered defect map',
      );
    }
    return jsonCreated({'defectMap': await _defectMapMetadataToJson(row)});
  }

  /// DELETE /api/calibration/defect-maps/{id}?deleteFile=true
  Future<Response> handleDeleteDefectMap(Request request, String id) async {
    final iid = _parsePathId(id, 'id');
    _logInfo('[API] DELETE /api/calibration/defect-maps/$iid');
    final deleteFile =
        request.url.queryParameters['deleteFile']?.toLowerCase() == 'true';

    final db = _database;
    final row = await (db.select(db.defectMaps)
          ..where((t) => t.id.equals(iid)))
        .getSingleOrNull();
    if (row == null) {
      return jsonNotFound({
        'error': 'defect_map_not_found',
        'message': 'No defect map with id $iid',
      });
    }

    bool fileDeleted = false;
    if (deleteFile && row.filePath != null && row.filePath!.isNotEmpty) {
      try {
        final file = File(row.filePath!);
        if (await file.exists()) {
          await file.delete();
          fileDeleted = true;
        }
      } on PathAccessException catch (e) {
        _logWarning('Permission denied deleting defect-map $iid file: $e');
        return jsonForbidden({
          'error': 'permission_denied',
          'path': row.filePath,
        });
      } on FileSystemException catch (e) {
        _logWarning(
          'Failed to delete defect-map $iid source file: ${e.message}',
        );
        await (db.delete(db.defectMaps)..where((t) => t.id.equals(iid)))
            .go();
        return jsonOk({
          'deleted': true,
          'fileDeleted': false,
          'fileError': e.message,
        });
      }
    }

    final rowsAffected =
        await (db.delete(db.defectMaps)..where((t) => t.id.equals(iid)))
            .go();
    return jsonOk({
      'deleted': rowsAffected > 0,
      'fileDeleted': fileDeleted,
    });
  }

  /// POST /api/calibration/defect-maps/{id}/regenerate
  ///
  /// Recomputes the defect map by re-running the Rust defect-map build
  /// against the source file. Returns 409 when the source path is unset
  /// or no longer on disk.
  Future<Response> handleRegenerateDefectMap(
    Request request,
    String id,
  ) async {
    final iid = _parsePathId(id, 'id');
    _logInfo('[API] POST /api/calibration/defect-maps/$iid/regenerate');

    final db = _database;
    final row = await (db.select(db.defectMaps)
          ..where((t) => t.id.equals(iid)))
        .getSingleOrNull();
    if (row == null) {
      return jsonNotFound({
        'error': 'defect_map_not_found',
        'message': 'No defect map with id $iid',
      });
    }
    final sourcePath = row.filePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      return jsonConflict({
        'error': 'defect_map_no_source',
        'message':
            'Defect map $iid was registered without a sourceFilePath; '
                'cannot regenerate',
      });
    }
    final source = File(sourcePath);
    if (!await source.exists()) {
      return jsonConflict({
        'error': 'defect_map_source_missing',
        'message':
            'Defect map $iid source file is no longer on disk: $sourcePath',
        'sourceFilePath': sourcePath,
      });
    }

    final service = container.read(defectMapServiceProvider);
    final temperatureCelsius = row.temperatureBucketDecicelsius / 10.0;
    final status = await service.build(
      cameraId: row.cameraId,
      darkFramePaths: [sourcePath],
      sensorTemperatureCelsius: temperatureCelsius,
    );

    // After build the row in Drift may have been updated by the native
    // side via a separate code path, or we may need to reflect the new
    // count + last-rebuilt-at directly. Refresh the row and use the
    // returned status as the source of truth for the response.
    final refreshed = await (db.select(db.defectMaps)
          ..where((t) => t.id.equals(iid)))
        .getSingleOrNull();
    return jsonOk({
      'status': {
        'cameraId': status.cameraId,
        'width': status.width,
        'height': status.height,
        'temperatureBucketDecicelsius':
            status.temperatureBucket.decicelsius,
        'defectivePixelCount': status.defectivePixelCount,
        'lastRebuiltUnixSeconds': status.lastRebuiltUnixSeconds,
        'applyDuringCapture': status.applyDuringCapture,
        'storedOnDisk': status.storedOnDisk,
      },
      if (refreshed != null)
        'defectMap': await _defectMapMetadataToJson(refreshed),
    });
  }

  // ===========================================================================
  // Helpers — JSON shape
  // ===========================================================================

  Future<Map<String, dynamic>> _darkEntryToWire(
      DarkLibraryEntry entry) async {
    final file = File(entry.filePath);
    bool exists = false;
    int? fileSize;
    try {
      exists = await file.exists();
      if (exists) {
        fileSize = await file.length();
      }
    } on FileSystemException {
      exists = false;
    }
    return {
      'id': entry.id,
      'filePath': entry.filePath,
      'fileName': p.basename(entry.filePath),
      'exposureDuration': entry.exposureTime,
      'sensorTempC': entry.temperature,
      'gain': entry.gain,
      'offset': entry.offset,
      'binX': entry.binX,
      'binY': entry.binY,
      'frameType': entry.frameType,
      'width': entry.width,
      'height': entry.height,
      'masterPath': entry.masterDarkPath,
      'frameCount': entry.masterFrameCount,
      'createdAt': entry.createdAt.toUtc().toIso8601String(),
      'fileSize': fileSize,
      'fileExists': exists,
    };
  }

  Map<String, dynamic> _flatEntryToJson(FlatHistoryEntry entry) {
    return {
      'id': entry.id,
      'filter': entry.filterName,
      'exposureDuration': entry.exposureTime,
      'histogramTarget': entry.histogramTarget,
      'adu': entry.actualAdu,
      'gain': entry.gain,
      'binning': entry.binning,
      'panelBrightness': entry.panelBrightness,
      'skyAduRate': entry.skyAduRate,
      'twilightPhase': entry.twilightPhase,
      'equipmentProfileId': entry.equipmentProfileId,
      'createdAt': entry.timestamp.toUtc().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> _defectMapMetadataToJson(
      DefectMapEntry row) async {
    int? fileSize;
    bool fileExists = false;
    final sp = row.filePath;
    if (sp != null && sp.isNotEmpty) {
      try {
        final file = File(sp);
        fileExists = await file.exists();
        if (fileExists) {
          fileSize = await file.length();
        }
      } on FileSystemException {
        fileExists = false;
      }
    }
    return {
      'id': row.id,
      'cameraId': row.cameraId,
      'width': row.width,
      'height': row.height,
      'temperatureBucketDecicelsius': row.temperatureBucketDecicelsius,
      'defectivePixelCount': row.defectivePixelCount,
      'lastRebuiltAt': row.lastRebuiltAt.toUtc().toIso8601String(),
      'sourceFilePath': row.filePath,
      'fileSize': fileSize,
      'fileExists': fileExists,
    };
  }

  // ===========================================================================
  // Helpers — query-param parsing
  // ===========================================================================

  int? _parseIntParam(Map<String, String> params, String name) {
    final raw = params[name];
    if (raw == null || raw.isEmpty) return null;
    final value = int.tryParse(raw);
    if (value == null) {
      throw BadRequestError(
        field: name,
        expected: 'integer',
        message: '$name must be an integer, got "$raw"',
      );
    }
    return value;
  }

  double? _parseDoubleParam(Map<String, String> params, String name) {
    final raw = params[name];
    if (raw == null || raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null) {
      throw BadRequestError(
        field: name,
        expected: 'number',
        message: '$name must be a number, got "$raw"',
      );
    }
    return value;
  }

  DateTime? _parseDateParam(Map<String, String> params, String name) {
    final raw = params[name];
    if (raw == null || raw.isEmpty) return null;
    final asInt = int.tryParse(raw);
    if (asInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw BadRequestError(
        field: name,
        expected: 'ISO-8601 timestamp or unix-ms integer',
        message: '$name is not a parseable timestamp: "$raw"',
      );
    }
    return parsed;
  }

  int _parseListLimit(Map<String, String> params) {
    final raw = params['limit'];
    if (raw == null || raw.isEmpty) return _defaultListLimit;
    final value = int.tryParse(raw);
    if (value == null || value <= 0) {
      throw BadRequestError(
        field: 'limit',
        expected: 'positive integer',
        message: 'limit must be a positive integer',
      );
    }
    return value > _maxListLimit ? _maxListLimit : value;
  }

  String? _sanitizeDarkFileName(String requested) {
    var name = requested.split(RegExp(r'[\\/]')).last.trim();
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (name.isEmpty || name == '.' || name == '..') return null;
    if (!name.contains('.')) name = '$name.fits';
    final lower = name.toLowerCase();
    if (!lower.endsWith('.fits') &&
        !lower.endsWith('.fit') &&
        !lower.endsWith('.xisf')) {
      return null;
    }
    if (name.length > 120) {
      final ext = lower.endsWith('.fits')
          ? '.fits'
          : (lower.endsWith('.fit') ? '.fit' : '.xisf');
      final stem = name.substring(0, name.length - ext.length);
      final maxStem = 120 - ext.length;
      final safeStem =
          stem.length <= maxStem ? stem : stem.substring(0, maxStem);
      name = '$safeStem$ext';
    }
    return name;
  }

  Future<File> _resolveUniquePath(Directory dir, String fileName) async {
    final candidate = File(p.join(dir.path, fileName));
    if (!await candidate.exists()) return candidate;
    final ext = p.extension(fileName);
    final stem = p.basenameWithoutExtension(fileName);
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return File(p.join(dir.path, '${stem}_upload_$timestamp$ext'));
  }

}

// Exposure of `defectMapServiceProvider` lives in nightshade_core; we read
// it via the container so this file does not need a direct provider import.
