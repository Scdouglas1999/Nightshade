import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database.dart' show PolarAlignmentHistoryEntry;
import '../services/optical_train_diagnostics_service.dart';
import '../services/time_sync_service.dart';
import 'database_provider.dart';

// =============================================================================
// Wave 5 Agent 3 — Pre-flight wiring providers
// =============================================================================
//
// Riverpod providers that surface the data the pre-flight validation rules
// need without each rule re-implementing the lookup. Kept separate from
// the rule files so test overrides have a single grep-able home.

/// Provider for the NTP-based time-sync probe. Override in tests with a
/// fake that returns a synthetic offset (or throws to simulate a
/// network failure).
final timeSyncProbeProvider = Provider<TimeSyncProbe>((ref) {
  return const TimeSyncServiceProbe(TimeSyncService());
});

/// Most recent polar-alignment history entry across ALL equipment
/// profiles. The pre-flight rule uses this to decide whether the
/// alignment is stale — checking per-profile would miss the case where
/// the user is on a profile that has no history yet but their other
/// rig was aligned an hour ago, etc. Profile-aware variants can be
/// added later.
///
/// `null` => no polar alignment has ever been recorded; the rule then
/// emits an info-severity "you haven't polar aligned yet" issue (still
/// honouring strictness).
final lastPolarAlignmentAnywhereProvider =
    FutureProvider.autoDispose<PolarAlignmentHistoryEntry?>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.polarAlignmentHistoryDao.getLastAlignment(null);
});

/// Pre-session optical-train baseline snapshot. Captured the first time
/// the user runs a sequence (or after the user clears it via the
/// diagnostics tab). The pre-flight rule compares the current snapshot
/// to this baseline to detect "your rig has shifted since last
/// session".
///
/// `null` => no baseline has been recorded yet; the rule skips the
/// comparison and surfaces an info note explaining that the first run
/// is establishing a baseline. Updated automatically by the executor on
/// run start.
class OpticalTrainBaseline {
  final double tiltScore;
  final double collimationScore;
  final DateTime capturedAt;

  const OpticalTrainBaseline({
    required this.tiltScore,
    required this.collimationScore,
    required this.capturedAt,
  });

  /// Construct from a diagnostics reading.
  factory OpticalTrainBaseline.fromDiagnostics(
    OpticalTrainDiagnostics diagnostics, {
    DateTime? capturedAt,
  }) {
    return OpticalTrainBaseline(
      tiltScore: diagnostics.tiltScore,
      collimationScore: diagnostics.collimationScore,
      capturedAt: capturedAt ?? DateTime.now(),
    );
  }

  /// Total magnitude of drift from this baseline to the supplied
  /// current diagnostics. Equal-weight blend of tilt + collimation
  /// score deltas matches the `OpticalHealthScore` weighting so the
  /// pre-flight number agrees with the diagnostics dashboard.
  double driftAgainst(OpticalTrainDiagnostics current) {
    final dTilt = (current.tiltScore - tiltScore).abs();
    final dColl = (current.collimationScore - collimationScore).abs();
    return dTilt * 0.5 + dColl * 0.5;
  }
}

/// In-memory baseline store. Persisting this across launches lives
/// further out (the executor writes it to a key in `app_settings` on
/// every run start); the in-process provider here is the runtime
/// cache. Tests override it directly via `overrideWith`.
final opticalTrainBaselineProvider =
    StateProvider<OpticalTrainBaseline?>((ref) => null);

/// Current optical-train snapshot supplied by the post-session pipeline
/// (or by the test harness). Wave 5 Agent 3 fills this from the live
/// diagnostics stream when a sequence finishes; the pre-flight rule
/// reads it to compare against [opticalTrainBaselineProvider].
///
/// `null` => no current snapshot is available yet — the rule emits an
/// info note rather than silently passing.
final opticalTrainCurrentSnapshotProvider =
    StateProvider<OpticalTrainBaseline?>((ref) => null);

/// Latest equipment-health snapshot for the post-session diagnostics
/// summary. Holds simple counters that don't fit cleanly into the
/// existing `EquipmentHealthReport` (which is built from session
/// history). Populated by the executor's session bookkeeping; tests
/// inject directly.
class PostSessionHealthSummary {
  /// Total USB / connection disconnects across all devices observed
  /// during the session.
  final int disconnectsDuringSession;

  /// Number of cooler temperature samples that exceeded the
  /// configured setpoint band (used for "cooler stability"
  /// surfacing).
  final int coolerOutOfBandSamples;

  /// Total focuser moves recorded during the session.
  final int focuserMoves;

  /// Sky brightness range encountered during the session, in mag /
  /// arcsec² (Bortle / SQM units).
  final double? skyBrightnessMin;
  final double? skyBrightnessMax;
  final double? skyBrightnessMedian;

  /// Any "noticed but did not fire" warnings — e.g. HFR trending up
  /// but never exceeding the explicit reject threshold. Surfaced
  /// verbatim in the post-session diagnostics section so the user
  /// knows the system was watching.
  final List<String> noticedConcerns;

  const PostSessionHealthSummary({
    this.disconnectsDuringSession = 0,
    this.coolerOutOfBandSamples = 0,
    this.focuserMoves = 0,
    this.skyBrightnessMin,
    this.skyBrightnessMax,
    this.skyBrightnessMedian,
    this.noticedConcerns = const [],
  });

  /// Whether there is anything interesting to render. The diagnostics
  /// section in the report dialog hides itself when this returns
  /// `false`, on the principle that a perfectly boring run should
  /// not get a noisy "nothing happened" block.
  bool get hasContent {
    return disconnectsDuringSession > 0 ||
        coolerOutOfBandSamples > 0 ||
        focuserMoves > 0 ||
        skyBrightnessMin != null ||
        noticedConcerns.isNotEmpty;
  }
}

/// Per-session post-session health summary. Family keyed by sessionId.
/// Populated by the executor's session tear-down and read by the
/// post-session report dialog.
final postSessionHealthSummaryProvider =
    StateProvider.family<PostSessionHealthSummary, int>(
        (ref, sessionId) => const PostSessionHealthSummary());
