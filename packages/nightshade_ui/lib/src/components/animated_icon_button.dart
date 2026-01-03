import 'package:flutter/material.dart';
import '../theme/nightshade_colors.dart';

/// An animated icon button with hover and press effects
class AnimatedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final Color? hoverColor;
  final Color? backgroundColor;
  final Color? hoverBackgroundColor;
  final String? tooltip;
  final bool showBorder;
  final bool isActive;

  const AnimatedIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 20,
    this.color,
    this.hoverColor,
    this.backgroundColor,
    this.hoverBackgroundColor,
    this.tooltip,
    this.showBorder = false,
    this.isActive = false,
  });

  @override
  State<AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final isDisabled = widget.onPressed == null;

    final iconColor = isDisabled
        ? colors.textMuted
        : widget.isActive
            ? widget.hoverColor ?? colors.primary
            : _isHovered
                ? widget.hoverColor ?? colors.primary
                : widget.color ?? colors.textSecondary;

    final bgColor = widget.isActive
        ? (widget.hoverBackgroundColor ?? colors.primary.withValues(alpha: 0.15))
        : _isHovered
            ? (widget.hoverBackgroundColor ?? colors.surfaceHover)
            : widget.backgroundColor ?? Colors.transparent;

    final borderColor = widget.isActive
        ? colors.primary.withValues(alpha: 0.3)
        : _isHovered && widget.showBorder
            ? colors.border
            : Colors.transparent;

    Widget button = MouseRegion(
      onEnter: isDisabled ? null : (_) => setState(() => _isHovered = true),
      onExit: isDisabled ? null : (_) => setState(() => _isHovered = false),
      cursor: isDisabled ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: isDisabled ? null : (_) => _pressController.forward(),
        onTapUp: isDisabled ? null : (_) => _pressController.reverse(),
        onTapCancel: isDisabled ? null : () => _pressController.reverse(),
        onTap: widget.onPressed,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.all(widget.size * 0.4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              widget.icon,
              size: widget.size,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }

    return button;
  }
}

/// A group of animated icon buttons that act like a segmented control
class AnimatedIconButtonGroup extends StatelessWidget {
  final List<AnimatedIconButtonItem> items;
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  final double iconSize;

  const AnimatedIconButtonGroup({
    super.key,
    required this.items,
    required this.selectedIndex,
    this.onSelected,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isSelected = index == selectedIndex;

          return Padding(
            padding: EdgeInsets.only(
              right: index < items.length - 1 ? 2 : 0,
            ),
            child: AnimatedIconButton(
              icon: item.icon,
              size: iconSize,
              isActive: isSelected,
              tooltip: item.tooltip,
              onPressed: onSelected != null ? () => onSelected!(index) : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// An item for AnimatedIconButtonGroup
class AnimatedIconButtonItem {
  final IconData icon;
  final String? tooltip;

  const AnimatedIconButtonItem({
    required this.icon,
    this.tooltip,
  });
}


