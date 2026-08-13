import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../localization/nightshade_localizations.dart';
import '../../widgets/contextual_tour_prompt.dart';
import '../../widgets/tutorial_keys/settings_keys.dart';
import 'settings_catalog.dart';
import 'settings_search_index.g.dart';
import 'widgets/settings_widgets.dart';

// Re-export the derived deep-link index map so existing importers keep
// resolving `package:.../settings_screen.dart` → kSettingsSectionIndex. The map
// itself is now derived from the declarative catalog (see settings_catalog.dart)
// and is a backward-compatibility shim only; selection is driven by KEY.
export 'settings_catalog.dart'
    show kSettingsSectionIndex, kMergedSectionAliases;

/// Words a user types for a setting that the owning page never says.
///
/// The app's own vocabulary was missing the page that owns it: the Dashboard
/// empty state says "Set a capture directory to track free space" and the
/// status bar says "No save path", but Files & Storage titles that row "Image
/// output" — so "capture folder", "disk", "free space" and "save path" all
/// returned nothing. Kept small and deliberate: a synonym that is too generous
/// makes the search match everything, which is the failure mode the derived
/// index replaced.
const Map<String, List<String>> kSettingsSearchSynonyms = {
  'files-storage': [
    'capture folder',
    'capture directory',
    'save path',
    'image folder',
    'disk space',
    'free space',
    'storage location',
  ],
};

/// Whether [section] answers a single search token, including the synonyms
/// above. Exposed so tests can exercise the same predicate the screen uses.
bool sectionMatchesToken(SettingsSectionDef section, String token) {
  if (section.matches(token)) return true;
  for (final synonym in kSettingsSearchSynonyms[section.key] ?? const []) {
    if (synonym.contains(token)) return true;
  }
  return false;
}

/// How well [section] answers [query]; lower sorts first.
///
/// Exact section titles outrank a row title that merely contains the query,
/// which is what kept sending an autofocus search to a page ranked above the
/// page the setting is actually on.
int settingsMatchRank(SettingsSectionDef section, String query) {
  final label = section.label.toLowerCase();
  if (label == query) return 0;
  if (label.contains(query)) return 1;
  var best = 4;
  for (final term in kSettingsSearchTerms[section.key] ?? const <String>[]) {
    final lower = term.toLowerCase();
    if (lower == query) return 2;
    if (lower.startsWith(query) && best > 3) best = 3;
  }
  return best;
}

/// A section that answered the query, plus the rows inside it that did.
///
/// The row titles were being computed and thrown away: the sidebar showed
/// "Connection" for a query of "Alpaca" and left the operator to find the
/// Alpaca row on a long page by eye.
class SettingsSearchResult {
  const SettingsSearchResult(this.section, this.rows);

  final SettingsSectionDef section;

  /// Matching row titles, best (shortest, i.e. most title-like) first. Empty
  /// when the section's own name or a synonym is what matched.
  final List<String> rows;
}

/// Does [term] look like the NAME of a setting, rather than prose about one?
///
/// The generated index is not a list of row titles. Its `title:` rule has no
/// left word boundary, so every `subtitle:` in the settings tree is indexed as
/// well — that is how "Where rejected frames go. Leave blank for the default
/// `<save_path>/Reject/…`" (164 characters) ends up in it. That was harmless
/// while the index only decided which SECTIONS matched, but a result list that
/// offers those strings as tappable rows offers dead ends: nothing on the page
/// is titled that, so opening it reveals and marks nothing — exactly the
/// complaint the row results were added to fix.
///
/// Measured over the 508 `title:` and 222 `subtitle:` literals under
/// `screens/settings/`: 99% of titles are <= 39 characters and <= 6 words,
/// while the median subtitle is 43 characters and 7 words.
bool isRowShapedSettingsTerm(String term) {
  final trimmed = term.trim();
  if (trimmed.isEmpty || trimmed.length > 48) return false;
  if (trimmed.split(RegExp(r'\s+')).length > 6) return false;
  // A sentence is prose; a row name never ends in a full stop or a comma and
  // never runs two sentences together.
  if (RegExp(r'[.,;]$').hasMatch(trimmed)) return false;
  if (trimmed.contains('. ')) return false;
  return true;
}

