import 'dart:convert';

import 'package:drift/drift.dart';

import '../../models/polar_alignment_config.dart';
import '../database.dart';
import '../tables/polar_alignment_history.dart';

part 'polar_alignment_history_dao.g.dart';

@DriftAccessor(tables: [PolarAlignmentHistory])
class PolarAlignmentHistoryDao extends DatabaseAccessor<NightshadeDatabase>
    with _$PolarAlignmentHistoryDaoMixin {
  PolarAlignmentHistoryDao(super.db);

  /// Insert a new polar alignment result
  Future<int> insertResult(PolarAlignmentResult result) {
    return into(polarAlignmentHistory).insert(
      PolarAlignmentHistoryCompanion.insert(
        equipmentProfileId: Value(result.equipmentProfileId),
        initialAzimuthError: result.initialError.azimuthError,
        initialAltitudeError: result.initialError.altitudeError,
        initialTotalError: result.initialError.totalError,
        finalAzimuthError: result.finalError.azimuthError,
        finalAltitudeError: result.finalError.altitudeError,
        finalTotalError: result.finalError.totalError,
        startedAt: result.startedAt,
        completedAt: result.completedAt,
        autoCompleted: Value(result.autoCompleted),
        isNorth: Value(result.config.isNorth),
        configJson: jsonEncode(result.config.toJson()),
      ),
    );
  }

  /// Get alignment history for a specific equipment profile
  ///
  /// If [profileId] is null, returns all history entries.
  /// Results are ordered by completion time, most recent first.
  Future<List<PolarAlignmentHistoryEntry>> getHistoryForProfile(
    int? profileId, {
    int limit = 20,
  }) {
    final query = select(polarAlignmentHistory)
      ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
      ..limit(limit);

    if (profileId != null) {
      query.where((t) => t.equipmentProfileId.equals(profileId));
    }

    return query.get();
  }

  /// Get the most recent alignment for a profile
  Future<PolarAlignmentHistoryEntry?> getLastAlignment(int? profileId) async {
    final query = select(polarAlignmentHistory)
      ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
      ..limit(1);

    if (profileId != null) {
      query.where((t) => t.equipmentProfileId.equals(profileId));
    }

    final results = await query.get();
    return results.isEmpty ? null : results.first;
  }

  /// Watch alignment history for real-time updates
  ///
  /// Returns a stream that emits whenever the history changes.
  Stream<List<PolarAlignmentHistoryEntry>> watchHistory(
    int? profileId, {
    int limit = 20,
  }) {
    final query = select(polarAlignmentHistory)
      ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
      ..limit(limit);

    if (profileId != null) {
      query.where((t) => t.equipmentProfileId.equals(profileId));
    }

    return query.watch();
  }

  /// Get alignment statistics for a profile
  ///
  /// Returns average initial and final errors, plus improvement percentage.
  Future<PolarAlignmentStats?> getStats(int? profileId) async {
    final history = await getHistoryForProfile(profileId, limit: 100);
    if (history.isEmpty) return null;

    double totalInitialError = 0;
    double totalFinalError = 0;
    int autoCompletedCount = 0;

    for (final entry in history) {
      totalInitialError += entry.initialTotalError;
      totalFinalError += entry.finalTotalError;
      if (entry.autoCompleted) autoCompletedCount++;
    }

    final avgInitial = totalInitialError / history.length;
    final avgFinal = totalFinalError / history.length;
    final avgImprovement = avgInitial > 0
        ? ((avgInitial - avgFinal) / avgInitial * 100)
        : 0.0;

    // Get best and worst results
    history.sort((a, b) => a.finalTotalError.compareTo(b.finalTotalError));
    final bestFinalError = history.first.finalTotalError;
    final worstFinalError = history.last.finalTotalError;

    return PolarAlignmentStats(
      totalSessions: history.length,
      avgInitialError: avgInitial,
      avgFinalError: avgFinal,
      avgImprovementPercent: avgImprovement,
      bestFinalError: bestFinalError,
      worstFinalError: worstFinalError,
      autoCompletedCount: autoCompletedCount,
    );
  }

  /// Delete old history entries, keeping the most recent N per profile
  Future<void> pruneHistory({int keepPerProfile = 50}) async {
    await transaction(() async {
      // Get distinct profile IDs
      final profiles = await (selectOnly(polarAlignmentHistory, distinct: true)
            ..addColumns([polarAlignmentHistory.equipmentProfileId]))
          .map((row) => row.read(polarAlignmentHistory.equipmentProfileId))
          .get();

      for (final profileId in profiles) {
        // Get IDs to keep for this profile
        final query = select(polarAlignmentHistory)
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
          ..limit(keepPerProfile);

        if (profileId != null) {
          query.where((t) => t.equipmentProfileId.equals(profileId));
        } else {
          query.where((t) => t.equipmentProfileId.isNull());
        }

        final keepIds = await query.map((e) => e.id).get();

        if (keepIds.isNotEmpty) {
          // Delete entries not in keep list
          await (delete(polarAlignmentHistory)
                ..where((t) {
                  if (profileId != null) {
                    return t.equipmentProfileId.equals(profileId) &
                        t.id.isNotIn(keepIds);
                  } else {
                    return t.equipmentProfileId.isNull() & t.id.isNotIn(keepIds);
                  }
                }))
              .go();
        }
      }
    });
  }

  /// Delete all history for a specific profile
  Future<int> deleteHistoryForProfile(int profileId) {
    return (delete(polarAlignmentHistory)
          ..where((t) => t.equipmentProfileId.equals(profileId)))
        .go();
  }

  /// Delete a specific history entry
  Future<int> deleteEntry(int id) {
    return (delete(polarAlignmentHistory)..where((t) => t.id.equals(id))).go();
  }

  /// Convert a database entry to a PolarAlignmentResult model
  PolarAlignmentResult entryToResult(PolarAlignmentHistoryEntry entry) {
    final configJson = jsonDecode(entry.configJson) as Map<String, dynamic>;
    final config = PolarAlignmentConfig.fromJson(configJson);

    return PolarAlignmentResult(
      initialError: PolarAlignmentError(
        azimuthError: entry.initialAzimuthError,
        altitudeError: entry.initialAltitudeError,
        totalError: entry.initialTotalError,
        currentRa: 0, // Not stored in history
        currentDec: 0,
        targetRa: 0,
        targetDec: 0,
        timestamp: entry.startedAt,
      ),
      finalError: PolarAlignmentError(
        azimuthError: entry.finalAzimuthError,
        altitudeError: entry.finalAltitudeError,
        totalError: entry.finalTotalError,
        currentRa: 0,
        currentDec: 0,
        targetRa: 0,
        targetDec: 0,
        timestamp: entry.completedAt,
      ),
      startedAt: entry.startedAt,
      completedAt: entry.completedAt,
      config: config,
      autoCompleted: entry.autoCompleted,
      equipmentProfileId: entry.equipmentProfileId,
    );
  }
}

/// Statistics for polar alignment history
class PolarAlignmentStats {
  /// Total number of alignment sessions
  final int totalSessions;

  /// Average initial error in arcseconds
  final double avgInitialError;

  /// Average final error in arcseconds
  final double avgFinalError;

  /// Average improvement percentage
  final double avgImprovementPercent;

  /// Best (lowest) final error achieved
  final double bestFinalError;

  /// Worst (highest) final error achieved
  final double worstFinalError;

  /// Number of sessions that auto-completed
  final int autoCompletedCount;

  const PolarAlignmentStats({
    required this.totalSessions,
    required this.avgInitialError,
    required this.avgFinalError,
    required this.avgImprovementPercent,
    required this.bestFinalError,
    required this.worstFinalError,
    required this.autoCompletedCount,
  });

  /// Percentage of sessions that auto-completed
  double get autoCompletedPercent =>
      totalSessions > 0 ? autoCompletedCount / totalSessions * 100 : 0;

  @override
  String toString() =>
      'PolarAlignmentStats(sessions: $totalSessions, avgFinal: ${avgFinalError.toStringAsFixed(1)}", best: ${bestFinalError.toStringAsFixed(1)}")';
}
