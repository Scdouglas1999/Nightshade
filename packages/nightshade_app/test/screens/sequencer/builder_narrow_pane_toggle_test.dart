// WE-SEQ-N7: at ~900px the desktop builder auto-collapses its side panes so the
// canvas keeps a workable width (that part is the WD-SEQ-N2 fix and is right).
// What was wrong is that the collapse could not be overruled: the effective
// state was `userPref || derived`, so clicking the toolbox icon three times and
// the properties icon once left the tree with no palette and no Target
// Settings. The window could be read but not edited, and the only escape was
// resizing the window.
//
// A derived layout decision is a default. The operator's explicit tap is an
// instruction, and has to win.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/sequencer_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/pump_app_screen.dart';

Sequence _seedSequence() {
  final exposure = ExposureNode(name: 'Lum', durationSecs: 120, count: 10);
  final root = InstructionSetNode(name: 'Root');
  return Sequence.create(
    name: 'Narrow builder',
    rootNodeId: root.id,
    nodes: {
      exposure.id: exposure.copyWith(parentId: root.id),
      root.id: root.copyWith(childIds: [exposure.id]),
    },
  );
}

List<Override> _overrides() {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = _seedSequence();
  return [
    currentSequenceProvider.overrideWith((_) => notifier),
    sequenceExecutionStateProvider
        .overrideWith((ref) => SequenceExecutionState.idle),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The band where BOTH panes derive collapsed: the builder region is narrow
  // enough that even collapsing the toolbox leaves the canvas under its
  // comfortable width. A 900px WINDOW lands here once the nav rail and page
  // padding are taken out, which is what the live repro used; the test pumps
  // the screen at the region width directly so it does not depend on the shell.
  const narrowBuilder = Size(690, 900);

  testWidgets('both auto-collapsed panes can still be opened', (tester) async {
    await pumpAppScreen(
      tester,
      const SequencerScreen(),
      size: narrowBuilder,
      extraOverrides: _overrides(),
    );
    await tester.pumpAndSettle();

    // Precondition: the layout derived a collapse for BOTH panes (each is a
    // rail with a "Show …" affordance). If this stops holding, the width band
    // moved and the rest of the test is meaningless.
    expect(
      find.byTooltip('Show Toolbox'),
      findsOneWidget,
      reason: 'expected the derived collapse here; the width band moved',
    );
    expect(find.byTooltip('Show Properties'), findsOneWidget);

    await tester.tap(find.byTooltip('Show Toolbox'));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Show Toolbox'),
      findsNothing,
      reason: 'one tap on the toolbox icon left the pane exactly as it was',
    );

    await tester.tap(find.byTooltip('Show Properties'));
    await tester.pumpAndSettle();
    expect(
      find.byTooltip('Show Properties'),
      findsNothing,
      reason: 'one tap on the properties icon left the pane exactly as it was',
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a force-opened pane can be collapsed again', (tester) async {
    await pumpAppScreen(
      tester,
      const SequencerScreen(),
      size: narrowBuilder,
      extraOverrides: _overrides(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Show Toolbox'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show Toolbox'), findsNothing);

    // The panel header's own collapse control puts it back, and the override
    // must not immediately re-open it.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SequencerScreen)),
    );
    container.read(sequencerToolboxCollapsedProvider.notifier).state = true;
    container.read(sequencerToolboxForceOpenProvider.notifier).state = false;
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show Toolbox'), findsOneWidget);
  });
}
