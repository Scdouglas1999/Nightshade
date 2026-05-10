import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

/// Standard dialog scaffold matching the Nightshade design system.
///
/// Replaces the hand-rolled `Dialog + Container + custom header + close
/// button` pattern duplicated across screens (equipment settings, cooling
/// temperature picker, centering dialog, etc.). Provides consistent corner
/// radius, border, header styling, and a scrollable body.
///
/// The dialog body scrolls vertically when content exceeds available
/// height, so callers can pass arbitrarily tall content without overflow.
///
/// Usage:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => NightshadeDialog(
///     title: 'Equipment Settings',
///     icon: LucideIcons.settings,
///     width: 700,
///     height: 500,
///     child: const EquipmentSettingsTab(),
///     actions: [NightshadeButton(label: 'Save', onPressed: ...)],
///   ),
/// );
/// ```
class NightshadeDialog extends StatelessWidget {
  /// Header title text. Required for accessibility.
  final String title;

  /// Optional leading icon shown before the title.
  final IconData? icon;

  /// Dialog body. Wrapped in a scroll view automatically.
  final Widget child;

  /// Optional footer actions (typically a row of buttons). Rendered with a
  /// top border separator. Layout is right-aligned to match platform
  /// conventions; pass a `Row` if you need custom alignment.
  final List<Widget>? actions;

  /// Optional callback fired when the user closes the dialog via the close
  /// button. If null, the close button just pops the route.
  final VoidCallback? onClose;

  /// Show the close button in the header. Defaults to true.
  final bool showCloseButton;

  /// Accessible label for the close button. Defaults to "Close dialog".
  final String closeButtonSemanticsLabel;

  /// Fixed dialog width. Defaults to 600px.
  final double width;

  /// Fixed dialog height. If null, the dialog sizes to content (capped by
  /// the parent constraints).
  final double? height;

  /// Padding applied around the body content. Defaults to 20px all sides
  /// to match the design doc's dialog scale.
  final EdgeInsets bodyPadding;

  /// When false, suppresses the body's internal scroll view (useful for
  /// content that already provides its own scrolling).
  final bool scrollableBody;

  const NightshadeDialog({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.actions,
    this.onClose,
    this.showCloseButton = true,
    this.closeButtonSemanticsLabel = 'Close dialog',
    this.width = 600,
    this.height,
    this.bodyPadding = const EdgeInsets.all(NightshadeTokens.spaceXl),
    this.scrollableBody = true,
  });

  void _handleClose(BuildContext context) {
    // Caller-provided onClose runs *before* popping so it can decide to
    // keep the dialog open by re-pushing if needed; in practice callers
    // either tear down state and let it pop, or pop themselves and pass a
    // no-op here.
    if (onClose != null) {
      onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final body = Padding(
      padding: bodyPadding,
      child: child,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(NightshadeTokens.spaceLg),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: NightshadeTokens.borderRadiusMd,
          border: Border.all(color: colors.border),
          boxShadow: NightshadeTokens.elevationLevel3(colors.primary),
        ),
        child: ClipRRect(
          borderRadius: NightshadeTokens.borderRadiusMd,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                title: title,
                icon: icon,
                colors: colors,
                showCloseButton: showCloseButton,
                closeButtonSemanticsLabel: closeButtonSemanticsLabel,
                onClose: () => _handleClose(context),
              ),
              Flexible(
                child: scrollableBody
                    ? SingleChildScrollView(child: body)
                    : body,
              ),
              if (actions != null && actions!.isNotEmpty)
                _Footer(colors: colors, actions: actions!),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final IconData? icon;
  final NightshadeColors colors;
  final bool showCloseButton;
  final String closeButtonSemanticsLabel;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.icon,
    required this.colors,
    required this.showCloseButton,
    required this.closeButtonSemanticsLabel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceXl,
        vertical: NightshadeTokens.spaceMd + 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: colors.textPrimary, size: NightshadeTokens.iconMd),
            const SizedBox(width: NightshadeTokens.spaceMd),
          ],
          Expanded(
            child: Text(
              title,
              style: NightshadeTypography.h4
                  .copyWith(color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showCloseButton)
            Semantics(
              button: true,
              label: closeButtonSemanticsLabel,
              child: IconButton(
                tooltip: closeButtonSemanticsLabel,
                onPressed: onClose,
                icon: Icon(LucideIcons.x, color: colors.textMuted),
                splashRadius: 18,
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final NightshadeColors colors;
  final List<Widget> actions;

  const _Footer({required this.colors, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceXl,
        vertical: NightshadeTokens.spaceMd,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: NightshadeTokens.spaceSm),
            actions[i],
          ],
        ],
      ),
    );
  }
}
