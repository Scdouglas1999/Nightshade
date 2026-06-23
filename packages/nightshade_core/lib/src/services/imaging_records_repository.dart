import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_bridge/nightshade_bridge.dart' show apiReadFitsFile;

import '../backend/network_backend.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/database.dart' as db;
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';
import '../providers/narrator_provider.dart' show narratorServiceProvider;
import '../providers/sky_atlas_provider.dart';
import '../providers/transient_detections_provider.dart';
import '../services/logging_service.dart';
import '../services/sky_atlas/sky_atlas_models.dart';
import '../services/transients/transient_candidate.dart';
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

  /// Optional sky-atlas fold hook, fired after a local plate-solve persist.
  final SolvedFrameFoldHook? _onSolvedFrameFold;

  ImagingRecordsRepository._({
    SessionsDao? sessionsDao,
    ImagesDao? imagesDao,
    NetworkBackend? remote,
    SolvedFrameFoldHook? onSolvedFrameFold,
  }) : _sessionsDao = sessionsDao,
       _imagesDao = imagesDao,
       _remote = remote,
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

  factory ImagingRecordsRepository.remote(NetworkBackend remote) =>
      ImagingRecordsRepository._(remote: remote);

  bool get isRemote => _remote != null;

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  Future<List<db.ImagingSession>> getAllSessions() async {
    if (_remote != null) {
      final rows = await _remote.getAllSessions();
      return rows.map(_sessionFromJson).toList();
    }
    return _sessionsDao!.getAllSessions();
  }

  Future<db.ImagingSession?> getSessionById(int id) async {
    if (_remote != null) {
      final row = await _remote.getSessionById(id);
      return row == null ? null : _sessionFromJson(row);
    }
    return _sessionsDao!.getSessionById(id);
  }

  Future<List<db.ImagingSession>> getSessionsForTarget(int targetId) async {
    if (_remote != null) {
      final rows = await _remote.getSessionsForTarget(targetId);
      return rows.map(_sessionFromJson).toList();
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
    final page = await remote.fetchSequenceRuns();
    return page.items.map(_sequenceRunFromRemote).toList();
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
      return _pollRemoteSessionImages(_remote, sessionId);
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

  static db.ImagingSession _sessionFromJson(Map<String, dynamic> json) {
    return db.ImagingSession(
      id: json['id'] as int,
      name: json['name'] as String?,
      profileId: json['profileId'] as int?,
      targetId: json['targetId'] as int?,
      startTime: _dateTimeFromJson(json['startTime']),
      endTime: json['endTime'] == null
          ? null
          : _dateTimeFromJson(json['endTime']),
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

  static DateTime _dateTimeFromJson(Object? value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
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
    int sessionId,
  ) async* {
    yield await _fetchRemoteSessionImages(backend, sessionId);
    while (true) {
      await Future.delayed(const Duration(seconds: 10));
      yield await _fetchRemoteSessionImages(backend, sessionId);
    }
  }

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
  }) async* {
    yield await _fetchRemoteProducingNodeThumbnails(
      backend,
      producingNodeId: producingNodeId,
      producingRunId: producingRunId,
      limit: limit,
    );
    while (true) {
      await Future.delayed(const Duration(seconds: 10));
      yield await _fetchRemoteProducingNodeThumbnails(
        backend,
        producingNodeId: producingNodeId,
        producingRunId: producingRunId,
        limit: limit,
      );
    }
  }

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

        // Fold dedup (Wave 0): a re-solved frame fires this hook again with the
        // same captured-image id. If the row was already folded into the atlas
        // (marker stamped), skip ONLY the fold so its photons are not
        // double-counted. First Light below still runs — its self-subtraction
        // dedup is Wave 1. The marker is stamped after a successful fold, so a
        // fold that throws leaves it unset and a retry can still fold.
        if (image.atlasFoldedAt == null) {
          final summary = await ref
              .read(skyAtlasServiceProvider)
              .autoFoldCapturedImage(
                image: image,
                imageWidth: fits.width,
                imageHeight: fits.height,
                distortion: distortion,
              );
          // Only stamp when a fold actually ran (null = not a foldable light /
          // no invertible WCS); leaving the marker unset lets a later, better
          // solve of the same row fold it then.
          if (summary != null) {
            await imagesDao.stampAtlasFolded(capturedImageId);
          }
        }

        // Pillar B ("First Light"): the SAME solve-persist event that folds the
        // light into the atlas also differences it against the now-deepened
        // template and logs any transient. Gated on a light frame with a valid,
        // invertible WCS; the scan itself no-ops (skips thin tiles) until a deep
        // template exists, so an early-night frame over a sparse tile is cheap.
        await _runFirstLightScan(
          ref: ref,
          logger: logger,
          image: image,
          imageWidth: fits.width,
          imageHeight: fits.height,
          distortion: distortion,
        );
      } catch (e, st) {
        logger.warning(
          'Sky-atlas auto-fold for image $capturedImageId failed: $e\n$st',
          source: 'SkyAtlasService',
        );
      }
    },
  );
});

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
  final wcs = SolvedWcs(
    raHours: ra / 15.0,
    decDegrees: dec,
    rotationDeg: image.solvedRotation ?? 0.0,
    pixelScaleArcsec: scale,
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
  } catch (e, st) {
    logger.warning(
      'First Light scan for image ${image.id} failed: $e\n$st',
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
