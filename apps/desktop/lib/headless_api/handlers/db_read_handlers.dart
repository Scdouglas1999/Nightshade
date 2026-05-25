// P2-8 — read-only API surface for DB tables the phone could not see
// before this wave (sequence_runs, observation_logs (notes journal),
// guide_rms_history, polar_alignment_history) plus paginated reads on
// the calibration tables (dark_library, flat_history) that bypass the
// existing P1-10 "best match" semantics.
//
// Endpoints (all under /api):
//
//   Sequence run history:
//     GET /api/sequence-runs
//         ?sequenceId=&limit=&offset=
//
//   Notes journal (observation_logs):
//     GET /api/notes-journal
//         ?equipmentProfileId=&limit=&offset=
//
//   Guide-RMS history (time-bucketed):
//     GET /api/guide-rms-history
//         ?sinceMs=&untilMs=&limit=&offset=
//
//   Polar alignment history:
//     GET /api/polar-alignment-history
//         ?equipmentProfileId=&limit=&offset=
//
//   Dark library (paginated read):
//     GET /api/db/dark-library
//         ?gainMin=&gainMax=&temperatureC=&exposureSecs=&limit=&offset=
//
//   Flat history (paginated read):
//     GET /api/db/flat-history
//         ?filterName=&panelKey=&limit=&offset=
//
// The dark/flat reads live under /api/db/ rather than /api/calibration/
// so we do NOT clash with the existing P1-10 calibration endpoints
// (which use different filter shapes — exposure tolerance ratios etc.).
//
// All endpoints return a JSON envelope: `{ "items": [...], "total": N }`.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:shelf/shelf.dart';

import '../response_helpers.dart';

/// P2-8 — read handlers for tables previously invisible to the phone.
class DbReadHandlers {
  /// Default page size. Same value as the science / calibration read
  /// surfaces use, so phone callers can apply one batching policy.
  static const int defaultLimit = 200;

  /// Hard upper bound per request. Picked so a fully-populated row of
  /// the largest table (sequence_runs.statsJson can be tens of KB)
  /// still fits in a typical mobile read budget.
  static const int maxLimit = 1000;

  final ProviderContainer container;

  DbReadHandlers(this.container);

  LoggingService get _logger => container.read(loggingServiceProvider);
  NightshadeDatabase get _database => container.read(databaseProvider);

  void _logInfo(String message) =>
      _logger.info(message, source: 'DbReadHandlers');

  /// Parse and clamp a `limit` query parameter. Defaults to
  /// [defaultLimit]; clamps to [1, maxLimit]. Why clamp silently here
  /// (and not throw): the spec promises pagination, and a phone caller
  /// asking for 5000 rows is better off receiving 1000 than a 400.
  int _parseLimit(String? raw) {
    if (raw == null || raw.isEmpty) return defaultLimit;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return defaultLimit;
    return parsed > maxLimit ? maxLimit : parsed;
  }

