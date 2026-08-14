// CON-62 — Help & Tutorials showed one page speaking two dialects.
//
// The E-fix closed the VERB split (Start / Re-run / Open -> Start). Wave F
// re-drove the page and found two halves still open:
//
//   (a) the row titles mix Title Case and sentence case in one list —
//       "First Night Walkthrough", "Capture your first light",
//       "Re-run equipment setup", "Re-run onboarding tour",
//       "Generate Diagnostic Dump" (44-help.png);
//   (b) the treatment split MOVED rather than vanished: the five Tutorial
//       Tours rows render FILLED BLUE "Start" buttons directly beneath the
//       five OUTLINE "Start" buttons of Guided Flows, so one page still
//       shows two treatments for one verb (45-help2.png).
//
// Both are asserted here on the RENDERED page, and (a) is additionally
// guarded mechanically over the widget's own source so a new row cannot
// reintroduce the split by adding a sixth Title Case title.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/settings/settings_search_index.g.dart';
import 'package:nightshade_app/screens/settings/widgets/help_tutorials_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

NightshadeDatabase _newInMemoryDb() =>
    NightshadeDatabase.forTesting(NativeDatabase.memory());

Future<ProviderContainer> _pumpHelpScreen(
  WidgetTester tester, {
  required NightshadeDatabase db,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 1400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = ProviderContainer(
    overrides: [
      backendProvider.overrideWith(
        (ref) => TestBackendNotifier(ref, mockBackend()),
      ),
      databaseProvider.overrideWithValue(db),
      appVersionProvider.overrideWithValue(
        const AppVersionInfo(version: '0.0.0-test', buildNumber: 0),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: '/help',
    routes: [
      GoRoute(
        path: '/help',
        builder: (context, state) =>
            const Scaffold(body: HelpTutorialsSettings()),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: NightshadeTheme.dark,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 5));
  return container;
}

/// The verbs a row uses for "run this thing". All of them must be drawn the
/// same way on one page.
const Set<String> _runVerbs = {'Start', 'Resume', 'Restart'};

/// Title Case = two or more capitalised words. Words that are capitalised
/// because they are proper nouns of the product are exempt.
const Set<String> _properNouns = {
  'Nightshade',
  'PHD2',
  'ASCOM',
  'INDI',
  'Alpaca',
};

bool _isTitleCase(String title) {
  final words =
      title.split(RegExp(r'[\s/]+')).where((w) => w.isNotEmpty).toList();
  if (words.length < 2) return false;
  var capitalised = 0;
  for (var i = 1; i < words.length; i++) {
    final w = words[i];
    if (_properNouns.contains(w)) continue;
    if (w[0] == w[0].toUpperCase() && w[0] != w[0].toLowerCase()) {
      capitalised++;
    }
  }
  return capitalised > 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every row title on the page is in one case register', (
    tester,
  ) async {
    final db = _newInMemoryDb();
    addTearDown(() async => db.close());
    await _pumpHelpScreen(tester, db: db);

    for (final title in const [
      'First night walkthrough',
      'Capture your first light',
      'Re-run equipment setup',
      'Re-run onboarding tour',
      'Generate diagnostic dump',
      'Equipment setup',
      'Target planning',
      'Automated imaging',
      'Calibration frames',
      'Advanced features',
      'Reset all progress',
      'Enable tutorials',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing row "$title"');
    }
    for (final shouted in const [
      'First Night Walkthrough',
      'Generate Diagnostic Dump',
      'Equipment Setup',
      'Calibration Frames',
      'Reset All Progress',
    ]) {
      expect(
        find.text(shouted),
        findsNothing,
        reason: 'CON-62: "$shouted" is the second register',
      );
    }
  });

  testWidgets('one verb is drawn one way across the whole page', (
    tester,
  ) async {
    final db = _newInMemoryDb();
    addTearDown(() async => db.close());
    await _pumpHelpScreen(tester, db: db);

    final buttons = tester
        .widgetList<NightshadeButton>(find.byType(NightshadeButton))
        .where((b) => _runVerbs.contains(b.label))
        .toList();
    expect(
      buttons.length,
      greaterThanOrEqualTo(10),
      reason: 'five Guided Flows rows + five Tutorial Tours rows',
    );
    final variants = buttons.map((b) => b.variant).toSet();
    expect(
      variants,
      hasLength(1),
      reason: 'CON-62(b): the Tutorial Tours "Start" rendered filled-primary '
          'directly beneath the outline "Start" of Guided Flows',
    );
    expect(variants.single, ButtonVariant.outline);
  });

  test('no row title in the widget source is Title Case', () {
    final source = File(
      'lib/screens/settings/widgets/help_tutorials_settings.dart',
    ).readAsStringSync();
    final offenders = <String>[];
    for (final match in RegExp(
      r"^\s*title: '([^']+)',",
      multiLine: true,
    ).allMatches(source)) {
      final title = match.group(1)!;
      if (_isTitleCase(title)) offenders.add(title);
    }
    // The SECTION headers are a different level of the hierarchy and stay
    // Title Case app-wide; they are declared with `title:` too, so they are
    // the expected members of this list and nothing else may join them.
    expect(
      offenders,
      unorderedEquals(<String>[
        'Guided Flows',
        'Tutorial Tours',
        'Reset Progress',
        'Help & Tutorials',
      ]),
    );
  });

  test('the generated settings search index carries the new titles', () {
    final help = kSettingsSearchTerms['help'];
    expect(help, isNotNull, reason: 'the Help section must be indexed');
    expect(help, contains('First night walkthrough'));
    expect(help, contains('Generate diagnostic dump'));
    expect(
      help,
      isNot(contains('First Night Walkthrough')),
      reason: 'a stale index makes the row unfindable by its visible name',
    );
  });
}
