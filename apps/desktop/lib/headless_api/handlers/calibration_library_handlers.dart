import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';
import '../validation.dart';

/// Handlers for the unified Calibration Library Manager.
///
/// Distinct from the per-table P1-10 `/api/calibration/*` CRUD surface: this
/// exposes the *library* view that joins darks, flats, biases, and defect
/// maps into one list with user tags/notes ([CalibrationLibraryService]),
/// plus the transparent auto-matcher a remote client uses to preview which
/// masters a given light-frame context will auto-select and why.
///
/// Endpoints (all under `/api/calibration-library`):
///   GET    /api/calibration-library            — list masters (filters)
///   POST   /api/calibration-library/match      — best master per type + why
///   PUT    `/api/calibration-library/<type>/<id>/tags` — set tags/notes
///   DELETE `/api/calibration-library/<type>/<id>`      — delete row (+ file?)
class CalibrationLibraryHandlers {
  final ProviderContainer container;
  CalibrationLibraryHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);
  CalibrationLibraryService get _service =>
      container.read(calibrationLibraryServiceProvider);

  /// GET /api/calibration-library — list masters, newest first.
  ///
  /// Query params (all optional): `type` (dark|bias|flat|defectMap),
  /// `cameraId`, `gain`, `filter`, `binX`, `binY`, `exposureSeconds`
  /// (with `exposureTolSecs`), `tempMin`, `tempMax`, and `mastersOnly`
  /// (default true).
  Future<Response> handleList(Request request) async {
    _logger.info('[API] GET /api/calibration-library',
        source: 'CalibrationLibraryHandlers');
    final q = request.url.queryParameters;

    final filter = CalibrationLibraryFilter(
      type: _typeParam(q['type']),
      cameraId: q['cameraId'],
      gain: _intParam(q['gain']),
      filter: q['filter'],
      binX: _intParam(q['binX']),
      binY: _intParam(q['binY']),
      exposureSeconds: _doubleParam(q['exposureSeconds']),
      exposureToleranceSecs: _doubleParam(q['exposureTolSecs']) ?? 0.5,
      temperatureMin: _doubleParam(q['tempMin']),
      temperatureMax: _doubleParam(q['tempMax']),
      mastersOnly: _boolParam(q['mastersOnly']) ?? true,
    );

    final records = await _service.listMasters(filter: filter);
    final now = DateTime.now();
    return jsonOk({
      'masters': [for (final r in records) r.toJson(now: now)],
      'count': records.length,
    });
  }

  /// POST /api/calibration-library/match — preview the auto-selection for a
  /// light-frame context. Body: `{gain, offset, exposureSeconds, temperature?,
  /// filter?, binX?, binY?, cameraId?, opticalTrainId?}`.
  Future<Response> handleMatch(Request request) async {
    _logger.info('[API] POST /api/calibration-library/match',
        source: 'CalibrationLibraryHandlers');
    final body = await readJsonObject(request);

    final context = LightFrameContext(
      cameraId: optionalString(body, 'cameraId'),
      gain: requireInt(body, 'gain'),
      offset: requireInt(body, 'offset'),
      exposureSeconds: requireDouble(body, 'exposureSeconds', min: 0),
      temperature: optionalDouble(body, 'temperature'),
      filter: optionalString(body, 'filter'),
      binX: optionalInt(body, 'binX', min: 1) ?? 1,
      binY: optionalInt(body, 'binY', min: 1) ?? 1,
      opticalTrainId: optionalString(body, 'opticalTrainId'),
    );

    final matchSet = await _service.match(context);
    return jsonOk(matchSet.toJson());
  }

  /// PUT `/api/calibration-library/<type>/<id>/tags` — replace tags/notes.
  /// Body: `{tags?: string[], notes?: string|null}`.
  Future<Response> handleSetTags(
      Request request, String typeRaw, String idRaw) async {
    final type = _requireType(typeRaw);
    final id = _requireId(idRaw);
    _logger.info('[API] PUT /api/calibration-library/$typeRaw/$id/tags',
        source: 'CalibrationLibraryHandlers');
    final body = await readJsonObject(request);

    if (body.containsKey('tags')) {
      final tags = requireList<String>(body, 'tags');
      await _service.setTags(type, id, tags);
    }
    if (body.containsKey('notes')) {
      await _service.setNotes(type, id, optionalString(body, 'notes'));
    }

    final updated = await _service.getRecord(type, id);
    if (updated == null) {
      throw HandlerFailure(
        code: 'calibration_master_not_found',
        message: 'No calibration master with that type/id',
        statusCode: 404,
      );
    }
    return jsonOk(updated.toJson());
  }

  /// DELETE `/api/calibration-library/<type>/<id>[?deleteFile=true]`.
  Future<Response> handleDelete(
      Request request, String typeRaw, String idRaw) async {
    final type = _requireType(typeRaw);
    final id = _requireId(idRaw);
    final deleteFile =
        _boolParam(request.url.queryParameters['deleteFile']) ?? false;
    _logger.info(
        '[API] DELETE /api/calibration-library/$typeRaw/$id'
        ' (deleteFile=$deleteFile)',
        source: 'CalibrationLibraryHandlers');

    final removed =
        await _service.deleteMaster(type, id, deleteFile: deleteFile);
    if (!removed) {
      throw HandlerFailure(
        code: 'calibration_master_not_found',
        message: 'No calibration master with that type/id',
        statusCode: 404,
      );
    }
    return jsonOk({'status': 'deleted', 'type': typeRaw, 'id': id});
  }

  // --- param helpers ---------------------------------------------------------

  CalibrationMasterType _requireType(String? raw) {
    final type = _typeParam(raw);
    if (type == null) {
      throw BadRequestError(
        field: 'type',
        expected: 'dark|bias|flat|defectMap',
        message: 'Unknown calibration master type',
      );
    }
    return type;
  }

  int _requireId(String? raw) {
    final id = _intParam(raw);
    if (id == null) {
      throw BadRequestError(field: 'id', expected: 'integer');
    }
    return id;
  }

  static CalibrationMasterType? _typeParam(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return calibrationMasterTypeFromWire(raw);
  }

  static int? _intParam(String? raw) =>
      (raw == null || raw.isEmpty) ? null : int.tryParse(raw);

  static double? _doubleParam(String? raw) =>
      (raw == null || raw.isEmpty) ? null : double.tryParse(raw);

  static bool? _boolParam(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
    return null;
  }
}
