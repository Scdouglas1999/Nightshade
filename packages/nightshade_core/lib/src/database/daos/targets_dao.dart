import 'dart:math' as math;

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
          ..where(
              (t) => t.name.like('%$query%') | t.catalogId.like('%$query%')))
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
    await customStatement(
      '''
      UPDATE targets
      SET
        is_favorite = CASE is_favorite WHEN 1 THEN 0 ELSE 1 END,
        updated_at = ?
      WHERE id = ?
      ''',
      [DateTime.now().millisecondsSinceEpoch ~/ 1000, id],
    );
  }

  /// Update imaging progress
  Future<void> updateProgress(
    int id, {
    int? capturedSubs,
    double? totalIntegrationSecs,
    double? goalIntegrationSecs,
    String? filterProgress,
  }) async {
    final updates = TargetsCompanion(
      capturedSubs:
          capturedSubs != null ? Value(capturedSubs) : const Value.absent(),
      totalIntegrationSecs: totalIntegrationSecs != null
          ? Value(totalIntegrationSecs)
          : const Value.absent(),
      goalIntegrationSecs: goalIntegrationSecs != null
          ? Value(goalIntegrationSecs)
          : const Value.absent(),
      filterProgress:
          filterProgress != null ? Value(filterProgress) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    );

    await (update(targets)..where((t) => t.id.equals(id))).write(updates);
  }

  /// Set the target's multi-night integration goal in seconds.
  Future<void> setGoalIntegrationSecs(
      int id, double goalIntegrationSecs) async {
    await (update(targets)..where((t) => t.id.equals(id))).write(
      TargetsCompanion(
        goalIntegrationSecs: Value(goalIntegrationSecs),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Get targets ordered by priority
  Future<List<Target>> getTargetsByPriority() {
    return (select(targets)..orderBy([(t) => OrderingTerm.desc(t.priority)]))
        .get();
  }

  /// Get targets that are observable tonight
  Future<List<Target>> getObservableTargets(
      double latitude, double longitude) async {
    final allTargets = await getAllTargets();
    final nowUtc = DateTime.now().toUtc();

    final observable = allTargets.where((target) {
      final altitudeDeg = _calculateAltitudeDegrees(
        latitudeDeg: latitude,
        longitudeDeg: longitude,
        raHours: target.ra,
        decDeg: target.dec,
        atUtc: nowUtc,
      );
      return altitudeDeg >= target.minAltitude;
    }).toList();

    observable.sort((a, b) => b.priority.compareTo(a.priority));
    return observable;
  }

  double _calculateAltitudeDegrees({
    required double latitudeDeg,
    required double longitudeDeg,
    required double raHours,
    required double decDeg,
    required DateTime atUtc,
  }) {
    final lstDeg =
        _localSiderealTimeDegrees(atUtc: atUtc, longitudeDeg: longitudeDeg);
    final raDeg = raHours * 15.0;
    final hourAngleDeg = _normalizeHa(lstDeg - raDeg);

    final latRad = latitudeDeg * math.pi / 180.0;
    final decRad = decDeg * math.pi / 180.0;
    final haRad = hourAngleDeg * math.pi / 180.0;

    final sinAlt = math.sin(decRad) * math.sin(latRad) +
        math.cos(decRad) * math.cos(latRad) * math.cos(haRad);
    final clamped = sinAlt.clamp(-1.0, 1.0);
    return math.asin(clamped) * 180.0 / math.pi;
  }

  double _localSiderealTimeDegrees({
    required DateTime atUtc,
    required double longitudeDeg,
  }) {
    final gmstDeg = _greenwichMeanSiderealTimeDegrees(atUtc);
    return _normalizeLst(gmstDeg + longitudeDeg);
  }

  double _greenwichMeanSiderealTimeDegrees(DateTime atUtc) {
    final jd = _julianDate(atUtc);
    final t = (jd - 2451545.0) / 36525.0;
    final gmst = 280.46061837 +
        360.98564736629 * (jd - 2451545.0) +
        0.000387933 * t * t -
        (t * t * t) / 38710000.0;
    return _normalizeLst(gmst);
  }

  double _julianDate(DateTime atUtc) {
    final utc = atUtc.toUtc();
    var year = utc.year;
    var month = utc.month;
    final dayFraction = utc.day +
        (utc.hour / 24.0) +
        (utc.minute / 1440.0) +
        (utc.second / 86400.0) +
        (utc.millisecond / 86400000.0);

    if (month <= 2) {
      year -= 1;
      month += 12;
    }

    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();

    return (365.25 * (year + 4716)).floorToDouble() +
        (30.6001 * (month + 1)).floorToDouble() +
        dayFraction +
        b -
        1524.5;
  }

  /// Normalize an angle into [0, 360) — appropriate for LST and GMST.
  double _normalizeLst(double degrees) {
    var n = degrees % 360.0;
    if (n < 0) n += 360.0;
    return n;
  }

  /// Normalize an angle into [-180, 180] — appropriate for hour angle.
  double _normalizeHa(double degrees) {
    var n = degrees % 360.0;
    if (n < 0) n += 360.0;
    if (n > 180) n -= 360.0;
    return n;
  }
}
