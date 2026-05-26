import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import '../components/nightshade_button.dart';
import '../dialogs/nightshade_dialog.dart';

/// User-friendly error dialog with optional technical details.
///
/// This widget provides a consistent way to display errors throughout the app
/// with clear, non-technical messages and optional detailed error information.
class ErrorDialog extends StatefulWidget {
  final String title;
  final String message;
  final String? technicalDetails;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.technicalDetails,
    this.onRetry,
    this.onDismiss,
  });

  /// Show the error dialog in the given context.
  ///
  /// Example:
  /// ```dart
  /// ErrorDialog.show(
  ///   context,
  ///   title: 'Connection Failed',
  ///   message: 'Could not connect to the device. Please check your connection and try again.',
  ///   technicalDetails: 'Timeout after 30s: $exception',
  ///   onRetry: () => _reconnect(),
  /// );
  /// ```
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    String? technicalDetails,
    VoidCallback? onRetry,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ErrorDialog(
        title: title,
        message: message,
        technicalDetails: technicalDetails,
        onRetry: onRetry,
        onDismiss: () => Navigator.pop(context),
      ),
    );
  }

  @override
  State<ErrorDialog> createState() => _ErrorDialogState();
}

class _ErrorDialogState extends State<ErrorDialog> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    return Semantics(
      label: 'Error dialog: ${widget.title}',
      child: NightshadeDialog(
        title: widget.title,
        icon: LucideIcons.alertCircle,
        width: 520,
        showCloseButton: false,
        actions: [
          Semantics(
            button: true,
            label: 'Close error dialog',
            child: NightshadeButton(
              label: 'Close',
              onPressed: widget.onDismiss,
              variant: ButtonVariant.ghost,
              size: ButtonSize.medium,
            ),
          ),
          if (widget.onRetry != null)
            Semantics(
              button: true,
              label: 'Retry the failed operation',
              child: NightshadeButton(
                label: 'Retry',
                icon: LucideIcons.refreshCw,
                onPressed: () {
                  widget.onDismiss?.call();
                  widget.onRetry?.call();
                },
                variant: ButtonVariant.primary,
                size: ButtonSize.medium,
              ),
            ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User-friendly message
            Semantics(
              label: 'Error message',
              child: Text(
                widget.message,
                style: NightshadeTypography.body.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),

            // Technical details toggle
            if (widget.technicalDetails != null) ...[
              const SizedBox(height: NightshadeTokens.spaceLg),
              Semantics(
                button: true,
                label: _showDetails
                    ? 'Hide technical details'
                    : 'Show technical details',
                child: InkWell(
                  onTap: () => setState(() => _showDetails = !_showDetails),
                  borderRadius: NightshadeTokens.borderRadiusMd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NightshadeTokens.spaceSm,
                      vertical: NightshadeTokens.spaceSm - 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showDetails
                              ? LucideIcons.chevronDown
                              : LucideIcons.chevronRight,
                          size: NightshadeTokens.iconSm,
                          color: colors.primary,
                        ),
                        const SizedBox(width: NightshadeTokens.spaceSm - 2),
                        Text(
                          _showDetails
                              ? 'Hide Technical Details'
                              : 'View Technical Details',
                          style: NightshadeTypography.label.copyWith(
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Technical details panel
              if (_showDetails) ...[
                const SizedBox(height: NightshadeTokens.spaceMd),
                Semantics(
                  label: 'Technical error details',
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    padding: NightshadeTokens.paddingMd,
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: NightshadeTokens.borderRadiusMd,
                      border: Border.all(color: colors.border),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        widget.technicalDetails!,
                        style: NightshadeTypography.monoSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Helper class for creating user-friendly error messages from exceptions.
class ErrorMessageHelper {
  /// Convert a technical exception message to a user-friendly message.
  static String getUserFriendlyMessage(Object error) {
    final errorString = error.toString();

    // Common error patterns and their user-friendly alternatives
    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return 'The operation took too long to complete. Please check your connection and try again.';
    }

    if (errorString.contains('connection refused') ||
        errorString.contains('failed to connect')) {
      return 'Could not establish a connection. Please verify the device is powered on and accessible.';
    }

    if (errorString.contains('network') || errorString.contains('socket')) {
      return 'A network error occurred. Please check your network connection and try again.';
    }

    if (errorString.contains('permission denied') ||
        errorString.contains('access denied')) {
      return 'Permission was denied. Please check your access rights and try again.';
    }

    if (errorString.contains('not found') || errorString.contains('404')) {
      return 'The requested resource could not be found. It may have been removed or is temporarily unavailable.';
    }

    if (errorString.contains('invalid') || errorString.contains('parse')) {
      return 'The data received was invalid or could not be processed.';
    }

    // Default fallback
    return 'An unexpected error occurred. Please try again.';
  }

  /// Get appropriate title based on error type.
  static String getErrorTitle(Object error) {
    final errorString = error.toString();

    if (errorString.contains('timeout') || errorString.contains('timed out')) {
      return 'Connection Timeout';
    }

    if (errorString.contains('connection') || errorString.contains('network')) {
      return 'Connection Failed';
    }

    if (errorString.contains('permission') || errorString.contains('access')) {
      return 'Access Denied';
    }

    if (errorString.contains('not found')) {
      return 'Not Found';
    }

    return 'Error';
  }

  /// Show an error dialog with automatically generated user-friendly messages.
  static Future<void> showError(
    BuildContext context, {
    required Object error,
    String? title,
    String? message,
    VoidCallback? onRetry,
  }) {
    return ErrorDialog.show(
      context,
      title: title ?? getErrorTitle(error),
      message: message ?? getUserFriendlyMessage(error),
      technicalDetails: error.toString(),
      onRetry: onRetry,
    );
  }
}
