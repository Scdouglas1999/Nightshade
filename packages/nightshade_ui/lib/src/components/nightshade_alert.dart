import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Alert severity levels
enum NightshadeAlertSeverity {
  /// Informational alert (blue)
  info,

  /// Success alert (green)
  success,

  /// Warning alert (yellow/orange)
  warning,

  /// Error alert (red)
  error,
}

/// A styled alert/banner component for notifications and status messages.
///
/// Features:
/// - Multiple severity levels (info, success, warning, error)
/// - Optional icon, title, and action button
/// - Dismissible with callback
/// - Animated entrance/exit
class NightshadeAlert extends StatelessWidget {
  const NightshadeAlert({
    super.key,
    required this.message,
    this.severity = NightshadeAlertSeverity.info,
    this.title,
    this.icon,
    this.action,
    this.onDismiss,
    this.showIcon = true,
    this.compact = false,
  });

  /// The main message text
  final String message;

  /// Severity level for styling
  final NightshadeAlertSeverity severity;

  /// Optional title shown above the message
  final String? title;

  /// Custom icon (defaults to severity-appropriate icon)
  final IconData? icon;

  /// Optional action widget (usually a button)
  final Widget? action;

  /// Callback when dismiss button is pressed (shows dismiss button when set)
  final VoidCallback? onDismiss;

  /// Whether to show the severity icon
  final bool showIcon;

  /// Use compact padding
  final bool compact;

  IconData get _defaultIcon {
    return switch (severity) {
      NightshadeAlertSeverity.info => LucideIcons.info,
      NightshadeAlertSeverity.success => LucideIcons.checkCircle2,
      NightshadeAlertSeverity.warning => LucideIcons.alertTriangle,
      NightshadeAlertSeverity.error => LucideIcons.xCircle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final (bgColor, borderColor, iconColor, textColor) = _getColors(colors);

    final padding = compact
        ? const EdgeInsets.symmetric(
            horizontal: NightshadeTokens.spaceMd,
            vertical: NightshadeTokens.spaceSm,
          )
        : const EdgeInsets.all(NightshadeTokens.spaceLg);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: NightshadeTokens.borderRadiusMd,
        border: Border.all(color: borderColor),
      ),
      padding: padding,
      child: Row(
        crossAxisAlignment:
            title != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (showIcon) ...[
            Icon(
              icon ?? _defaultIcon,
              size: compact ? NightshadeTokens.iconSm : NightshadeTokens.iconMd,
              color: iconColor,
            ),
            SizedBox(width: compact ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: (compact ? NightshadeTypography.labelSm : NightshadeTypography.label)
                        .copyWith(color: textColor),
                  ),
                  const SizedBox(height: NightshadeTokens.spaceXs),
                ],
                Text(
                  message,
                  style: (compact ? NightshadeTypography.bodySm : NightshadeTypography.body)
                      .copyWith(color: textColor.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            SizedBox(width: compact ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd),
            action!,
          ],
          if (onDismiss != null) ...[
            SizedBox(width: compact ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd),
            IconButton(
              icon: Icon(
                LucideIcons.x,
                size: compact ? NightshadeTokens.iconSm : NightshadeTokens.iconMd,
              ),
              onPressed: onDismiss,
              color: textColor.withValues(alpha: 0.7),
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: compact ? 24 : 32,
                minHeight: compact ? 24 : 32,
              ),
              splashRadius: compact ? 16 : 20,
            ),
          ],
        ],
      ),
    );
  }

  (Color bg, Color border, Color icon, Color text) _getColors(
      NightshadeColors colors) {
    return switch (severity) {
      NightshadeAlertSeverity.info => (
          colors.info.withValues(alpha: 0.1),
          colors.info.withValues(alpha: 0.3),
          colors.info,
          colors.textPrimary,
        ),
      NightshadeAlertSeverity.success => (
          colors.success.withValues(alpha: 0.1),
          colors.success.withValues(alpha: 0.3),
          colors.success,
          colors.textPrimary,
        ),
      NightshadeAlertSeverity.warning => (
          colors.warning.withValues(alpha: 0.1),
          colors.warning.withValues(alpha: 0.3),
          colors.warning,
          colors.textPrimary,
        ),
      NightshadeAlertSeverity.error => (
          colors.error.withValues(alpha: 0.1),
          colors.error.withValues(alpha: 0.3),
          colors.error,
          colors.textPrimary,
        ),
    };
  }
}

