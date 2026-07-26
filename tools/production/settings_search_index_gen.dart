// Generates the Settings search index from the settings widgets themselves.
//
// WHY THIS EXISTS
// ---------------
// `SettingsSectionDef.keywords` used to be the ONLY thing the Settings search
// box matched against, and it was maintained by hand. Measured on the live app,
// 243 of 496 rendered setting rows (49%) could not be found by typing their own
// visible title: "Safety fail mode", "Park on unsafe weather", "Default
// watermark template" and "Default broadcast port" all returned "No settings
// match your search". Worse than incomplete, it misdirected — searching
// "thumbnail" returned only Captured Images even though the Sequencer page has a
// "Default thumbnail size" row.
//
// A hand-maintained index drifts by construction: nothing forces the author of a
// new setting row to also add a keyword. So the index is derived from the row
// titles instead, and `--check` fails CI when it goes stale.
//
// USAGE
//   dart run tools/production/settings_search_index_gen.dart          # write
//   dart run tools/production/settings_search_index_gen.dart --check  # verify
//
// The hand-written `keywords` lists are deliberately KEPT. They carry synonyms a
// title cannot ("dark mode" for Appearance, "gain" for a page that says
// "Sensor"), which is exactly the value a derived index cannot supply.
import 'dart:io';

const _generatedPath =
    'packages/nightshade_app/lib/screens/settings/settings_search_index.g.dart';
const _catalogPath =
    'packages/nightshade_app/lib/screens/settings/settings_catalog.dart';
const _translationsPath =
    'packages/nightshade_app/lib/localization/nightshade_localizations/translations.dart';
const _libRoot = 'packages/nightshade_app/lib';

void main(List<String> args) {
  final checkOnly = args.contains('--check');
  final repoRoot = _findRepoRoot();
  if (repoRoot == null) {
    stderr.writeln('error: could not locate repo root (no melos.yaml found)');
    exit(2);
  }

  final generated = _generate(repoRoot);
  final target = File('$repoRoot/$_generatedPath');

  if (!checkOnly) {
    target.writeAsStringSync(generated);
    final terms = RegExp(
      r"^\s{4}'",
      multiLine: true,
    ).allMatches(generated).length;
    stdout.writeln('wrote $_generatedPath ($terms search terms)');
    return;
  }

  final existing = target.existsSync() ? target.readAsStringSync() : '';
  if (existing == generated) {
    stdout.writeln('settings search index is up to date');
    return;
  }
  stderr.writeln(
    'error: $_generatedPath is stale.\n'
    'A setting row title was added, removed, or reworded without regenerating '
    'the search index, so the Settings search box can no longer find it.\n'
    'Fix: dart run tools/production/settings_search_index_gen.dart',
  );
  exit(1);
}

String? _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File('${dir.path}/melos.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// `key` -> widget class that renders that section's detail pane.
Map<String, String> _sectionWidgets(String catalogSource) {
  final result = <String, String>{};
  // Each SettingsSectionDef literal spans from `SettingsSectionDef(` to the
  // `build:` line that names its widget, which is always the last field.
  final defs = RegExp(
    r'SettingsSectionDef\((.*?)build:\s*\(isMobile\)\s*=>\s*(?:const\s+)?([A-Za-z0-9_]+)',
    dotAll: true,
  );
  for (final m in defs.allMatches(catalogSource)) {
    final key = RegExp(r"key:\s*'([^']+)'").firstMatch(m.group(1)!);
    if (key == null) continue;
    result[key.group(1)!] = m.group(2)!;
  }
  return result;
}

/// Class name -> source file, for every class under the app's lib/.
Map<String, File> _classIndex(String repoRoot) {
  final index = <String, File>{};
  final classDecl = RegExp(r'^class ([A-Za-z0-9_]+)', multiLine: true);
  for (final entity in Directory(
    '$repoRoot/$_libRoot',
  ).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final m in classDecl.allMatches(source)) {
      index.putIfAbsent(m.group(1)!, () => entity);
    }
  }
  return index;
}

