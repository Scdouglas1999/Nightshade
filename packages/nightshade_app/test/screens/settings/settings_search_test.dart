import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/localization/nightshade_localizations.dart';
import 'package:nightshade_app/screens/settings/settings_catalog.dart';
import 'package:nightshade_app/screens/settings/settings_search_index.g.dart';

/// Typing a setting's own visible name into the Settings search box must find
/// the page that setting lives on.
///
/// Regression, measured on the running app: the index was a hand-written
/// `keywords` list, and 243 of 496 rendered setting rows (49%) could not be
/// found by their own title. The queries below are the exact ones observed
/// returning "No settings match your search" while the setting was visibly
/// present on screen.
///
/// The worst of them was not the silence but the misdirection: "thumbnail"
/// returned only Captured Images, even though the Sequencer page has a "Default
/// thumbnail size" row — so the search actively sent you to the wrong page and
/// implied that was the only match.
void main() {
  Future<List<SettingsSectionDef>> allSections(WidgetTester tester) async {
    late List<SettingsGroupDef> groups;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NightshadeLocalizations.localizationsDelegates,
        supportedLocales: NightshadeLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            groups = buildSettingsGroups(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    // Localizations builds its subtree only once the delegate resolves.
    await tester.pumpAndSettle();
    return [for (final g in groups) ...g.sections];
  }

  /// Section keys whose search matches [query], mirroring settings_screen.dart
  /// which lower-cases the query before calling `matches`.
  Set<String> hits(List<SettingsSectionDef> sections, String query) => {
        for (final s in sections)
          if (s.matches(query.toLowerCase())) s.key,
      };

  // Each case is (query typed, section key that must be returned).
  const observedFailures = <(String, String)>[
    // The app's own blocking pre-flight error tells the user to "switch the
    // safety fail mode to fail open in Settings > Automation & Safety". Typing
    // that phrase found nothing, so the app's own advice was a dead end.
    ('fail mode', 'sequencer'),
    ('safety fail', 'sequencer'),
    ('park', 'sequencer'),
    ('watermark', 'sequencer'),
    ('broadcast', 'sequencer'),
    ('thumbnail', 'sequencer'),
    ('auto-connect', 'general'),
    ('confirm before closing', 'general'),
    ('ui scale', 'appearance'),
    ('bortle', 'location'),
    ('limiting magnitude', 'location'),
  ];

  testWidgets('every setting observed as unfindable is now findable', (
    tester,
  ) async {
    final sections = await allSections(tester);
    final broken = <String>[];
    for (final (query, expectedKey) in observedFailures) {
      final matched = hits(sections, query);
      if (!matched.contains(expectedKey)) {
        broken
            .add('"$query" -> expected $expectedKey, got ${matched.toList()}');
      }
    }
    expect(broken, isEmpty, reason: broken.join('\n'));
  });

  testWidgets('a query matching nothing still reports no results', (
    tester,
  ) async {
    final sections = await allSections(tester);
    // Guards against "fix" by making everything match everything.
    expect(hits(sections, 'zzzqqqnotasetting'), isEmpty);
  });

  testWidgets('the generated index covers every section in the catalog', (
    tester,
  ) async {
    final sections = await allSections(tester);
    final catalogKeys = {for (final s in sections) s.key};
    final indexKeys = kSettingsSearchTerms.keys.toSet();

    // A stale index would silently drop a whole page out of search.
    expect(
      indexKeys.difference(catalogKeys),
      isEmpty,
      reason: 'generated index has sections the catalog no longer has; rerun '
          'dart run tools/production/settings_search_index_gen.dart',
    );
    // Pages that legitimately have no named setting rows: a log viewer and two
    // list managers, whose visible strings are action verbs ("Delete",
    // "Rename") rather than setting names. Indexing those would make "delete"
    // match a settings page. They stay reachable by their own section label.
    // A NEW page landing here means its settings are unsearchable — add it only
    // after checking it really has none.
    const noNamedSettings = {'observation-log', 'observing-lists', 'logs'};
    expect(
      catalogKeys.difference(indexKeys).difference(noNamedSettings),
      isEmpty,
      reason:
          'these settings pages contribute no searchable row titles, so their '
          'settings cannot be found by name; rerun '
          'dart run tools/production/settings_search_index_gen.dart',
    );
  });

  testWidgets('every indexed term actually finds its own section', (
    tester,
  ) async {
    final sections = await allSections(tester);
    final byKey = {for (final s in sections) s.key: s};
    final unreachable = <String>[];
    kSettingsSearchTerms.forEach((key, terms) {
      final section = byKey[key];
      if (section == null) return;
      for (final term in terms) {
        if (!section.matches(term.toLowerCase())) {
          unreachable.add('$key: "$term"');
        }
      }
    });
    expect(unreachable, isEmpty, reason: unreachable.take(10).join('\n'));
  });
}
