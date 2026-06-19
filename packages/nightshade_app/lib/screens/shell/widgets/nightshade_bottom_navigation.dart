import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../shell_navigation.dart';

class NightshadeBottomNavigation extends StatelessWidget {
  final String currentRoute;
  final ValueChanged<String> onRouteSelected;

  const NightshadeBottomNavigation({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    final currentPath = currentRoute.split('?').first;

    // In landscape vertical space is scarce (a phone is only ~360–430 px tall),
    // so shorten the bar and tighten the item's internal padding.
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final barHeight = isLandscape ? 64.0 : BottomNavMetrics.barHeight;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: BottomNavMetrics.listHorizontalPadding,
              vertical: BottomNavMetrics.listVerticalPadding,
            ),
            child: Row(
              children: [
                for (final dest in ShellNavigation.bottomNavigationDestinations)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: BottomNavMetrics.itemGap / 2,
                      ),
                      child: _BottomNavItem(
                        icon: dest.icon,
                        label: dest.label(l10n),
                        isSelected: currentPath == dest.route,
                        compact: isLandscape,
                        colors: colors,
                        onTap: () => onRouteSelected(dest.route),
                      ),
                    ),
                  ),
              ],
            ),
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

  /// Tighter vertical metrics for the shorter landscape bar.
  final bool compact;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(BottomNavMetrics.itemBorderRadius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: NightshadeTokens.minTouchTarget,
          ),
          child: AnimatedContainer(
            duration: BottomNavMetrics.itemSelectionAnimationDuration,
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 6, vertical: 4)
                : BottomNavMetrics.itemPadding,
            decoration: isSelected
                ? NightshadeDecorations.navSelected(
                    colors,
                    borderRadius: BorderRadius.circular(
                      BottomNavMetrics.itemBorderRadius,
                    ),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: BottomNavMetrics.itemIconSize,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                SizedBox(
                    height: compact
                        ? BottomNavMetrics.itemIconLabelGap - 3
                        : BottomNavMetrics.itemIconLabelGap),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: NightshadeTypography.captionSm.copyWith(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? colors.primary : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
