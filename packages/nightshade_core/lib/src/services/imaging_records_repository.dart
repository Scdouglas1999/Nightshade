import 'dart:async';
import 'dart:developer' as developer;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show apiReadFitsFile;

import '../backend/network_backend.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/database.dart' as db;
import '../models/backend/event_types.dart' show EventSeverity;
import '../models/notification/notification_categories.dart';
import '../providers/backend_provider.dart';
import '../providers/constellation_provider.dart'
    show coImagingSessionServiceProvider;
import '../providers/database_provider.dart';
import '../providers/narrator_provider.dart' show narratorServiceProvider;
import '../providers/notification_router_provider.dart'
    show notificationRouterProvider;
import '../providers/sky_atlas_provider.dart';
import '../providers/transient_detections_provider.dart';
import '../services/logging_service.dart';
import '../services/sky_atlas/sky_atlas_models.dart';
import '../services/sky_atlas/sky_atlas_service.dart' show SkyAtlasService;
import '../services/transients/transient_candidate.dart';
import '../utils/coordinate_format.dart';
import '../utils/utc_timestamp.dart';
import '../utils/resilient_poll_stream.dart';
import '../services/wcs/gnomonic_projection.dart' show SolvedWcs;
import '../services/wcs/wcs_sip_codec.dart';

/// Invoked after a freshly solved light frame's WCS is persisted locally, so
/// Pillar A ("Your Sky") can fold that frame into the personal sky atlas. The
/// callback owns its own error handling — it must never throw back into the
/// solve-persist path. Wired by [imagingRecordsRepositoryProvider]; absent for
/// remote companions (the appliance folds on its own host side).
typedef SolvedFrameFoldHook = Future<void> Function(int capturedImageId);

/// Host-authoritative access to imaging sessions and captured-image rows.
///
/// Local [FfiBackend] / desktop UI uses Drift DAOs. Remote companions
/// ([NetworkBackend]) read and write through the headless REST API so
/// mobile never mutates an empty local SQLite catalog.
class ImagingRecordsRepository {
  final SessionsDao? _sessionsDao;
  final ImagesDao? _imagesDao;
  final NetworkBackend? _remote;
  final Duration _remotePollInterval;

  /// Optional sky-atlas fold hook, fired after a local plate-solve persist.
  final SolvedFrameFoldHook? _onSolvedFrameFold;

  ImagingRecordsRepository._({
    SessionsDao? sessionsDao,
    ImagesDao? imagesDao,
    NetworkBackend? remote,
    Duration remotePollInterval = const Duration(seconds: 10),
    SolvedFrameFoldHook? onSolvedFrameFold,
  }) : _sessionsDao = sessionsDao,
       _imagesDao = imagesDao,
       _remote = remote,
       _remotePollInterval = remotePollInterval,
       _onSolvedFrameFold = onSolvedFrameFold {
    assert(
      (sessionsDao != null && imagesDao != null && remote == null) ||
          (sessionsDao == null && imagesDao == null && remote != null),
      'ImagingRecordsRepository must be local (DAOs) or remote (NetworkBackend)',
    );
  }

  factory ImagingRecordsRepository.local({
    required SessionsDao sessionsDao,
    required ImagesDao imagesDao,
    SolvedFrameFoldHook? onSolvedFrameFold,
  }) => ImagingRecordsRepository._(
    sessionsDao: sessionsDao,
    imagesDao: imagesDao,
    onSolvedFrameFold: onSolvedFrameFold,
  );

  factory ImagingRecordsRepository.remote(
    NetworkBackend remote, {
    Duration pollInterval = const Duration(seconds: 10),
  }) => ImagingRecordsRepository._(
    remote: remote,
    remotePollInterval: pollInterval,
  );

  bool get isRemote => _remote != null;

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  Future<List<db.ImagingSession>> getAllSessions() async {
    if (_remote != null) {
      final rows = await _remote.getAllSessions();
      return rows.map(imagingSessionFromWireJson).toList();
    }
    return _sessionsDao!.getAllSessions();
  }

  Future<db.ImagingSession?> getSessionById(int id) async {
    if (_remote != null) {
      final row = await _remote.getSessionById(id);
      return row == null ? null : imagingSessionFromWireJson(row);
    }
    return _sessionsDao!.getSessionById(id);
  }

  Future<List<db.ImagingSession>> getSessionsForTarget(int targetId) async {
    if (_remote != null) {
      final rows = await _remote.getSessionsForTarget(targetId);
      return rows.map(imagingSessionFromWireJson).toList();
    }
    return _sessionsDao!.getSessionsForTarget(targetId);
  }

  /// Remote-only: pull the host's `sequence_runs` rows via
  /// `GET /api/sequence-runs` and map them onto the local Drift `SequenceRun`
  /// shape. Used by [SessionReportService] so the report's mount/operations and
  /// errors/warnings sections reflect the master's real run history instead of
  /// the slave's empty local table. Throws when called on a local repository —
  /// callers branch on [isRemote] first and read the local DAO directly there.
  Future<List<db.SequenceRun>> getAllSequenceRunsRemote() async {
    final remote = _remote;
    if (remote == null) {
      throw StateError(
        'getAllSequenceRunsRemote requires a remote (NetworkBackend) repository',
      );
    }
    final runs = await fetchAllRemoteSequenceRuns(remote);
    return runs.map(_sequenceRunFromRemote).toList();
  }