/// The English translation table, so `l10n.text('k')` titles resolve to the
/// string a user actually reads.
Map<String, String> _englishStrings(String translationsSource) {
  final start = translationsSource.indexOf("'en':");
  if (start < 0) return const {};
  // The 'es' block follows; stop there so Spanish strings do not leak into the
  // index and make an English query match a Spanish-only term.
  var end = translationsSource.indexOf("'es':", start);
  if (end < 0) end = translationsSource.length;
  final block = translationsSource.substring(start, end);
  final entry = RegExp(r"'([A-Za-z0-9_]+)'\s*:\s*'((?:[^'\\]|\\.)*)'");
  final result = <String, String>{};
  for (final m in entry.allMatches(block)) {
    result.putIfAbsent(m.group(1)!, () => m.group(2)!);
  }
  return result;
}

/// Constructors whose `label:`/`labelText:` names a SETTING rather than an
/// action. A button's label is a verb ("Delete", "Cancel") and indexing it would
/// make "delete" match half the app; an input's label is the setting's name.
final _inputWidget = RegExp(r'(Field|Input|Number|Slider|Dropdown|Picker)$');

/// Every human-readable setting name in [source], with `l10n` keys resolved.
List<String> _titles(String source, Map<String, String> english) {
  final found = <String>[];

  void addLiteral(RegExp pattern, {bool inputsOnly = false}) {
    for (final m in pattern.allMatches(source)) {
      if (inputsOnly && !_enclosedByInput(source, m.start)) continue;
      found.add(m.group(1)!);
    }
  }

  void addKey(RegExp pattern, {bool inputsOnly = false}) {
    for (final m in pattern.allMatches(source)) {
      if (inputsOnly && !_enclosedByInput(source, m.start)) continue;
      final resolved = english[m.group(1)!];
      if (resolved != null) found.add(resolved);
    }
  }

  addLiteral(RegExp(r"title:\s*'((?:[^'\\]|\\.)*)'"));
  addKey(RegExp(r"title:\s*(?:context\.)?l10n\.text\(\s*'([A-Za-z0-9_]+)'"));
  // Some pages label their controls directly instead of wrapping each one in a
  // SettingRow — the whole Adaptive Exposure page is built that way, and it had
  // no searchable content at all until these were included.
  addLiteral(
    RegExp(r"label(?:Text)?:\s*'((?:[^'\\]|\\.)*)'"),
    inputsOnly: true,
  );
  addKey(
    RegExp(r"label(?:Text)?:\s*(?:context\.)?l10n\.text\(\s*'([A-Za-z0-9_]+)'"),
    inputsOnly: true,
  );
  return found;
}

/// Setting names rendered by [file] AND by any settings page it embeds.
///
/// Two catalog entries are pure composers: Files & Storage and Autofocus render
/// nothing themselves, they stack other settings pages inside a shared shell. Not
/// following the composition left both of them with an empty index, so none of
/// their settings could be found by name.
List<String> _collect(
  File file,
  Map<String, File> classes,
  Map<String, String> english, {
  int depth = 0,
  Set<String>? visited,
}) {
  visited ??= <String>{};
  if (!visited.add(file.path) || depth > 3) return const [];
  final source = file.readAsStringSync();
  final found = _titles(source, english);
  // Follow constructor calls that resolve to another page under settings/,
  // excluding the shared row/section components — those are generic chrome and
  // their internal strings are not this page's content.
  for (final m in RegExp(r'\b([A-Z][A-Za-z0-9_]{3,})\(').allMatches(source)) {
    final target = classes[m.group(1)!];
    if (target == null) continue;
    final path = target.path;
    if (!path.contains('/screens/settings/')) continue;
    if (path.contains('/widgets/settings_widgets/')) continue;
    found.addAll(
      _collect(target, classes, english, depth: depth + 1, visited: visited),
    );
  }
  return found;
}

