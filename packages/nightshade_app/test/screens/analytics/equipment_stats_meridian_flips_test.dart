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

SequenceRun _run(int id, String statsJson) => SequenceRun(
      id: id,
      sequenceId: 1,
      sequenceName: 'Veil',
      startedAt: DateTime.utc(2026, 8, 1, 21),
      status: 'completed',
      statsJson: statsJson,
    );

Widget _app(List<SequenceRun> runs) => ProviderScope(
      overrides: [
        allDbImagesProvider
            .overrideWith((ref) => Stream.value(const <DbCapturedImage>[])),
        standaloneImagesProvider
            .overrideWith((ref) => Stream.value(const <DbCapturedImage>[])),
        allSessionsProvider
            .overrideWith((ref) => Stream.value(const <ImagingSession>[])),
        sequenceRunsProvider.overrideWith((ref) => Stream.value(runs)),
        tutorialProvider.overrideWith((ref) => _TutorialsDisabledNotifier()),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(
          body: AnalyticsScreen(initialTab: AnalyticsTab.equipment),
        ),
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

  testWidgets('Meridian Flips totals the count the runs recorded',
      (tester) async {
    await tester.pumpWidget(_app([
      _run(1, '{"meridianFlips": 2, "framesCaptured": 40}'),
      _run(2, '{"meridianFlips": 1, "framesCaptured": 12}'),
      // Older and corrupt stats must not invent a flip or take the tab down.
      _run(3, '{}'),
      _run(4, 'not json'),
    ]));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Meridian Flips'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    for (final label in [
      'Total Slews',
      'Total Tracking Time',
      'Total Movements',
      'Total Guide Time',
      'Star Lost Events',
    ]) {
      expect(find.text(label), findsNothing);
    }
    expect(find.text('Not tracked'), findsNothing);
  });

  testWidgets('a night with no flips reads zero, not "Not tracked"',
      (tester) async {
    await tester.pumpWidget(_app([_run(1, '{"meridianFlips": 0}')]));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('0'), findsWidgets);
  });
}