  /// Remote-only: target id -> name map from the host's `/api/targets` list, so
  /// the session report resolves real target names instead of falling back to
  /// "Target N" against the slave's empty local `targets` table. Throws when
  /// called on a local repository (callers branch on [isRemote] first).
  Future<Map<int, String>> getTargetNamesRemote() async {
    final remote = _remote;
    if (remote == null) {
      throw StateError(
        'getTargetNamesRemote requires a remote (NetworkBackend) repository',
      );
    }
    final rows = await remote.getAllTargets();
    final out = <int, String>{};
    for (final row in rows) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      final name = row['name'] as String?;
      if (name != null && name.isNotEmpty) out[id] = name;
    }
    return out;
  }

  Future<int> startSession({
    String? name,
    int? profileId,
    int? targetId,
    int? sequenceId,
  }) async {
    if (_remote != null) {
      return _remote.createSession({
        if (name != null) 'name': name,
        if (profileId != null) 'profileId': profileId,
        if (targetId != null) 'targetId': targetId,
        if (sequenceId != null) 'sequenceId': sequenceId,
      });
    }
    return _sessionsDao!.startSession(
      name: name,
      profileId: profileId,
      targetId: targetId,
      sequenceId: sequenceId,
    );
  }

  Future<void> endSession(int id, {String status = 'completed'}) async {
    if (_remote != null) {
      await _remote.endSession(id, status: status);
      return;
    }
    await _sessionsDao!.endSession(id, status: status);
  }

  /// Record the equipment this session is running with, so the Continue
  /// Session handoff can re-apply it on the next launch.
  ///
  /// Host-only on purpose: on a paired companion the session row lives on the
  /// appliance, and the equipment state worth restoring is the appliance's —
  /// which its own executor stamps. Writing the phone's device state onto a
  /// local row nothing reads would be a second, wrong source.
  Future<void> updateEquipmentSnapshot(int id, String snapshotJson) async {
    if (_remote != null) return;
    await _sessionsDao!.updateEquipmentSnapshot(id, snapshotJson);
  }

  /// Close a session that was abandoned, back-dating `end_time` to its last
  /// captured frame. See [SessionsDao.abortSession] for why the recovery
  /// clock is the wrong timestamp to record.
  ///
  /// The remote branch is the companion asking the HOST to close one of the
  /// host's sessions; the host runs its own recovery against its own DAO, so
  /// the back-dating happens there.
  Future<void> abortSession(int id) async {
    if (_remote != null) {
      await _remote.endSession(id, status: 'aborted');
      return;
    }
    await _sessionsDao!.abortSession(id);
  }

  Future<void> updateSessionStats(
    int id, {
    int? totalExposures,
    int? successfulExposures,
    int? failedExposures,
    double? totalIntegrationSecs,
    double? avgHfr,
    double? avgGuidingRms,
    int? autofocusCount,
  }) async {
    if (_remote != null) {
      await _remote.updateSession(id, {
        if (totalExposures != null) 'totalExposures': totalExposures,
        if (successfulExposures != null)
          'successfulExposures': successfulExposures,
        if (failedExposures != null) 'failedExposures': failedExposures,
        if (totalIntegrationSecs != null)
          'totalIntegrationSecs': totalIntegrationSecs,
        if (avgHfr != null) 'avgHfr': avgHfr,
        if (avgGuidingRms != null) 'avgGuidingRms': avgGuidingRms,
        if (autofocusCount != null) 'autofocusCount': autofocusCount,
      });
      return;
    }
    await _sessionsDao!.updateSessionStats(
      id,
      totalExposures: totalExposures,
      successfulExposures: successfulExposures,
      failedExposures: failedExposures,
      totalIntegrationSecs: totalIntegrationSecs,
      avgHfr: avgHfr,
      avgGuidingRms: avgGuidingRms,
      autofocusCount: autofocusCount,
    );
  }

  Future<void> updateSessionNotes(int id, String notes) async {
    if (_remote != null) {
      await _remote.updateSession(id, {'notes': notes});
      return;
    }
    await _sessionsDao!.updateNotes(id, notes);
  }

  // ---------------------------------------------------------------------------
  // Captured images
  // ---------------------------------------------------------------------------

  Future<db.CapturedImage?> getImageById(int id) async {
    if (_remote != null) {
      final row = await _remote.getCapturedImageById(id);
      return row == null ? null : db.CapturedImage.fromJson(row);
    }
    return _imagesDao!.getImageById(id);
  }

  Future<List<db.CapturedImage>> getImagesForSession(int sessionId) async {
    if (_remote != null) {
      final rows = await _remote.getSessionImageRows(sessionId);
      return rows.map(db.CapturedImage.fromJson).toList();
    }
    return _imagesDao!.getImagesForSession(sessionId);
  }

  Future<List<db.CapturedImage>> getImagesForTarget(int targetId) async {
    if (_remote != null) {
      final rows = await _remote.getImagesForTarget(targetId);
      return rows.map(db.CapturedImage.fromJson).toList();
    }
    return _imagesDao!.getImagesForTarget(targetId);
  }

  Future<List<db.CapturedImage>> getRecentImagesForSession(
    int sessionId, {
    int limit = 5,
  }) async {
    if (_remote != null) {
      final rows = await _remote.getSessionImageRows(sessionId);
      final images = rows.map(db.CapturedImage.fromJson).toList()
        ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
      if (images.length <= limit) {
        return images;
      }
      return images.sublist(0, limit);
    }
    return _imagesDao!.getRecentImagesForSession(sessionId, limit: limit);
  }

  Stream<List<db.CapturedImage>> watchImagesForSession(int sessionId) {
    if (_remote != null) {
      return _pollRemoteSessionImages(
        _remote,
        sessionId,
        interval: _remotePollInterval,
      );
    }
    return _imagesDao!.watchImagesForSession(sessionId);
  }

  Future<int> createImage(db.CapturedImagesCompanion image) async {
    if (_remote != null) {
      return _remote.createCapturedImage(_companionToCreateJson(image));
    }
    return _imagesDao!.createImage(image);
  }

  Future<void> updateImageFilePath(int id, String filePath) async {
    if (_remote != null) {
      await _remote.updateCapturedImage(id, {'filePath': filePath});
      return;
    }
    await _imagesDao!.updateImageFilePath(id, filePath);
  }

  Future<void> rejectImage(int id, String reason) async {
    if (_remote != null) {
      await _remote.updateCapturedImage(id, {
        'isAccepted': false,
        'rejectionReason': reason,
      });
      return;
    }
    await _imagesDao!.rejectImage(id, reason);
  }

  Future<void> acceptImage(int id) async {
    if (_remote != null) {
      await _remote.updateCapturedImage(id, {
        'isAccepted': true,
        'rejectionReason': null,
      });
      return;
    }
    await _imagesDao!.acceptImage(id);
  }

  Future<void> updatePlateSolveResult(
    int id, {
    required double solvedRa,
    required double solvedDec,
    required double solvedRotation,
    required double solvedPixelScale,
    double? solvedCd1_1,
    double? solvedCd1_2,
    double? solvedCd2_1,
    double? solvedCd2_2,
    String? solvedSip,
  }) async {
    final hasCd =
        solvedCd1_1 != null &&
        solvedCd1_2 != null &&
        solvedCd2_1 != null &&
        solvedCd2_2 != null;
    if (_remote != null) {
      await _remote.updateCapturedImage(id, {
        'isPlateSolved': true,
        'solvedRa': solvedRa,
        'solvedDec': solvedDec,
        'solvedRotation': solvedRotation,
        'solvedPixelScale': solvedPixelScale,
        if (hasCd) 'solvedCd1_1': solvedCd1_1,
        if (hasCd) 'solvedCd1_2': solvedCd1_2,
        if (hasCd) 'solvedCd2_1': solvedCd2_1,
        if (hasCd) 'solvedCd2_2': solvedCd2_2,
        if (hasCd) 'solvedSip': solvedSip,
      });
      return;
    }
    await _imagesDao!.updatePlateSolveResult(
      id,
      solvedRa: solvedRa,
      solvedDec: solvedDec,
      solvedRotation: solvedRotation,
      solvedPixelScale: solvedPixelScale,
      solvedCd1_1: solvedCd1_1,
      solvedCd1_2: solvedCd1_2,
      solvedCd2_1: solvedCd2_1,
      solvedCd2_2: solvedCd2_2,
      solvedSip: solvedSip,
    );

    // Pillar A ("Your Sky"): fold the freshly solved light into the personal
    // sky atlas. Best-effort and fire-and-forget — a fold failure must never
    // roll back the solve persist or surface to the imaging path. The hook
    // owns its own error handling; this guard is defensive belt-and-braces.
    final foldHook = _onSolvedFrameFold;
    if (foldHook != null) {
      unawaited(
        foldHook(id).catchError((Object _) {
          // Swallowed: the atlas fold is an enhancement on top of the solve,
          // not a precondition for it. Errors are logged inside the hook.
        }),
      );
    }
  }

  /// Read the off-table v51 WCS distortion (CD matrix + SIP JSON) for [id].
  /// Returns null in remote mode (the appliance owns the authoritative DB)
  /// or when the row is absent; absent CD/SIP fields mean an isotropic solve.
  Future<
    ({double? cd1_1, double? cd1_2, double? cd2_1, double? cd2_2, String? sip})?
  >
  getStoredWcsDistortion(int id) async {
    if (_remote != null) return null;
    return _imagesDao!.getStoredWcsDistortion(id);
  }

  Future<void> stampProducingNode({
    required int imageId,
    String? producingNodeId,
    String? producingRunId,
    String? runtimeGrade,
    double? eccentricity,
    double? fwhm,
  }) async {
    if (_remote != null) {
      await _remote.updateCapturedImage(imageId, {
        if (producingNodeId != null) 'producingNodeId': producingNodeId,
        if (producingRunId != null) 'producingRunId': producingRunId,
        if (runtimeGrade != null) 'runtimeGrade': runtimeGrade,
        if (eccentricity != null) 'eccentricity': eccentricity,
        if (fwhm != null) 'fwhm': fwhm,
      });
      return;
    }
    await _imagesDao!.stampProducingNode(
      imageId: imageId,
      producingNodeId: producingNodeId,
      producingRunId: producingRunId,
      runtimeGrade: runtimeGrade,
      eccentricity: eccentricity,
      fwhm: fwhm,
    );
  }

  Future<List<ProducingNodeThumbnail>> getImagesByProducingNode({
    required String producingNodeId,
    String? producingRunId,
    int limit = 100,
  }) async {
    if (_remote != null) {
      final rows = await _remote.getImagesByProducingNode(
        producingNodeId,
        producingRunId: producingRunId,
        limit: limit,
      );
      return rows.map(_producingThumbnailFromApiJson).toList();
    }
    return _imagesDao!.getImagesByProducingNode(
      producingNodeId: producingNodeId,
      producingRunId: producingRunId,
      limit: limit,
    );
  }

  Stream<List<ProducingNodeThumbnail>> watchImagesByProducingNode({
    required String producingNodeId,
    String? producingRunId,
    int limit = 100,
  }) {
    if (_remote != null) {
      return _pollRemoteProducingNodeThumbnails(
        _remote,
        producingNodeId: producingNodeId,
        producingRunId: producingRunId,
        limit: limit,
        interval: _remotePollInterval,
      );
    }
    return _imagesDao!.watchImagesByProducingNode(
      producingNodeId: producingNodeId,
      producingRunId: producingRunId,
      limit: limit,
    );
  }

  Future<int> countImagesByProducingNode({
    required String producingNodeId,
    String? producingRunId,
  }) async {
    if (_remote != null) {
      final rows = await _remote.getImagesByProducingNode(
        producingNodeId,
        producingRunId: producingRunId,
      );
      return rows.length;
    }
    return _imagesDao!.countImagesByProducingNode(
      producingNodeId: producingNodeId,
      producingRunId: producingRunId,
    );
  }

  /// Map a `/api/sequence-runs` wire row onto the local Drift `SequenceRun`
  /// shape the report builder reads. `statsJson` carries the mount/op counts
  /// and error/warning lists the report parses; the snapshot column is not
  /// exposed by the endpoint and the report does not read it.
  static db.SequenceRun _sequenceRunFromRemote(RemoteSequenceRun run) {
    return db.SequenceRun(
      id: run.id,
      sequenceId: run.sequenceId,
      sequenceName: run.sequenceName ?? 'Sequence',
      startedAt: run.startedAt,
      endedAt: run.endedAt,
      status: run.status,
      statsJson: run.statsJson ?? '{}',
      sequenceSnapshotJson: null,
    );
  }

  static Map<String, dynamic> _companionToCreateJson(
    db.CapturedImagesCompanion companion,
  ) {
    T? read<T>(Value<T?> field) => field.present ? field.value : null;

    final capturedAt = read(companion.capturedAt);
    if (capturedAt == null) {
      throw ArgumentError(
        'capturedAt is required when creating a captured image',
      );
    }

    return {
      'filePath': read(companion.filePath)!,
      'fileName': read(companion.fileName)!,
      'fileFormat': read(companion.fileFormat) ?? 'fits',
      'fileSize': read(companion.fileSize),
      'sessionId': read(companion.sessionId),
      'targetId': read(companion.targetId),
      'frameType': read(companion.frameType)!,
      'exposureDuration': read(companion.exposureDuration)!,
      'gain': read(companion.gain),
      'offset': read(companion.offset),
      'binX': read(companion.binX) ?? 1,
      'binY': read(companion.binY) ?? 1,
      'filter': read(companion.filter),
      'sensorTemp': read(companion.sensorTemp),
      'coolerPower': read(companion.coolerPower),
      'hfr': read(companion.hfr),
      'starCount': read(companion.starCount),
      'background': read(companion.background),
      'noise': read(companion.noise),
      'qualityScore': read(companion.qualityScore),
      'guidingRmsRa': read(companion.guidingRmsRa),
      'guidingRmsDec': read(companion.guidingRmsDec),
      'guidingRmsTotal': read(companion.guidingRmsTotal),
      'mountRa': read(companion.mountRa),
      'mountDec': read(companion.mountDec),
      'mountAltitude': read(companion.mountAltitude),
      'mountAzimuth': read(companion.mountAzimuth),
      'pierSide': read(companion.pierSide),
      'focuserPosition': read(companion.focuserPosition),
      'focuserTemp': read(companion.focuserTemp),
      'rotatorAngle': read(companion.rotatorAngle),
      'isPlateSolved': read(companion.isPlateSolved) ?? false,
      'solvedRa': read(companion.solvedRa),
      'solvedDec': read(companion.solvedDec),
      'solvedRotation': read(companion.solvedRotation),
      'solvedPixelScale': read(companion.solvedPixelScale),
      'capturedAt': capturedAt.millisecondsSinceEpoch,
      'isAccepted': read(companion.isAccepted) ?? true,
      'rejectionReason': read(companion.rejectionReason),
    };
  }

  static Stream<List<db.CapturedImage>> _pollRemoteSessionImages(
    NetworkBackend backend,
    int sessionId, {
    required Duration interval,
  }) => _pollRemoteDistinct(
    () => _fetchRemoteSessionImages(backend, sessionId),
    listEquals,
    interval: interval,
  );

  static Future<List<db.CapturedImage>> _fetchRemoteSessionImages(
    NetworkBackend backend,
    int sessionId,
  ) async {
    final rows = await backend.getSessionImageRows(sessionId);
    final mapped = rows.map(db.CapturedImage.fromJson).toList();
    mapped.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return mapped;
  }

  static Stream<List<ProducingNodeThumbnail>>
  _pollRemoteProducingNodeThumbnails(
    NetworkBackend backend, {
    required String producingNodeId,
    String? producingRunId,
    int limit = 100,
    required Duration interval,
  }) => _pollRemoteDistinct(
    () => _fetchRemoteProducingNodeThumbnails(
      backend,
      producingNodeId: producingNodeId,
      producingRunId: producingRunId,
      limit: limit,
    ),
    _thumbnailListsEqual,
    interval: interval,
  );

  static Future<List<ProducingNodeThumbnail>>
  _fetchRemoteProducingNodeThumbnails(
    NetworkBackend backend, {
    required String producingNodeId,
    String? producingRunId,
    int limit = 100,
  }) async {
    final rows = await backend.getImagesByProducingNode(
      producingNodeId,
      producingRunId: producingRunId,
      limit: limit,
    );
    return rows.map(_producingThumbnailFromApiJson).toList();
  }

  static Stream<T> _pollRemoteDistinct<T>(
    Future<T> Function() fetch,
    bool Function(T previous, T next) unchanged, {
    required Duration interval,
  }) => resilientDistinctPoll(
    fetch: fetch,
    unchanged: unchanged,
    interval: interval,
    onRetainedError: (error, stackTrace) {
      developer.log(
        'Remote imaging-record poll failed; retaining last value',
        name: 'ImagingRecordsRepository',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    },
  );
}

