import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

enum ButtonVariant { primary, outline, ghost, destructive }

enum ButtonSize { small, medium, large }

/// A button matching the Nightshade visual-polish design doc
/// (`docs/plans/2026-01-07-ui-visual-polish-design.md`, §3 Button Hierarchy).
///
/// Filled variants (primary/destructive) use a vertical
/// `LinearGradient(primary.lighten(5) → primary)` for depth, a soft accent
/// glow on hover, and a flat darkened press state.
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
          parent: _pressController, curve: NightshadeTokens.curveSnappy),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  // Hover/press setState calls run synchronously: MouseRegion and
  // GestureDetector callbacks fire outside the build phase, so the
  // post-frame indirection we used to do here just added a frame of lag.
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
      ButtonSize.small =>
        NightshadeTypography.captionSm.copyWith(fontWeight: FontWeight.w500),
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

  /// Lighten via HSL — the design doc's `primary.lighten(5)` shorthand.
  /// `amount` is a fractional lightness delta (0.05 = "+5").
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
    final colors = theme.extension<NightshadeColors>()!;
    final colorScheme = theme.colorScheme;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    final Color foregroundColor;
    final Color borderColor;
    Color? flatColor;
    Gradient? gradient;
    List<BoxShadow>? boxShadow;

    switch (widget.variant) {
      case ButtonVariant.primary:
        (flatColor, gradient, foregroundColor, borderColor, boxShadow) =
            _buildFilled(colors.primary, colors, colorScheme.onPrimary,
                isDisabled: isDisabled);
      case ButtonVariant.destructive:
        (flatColor, gradient, foregroundColor, borderColor, boxShadow) =
            _buildFilled(colors.error, colors, colorScheme.onError,
                isDisabled: isDisabled);
      case ButtonVariant.outline:
        flatColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.08)
            : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textPrimary;
        borderColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.5)
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
                color: gradient == null ? flatColor : null,
                gradient: gradient,
                borderRadius: NightshadeTokens.borderRadiusSm,
                border: Border.all(color: borderColor),
                boxShadow: boxShadow,
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
                      Icon(widget.icon,
                          size: _iconSize, color: foregroundColor),
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

  /// Builds the visuals for filled variants (primary, destructive) per the
  /// visual-polish design doc:
  ///   - default/hover: `LinearGradient(base.lighten(5) → base)` top→bottom
  ///   - pressed: flat darkened fill, no glow (physical press feel)
  ///   - hover: soft accent glow (alpha 0.3, blurRadius 12)
  ///   - disabled: flat surface with muted text
  (Color?, Gradient?, Color, Color, List<BoxShadow>?) _buildFilled(
    Color base,
    NightshadeColors colors,
    Color onColor, {
    required bool isDisabled,
  }) {
    if (isDisabled) {
      return (
        colors.surfaceAlt,
        null,
        colors.textMuted,
        colors.border,
        null,
      );
    }
    if (_isPressed) {
      return (
        _darkenColor(base, 0.1),
        null,
        onColor,
        Colors.transparent,
        null,
      );
    }
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_lightenColor(base, 0.05), base],
    );
    final glow = _isHovered
        ? <BoxShadow>[
            BoxShadow(
              color: base.withValues(alpha: 0.3),
              blurRadius: 12,
            ),
          ]
        : null;
    return (null, gradient, onColor, Colors.transparent, glow);
  }
}
