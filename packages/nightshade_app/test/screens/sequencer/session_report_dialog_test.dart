// Smoke tests for the Feature-A session report dialog.
//
// We avoid spinning up the full backend / FFI stack by overriding the
// `sessionReportProvider.family` with a pre-built fake report. The dialog
// only reads from that provider, so this exercises the rendering path and
// the Markdown-copy action without touching any IO.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/session_report_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

SessionReport _fakeReport({
  String name = 'M42 night 1',
  List<SessionTargetReport>? targets,
  List<String> errors = const [],
}) {
  final t = targets ??
      [
        SessionTargetReport(
          targetId: 1,
          targetName: 'M42',
          filters: const [
            SessionFilterReport(
              filter: 'L',
              framesAttempted: 12,
              framesAccepted: 10,
              framesRejected: 2,
              totalIntegrationSecs: 600,
              meanHfr: 2.4,
              meanFwhm: 2.4 * 2.35,
              meanStarCount: 480,
              meanSnr: 21.5,
              meanGuidingRmsTotal: 0.62,
              meanSensorTemp: -10,
              rejectionReasons: {'High HFR': 2},
            ),
          ],
        ),
      ];
  return SessionReport(
    sessionId: 42,
    sessionName: name,
    status: 'completed',
    startTime: DateTime.utc(2026, 1, 1, 22),
    endTime: DateTime.utc(2026, 1, 2, 1),
    wallClockDuration: const Duration(hours: 3),
    totalIntegration: const Duration(minutes: 10),
    effectiveImagingFraction: 10 / 180,
    downtime: const Duration(hours: 2, minutes: 50),
    targets: t,
    guideStats: const SessionGuideStats(
      meanRmsRaArcsec: 0.5,
      meanRmsDecArcsec: 0.4,
      meanRmsTotalArcsec: 0.6,
      maxRmsRaArcsec: 0.9,
      maxRmsDecArcsec: 0.7,
      maxRmsTotalArcsec: 1.1,
      percentUnguidedFrames: 0.0,
    ),
    mountStats: const SessionMountStats(
      autofocusRuns: 2,
      meridianFlips: 1,
      ditherCount: 9,
      triggerFires: 1,
    ),
    avgTemperatureC: 5.0,
    avgHumidityPercent: 60.0,
    avgSeeingArcsec: 2.0,
    notes: null,
    errorMessages: errors,
    generatedAt: DateTime.utc(2026, 1, 2, 2),
  );
}

Future<void> _pump(WidgetTester tester, SessionReport report) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionReportProvider(report.sessionId).overrideWith(
          (ref) async => report,
        ),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => SessionReportDialog.show(ctx, report.sessionId),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders headline metrics and per-target table',
      (tester) async {
    await _pump(tester, _fakeReport());

    // Headline.
    expect(find.text('Session Report'), findsOneWidget);
    expect(find.textContaining('M42 night 1'), findsOneWidget);

    // Overview tiles.
    expect(find.text('Wall clock'), findsOneWidget);
    expect(find.text('Integration'), findsAtLeastNWidgets(1));
    expect(find.text('Effective imaging'), findsOneWidget);
    expect(find.text('Downtime'), findsOneWidget);
    expect(find.text('Frames accepted'), findsOneWidget);
    expect(find.text('Frames rejected'), findsOneWidget);

    // Sections.
    expect(find.text('Mount / operations'), findsOneWidget);
    expect(find.text('Guiding'), findsOneWidget);
    expect(find.text('Conditions'), findsOneWidget);
    expect(find.text('Targets'), findsOneWidget);

    // Per-target table — filter row present.
    expect(find.text('M42'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    // The rejection-rollup line is rendered.
    expect(find.textContaining('Rejections:'), findsOneWidget);
  });

  testWidgets('Copy as Markdown writes to the clipboard', (tester) async {
    final clipboardText = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final data = call.arguments as Map<dynamic, dynamic>;
        clipboardText.add(data['text'] as String);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await _pump(tester, _fakeReport());

    await tester.tap(find.byTooltip('Copy as Markdown'));
    await tester.pumpAndSettle();

    expect(clipboardText, hasLength(1));
    expect(clipboardText.single, contains('# Session Report: M42 night 1'));
    expect(clipboardText.single, contains('## Targets'));
    expect(clipboardText.single, contains('### M42'));
  });

  testWidgets('surfaces error messages section when present', (tester) async {
    await _pump(
      tester,
      _fakeReport(errors: const ['Guider lost star', 'Recovered']),
    );

    expect(find.text('Errors / warnings'), findsOneWidget);
    expect(find.text('Guider lost star'), findsOneWidget);
    expect(find.text('Recovered'), findsOneWidget);
  });
}
