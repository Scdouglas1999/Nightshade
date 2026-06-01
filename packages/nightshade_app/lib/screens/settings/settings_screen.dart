import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_catalog.dart';

// Re-export the derived deep-link index map so existing importers keep
// resolving `package:.../settings_screen.dart` → kSettingsSectionIndex. The map
// itself is now derived from the declarative catalog (see settings_catalog.dart)
// and is a backward-compatibility shim only; selection is driven by KEY.
export 'settings_catalog.dart'
    show kSettingsSectionIndex, kMergedSectionAliases;

class SettingsScreen extends ConsumerStatefulWidget {
  /// Optional stable section key (e.g. `'location'`) to open directly. Unknown
  /// or null keys fall back to the first section; merged-away keys
  /// (`auto-save`, `predictive-af`, `notification-routing`) resolve to their
  /// combined section. See [kSettingsSectionIndex] / [kMergedSectionAliases].
  final String? initialSection;

  const SettingsScreen({super.key, this.initialSection});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// The currently selected section's stable key.
  late String _selectedKey;

  /// On mobile, false means show the grouped list; true shows the detail pane.
  bool _mobileShowingDetail = false;

  /// Which group titles are currently expanded in the sidebar. Remembered for
  /// the session. The group holding the initial/active section starts expanded.
  final Set<String> _expandedGroups = {};

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Resolve the initial section by KEY (locale-independent; no BuildContext
    // is required, so this is safe in initState). Merged-away keys resolve to
    // their combined section; unknown/null keys fall back to the first section.
    final resolvedKey = resolveSectionKey(widget.initialSection);
    if (resolvedKey != null) {
      _selectedKey = resolvedKey;
      _mobileShowingDetail = true;
    } else {
      _selectedKey = kFirstSectionKey;
    }
    // Start with the group containing the active section expanded.
    _expandedGroups.add(groupTitleForKey(_selectedKey));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  SettingsSectionDef _selectedSection(List<SettingsGroupDef> groups) {
    for (final group in groups) {
      for (final section in group.sections) {
        if (section.key == _selectedKey) return section;
      }
    }
    return groups.first.sections.first;
  }

  void _selectSection(String key, {required bool isMobile}) {
    setState(() {
      _selectedKey = key;
      if (isMobile) _mobileShowingDetail = true;
    });
  }

  void _toggleGroup(String title) {
    setState(() {
      if (!_expandedGroups.remove(title)) _expandedGroups.add(title);
    });
  }

  /// Sections matching the live search query, flattened across all groups.
  List<SettingsSectionDef> _searchResults(List<SettingsGroupDef> groups) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = <SettingsSectionDef>[];
    for (final group in groups) {
      for (final section in group.sections) {
        if (section.matches(q)) results.add(section);
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    // Phone tier (< 600): list -> full-screen detail navigation. Tablets and
    // desktop (>= 600) keep the sidebar + detail split. (Was Responsive.isMobile
    // at < 768, which forced small tablets into the cramped phone flow.)
    final isPhone = Responsive.isPhone(context);
    final l10n = context.l10n;
    final groups = buildSettingsGroups(context);

    final child = isPhone
        ? _buildMobileLayout(colors, groups)
        : _buildDesktopLayout(colors, groups);

    return ContextualTourPrompt(
      screenId: 'settings',
      tourCategory: TutorialCategory.settingsTour,
      title: l10n.text('settingsTourTitle'),
      description: l10n.text('settingsTourDescription'),
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Mobile
  // ---------------------------------------------------------------------------

  Widget _buildMobileLayout(
    NightshadeColors colors,
    List<SettingsGroupDef> groups,
  ) {
    if (!_mobileShowingDetail) {
      return _MobileSectionList(
        groups: groups,
        searchController: _searchController,
        query: _query,
        results: _searchResults(groups),
        expandedGroups: _expandedGroups,
        onQueryChanged: (value) => setState(() => _query = value),
        onToggleGroup: _toggleGroup,
        onSectionTap: (key) => _selectSection(key, isMobile: true),
        colors: colors,
        title: context.l10n.text('settingsTitle'),
      );
    }

    final section = _selectedSection(groups);
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon:
                        Icon(LucideIcons.arrowLeft, color: colors.textPrimary),
                    onPressed: () =>
                        setState(() => _mobileShowingDetail = false),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    section.label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // SafeArea (sides + bottom) so a rotated phone's notch/home indicator
        // never clips the detail content; top is already handled by the header.
        Expanded(
          child: SafeArea(
            top: false,
            child: section.build(true),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Desktop
  // ---------------------------------------------------------------------------

  Widget _buildDesktopLayout(
    NightshadeColors colors,
    List<SettingsGroupDef> groups,
  ) {
    final results = _searchResults(groups);
    final searching = _query.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ResizablePanel(
          initialWidth: 260,
          minWidth: 200,
          maxWidth: 420,
          side: ResizeSide.right,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Text(
                    context.l10n.text('settingsTitle'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: _SearchField(
                    controller: _searchController,
                    colors: colors,
                    onChanged: (value) => setState(() => _query = value),
                    onClear: () => setState(() {
                      _searchController.clear();
                      _query = '';
                    }),
                  ),
                ),
                Expanded(
                  child: searching
                      ? _DesktopSearchResults(
                          results: results,
                          selectedKey: _selectedKey,
                          colors: colors,
                          onTap: (key) =>
                              _selectSection(key, isMobile: false),
                        )
                      : _DesktopGroupedList(
                          groups: groups,
                          selectedKey: _selectedKey,
                          expandedGroups: _expandedGroups,
                          colors: colors,
                          onToggleGroup: _toggleGroup,
                          onSelect: (key) =>
                              _selectSection(key, isMobile: false),
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: _selectedSection(groups).build(false)),
      ],
    );
  }
}

// =============================================================================
// Search field
// =============================================================================

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.colors,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final NightshadeColors colors;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontSize: 13, color: colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search settings…',
        hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
        prefixIcon:
            Icon(LucideIcons.search, size: 16, color: colors.textMuted),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 36, minHeight: 36),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(LucideIcons.x, size: 16, color: colors.textMuted),
                splashRadius: 16,
                onPressed: onClear,
              ),
        filled: true,
        fillColor: colors.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.primary.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}

// =============================================================================
// Desktop: grouped, collapsible sidebar
// =============================================================================

class _DesktopGroupedList extends StatelessWidget {
  const _DesktopGroupedList({
    required this.groups,
    required this.selectedKey,
    required this.expandedGroups,
    required this.colors,
    required this.onToggleGroup,
    required this.onSelect,
  });

  final List<SettingsGroupDef> groups;
  final String selectedKey;
  final Set<String> expandedGroups;
  final NightshadeColors colors;
  final void Function(String title) onToggleGroup;
  final void Function(String key) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: SettingsTutorialKeys.categories,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final expanded = expandedGroups.contains(group.title);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeader(
              title: group.title,
              icon: group.icon,
              expanded: expanded,
              colors: colors,
              onTap: () => onToggleGroup(group.title),
            ),
            if (expanded)
              ...group.sections.map(
                (section) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _CategoryItem(
                    icon: section.icon,
                    label: section.label,
                    isSelected: section.key == selectedKey,
                    onTap: () => onSelect(section.key),
                    colors: colors,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final NightshadeColors colors;
  final VoidCallback onTap;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? colors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 16, color: colors.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: widget.expanded ? 0.25 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: colors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Desktop: flat search results
// =============================================================================

class _DesktopSearchResults extends StatelessWidget {
  const _DesktopSearchResults({
    required this.results,
    required this.selectedKey,
    required this.colors,
    required this.onTap,
  });

  final List<SettingsSectionDef> results;
  final String selectedKey;
  final NightshadeColors colors;
  final void Function(String key) onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No settings match your search.',
          style: TextStyle(fontSize: 13, color: colors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final section = results[index];
        return _CategoryItem(
          icon: section.icon,
          label: section.label,
          isSelected: section.key == selectedKey,
          onTap: () => onTap(section.key),
          colors: colors,
        );
      },
    );
  }
}

// =============================================================================
// Mobile: grouped list with search
// =============================================================================

class _MobileSectionList extends StatelessWidget {
  const _MobileSectionList({
    required this.groups,
    required this.searchController,
    required this.query,
    required this.results,
    required this.expandedGroups,
    required this.onQueryChanged,
    required this.onToggleGroup,
    required this.onSectionTap,
    required this.colors,
    required this.title,
  });

  final List<SettingsGroupDef> groups;
  final TextEditingController searchController;
  final String query;
  final List<SettingsSectionDef> results;
  final Set<String> expandedGroups;
  final ValueChanged<String> onQueryChanged;
  final void Function(String title) onToggleGroup;
  final void Function(String key) onSectionTap;
  final NightshadeColors colors;
  final String title;

  @override
  Widget build(BuildContext context) {
    final searching = query.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SearchField(
                    controller: searchController,
                    colors: colors,
                    onChanged: onQueryChanged,
                    onClear: () {
                      searchController.clear();
                      onQueryChanged('');
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          // Sides + bottom SafeArea so list rows clear a rotated phone's notch
          // / home indicator in landscape (the header above handles the top).
          child: SafeArea(
            top: false,
            child: searching
              ? _MobileSearchResults(
                  results: results,
                  colors: colors,
                  onSectionTap: onSectionTap,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final expanded = expandedGroups.contains(group.title);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _MobileGroupHeader(
                          title: group.title,
                          icon: group.icon,
                          expanded: expanded,
                          colors: colors,
                          onTap: () => onToggleGroup(group.title),
                        ),
                        if (expanded)
                          ...group.sections.map(
                            (section) => _MobileSectionItem(
                              icon: section.icon,
                              label: section.label,
                              onTap: () => onSectionTap(section.key),
                              colors: colors,
                            ),
                          ),
                      ],
                    );
                  },
                ),
          ),
        ),
      ],
    );
  }
}

class _MobileSearchResults extends StatelessWidget {
  const _MobileSearchResults({
    required this.results,
    required this.colors,
    required this.onSectionTap,
  });

  final List<SettingsSectionDef> results;
  final NightshadeColors colors;
  final void Function(String key) onSectionTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No settings match your search.',
          style: TextStyle(fontSize: 14, color: colors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final section = results[index];
        return _MobileSectionItem(
          icon: section.icon,
          label: section.label,
          onTap: () => onSectionTap(section.key),
          colors: colors,
        );
      },
    );
  }
}

class _MobileGroupHeader extends StatelessWidget {
  const _MobileGroupHeader({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.colors,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final NightshadeColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceAlt.withValues(alpha: 0.4),
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: colors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: colors.textSecondary,
                ),
              ),
            ),
            AnimatedRotation(
              turns: expanded ? 0.25 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                LucideIcons.chevronRight,
                size: 18,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSectionItem extends StatelessWidget {
  const _MobileSectionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final NightshadeColors colors;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(28, 14, 16, 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: colors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 20, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Shared sidebar section item (preserves the original visual style)
// =============================================================================

class _CategoryItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final NightshadeColors colors;

  const _CategoryItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colors,
  });

  @override
  State<_CategoryItem> createState() => _CategoryItemState();
}

class _CategoryItemState extends State<_CategoryItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.colors.primary.withValues(alpha: 0.1)
                : _isHovered
                    ? widget.colors.surfaceAlt
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: widget.isSelected
                ? Border.all(
                    color: widget.colors.primary.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.isSelected
                    ? widget.colors.primary
                    : widget.colors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: widget.isSelected
                        ? widget.colors.textPrimary
                        : widget.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
