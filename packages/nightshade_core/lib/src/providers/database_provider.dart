import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/network_backend.dart';
import '../database/database.dart' as db;
import '../database/daos/equipment_profiles_dao.dart';
import '../database/daos/targets_dao.dart';
import '../database/daos/sessions_dao.dart';
import '../database/daos/images_dao.dart';
import '../database/daos/sequences_dao.dart';
import '../database/daos/settings_dao.dart';
import '../database/daos/science_dao.dart';
import 'backend_provider.dart';

export 'project_tracking_provider.dart';

/// Global database instance provider
final databaseProvider = Provider<db.NightshadeDatabase>((ref) {
  final database = db.NightshadeDatabase();
  ref.onDispose(() => database.close());
  return database;
});

/// Equipment profiles DAO provider
final equipmentProfilesDaoProvider = Provider<EquipmentProfilesDao>((ref) {
  return EquipmentProfilesDao(ref.watch(databaseProvider));
});

/// Targets DAO provider
final targetsDaoProvider = Provider<TargetsDao>((ref) {
  return TargetsDao(ref.watch(databaseProvider));
});

/// Sessions DAO provider
final sessionsDaoProvider = Provider<SessionsDao>((ref) {
  return SessionsDao(ref.watch(databaseProvider));
});

/// Images DAO provider
final imagesDaoProvider = Provider<ImagesDao>((ref) {
  return ImagesDao(ref.watch(databaseProvider));
});

/// Sequences DAO provider
final sequencesDaoProvider = Provider<SequencesDao>((ref) {
  return SequencesDao(ref.watch(databaseProvider));
});

/// Settings DAO provider
final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return SettingsDao(ref.watch(databaseProvider));
});

/// Science DAO provider
final scienceDaoProvider = Provider<ScienceDao>((ref) {
  return ScienceDao(ref.watch(databaseProvider));
});

// ============================================================================
// Convenience providers for watching data
// Note: These use the database entity types (prefixed with db.)
// ============================================================================

/// Watch all equipment profiles
final allProfilesProvider = StreamProvider<List<db.EquipmentProfile>>((ref) {
  return ref.watch(equipmentProfilesDaoProvider).watchAllProfiles();
});

/// Watch the active equipment profile
final activeProfileProvider = StreamProvider<db.EquipmentProfile?>((ref) {
  return ref.watch(equipmentProfilesDaoProvider).watchActiveProfile();
});

/// Watch all targets (database entities)
final allDbTargetsProvider = StreamProvider<List<db.Target>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteTargets(backend);
  }
  return ref.watch(targetsDaoProvider).watchAllTargets();
});

/// Watch favorite targets (database entities)
final favoriteDbTargetsProvider = StreamProvider<List<db.Target>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteTargets(backend)
        .map((targets) => targets.where((target) => target.isFavorite).toList());
  }
  return ref.watch(targetsDaoProvider).watchFavoriteTargets();
});

/// Watch all sequences (database entities)
final allDbSequencesProvider = StreamProvider<List<db.Sequence>>((ref) {
  return ref.watch(sequencesDaoProvider).watchAllSequences();
});

/// Watch all sequence templates (database entities)
final allDbTemplatesProvider = StreamProvider<List<db.Sequence>>((ref) {
  return ref.watch(sequencesDaoProvider).watchAllTemplates();
});

/// Watch all imaging sessions
final allSessionsProvider = StreamProvider<List<db.ImagingSession>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteSessions(backend);
  }
  return ref.watch(sessionsDaoProvider).watchAllSessions();
});

/// Watch all captured images (database entities)
final allDbImagesProvider = StreamProvider<List<db.CapturedImage>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteImages(backend);
  }
  return ref.watch(imagesDaoProvider).watchAllImages();
});

/// Load a captured image row by id.
final capturedImageByIdProvider =
    FutureProvider.family<db.CapturedImage?, int>((ref, imageId) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return backend.getAllImageRows().then((rows) {
      for (final row in rows) {
        if ((row['id'] as int?) == imageId) {
          return _imageFromJson(row);
        }
      }
      return null;
    });
  }
  return ref.watch(imagesDaoProvider).getImageById(imageId);
});

class CapturedImageWcsData {
  final int id;
  final bool isPlateSolved;
  final double? solvedRaHours;
  final double? solvedDecDegrees;
  final double? solvedRotationDegrees;
  final double? solvedPixelScaleArcsecPerPixel;

