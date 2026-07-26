import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
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

DbCapturedImage _image({
  required int id,
  required String type,
  required bool accepted,
  required double exposure,
  double? temperature,
  double? hfr,
  double? rms,
}) =>
    DbCapturedImage(
      id: id,
      filePath: '/tmp/$id.fits',
      fileName: '$id.fits',
      fileFormat: 'fits',
      frameType: type,
      exposureDuration: exposure,
      binX: 1,
      binY: 1,
      capturedAt: DateTime.utc(2026, 7, 14),
      createdAt: DateTime.utc(2026, 7, 14),
      isAccepted: accepted,
      isPlateSolved: false,
      sensorTemp: temperature,
      hfr: hfr,
      guidingRmsTotal: rms,
    );

ImagingSession _session(int id, int autofocusCount) => ImagingSession(
      id: id,
      startTime: DateTime.utc(2026, 7, 14),
      totalExposures: 0,
      successfulExposures: 0,
      failedExposures: 0,
      totalIntegrationSecs: 0,
      autofocusCount: autofocusCount,
      status: 'completed',
    );

Widget _app({
  required Stream<List<DbCapturedImage>> images,
  required Stream<List<ImagingSession>> sessions,
}) {
  return ProviderScope(
    overrides: [
      allDbImagesProvider.overrideWith((ref) => images),
      standaloneImagesProvider.overrideWith(
        (ref) => Stream.value(const <DbCapturedImage>[]),
      ),
      allSessionsProvider.overrideWith((ref) => sessions),
      tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
    ],
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: const Scaffold(
        body: AnalyticsScreen(initialTab: AnalyticsTab.equipment),
      ),
    ),
  );
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

  testWidgets('equipment metrics use truthful populations and short durations',
      (tester) async {
    await tester.pumpWidget(
      _app(
        images: Stream.value([
          _image(
            id: 1,
            type: 'light',
            accepted: true,
            exposure: 45,
            temperature: -10,
            hfr: 2,
            rms: 0.8,
          ),
          _image(
            id: 2,
            type: 'light',
            accepted: false,
            exposure: 120,
            temperature: -5,
            hfr: 10,
            rms: 4,
          ),
          _image(
            id: 3,
            type: 'flat',
            accepted: true,
            exposure: 2,
            temperature: 0,
          ),
        ]),
        sessions: Stream.value([_session(1, 2), _session(2, 3)]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Total Exposures'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Accepted Integration'), findsOneWidget);
    expect(find.text('45s'), findsOneWidget);
    expect(find.text('-5.0 °C'), findsOneWidget);
    expect(find.text('2.00'), findsOneWidget);
    expect(find.text('0.80"'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('session failures do not masquerade as zero autofocus runs',
      (tester) async {
    await tester.pumpWidget(
      _app(
        images: Stream.value(const <DbCapturedImage>[]),
        sessions: Stream.error(StateError('session database unavailable')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Session-based equipment totals are unavailable.'),
        findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
