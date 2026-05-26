// P2-8 — read-only API surface for DB tables the phone could not see
// before this wave (sequence_runs, observation_logs (notes journal),
// guide_rms_history, polar_alignment_history) plus paginated reads on
// the calibration tables (dark_library, flat_history) that bypass the
// existing P1-10 "best match" semantics.
//
// Wave 7B — Replay scrubber extensions. Three additional endpoints
// support the mobile session-replay surface:
//
//   GET /api/sequence-runs/<runId>
//   GET /api/sequence-runs/<runId>/events
//   GET /api/sequence-runs/<runId>/frames
//
// These are scoped to a single past run so the phone can rehydrate the
// dashboard state at any point during a finished session.
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
import '../validation.dart';

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

  // =========================================================================
  // Wave 7B — Replay scrubber endpoints (single run + per-run events/frames).
  // =========================================================================

  /// Parse a path-segment integer with translation to a structured 400.
  /// The existing `_parseOptionalInt` returns null for invalid input,
  /// which is fine for query params (the handler treats null as "filter
  /// not requested"); a missing/garbled path param is a client bug and
  /// must surface as a Bad Request rather than a silent no-op.
  int _parseRunId(String raw) {
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      throw BadRequestError(
        field: 'runId',
        expected: 'positive integer',
        message: '"$raw" is not a valid sequence-run id',
      );
    }
    return parsed;
  }

  /// `GET /api/sequence-runs/<runId>` — fetch a single sequence-run by id.
  ///
  /// The response carries everything the replay scrubber needs to build
  /// its timeline header: started/ended timestamps so it can compute the
  /// duration, the sequence and target names for the header label, the
  /// final status, the stats blob (frame count + integration time), and
  /// a `frameCount` projection convenience field so the client can render
  /// the header without parsing statsJson.
  Future<Response> handleGetSequenceRunById(
    Request request,
    String runIdRaw,
  ) async {
    _logInfo('[API] GET /api/sequence-runs/$runIdRaw');
    final runId = _parseRunId(runIdRaw);

    final run = await _database.sequenceRunsDao.getRunById(runId);
    if (run == null) {
      return jsonNotFound({
        'error': 'sequence_run_not_found',
        'message': 'No sequence run with id $runId',
      });
    }

    // Project a frame count by counting captured_images rows whose
    // producing_run_id matches the run id. This is the same source of
    // truth used by the run dashboard's thumbnail strip; we surface it
    // here so the replay's run-picker row doesn't have to call
    // /frames just to display "23 frames".
    final frameCount = await _database.imagesDao.countImagesByProducingRun(
      producingRunId: runId.toString(),
    );

    // Derive a target name from the captured frames (target_id → targets
    // table). Take the first-captured frame's target as the canonical one
    // — multi-target runs list them in capture order; the first non-null
    // target_id wins. If there are no frames or the join produces nothing
    // the field is omitted entirely so the client falls back to
    // sequenceName.
    String? targetName;
    if (frameCount > 0) {
      final firstFrames = await _database.imagesDao.getImagesByProducingRun(
        producingRunId: runId.toString(),
        limit: 1,
      );
      if (firstFrames.isNotEmpty && firstFrames.first.targetId != null) {
        final target = await _database.targetsDao
            .getTargetById(firstFrames.first.targetId!);
        targetName = target?.name;
      }
    }

    return jsonOk({
      'run': _sequenceRunDetailToJson(run, frameCount, targetName),
    });
  }

  /// Detail-shaped JSON for a single run — same field names as the list
  /// view plus `frameCount` and `targetName` for replay header rendering.
  Map<String, dynamic> _sequenceRunDetailToJson(
    SequenceRun row,
    int frameCount,
    String? targetName,
  ) {
    return {
      'id': row.id,
      'sequenceId': row.sequenceId,
      'sequenceName': row.sequenceName,
      'startedAt': row.startedAt.toIso8601String(),
      'endedAt': row.endedAt?.toIso8601String(),
      'status': row.status,
      'statsJson': row.statsJson,
      'frameCount': frameCount,
      if (targetName != null) 'targetName': targetName,
    };
  }

  /// `GET /api/sequence-runs/<runId>/events` — paginated events captured
  /// during the run's time window.
  ///
  /// The headless server does NOT (yet) persist `NightshadeEvent`
  /// instances to a dedicated DAO — events are forwarded to the
  /// LoggingService which keeps an in-memory ring buffer (1000 entries)
  /// and the Rust tracing appender that writes to disk. The disk format
  /// is human-readable text, not structured JSON, and is not indexed
  /// by sequence-run id; for now the ring buffer is the only structured
  /// source we can hand back.
  ///
  /// Consequence: any run older than ~the last 1000 log entries (or one
  /// that ended before the server restarted) will return a sparse event
  /// list. We surface this loudly via `is_partial: true` in the
  /// envelope so the phone UI can render a banner explaining the gap
  /// rather than silently misleading the operator. Follow-up work is
  /// tracked in the W7B report — a `nightshade_events` DAO writing every
  /// broadcast event would make this lossless.
  Future<Response> handleGetSequenceRunEvents(
    Request request,
    String runIdRaw,
  ) async {
    _logInfo('[API] GET /api/sequence-runs/$runIdRaw/events');
    final runId = _parseRunId(runIdRaw);

    final run = await _database.sequenceRunsDao.getRunById(runId);
    if (run == null) {
      return jsonNotFound({
        'error': 'sequence_run_not_found',
        'message': 'No sequence run with id $runId',
      });
    }

    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);

    final sinceMs = _parseOptionalInt(qp['since']);
    final untilMs = _parseOptionalInt(qp['until']);

    final startBound = sinceMs != null
        ? DateTime.fromMillisecondsSinceEpoch(sinceMs)
        : run.startedAt;
    final endBound = untilMs != null
        ? DateTime.fromMillisecondsSinceEpoch(untilMs)
        : (run.endedAt ?? DateTime.now());

    LogLevel? severityMin;
    final sevRaw = qp['severityMin'];
    if (sevRaw != null && sevRaw.isNotEmpty) {
      final parsed = LoggingService.parseLogLevel(sevRaw);
      if (parsed == null) {
        throw BadRequestError(
          field: 'severityMin',
          expected:
              'one of: ${LogLevel.values.map((l) => l.name).join(', ')}',
          message: '"$sevRaw" is not a valid severity name',
        );
      }
      severityMin = parsed;
    }

    final logger = container.read(loggingServiceProvider);
    final allEntries = logger.getRecentLogs(minLevel: severityMin);
    final inWindow = allEntries.where((e) {
      // Inclusive lower/upper bounds — the run header events
      // `sequencer.started` and `sequencer.completed` line up exactly
      // with `startedAt`/`endedAt` so half-open semantics would drop
      // the bookends.
      if (e.timestamp.isBefore(startBound)) return false;
      if (e.timestamp.isAfter(endBound)) return false;
      return true;
    }).toList();

    final total = inWindow.length;
    final end = (offset + limit).clamp(0, total);
    final start = offset.clamp(0, total);
    final slice = (start >= end) ? <LogEntry>[] : inWindow.sublist(start, end);

    // The ring buffer is finite (1000 entries). If the oldest buffered
    // entry's timestamp is AFTER the run's startedAt we know we have
    // dropped older entries that should logically belong to this run.
    // Surface that as `is_partial` so the client can render a banner.
    final bool isPartial;
    final String? partialReason;
    if (allEntries.isEmpty) {
      isPartial = true;
      partialReason = 'no_buffered_entries';
    } else {
      final oldest = allEntries.first.timestamp;
      isPartial = oldest.isAfter(run.startedAt);
      partialReason = isPartial ? 'ring_buffer_truncated' : null;
    }

    return jsonOk({
      'items': slice.map(_eventEntryToJson).toList(growable: false),
      'total': total,
      'is_partial': isPartial,
      'source': 'logging_service_ring_buffer',
      if (partialReason != null) 'partialReason': partialReason,
    });
  }

  /// Project a LogEntry into the wire shape the replay client consumes.
  /// Mirrors LogEntry.toJson plus a unix-ms timestamp for monotonic
  /// scrubber arithmetic on the phone side (DateTime parsing on
  /// Dart-on-iOS has noticeable cost vs an int comparison; the scrubber
  /// runs the scan-to-time on every drag frame, so the extra field
  /// pays for itself within a few drags).
  Map<String, Object?> _eventEntryToJson(LogEntry entry) {
    return {
      'timestamp': entry.timestamp.toUtc().toIso8601String(),
      'timestampMs': entry.timestamp.millisecondsSinceEpoch,
      'severity': entry.level.name,
      if (entry.source != null) 'source': entry.source,
      'message': entry.message,
      if (entry.fields.isNotEmpty) 'fields': _jsonSafeFields(entry.fields),
    };
  }

  /// Defensive copy of [LogEntry.fields] suitable for JSON encoding.
  /// LogEntry already calls its private `_jsonSafe` helper on toJson,
  /// but that helper is unreachable from this file. We re-implement
  /// the narrow safety: pass through primitives, recurse into maps/
  /// iterables, stringify everything else. Mirrors the upstream
  /// helper so wire payloads agree shape-for-shape.
  Object? _jsonSafeFields(Object? value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Iterable) {
      return value.map(_jsonSafeFields).toList(growable: false);
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafeFields(entry.value),
      };
    }
    return value.toString();
  }

  /// `GET /api/sequence-runs/<runId>/frames` — paginated captured-image
  /// rows for the run.
  ///
  /// Joins to the `producing_run_id` raw-DDL column added in the v30
  /// migration. The row shape includes every column the replay
  /// scrubber's "current frame" panel may want: HFR, star count,
  /// background, guiding RMS at the time of the exposure, the filter
  /// name, and the file path so the phone can request a thumbnail via
  /// the existing `/api/images/<id>/thumbnail` endpoint.
  Future<Response> handleGetSequenceRunFrames(
    Request request,
    String runIdRaw,
  ) async {
    _logInfo('[API] GET /api/sequence-runs/$runIdRaw/frames');
    final runId = _parseRunId(runIdRaw);

    final run = await _database.sequenceRunsDao.getRunById(runId);
    if (run == null) {
      return jsonNotFound({
        'error': 'sequence_run_not_found',
        'message': 'No sequence run with id $runId',
      });
    }

    final qp = request.url.queryParameters;
    final limit = _parseLimit(qp['limit']);
    final offset = _parseOffset(qp['offset']);

    final frames = await _database.imagesDao.getImagesByProducingRun(
      producingRunId: runId.toString(),
      limit: limit,
      offset: offset,
    );
    final total = await _database.imagesDao.countImagesByProducingRun(
      producingRunId: runId.toString(),
    );

    return jsonOk({
      'items': frames.map(_capturedImageToJson).toList(growable: false),
      'total': total,
    });
  }

  /// Wire projection of a CapturedImage row scoped to what the replay
  /// scrubber renders. We deliberately do NOT include `displayData` or
  /// any FITS body bytes — those are served by `/api/images/{id}/...`
  /// endpoints and would balloon this list response.
  ///
  /// Uses [DbCapturedImage] because the nightshade_core barrel hides
  /// the raw drift `CapturedImage` entity to avoid colliding with the
  /// imaging-domain class of the same name (see CQ-W4-BARREL-EXPOSE).
  Map<String, Object?> _capturedImageToJson(DbCapturedImage row) {
    return {
      'id': row.id,
      'fileName': row.fileName,
      'filePath': row.filePath,
      'capturedAt': row.capturedAt.toIso8601String(),
      'capturedAtMs': row.capturedAt.millisecondsSinceEpoch,
      'frameType': row.frameType,
      'exposureDuration': row.exposureDuration,
      'filter': row.filter,
      'gain': row.gain,
      'offset': row.offset,
      'binX': row.binX,
      'binY': row.binY,
      'sensorTemp': row.sensorTemp,
      'hfr': row.hfr,
      'starCount': row.starCount,
      'background': row.background,
      'noise': row.noise,
      'qualityScore': row.qualityScore,
      'guidingRmsRa': row.guidingRmsRa,
      'guidingRmsDec': row.guidingRmsDec,
      'guidingRmsTotal': row.guidingRmsTotal,
      'mountRa': row.mountRa,
      'mountDec': row.mountDec,
      'mountAltitude': row.mountAltitude,
      'mountAzimuth': row.mountAzimuth,
      'focuserPosition': row.focuserPosition,
      'isAccepted': row.isAccepted,
      'rejectionReason': row.rejectionReason,
      'sessionId': row.sessionId,
      'targetId': row.targetId,
    };
  }
}
