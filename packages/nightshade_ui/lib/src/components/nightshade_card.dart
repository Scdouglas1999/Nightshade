import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Card variant for different use cases
enum CardVariant {
  /// Standard card with surface background
  standard,

  /// Elevated card with stronger border contrast
  elevated,

  /// Subtle card with minimal styling
  subtle,
}

class NightshadeCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool enableHover;
  final bool isSelected;
  final CardVariant variant;

  const NightshadeCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderRadius = NightshadeTokens.radiusMd,
    this.onTap,
    this.enableHover = false,
    this.isSelected = false,
    this.variant = CardVariant.standard,
  });

  @override
  State<NightshadeCard> createState() => _NightshadeCardState();
}

class _NightshadeCardState extends State<NightshadeCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final shouldAnimate = widget.enableHover || widget.onTap != null;

    final baseBackground =
        widget.backgroundColor ??
        switch (widget.variant) {
          CardVariant.standard => colors.surfaceAlt,
          CardVariant.elevated => colors.surfaceElevated,
          CardVariant.subtle => colors.surface,
        };

    final backgroundColor = widget.isSelected
        ? Color.alphaBlend(
            colors.primary.withValues(alpha: 0.04),
            baseBackground,
          )
        : _isHovered && shouldAnimate
        ? colors.surfaceHover
        : baseBackground;

    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.45)
        : _isHovered && shouldAnimate
        ? colors.borderHighlight.withValues(alpha: 0.85)
        : colors.border.withValues(alpha: 0.55);

    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    return MouseRegion(
      onEnter: shouldAnimate ? (_) => setState(() => _isHovered = true) : null,
      onExit: shouldAnimate ? (_) => setState(() => _isHovered = false) : null,
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: NightshadeTokens.durationNormal,
          curve: NightshadeTokens.curveSnappy,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: content,
        ),
      ),
    );
  }
}