/// Decode a `/api/sessions` wire row into the Drift [db.ImagingSession] shape.
///
/// One copy on purpose: this repository and the remote `databaseProvider`
/// streams hydrate the same endpoint into the same row, and two hand-maintained
/// copies of one wire contract drift apart silently.
db.ImagingSession imagingSessionFromWireJson(Map<String, dynamic> json) {
  return db.ImagingSession(
    id: json['id'] as int,
    name: json['name'] as String?,
    profileId: json['profileId'] as int?,
    targetId: json['targetId'] as int?,
    startTime: wireTimestamp(json['startTime']),
    endTime: json['endTime'] == null ? null : wireTimestamp(json['endTime']),
    totalExposures: json['totalExposures'] as int? ?? 0,
    successfulExposures: json['successfulExposures'] as int? ?? 0,
    failedExposures: json['failedExposures'] as int? ?? 0,
    totalIntegrationSecs:
        (json['totalIntegrationSecs'] as num?)?.toDouble() ?? 0.0,
    avgTemperature: (json['avgTemperature'] as num?)?.toDouble(),
    avgHumidity: (json['avgHumidity'] as num?)?.toDouble(),
    avgSeeing: (json['avgSeeing'] as num?)?.toDouble(),
    avgHfr: (json['avgHfr'] as num?)?.toDouble(),
    avgGuidingRms: (json['avgGuidingRms'] as num?)?.toDouble(),
    autofocusCount: json['autofocusCount'] as int? ?? 0,
    notes: json['notes'] as String?,
    status: json['status'] as String? ?? 'completed',
    sequenceId: json['sequenceId'] as int?,
    equipmentSnapshot: json['equipmentSnapshot'] as String?,
  );
}