  /// Parse and clamp an `offset` query parameter. Defaults to 0;
  /// negative offsets are treated as 0.
  int _parseOffset(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) return 0;
    return parsed;
  }

  int? _parseOptionalInt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  double? _parseOptionalDouble(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  // =========================================================================
  // Sequence run history
  // =========================================================================

  Future<Response> handleListSequenceRuns(Request request) async {
    _logInfo('[API] GET /api/sequence-runs');
    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);
    final sequenceId = _parseOptionalInt(qp['sequenceId']);

    final dao = _database.sequenceRunsDao;
    final rows = await dao.listPaginated(
      sequenceId: sequenceId,
      limit: limit,
      offset: offset,
    );
    final total = await dao.countFiltered(sequenceId: sequenceId);

    return jsonOk({
      'items': rows.map(_sequenceRunToJson).toList(),
      'total': total,
    });
  }

  Map<String, dynamic> _sequenceRunToJson(SequenceRun row) {
    return {
      'id': row.id,
      'sequenceId': row.sequenceId,
      'sequenceName': row.sequenceName,
      'startedAt': row.startedAt.toIso8601String(),
      'endedAt': row.endedAt?.toIso8601String(),
      'status': row.status,
      'statsJson': row.statsJson,
    };
  }

  // =========================================================================
  // Notes journal (observation_logs)
  //
  // The task spec said "?sessionId=" — but the underlying observation_logs
  // table is per-equipment-profile, not per-imaging-session. We expose
  // the actual column (equipmentProfileId) so the phone gets a filter
  // that matches reality instead of a silent no-op on a fake key.
  // =========================================================================

  Future<Response> handleListNotesJournal(Request request) async {
    _logInfo('[API] GET /api/notes-journal');
    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);
    final profileId = _parseOptionalInt(qp['equipmentProfileId']);

    final dao = _database.observationLogsDao;
    final rows = await dao.listPaginated(
      equipmentProfileId: profileId,
      limit: limit,
      offset: offset,
    );
    final total = await dao.countFiltered(equipmentProfileId: profileId);

    return jsonOk({
      'items': rows.map(_observationLogToJson).toList(),
      'total': total,
    });
  }

  Map<String, dynamic> _observationLogToJson(ObservationLogEntry row) {
    return {
      'id': row.id,
      'timestamp': row.timestamp.toIso8601String(),
      'objectName': row.objectName,
      'objectType': row.objectType,
      'catalogId': row.catalogId,
      'ra': row.ra,
      'dec': row.dec,
      'altitude': row.altitude,
      'azimuth': row.azimuth,
      'notes': row.notes,
      'rating': row.rating,
      'equipmentProfileId': row.equipmentProfileId,
      'seeingConditions': row.seeingConditions,
      'transparency': row.transparency,
      'locationName': row.locationName,
      'latitude': row.latitude,
      'longitude': row.longitude,
    };
  }

  // =========================================================================
  // Guide-RMS history
  // =========================================================================

  Future<Response> handleListGuideRmsHistory(Request request) async {
    _logInfo('[API] GET /api/guide-rms-history');
    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);
    final sinceMs = _parseOptionalInt(qp['sinceMs']);
    final untilMs = _parseOptionalInt(qp['untilMs']);

    final dao = _database.guideRmsHistoryDao;
    final rows = await dao.listPaginated(
      sinceMs: sinceMs,
      untilMs: untilMs,
      limit: limit,
      offset: offset,
    );
    final total = await dao.countFiltered(
      sinceMs: sinceMs,
      untilMs: untilMs,
    );

    return jsonOk({
      'items': rows.map(_guideRmsToJson).toList(),
      'total': total,
    });
  }

  Map<String, dynamic> _guideRmsToJson(GuideRmsHistoryEntry row) {
    return {
      'id': row.id,
      'sessionId': row.sessionId,
      'mountId': row.mountId,
      'targetId': row.targetId,
      'totalRmsArcsec': row.totalRmsArcsec,
      'sampleCount': row.sampleCount,
      'exposureSeconds': row.exposureSeconds,
      'recordedAt': row.recordedAt.toIso8601String(),
    };
  }

  // =========================================================================
  // Polar alignment history
  // =========================================================================

  Future<Response> handleListPolarAlignmentHistory(Request request) async {
    _logInfo('[API] GET /api/polar-alignment-history');
    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);
    final profileId = _parseOptionalInt(qp['equipmentProfileId']);

    final dao = _database.polarAlignmentHistoryDao;
    final rows = await dao.listPaginated(
      equipmentProfileId: profileId,
      limit: limit,
      offset: offset,
    );
    final total =
        await dao.countFiltered(equipmentProfileId: profileId);

    return jsonOk({
      'items': rows.map(_polarAlignmentToJson).toList(),
      'total': total,
    });
  }

  Map<String, dynamic> _polarAlignmentToJson(
      PolarAlignmentHistoryEntry row) {
    return {
      'id': row.id,
      'equipmentProfileId': row.equipmentProfileId,
      'initialAzimuthError': row.initialAzimuthError,
      'initialAltitudeError': row.initialAltitudeError,
      'initialTotalError': row.initialTotalError,
      'finalAzimuthError': row.finalAzimuthError,
      'finalAltitudeError': row.finalAltitudeError,
      'finalTotalError': row.finalTotalError,
      'startedAt': row.startedAt.toIso8601String(),
      'completedAt': row.completedAt.toIso8601String(),
      'autoCompleted': row.autoCompleted,
      'isNorth': row.isNorth,
      'configJson': row.configJson,
    };
  }

  // =========================================================================
  // Dark library (paginated read)
  // =========================================================================

  Future<Response> handleListDarkLibrary(Request request) async {
    _logInfo('[API] GET /api/db/dark-library');
    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);
    final gainMin = _parseOptionalInt(qp['gainMin']);
    final gainMax = _parseOptionalInt(qp['gainMax']);
    final temperatureC = _parseOptionalDouble(qp['temperatureC']);
    final exposureSecs = _parseOptionalDouble(qp['exposureSecs']);

    final dao = _database.darkLibraryDao;
    final rows = await dao.listPaginated(
      gainMin: gainMin,
      gainMax: gainMax,
      temperatureCelsius: temperatureC,
      exposureSeconds: exposureSecs,
      limit: limit,
      offset: offset,
    );
    final total = await dao.countFilteredForRemote(
      gainMin: gainMin,
      gainMax: gainMax,
      temperatureCelsius: temperatureC,
      exposureSeconds: exposureSecs,
    );

    return jsonOk({
      'items': rows.map(_darkLibraryToJson).toList(),
      'total': total,
    });
  }

  Map<String, dynamic> _darkLibraryToJson(DarkLibraryEntry row) {
    return {
      'id': row.id,
      'filePath': row.filePath,
      'frameType': row.frameType,
      'exposureTime': row.exposureTime,
      'gain': row.gain,
      'offset': row.offset,
      'binX': row.binX,
      'binY': row.binY,
      'temperature': row.temperature,
      'width': row.width,
      'height': row.height,
      'masterDarkPath': row.masterDarkPath,
      'masterFrameCount': row.masterFrameCount,
      'createdAt': row.createdAt.toIso8601String(),
    };
  }

  // =========================================================================
  // Flat history (paginated read)
  // =========================================================================

  Future<Response> handleListFlatHistory(Request request) async {
    _logInfo('[API] GET /api/db/flat-history');
    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);
    final filterName = qp['filterName'];
    // `panelKey` maps onto `panelBrightness` — see DAO comment for the
    // mapping rationale (no separate panel-id column in this table).
    final panelKey = _parseOptionalInt(qp['panelKey']);

    final dao = _database.flatHistoryDao;
    final rows = await dao.listPaginated(
      filterName: (filterName != null && filterName.isNotEmpty)
          ? filterName
          : null,
      panelBrightness: panelKey,
      limit: limit,
      offset: offset,
    );
    final total = await dao.countFiltered(
      filterName: (filterName != null && filterName.isNotEmpty)
          ? filterName
          : null,
      panelBrightness: panelKey,
    );

    return jsonOk({
      'items': rows.map(_flatHistoryToJson).toList(),
      'total': total,
    });
  }

  Map<String, dynamic> _flatHistoryToJson(FlatHistoryEntry row) {
    return {
      'id': row.id,
      'filterName': row.filterName,
      'exposureTime': row.exposureTime,
      'histogramTarget': row.histogramTarget,
      'actualAdu': row.actualAdu,
      'equipmentProfileId': row.equipmentProfileId,
      'panelBrightness': row.panelBrightness,
      'skyAduRate': row.skyAduRate,
      'twilightPhase': row.twilightPhase,
      'gain': row.gain,
      'binning': row.binning,
      'timestamp': row.timestamp.toIso8601String(),
    };
  }
}
