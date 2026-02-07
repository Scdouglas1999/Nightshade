// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

enum ButtonVariant { primary, outline, ghost, destructive }

enum ButtonSize { small, medium, large }

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

  void _handleTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _runAfterSafeUpdate(() {
        if (widget.onPressed == null || widget.isLoading) return;
        _isPressed = true;
        _pressController.forward();
      });
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _releasePress();
  }

  void _handleTapCancel() {
    _releasePress();
  }

  void _runAfterSafeUpdate(VoidCallback update) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks) {
      setState(update);
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(update);
      });
    }
  }

  void _setHovered(bool value) {
    if (_isHovered == value) return;
    _runAfterSafeUpdate(() {
      if (_isHovered == value) return;
      _isHovered = value;
    });
  }

  void _releasePress() {
    if (_isPressed) {
      _runAfterSafeUpdate(() {
        if (!_isPressed) return;
        _isPressed = false;
        _pressController.reverse();
      });
    }
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

  /// Creates a slightly lighter shade of the given color
  Color _lightenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Creates a slightly darker shade of the given color
  Color _darkenColor(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    // Determine colors based on variant
    final Color baseColor;
    final Color foregroundColor;
    final Color borderColor;
    final bool useGradient;
    final bool showGlow;

    switch (widget.variant) {
      case ButtonVariant.primary:
        baseColor = isDisabled
            ? colors.primary
                .withValues(alpha: NightshadeTokens.opacityDisabled + 0.12)
            : _isPressed
                ? _darkenColor(colors.primary, 0.1)
                : colors.primary;
        foregroundColor = Colors.white;
        borderColor = Colors.transparent;
        useGradient = !isDisabled && !_isPressed;
        showGlow = _isHovered && !isDisabled && !_isPressed;
      case ButtonVariant.destructive:
        baseColor = isDisabled
            ? colors.error
                .withValues(alpha: NightshadeTokens.opacityDisabled + 0.12)
            : _isPressed
                ? _darkenColor(colors.error, 0.1)
                : colors.error;
        foregroundColor = Colors.white;
        borderColor = Colors.transparent;
        useGradient = !isDisabled && !_isPressed;
        showGlow = _isHovered && !isDisabled && !_isPressed;
      case ButtonVariant.outline:
        baseColor = _isHovered
            ? colors.primary.withValues(alpha: 0.08)
            : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textPrimary;
        borderColor = _isHovered && !isDisabled
            ? colors.primary.withValues(alpha: 0.5)
            : colors.border;
        useGradient = false;
        showGlow = false;
      case ButtonVariant.ghost:
        baseColor = _isHovered ? colors.surfaceHover : Colors.transparent;
        foregroundColor = isDisabled ? colors.textMuted : colors.textSecondary;
        borderColor = Colors.transparent;
        useGradient = false;
        showGlow = false;
    }

    // Primary/destructive buttons use a muted, semi-transparent color
    // This creates a translucent effect that lets the dark background show through
    final Color? flatButtonColor =
        useGradient ? baseColor.withValues(alpha: 0.65) : null;

    // Build glow shadow for hover state
    final List<BoxShadow>? boxShadow = showGlow
        ? [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 0,
            ),
          ]
        : null;

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
                color: flatButtonColor ?? baseColor,
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
}
