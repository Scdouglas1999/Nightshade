import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
                        label: dest.bottomNavLabel(l10n),
                        // Sub-route aware: the image-ready deep link
                        // (/imaging/preview/:id) renders the Imaging screen, so
                        // the Imaging slot must own it. Exact matching left the
                        // whole bar unlit on those routes.
                        isSelected: ShellNavigation.locationIsUnder(
                          currentPath,
                          dest.route,
                        ),
                        compact: isLandscape,
                        colors: colors,
                        onTap: () => onRouteSelected(dest.route),
                      ),
                    ),
                  ),
                // "More" overflow so the primary features without a fixed slot
                // (Weather, Analytics) are reachable on phone.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BottomNavMetrics.itemGap / 2,
                    ),
                    child: _BottomNavItem(
                      icon: LucideIcons.menu,
                      label: l10n.text('navMore'),
                      isSelected: ShellNavigation.overflowDestinations.any(
                        (d) => ShellNavigation.locationIsUnder(
                          currentPath,
                          d.route,
                        ),
                      ),
                      compact: isLandscape,
                      colors: colors,
                      onTap: () => _showMoreSheet(context, l10n, colors),
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

  /// Bottom-sheet overflow listing the primary destinations without a fixed
  /// bottom-nav slot (today: Weather and Analytics — Your Sky and Constellation
  /// are Plan Tonight tabs). Selecting one routes to it and dismisses the sheet.
  void _showMoreSheet(
    BuildContext context,
    NightshadeLocalizations l10n,
    NightshadeColors colors,
  ) {
    final currentPath = currentRoute.split('?').first;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final dest in ShellNavigation.overflowDestinations)
                Builder(builder: (context) {
                  final isCurrent =
                      ShellNavigation.locationIsUnder(currentPath, dest.route);
                  return ListTile(
                    leading: Icon(
                      dest.icon,
                      color: isCurrent ? colors.primary : colors.textSecondary,
                    ),
                    title: Text(
                      dest.label(l10n),
                      style: NightshadeTypography.body.copyWith(
                        color: colors.textPrimary,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      dest.description(l10n),
                      style: NightshadeTypography.captionSm.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    selected: isCurrent,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      onRouteSelected(dest.route);
                    },
                  );
                }),
            ],
          ),
        );
      },
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
            // Horizontal 4 (not itemPadding's 10): seven slots on a 430dp
            // phone leave ~50dp per item, and 20dp of internal padding
            // ellipsized even the short labels ("Ho…", "Guid…").
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 4, vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                // FittedBox: a label a shade too wide for its slot
                // ("Sequence", Spanish "Secuencia") scales down a few
                // percent instead of ellipsizing — an ellipsis in a 7-slot
                // bar reads as broken, a 5% smaller glyph is invisible.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    // itemLabelFontSize (10px), not captionSm: the metrics
                    // already define the bar's label size; captionSm's larger
                    // glyphs were the other half of the ellipsis problem.
                    style: NightshadeTypography.captionSm.copyWith(
                      fontSize: BottomNavMetrics.itemLabelFontSize,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? colors.primary : colors.textSecondary,
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
