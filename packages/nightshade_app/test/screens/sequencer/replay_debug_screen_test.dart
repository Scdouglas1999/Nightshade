import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/replay_debug_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// NEW-E3. The Replay header read **"1 of 2 decisions"** while exactly one row
/// rendered, with the `All` filter selected and the time-range slider at its
/// full extent (`Time range: 20:53:44 — 20:54:01`). Nothing on screen accounted
/// for the second decision: the scrub window was pinned to the run's
/// `started_at`/`ended_at`, so any decision written outside that window — the
/// completion decision persisted a beat after the run row was closed is the
/// common one — was unreachable at *every* slider position while still being
/// counted in the denominator.
///
/// The timestamps below are the live run's (20:53:44 start, 20:54:01 end) with
/// the second decision landing 120 ms past `ended_at`.
ReplayDecision _decision(
  int id,
  DateTime timestamp,
  String summary, {
  DecisionCategory category = DecisionCategory.unknown,
}) =>
    ReplayDecision(
      id: id,
      sequenceRunId: 7,
      timestamp: timestamp,
      category: category,
      summary: summary,
      details: const {},
    );

void main() {
  final startedAt = DateTime.utc(2026, 8, 13, 20, 53, 44);
  final endedAt = DateTime.utc(2026, 8, 13, 20, 54, 1);

  testWidgets('a decision written past ended_at is reachable and counted',
      (tester) async {
    final decisions = [
      _decision(1, startedAt, 'Sequence started'),
      _decision(2, endedAt.add(const Duration(milliseconds: 120)),
          'Sequence completed'),
    ];

    await pumpAppScreen(
      tester,
      ReplayDebugScreen(
        sequenceRunId: 7,
        sequenceName: 'New Sequence',
        startedAt: startedAt,
        endedAt: endedAt,
      ),
      size: const Size(1000, 800),
      settle: false,
      extraOverrides: [
        decisionsForRunProvider(7).overrideWith((ref) => Stream.value(
              decisions,
            )),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('2 of 2 decisions'), findsOneWidget);
    expect(find.textContaining('Sequence started'), findsOneWidget);
    expect(find.textContaining('Sequence completed'), findsOneWidget);
  });

  testWidgets('the visible count never exceeds what the list renders',
      (tester) async {
    final decisions = [
      for (var i = 0; i < 5; i++)
        _decision(
          i + 1,
          startedAt.add(Duration(seconds: i * 3)),
          'Decision $i',
        ),
    ];

    await pumpAppScreen(
      tester,
      ReplayDebugScreen(
        sequenceRunId: 7,
        sequenceName: 'New Sequence',
        startedAt: startedAt,
        endedAt: endedAt,
      ),
      size: const Size(1000, 800),
      settle: false,
      extraOverrides: [
        decisionsForRunProvider(7).overrideWith((ref) => Stream.value(
              decisions,
            )),
      ],
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('5 of 5 decisions'), findsOneWidget);
  });
}
