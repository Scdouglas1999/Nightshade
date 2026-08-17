// The Analytics session dialog's header at the widths it is actually opened at.
//
// Two defects lived here, and both are about a control the app claims to offer
// and does not:
//
//  * the action cluster was a horizontally scrolling Row, so at phone width the
//    first three icons — "Review & Integrate", "Refine in Darkroom" and
//    "Session Report" — were clipped away while the accessibility tree went on
//    advertising all seven, and a tap where one used to be landed on nothing;
//  * the Darkroom refusal was posted to the page's ScaffoldMessenger while the
//    dialog deliberately stayed up to carry it, so the modal route painted over
//    the SnackBar and the operator read half a sentence, or two words of it.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

class _MockImagesDao extends Mock implements ImagesDao {}

class _MockIntegratedMastersDao extends Mock implements IntegratedMastersDao {}

/// A session whose frames were never folded into a master.
class _NoMastersResolver extends DawnMasterResolver {
  _NoMastersResolver()
      : super(images: _MockImagesDao(), masters: _MockIntegratedMastersDao());

  @override
  Future<DawnMasterSet> resolve(int sessionId) async => DawnMasterSet(
        sessionId: sessionId,
        masters: const [],
        withoutFile: const [],
      );
}

class _PinnedBackend extends BackendNotifier {
  _PinnedBackend(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

class _TutorialsDisabledNotifier extends TutorialNotifier {
  _TutorialsDisabledNotifier() : super(_NoopTutorialProgressDao()) {
    // ignore: invalid_use_of_protected_member
    state = const TutorialProgress(tutorialsEnabled: false);
  }
}

class _NoopTutorialProgressDao implements TutorialProgressDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
        'NoopTutorialProgressDao.${invocation.memberName} called in test',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openDialog(WidgetTester tester, {required Size window}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = window;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final session = ImagingSession(
      id: 5,
      name: 'Night A - M31',
      startTime: DateTime(2026, 7, 30),
      totalExposures: 12,
      successfulExposures: 12,
      failedExposures: 0,
      totalIntegrationSecs: 1440,
      autofocusCount: 0,
      status: 'completed',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _PinnedBackend(ref, DisconnectedBackend()),
          ),
          dawnMasterResolverProvider.overrideWithValue(_NoMastersResolver()),
          // The Session Report action opens a dialog over this one and watches
          // this. Scripted so the tap reaches no database: what is under test
          // is what the press does to the alert BELOW the report, not the
          // report.
          sessionReportProvider(5).overrideWith(
            (ref) => throw StateError('no session report in this test'),
          ),
          allSessionsProvider.overrideWith(
            (ref) => Stream<List<ImagingSession>>.value([session]),
          ),
          standaloneImagesProvider.overrideWith(
            (ref) => Stream<List<DbCapturedImage>>.value(const []),
          ),
          allDbImagesProvider.overrideWith(
            (ref) => Stream<List<DbCapturedImage>>.value(const []),
          ),
          dbSessionImagesProvider(5).overrideWith(
            (ref) => Stream<List<DbCapturedImage>>.value(const []),
          ),
          tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AnalyticsScreen(initialTab: AnalyticsTab.history),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Night A - M31'));
    // pump, not pumpAndSettle: the thumbnail futures never go idle locally.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Every named, tappable control the semantics tree currently publishes.
  List<String> tappableNames(WidgetTester tester) {
    final names = <String>[];
    void walk(SemanticsNode node) {
      final data = node.getSemanticsData();
      if (data.hasFlag(SemanticsFlag.isButton) &&
          data.hasAction(SemanticsAction.tap) &&
          data.label.isNotEmpty) {
        names.add(data.label);
      }
      node.visitChildren((child) {
        walk(child);
        return true;
      });
    }

    walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
    return names;
  }

  testWidgets('a laptop-width dialog keeps every action inline', (
    tester,
  ) async {
    await openDialog(tester, window: const Size(1400, 900));

    expect(
      find.byKey(const ValueKey('session_detail_actions_menu')),
      findsNothing,
      reason: 'there is room for the icons, so nothing folds',
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(IconButton),
      ),
      findsNWidgets(7),
      reason: 'six actions plus the close button',
    );
    expect(find.byTooltip('Refine in Darkroom'), findsOneWidget);
  });

  testWidgets('at phone width the cluster folds and the tree follows it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openDialog(tester, window: const Size(430, 900));

    // What paints: one overflow button and the close.
    expect(
      find.byKey(const ValueKey('session_detail_actions_menu')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(IconButton),
      ),
      findsNWidgets(2),
    );

    // What the tree says: exactly the same two, and NOT the six that used to be
    // announced from inside a clipped scroll view.
    final announced = tappableNames(tester);
    expect(announced, contains('Session actions'));
    expect(announced, contains('Close'));
    expect(announced, isNot(contains('Refine in Darkroom')));
    expect(announced, isNot(contains('Review & Integrate')));
    expect(announced, isNot(contains('Session Report')));

    // And every one of them is reachable once the menu is open.
    await tester.tap(find.byKey(const ValueKey('session_detail_actions_menu')));
    // pump, not pumpAndSettle: the dialog behind the menu holds thumbnail
    // futures that never go idle here.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final label in const [
      'Review & Integrate',
      'Refine in Darkroom',
      'Session Report',
      'Export to JSON',
      'Export to CSV',
      'Export HTML report',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label is unreachable');
    }
    handle.dispose();
  });

  testWidgets('the Darkroom refusal renders inside the dialog that carries it',
      (tester) async {
    await openDialog(tester, window: const Size(1100, 800));

    await tester.tap(find.byKey(const ValueKey('session_detail_darkroom')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    const reason = 'This session has no integrated master yet. Integrate it in '
        'Session Review first, then refine it here.';
    // Inside the dialog subtree — not in the page's ScaffoldMessenger, which
    // this modal route paints over.
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text(reason),
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.byType(Dialog),
      findsOneWidget,
      reason: 'the dialog stays up to carry the explanation',
    );

    // It is dismissible, and dismissing it leaves the dialog behind.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('session_detail_refusal')),
        matching: find.byTooltip('Dismiss'),
      ),
    );
    await tester.pump();
    expect(find.text(reason), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('a standing refusal does not outlive the next press',
      (tester) async {
    await openDialog(tester, window: const Size(1100, 800));

    await tester.tap(find.byKey(const ValueKey('session_detail_darkroom')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.byKey(const ValueKey('session_detail_refusal')),
      findsOneWidget,
    );

    // A different action: whatever it goes on to do, the sentence about the
    // last one has stopped describing anything on screen. Session Report is
    // the one action that neither dismisses this dialog nor writes a file —
    // it opens a second dialog over it whose own data is an AsyncValue.
    await tester.tap(find.byTooltip('Session Report'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const ValueKey('session_detail_refusal')), findsNothing);
  });
}
