import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'side_navigation.dart';

class NightshadeBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;

  const NightshadeBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;

    // Use a limited set of tabs for mobile/bottom nav if there are too many
    // Use all tabs and let layout choose between fixed and scrolling behavior.
    // 8 items is too many for a standard bottom bar.
    // We should probably show the top 4-5 and a "More" menu, or just scroll.
    // Use a scrollable row to ensure all tabs remain accessible.

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(
            color: colors.border,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: SideNavigation.tabs.length,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemBuilder: (context, index) {
              final tab = SideNavigation.tabs[index];
              final isSelected = index == currentIndex;

              return _BottomNavItem(
                icon: tab.icon,
                label: tab.label,
                isSelected: isSelected,
                onTap: () => onTabSelected(index),
                colors: colors,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 70,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
