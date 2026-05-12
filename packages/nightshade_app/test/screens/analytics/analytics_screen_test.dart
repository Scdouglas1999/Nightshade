// Tests for the Analytics screen tab structure after Diagnostics was merged
// in as a tab (§UX consolidation). We don't spin up the full Riverpod graph
// (which would require a real drift database, an Ffi backend, and the full
// event bus). Instead we override the stream providers each tab reads with
// deterministic test doubles that emit a single empty list, so the tab
// chrome renders without the heavy database stack.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_core/nightshade_core.dart' hide CapturedImage;
// ignore: implementation_imports
import 'package:nightshade_core/src/database/database.dart'
    show CapturedImage, ImagingSession;
// ignore: implementation_imports
import 'package:nightshade_core/src/database/daos/tutorial_progress_dao.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// Test-only TutorialNotifier that reports tutorials disabled so the
/// `ContextualTourPrompt` short-circuits before scheduling its 500 ms
/// `Future.delayed`. Without this override the test framework reports a
/// pending timer at teardown because the prompt is still waiting to fade in.
class _TutorialsDisabledNotifier extends TutorialNotifier {
  _TutorialsDisabledNotifier()
      : super(_NoopTutorialProgressDao()) {
    // ignore: invalid_use_of_protected_member
    state = const TutorialProgress(tutorialsEnabled: false);
  }
}

class _NoopTutorialProgressDao implements TutorialProgressDao {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    // The disabled notifier never reads from the DAO; if any helper does,
    // surface it loudly rather than swallow it.
    throw UnimplementedError(
      'NoopTutorialProgressDao.${invocation.memberName} called in test',
    );
  }
}

List<Override> _commonOverrides() {
  return [
    allSessionsProvider.overrideWith(
      (ref) => Stream<List<ImagingSession>>.value(const []),
    ),
    standaloneImagesProvider.overrideWith(
      (ref) => Stream<List<CapturedImage>>.value(const []),
    ),
    allDbImagesProvider.overrideWith(
      (ref) => Stream<List<CapturedImage>>.value(const []),
    ),
    tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('analyticsTabFromQuery', () {
    test('returns null for null input', () {
      expect(analyticsTabFromQuery(null), isNull);
    });

    test('returns null for an unrecognised value', () {
      expect(analyticsTabFromQuery('made-up-tab'), isNull);
    });

    test('maps canonical tab names', () {
      expect(analyticsTabFromQuery('session'), AnalyticsTab.session);
      expect(analyticsTabFromQuery('history'), AnalyticsTab.history);
      expect(analyticsTabFromQuery('projects'), AnalyticsTab.projects);
      expect(analyticsTabFromQuery('equipment'), AnalyticsTab.equipment);
      expect(analyticsTabFromQuery('science'), AnalyticsTab.science);
      expect(analyticsTabFromQuery('diagnostics'), AnalyticsTab.diagnostics);
    });

    test('accepts case-insensitive equipment aliases', () {
      expect(analyticsTabFromQuery('Diagnostics'), AnalyticsTab.diagnostics);
      expect(analyticsTabFromQuery('equipment-stats'), AnalyticsTab.equipment);
      expect(analyticsTabFromQuery('equipmentstats'), AnalyticsTab.equipment);
    });

    test('Diagnostics is the right-most enum entry', () {
      expect(
        AnalyticsTab.values.last,
        AnalyticsTab.diagnostics,
        reason:
            'UX consolidation places Diagnostics as the right-most Analytics tab',
      );
    });
  });

  testWidgets('renders all analytics tabs including Diagnostics',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: AnalyticsScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.widgetWithText(SubTabButton, 'Session'), findsOneWidget);
    expect(find.widgetWithText(SubTabButton, 'History'), findsOneWidget);
    expect(find.widgetWithText(SubTabButton, 'Projects'), findsOneWidget);
    expect(
      find.widgetWithText(SubTabButton, 'Equipment Stats'),
      findsOneWidget,
    );
    expect(find.widgetWithText(SubTabButton, 'Science'), findsOneWidget);
    expect(find.widgetWithText(SubTabButton, 'Diagnostics'), findsOneWidget);
  });

  testWidgets('?tab=diagnostics selects the Diagnostics tab on initial render',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: AnalyticsScreen(initialTabQuery: 'diagnostics'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final selectedDiagnostics = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Diagnostics' &&
          widget.isSelected,
    );
    expect(selectedDiagnostics, findsOneWidget);

    // Session is the default tab; it must not be selected when the query
    // explicitly asks for Diagnostics.
    final selectedSession = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Session' &&
          widget.isSelected,
    );
    expect(selectedSession, findsNothing);
  });

  testWidgets('defaults to Session when no query param is supplied',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: _commonOverrides(),
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(body: AnalyticsScreen()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final selectedSession = find.byWidgetPredicate(
      (widget) =>
          widget is SubTabButton &&
          widget.label == 'Session' &&
          widget.isSelected,
    );
    expect(selectedSession, findsOneWidget);
  });
}
