import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../models/command_action_result.dart';

/// Provider for the SequenceActionService.
final sequenceActionServiceProvider =
    Provider((ref) => SequenceActionService(ref));

/// Centralized service for sequence playback actions.
///
/// This eliminates duplicate sequence control implementations across screens.
/// All sequence control buttons should use this service instead of implementing
/// their own try/catch patterns with sequenceExecutorProvider.
class SequenceActionService {
  final Ref _ref;

  SequenceActionService(this._ref);

  SequenceExecutor get _executor => _ref.read(sequenceExecutorProvider);

  /// Starts the sequence.
  ///
  /// Audit C3 — `_executor.start()` is async (full pre-flight validation
  /// including async disk-space). The previous `_executor.start();`
  /// without `await` returned `ok` before validation completed, swallowing
  /// any [SequenceValidationException]. Awaiting it surfaces all
  /// validation errors via the failure path.
  Future<CommandActionResult> start() async {
    try {
      await _executor.start();
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to start sequence: $e');
    }
  }

  /// Pauses the running sequence.
  Future<CommandActionResult> pause() async {
    try {
      await _executor.pause();
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to pause sequence: $e');
    }
  }

  /// Resumes a paused sequence.
  Future<CommandActionResult> resume() async {
    try {
      await _executor.resume();
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to resume sequence: $e');
    }
  }

  /// Stops the sequence.
  ///
  /// Audit C3 — user-initiated stops preserve the checkpoint by default
  /// so the operator can resume the run later (e.g. paused last night,
  /// stopped this morning, want to keep going tonight). Pass
  /// `preserveCheckpoint: false` from a "discard and stop" affordance
  /// when the user explicitly wants the checkpoint cleared.
  Future<CommandActionResult> stop({bool preserveCheckpoint = true}) async {
    try {
      await _executor.stop(preserveCheckpoint: preserveCheckpoint);
      return CommandActionResult.ok;
    } catch (e) {
      return CommandActionResult.failure('Failed to stop sequence: $e');
    }
  }

  /// Skips the current sequence item.
  ///
  /// [showFeedback] - If true, shows a snackbar confirming the skip.
  Future<CommandActionResult> skip({bool showFeedback = true}) async {
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
  }

  /// Resets the sequence to its initial state.
  void reset() {
    _executor.reset();
  }
}
