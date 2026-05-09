import 'package:flutter/material.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

// Re-export all tab widgets and shared widgets so existing imports still work
export 'tonight_tab.dart';
export 'catalog_tab.dart' show CatalogTab;
export 'search_tab.dart';
export 'info_tab.dart';
export 'lists_tab.dart';
export 'sidebar_shared_widgets.dart';

class SidebarTabs extends StatelessWidget {
  final NightshadeColors colors;

  const SidebarTabs({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: TabBar(
        labelColor: colors.primary,
        unselectedLabelColor: colors.textSecondary,
        indicatorColor: colors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [
          Tab(text: 'Tonight'),
          Tab(text: 'Catalog'),
          Tab(text: 'Lists'),
          Tab(text: 'Search'),
          Tab(text: 'Info'),
        ],
      ),
    );
  }
}
