import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/session_handoff_service.dart';
import 'database_provider.dart';
import 'sequence_provider.dart';
import 'settings_provider.dart';

/// Service provider for SessionHandoffService.
///
/// Wires the DAOs so the service can perform multi-night
/// carry-over detection. The original device-to-device handoff API
/// (`exportBundle` / `describe`) still works without DAOs because the
/// constructor parameters are optional.
final sessionHandoffServiceProvider = Provider<SessionHandoffService>((ref) {
  return SessionHandoffService(
    sessionsDao: ref.watch(sessionsDaoProvider),
    imagesDao: ref.watch(imagesDaoProvider),
    targetsDao: ref.watch(targetsDaoProvider),
  );
});

/// Carry-over detection for the current in-editor sequence.
///
/// Auto-invalidates when the sequence model changes (i.e. a target is
/// added/removed). Returns an empty list when no recent prior sessions
/// match the target list, when the sequence is empty, or when the
/// underlying DAOs are not wired (offline backend).
///
/// The pre-flight dialog consults this provider to decide whether to
/// render the carry-over banner. The provider intentionally returns an
/// empty list rather than throwing for any failure path — pre-flight
/// must never be blocked by a transient database read.
final sessionCarryOverProvider =
    FutureProvider.autoDispose<List<SessionCarryOver>>((ref) async {
      final sequence = ref.watch(currentSequenceProvider);
      if (sequence == null) return const <SessionCarryOver>[];
      final service = ref.watch(sessionHandoffServiceProvider);
      try {
        final libraryTargets = await ref.watch(allDbTargetsProvider.future);
        final capturedImages = await ref.watch(allDbImagesProvider.future);
        final sessions = await ref.watch(allSessionsProvider.future);
        return await service.detectCarryOver(
          sequence: sequence,
          libraryTargets: libraryTargets,
          capturedImages: capturedImages,
          sessions: sessions,
        );
      } catch (_) {
        // Failing closed here would be wrong: the user could be blocked
        // from running their sequence because of a stale DAO. Carry-over
        // is a "hint" surface — degrade gracefully when the DB call fails.
        return const <SessionCarryOver>[];
      }
    });

/// Controls whether the carry-over pre-flight dialog auto-opens.
///
/// Mirrors the [AppSettingsState.sessionHandoffAutoPrompt] toggle so the
/// pre-flight widget can synchronously read the current value without
/// pulling the entire `appSettingsProvider`.
final sessionHandoffAutoPromptProvider = Provider<bool>((ref) {
  final settings = ref.watch(appSettingsProvider).valueOrNull;
  return settings?.sessionHandoffAutoPrompt ?? true;
});

/// Operator's last decision for a given target id. Pre-flight
/// uses this to avoid re-prompting on the same sequence after the
/// user has chosen Restart / Continue New (Resume can be revoked by
/// opening the banner from the menu).
///
/// Keyed by `(sequenceDatabaseId, targetId)` so independent sequences
/// for the same target don't share state.
final sessionHandoffDecisionProvider =
    StateProvider.family<
      SessionHandoffDecision?,
      ({int? sequenceId, int targetId})
    >((ref, key) => null);
