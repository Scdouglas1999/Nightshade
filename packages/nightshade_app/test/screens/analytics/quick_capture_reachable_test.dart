// WD-SCI-N1: once one sequence run exists, the quick captures must still be
// reachable from Analytics ▸ Session and ▸ Science.
//
// Live evidence (Wave D, 2026-08-13): with 37 loop frames and one completed
// 4-frame run on record, the "Reviewing" selector read "Quick captures (no
// session selected)" but its menu held exactly one entry — the run. Selecting
// it, leaving the tab and coming back never brought the 37 frames' charts,
// captured-image grid, photometry or field-quality products back; History's own
// Quick captures card meanwhile instructs the operator to "open Analytics ▸
// Session to review them frame by frame". Diagnostics already offered the
// entry, so the picker — not the data — was the whole defect.
//
// The counter-input these pins encode is the one the live drive used: standalone
// frames AND a session, with the auto-pick resolving to the session.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/accessible_dropdown.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_app/screens/analytics/quick_capture_selection.dart';
import 'package:nightshade_app/screens/analytics/widgets/science_analytics_tab.dart';
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

DbCapturedImage _standalone(int id) => DbCapturedImage(
      id: id,
      filePath: '/tmp/$id.fits',
      fileName: '$id.fits',
      fileFormat: 'fits',
      frameType: 'light',
      exposureDuration: 30,
      binX: 1,
      binY: 1,
      capturedAt: DateTime.utc(2026, 8, 13, 18, 10),
      createdAt: DateTime.utc(2026, 8, 13, 18, 10),
      isAccepted: true,
      isPlateSolved: false,
      hfr: 2.15,
    );

ImagingSession _run(int id) => ImagingSession(
      id: id,
      name: 'New Sequence',
      startTime: DateTime.utc(2026, 8, 13, 18, 45),
      totalExposures: 4,
      successfulExposures: 4,
      failedExposures: 0,
      totalIntegrationSecs: 12,
      autofocusCount: 0,
      status: 'completed',
    );

/// The exact live state: 37 loose frames, one completed run, and the auto-pick
/// resolving to that run (`latestScienceSessionProvider`).
Widget _app(AnalyticsTab tab) => ProviderScope(
      overrides: [
        standaloneImagesProvider.overrideWith(
          (ref) => Stream.value([for (var i = 1; i <= 37; i++) _standalone(i)]),
        ),
        allDbImagesProvider
            .overrideWith((ref) => Stream.value(const <DbCapturedImage>[])),
        allSessionsProvider.overrideWith((ref) => Stream.value([_run(1)])),
        latestScienceSessionProvider.overrideWith((ref) async => 1),
        latestScienceProductSessionProvider.overrideWith((ref) async => 1),
        tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(body: AnalyticsScreen(initialTab: tab)),
      ),
    );

/// The picker inside the review bar carrying [label] ("Reviewing" on Session,
/// "Analysing" on Science) — never any other dropdown on the screen.
Finder _pickerUnder(String label) => find.descendant(
      of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
      matching: find.byType(AccessibleDropdown<int>),
    );

/// Advance frames without `pumpAndSettle`: the Analytics IndexedStack keeps a
/// shimmer skeleton animating on a sibling tab, so settling never completes.
Future<void> _pumpFrames(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

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

  testWidgets('Session offers the quick captures back and honours the choice',
      (tester) async {
    await tester.pumpWidget(_app(AnalyticsTab.session));
    await tester.pump(const Duration(milliseconds: 300));

    // Preconditions: the run won the auto-pick, so the tab is on the run.
    expect(find.text('New Sequence'), findsWidgets);
    expect(find.text('Quick Capture'), findsNothing);

    await tester.tap(_pickerUnder('Reviewing'));
    await _pumpFrames(tester);

    expect(
      find.text(kQuickCaptureSessionLabel),
      findsOneWidget,
      reason: 'the picker lists only sequence runs, so the 37 loose frames are '
          'unreachable for the rest of the app\'s life',
    );

    await tester.tap(find.text(kQuickCaptureSessionLabel).last);
    await _pumpFrames(tester);

    expect(
      find.text('Quick Capture'),
      findsOneWidget,
      reason: 'choosing the quick captures must actually switch to them, not '
          'fall straight back to the auto-picked run',
    );
  });

  testWidgets('the Session choice survives a rebuild', (tester) async {
    await tester.pumpWidget(_app(AnalyticsTab.session));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(_pickerUnder('Reviewing'));
    await _pumpFrames(tester);
    await tester.tap(find.text(kQuickCaptureSessionLabel).last);
    await _pumpFrames(tester);

    // The live drive's second half: the auto-pick must not quietly reclaim the
    // tab on the next build.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Quick Capture'), findsOneWidget);
  });

  testWidgets('Science offers the same entry under its own label',
      (tester) async {
    await tester.pumpWidget(_app(AnalyticsTab.science));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(_pickerUnder('Analysing'));
    await _pumpFrames(tester);

    expect(
      find.text(kQuickCaptureSessionLabel),
      findsOneWidget,
      reason: 'SCI-46 landed in one picker of three; Science was the second',
    );
  });
}
