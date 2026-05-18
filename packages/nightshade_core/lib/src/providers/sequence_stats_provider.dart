import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart';
import '../database/daos/sequence_runs_dao.dart';
import 'database_provider.dart';

// =============================================================================
// POST-SESSION STATISTICS MODEL
// =============================================================================

/// Statistics collected during a sequence execution run.
class SequenceRunStats {
  final DateTime startTime;
  DateTime? endTime;

  int framesCaptured;
  int framesRejected;
  double integrationSecs;
  int triggerFires;
  int autofocusRuns;
  int meridianFlips;
  int ditherCount;

  /// Per-target, per-filter breakdown: targetName -> filterName -> stats
  final Map<String, Map<String, _FilterStats>> targetBreakdown;

  /// Error messages accumulated during the run
  final List<String> errorMessages;

  /// Non-fatal warnings accumulated during the run. Used by the executor to
  /// surface conditions like "filter wheel not connected, using filter name
  /// as a literal" — situations that don't stop the sequence but the user
  /// should see in the post-session report.
  final List<String> warningMessages;

  SequenceRunStats()
      : startTime = DateTime.now(),
        framesCaptured = 0,
        framesRejected = 0,
        integrationSecs = 0,
        triggerFires = 0,
        autofocusRuns = 0,
        meridianFlips = 0,
        ditherCount = 0,
        targetBreakdown = {},
        errorMessages = [],
        warningMessages = [];

  double get wallClockSecs {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inMilliseconds / 1000.0;
  }

  double get overheadSecs => wallClockSecs - integrationSecs;

  void recordFrame({
    required String target,
    required String filter,
    required double exposureSecs,
    required bool accepted,
  }) {
    framesCaptured++;
    if (!accepted) framesRejected++;
    integrationSecs += exposureSecs;

    targetBreakdown.putIfAbsent(target, () => {});
    final filterStats =
        targetBreakdown[target]!.putIfAbsent(filter, () => _FilterStats());
    filterStats.captured++;
    if (!accepted) filterStats.rejected++;
    filterStats.integrationSecs += exposureSecs;
  }

  void recordTriggerFire() => triggerFires++;
  void recordAutofocus() => autofocusRuns++;
  void recordMeridianFlip() => meridianFlips++;
  void recordDither() => ditherCount++;
  void recordError(String message) => errorMessages.add(message);

  /// Record a non-fatal warning surfaced during execution. Idempotent on
  /// exact-duplicate consecutive messages so a per-frame warning (e.g.
  /// "filter wheel not connected") doesn't bloat the stats blob.
  void recordWarning(String message) {
    if (warningMessages.isNotEmpty && warningMessages.last == message) {
      return;
    }
    warningMessages.add(message);
  }

  /// Serialize to JSON for database storage.
  String toJson() {
    final breakdown = <String, dynamic>{};
    for (final targetEntry in targetBreakdown.entries) {
      final filters = <String, dynamic>{};
      for (final filterEntry in targetEntry.value.entries) {
        filters[filterEntry.key] = {
          'captured': filterEntry.value.captured,
          'rejected': filterEntry.value.rejected,
          'integrationSecs': filterEntry.value.integrationSecs,
        };
      }
      breakdown[targetEntry.key] = filters;
    }

    return jsonEncode({
      'wallClockSecs': wallClockSecs,
      'integrationSecs': integrationSecs,
      'overheadSecs': overheadSecs,
      'framesCaptured': framesCaptured,
      'framesRejected': framesRejected,
      'targetBreakdown': breakdown,
      'triggerFires': triggerFires,
      'autofocusRuns': autofocusRuns,
      'meridianFlips': meridianFlips,
      'ditherCount': ditherCount,
      'errorMessages': errorMessages,
      'warningMessages': warningMessages,
    });
  }

  /// Deserialize from JSON stored in the database.
  factory SequenceRunStats.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final stats = SequenceRunStats();
    stats.framesCaptured = (map['framesCaptured'] as num?)?.toInt() ?? 0;
    stats.framesRejected = (map['framesRejected'] as num?)?.toInt() ?? 0;
    stats.integrationSecs =
        (map['integrationSecs'] as num?)?.toDouble() ?? 0.0;
    stats.triggerFires = (map['triggerFires'] as num?)?.toInt() ?? 0;
    stats.autofocusRuns = (map['autofocusRuns'] as num?)?.toInt() ?? 0;
    stats.meridianFlips = (map['meridianFlips'] as num?)?.toInt() ?? 0;
    stats.ditherCount = (map['ditherCount'] as num?)?.toInt() ?? 0;

    final errors = map['errorMessages'] as List<dynamic>?;
    if (errors != null) {
      stats.errorMessages.addAll(errors.cast<String>());
    }

    final warnings = map['warningMessages'] as List<dynamic>?;
    if (warnings != null) {
      stats.warningMessages.addAll(warnings.cast<String>());
    }

