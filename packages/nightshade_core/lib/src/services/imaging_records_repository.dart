import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/database.dart' as db;
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';

/// Host-authoritative access to imaging sessions and captured-image rows.
///
/// Local [FfiBackend] / desktop UI uses Drift DAOs. Remote companions
/// ([NetworkBackend]) read and write through the headless REST API so
/// mobile never mutates an empty local SQLite catalog.
class ImagingRecordsRepository {
  final SessionsDao? _sessionsDao;
  final ImagesDao? _imagesDao;
  final NetworkBackend? _remote;

  ImagingRecordsRepository._({
    SessionsDao? sessionsDao,
    ImagesDao? imagesDao,
    NetworkBackend? remote,
  }) : _sessionsDao = sessionsDao,
       _imagesDao = imagesDao,
       _remote = remote {
    assert(
      (sessionsDao != null && imagesDao != null && remote == null) ||
          (sessionsDao == null && imagesDao == null && remote != null),
      'ImagingRecordsRepository must be local (DAOs) or remote (NetworkBackend)',
    );
  }

  factory ImagingRecordsRepository.local({
    required SessionsDao sessionsDao,
    required ImagesDao imagesDao,
  }) => ImagingRecordsRepository._(
    sessionsDao: sessionsDao,
    imagesDao: imagesDao,
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
  }

  /// Read the off-table v51 WCS distortion (CD matrix + SIP JSON) for [id].
  /// Returns null in remote mode (the appliance owns the authoritative DB)
  /// or when the row is absent; absent CD/SIP fields mean an isotropic solve.
  Future<
    ({
      double? cd1_1,
      double? cd1_2,
      double? cd2_1,
      double? cd2_2,
      String? sip,
    })?
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
final imagingRecordsRepositoryProvider = Provider<ImagingRecordsRepository>((
  ref,
) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return ImagingRecordsRepository.remote(backend);
  }
  return ImagingRecordsRepository.local(
    sessionsDao: ref.watch(sessionsDaoProvider),
    imagesDao: ref.watch(imagesDaoProvider),
  );
});

/// Persisted captured-image rows for one session (Drift watch or remote poll).
final sessionDbImagesProvider = StreamProvider.autoDispose
    .family<List<db.CapturedImage>, int>((ref, sessionId) {
      return ref
          .watch(imagingRecordsRepositoryProvider)
          .watchImagesForSession(sessionId);
    });
