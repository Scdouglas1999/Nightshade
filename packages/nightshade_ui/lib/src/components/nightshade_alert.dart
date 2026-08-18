import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
    final colors = context.nightshadeColors;
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
      child: _IntrinsicSafeLayout(
        child: LayoutBuilder(
          builder: (context, constraints) =>
              _body(constraints, iconColor, textColor),
        ),
      ),
    );
  }

  /// The alert's contents, laid out against the width it was actually given.
  ///
  /// A `Row` measures its INFLEXIBLE children against the full incoming width
  /// before it hands what is left to the flexible ones. An action appended
  /// unbounded therefore takes whatever it wants — a `Wrap` of two buttons
  /// measures as one ~450px run and never wraps — and the text column, the only
  /// `Expanded` child, is left the remainder. Measured on this component: at a
  /// 430px window the Darkroom's branch-delete refusal gave its title 0px and
  /// laid it out one glyph per line down a 6,395px column that took the whole
  /// editor off screen; at 700px the title still measured 0px.
  ///
  /// Two rules, and the width chooses between them:
  ///
  ///  - **Wide** (at least [NightshadeTokens.breakpointMobile]): the action
  ///    stays beside the text and is bounded to half the alert. Bounded, a
  ///    `Wrap` reflows onto extra runs instead of running off the edge, and the
  ///    sentence it answers always keeps the other half. A small action is
  ///    unaffected — natural width, flush against the trailing edge, exactly
  ///    where it has always been.
  ///  - **Narrow**: bounding is not enough. Half of 430px is a column the
  ///    message wraps down for 800px, which removes the screen just as surely
  ///    as the glyph column did. So the action moves into the text column,
  ///    under the title and above the message, at the alert's own width.
  ///
  /// Under the TITLE, not under the whole text, and that placement is load
  /// bearing: the Darkroom's recipe panel is a ~330px scrolling column whose
  /// "Show more" lives inside the alert precisely so the truncated sentence and
  /// the control that completes it share one viewport. Below a seven-line
  /// message that control lands past the panel's fold — measured, not
  /// supposed — which trades this defect for the one it was built to fix.
  /// Under the title it stays where the reader already is. An alert with no
  /// title has nothing to sit under, so its action follows the message.
  ///
  /// An unbounded width (an alert inside a horizontal scroller) has no half to
  /// take and no width to compare, and keeps the plain row.
  Widget _body(BoxConstraints constraints, Color iconColor, Color textColor) {
    final gap = compact ? NightshadeTokens.spaceSm : NightshadeTokens.spaceMd;
    final bounded = constraints.maxWidth.isFinite;
    final stacked =
        action != null &&
        bounded &&
        constraints.maxWidth < NightshadeTokens.breakpointMobile;

    return Row(
      crossAxisAlignment: title != null
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (showIcon) ...[
          Icon(
            icon ?? _defaultIcon,
            size: compact ? NightshadeTokens.iconSm : NightshadeTokens.iconMd,
            color: iconColor,
          ),
          SizedBox(
            width: compact
                ? NightshadeTokens.spaceSm
                : NightshadeTokens.spaceMd,
          ),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null) ...[
                Text(
                  title!,
                  style:
                      (compact
                              ? NightshadeTypography.labelSm
                              : NightshadeTypography.label)
                          .copyWith(color: textColor),
                ),
                const SizedBox(height: NightshadeTokens.spaceXs),
              ],
              if (stacked && title != null) ...[
                Align(alignment: Alignment.centerRight, child: action!),
                SizedBox(height: gap),
              ],
              Text(
                message,
                style:
                    (compact
                            ? NightshadeTypography.bodySm
                            : NightshadeTypography.body)
                        .copyWith(color: textColor.withValues(alpha: 0.9)),
              ),
              if (stacked && title == null) ...[
                SizedBox(height: gap),
                Align(alignment: Alignment.centerRight, child: action!),
              ],
            ],
          ),
        ),
        if (action != null && !stacked) ...[
          SizedBox(width: gap),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: bounded ? constraints.maxWidth / 2 : double.infinity,
            ),
            child: action!,
          ),
        ],
        if (onDismiss != null) ...[
          SizedBox(
            width: compact
                ? NightshadeTokens.spaceSm
                : NightshadeTokens.spaceMd,
          ),
          IconButton(
            icon: Icon(
              LucideIcons.x,
              size: compact ? NightshadeTokens.iconSm : NightshadeTokens.iconMd,
              // An icon-only control with no text of its own; without a name
              // the only way out of the alert is a blank button.
              semanticLabel: 'Dismiss',
            ),
            tooltip: 'Dismiss',
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
    );
  }

  (Color bg, Color border, Color icon, Color text) _getColors(
    NightshadeColors colors,
  ) {
    return switch (severity) {
      NightshadeAlertSeverity.info => (
        Color.alphaBlend(
          colors.info.withValues(alpha: 0.06),
          colors.surfaceAlt,
        ),
        colors.info.withValues(alpha: 0.35),
        colors.info,
        colors.textPrimary,
      ),
      NightshadeAlertSeverity.success => (
        Color.alphaBlend(
          colors.success.withValues(alpha: 0.06),
          colors.surfaceAlt,
        ),
        colors.success.withValues(alpha: 0.35),
        colors.success,
        colors.textPrimary,
      ),
      NightshadeAlertSeverity.warning => (
        Color.alphaBlend(
          colors.warning.withValues(alpha: 0.06),
          colors.surfaceAlt,
        ),
        colors.warning.withValues(alpha: 0.35),
        colors.warning,
        colors.textPrimary,
      ),
      NightshadeAlertSeverity.error => (
        Color.alphaBlend(
          colors.error.withValues(alpha: 0.06),
          colors.surfaceAlt,
        ),
        colors.error.withValues(alpha: 0.35),
        colors.error,
        colors.textPrimary,
      ),
    };
  }
}