    final breakdown = map['targetBreakdown'] as Map<String, dynamic>?;
    if (breakdown != null) {
      for (final targetEntry in breakdown.entries) {
        final filters = targetEntry.value as Map<String, dynamic>;
        stats.targetBreakdown[targetEntry.key] = {};
        for (final filterEntry in filters.entries) {
          final fMap = filterEntry.value as Map<String, dynamic>;
          final fs = _FilterStats();
          fs.captured = (fMap['captured'] as num?)?.toInt() ?? 0;
          fs.rejected = (fMap['rejected'] as num?)?.toInt() ?? 0;
          fs.integrationSecs =
              (fMap['integrationSecs'] as num?)?.toDouble() ?? 0.0;
          stats.targetBreakdown[targetEntry.key]![filterEntry.key] = fs;
        }
      }
    }

    return stats;
  }
}

class _FilterStats {
  int captured = 0;
  int rejected = 0;
  double integrationSecs = 0.0;
}

// =============================================================================
// PARSED STATS FOR UI DISPLAY
// =============================================================================

/// Parsed stats from a SequenceRun for easy UI consumption.
class ParsedRunStats {
  final double wallClockSecs;
  final double integrationSecs;
  final double overheadSecs;
  final int framesCaptured;
  final int framesRejected;
  final int triggerFires;
  final int autofocusRuns;
  final int meridianFlips;
  final int ditherCount;
  final Map<String, Map<String, Map<String, dynamic>>> targetBreakdown;
  final List<String> errorMessages;
  final List<String> warningMessages;

  ParsedRunStats({
    required this.wallClockSecs,
    required this.integrationSecs,
    required this.overheadSecs,
    required this.framesCaptured,
    required this.framesRejected,
    required this.triggerFires,
    required this.autofocusRuns,
    required this.meridianFlips,
    required this.ditherCount,
    required this.targetBreakdown,
    required this.errorMessages,
    this.warningMessages = const [],
  });

  factory ParsedRunStats.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;

    final breakdown = <String, Map<String, Map<String, dynamic>>>{};
    final rawBreakdown = map['targetBreakdown'] as Map<String, dynamic>?;
    if (rawBreakdown != null) {
      for (final te in rawBreakdown.entries) {
        breakdown[te.key] = {};
        final filters = te.value as Map<String, dynamic>;
        for (final fe in filters.entries) {
          breakdown[te.key]![fe.key] = fe.value as Map<String, dynamic>;
        }
      }
    }

    return ParsedRunStats(
      wallClockSecs: (map['wallClockSecs'] as num?)?.toDouble() ?? 0,
      integrationSecs: (map['integrationSecs'] as num?)?.toDouble() ?? 0,
      overheadSecs: (map['overheadSecs'] as num?)?.toDouble() ?? 0,
      framesCaptured: (map['framesCaptured'] as num?)?.toInt() ?? 0,
      framesRejected: (map['framesRejected'] as num?)?.toInt() ?? 0,
      triggerFires: (map['triggerFires'] as num?)?.toInt() ?? 0,
      autofocusRuns: (map['autofocusRuns'] as num?)?.toInt() ?? 0,
      meridianFlips: (map['meridianFlips'] as num?)?.toInt() ?? 0,
      ditherCount: (map['ditherCount'] as num?)?.toInt() ?? 0,
      targetBreakdown: breakdown,
      errorMessages:
          (map['errorMessages'] as List<dynamic>?)?.cast<String>() ?? [],
      warningMessages:
          (map['warningMessages'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  String formatDuration(double secs) {
    final hours = (secs / 3600).floor();
    final mins = ((secs % 3600) / 60).floor();
    final seconds = (secs % 60).round();
    if (hours > 0) return '${hours}h ${mins}m ${seconds}s';
    if (mins > 0) return '${mins}m ${seconds}s';
    return '${seconds}s';
  }
}

// =============================================================================
// PROVIDERS
// =============================================================================

/// Provider for accessing the sequence runs DAO.
final sequenceRunsDaoProvider = Provider<SequenceRunsDao>((ref) {
  final db = ref.watch(databaseProvider);
  return db.sequenceRunsDao;
});

/// Live stats tracker for the currently running sequence.
/// Null when no sequence is running.
final liveSequenceStatsProvider =
    StateProvider<SequenceRunStats?>((ref) => null);

/// The database row ID of the current run (for updating on completion).
final currentRunIdProvider = StateProvider<int?>((ref) => null);

/// Watch all sequence runs from the database.
final sequenceRunsProvider = StreamProvider<List<SequenceRun>>((ref) {
  final dao = ref.watch(sequenceRunsDaoProvider);
  return dao.watchAllRuns();
});

/// Watch runs for a specific sequence.
final sequenceRunsForSequenceProvider =
    StreamProvider.family<List<SequenceRun>, int>((ref, sequenceId) {
  final dao = ref.watch(sequenceRunsDaoProvider);
  return dao.watchRunsForSequence(sequenceId);
});
