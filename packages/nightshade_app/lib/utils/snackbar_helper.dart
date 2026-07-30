import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../models/command_action_result.dart';
import 'transient_bottom_inset.dart';

/// Extension on BuildContext providing convenient SnackBar display methods.
///
/// All methods check `mounted` before showing to prevent errors when
/// the widget has been disposed.
///
/// Snackbars are floating (see the app theme), so they are anchored to the
/// bottom of the enclosing [Scaffold] and would otherwise be drawn straight
/// over a screen's own bottom bar. [TransientBottomInset] lets a screen declare
/// the height it needs kept clear — on the Imaging screen that is the
/// Snapshot / Loop / Duration strip — and every helper here honours it.
extension SnackBarHelper on BuildContext {
  /// Margin that lifts a floating snackbar clear of the current screen's
  /// bottom bar. Null when the screen declares no inset, so the framework's
  /// default placement is untouched.
  EdgeInsetsGeometry? get _snackBarMargin {
    final inset = TransientBottomInset.of(this);
    if (inset <= 0) return null;
    // Mirrors the framework's own floating-snackbar margin, plus the bar.
    return EdgeInsets.fromLTRB(15, 5, 15, 10 + inset);
  }

  /// Shows an error SnackBar with red background.
  void showErrorSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final colors = NightshadeColors.of(this);
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.error,
        margin: _snackBarMargin,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  /// Shows a success SnackBar with green background.
  void showSuccessSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final colors = NightshadeColors.of(this);
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.success,
        margin: _snackBarMargin,
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }

  /// Shows a warning SnackBar with amber/yellow background.
  void showWarningSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final colors = NightshadeColors.of(this);
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: colors.warning,
        margin: _snackBarMargin,
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
        margin: _snackBarMargin,
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
