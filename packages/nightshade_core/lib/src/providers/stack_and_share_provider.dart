import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/stacked_results_dao.dart';
import '../models/imaging/stack_and_share_models.dart';
import '../services/logging_service.dart';
import '../services/stack_and_share_service.dart';

/// UI-facing state for the **Stack-and-Share Loop** orchestrator (component C7).
///
/// Wraps the live [StackAndShareProgress] emitted by [StackAndShareService.run]
/// together with the terminal artifacts of the most recent run: the persisted
/// [StackAndShareResult] provenance record (with its DB id), the auto-stretched
/// RGBA display buffer, and the integrated raw u16 mono buffer. A failed run
/// surfaces its cause in [errorMessage] (per project policy errors are never
/// swallowed) while leaving the buffers null.
///
/// This is a plain immutable value class (const constructor + [copyWith]),
/// matching the style of [LiveStackingState] in `live_stacking_provider.dart`.
class StackAndShareState {
  /// Live progress of the current (or most recent) run. Starts at
  /// [StackAndSharePhase.idle].
  final StackAndShareProgress progress;

  /// The persisted result of the most recent successful run, or null when no
  /// run has completed (idle, in-flight, or failed).
  final StackAndShareResult? result;

  /// The auto-stretched RGBA display buffer of the most recent successful run,
  /// or null when the last run did not stretch (mono / `autoStretch` off) or has
  /// not completed. Length is `resultWidth * resultHeight * 4` when present.
  final Uint8List? resultRgba;

  /// Width of [resultRgba] / [resultMono] in pixels (0 when no result).
  final int resultWidth;

  /// Height of [resultRgba] / [resultMono] in pixels (0 when no result).
  final int resultHeight;

  /// The integrated, calibrated raw u16 mono buffer of the most recent
  /// successful run, or null when no run has completed. Length is
  /// `resultWidth * resultHeight` when present.
  final Uint16List? resultMono;

  /// Human-readable failure message when the last run ended in
  /// [StackAndSharePhase.error], else null.
  final String? errorMessage;

  const StackAndShareState({
    this.progress = const StackAndShareProgress(),
    this.result,
    this.resultRgba,
    this.resultWidth = 0,
    this.resultHeight = 0,
    this.resultMono,
    this.errorMessage,
  });

  /// Whether a run is currently in flight (past idle, not yet terminal).
  bool get isRunning =>
      progress.phase != StackAndSharePhase.idle &&
      progress.phase != StackAndSharePhase.complete &&
      progress.phase != StackAndSharePhase.error;

  /// Whether the most recent run completed successfully and produced a result.
  bool get isComplete =>
      progress.phase == StackAndSharePhase.complete && result != null;

  /// Whether the most recent run ended in failure.
  bool get hasError => progress.phase == StackAndSharePhase.error;

