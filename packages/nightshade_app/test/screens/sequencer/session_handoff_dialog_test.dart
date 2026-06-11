// Widget tests for the session-handoff carry-over dialog.
//
// We exercise rendering and the basic decision-pick path. The dialog
// reads carry-over data from its constructor arg, so we don't need
// to spin up the DAO stack — just hand it a fixture list.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/session_handoff_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

SessionCarryOver _fake(int id, String name) {
  return SessionCarryOver(
    targetId: id,
    targetName: name,
    previousSessionId: 99,
    previousSessionStartedAt: DateTime(2026, 5, 17, 22),
    previousAcceptedFrames: 50,
    previousIntegrationSecs: 15000,
    campaignIntegrationSecs: 21600,
    budgetSecs: 43200,
    perFilterIntegrationSecs: const {'l': 10800, 'ha': 10800},
  );
}

Widget _harness(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(
        extensions: const [NightshadeColors.dark],
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders carry-over rows and default Resume decision',
      (tester) async {
    final co = _fake(1, 'M31');
    Map<int, SessionHandoffDecision>? captured;
    await tester.pumpWidget(_harness(
      SessionHandoffDialog(
        sequenceId: 7,
        carryOvers: [co],
        onDecisionsChosen: (m) => captured = m,
      ),
    ));
    await tester.pump();

    // Header
    expect(find.text('Resume from previous night?'), findsOneWidget);

    // Per-target tile shows the target name and the campaign total.
    expect(find.text('M31'), findsOneWidget);

    // Decision chips. The bulk row at the top of the dialog uses
    // "Resume all" / "Restart all" / "Continue new" labels (note the
    // asymmetry — Continue new has no "all" suffix), and each
    // per-target row repeats the bare "Resume" / "Restart" /
    // "Continue new" chip labels. So "Resume" and "Restart" appear
    // exactly once, but "Continue new" appears twice (once in the bulk
    // row, once in the per-target chip).
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(find.text('Continue new'), findsNWidgets(2));

    // Confirm with default selection (Resume).
    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured![1], SessionHandoffDecision.resume);
  });

  testWidgets('switching to Restart updates the decision map', (tester) async {
    final co = _fake(2, 'M42');
    Map<int, SessionHandoffDecision>? captured;
    await tester.pumpWidget(_harness(
      SessionHandoffDialog(
        sequenceId: 7,
        carryOvers: [co],
        onDecisionsChosen: (m) => captured = m,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Restart'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(captured, isNotNull);
    expect(captured![2], SessionHandoffDecision.restart);
  });

  testWidgets('"Restart all" bulk button propagates to every target',
      (tester) async {
    final cos = [_fake(1, 'M31'), _fake(2, 'M42')];
    Map<int, SessionHandoffDecision>? captured;
    await tester.pumpWidget(_harness(
      SessionHandoffDialog(
        sequenceId: 7,
        carryOvers: cos,
        onDecisionsChosen: (m) => captured = m,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Restart all'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pump();

    expect(captured![1], SessionHandoffDecision.restart);
    expect(captured![2], SessionHandoffDecision.restart);
  });
}
