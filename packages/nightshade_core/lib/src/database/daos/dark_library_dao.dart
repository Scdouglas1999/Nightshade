import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/dark_library.dart';

part 'dark_library_dao.g.dart';

@DriftAccessor(tables: [DarkLibrary])
class DarkLibraryDao extends DatabaseAccessor<NightshadeDatabase>
    with _$DarkLibraryDaoMixin {
  DarkLibraryDao(super.db);

  /// Insert a new dark frame entry and return its ID.
  Future<int> addEntry(DarkLibraryCompanion entry) {
    return transaction(() async {
      final filePath = entry.filePath.present ? entry.filePath.value : null;
      if (filePath == null) {
        throw ArgumentError('Dark library entries require a filePath');
      }

      final existing = await (select(darkLibrary)
            ..where((t) => t.filePath.equals(filePath)))
          .getSingleOrNull();

      if (existing != null) {
        await (update(darkLibrary)..where((t) => t.id.equals(existing.id)))
            .write(
          entry.copyWith(id: Value(existing.id)),
        );
        return existing.id;
      }

      return into(darkLibrary).insert(entry);
    });
  }

  /// Get all entries, newest first.
  Future<List<DarkLibraryEntry>> getAllEntries() {
    return (select(darkLibrary)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Watch all entries, newest first.
  Stream<List<DarkLibraryEntry>> watchAllEntries() {
    return (select(darkLibrary)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Get entries by frame type ('dark' or 'bias').
  Future<List<DarkLibraryEntry>> getEntriesByFrameType(String type) {
    return (select(darkLibrary)
          ..where((t) => t.frameType.equals(type))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Watch entries by frame type.
  Stream<List<DarkLibraryEntry>> watchEntriesByFrameType(String type) {
    return (select(darkLibrary)
          ..where((t) => t.frameType.equals(type))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Find the best matching dark/bias for a given light frame's parameters.
  ///
  /// Matching rules:
  /// - Exposure time must match exactly
  /// - Gain must match exactly
  /// - Binning must match exactly
  /// - Temperature must be within [tempToleranceDegC] (default ±2°C)
  /// - Prefers master darks over individual raws
  /// - Among matches, picks the one closest in temperature
  Future<DarkLibraryEntry?> findBestMatch({
    required double exposureTime,
    required int gain,
    required int offset,
    required int binX,
    required int binY,
    double? temperature,
    double tempToleranceDegC = 2.0,
    String frameType = 'dark',
  }) async {
    // Build query: tolerance match on exposure (±0.001s), exact on gain, binning, frame type
    var query = select(darkLibrary)
      ..where((t) =>
          t.exposureTime.isBiggerThanValue(exposureTime - 0.001) &
          t.exposureTime.isSmallerThanValue(exposureTime + 0.001) &
          t.gain.equals(gain) &
          t.offset.equals(offset) &
          t.binX.equals(binX) &
          t.binY.equals(binY) &
          t.frameType.equals(frameType));

    final candidates = await query.get();
    if (candidates.isEmpty) return null;

    // Filter by temperature tolerance if temperature is available
    List<DarkLibraryEntry> filtered;
    if (temperature != null) {
      filtered = candidates.where((c) {
        if (c.temperature == null)
          return true; // Accept frames without temp data
        return (c.temperature! - temperature).abs() <= tempToleranceDegC;
      }).toList();
    } else {
      filtered = candidates;
    }

    if (filtered.isEmpty) return null;

    // Prefer master darks over raw frames
    final masters = filtered.where((c) => c.masterDarkPath != null).toList();
    final pool = masters.isNotEmpty ? masters : filtered;

    if (temperature == null) {
      // No temperature to sort by; return the newest entry
      pool.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return pool.first;
    }

    // Sort by closest temperature match
    pool.sort((a, b) {
      final aDelta = a.temperature != null
          ? (a.temperature! - temperature).abs()
          : double.maxFinite;
      final bDelta = b.temperature != null
          ? (b.temperature! - temperature).abs()
          : double.maxFinite;
      return aDelta.compareTo(bDelta);
    });

    return pool.first;
  }

  /// Get all entries that match a specific exposure/gain/binning combo.
  /// Useful for selecting frames to combine into a master dark.
  Future<List<DarkLibraryEntry>> getMatchingFrames({
    required double exposureTime,
    required int gain,
    required int binX,
    required int binY,
    String frameType = 'dark',
  }) {
    return (select(darkLibrary)
          ..where((t) =>
              t.exposureTime.isBiggerThanValue(exposureTime - 0.001) &
              t.exposureTime.isSmallerThanValue(exposureTime + 0.001) &
              t.gain.equals(gain) &
              t.binX.equals(binX) &
              t.binY.equals(binY) &
              t.frameType.equals(frameType) &
              t.masterDarkPath.isNull()) // Only raw frames
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Get a single entry by ID.
  Future<DarkLibraryEntry?> getEntryById(int id) {
    return (select(darkLibrary)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Delete an entry by ID.
  Future<int> deleteEntry(int id) {
    return (delete(darkLibrary)..where((t) => t.id.equals(id))).go();
  }

  /// Delete multiple entries by IDs.
  Future<int> deleteEntries(List<int> ids) {
    return (delete(darkLibrary)..where((t) => t.id.isIn(ids))).go();
  }

  /// Delete all entries.
  Future<int> deleteAll() {
    return delete(darkLibrary).go();
  }

  /// Update an existing entry (e.g. to set masterDarkPath after stacking).
  Future<bool> updateEntry(DarkLibraryEntry entry) {
    return update(darkLibrary).replace(entry);
  }

  /// Get summary statistics: count per frame type, total disk usage estimate.
  ///
  /// Uses SQL COUNT queries instead of loading the entire table into memory.
  Future<DarkLibraryStats> getStats() async {
    final totalExp = darkLibrary.id.count();

    // Count master darks (masterDarkPath IS NOT NULL)
    final masterQuery = selectOnly(darkLibrary)
      ..addColumns([totalExp])
      ..where(darkLibrary.masterDarkPath.isNotNull());
    final masterResult = await masterQuery.getSingle();
    final masterCount = masterResult.read(totalExp) ?? 0;

    // Count bias frames (non-master)
    final biasQuery = selectOnly(darkLibrary)
      ..addColumns([totalExp])
      ..where(darkLibrary.frameType.equals('bias') &
          darkLibrary.masterDarkPath.isNull());
    final biasResult = await biasQuery.getSingle();
    final biasCount = biasResult.read(totalExp) ?? 0;

    // Count dark frames (non-master, non-bias)
    final darkQuery = selectOnly(darkLibrary)
      ..addColumns([totalExp])
      ..where(darkLibrary.frameType.equals('dark') &
          darkLibrary.masterDarkPath.isNull());
    final darkResult = await darkQuery.getSingle();
    final darkCount = darkResult.read(totalExp) ?? 0;

    // Total entries
    final totalQuery = selectOnly(darkLibrary)..addColumns([totalExp]);
    final totalResult = await totalQuery.getSingle();
    final totalEntries = totalResult.read(totalExp) ?? 0;

    return DarkLibraryStats(
      totalEntries: totalEntries,
      darkCount: darkCount,
      biasCount: biasCount,
      masterCount: masterCount,
    );
  }

  /// Get distinct exposure/gain/binning combinations present in the library.
  ///
  /// Uses SQL GROUP BY instead of loading the entire table into memory.
  Future<List<DarkGroupKey>> getDistinctGroups() async {
    final query = selectOnly(darkLibrary)
      ..addColumns([
        darkLibrary.frameType,
        darkLibrary.exposureTime,
        darkLibrary.gain,
        darkLibrary.binX,
        darkLibrary.binY,
      ])
      ..groupBy([
        darkLibrary.frameType,
        darkLibrary.exposureTime,
        darkLibrary.gain,
        darkLibrary.binX,
        darkLibrary.binY,
      ]);

    final rows = await query.get();
    return rows.map((row) {
      return DarkGroupKey(
        frameType: row.read(darkLibrary.frameType)!,
        exposureTime: row.read(darkLibrary.exposureTime)!,
        gain: row.read(darkLibrary.gain)!,
        binX: row.read(darkLibrary.binX)!,
        binY: row.read(darkLibrary.binY)!,
      );
    }).toList();
  }
}

/// Summary statistics for the dark library.
class DarkLibraryStats {
  final int totalEntries;
  final int darkCount;
  final int biasCount;
  final int masterCount;

  const DarkLibraryStats({
    required this.totalEntries,
    required this.darkCount,
    required this.biasCount,
    required this.masterCount,
  });
}

/// Identifies a unique group of dark frames by their capture parameters.
class DarkGroupKey {
  final String frameType;
  final double exposureTime;
  final int gain;
  final int binX;
  final int binY;

  const DarkGroupKey({
    required this.frameType,
    required this.exposureTime,
    required this.gain,
    required this.binX,
    required this.binY,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DarkGroupKey &&
          frameType == other.frameType &&
          exposureTime == other.exposureTime &&
          gain == other.gain &&
          binX == other.binX &&
          binY == other.binY;

  @override
  int get hashCode => Object.hash(frameType, exposureTime, gain, binX, binY);

  @override
  String toString() =>
      'DarkGroupKey($frameType, ${exposureTime}s, gain=$gain, ${binX}x$binY)';
}