/// Whether the argument at [offset] belongs to an input-like constructor.
bool _enclosedByInput(String source, int offset) {
  final name = _enclosingConstructor(source, offset);
  return name != null && _inputWidget.hasMatch(name);
}

/// The constructor whose argument list encloses [offset].
///
/// Must count parens rather than take the nearest preceding `(`: earlier
/// arguments routinely open and close their own calls, e.g.
/// `_LabeledNumberField(fieldKey: const ValueKey('x'), label: 'Reference')`,
/// where the naive answer is `ValueKey` and the real one is
/// `_LabeledNumberField`. Getting this wrong silently dropped an entire settings
/// page out of the index.
String? _enclosingConstructor(String source, int offset) {
  final from = offset < 2000 ? 0 : offset - 2000;
  // Blank out string literals so parentheses inside labels ("Exposure (s)") do
  // not unbalance the count.
  final window = source
      .substring(from, offset)
      .replaceAll(RegExp(r"'(?:[^'\\\n]|\\.)*'"), "''");
  var depth = 0;
  for (var i = window.length - 1; i >= 0; i--) {
    final c = window[i];
    if (c == ')') {
      depth++;
    } else if (c == '(') {
      if (depth == 0) {
        final head = RegExp(
          r'([A-Za-z_][A-Za-z0-9_]*)$',
        ).firstMatch(window.substring(0, i));
        return head?.group(1);
      }
      depth--;
    }
  }
  return null;
}

/// Keeps only titles that are useful, stable search terms.
List<String> _clean(Iterable<String> titles) {
  final seen = <String, String>{};
  for (final raw in titles) {
    // Dart interpolation renders differently per state, so it is not a term.
    if (raw.contains(r'$')) continue;
    final text = raw
        .replaceAll(r'\n', ' ')
        .replaceAll(r"\'", "'")
        .replaceAll(RegExp(r'\\u[0-9A-Fa-f]{4}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.length < 3) continue;
    // A title needs at least one word; bare punctuation or units are noise.
    if (!RegExp(r'[A-Za-z]{3}').hasMatch(text)) continue;
    seen.putIfAbsent(text.toLowerCase(), () => text);
  }
  final result = seen.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return result;
}

String _generate(String repoRoot) {
  final catalog = File('$repoRoot/$_catalogPath').readAsStringSync();
  final english = _englishStrings(
    File('$repoRoot/$_translationsPath').readAsStringSync(),
  );
  final classes = _classIndex(repoRoot);
  final widgets = _sectionWidgets(catalog);

  final missing = <String>[];
  final entries = <String, List<String>>{};
  for (final key in widgets.keys.toList()..sort()) {
    final file = classes[widgets[key]!];
    if (file == null) {
      missing.add('$key -> ${widgets[key]}');
      continue;
    }
    final titles = _clean(_collect(file, classes, english));
    if (titles.isNotEmpty) entries[key] = titles;
  }
  if (missing.isNotEmpty) {
    stderr.writeln(
      'error: could not resolve the widget for these settings sections, so '
      'their rows would silently become unsearchable:\n  '
      '${missing.join('\n  ')}',
    );
    exit(2);
  }

  final out = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT BY HAND.')
    ..writeln('//')
    ..writeln('// Regenerate with:')
    ..writeln('//   dart run tools/production/settings_search_index_gen.dart')
    ..writeln('//')
    ..writeln(
      '// Source of truth is the `title:` of every row each settings section',
    )
    ..writeln(
      '// actually renders, so typing a setting\'s visible name finds it. See',
    )
    ..writeln('// tools/production/settings_search_index_gen.dart for why.')
    ..writeln()
    ..writeln(
      '/// Settings section key -> the row titles that section renders.',
    )
    ..writeln('const Map<String, List<String>> kSettingsSearchTerms = {');
  for (final key in entries.keys) {
    out.writeln("  '$key': [");
    for (final term in entries[key]!) {
      out.writeln(
        "    '${term.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}',",
      );
    }
    out.writeln('  ],');
  }
  out.writeln('};');
  return out.toString();
}
