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

part 'settings_screen_parts/_search_index.dart';
part 'settings_screen_parts/_desktop_layout.dart';
part 'settings_screen_parts/_mobile_layout.dart';

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
