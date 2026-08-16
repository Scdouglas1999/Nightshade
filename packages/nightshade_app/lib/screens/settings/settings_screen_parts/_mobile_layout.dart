// Mobile section list, search results and category widgets.
part of '../settings_screen.dart';

// Mobile: grouped list with search

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
  final List<SettingsSearchResult> results;
  final Set<String> expandedGroups;
  final ValueChanged<String> onQueryChanged;
  final void Function(String title) onToggleGroup;
  final void Function(String key, String? rowTitle) onSectionTap;
  final NightshadeColors colors;
  final String title;

  @override
  Widget build(BuildContext context) {
    final searching = query.trim().isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        // The app shell may consume the keyboard inset before this screen can
        // observe it. Actual remaining height is therefore the reliable signal
        // for a route-level search field: keep only the field in the transient
        // compact viewport and restore the title when the keyboard closes.
        final keyboardCompact = constraints.maxHeight < 160;
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
                  padding: keyboardCompact
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
                      : const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!keyboardCompact) ...[
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: NightshadeTypography.fontSize24,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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
                                title: group.displayTitle,
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
                                    onTap: () =>
                                        onSectionTap(section.key, null),
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
      },
    );
  }
}

class _MobileSearchResults extends StatelessWidget {
  const _MobileSearchResults({
    required this.results,
    required this.colors,
    required this.onSectionTap,
  });

  final List<SettingsSearchResult> results;
  final NightshadeColors colors;
  final void Function(String key, String? rowTitle) onSectionTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No settings match your search.',
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize14,
              color: colors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final section = result.section;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MobileSectionItem(
              icon: section.icon,
              label: section.label,
              onTap: () => onSectionTap(section.key, null),
              colors: colors,
            ),
            for (final row in result.rows)
              _SearchRowResult(
                label: row,
                colors: colors,
                onTap: () => onSectionTap(section.key, row),
              ),
          ],
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
                  fontSize: NightshadeTypography.fontSize12,
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
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              ),
              child: Icon(icon, size: 20, color: colors.textSecondary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: NightshadeTypography.fontSize15,
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

// Shared sidebar section item (preserves the original visual style)

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
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      // A settings section is a CONTROL, not a panel: as a bare GestureDetector
      // keyboard-only and screen-reader users cannot change section at all.
      // InkWell supplies traversal, Enter/Space activation and the button role
      // in one widget; Semantics adds the selected state so AT can announce
      // which section is open.
      child: MergeSemantics(
        child: Semantics(
          // Semantics publishes isEnabled only when this field is given;
          // omitting it makes assistive tech announce a live control as
          // disabled.
          enabled: true,
          button: true,
          selected: widget.isSelected,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _isFocused = value),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
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
                borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
                // Focus outlines the row at full strength; selection keeps its
                // softer tint, so the two states stay distinguishable.
                border: _isFocused
                    ? Border.all(color: widget.colors.primary, width: 2)
                    : widget.isSelected
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
                        fontSize: NightshadeTypography.fontSize13,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
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
        ),
      ),
    );
  }
}
