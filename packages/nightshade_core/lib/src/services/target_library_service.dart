import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../database/database.dart' as db;
import '../providers/backend_provider.dart';
import '../providers/database_provider.dart';
import 'catalog_target_resolver.dart';

/// Host-aware targets-library CRUD for planetarium and transient flows.
class TargetLibraryService {
  TargetLibraryService(this._ref);

  final Ref _ref;

  /// Creates a row in the targets library on the imaging host (remote) or
  /// local SQLite (FFI). Returns the new target id.
  Future<int> createTarget({
    required String name,
    required double raHours,
    required double decDegrees,
    String? catalogId,
    String? objectType,
    String? constellation,
    double? magnitude,
    double? sizeArcmin,
    double? positionAngle,
    double minAltitude = 30.0,
    String? notes,
    bool isFavorite = false,
    int priority = 5,
  }) async {
    final backend = _ref.read(backendProvider);
    if (backend is NetworkBackend) {
      final id = await backend.createTarget({
        'name': name,
        'ra': raHours,
        'dec': decDegrees,
        if (catalogId != null) 'catalogId': catalogId,
        if (objectType != null) 'objectType': objectType,
        if (constellation != null) 'constellation': constellation,
        if (magnitude != null) 'magnitude': magnitude,
        if (sizeArcmin != null) 'sizeArcmin': sizeArcmin,
        if (positionAngle != null) 'positionAngle': positionAngle,
        'minAltitude': minAltitude,
        if (notes != null) 'notes': notes,
        'isFavorite': isFavorite,
        'priority': priority,
      });
      _invalidateCatalog();
      return id;
    }

    final targetsDao = _ref.read(targetsDaoProvider);
    final id = await targetsDao.createTarget(
      db.TargetsCompanion.insert(
        name: name,
        catalogId: Value(catalogId),
        ra: raHours,
        dec: decDegrees,
        objectType: Value(objectType),
        constellation: Value(constellation),
        magnitude: Value(magnitude),
        sizeArcmin: Value(sizeArcmin),
        positionAngle: Value(positionAngle),
        minAltitude: Value(minAltitude),
        notes: Value(notes),
        isFavorite: Value(isFavorite),
        priority: Value(priority),
      ),
    );
    _invalidateCatalog();
    return id;
  }

  /// Resolves an existing library target or creates one on the host/local DB.
  Future<db.Target> ensureCatalogTarget({
    required String targetName,
    required double raHours,
    required double decDegrees,
    String? catalogId,
    String? objectType,
    String? constellation,
    double? magnitude,
    double? sizeArcmin,
  }) async {
    final candidates = await _ref.read(allDbTargetsProvider.future);
    final existing = resolveDbTargetForCatalog(
      candidates: candidates,
      targetName: targetName,
      catalogId: catalogId,
      raHours: raHours,
      decDegrees: decDegrees,
    );
    if (existing != null) {
      return existing;
    }

    final id = await createTarget(
      name: targetName,
      raHours: raHours,
      decDegrees: decDegrees,
      catalogId: catalogId ?? targetName,
      objectType: objectType,
      constellation: constellation,
      magnitude: magnitude,
      sizeArcmin: sizeArcmin,
    );

    final refreshed = await _ref.read(allDbTargetsProvider.future);
    for (final target in refreshed) {
      if (target.id == id) {
        return target;
      }
    }

    return db.Target(
      id: id,
      name: targetName,
      catalogId: catalogId ?? targetName,
      objectType: objectType,
      ra: raHours,
      dec: decDegrees,
      constellation: constellation,
      magnitude: magnitude,
      sizeArcmin: sizeArcmin,
      minAltitude: 30.0,
      priority: 5,
      totalPlannedSubs: 0,
      capturedSubs: 0,
      totalIntegrationSecs: 0,
      goalIntegrationSecs: 0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isFavorite: false,
    );
  }

  void _invalidateCatalog() {
    _ref.invalidate(allDbTargetsProvider);
    _ref.invalidate(favoriteDbTargetsProvider);
  }
}

final targetLibraryServiceProvider = Provider<TargetLibraryService>((ref) {
  return TargetLibraryService(ref);
});
