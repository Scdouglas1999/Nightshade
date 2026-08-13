// Part of ../settings_screen.dart -- extracted for maintainability.
//
// Desktop search field, grouped list and search-result widgets.
part of '../settings_screen.dart';

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
      style: TextStyle(
          fontSize: NightshadeTypography.fontSize13, color: colors.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: context.l10n.text('settingsSearchHint'),
        hintStyle: TextStyle(
            fontSize: NightshadeTypography.fontSize13, color: colors.textMuted),
        prefixIcon: Icon(LucideIcons.search, size: 16, color: colors.textMuted),
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
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
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
              // Display title: the group's `title` is the structural id and
              // stays English, so rendering it would leave the header
              // untranslated above translated child items.
              title: group.displayTitle,
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      // InkWell, not GestureDetector: the whole section navigator was
      // mouse-only — 24 Tab presses never landed on it, and AT read every
      // entry as "panel" rather than a control. InkWell joins the traversal
      // order, activates on Enter/Space, and reports itself as a button.
      child: MergeSemantics(
        child: Semantics(
          // Semantics publishes isEnabled only when this field is given;
          // omitting it makes assistive tech announce a live control as
          // disabled. Measured on the running app 2026-08-09.
          enabled: true,
          button: true,
          expanded: widget.expanded,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (value) => setState(() => _focused = value),
            borderRadius: BorderRadius.circular(NightshadeTokens.radiusInline8),
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _hovered ? colors.surfaceAlt : Colors.transparent,
                borderRadius:
                    BorderRadius.circular(NightshadeTokens.radiusInline8),
                // Keyboard focus has to be VISIBLE, not just held.
                border: _focused
                    ? Border.all(color: colors.primary, width: 2)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: colors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: NightshadeTypography.fontSize11,
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

  final List<SettingsSearchResult> results;
  final String selectedKey;
  final NightshadeColors colors;
  final void Function(String key, String? rowTitle) onTap;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No settings match your search.',
          style: TextStyle(
              fontSize: NightshadeTypography.fontSize13,
              color: colors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        final section = result.section;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CategoryItem(
              icon: section.icon,
              label: section.label,
              isSelected: section.key == selectedKey,
              onTap: () => onTap(section.key, null),
              colors: colors,
            ),
            // The rows that actually matched. Tapping one opens the section
            // scrolled to that row instead of at the top of a long page.
            for (final row in result.rows)
              _SearchRowResult(
                label: row,
                colors: colors,
                onTap: () => onTap(section.key, row),
              ),
          ],
        );
      },
    );
  }
}

/// A single matched setting beneath its section in the search results.
class _SearchRowResult extends StatefulWidget {
  const _SearchRowResult({
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final NightshadeColors colors;
  final VoidCallback onTap;

  @override
  State<_SearchRowResult> createState() => _SearchRowResultState();
}

class _SearchRowResultState extends State<_SearchRowResult> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Semantics(
      // Semantics publishes isEnabled only when this field is given;
      // omitting it makes assistive tech announce a live control as
      // disabled. Measured on the running app 2026-08-09.
      enabled: true,
      button: true,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (value) => setState(() => _focused = value),
        borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Container(
            margin: const EdgeInsets.only(left: 20, bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered ? colors.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(NightshadeTokens.radiusLg),
              border:
                  _focused ? Border.all(color: colors.primary, width: 2) : null,
            ),
            child: Row(
              children: [
                Icon(LucideIcons.cornerDownRight,
                    size: 12, color: colors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: NightshadeTypography.fontSize12,
                      color: colors.textSecondary,
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
