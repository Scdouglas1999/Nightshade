import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';

/// An accessible icon button with proper semantics and focus support.
///
/// This widget wraps IconButton with accessibility features including:
/// - Semantic labels for screen readers
/// - Keyboard focus support
/// - Proper enabled/disabled states
/// - Tooltip support
class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final bool autofocus;

  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.tooltip,
    this.onPressed,
    this.color,
    this.size = 24,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final effectiveColor = color ?? colors.textPrimary;
    final isEnabled = onPressed != null;

    return Semantics(
      button: true,
      label: label,
      enabled: isEnabled,
      child: Tooltip(
        message: tooltip ?? label,
        child: IconButton(
          icon: Icon(icon),
          iconSize: size,
          color: isEnabled ? effectiveColor : colors.textMuted,
          onPressed: onPressed,
          autofocus: autofocus,
          splashRadius: size + 4,
        ),
      ),
    );
  }
}
