import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../models/command_action_result.dart';

/// Extension on BuildContext providing convenient SnackBar display methods.
///
/// All methods check `mounted` before showing to prevent errors when
/// the widget has been disposed.
extension SnackBarHelper on BuildContext {
  /// Shows an error SnackBar with red background.
  void showErrorSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final colors = Theme.of(this).extension<NightshadeColors>()!;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.error,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  /// Shows a success SnackBar with green background.
  void showSuccessSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final colors = Theme.of(this).extension<NightshadeColors>()!;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.success,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Shows a warning SnackBar with amber/yellow background.
  void showWarningSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final colors = Theme.of(this).extension<NightshadeColors>()!;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.warning,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Shows an info SnackBar with default background.
  void showInfoSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration ?? const Duration(seconds: 2),
      ),
    );
  }

  /// Shows user feedback for a command result when it has a message payload.
  void showCommandActionResult(CommandActionResult result,
      {Duration? duration}) {
    if (!result.hasMessage) return;
    final message = result.message!;
    switch (result.feedbackType) {
      case CommandFeedbackType.error:
        showErrorSnackBar(message, duration: duration);
        break;
      case CommandFeedbackType.warning:
        showWarningSnackBar(message, duration: duration);
        break;
      case CommandFeedbackType.info:
        showInfoSnackBar(message, duration: duration);
        break;
      case CommandFeedbackType.success:
        showSuccessSnackBar(message, duration: duration);
        break;
    }
  }
}
