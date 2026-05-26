import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';
import '../shell_navigation.dart';

class NightshadeBottomNavigation extends StatefulWidget {
  final String currentRoute;
  final ValueChanged<String> onRouteSelected;

  const NightshadeBottomNavigation({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
  });

  @override
  State<NightshadeBottomNavigation> createState() =>
      _NightshadeBottomNavigationState();
}

class _NightshadeBottomNavigationState
    extends State<NightshadeBottomNavigation> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = NightshadeColors.of(context);
    final l10n = context.l10n;
    final items = ShellNavigation.bottomNavigationDestinations
        .map(
          (d) => _NavRouteItem(
            route: d.route,
            label: d.label(l10n),
            icon: d.icon,
          ),
        )
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = BottomNavMetrics.itemWidth(
          MediaQuery.sizeOf(context),
          constraints.maxWidth,
        );
        _scheduleScroll(items, itemWidth, constraints.maxWidth);

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
              height: BottomNavMetrics.barHeight,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: BottomNavMetrics.listHorizontalPadding,
                  vertical: BottomNavMetrics.listVerticalPadding,
                ),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: BottomNavMetrics.itemGap),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final currentPath = widget.currentRoute.split('?').first;
                  return SizedBox(
                    width: itemWidth,
                    child: _BottomNavItem(
                      icon: item.icon,
                      label: item.label,
                      isSelected: currentPath == item.route,
                      colors: colors,
                      onTap: () => widget.onRouteSelected(item.route),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _scheduleScroll(
    List<_NavRouteItem> items,
    double itemWidth,
    double viewportWidth,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final selectedIndex = items.indexWhere((item) {
        final path = widget.currentRoute.split('?').first;
        return path == item.route;
      });
      if (selectedIndex < 0) {
        return;
      }

      final slotWidth = itemWidth + BottomNavMetrics.itemGap;
      final target = (selectedIndex * slotWidth) -
          ((viewportWidth - itemWidth) / 2) +
          BottomNavMetrics.listHorizontalPadding;
      final clampedTarget =
          target.clamp(0.0, _scrollController.position.maxScrollExtent);

      if ((_scrollController.offset - clampedTarget).abs() < 8) {
        return;
      }

      _scrollController.animateTo(
        clampedTarget,
        duration: BottomNavMetrics.scrollAnimationDuration,
        curve: Curves.easeOutCubic,
      );
    });
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
      color: Colors.transparent,
      child: InkWell(
        borderRadius:
            BorderRadius.circular(BottomNavMetrics.itemBorderRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: BottomNavMetrics.itemSelectionAnimationDuration,
          padding: BottomNavMetrics.itemPadding,
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.12)
                : colors.surface,
            borderRadius:
                BorderRadius.circular(BottomNavMetrics.itemBorderRadius),
            border: Border.all(
              color: isSelected
                  ? colors.primary.withValues(alpha: 0.35)
                  : colors.border.withValues(alpha: 0.7),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: BottomNavMetrics.itemIconSize,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(height: BottomNavMetrics.itemIconLabelGap),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: BottomNavMetrics.itemLabelFontSize,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavRouteItem {
  final String route;
  final String label;
  final IconData icon;

  const _NavRouteItem({
    required this.route,
    required this.label,
    required this.icon,
  });
}
