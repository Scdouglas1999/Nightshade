// WE-SEQ-N4: the Dashboard's "Last night" card printed the raw state-machine
// token — "New Sequence / Paused-stopped · 1 hour ago". SEQ-6 replaced that
// vocabulary everywhere Wave D looked (History chips, the Session Report title
// "Stopped (resumable)"), but this card carried its OWN status→copy mapping
// whose default arm just capitalised the token. Same defect shape as
// WD-SEQ-N4's `_statusLabel` in target_score_row.dart: two implementations of
// one label, and the fixed one is not the one on screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/standby/last_night_recap_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _app(List<SequenceRun> runs) => ProviderScope(
      overrides: [
        sequenceRunsProvider.overrideWith((ref) => Stream.value(runs)),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: const LastNightRecapCard(colors: NightshadeColors.dark),
        ),
      ),
    );

SequenceRun _run(String status) => SequenceRun(
      id: 1,
      sequenceName: 'New Sequence',
      startedAt: DateTime.now().subtract(const Duration(hours: 1)),
      endedAt: DateTime.now(),
      status: status,
      statsJson: '',
    );

void main() {
  testWidgets('a stopped run is not reported as "Paused-stopped"',
      (tester) async {
    await tester.pumpWidget(_app([_run('paused-stopped')]));
    await tester.pump();

    expect(find.textContaining('Paused-stopped'), findsNothing);
    expect(find.textContaining('Stopped (resumable)'), findsOneWidget);
  });

  testWidgets('an unmapped status still degrades to something readable',
      (tester) async {
    await tester.pumpWidget(_app([_run('cleanup_failed')]));
    await tester.pump();

    expect(find.textContaining('Cleanup failed'), findsOneWidget);
  });
}
