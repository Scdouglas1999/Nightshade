import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';

/// Card variant for different use cases
enum CardVariant {
  /// Standard card with surface background
  standard,

  /// Elevated card with stronger shadow
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
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final shouldAnimate = widget.enableHover || widget.onTap != null;

    // Determine base background color
    final baseBackground = widget.backgroundColor ??
        switch (widget.variant) {
          CardVariant.standard => colors.surfaceAlt,
          CardVariant.elevated => colors.surfaceElevated,
          CardVariant.subtle => colors.surface,
        };

    // Determine shadow based on variant and hover state
    final List<BoxShadow> shadow;
    if (widget.variant == CardVariant.subtle) {
      shadow = [];
    } else if (_isHovered && shouldAnimate) {
      shadow = NightshadeTokens.elevationLevel2;
    } else if (widget.variant == CardVariant.elevated || widget.isSelected) {
      shadow = NightshadeTokens.elevationLevel1to2;
    } else {
      shadow = NightshadeTokens.elevationLevel1;
    }

    // Border color with hover and selected states
    final borderColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.55)
        : _isHovered && shouldAnimate
            ? colors.borderHighlight.withValues(alpha: 0.8)
            : colors.border.withValues(alpha: 0.65);

    // Build the card content with optional padding
    Widget content = widget.child;
    if (widget.padding != null) {
      content = Padding(padding: widget.padding!, child: content);
    }

    // Selected state indicator (accent left border)
    if (widget.isSelected) {
      content = Stack(
        children: [
          content,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(widget.borderRadius),
                  bottomLeft: Radius.circular(widget.borderRadius),
                ),
              ),
            ),
          ),
        ],
      );
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
          transform: _isHovered && shouldAnimate
              ? (Matrix4.identity()..setTranslationRaw(0.0, -2.0, 0.0))
              : Matrix4.identity(),
          decoration: BoxDecoration(
            color: baseBackground,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(color: borderColor),
            boxShadow: shadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Highlight edge at top (catches light effect)
              if (widget.variant != CardVariant.subtle)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colors.borderHighlight
                              .withValues(alpha: _isHovered ? 0.3 : 0.15),
                          colors.borderHighlight.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.7],
                      ),
                    ),
                  ),
                ),
              // Main content
              content,
            ],
          ),
        ),
      ),
    );
  }
}
