import 'package:flutter/material.dart';

import '../theme/nightshade_colors.dart';
import '../theme/nightshade_tokens.dart';
import '../theme/nightshade_typography.dart';
import '../utils/responsive_utils.dart';

/// Sidebar navigation row with flat icon, tonal selection, and left accent.
class NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<NavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.nightshadeColors;

    final backgroundColor = widget.isSelected
        ? colors.primary.withValues(alpha: 0.06)
        : _isHovered
        ? colors.surfaceHover
        : Colors.transparent;

    final horizontalPadding = widget.isExpanded
        ? NightshadeTokens.panelSectionPadding
        : NightshadeTokens.spaceXs;
    final verticalPadding = widget.isExpanded ? NightshadeTokens.spaceMd : 10.0;
    final iconSize = Responsive.iconSize(context, 18);
    final labelFontSize = Responsive.fontSize(context, 13);
    final descriptionFontSize = Responsive.fontSize(context, 11);

    return Semantics(
      // Semantics publishes isEnabled only when this field is given;
      // omitting it makes assistive tech announce a live control as
      // disabled. Measured on the running app 2026-08-09.
      enabled: true,
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            highlightColor: colors.primary.withValues(alpha: 0.06),
            splashColor: colors.primary.withValues(alpha: 0.06),
            borderRadius: NightshadeTokens.borderRadiusMd,
            child: AnimatedContainer(
              duration: NightshadeTokens.durationNormal,
              curve: NightshadeTokens.curveSnappy,
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: NightshadeTokens.borderRadiusMd,
                border: widget.isSelected
                    ? Border(left: BorderSide(color: colors.primary, width: 2))
                    : null,
              ),
              child: Row(
                mainAxisAlignment: widget.isExpanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                mainAxisSize: widget.isExpanded
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: [
                  Icon(
                    widget.icon,
                    size: iconSize,
                    color: widget.isSelected || _isHovered
                        ? colors.textPrimary
                        : colors.textSecondary,
                  ),
                  if (widget.isExpanded) ...[
                    const SizedBox(width: NightshadeTokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.label,
                            style: NightshadeTypography.label.copyWith(
                              fontSize: labelFontSize,
                              fontWeight: widget.isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: widget.isSelected || _isHovered
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: NightshadeTokens.spaceXs / 2),
                          Text(
                            widget.description,
                            style: NightshadeTypography.captionSm.copyWith(
                              fontSize: descriptionFontSize,
                              color: colors.textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
