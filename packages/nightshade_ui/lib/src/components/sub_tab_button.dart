import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';

class SubTabButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const SubTabButton({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<SubTabButton> createState() => _SubTabButtonState();
}

class _SubTabButtonState extends State<SubTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    final backgroundColor = widget.isSelected
        ? Color.alphaBlend(
            colors.primary.withValues(alpha: 0.06),
            colors.surfaceAlt,
          )
        : _isHovered
            ? colors.surfaceHover
            : Colors.transparent;

    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.45)
        : _isHovered
            ? colors.borderHighlight.withValues(alpha: 0.85)
            : Colors.transparent;

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: NightshadeTokens.durationQuick,
          curve: NightshadeTokens.curveSnappy,
          margin: const EdgeInsets.only(top: 4, bottom: 4, right: 4),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: NightshadeTokens.borderRadiusMd,
            border: Border.all(color: borderColor),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              hoverColor: Colors.transparent,
              highlightColor: colors.primary.withValues(alpha: 0.06),
              splashColor: colors.primary.withValues(alpha: 0.06),
              borderRadius: NightshadeTokens.borderRadiusMd,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: NightshadeTokens.spaceMd + 2,
                  vertical: NightshadeTokens.spaceSm - 2,
                ),
                child: Text(
                  widget.label,
                  style: NightshadeTypography.labelSm.copyWith(
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: widget.isSelected
                        ? colors.primary
                        : _isHovered
                            ? colors.textPrimary
                            : colors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
