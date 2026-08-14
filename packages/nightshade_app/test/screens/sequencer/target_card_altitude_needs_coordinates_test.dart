// WE-SEQ-N2: the target card simultaneously said the coordinates were "Not
// set" AND plotted a full altitude curve for them — "Alt 44.7° / Airmass 1.42 /
// Rise 15:03 / Transit 21:06 / Set 03:08", the numbers for the 0h/+0°
// placeholder at latitude 45. An observation plan for a pointing nobody chose
// is worse than no plan: the operator schedules a night around a transit time
// that belongs to a random patch of Pisces.
//
// The desktop card is the one that shows the chart (mobile hides it), so this
// pins the desktop card at both coordinate states.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/framing/altitude_chart.dart';
import 'package:nightshade_app/screens/sequencer/widgets/target_header_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('no curve is plotted for a target still on the 0h/+0 default',
      (tester) async {
    await pumpAppScreen(
      tester,
      TargetHeaderCard(
        node: TargetHeaderNode(
          id: 'target',
          name: 'M31',
          targetName: 'M31',
          raHours: 0,
          decDegrees: 0,
        ),
        colors: NightshadeColors.dark,
      ),
      size: const Size(1200, 900),
    );
    await tester.pump();

    expect(
      find.byType(AltitudeChart),
      findsNothing,
      reason: 'a rise/transit/set plan was drawn for coordinates the same '
          'card calls "Not set"',
    );
    expect(
      find.textContaining('Set coordinates'),
      findsOneWidget,
      reason: 'the empty state has to say what would fill it',
    );
  });

  testWidgets('a real pointing still gets its altitude chart', (tester) async {
    await pumpAppScreen(
      tester,
      TargetHeaderCard(
        node: TargetHeaderNode(
          id: 'target',
          name: 'M31',
          targetName: 'M31',
          raHours: 0.712306,
          decDegrees: 41.26875,
        ),
        colors: NightshadeColors.dark,
      ),
      size: const Size(1200, 900),
    );
    await tester.pump();

    expect(find.byType(AltitudeChart), findsOneWidget);
  });
}