/// Does [token] begin a word in [lowerTerm]?
///
/// A bare `contains` made "gain" match "try ag[ain]." and "port" match
/// "sup[port]" and "re[port]ing_group_id" — results that have nothing to do
/// with what was typed. Sections keep the looser substring test
/// ([sectionMatchesToken]); only the row list, which claims to name the
/// setting that matched, is held to a word boundary.
bool _startsWord(String lowerTerm, String token) {
  if (token.isEmpty) return false;
  var from = 0;
  while (true) {
    final at = lowerTerm.indexOf(token, from);
    if (at < 0) return false;
    if (at == 0 || !RegExp(r'[a-z0-9]').hasMatch(lowerTerm[at - 1])) {
      return true;
    }
    from = at + 1;
  }
}

/// Row titles inside [section] that answer every token of the query.
///
/// Shortest first: the index holds row titles, page headings and control
/// labels, and the short entries are the ones that are actually a row's name.
List<String> matchingSettingsRows(
  SettingsSectionDef section,
  List<String> tokens, {
  int limit = 3,
}) {
  final matches = <String>[];
  final sectionLabel = section.label.toLowerCase();
  for (final term in kSettingsSearchTerms[section.key] ?? const <String>[]) {
    if (!isRowShapedSettingsTerm(term)) continue;
    final lower = term.toLowerCase();
    // A page whose own heading repeats the section name ("Notifications"
    // inside Notifications) would be offered as a child of the entry directly
    // above it, which says nothing new and cannot be tapped anywhere better.
    if (lower == sectionLabel) continue;
    if (tokens.every((token) => _startsWord(lower, token))) matches.add(term);
  }
  mergeSort<String>(matches, compare: (a, b) => a.length.compareTo(b.length));
  return matches.take(limit).toList();
}

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

  /// Row title the detail pane should reveal, set when a search result names a
  /// specific row. Cleared a few seconds later by [_highlightTimer].
  String? _highlightRow;
  Timer? _highlightTimer;

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
    ShellBackDispatcher.register(_handleSystemBack);
  }

  /// A second `/settings?section=<key>` navigation while this screen is open.
  ///
  /// The `/settings` page is keyless, so the router UPDATES this element with a
  /// new [SettingsScreen.initialSection] instead of pushing a second screen —
  /// and reading the key only in [initState] meant every in-Settings link back
  /// into Settings (the title bar's profile icon, the plate-solver and weather
  /// banners, the tour's jump targets) silently did nothing once the screen was
  /// up. Only a CHANGED key is a navigation request: a plain parent rebuild
  /// carrying the same deep link must leave the operator wherever they walked
  /// to, and an unknown key names no section, so it moves nothing.
  @override
  void didUpdateWidget(SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSection == oldWidget.initialSection) return;
    final resolvedKey = resolveSectionKey(widget.initialSection);
    if (resolvedKey == null || resolvedKey == _selectedKey) return;
    _highlightTimer?.cancel();
    setState(() {
      _selectedKey = resolvedKey;
      _highlightRow = null;
      // The link named a destination, so on a phone the detail pane is the
      // destination — not the grouped list the operator would otherwise land
      // back on.
      _mobileShowingDetail = true;
      _expandedGroups.add(groupTitleForKey(resolvedKey));
    });
  }

  @override
  void dispose() {
    ShellBackDispatcher.unregister(_handleSystemBack);
    _highlightTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// System back on phone walks the in-screen stack before leaving the
  /// screen: detail pane → grouped list → clear an active search → let the
  /// shell take over (Dashboard / app exit).
  bool _handleSystemBack() {
    if (_mobileShowingDetail) {
      setState(() => _mobileShowingDetail = false);
      return true;
    }
    if (_query.isNotEmpty) {
      setState(() {
        _searchController.clear();
        _query = '';
      });
      return true;
    }
    return false;
  }

  SettingsSectionDef _selectedSection(List<SettingsGroupDef> groups) {
    for (final group in groups) {
      for (final section in group.sections) {
        if (section.key == _selectedKey) return section;
      }
    }
    return groups.first.sections.first;
  }

  void _selectSection(String key, {required bool isMobile, String? rowTitle}) {
    _highlightTimer?.cancel();
    setState(() {
      _selectedKey = key;
      _highlightRow = rowTitle;
      if (isMobile) _mobileShowingDetail = true;
    });
    if (rowTitle == null) return;
    // The tint is a pointer, not a state: leaving it on would make the row look
    // selected for the rest of the session.
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlightRow = null);
    });
  }

  void _toggleGroup(String title) {
    setState(() {
      if (!_expandedGroups.remove(title)) _expandedGroups.add(title);
    });
  }

  /// Sections matching the live search query, best match first.
  ///
  /// The query is tokenised and every token must match, because
  /// [SettingsSectionDef.matches] is a substring test over single indexed
  /// phrases: the whole string "capture folder" is not a substring of any one
  /// row title, so the two-word phrase a user actually types returned "No
  /// settings match your search" while "folder" alone returned three sections.
  List<SettingsSearchResult> _searchResults(List<SettingsGroupDef> groups) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final tokens =
        query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const [];

    final sections = <SettingsSectionDef>[];
    for (final group in groups) {
      for (final section in group.sections) {
        if (tokens.every((token) => sectionMatchesToken(section, token))) {
          sections.add(section);
        }
      }
    }
    // Stable sort: equal ranks keep sidebar order, so the list only ever
    // PROMOTES a better match rather than reshuffling the taxonomy.
    mergeSort<SettingsSectionDef>(
      sections,
      compare: (a, b) =>
          settingsMatchRank(a, query).compareTo(settingsMatchRank(b, query)),
    );
    return [
      for (final section in sections)
        SettingsSearchResult(section, matchingSettingsRows(section, tokens)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettingsWriteFailure?>(appSettingsWriteFailureProvider, (
      previous,
      next,
    ) {
      if (next == null || identical(previous, next)) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(next.message),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => ref.invalidate(appSettingsProvider),
            ),
          ),
        );
    });
    final colors = Theme.of(context).extension<NightshadeColors>()!;
    final l10n = context.l10n;
    final groups = buildSettingsGroups(context);

    return ContextualTourPrompt(
      screenId: 'settings',
      tourCategory: TutorialCategory.settingsTour,
      title: l10n.text('settingsTourTitle'),
      description: l10n.text('settingsTourDescription'),
      durationMinutes: 3,
      alignment: Alignment.bottomRight,
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Phone tier (< 600 window): list -> full-screen detail navigation.
            //
            // The split view is also dropped whenever THIS screen — not the
            // window — is too narrow to host it. The window can be 800 px wide
            // while the settings body only gets ~580 px because the shell's
            // navigation rail already ate 220 px; a 260 px sidebar then leaves
            // ~320 px of detail, which is not enough for a settings row and
            // made the accent-colour swatches, path pickers, autofocus filter
            // table and calibration status cards overflow off-screen.
            final singlePane = Responsive.isPhone(context) ||
                (constraints.hasBoundedWidth &&
                    constraints.maxWidth < _splitPaneMinWidth);
            return singlePane
                ? _buildMobileLayout(colors, groups)
                : _buildDesktopLayout(colors, groups);
          },
        ),
      ),
    );
  }

  /// Minimum width this screen needs before the sidebar + detail split is
  /// worth showing. Below it the detail pane cannot hold a settings row at
  /// its design width, so the single-pane (list -> detail) flow is used.
  static const double _splitPaneMinWidth = 720;

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
        onSectionTap: (key, rowTitle) =>
            _selectSection(key, isMobile: true, rowTitle: rowTitle),
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
                      fontSize: NightshadeTypography.fontSize18,
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
            child: SettingsRowHighlight(
              rowTitle: _highlightRow,
              child: section.build(true),
            ),
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
                      fontSize: NightshadeTypography.fontSize20,
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
                          onTap: (key, rowTitle) => _selectSection(
                            key,
                            isMobile: false,
                            rowTitle: rowTitle,
                          ),
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
        Expanded(
          child: SettingsRowHighlight(
            rowTitle: _highlightRow,
            child: _selectedSection(groups).build(false),
          ),
        ),
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
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      // A settings section is a control, not a panel: keyboard-only and
      // screen-reader users could not change section at all while this was a
      // bare GestureDetector. InkWell supplies traversal, Enter/Space
      // activation and the button role in one widget; Semantics adds the
      // selected state so AT can announce which section is open.
      child: MergeSemantics(
        child: Semantics(
          // Semantics publishes isEnabled only when this field is given;
          // omitting it makes assistive tech announce a live control as
          // disabled. Measured on the running app 2026-08-09.
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
