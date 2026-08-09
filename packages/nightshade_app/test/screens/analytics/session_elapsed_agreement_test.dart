// A session the app never closed must be described the same way everywhere.
//
// Observed defect: for one row (status in_progress, end_time NULL, three
// frames spanning 20 minutes) Analytics > History read "46h 2m elapsed" —
// `now - startTime`, which grows forever after a crash — while Analytics >
// Session read "DURATION 0s", because it computed
// `(endTime ?? startTime) - startTime`. Two readouts, both false, in one app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_app/screens/analytics/widgets/science_analytics_tab.dart'
    show latestScienceSessionProvider;
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _TutorialsDisabledNotifier extends TutorialNotifier {
  _TutorialsDisabledNotifier() : super(_NoopTutorialProgressDao()) {
    // ignore: invalid_use_of_protected_member
    state = const TutorialProgress(tutorialsEnabled: false);
  }
}

class _NoopTutorialProgressDao implements TutorialProgressDao {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final _start = DateTime.utc(2026, 7, 30, 20, 30);

/// Night C - M31: never closed, three frames over 20.3 minutes.
final _unfinished = ImagingSession(
  id: 3,
  name: 'Night C - M31',
  startTime: _start,
  totalExposures: 3,
  successfulExposures: 3,
  failedExposures: 0,
  totalIntegrationSecs: 900,
  autofocusCount: 0,
  status: 'in_progress',
);

DbCapturedImage _image({required int id, required int minutesIn}) =>
    DbCapturedImage(
      id: id,
      sessionId: 3,
      filePath: '/tmp/$id.fits',
      fileName: '$id.fits',
      fileFormat: 'fits',
      frameType: 'light',
      exposureDuration: 300,
      binX: 1,
      binY: 1,
      capturedAt: _start.add(Duration(minutes: minutesIn)),
      createdAt: _start.add(Duration(minutes: minutesIn)),
      isAccepted: true,
      isPlateSolved: false,
      hfr: 2.2,
    );

final _frames = [
  _image(id: 1, minutesIn: 0),
  _image(id: 2, minutesIn: 10),
  _image(id: 3, minutesIn: 20),
];

Widget _app(AnalyticsTab tab) {
  return ProviderScope(
    overrides: [
      allSessionsProvider.overrideWith((ref) => Stream.value([_unfinished])),
      allDbImagesProvider.overrideWith((ref) => Stream.value(_frames)),
      dbSessionImagesProvider.overrideWith((ref, id) => Stream.value(_frames)),
      latestScienceSessionProvider.overrideWith((ref) async => 3),
      standaloneImagesProvider.overrideWith(
        (ref) => Stream.value(const <DbCapturedImage>[]),
      ),
      tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
    ],
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(body: AnalyticsScreen(initialTab: tab)),
    ),
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .physicalSize = const Size(1400, 2400);
    TestWidgetsFlutterBinding
        .instance.platformDispatcher.views.first.devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetDevicePixelRatio();
  });

  testWidgets('the Session tab does not report 0s for an unclosed session',
      (tester) async {
    await tester.pumpWidget(_app(AnalyticsTab.session));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('0s'),
      findsNothing,
      reason: 'a 20-minute session must not be reported as lasting 0s',
    );
    expect(find.text('20m'), findsWidgets);
    // The stat strip uppercases its caption.
    expect(find.textContaining('TO LAST FRAME'), findsOneWidget);
  });

  testWidgets('the History card does not accrue wall-clock time after a crash',
      (tester) async {
    await tester.pumpWidget(_app(AnalyticsTab.history));
    await tester.pump(const Duration(milliseconds: 300));

    // `now - startTime` for a July 2026 start is hours at best and years at
    // worst; either way it is not the session's span.
    final wallClock = RegExp(r'^\d+h \d+m$');
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d != null && wallClock.hasMatch(d)),
      isEmpty,
      reason: 'History must not print wall-clock elapsed for an unclosed row',
    );
    expect(find.text('20m'), findsOneWidget);
    expect(find.text('to last frame'), findsOneWidget);
  });

  testWidgets('History and Session agree on the same session', (tester) async {
    await tester.pumpWidget(_app(AnalyticsTab.session));
    await tester.pump(const Duration(milliseconds: 300));
    final onSessionTab = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == '20m')
        .length;

    await tester.pumpWidget(_app(AnalyticsTab.history));
    await tester.pump(const Duration(milliseconds: 300));
    final onHistoryTab = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .where((d) => d == '20m')
        .length;

    expect(onSessionTab, greaterThan(0));
    expect(onHistoryTab, greaterThan(0));
  });
}
