import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../shell_navigation.dart';

List<SideNavTab> sideNavigationTabs(BuildContext context) {
  final l10n = context.l10n;
  return [
    for (final dest in ShellNavigation.primaryDestinations)
      SideNavTab(
        icon: dest.icon,
        label: dest.label(l10n),
        description: dest.description(l10n),
      ),
    // Scheduler merged into Plan Tonight as a tab (§UX consolidation,
    // W8-SCHED-MERGE). Reach it via Plan Tonight → Target Queue or
    // `/planner?tab=scheduler`.
    // Diagnostics merged into Analytics as a tab (§UX consolidation).
    // Reach it via Analytics → Diagnostics or `/analytics?tab=diagnostics`.
  ];
}

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

  Widget _buildNavButton(
    BuildContext context, {
    required SideNavTab tab,
    required int index,
    required bool isSelected,
  }) {
    final button = NavItem(
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
              style: NightshadeTypography.label.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              tab.description,
              style: NightshadeTypography.captionSm.copyWith(
                color: NightshadeColors.of(context).textMuted,
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
    final colors = NightshadeColors.of(context);
    final tabs = sideNavigationTabs(context);

    return AnimatedContainer(
      duration: NightshadeTokens.durationSmooth,
      curve: NightshadeTokens.curveSnappy,
      width: isExpanded
          ? NightshadeTokens.sidebarExpanded
          : NightshadeTokens.sidebarCollapsed,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          right: BorderSide(
            color: colors.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
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

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _buildNavButton(
                    context,
                    tab: tab,
                    index: index,
                    isSelected: isSelected,
                  ),
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

class SideNavTab {
  final IconData icon;
  final String label;
  final String description;

  const SideNavTab({
    required this.icon,
    required this.label,
    required this.description,
  });
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
    final colors = NightshadeColors.of(context);

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
                    context.l10n.text('collapse'),
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
