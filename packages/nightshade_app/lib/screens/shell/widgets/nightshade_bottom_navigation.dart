import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../localization/nightshade_localizations.dart';

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
  static const double _itemGap = 8;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final items = _navigationItems(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth =
            _itemWidth(MediaQuery.sizeOf(context), constraints.maxWidth);
        _scheduleScroll(items.length, itemWidth, constraints.maxWidth);

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
              height: 78,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: _itemGap),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SizedBox(
                    width: itemWidth,
                    child: _BottomNavItem(
                      icon: item.icon,
                      label: item.label,
                      isSelected: widget.currentRoute == item.route,
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

  void _scheduleScroll(int itemCount, double itemWidth, double viewportWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final selectedIndex = _navigationItems(context)
          .indexWhere((item) => item.route == widget.currentRoute);
      if (selectedIndex < 0) {
        return;
      }

      final slotWidth = itemWidth + _itemGap;
      final target =
          (selectedIndex * slotWidth) - ((viewportWidth - itemWidth) / 2) + 10;
      final clampedTarget =
          target.clamp(0.0, _scrollController.position.maxScrollExtent);

      if ((_scrollController.offset - clampedTarget).abs() < 8) {
        return;
      }

      _scrollController.animateTo(
        clampedTarget,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double _itemWidth(Size screenSize, double viewportWidth) {
    final aspectRatio = screenSize.width / screenSize.height;
    final visibleSlots = switch (viewportWidth) {
      >= 960 => 8.0,
      >= 780 => 7.0,
      >= 640 => 6.0,
      >= 520 => 5.25,
      _ when aspectRatio > 0.56 => 4.6,
      _ => 4.15,
    };

    final computed = (viewportWidth - 20) / visibleSlots;
    return computed.clamp(84.0, 116.0);
  }

  List<_NavRouteItem> _navigationItems(BuildContext context) {
    final l10n = context.l10n;
    return [
      _NavRouteItem(
        route: '/equipment',
        label: l10n.text('navEquipment'),
        icon: LucideIcons.plug,
      ),
      _NavRouteItem(
        route: '/imaging',
        label: l10n.text('navImaging'),
        icon: LucideIcons.camera,
      ),
      _NavRouteItem(
        route: '/sequencer',
        label: l10n.text('navSequencer'),
        icon: LucideIcons.listOrdered,
      ),
      _NavRouteItem(
        route: '/planetarium',
        label: l10n.text('navPlanetarium'),
        icon: LucideIcons.globe,
      ),
      _NavRouteItem(
        route: '/dashboard',
        label: l10n.text('navDashboard'),
        icon: LucideIcons.layoutDashboard,
      ),
      _NavRouteItem(
        route: '/guiding',
        label: l10n.text('navGuiding'),
        icon: LucideIcons.crosshair,
      ),
      _NavRouteItem(
        route: '/framing',
        label: l10n.text('navFraming'),
        icon: LucideIcons.frame,
      ),
      _NavRouteItem(
        route: '/analytics',
        label: l10n.text('navAnalytics'),
        icon: LucideIcons.barChart3,
      ),
      _NavRouteItem(
        route: '/flat-wizard',
        label: l10n.text('navFlatWizard'),
        icon: LucideIcons.sun,
      ),
      _NavRouteItem(
        route: '/weather',
        label: l10n.text('navWeather'),
        icon: LucideIcons.cloudRain,
      ),
      _NavRouteItem(
        route: '/planner',
        label: l10n.text('navPlanner'),
        icon: LucideIcons.moonStar,
      ),
      const _NavRouteItem(
        route: '/scheduler',
        label: 'Scheduler',
        icon: LucideIcons.brain,
      ),
      // Diagnostics merged into Analytics as a tab (§UX consolidation).
      // Reach it via Analytics → Diagnostics or `/analytics?tab=diagnostics`.
      _NavRouteItem(
        route: '/settings',
        label: l10n.text('settingsTitle'),
        icon: LucideIcons.settings,
      ),
    ];
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
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.12)
                : colors.surface,
            borderRadius: BorderRadius.circular(8),
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
                size: 18,
                color: isSelected ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
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
