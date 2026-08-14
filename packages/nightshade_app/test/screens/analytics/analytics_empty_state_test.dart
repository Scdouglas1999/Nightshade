// CON-45 / CON-48: the Analytics tabs must present one empty state, and
// Diagnostics must stop being the one tab with a page title and an essay.
//
// Wave D measured, on one screen: Session centred with a full stop, History
// with no stops, Projects left-aligned with two, Equipment Stats with no empty
// state at all, Diagnostics with a star glyph — four structures, two
// punctuation rules, and not one of the five offering an action. Diagnostics
// additionally rendered an H1 ("Optical Train Diagnostics") and a ~95-word
// paragraph that none of its four siblings had.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_app/screens/analytics/widgets/analytics_empty_state.dart';
import 'package:nightshade_app/screens/diagnostics/diagnostics_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _TutorialsDisabledNotifier extends TutorialNotifier {
  _TutorialsDisabledNotifier() : super(_NoopTutorialProgressDao());

  @override
  // ignore: invalid_use_of_protected_member
  TutorialProgress get state => const TutorialProgress(tutorialsEnabled: false);
}

class _NoopTutorialProgressDao implements TutorialProgressDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _host(Widget child) => ProviderScope(
      overrides: [
        standaloneImagesProvider
            .overrideWith((ref) => Stream.value(const <DbCapturedImage>[])),
        allDbImagesProvider
            .overrideWith((ref) => Stream.value(const <DbCapturedImage>[])),
        allSessionsProvider
            .overrideWith((ref) => Stream.value(const <ImagingSession>[])),
        tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(body: child),
      ),
    );

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .physicalSize = const Size(1400, 900);
    TestWidgetsFlutterBinding
        .instance.platformDispatcher.views.first.devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetDevicePixelRatio();
  });

  group('AnalyticsEmptyState', () {
    testWidgets('states one sentence, labels the title, and offers an action',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const AnalyticsEmptyState(
            icon: Icons.folder_open,
            // Both halves deliberately wrong: a title punctuated as a sentence
            // and a body with no terminal stop. The widget is the one place
            // that rule lives, so translations cannot reintroduce the split.
            title: 'No session history.',
            body: 'Complete an imaging session to see history here',
          ),
        ),
      );

      expect(find.text('No session history'), findsOneWidget);
      expect(
        find.text('Complete an imaging session to see history here.'),
        findsOneWidget,
      );
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('does not double-punctuate a body that is already a sentence',
        (tester) async {
      await tester.pumpWidget(
        _host(
          const AnalyticsEmptyState(
            icon: Icons.folder_open,
            title: 'Nothing captured yet',
            body: 'Start a capture and this tab fills in.',
          ),
        ),
      );

      expect(
        find.text('Start a capture and this tab fills in.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('the Session tab renders the shared widget, with its action',
      (tester) async {
    await tester.pumpWidget(_host(
      const AnalyticsScreen(initialTab: AnalyticsTab.session),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AnalyticsEmptyState), findsOneWidget);
    // The action CON-45 said none of the five tabs offered.
    expect(find.text('Go to Imaging'), findsOneWidget);
  });

  // The other four tabs need a live database to reach their empty branch at
  // all (run stats, project progress, sessionless PSF tiles), so the pin that
  // they share the one widget is structural. Both halves matter: five call
  // sites using it, and no call site keeping a hand-rolled column.
  test('all five Analytics empty states go through AnalyticsEmptyState', () {
    const sites = <String, String>{
      'Session': 'lib/screens/analytics/analytics_screen/session_tab.dart',
      'History': 'lib/screens/analytics/analytics_screen/history_tab.dart',
      'Projects': 'lib/screens/analytics/widgets/project_tracking_panel.dart',
      'Equipment Stats':
          'lib/screens/analytics/analytics_screen/equipment_stats.dart',
      'Diagnostics': 'lib/screens/diagnostics/diagnostics_screen.dart',
    };
    final missing = <String>[];
    sites.forEach((tab, path) {
      final file = File(path);
      if (!file.existsSync() ||
          !file.readAsStringSync().contains('AnalyticsEmptyState(')) {
        missing.add('$tab ($path)');
      }
    });
    expect(
      missing,
      isEmpty,
      reason: 'these tabs still hand-roll an empty state: '
          '${missing.join(', ')}',
    );
  });

  group('Diagnostics chrome (CON-48)', () {
    testWidgets('the Analytics tab prints no page title and no essay',
        (tester) async {
      await tester.pumpWidget(_host(const DiagnosticsTabContent()));
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('Optical Train Diagnostics'),
        findsNothing,
        reason: 'the tab strip two rows above already names this tab, and no '
            'sibling tab prints an H1',
      );
      expect(
        find.textContaining('Analytics tracks per-frame image quality'),
        findsNothing,
        reason: 'the scope contrast belongs in the guide the chip opens',
      );
      expect(
        find.textContaining('Lower scores are better.'),
        findsOneWidget,
        reason: 'the one line worth keeping on the page',
      );
    });

    testWidgets('the standalone route keeps its title', (tester) async {
      await tester.pumpWidget(
        _host(const DiagnosticsTabContent(showTitle: true)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Optical Train Diagnostics'), findsOneWidget);
    });
  });
}
