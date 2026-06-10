// Widget tests for ScienceStatusBanner. Verifies the three render states
// (idle, busy, error) it produces from a ScienceProcessingStatusTracker.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/widgets/science_status_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _harness({
  required Widget child,
  required ScienceProcessingStatusTracker tracker,
}) {
  return ProviderScope(
    overrides: [
      scienceProcessingStatusTrackerProvider.overrideWith((_) => tracker),
    ],
    child: MaterialApp(
      theme: ThemeData(
        extensions: const [NightshadeColors.dark],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides itself when idle and hideWhenIdle is set', (tester) async {
    final tracker = ScienceProcessingStatusTracker();
    addTearDown(tracker.dispose);

    await tester.pumpWidget(_harness(
      tracker: tracker,
      child: const ScienceStatusBanner(hideWhenIdle: true),
    ));
    await tester.pump();

    expect(find.byType(ScienceStatusBanner), findsOneWidget);
    expect(find.text('Science idle'), findsNothing);
    expect(find.byType(Container), findsNothing,
        reason:
            'Banner should collapse to SizedBox.shrink when idle + hide flag.');
  });

  testWidgets('renders the idle line when there is no work in flight',
      (tester) async {
    final tracker = ScienceProcessingStatusTracker();
    addTearDown(tracker.dispose);

    await tester.pumpWidget(_harness(
      tracker: tracker,
      child: const ScienceStatusBanner(),
    ));
    await tester.pump();

    expect(find.text('Science idle'), findsOneWidget);
    expect(find.text('Waiting for the first captured frame'), findsOneWidget);
  });

  testWidgets('renders a busy state with the running stage label',
      (tester) async {
    final tracker = ScienceProcessingStatusTracker();
    addTearDown(tracker.dispose);

    tracker.beginFrame(imagePath: '/tmp/img.fits');
    tracker.beginStage(ScienceStage.plateSolve);

    await tester.pumpWidget(_harness(
      tracker: tracker,
      child: const ScienceStatusBanner(),
    ));
    await tester.pump();

    expect(find.textContaining('Plate solve'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('surfaces a recent failure with the truncated note',
      (tester) async {
    final tracker = ScienceProcessingStatusTracker();
    addTearDown(tracker.dispose);

    tracker.beginFrame(imagePath: '/tmp/img.fits');
    tracker.beginStage(ScienceStage.calibration);
    tracker.endStage(ScienceStage.calibration, ScienceStageOutcome.failed,
        note: 'no WCS available');
    tracker.endFrame();

    await tester.pumpWidget(_harness(
      tracker: tracker,
      child: const ScienceStatusBanner(),
    ));
    await tester.pump();

    expect(find.textContaining('failed'), findsWidgets);
    expect(find.textContaining('no WCS'), findsOneWidget);
  });
}
