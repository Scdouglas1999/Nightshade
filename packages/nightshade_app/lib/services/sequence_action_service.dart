import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../models/command_action_result.dart';

/// Provider for the SequenceActionService.
final sequenceActionServiceProvider =
    Provider((ref) => SequenceActionService(ref));

/// The distinct playback commands, keyed for the shared single-flight latch.
enum _SequenceCommand { start, pause, resume, stop, skip, reset }

/// Centralized service for sequence playback actions.
///
/// This eliminates duplicate sequence control implementations across screens.
/// All sequence control buttons should use this service instead of implementing
/// their own try/catch patterns with sequenceExecutorProvider.
///
/// Shared single-flight: every playback surface — the desktop toolbar, the
/// mobile playback bar, the dashboard cockpit strip, and the persistent
/// app-shell mini bar — routes through this ONE service instance (the provider
/// is app-scoped), so the [_inFlight] latch below is shared across all of them.
/// Two of those surfaces are on screen at the same time during a run (the
/// dashboard renders both the cockpit strip and the mini bar), so a stray
/// double-press — one on each — is a real scenario, not just a fast double-tap.
class SequenceActionService {
  final Ref _ref;

  SequenceActionService(this._ref);

  SequenceExecutor get _executor => _ref.read(sequenceExecutorProvider);

  /// One in-flight future per command kind. A second call of the SAME command
  /// while the first is still running JOINS that future instead of issuing a
  /// duplicate backend command.
  ///
  /// Why it matters per command:
  ///   * skip — the executor's `skip()` has NO single-use guard of its own, so
  ///     without this two concurrent skips advance the native node pointer
  ///     twice (a silent double-skip).
  ///   * start — a double-fired preflight callback (or a start from two
  ///     surfaces) would otherwise bounce off the executor's start latch with a
  ///     StateError surfaced as a scary red snackbar.
  ///   * pause / resume — the executor rejects a concurrent pause/resume with
  ///     "operation already in progress"; joining turns a double-tap into one
  ///     command with one truthful result instead of that error.
  ///   * stop / reset — the executor already coalesces these internally; the
  ///     latch keeps the surfaced result identical for every joined caller.
  final Map<_SequenceCommand, Future<CommandActionResult>> _inFlight = {};

  /// Run [body] under the single-flight latch for [kind]: return the in-flight
  /// future if one exists, otherwise start [body], track it, and clear the
  /// latch when it settles so the next press issues a fresh command.
  Future<CommandActionResult> _single(
    _SequenceCommand kind,
    Future<CommandActionResult> Function() body,
  ) {
    final existing = _inFlight[kind];
    if (existing != null) return existing;
    late final Future<CommandActionResult> future;
    future = body().whenComplete(() {
      if (identical(_inFlight[kind], future)) _inFlight.remove(kind);
    });
    _inFlight[kind] = future;
    return future;
  }

  /// Starts the sequence.
  ///
  /// Audit C3 — `_executor.start()` is async (full pre-flight validation
  /// including async disk-space). The previous `_executor.start();`
  /// without `await` returned `ok` before validation completed, swallowing
  /// any [SequenceValidationException]. Awaiting it surfaces all
  /// validation errors via the failure path.
  Future<CommandActionResult> start() =>
      _single(_SequenceCommand.start, () async {
        if (!_ref.read(sequenceExecutionStateProvider).canStart) {
          return CommandActionResult.ok;
        }
        try {
          await _executor.start();
          return CommandActionResult.ok;
        } catch (e) {
          return CommandActionResult.failure('Failed to start sequence: $e');
        }
      });

  /// Pauses the running sequence.
  Future<CommandActionResult> pause() => _single(
      _SequenceCommand.pause,
      () => _afterStart(() async {
            if (!_ref.read(sequenceExecutionStateProvider).canPause) {
              return CommandActionResult.ok;
            }
            try {
              await _executor.pause();
              return CommandActionResult.ok;
            } catch (e) {
              return CommandActionResult.failure(
                  'Failed to pause sequence: $e');
            }
          }));