  StackAndShareState copyWith({
    StackAndShareProgress? progress,
    StackAndShareResult? result,
    Uint8List? resultRgba,
    int? resultWidth,
    int? resultHeight,
    Uint16List? resultMono,
    String? errorMessage,
  }) {
    return StackAndShareState(
      progress: progress ?? this.progress,
      result: result ?? this.result,
      resultRgba: resultRgba ?? this.resultRgba,
      resultWidth: resultWidth ?? this.resultWidth,
      resultHeight: resultHeight ?? this.resultHeight,
      resultMono: resultMono ?? this.resultMono,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Orchestrator [StateNotifier] that drives the Stack-and-Share pipeline and
/// exposes its progress + result to the UI.
///
/// [runForSession] calls [StackAndShareService.run] with an `onProgress`
/// callback that publishes each phase transition into [state], guarded by the
/// `mounted` check required by CLAUDE.md so a disposed notifier never mutates
/// state. On success it captures the persisted result plus the retained RGBA /
/// mono buffers from the service; on failure it records the error message and
/// leaves a terminal [StackAndSharePhase.error] progress so the UI can render a
/// banner. Errors are rethrow-free at this layer (the notifier owns the failure
/// presentation), but they are never silently dropped — the message is always
/// surfaced into [state].
class StackAndShareNotifier extends StateNotifier<StackAndShareState> {
  StackAndShareNotifier(this._ref) : super(const StackAndShareState());

  final Ref _ref;

  StackAndShareService get _service => _ref.read(stackAndShareServiceProvider);
  LoggingService get _logger => _ref.read(loggingServiceProvider);

  /// Run the full Stack-and-Share pipeline for [sessionId].
  ///
  /// Resets to a fresh in-flight state, streams progress into [state] (with a
  /// `mounted` guard on every update), and on completion captures the persisted
  /// [StackAndShareResult] together with the integrated mono buffer and the
  /// auto-stretched RGBA buffer the service retained. Any thrown error is caught
  /// and recorded in [StackAndShareState.errorMessage]; it is not rethrown so
  /// the calling widget does not need a try/catch around `ref.read(...).run`.
  Future<void> runForSession(
    int sessionId, {
    StackAndShareConfig? config,
  }) async {
    final effectiveConfig = config ?? StackAndShareConfig.defaults;

    // Begin a fresh run: clear any prior result/buffers/error and start at the
    // first real phase the service emits.
    state = const StackAndShareState(
      progress: StackAndShareProgress(
        phase: StackAndSharePhase.selectingLights,
      ),
    );

    try {
      final result = await _service.run(
        sessionId: sessionId,
        config: effectiveConfig,
        onProgress: (p) {
          if (!mounted) return;
          state = state.copyWith(progress: p);
        },
      );

      if (!mounted) return;

      // Capture the terminal artifacts from the service's retained buffers. The
      // service guarantees [lastRawResult] is set on success; the RGBA buffer is
      // present only when the run auto-stretched.
      final raw = _service.lastRawResult;
      final rgba = _service.lastRgbaResult;

      state = StackAndShareState(
        // The service emits the terminal `complete` phase via onProgress, so
        // `state.progress` is already complete here; reuse it to keep the frame
        // counts the service reported.
        progress: state.progress,
        result: result,
        resultWidth: raw?.width ?? result.width,
        resultHeight: raw?.height ?? result.height,
        resultMono: raw?.data,
        resultRgba: rgba?.rgba,
      );
    } catch (e, st) {
      if (!mounted) return;
      // Ensure the terminal error phase is reflected even if the failure
      // happened before the service emitted its own error progress event.
      state = state.copyWith(
        progress: state.progress.phase == StackAndSharePhase.error
            ? state.progress
            : state.progress.copyWith(phase: StackAndSharePhase.error),
        errorMessage: e.toString(),
      );
      _logger.error(
        'Stack-and-Share run failed for session $sessionId: $e',
        source: 'StackAndShareNotifier',
        fields: {'stackTrace': st.toString()},
      );
    }
  }

  /// Reset back to the idle state, discarding the current progress, result, and
  /// retained buffers so the UI returns to its initial empty surface.
  void reset() {
    if (!mounted) return;
    state = const StackAndShareState();
  }
}

/// Orchestrator provider for the Stack-and-Share Loop.
///
/// `autoDispose` so the in-memory RGBA / mono buffers (which can be tens of
/// megabytes for a full-frame integration) are released as soon as the last
/// listener — the Stack-and-Share screen — is torn down.
final stackAndShareProvider = StateNotifierProvider.autoDispose<
    StackAndShareNotifier, StackAndShareState>((ref) {
  return StackAndShareNotifier(ref);
});

/// Loads a single persisted [StackAndShareResult] by its database id for the
/// result viewer.
///
/// Throws [StateError] when no row matches [id] rather than returning a
/// fabricated empty result — a stale / deleted id is a real error the viewer
/// should surface, not silently render as a blank stack (errors are a feature,
/// per CLAUDE.md).
final stackResultViewerProvider =
    FutureProvider.family<StackAndShareResult, int>((ref, id) async {
  final dao = ref.watch(stackedResultsDaoProvider);
  final result = await dao.getResultById(id);
  if (result == null) {
    throw StateError('No stacked result found for id $id');
  }
  return result;
});

/// The most recent stacked results across all sessions, newest first, for any
/// history / gallery surface. Caps at the DAO's default limit.
final recentStackedResultsProvider =
    FutureProvider<List<StackAndShareResult>>((ref) async {
  final dao = ref.watch(stackedResultsDaoProvider);
  return dao.getRecentResults();
});
