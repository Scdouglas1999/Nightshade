import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

enum ButtonVariant { primary, outline, ghost, destructive }

enum ButtonSize { small, medium, large }

/// Solid-fill button with subtle borders and pressed darkening.
class NightshadeButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final bool isLoading;

  const NightshadeButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.medium,
    this.isLoading = false,
  });

  @override
  State<NightshadeButton> createState() => _NightshadeButtonState();
}

class _NightshadeButtonState extends State<NightshadeButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isPressed = false;

  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      duration: NightshadeTokens.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(
        parent: _pressController,
        curve: NightshadeTokens.curveSnappy,
      ),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (!mounted || _isHovered == value) return;
    setState(() => _isHovered = value);
  }

  void _handleTapDown(TapDownDetails details) {
    if (!mounted || widget.onPressed == null || widget.isLoading) return;
    setState(() => _isPressed = true);
    _pressController.forward();
  }

  void _handleTapUp(TapUpDetails details) => _releasePress();
  void _handleTapCancel() => _releasePress();

  void _releasePress() {
    if (!mounted || !_isPressed) return;
    setState(() => _isPressed = false);
    _pressController.reverse();
  }

  EdgeInsets get _padding {
    return switch (widget.size) {
      ButtonSize.small => const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceSm + 2,
        vertical: NightshadeTokens.spaceSm - 2,
      ),
      ButtonSize.medium => const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceMd + 2,
        vertical: NightshadeTokens.spaceSm + 2,
      ),
      ButtonSize.large => const EdgeInsets.symmetric(
        horizontal: NightshadeTokens.spaceLg + 2,
        vertical: NightshadeTokens.spaceMd + 2,
      ),
    };
  }

  TextStyle get _textStyle {
    return switch (widget.size) {
      ButtonSize.small => NightshadeTypography.captionSm.copyWith(
        fontWeight: FontWeight.w500,
      ),
      ButtonSize.medium => NightshadeTypography.buttonSm,
      ButtonSize.large => NightshadeTypography.button,
    };
  }

  double get _iconSize {
    return switch (widget.size) {
      ButtonSize.small => NightshadeTokens.iconXs - 2,
      ButtonSize.medium => NightshadeTokens.iconXs,
      ButtonSize.large => NightshadeTokens.iconSm,
    };
  }

  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.nightshadeColors;
    final colorScheme = theme.colorScheme;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    final Color foregroundColor;
    final Color borderColor;
    Color? flatColor;

    switch (widget.variant) {
      case ButtonVariant.primary:
        (flatColor, foregroundColor, borderColor) = _buildFilled(
          colors.primary,
          colors,
          colorScheme.onPrimary,
          isDisabled: isDisabled,
        );
      case ButtonVariant.destructive:
        (flatColor, foregroundColor, borderColor) = _buildFilled(
          colors.error,
          colors,
          colorScheme.onError,
          isDisabled: isDisabled,
        );
      case ButtonVariant.outline:
        flatColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.08)
            : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textPrimary;
        borderColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.45)
            : colors.border;
      case ButtonVariant.ghost:
        flatColor = _isHovered && !isDisabled
            ? colors.surfaceHover
            : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textSecondary;
        borderColor = Colors.transparent;
    }

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _releasePress();
        },
        cursor: isDisabled
            ? SystemMouseCursors.forbidden
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          onTap: isDisabled ? null : widget.onPressed,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              );
            },
            child: AnimatedContainer(
              duration: NightshadeTokens.durationQuick,
              curve: NightshadeTokens.curveSnappy,
              decoration: BoxDecoration(
                color: flatColor,
                borderRadius: NightshadeTokens.borderRadiusSm,
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: _padding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.isLoading) ...[
                      SizedBox(
                        width: _iconSize,
                        height: _iconSize,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(foregroundColor),
                        ),
                      ),
                      const SizedBox(width: NightshadeTokens.spaceSm),
                    ] else if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: _iconSize,
                        color: foregroundColor,
                      ),
                      const SizedBox(width: NightshadeTokens.spaceSm - 2),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        style: _textStyle.copyWith(color: foregroundColor),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color?, Color, Color) _buildFilled(
    Color base,
    NightshadeColors colors,
    Color onColor, {
    required bool isDisabled,
  }) {
    if (isDisabled) {
      return (colors.surfaceAlt, colors.textMuted, colors.border);
    }
    if (_isPressed) {
      return (_darkenColor(base, 0.1), onColor, _darkenColor(base, 0.15));
    }
    if (_isHovered) {
      return (_lightenColor(base, 0.04), onColor, _darkenColor(base, 0.08));
    }
    return (base, onColor, _darkenColor(base, 0.12));
  }
}