  const CapturedImageWcsData({
    required this.id,
    required this.isPlateSolved,
    required this.solvedRaHours,
    required this.solvedDecDegrees,
    required this.solvedRotationDegrees,
    required this.solvedPixelScaleArcsecPerPixel,
  });
}

final capturedImageWcsProvider =
    FutureProvider.family<CapturedImageWcsData?, int>((ref, imageId) async {
  final row = await ref.watch(imagesDaoProvider).getImageById(imageId);
  if (row == null) {
    return null;
  }
  return CapturedImageWcsData(
    id: row.id,
    isPlateSolved: row.isPlateSolved,
    solvedRaHours: row.solvedRa,
    solvedDecDegrees: row.solvedDec,
    solvedRotationDegrees: row.solvedRotation,
    solvedPixelScaleArcsecPerPixel: row.solvedPixelScale,
  );
});

/// Watch all settings as a map
final allSettingsProvider = StreamProvider<Map<String, String>>((ref) {
  return ref.watch(settingsDaoProvider).watchAllSettings();
});

Stream<List<db.Target>> _pollRemoteTargets(NetworkBackend backend) async* {
  yield await _fetchRemoteTargets(backend);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteTargets(backend);
  }
}

Stream<List<db.ImagingSession>> _pollRemoteSessions(
  NetworkBackend backend,
) async* {
  yield await _fetchRemoteSessions(backend);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteSessions(backend);
  }
}

Stream<List<db.CapturedImage>> _pollRemoteImages(NetworkBackend backend) async* {
  yield await _fetchRemoteImages(backend);
  while (true) {
    await Future.delayed(const Duration(seconds: 10));
    yield await _fetchRemoteImages(backend);
  }
}

Future<List<db.Target>> _fetchRemoteTargets(NetworkBackend backend) async {
  final targets = await backend.getAllTargets();
  return targets.map(_targetFromJson).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
}

Future<List<db.ImagingSession>> _fetchRemoteSessions(
  NetworkBackend backend,
) async {
  final sessions = await backend.getAllSessions();
  final mapped = sessions.map(_sessionFromJson).toList();
  mapped.sort((a, b) => a.startTime.compareTo(b.startTime));
  return mapped;
}

Future<List<db.CapturedImage>> _fetchRemoteImages(NetworkBackend backend) async {
  final images = await backend.getAllImageRows();
  final mapped = images.map(_imageFromJson).toList();
  mapped.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  return mapped;
}

db.Target _targetFromJson(Map<String, dynamic> json) {
  return db.Target(
    id: json['id'] as int,
    name: json['name'] as String? ?? 'Untitled target',
    catalogId: json['catalogId'] as String?,
    objectType: json['objectType'] as String?,
    ra: (json['ra'] as num?)?.toDouble() ?? 0.0,
    dec: (json['dec'] as num?)?.toDouble() ?? 0.0,
    positionAngle: (json['positionAngle'] as num?)?.toDouble(),
    magnitude: (json['magnitude'] as num?)?.toDouble(),
    constellation: json['constellation'] as String?,
    sizeArcmin: (json['sizeArcmin'] as num?)?.toDouble(),
    minAltitude: (json['minAltitude'] as num?)?.toDouble() ?? 30.0,
    priority: json['priority'] as int? ?? 5,
    totalPlannedSubs: json['totalPlannedSubs'] as int? ?? 0,
    capturedSubs: json['capturedSubs'] as int? ?? 0,
    totalIntegrationSecs:
        (json['totalIntegrationSecs'] as num?)?.toDouble() ?? 0.0,
    goalIntegrationSecs:
        (json['goalIntegrationSecs'] as num?)?.toDouble() ?? 0.0,
    filterProgress: json['filterProgress'] as String?,
    notes: json['notes'] as String?,
    createdAt: _dateTimeFromJsonValue(json['createdAt']),
    updatedAt: _dateTimeFromJsonValue(json['updatedAt']),
    isFavorite: json['isFavorite'] as bool? ?? false,
  );
}

db.ImagingSession _sessionFromJson(Map<String, dynamic> json) {
  return db.ImagingSession(
    id: json['id'] as int,
    name: json['name'] as String?,
    profileId: json['profileId'] as int?,
    targetId: json['targetId'] as int?,
    startTime: _dateTimeFromJsonValue(json['startTime']),
    endTime: json['endTime'] == null
        ? null
        : _dateTimeFromJsonValue(json['endTime']),
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

db.CapturedImage _imageFromJson(Map<String, dynamic> json) {
  return db.CapturedImage.fromJson(json);
}

DateTime _dateTimeFromJsonValue(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
