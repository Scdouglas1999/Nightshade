import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/flat_history.dart';

part 'flat_history_dao.g.dart';

@DriftAccessor(tables: [FlatHistory])
class FlatHistoryDao extends DatabaseAccessor<NightshadeDatabase>
    with _$FlatHistoryDaoMixin {
  FlatHistoryDao(super.db);

  /// Get recent calibrations for a filter, optionally filtered by equipment profile
  Future<List<FlatHistoryEntry>> getRecentCalibrations({
    required String filterName,
    int? equipmentProfileId,
    int limit = 10,
  }) {
    final query = select(flatHistory)
      ..where((t) => t.filterName.equals(filterName))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit);

    if (equipmentProfileId != null) {
      query.where((t) => t.equipmentProfileId.equals(equipmentProfileId));
    }

    return query.get();
  }

  /// Get suggested starting exposure based on historical data
  /// Returns average of last N successful calibrations for this filter
  Future<double?> getSuggestedExposure({
    required String filterName,
    int? equipmentProfileId,
    int sampleSize = 5,
  }) async {
    final entries = await getRecentCalibrations(
      filterName: filterName,
      equipmentProfileId: equipmentProfileId,
      limit: sampleSize,
    );

    if (entries.isEmpty) return null;

    final sum = entries.fold<double>(0, (sum, e) => sum + e.exposureTime);
    return sum / entries.length;
  }

  /// Record a successful calibration
  Future<int> recordCalibration({
    required String filterName,
    required double exposureTime,
    required double histogramTarget,
    required int actualAdu,
    int? equipmentProfileId,
    int? panelBrightness,
    double? skyAduRate,
    String? twilightPhase,
    int gain = 0,
    int binning = 1,
  }) {
    return into(flatHistory).insert(FlatHistoryCompanion.insert(
      filterName: filterName,
      exposureTime: exposureTime,
      histogramTarget: histogramTarget,
      actualAdu: actualAdu,
      equipmentProfileId: Value(equipmentProfileId),
      panelBrightness: Value(panelBrightness),
      skyAduRate: Value(skyAduRate),
      twilightPhase: Value(twilightPhase),
      gain: Value(gain),
      binning: Value(binning),
    ));
  }

  /// Clear old history entries (keep last N per filter)
  Future<void> pruneHistory({int keepPerFilter = 50}) async {
    // Get distinct filter names
    final filters = await (selectOnly(flatHistory, distinct: true)
          ..addColumns([flatHistory.filterName]))
        .map((row) => row.read(flatHistory.filterName)!)
        .get();

    for (final filter in filters) {
      // Get IDs to keep
      final keepIds = await (select(flatHistory)
            ..where((t) => t.filterName.equals(filter))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
            ..limit(keepPerFilter))
          .map((e) => e.id)
          .get();

      if (keepIds.isNotEmpty) {
        // Delete entries not in keep list
        await (delete(flatHistory)
              ..where((t) =>
                  t.filterName.equals(filter) & t.id.isNotIn(keepIds)))
            .go();
      }
    }
  }
}