/// Coerce a wire timestamp — epoch milliseconds or ISO-8601 — into a
/// [DateTime], falling back to the epoch for anything else.
///
/// The string form routes through [tryParseUtcTimestamp] because
/// `DateTime.tryParse` reads an offset-less ISO string as *local* time: a phone
/// in a different timezone than the appliance would otherwise render every
/// session start/end shifted by the offset delta, with no error. The host emits
/// both shapes across its endpoints, so the coercion has to be safe for both.
DateTime wireTimestamp(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return tryParseUtcTimestamp(value) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

bool _thumbnailListsEqual(
  List<ProducingNodeThumbnail> previous,
  List<ProducingNodeThumbnail> next,
) {
  if (identical(previous, next)) return true;
  if (previous.length != next.length) return false;
  for (var index = 0; index < previous.length; index++) {
    final a = previous[index];
    final b = next[index];
    if (a.id != b.id ||
        a.filePath != b.filePath ||
        a.fileName != b.fileName ||
        a.filter != b.filter ||
        a.frameType != b.frameType ||
        a.hfr != b.hfr ||
        a.eccentricity != b.eccentricity ||
        a.fwhm != b.fwhm ||
        a.starCount != b.starCount ||
        a.exposureDuration != b.exposureDuration ||
        a.capturedAt != b.capturedAt ||
        a.isAccepted != b.isAccepted ||
        a.rejectionReason != b.rejectionReason ||
        a.runtimeGrade != b.runtimeGrade ||
        a.producingNodeId != b.producingNodeId ||
        a.producingRunId != b.producingRunId) {
      return false;
    }
  }
  return true;
}

ProducingNodeThumbnail _producingThumbnailFromApiJson(
  Map<String, dynamic> json,
) {
  final image = db.CapturedImage.fromJson(json);
  return ProducingNodeThumbnail(
    id: image.id,
    filePath: image.filePath,
    fileName: image.fileName,
    filter: image.filter,
    frameType: image.frameType,
    hfr: image.hfr,
    eccentricity: (json['eccentricity'] as num?)?.toDouble(),
    fwhm: (json['fwhm'] as num?)?.toDouble(),
    starCount: image.starCount,
    exposureDuration: image.exposureDuration,
    capturedAt: image.capturedAt,
    isAccepted: image.isAccepted,
    rejectionReason: image.rejectionReason,
    runtimeGrade: json['runtimeGrade'] as String?,
    producingNodeId: json['producingNodeId'] as String? ?? '',
    producingRunId: json['producingRunId'] as String?,
  );
}

/// Repository provider — local DAOs or remote host API.
///
/// The Pillar A ("Your Sky") fold-dedup gate, factored out of the local
/// solve-persist hook so the production path and its regression test exercise
/// the SAME logic instead of a re-implementation.
///
/// Contract: fold the freshly-solved [image] into the personal sky atlas only
/// when it has not already been folded ([db.CapturedImage.atlasFoldedAt] is
/// null), and stamp the dedup marker only after a fold that actually ran
/// (a null summary means the row was not foldable — e.g. no invertible WCS —
/// so the marker stays unset and a later, better solve can still fold it).
/// Returns the fold summary, or null when skipped/not foldable.
@visibleForTesting
Future<AtlasFoldSummary?> applyAtlasFoldDedup({
  required db.CapturedImage image,
  required ImagesDao imagesDao,
  required SkyAtlasService atlas,
  required int imageWidth,
  required int imageHeight,
  SolvedWcsDistortion distortion = const SolvedWcsDistortion(),
}) async {
  if (image.atlasFoldedAt != null) return null; // already folded — dedup
  final summary = await atlas.autoFoldCapturedImage(
    image: image,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    distortion: distortion,
  );
  if (summary != null) {
    await imagesDao.stampAtlasFolded(image.id);
  }
  return summary;
}

/// In local mode the repository is wired with the Pillar A ("Your Sky") fold
/// hook: every solve persisted through [ImagingRecordsRepository.updatePlateSolveResult]
/// auto-folds that light into the personal sky atlas. The hook reads the stored
/// WCS distortion + the frame's FITS dimensions, then delegates to
/// [SkyAtlasService.autoFoldCapturedImage]; remote companions skip it (the
/// appliance host owns the authoritative atlas).
final imagingRecordsRepositoryProvider = Provider<ImagingRecordsRepository>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ImagingRecordsRepository.remote(backend);
  }
  final imagesDao = ref.watch(imagesDaoProvider);
  return ImagingRecordsRepository.local(
    sessionsDao: ref.watch(sessionsDaoProvider),
    imagesDao: imagesDao,
    onSolvedFrameFold: (capturedImageId) async {
      final logger = ref.read(loggingServiceProvider);
      try {
        final image = await imagesDao.getImageById(capturedImageId);
        if (image == null) return;
        final fits = await apiReadFitsFile(filePath: image.filePath);
        final stored = await imagesDao.getStoredWcsDistortion(capturedImageId);
        final sip = decodeSolvedSip(stored?.sip);
        final distortion = SolvedWcsDistortion(
          cd1_1: stored?.cd1_1,
          cd1_2: stored?.cd1_2,
          cd2_1: stored?.cd2_1,
          cd2_2: stored?.cd2_2,
          aOrder: sip?.aOrder ?? 0,
          bOrder: sip?.bOrder ?? 0,
          aCoeffs: sip?.aCoeffs ?? const [],
          bCoeffs: sip?.bCoeffs ?? const [],
          apOrder: sip?.apOrder ?? 0,
          bpOrder: sip?.bpOrder ?? 0,
          apCoeffs: sip?.apCoeffs ?? const [],
          bpCoeffs: sip?.bpCoeffs ?? const [],
        );

        // Pillar B ("First Light"): the SAME solve-persist event that folds the
        // light into the atlas also differences it against the comparison
        // template and logs any transient. Gated on a light frame with a valid,
        // invertible WCS; the scan itself no-ops (skips thin tiles) until a deep
        // template exists, so an early-night frame over a sparse tile is cheap.
        //
        // ORDER IS LOAD-BEARING (Wave 1 self-subtraction fix): the scan MUST run
        // BEFORE the atlas fold below. The diff template is read from the SAME
        // per-tile `.nst` sidecars the fold writes into, so folding first would
        // average this frame's own flux into the template it is differenced
        // against (weight ~1/(N+1)) — every transient would self-suppress and
        // faint SNR~5-6 sources would drop below the persist gate and vanish.
        // Running the scan first means the template = history (all PRIOR frames
        // only); the fold then deepens the template for the NEXT frame.
        // A future refactor MUST NOT reorder fold above scan.
        await _runFirstLightScan(
          ref: ref,
          logger: logger,
          image: image,
          imageWidth: fits.width,
          imageHeight: fits.height,
          distortion: distortion,
        );

        // Fold dedup (Wave 0): a re-solved frame fires this hook again with the
        // same captured-image id. The gate (extracted to [applyAtlasFoldDedup]
        // so the production path and its regression test run the SAME logic)
        // folds only when the row is not already stamped, and stamps only after
        // a fold that actually ran.
        final foldSummary = await applyAtlasFoldDedup(
          image: image,
          imagesDao: imagesDao,
          atlas: ref.read(skyAtlasServiceProvider),
          imageWidth: fits.width,
          imageHeight: fits.height,
          distortion: distortion,
        );

        // Collaborative Sky WS3 Gap 2 — live co-imaging auto-contribute: a fold
        // that ACTUALLY ran (non-null summary) means this rig's own-light delta
        // is now in the atlas, so any live co-imaging session whose target this
        // frame covers can fold the SAME sub into the shared-target tile and
        // advance the combined accounting. Ordering is load-bearing: contributing
        // only AFTER the atlas fold lands is what makes the additive-sum export
        // non-empty, so the headline depth tracks real fused depth (no undercount
        // race). A non-fold (re-solve / not foldable) skips — the sub was already
        // contributed on its first fold.
        if (foldSummary != null) {
          await _driveCoImagingAutoContribute(
            ref: ref,
            logger: logger,
            image: image,
          );
        }
      } catch (e, st) {
        logger.warning(
          'Sky-atlas auto-fold for image $capturedImageId failed: $e\n$st',
          source: 'SkyAtlasService',
        );
      }
    },
  );
});