/// An inline banner alert that can be placed within content.
class NightshadeInlineBanner extends StatelessWidget {
  const NightshadeInlineBanner({
    super.key,
    required this.message,
    this.severity = NightshadeAlertSeverity.info,
    this.icon,
    this.showIcon = true,
  });

  final String message;
  final NightshadeAlertSeverity severity;
  final IconData? icon;
  final bool showIcon;

  IconData get _defaultIcon {
    return switch (severity) {
      NightshadeAlertSeverity.info => LucideIcons.info,
      NightshadeAlertSeverity.success => LucideIcons.check,
      NightshadeAlertSeverity.warning => LucideIcons.alertTriangle,
      NightshadeAlertSeverity.error => LucideIcons.alertCircle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final color = _getColor(colors);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIcon) ...[
          Icon(
            icon ?? _defaultIcon,
            size: NightshadeTokens.iconSm,
            color: color,
          ),
          const SizedBox(width: NightshadeTokens.spaceSm),
        ],
        Flexible(
          child: Text(
            message,
            style: NightshadeTypography.bodySm.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  Color _getColor(NightshadeColors colors) {
    return switch (severity) {
      NightshadeAlertSeverity.info => colors.info,
      NightshadeAlertSeverity.success => colors.success,
      NightshadeAlertSeverity.warning => colors.warning,
      NightshadeAlertSeverity.error => colors.error,
    };
  }
}

/// A toast-style notification that appears temporarily.
class NightshadeToast extends StatelessWidget {
  const NightshadeToast({
    super.key,
    required this.message,
    this.severity = NightshadeAlertSeverity.info,
    this.icon,
    this.action,
    this.onDismiss,
  });

  final String message;
  final NightshadeAlertSeverity severity;
  final IconData? icon;
  final Widget? action;
  final VoidCallback? onDismiss;

  IconData get _defaultIcon {
    return switch (severity) {
      NightshadeAlertSeverity.info => LucideIcons.info,
      NightshadeAlertSeverity.success => LucideIcons.checkCircle2,
      NightshadeAlertSeverity.warning => LucideIcons.alertTriangle,
      NightshadeAlertSeverity.error => LucideIcons.xCircle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final color = _getColor(colors);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: NightshadeTokens.borderRadiusMd,
          border: Border.all(color: colors.border),
          boxShadow: NightshadeTokens.shadowLg,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: NightshadeTokens.spaceLg,
          vertical: NightshadeTokens.spaceMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 4,
              height: 32,
              margin: const EdgeInsets.only(right: NightshadeTokens.spaceMd),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Icon(
              icon ?? _defaultIcon,
              size: NightshadeTokens.iconMd,
              color: color,
            ),
            const SizedBox(width: NightshadeTokens.spaceMd),
            Flexible(
              child: Text(
                message,
                style: NightshadeTypography.body.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: NightshadeTokens.spaceMd),
              action!,
            ],
            if (onDismiss != null) ...[
              const SizedBox(width: NightshadeTokens.spaceSm),
              IconButton(
                icon: const Icon(LucideIcons.x, size: NightshadeTokens.iconSm),
                onPressed: onDismiss,
                color: colors.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                splashRadius: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getColor(NightshadeColors colors) {
    return switch (severity) {
      NightshadeAlertSeverity.info => colors.info,
      NightshadeAlertSeverity.success => colors.success,
      NightshadeAlertSeverity.warning => colors.warning,
      NightshadeAlertSeverity.error => colors.error,
    };
  }
}

/// Helper to show toast notifications.
///
/// Usage:
/// ```dart
/// NightshadeToastHelper.show(
///   context: context,
///   message: 'Image saved successfully',
///   severity: NightshadeAlertSeverity.success,
/// );
/// ```
class NightshadeToastHelper {
  static void show({
    required BuildContext context,
    required String message,
    NightshadeAlertSeverity severity = NightshadeAlertSeverity.info,
    IconData? icon,
    Widget? action,
    Duration duration = const Duration(seconds: 4),
    bool dismissible = true,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: NightshadeTokens.space2xl,
        right: NightshadeTokens.space2xl,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: NightshadeTokens.durationNormal,
          curve: NightshadeTokens.curveDecelerate,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(50 * (1 - value), 0),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: NightshadeToast(
            message: message,
            severity: severity,
            icon: icon,
            action: action,
            onDismiss: dismissible ? () => entry.remove() : null,
          ),
        ),
      ),
    );

    overlay.insert(entry);

    Future.delayed(duration, () {
      if (entry.mounted) {
        entry.remove();
      }
    });
  }
}
