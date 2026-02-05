import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class SideNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool isExpanded;
  final VoidCallback onToggleExpanded;

  /// Optional list of GlobalKeys for tutorial targeting.
  /// Index 0 = Dashboard, 1 = Equipment, etc.
  final List<GlobalKey?>? tutorialKeys;

  const SideNavigation({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.isExpanded,
    required this.onToggleExpanded,
    this.tutorialKeys,
  });

  static const tabs = [
    NavItem(
      icon: LucideIcons.layoutDashboard,
      label: 'Dashboard',
      description: 'Overview & status',
    ),
    NavItem(
      icon: LucideIcons.plug,
      label: 'Equipment',
      description: 'Connect devices',
    ),
    NavItem(
      icon: LucideIcons.camera,
      label: 'Imaging',
      description: 'Capture & focus',
    ),
    NavItem(
      icon: LucideIcons.crosshair,
      label: 'Guiding',
      description: 'PHD2 control',
    ),
    NavItem(
      icon: LucideIcons.listOrdered,
      label: 'Sequencer',
      description: 'Automation',
    ),
    NavItem(
      icon: LucideIcons.globe,
      label: 'Planetarium',
      description: 'Sky view',
    ),
    NavItem(
      icon: LucideIcons.frame,
      label: 'Framing',
      description: 'Plan shots',
    ),
    NavItem(
      icon: LucideIcons.barChart3,
      label: 'Analytics',
      description: 'Session stats',
    ),
    NavItem(
      icon: LucideIcons.sun,
      label: 'Flat Wizard',
      description: 'Calibration',
    ),
    NavItem(
      icon: LucideIcons.cloudRain,
      label: 'Weather',
      description: 'Cloud radar',
    ),
    NavItem(
      icon: LucideIcons.lightbulb,
      label: 'Suggestions',
      description: "Tonight's targets",
    ),
  ];

  Widget _buildNavButton(
    BuildContext context, {
    required NavItem tab,
    required int index,
    required bool isSelected,
  }) {
    final button = _NavButton(
      key: tutorialKeys != null && index < tutorialKeys!.length
          ? tutorialKeys![index]
          : null,
      icon: tab.icon,
      label: tab.label,
      description: tab.description,
      isSelected: isSelected,
      isExpanded: isExpanded,
      onTap: () => onTabSelected(index),
    );

    // When collapsed, wrap with tooltip to show label
    if (!isExpanded) {
      return NightshadeTooltip(
        message: tab.label,
        richMessage: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tab.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.description,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).extension<NightshadeColors>()!.textMuted,
              ),
            ),
          ],
        ),
        position: NightshadeTooltipPosition.right,
        child: button,
      );
    }

    return button;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return AnimatedContainer(
      duration: NightshadeTokens.durationSmooth,
      curve: NightshadeTokens.curveSnappy,
      width: isExpanded ? NightshadeTokens.sidebarExpanded : NightshadeTokens.sidebarCollapsed,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          right: BorderSide(
            color: colors.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        // Level 1 elevation shadow on right edge
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // Navigation items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isSelected = index == currentIndex;

                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 200 + (index * 30)),
                  tween: Tween(begin: 0.0, end: 1.0),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset((1 - value) * 10, 0),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _buildNavButton(
                            context,
                            tab: tab,
                            index: index,
                            isSelected: isSelected,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Collapse/Expand button
          Padding(
            padding: const EdgeInsets.all(12),
            child: _CollapseButton(
              isExpanded: isExpanded,
              onTap: onToggleExpanded,
            ),
          ),
        ],
      ),
    );
  }
}

class NavItem {
  final IconData icon;
  final String label;
  final String description;

  const NavItem({
    required this.icon,
    required this.label,
    required this.description,
  });
}

class _NavButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _NavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton>
    with TickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _animController;
  late AnimationController _selectionController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _selectionScaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: NightshadeTokens.durationFast,
    );
    _selectionController = AnimationController(
      vsync: this,
      duration: NightshadeTokens.durationSmooth,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _animController, curve: NightshadeTokens.curveSnappy),
    );
    _selectionScaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(
        parent: _selectionController,
        curve: NightshadeTokens.curveSettle, // Overshoot for satisfying snap
      ),
    );
    if (widget.isSelected) {
      _selectionController.forward();
    }
  }

  @override
  void didUpdateWidget(_NavButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _selectionController.forward();
      } else {
        _selectionController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    final horizontalPadding = widget.isExpanded ? 14.0 : 4.0;
    final iconPadding = widget.isExpanded ? 8.0 : 1.5;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => _animController.forward(),
        onTapUp: (_) => _animController.reverse(),
        onTapCancel: () => _animController.reverse(),
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: ScaleTransition(
            scale: _selectionScaleAnimation,
            child: AnimatedContainer(
            duration: NightshadeTokens.durationNormal,
            curve: NightshadeTokens.curveSnappy,
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: widget.isExpanded ? 12 : 10,
            ),
            decoration: BoxDecoration(
              gradient: widget.isSelected
                  ? LinearGradient(
                      colors: [
                        colors.primary.withValues(alpha: 0.15),
                        colors.primary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    )
                  : null,
              color: widget.isSelected
                  ? null
                  : _isHovered
                      ? colors.surfaceHover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: widget.isSelected
                  ? Border.all(
                      color: colors.primary.withValues(alpha: 0.3),
                      width: 1,
                    )
                  : null,
            ),
            child: ClipRect(
              child: Row(
                mainAxisAlignment: widget.isExpanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                mainAxisSize: widget.isExpanded
                    ? MainAxisSize.max
                    : MainAxisSize.min,
                children: [
                  // Icon with glow effect when selected
                  AnimatedContainer(
                    duration: NightshadeTokens.durationSmooth,
                    curve: NightshadeTokens.curveSnappy,
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: widget.isSelected
                          ? colors.primary.withValues(alpha: 0.2)
                          : _isHovered
                              ? colors.surfaceAlt
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: widget.isSelected
                          ? [
                              BoxShadow(
                                color: colors.primary.withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: widget.isSelected
                          ? colors.primary
                          : _isHovered
                              ? colors.textPrimary
                              : colors.textSecondary,
                    ),
                  ),

                // Labels (when expanded)
                if (widget.isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: widget.isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: widget.isSelected
                                ? colors.textPrimary
                                : _isHovered
                                    ? colors.textPrimary
                                    : colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.description,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],

                // Selection indicator
                if (widget.isExpanded && widget.isSelected)
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                      boxShadow: [
                        BoxShadow(
                          color: colors.primary.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
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

class _CollapseButton extends StatefulWidget {
  final bool isExpanded;
  final VoidCallback onTap;

  const _CollapseButton({
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<_CollapseButton> createState() => _CollapseButtonState();
}

class _CollapseButtonState extends State<_CollapseButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered ? colors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered ? colors.border : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.max,
            children: [
              AnimatedRotation(
                turns: widget.isExpanded ? 0 : 0.5,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  LucideIcons.panelLeftClose,
                  size: 16,
                  color: colors.textMuted,
                ),
              ),
              if (widget.isExpanded) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Collapse',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

