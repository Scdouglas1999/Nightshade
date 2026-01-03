import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/targets.dart';

part 'targets_dao.g.dart';

@DriftAccessor(tables: [Targets])
class TargetsDao extends DatabaseAccessor<NightshadeDatabase>
    with _$TargetsDaoMixin {
  TargetsDao(NightshadeDatabase db) : super(db);

  /// Get all targets
  Future<List<Target>> getAllTargets() => select(targets).get();

  /// Watch all targets
  Stream<List<Target>> watchAllTargets() => select(targets).watch();

  /// Get favorite targets
  Future<List<Target>> getFavoriteTargets() {
    return (select(targets)..where((t) => t.isFavorite.equals(true))).get();
  }

  /// Watch favorite targets
  Stream<List<Target>> watchFavoriteTargets() {
    return (select(targets)..where((t) => t.isFavorite.equals(true))).watch();
  }

  /// Get target by ID
  Future<Target?> getTargetById(int id) {
    return (select(targets)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Get target by catalog ID (e.g., M42, NGC7000)
  Future<Target?> getTargetByCatalogId(String catalogId) {
    return (select(targets)..where((t) => t.catalogId.equals(catalogId)))
        .getSingleOrNull();
  }

  /// Search targets by name
  Future<List<Target>> searchTargets(String query) {
    return (select(targets)
          ..where((t) => t.name.like('%$query%') | t.catalogId.like('%$query%')))
        .get();
  }

  /// Get targets by object type
  Future<List<Target>> getTargetsByType(String objectType) {
    return (select(targets)..where((t) => t.objectType.equals(objectType)))
        .get();
  }

  /// Create a new target
  Future<int> createTarget(TargetsCompanion target) {
    return into(targets).insert(target);
  }

  /// Update a target
  Future<bool> updateTarget(Target target) {
    return update(targets).replace(target);
  }

  /// Delete a target
  Future<int> deleteTarget(int id) {
    return (delete(targets)..where((t) => t.id.equals(id))).go();
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(int id) async {
    final target = await getTargetById(id);
    if (target != null) {
      await (update(targets)..where((t) => t.id.equals(id))).write(
        TargetsCompanion(isFavorite: Value(!target.isFavorite)),
      );
    }
  }

  /// Update imaging progress
  Future<void> updateProgress(int id, {
    int? capturedSubs,
    double? totalIntegrationSecs,
    String? filterProgress,
  }) async {
    final updates = TargetsCompanion(
      capturedSubs: capturedSubs != null ? Value(capturedSubs) : const Value.absent(),
      totalIntegrationSecs: totalIntegrationSecs != null
          ? Value(totalIntegrationSecs)
          : const Value.absent(),
      filterProgress: filterProgress != null
          ? Value(filterProgress)
          : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    );

    await (update(targets)..where((t) => t.id.equals(id))).write(updates);
  }

  /// Get targets ordered by priority
  Future<List<Target>> getTargetsByPriority() {
    return (select(targets)
          ..orderBy([(t) => OrderingTerm.desc(t.priority)]))
        .get();
  }

  /// Get targets that are observable tonight
  /// This is a simplified check - real implementation would calculate altitude
  Future<List<Target>> getObservableTargets(double latitude, double longitude) {
    // For now, return all targets
    // Real implementation would calculate current altitude and filter
    return getAllTargets();
  }
}





