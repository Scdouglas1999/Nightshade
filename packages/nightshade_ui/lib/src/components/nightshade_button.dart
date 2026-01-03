import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

enum ButtonVariant { primary, outline, ghost }
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

class _NightshadeButtonState extends State<NightshadeButton> {
  bool _isHovered = false;

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
      ButtonSize.small => NightshadeTypography.captionSm.copyWith(fontWeight: FontWeight.w500),
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isDisabled = widget.onPressed == null || widget.isLoading;

    final (backgroundColor, foregroundColor, borderColor) = switch (widget.variant) {
      ButtonVariant.primary => (
          isDisabled
              ? colors.primary.withValues(alpha: NightshadeTokens.opacityDisabled + 0.12)
              : _isHovered
                  ? colors.primary.withValues(alpha: 0.9)
                  : colors.primary,
          Colors.white,
          Colors.transparent,
        ),
      ButtonVariant.outline => (
          _isHovered ? colors.surfaceHover : Colors.transparent,
          isDisabled ? colors.textMuted : colors.textPrimary,
          colors.border,
        ),
      ButtonVariant.ghost => (
          _isHovered ? colors.surfaceHover : Colors.transparent,
          isDisabled ? colors.textMuted : colors.textSecondary,
          Colors.transparent,
        ),
    };

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveStandard,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: NightshadeTokens.borderRadiusSm,
            border: Border.all(color: borderColor),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: isDisabled ? null : widget.onPressed,
              borderRadius: NightshadeTokens.borderRadiusSm,
              hoverColor: Colors.transparent, // Handled by AnimatedContainer
              highlightColor: foregroundColor.withValues(alpha: 0.1),
              splashColor: foregroundColor.withValues(alpha: 0.1),
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
                      Icon(widget.icon, size: _iconSize, color: foregroundColor),
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





