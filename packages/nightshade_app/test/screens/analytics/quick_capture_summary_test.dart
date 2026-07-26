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
  double? hfr,
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
      hfr: hfr,
    );

Widget _app(Stream<List<DbCapturedImage>> standalone) {
  return ProviderScope(
    overrides: [
      standaloneImagesProvider.overrideWith((ref) => standalone),
      allDbImagesProvider.overrideWith(
        (ref) => Stream.value(const <DbCapturedImage>[]),
      ),
      allSessionsProvider.overrideWith(
        (ref) => Stream.value(const <ImagingSession>[]),
      ),
      tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
    ],
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: const Scaffold(
        body: AnalyticsScreen(initialTab: AnalyticsTab.session),
      ),
    ),
  );
}

List<String> _summaryValues(WidgetTester tester) {
  final strip = tester.widget<ResponsiveStatStrip>(
    find.byType(ResponsiveStatStrip).first,
  );
  return strip.stats.map((stat) => stat.value).toList(growable: false);
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .physicalSize = const Size(1200, 900);
    TestWidgetsFlutterBinding
        .instance.platformDispatcher.views.first.devicePixelRatio = 1;
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetPhysicalSize();
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        .resetDevicePixelRatio();
  });

  testWidgets('quick capture summary reflects its actual standalone frames',
      (tester) async {
    await tester.pumpWidget(
      _app(Stream.value([
        _image(id: 1, type: 'light', accepted: true, exposure: 45, hfr: 2),
        _image(id: 2, type: 'light', accepted: false, exposure: 120, hfr: 10),
        _image(id: 3, type: 'flat', accepted: true, exposure: 2),
      ])),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Quick Capture'), findsOneWidget);
    expect(_summaryValues(tester), ['—', '3', '45s', '2.00']);
  });

  testWidgets('standalone image failures stay distinct from empty data',
      (tester) async {
    await tester.pumpWidget(
      _app(Stream.error(StateError('image catalog offline'))),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(_summaryValues(tester),
        ['—', 'Unavailable', 'Unavailable', 'Unavailable']);
    expect(find.textContaining('Failed to load images'), findsOneWidget);
  });
}
