import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';

class NightshadeCard extends StatefulWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? backgroundColor;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool enableHover;

  const NightshadeCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.borderRadius = 12,
    this.onTap,
    this.enableHover = false,
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

    return MouseRegion(
      onEnter: shouldAnimate ? (_) => setState(() => _isHovered = true) : null,
      onExit: shouldAnimate ? (_) => setState(() => _isHovered = false) : null,
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: _isHovered 
                ? (widget.backgroundColor ?? colors.surface).withValues(alpha: 0.95)
                : widget.backgroundColor ?? colors.surface,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _isHovered ? colors.primary.withValues(alpha: 0.3) : colors.border,
            ),
            boxShadow: _isHovered ? [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.1),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ] : null,
          ),
          transform: _isHovered 
              ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 0.0))
              : Matrix4.identity(),
          child: widget.child,
        ),
      ),
    );
  }
}




