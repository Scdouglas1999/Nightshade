import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/network_backend.dart';
import '../models/notes/journal_note.dart';
import '../services/notes_service.dart';
import '../services/sequence_diff_service.dart';
import 'backend_provider.dart';
import 'database_provider.dart';

/// Riverpod surface for per-target / per-run notes
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
///
/// On a remote client (`NetworkBackend`) the journal lives only on the
/// master; the slave's local `notes_journal` table is never populated. We
/// poll the host's `GET /api/db/notes?targetId=` and map each
/// [RemoteJournalNote] onto [JournalNote]. The local `NotesService` path is
/// unchanged for the host backend.
final notesForTargetProvider = StreamProvider.family<List<JournalNote>, String>(
  (ref, targetId) {
    final backend = ref.watch(backendProvider);
    if (backend is NetworkBackend) {
      return _pollRemoteNotes(backend, targetId: targetId);
    }
    final service = ref.watch(notesServiceProvider);
    return service.watchTargetNotes(targetId);
  },
);

/// Live notes for a specific sequence run row id.
final notesForRunProvider = StreamProvider.family<List<JournalNote>, int>((
  ref,
  runId,
) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteNotes(backend, runId: runId);
  }
  final service = ref.watch(notesServiceProvider);
  return service.watchRunNotes(runId);
});

/// Live stream of every note (for global search / debug views).
final allNotesProvider = StreamProvider<List<JournalNote>>((ref) {
  final backend = ref.watch(backendProvider);
  if (backend is NetworkBackend) {
    return _pollRemoteNotes(backend);
  }
  final service = ref.watch(notesServiceProvider);
  return service.watchAllNotes();
});

/// Polls the host's journal notes, emitting only on change (mirrors the
/// `_pollRemote` change-guard in `database_provider.dart`). [targetId] /
/// [runId] scope the poll for the family variants.
Stream<List<JournalNote>> _pollRemoteNotes(
  NetworkBackend backend, {
  String? targetId,
  int? runId,
  Duration interval = const Duration(seconds: 10),
}) async* {
  var last = await _fetchRemoteNotes(backend, targetId: targetId, runId: runId);
  yield last;
  while (true) {
    await Future<void>.delayed(interval);
    final next = await _fetchRemoteNotes(
      backend,
      targetId: targetId,
      runId: runId,
    );
    if (!listEquals(last, next)) {
      last = next;
      yield next;
    }
  }
}

Future<List<JournalNote>> _fetchRemoteNotes(
  NetworkBackend backend, {
  String? targetId,
  int? runId,
}) async {
  final page = await backend.fetchJournalNotes(
    targetId: targetId,
    runId: runId,
  );
  final mapped = page.items.map(_noteFromRemote).toList()
    // Host serves created_at desc; keep newest-first.
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return mapped;
}

JournalNote _noteFromRemote(RemoteJournalNote row) {
  return JournalNote(
    id: row.id,
    targetId: row.targetId,
    sequenceRunId: row.sequenceRunId,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    title: row.title,
    body: row.body,
    tags: row.tags,
    attachments: row.attachments,
    sentiment: row.sentiment,
  );
}

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
final notesPromptToggleProvider = Provider<Future<void> Function(bool)>((ref) {
  final dao = ref.watch(settingsDaoProvider);
  return (bool enabled) async {
    await dao.setSetting(kPromptForNotesAfterRunKey, enabled.toString());
  };
});
