import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../widgets/pill_tab.dart';

// Re-export all tab widgets and shared widgets so existing imports still work
export 'tonight_tab.dart';
export 'catalog_tab.dart' show CatalogTab;
export 'search_tab.dart';
export 'info_tab.dart';
export 'lists_tab.dart';
export 'sidebar_shared_widgets.dart';

/// The planetarium sidebar sub-tabs, rendered as filled icon-over-label pills
/// matching the imaging panel's sub-tabs.
///
/// This drives the ambient [DefaultTabController] (length 5) so taps, swipes on
/// the [TabBarView], and programmatic index changes all stay in sync. The pill
/// styling is shared with the imaging panel via [PillTab].
class SidebarTabs extends StatelessWidget {
  final NightshadeColors colors;

  const SidebarTabs({super.key, required this.colors});

  static const _tabs = [
    (LucideIcons.moon, 'Tonight'),
    (LucideIcons.bookOpen, 'Catalog'),
    (LucideIcons.list, 'Lists'),
    (LucideIcons.search, 'Search'),
    (LucideIcons.info, 'Info'),
  ];

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      child: AnimatedBuilder(
        animation: controller.animation!,
        builder: (context, _) {
          final selected = controller.index;
          return Row(
            children: [
              for (var i = 0; i < _tabs.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: PillTab(
                    icon: _tabs[i].$1,
                    label: _tabs[i].$2,
                    isSelected: selected == i,
                    onTap: () => controller.animateTo(i),
                    colors: colors,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
