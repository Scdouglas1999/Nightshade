// SEQ-15: the toolbar's "Slew to Target" fired a real, unconfirmed slew —
// during a run, and to targets below the horizon — with zero feedback. No
// dialog, no toast, no "Slewing" state, and `grep -ic slew` over the whole
// session log returned 0. The only way to discover the mount had moved was to
// open another screen and read the Equipment panel.
//
// These tests drive the real toolbar: the control must be locked while the
// executor owns the mount, and must ask before moving it when idle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_toolbar.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

Sequence _sequenceWithTarget() {
  final exposure = ExposureNode(
    id: 'exp',
    name: 'Lum',
    durationSecs: 15,
    count: 4,
    parentId: 'target',
  );
  final target = TargetHeaderNode(
    id: 'target',
    name: 'Target',
    targetName: 'M42-TEST',
    raHours: 12.0,
    decDegrees: -35.0,
    childIds: const ['exp'],
  );
  return Sequence.create(
    name: 'T',
    nodes: {target.id: target, exposure.id: exposure},
    rootNodeId: target.id,
  );
}

Future<void> _pumpToolbar(
  WidgetTester tester, {
  required SequenceExecutionState executionState,
}) async {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = _sequenceWithTarget();

  await pumpAppScreen(
    tester,
    Builder(
      builder: (context) =>
          SequenceToolbar(colors: NightshadeColors.of(context)),
    ),
    size: const Size(1600, 900),
    extraOverrides: [
      currentSequenceProvider.overrideWith((_) => notifier),
      sequenceExecutionStateProvider.overrideWith((ref) => executionState),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('locked while the sequence is running, like its neighbours',
      (tester) async {
    await _pumpToolbar(tester, executionState: SequenceExecutionState.running);

    expect(
      find.byTooltip('Slew to Target (locked while sequence is running)'),
      findsOneWidget,
    );
    expect(find.byTooltip('Slew to Target'), findsNothing);
  });

  testWidgets('when idle it asks before moving the mount', (tester) async {
    await _pumpToolbar(tester, executionState: SequenceExecutionState.idle);

    final action = find.byTooltip('Slew to Target');
    expect(action, findsOneWidget);

    await tester.tap(action);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Slew to M42-TEST?'), findsOneWidget);
    expect(find.text('The mount will move now.'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Slew now'), findsOneWidget);
  });
}
