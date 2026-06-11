import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/replay_decision.dart';
import '../services/replay_debug_service.dart';
import 'database_provider.dart';

/// Replay Debug — Riverpod surface for the structured decision
/// log feeding the retrospective Replay screen.
///
/// The service-layer types are exposed through thin providers so the UI
/// never reaches into the raw Drift connection directly:
///   * [replayDebugServiceProvider]    — singleton service.
///   * [decisionsForRunProvider]       — reactive list for a run id.
///   * [decisionCountForRunProvider]   — count badge in history.
///
/// The live event-handling path (sequencer event → DB row) lives in
/// `SequenceExecutor._handleSequencerEvent` over in `nightshade_app`;
/// this file is the read-side surface.

final replayDebugServiceProvider = Provider<ReplayDebugService>((ref) {
  final database = ref.watch(databaseProvider);
  final service = ReplayDebugService(database);
  ref.onDispose(() {
    // Fire-and-forget close — the broadcaster has no IO side-effects.
    service.dispose();
  });
  return service;
});

/// Live chronological decision list for a sequence run id. Emits a
/// fresh snapshot on every persist/delete (the service publishes on its
/// internal change bus).
final decisionsForRunProvider =
    StreamProvider.family<List<ReplayDecision>, int>((ref, runId) {
      final service = ref.watch(replayDebugServiceProvider);
      return service.watchByRun(runId);
    });

/// Count of decisions for a run. Async because counts come from the
/// service's persistence layer; the consumer (history row badge)
/// invalidates this on every navigation back to history so a fresh
/// count appears after a run completes.
final decisionCountForRunProvider = FutureProvider.family<int, int>((
  ref,
  runId,
) async {
  final service = ref.watch(replayDebugServiceProvider);
  return service.countByRun(runId);
});

/// Replay Debug — settings keys persisted in `app_settings`.
const String replayDebugEnabledKey = 'replay_debug.enabled';
const String replayDebugRetentionDaysKey = 'replay_debug.retention_days';

/// Default retention window when the setting is unset on first install.
const int replayDebugDefaultRetentionDays = 90;

/// Replay Debug — runtime-enabled toggle. Reads from the
/// `app_settings` table via the SettingsDao. Default is `true` (the
/// migration seeds it on first install).
///
/// Mirrors to the Rust executor via the backend's
/// `sequencerSetDecisionLoggingEnabled` when written; the read side
/// returns the cached value so the UI doesn't await a Rust round-trip.
final replayDebugEnabledProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  final row = await (db.select(
    db.appSettings,
  )..where((t) => t.key.equals(replayDebugEnabledKey))).getSingleOrNull();
  if (row == null) return true;
  return row.value.toLowerCase() != 'false';
});

/// Replay Debug — retention window in days. Decisions older
/// than this are pruned by `ReplayDebugService.pruneOlderThan`. Default
/// 90 days.
final replayDebugRetentionDaysProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final row = await (db.select(
    db.appSettings,
  )..where((t) => t.key.equals(replayDebugRetentionDaysKey))).getSingleOrNull();
  if (row == null) return replayDebugDefaultRetentionDays;
  return int.tryParse(row.value) ?? replayDebugDefaultRetentionDays;
});

/// Replay Debug — write-side controller for the retention
/// settings + the "clear all" affordance. Reads go through the
/// dedicated FutureProviders above; this notifier centralises mutations
/// so the Replay Debug settings page can `await` a single notifier per
/// action and invalidate the read providers in lockstep.
///
/// The setter methods write through the settings DAO and then
/// invalidate the matching read provider — callers can chain
/// `await ref.read(replayDebugSettingsControllerProvider).setEnabled(true)`
/// + `ref.refresh(replayDebugEnabledProvider)` if they want immediate
/// reads, but the controller handles that for them via
/// [Ref.invalidate].
class ReplayDebugSettingsController {
  ReplayDebugSettingsController(this._ref);

  final Ref _ref;

  Future<void> setEnabled(bool value) async {
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(replayDebugEnabledKey, value.toString());
    _ref.invalidate(replayDebugEnabledProvider);
  }

  /// Persist [days] (clamped to a sensible band so a slip-of-the-finger
  /// 0 or 9999 doesn't poison the prune loop). The minimum is 1 day —
  /// we don't allow disabling retention entirely because the database
  /// would grow unbounded; users who want to keep everything forever
  /// can pick the upper clamp (3650 = ~10 years).
  Future<void> setRetentionDays(int days) async {
    final clamped = days.clamp(1, 3650);
    final dao = _ref.read(settingsDaoProvider);
    await dao.setSetting(replayDebugRetentionDaysKey, clamped.toString());
    _ref.invalidate(replayDebugRetentionDaysProvider);
  }

  /// Delete every persisted decision row. Returns the number of rows
  /// removed (zero when the table is already empty).
  Future<int> clearAllHistory() async {
    final service = _ref.read(replayDebugServiceProvider);
    // Schema bootstrap is idempotent — this also exercises the prune
    // path so we know writes are wired through correctly. We use a
    // far-future cutoff so every row qualifies.
    return service.pruneOlderThan(
      DateTime.now().toUtc().add(const Duration(days: 1)),
    );
  }
}

final replayDebugSettingsControllerProvider =
    Provider<ReplayDebugSettingsController>((ref) {
      return ReplayDebugSettingsController(ref);
    });