/// Collaborative Sky WS3 Gap 2 — drive the live co-imaging auto-contribute for a
/// freshly-folded light frame. For every active co-imaging membership whose
/// session target this frame's solved centre covers, fold the same sub into the
/// shared-target tile and advance the COMBINED accounting via
/// [CoImagingSessionService.recordCompletedSub] (which itself fuses, then
/// reports the TRUE pushed delta, under the operator's persisted consent and
/// failing closed when none is on record).
///
/// Best-effort and self-contained: a no-hub config, no covering session, or any
/// per-session failure is logged and swallowed so it never disturbs the
/// solve/fold path. `solvedRa` is app-canonical HOURS; the matcher works in
/// degrees, so it is converted at the boundary.
Future<void> _driveCoImagingAutoContribute({
  required Ref ref,
  required LoggingService logger,
  required db.CapturedImage image,
}) async {
  if (image.frameType.toLowerCase() != 'light' || !image.isAccepted) return;
  final ra = image.solvedRa;
  final dec = image.solvedDec;
  if (ra == null || dec == null) return;
  try {
    final coImaging = ref.read(coImagingSessionServiceProvider);
    final memberships = await coImaging.membershipsForPoint(
      raDeg: ra * 15.0,
      decDeg: dec,
    );
    for (final row in memberships) {
      try {
        final accounting = await coImaging.recordCompletedSub(
          row.sessionId,
          exposureSeconds: image.exposureDuration,
        );
        if (accounting != null) {
          logger.info(
            'Co-imaging: sub folded into session ${row.sessionId}; combined '
            'now ${accounting.combinedFrames} frames across '
            '${accounting.participantCount} rig(s).',
            source: 'CoImagingSessionService',
          );
        }
      } catch (e) {
        logger.warning(
          'Co-imaging auto-contribute for session ${row.sessionId} failed: $e',
          source: 'CoImagingSessionService',
        );
      }
    }
  } catch (e) {
    logger.warning(
      'Co-imaging auto-contribute resolve failed: $e',
      source: 'CoImagingSessionService',
    );
  }
}

