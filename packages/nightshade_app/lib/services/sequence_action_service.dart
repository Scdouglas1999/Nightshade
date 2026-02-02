import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../utils/snackbar_helper.dart';

/// Provider for the SequenceActionService.
final sequenceActionServiceProvider = Provider((ref) => SequenceActionService(ref));

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
  Future<bool> start() async {
    try {
      _executor.start();
      return true;
    } catch (e) {
      _ref.read(uiNotificationProvider.notifier).showError(
        'Failed to start sequence: $e',
        title: 'Sequence Error',
      );
      return false;
    }
  }

  /// Pauses the running sequence.
  Future<bool> pause(BuildContext context) async {
    try {
      await _executor.pause();
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to pause sequence: $e');
      return false;
    }
  }

  /// Resumes a paused sequence.
  Future<bool> resume(BuildContext context) async {
    try {
      await _executor.resume();
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to resume sequence: $e');
      return false;
    }
  }

  /// Stops the sequence, optionally showing a confirmation dialog.
  ///
  /// [requireConfirmation] - If true, shows a confirmation dialog before stopping.
  Future<bool> stop(BuildContext context, {bool requireConfirmation = false}) async {
    if (requireConfirmation) {
      final colors = Theme.of(context).extension<NightshadeColors>()!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Stop Sequence?'),
          content: const Text('This will stop the current sequence. Are you sure?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: colors.error),
              child: const Text('Stop'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
    }

    try {
      await _executor.stop();
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to stop sequence: $e');
      return false;
    }
  }

  /// Skips the current sequence item.
  ///
  /// [showFeedback] - If true, shows a snackbar confirming the skip.
  Future<bool> skip(BuildContext context, {bool showFeedback = true}) async {
    try {
      await _executor.skip();
      if (showFeedback) {
        context.showInfoSnackBar('Skipped current item');
      }
      return true;
    } catch (e) {
      context.showErrorSnackBar('Failed to skip: $e');
      return false;
    }
  }

  /// Resets the sequence to its initial state.
  void reset() {
    _executor.reset();
  }
}