/// Answers intrinsic-dimension queries so they never reach the
/// [LayoutBuilder] beneath it, which cannot answer them — measuring a
/// LayoutBuilder speculatively would run its build callback against the live
/// tree, so the framework throws instead. [AlertDialog] measures its content
/// with `IntrinsicWidth`, which made every alert-with-action inside a dialog
/// crash at layout.
///
/// Zero is the honest answer for a wrapping banner: the alert conforms to
/// whatever width its parent chooses and wraps its text there, so it has no
/// preferred width of its own to report, and letting it drive an
/// `IntrinsicWidth` parent wider would size a dialog to the alert's longest
/// unwrapped line. Inside a measuring parent the alert therefore defers to
/// its siblings for sizing; everywhere else these overrides are never called
/// and layout is untouched.
class _IntrinsicSafeLayout extends SingleChildRenderObjectWidget {
  const _IntrinsicSafeLayout({super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicSafeLayout();
}

class _RenderIntrinsicSafeLayout extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;
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
    final colors = context.nightshadeColors;
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
    final colors = context.nightshadeColors;
    final color = _getColor(colors);

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: NightshadeTokens.borderRadiusMd,
          border: Border.all(color: colors.border),
          boxShadow: NightshadeTokens.shadowMd,
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
    showInOverlay(
      overlay: Overlay.of(context),
      message: message,
      severity: severity,
      icon: icon,
      action: action,
      duration: duration,
      dismissible: dismissible,
    );
  }

  /// Shows a toast in an already-resolved overlay.
  ///
  /// This is useful for app-level launchers that intentionally wrap the root
  /// Navigator and therefore cannot discover its descendant overlay from their
  /// own [BuildContext].
  static void showInOverlay({
    required OverlayState overlay,
    required String message,
    NightshadeAlertSeverity severity = NightshadeAlertSeverity.info,
    IconData? icon,
    Widget? action,
    Duration duration = const Duration(seconds: 4),
    bool dismissible = true,
  }) {
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
              child: Opacity(opacity: value, child: child),
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