/// The WCS the Pillar B ("First Light") difference scan runs a solved frame
/// against.
///
/// `captured_images.solvedRa` is app-canonical **hours** on both the write side
/// (the science pipeline persists `SolvedResult.raHours`) and every other read
/// side, so the centre is carried across unconverted — it must land on the same
/// sky tiles [SkyAtlasService.autoFoldCapturedImage] folds the frame into, and
/// that builds its own centre from the identical column.
///
/// Callers guard `solvedRa`/`solvedDec`/`solvedPixelScale` before calling.
@visibleForTesting
SolvedWcs firstLightScanWcs({
  required db.CapturedImage image,
  required int imageWidth,
  required int imageHeight,
  required SolvedWcsDistortion distortion,
  DecodedSip? sip,
}) {
  return SolvedWcs(
    raHours: image.solvedRa!,
    decDegrees: image.solvedDec!,
    rotationDeg: image.solvedRotation ?? 0.0,
    pixelScaleArcsec: image.solvedPixelScale!,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    cd1_1: distortion.cd1_1,
    cd1_2: distortion.cd1_2,
    cd2_1: distortion.cd2_1,
    cd2_2: distortion.cd2_2,
    aOrder: sip?.aOrder ?? 0,
    bOrder: sip?.bOrder ?? 0,
    aCoeffs: sip?.aCoeffs ?? const [],
    bCoeffs: sip?.bCoeffs ?? const [],
    apOrder: sip?.apOrder ?? 0,
    bpOrder: sip?.bpOrder ?? 0,
    apCoeffs: sip?.apCoeffs ?? const [],
    bpCoeffs: sip?.bpCoeffs ?? const [],
  );
}