  /// Resumes a paused sequence.
  Future<CommandActionResult> resume() => _single(
      _SequenceCommand.resume,
      () => _afterStart(() async {
            if (!_ref.read(sequenceExecutionStateProvider).canResume) {
              return CommandActionResult.ok;
            }
            try {
              await _executor.resume();
              return CommandActionResult.ok;
            } catch (e) {
              return CommandActionResult.failure(
                  'Failed to resume sequence: $e');
            }
          }));

  /// Stops the sequence.
  ///
  /// Audit C3 — user-initiated stops preserve the checkpoint by default
  /// so the operator can resume the run later (e.g. paused last night,
  /// stopped this morning, want to keep going tonight). Pass
  /// `preserveCheckpoint: false` from a "discard and stop" affordance
  /// when the user explicitly wants the checkpoint cleared.
  ///
  /// Single-flight note: a Stop retry (from stopFailed / cleanupFailed) or a
  /// second surface pressing Stop JOINS the in-flight stop — the first caller's
  /// [preserveCheckpoint] intent wins, matching the executor's own
  /// finalization join, so a retry never duplicates the native stop or cleanup.
  Future<CommandActionResult> stop({bool preserveCheckpoint = true}) => _single(
      _SequenceCommand.stop,
      () => _afterStart(() async {
            // start() publishes `running` before it has finished acquiring the
            // session, run row, event subscription, and native executor. A Stop
            // from another visible control surface during that window must wait;
            // otherwise teardown can race resources that start is still creating.
            if (!_ref.read(sequenceExecutionStateProvider).canStop) {
              return CommandActionResult.ok;
            }
            try {
              await _executor.stop(preserveCheckpoint: preserveCheckpoint);
              return CommandActionResult.ok;
            } catch (e) {
              return CommandActionResult.failure('Failed to stop sequence: $e');
            }
          }));

  /// Skips the current sequence item.
  ///
  /// [showFeedback] - If true, shows a snackbar confirming the skip.
  ///
  /// Guards on [SequenceExecutionStateCapabilities.canSkip] before forwarding:
  /// skip only advances the node pointer while the run is running or paused, so
  /// if the state has already moved on (e.g. the run ended between the tap and
  /// this async callback) we return a silent no-op instead of issuing a
  /// meaningless native skip and then falsely reporting "Skipped current item".
  Future<CommandActionResult> skip({bool showFeedback = true}) => _single(
      _SequenceCommand.skip,
      () => _afterStart(() async {
            if (!_ref.read(sequenceExecutionStateProvider).canSkip) {
              return CommandActionResult.ok;
            }
            try {
              await _executor.skip();
              if (showFeedback) {
                return const CommandActionResult.success(
                  message: 'Skipped current item',
                  feedbackType: CommandFeedbackType.info,
                );
              }
              return CommandActionResult.ok;
            } catch (e) {
              return CommandActionResult.failure('Failed to skip: $e');
            }
          }));

  /// Resets the sequence to its initial state.
  ///
  /// Awaited end to end: [SequenceExecutor.reset] first stops any live (or
  /// stop-failed / cleanup-failed) run before clearing progress — and a stop
  /// that cannot confirm the hardware stopped (or whose cleanup failed) throws,
  /// so the reset does NOT force a resettable idle. Returning a
  /// [CommandActionResult] (instead of the old fire-and-forget `void`) lets
  /// toolbar callbacks await the reset, gate their busy state on it, and
  /// surface a failure instead of silently swallowing it.
  Future<CommandActionResult> reset() => _single(
      _SequenceCommand.reset,
      () => _afterStart(() async {
            if (!_ref.read(sequenceExecutionStateProvider).canReset) {
              return CommandActionResult.ok;
            }
            try {
              await _executor.reset();
              return CommandActionResult.ok;
            } catch (e) {
              return CommandActionResult.failure(
                  'Failed to reset sequence: $e');
            }
          }));

  Future<CommandActionResult> _afterStart(
    Future<CommandActionResult> Function() body,
  ) {
    final start = _inFlight[_SequenceCommand.start];
    if (start == null) return body();
    return start.then((_) => body());
  }
}
