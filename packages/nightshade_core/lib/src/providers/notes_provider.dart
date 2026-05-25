import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/notes/journal_note.dart';
import '../services/notes_service.dart';
import '../services/sequence_diff_service.dart';
import 'database_provider.dart';

/// Wave 6 Agent 5 — Riverpod surface for per-target / per-run notes
/// and the structural sequence diff.
///
/// The service-layer types are exposed through three thin providers so
/// the UI never reaches into the raw Drift connection directly:
///   * [notesServiceProvider]       — singleton service.
///   * [notesForTargetProvider]     — reactive list for a target id.
///   * [notesForRunProvider]        — reactive list for a sequence run.
///   * [sequenceDiffServiceProvider] — singleton diff engine.
///
/// Why a [Provider] (not [FutureProvider]): the service constructs
/// instantly and holds a long-lived broadcast controller; consumers
/// that need live data subscribe via `notesForTargetProvider`'s
/// [StreamProvider] which pumps fresh snapshots on every mutation
/// (including writes from other UI surfaces, so adding a note from the
/// target card immediately re-renders the history dialog).

final notesServiceProvider = Provider<NotesService>((ref) {
  final database = ref.watch(databaseProvider);
  final service = NotesService(database);
  ref.onDispose(() {
    // Fire-and-forget close — the broadcaster has no IO side-effects.
    service.dispose();
  });
  return service;
});

/// Live notes for a target. Family-keyed by the logical target id
/// string (catalog id or display name).
final notesForTargetProvider =
    StreamProvider.family<List<JournalNote>, String>((ref, targetId) {
  final service = ref.watch(notesServiceProvider);
  return service.watchTargetNotes(targetId);
});

/// Live notes for a specific sequence run row id.
final notesForRunProvider =
    StreamProvider.family<List<JournalNote>, int>((ref, runId) {
  final service = ref.watch(notesServiceProvider);
  return service.watchRunNotes(runId);
});

/// Live stream of every note (for global search / debug views).
final allNotesProvider = StreamProvider<List<JournalNote>>((ref) {
  final service = ref.watch(notesServiceProvider);
  return service.watchAllNotes();
});

/// Singleton diff engine. Stateless, no setup cost.
final sequenceDiffServiceProvider = Provider<SequenceDiffService>(
  (ref) => const SequenceDiffService(),
);

/// Settings key for the "prompt for notes after run" preference.
const String kPromptForNotesAfterRunKey = 'notes.prompt_after_run';

/// Whether the auto-prompt note dialog should appear after a run
/// completes. Defaults to `true` when the setting has never been
/// written (the journal feature is opt-out, not opt-in: the report
/// is more useful when the user is in the habit of dropping a quick
/// note at the end of every run).
final promptForNotesAfterRunProvider = StreamProvider<bool>((ref) {
  final dao = ref.watch(settingsDaoProvider);
  return dao.watchSetting(kPromptForNotesAfterRunKey).map((raw) {
    if (raw == null) return true;
    return raw.toLowerCase() == 'true';
  });
});

/// Mutator for the auto-prompt preference.
final notesPromptToggleProvider =
    Provider<Future<void> Function(bool)>((ref) {
  final dao = ref.watch(settingsDaoProvider);
  return (bool enabled) async {
    await dao.setSetting(
      kPromptForNotesAfterRunKey,
      enabled.toString(),
    );
  };
});
