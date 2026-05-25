import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/node_progress_panels.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('exposure progress panel prefers structured detail',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: getProgressPanelForNode(
          node: ExposureNode(
            filter: 'L',
            count: 99,
            durationSecs: 120,
          ),
          colors: NightshadeColors.dark,
          progressPercent: 40,
          progressDetail: '',
          structuredProgressDetail: const ExposureInstructionProgressDetail(
            frame: 4,
            total: 9,
            durationSecs: 210,
          ),
        ),
      ),
    ));

    expect(find.text('4 / 9 frames'), findsOneWidget);
    expect(find.text('210'), findsOneWidget);
  });

  testWidgets('exposure progress panel keeps legacy detail fallback',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: getProgressPanelForNode(
          node: ExposureNode(
            filter: 'L',
            count: 10,
            durationSecs: 120,
          ),
          colors: NightshadeColors.dark,
          progressPercent: 40,
          progressDetail: 'Frame 3/10',
        ),
      ),
    ));

    expect(find.text('3 / 10 frames'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
  });
}