/// Run the Pillar B difference scan for a freshly-solved light frame, persist any
/// transients, and feed the survivors to the active-session Narrator so its
/// First Light detectors can announce them. Best-effort and self-contained: any
/// failure is logged and swallowed so it never disturbs the solve/fold path.
Future<void> _runFirstLightScan({
  required Ref ref,
  required LoggingService logger,
  required db.CapturedImage image,
  required int imageWidth,
  required int imageHeight,
  required SolvedWcsDistortion distortion,
}) async {
  // Only difference real light frames (a solved flat/dark would be nonsense).
  if (image.frameType.toLowerCase() != 'light') return;
  final ra = image.solvedRa;
  final dec = image.solvedDec;
  final scale = image.solvedPixelScale;
  if (ra == null || dec == null || scale == null || scale <= 0) return;

  final sip = decodeSolvedSip(
    await ref
        .read(imagesDaoProvider)
        .getStoredWcsDistortion(image.id)
        .then((w) => w?.sip),
  );
  final wcs = firstLightScanWcs(
    image: image,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    distortion: distortion,
    sip: sip,
  );
  if (!wcs.isValid) return;

  try {
    final rows = await ref
        .read(firstLightServiceProvider)
        .scanFrame(
          framePath: image.filePath,
          wcs: wcs,
          sessionId: image.sessionId,
          capturedImageId: image.id,
        );
    if (rows.isEmpty) return;
    // Feed the freshly-detected transients to the active Narrator so the First
    // Light detectors (transient/brightening/mover) can announce them.
    final candidates = rows.map(_candidateFromRow).toList(growable: false);
    ref
        .read(narratorServiceProvider)
        .ingestTransientCandidates(candidates, capturedImageId: image.id);
    // Bridge a genuinely-new discovery to the push router so a sleeping
    // operator is paged while the chase window is still open. The in-app
    // Narrator banner alone is invisible at night.
    _pushTransientDiscoveries(ref, logger, rows);
  } catch (e, st) {
    logger.warning(
      'First Light scan for image ${image.id} failed: $e\n$st',
      source: 'FirstLightService',
    );
  }
}

