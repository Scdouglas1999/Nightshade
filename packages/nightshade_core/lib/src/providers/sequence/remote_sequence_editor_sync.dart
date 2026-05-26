import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/network_backend.dart';
import '../../backend/nightshade_backend.dart';
import '../../models/sequence/sequence_models.dart';
import '../../services/logging_service.dart';
import '../../services/sequence_repository.dart';
import '../backend_provider.dart';
import '../sequence_provider.dart';
import 'sequence_catalog_sync.dart';
import 'sequence_editor.dart';

const _logSource = 'RemoteSequenceEditorSync';

/// Debounce window for pushing in-editor sequence changes to a remote host.
const remoteSequenceAutoSaveDebounce = Duration(milliseconds: 1500);

/// Debounced auto-save of the in-editor sequence to a remote imaging host.
///
/// Mobile/tablet companions edit in memory; this provider pushes changes to the
/// host via [SequenceRepository.saveSequence] (NetworkBackend `save-full`).
final remoteSequenceEditorSyncProvider = Provider<void>((ref) {
  Timer? debounce;
  // Tracks whether the provider has been disposed. We cannot call
  // `ref.read(...)` inside an `onDispose` continuation because the
  // container is already in tear-down — that throws
  //   "Tried to read a provider from a ProviderContainer that was
  //    already disposed"
  // (see widgets/ui_scale_test.dart failure, where the host
  // ProviderScope unmounts and bubbles the throw up to the test
  // runner). The previous "unawaited(flushPending(reason:
  // 'provider_dispose'))" line tried to do a best-effort final save
  // during tear-down but in practice that save NEVER completes — by
  // the time the microtask runs the container is gone and the very
  // first `ref.read` inside flushPending throws. There is therefore
  // no behavioural regression in dropping the dispose-time flush;
  // remote auto-save still happens on every debounce window and on
  // backend disconnect, which is when an in-flight edit actually
  // needs to be pushed.
  var isDisposed = false;

  Future<void> flushPending({required String reason}) async {
    debounce?.cancel();
    debounce = null;
    if (isDisposed) return;
    if (ref.read(currentSequenceProvider) == null) return;
    await _persistRemoteSequence(ref, reason: reason);
  }

  ref.onDispose(() {
    isDisposed = true;
    debounce?.cancel();
    debounce = null;
  });

  ref.listen<NightshadeBackend>(backendProvider, (previous, next) {
    if (previous is NetworkBackend && next is! NetworkBackend) {
      unawaited(flushPending(reason: 'backend_disconnect'));
    }
    if (next is! NetworkBackend) {
      debounce?.cancel();
      debounce = null;
    }
  });

  ref.listen<Sequence?>(currentSequenceProvider, (previous, next) {
    final backend = ref.read(backendProvider);
    if (backend is! NetworkBackend) return;
    if (next == null) {
      debounce?.cancel();
      debounce = null;
      return;
    }

    final editor = ref.read(currentSequenceProvider.notifier);
    if (!editor.isDirty) return;
    if (!ref.read(canEditSequenceProvider)) return;

    debounce?.cancel();
    debounce = Timer(remoteSequenceAutoSaveDebounce, () {
      unawaited(flushPending(reason: 'debounced_edit'));
    });
  });
});

Future<void> _persistRemoteSequence(
  Ref ref, {
  required String reason,
}) async {
  final backend = ref.read(backendProvider);
  if (backend is! NetworkBackend) return;

  final editor = ref.read(currentSequenceProvider.notifier);
  if (!editor.isDirty) return;
  if (!ref.read(canEditSequenceProvider)) return;

  final sequence = ref.read(currentSequenceProvider);
  if (sequence == null) return;

  final logger = ref.read(loggingServiceProvider);
  final repository = ref.read(sequenceRepositoryProvider);

  try {
    final savedId = await repository.saveSequence(sequence);
    editor.applyRemoteSave(savedId);
    ref.invalidate(savedSequencesProvider);
    logger.info(
      'Remote sequence auto-save complete ($reason): '
      '"${sequence.name}" id=$savedId',
      source: _logSource,
    );
  } catch (e, stackTrace) {
    logger.error(
      'Remote sequence auto-save failed ($reason): $e',
      source: _logSource,
      fields: {'stackTrace': '$stackTrace', 'sequenceName': sequence.name},
    );
    developer.log(
      'Remote sequence auto-save failed: $e',
      name: _logSource,
      level: 1000,
      error: e,
      stackTrace: stackTrace,
    );
  }
}