/// Minimum confidence for a transient to escalate to a phone push. High enough
/// that the operator is only paged for a genuinely promising candidate (the
/// chase costs telescope time), not every marginal residual.
const double _kTransientPushConfidence = 0.7;

/// Route any high-confidence, unnamed, brand-new point source from a scan to the
/// notification router so it pushes to the operator's phone (the
/// `transientDiscovered` category is critical / systemPush-by-default). Only a
/// `newSource` with no catalog match qualifies as a possible-discovery worth a
/// page; a brightening of a known star, a mover, or a dipole artefact stays
/// in-app. Best-effort — a router failure must never disturb the solve path.
void _pushTransientDiscoveries(
  Ref ref,
  LoggingService logger,
  List<db.TransientDetectionRow> rows,
) {
  final discoveries = rows
      .where((r) {
        if (r.catalogMatch != null) return false;
        if (r.confidence < _kTransientPushConfidence) return false;
        return TransientKind.fromWire(r.kind) == TransientKind.newSource;
      })
      .toList(growable: false);
  if (discoveries.isEmpty) return;

  try {
    final router = ref.read(notificationRouterProvider);
    for (final r in discoveries) {
      final coords =
          '${CoordinateFormat.ra(r.raDeg / 15.0)} ${CoordinateFormat.dec(r.decDeg)}';
      router.route(NotificationCategory.transientDiscovered, {
        'transient.coords': coords,
        'transient.snr': r.snr.toStringAsFixed(1),
        'transient.confidence': (r.confidence * 100).round().toString(),
      }, severity: EventSeverity.critical);
    }
  } catch (e, st) {
    logger.warning(
      'First Light push routing failed: $e\n$st',
      source: 'FirstLightService',
    );
  }
}

/// Reconstruct a [TransientCandidate] from a persisted detection row for the
/// Narrator feed. The tile pixel coordinates are not stored on the row (they are
/// a native-only intermediate), so they default to 0 — the detectors only read
/// sky position, SNR, deltaMag, kind, confidence, and eccentricity.
TransientCandidate _candidateFromRow(db.TransientDetectionRow row) {
  return TransientCandidate(
    ra: row.raDeg,
    dec: row.decDeg,
    tileId: row.tileId,
    tileX: 0,
    tileY: 0,
    residualFlux: row.residualFlux,
    deltaMag: row.deltaMag,
    snr: row.snr,
    fwhm: row.fwhm,
    eccentricity: row.eccentricity,
    positionAngleDeg: row.positionAngleDeg,
    kind: TransientKind.fromWire(row.kind),
    catalogMatch: row.catalogMatch,
    confidence: row.confidence,
  );
}

/// Persisted captured-image rows for one session (Drift watch or remote poll).
final sessionDbImagesProvider = StreamProvider.autoDispose
    .family<List<db.CapturedImage>, int>((ref, sessionId) {
      return ref
          .watch(imagingRecordsRepositoryProvider)
          .watchImagesForSession(sessionId);
    });
