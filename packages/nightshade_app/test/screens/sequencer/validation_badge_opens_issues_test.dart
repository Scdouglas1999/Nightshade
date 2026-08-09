// The header's red/amber count badges must be readable without arming a run.
//
// They were plain Containers: clicking did nothing, the builder has no issues
// panel, and the only way to learn what "1 error" meant was to press Start and
// read the pre-flight dialog. That is a real hazard at 2am - "press the button
// that starts the rig" is not an acceptable way to ask "what's wrong?".
//
// The assertions below deliberately read the LIVE validation state and then
// require the dialog to show every issue in it, rather than hard-coding rule
// text: the property under test is "the badge opens the same issue list",
// not "this particular rule fires".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_issues_dialog.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping the validation badge opens the issue list',
      (tester) async {
    // A target still carrying the (0h, +0deg) placeholder: a real rule fires
    // on it AND names the offending node, so both halves of the fix are
    // exercised.
    final target = TargetHeaderNode(
      targetName: 'Unset target',
      raHours: 0,
      decDegrees: 0,
    );
    final root = InstructionSetNode(name: 'Root');
    final editor = CurrentSequenceNotifier();
    // ignore: invalid_use_of_protected_member
    editor.state = Sequence.create(
      name: 'Tonight',
      nodes: {
        target.id: target.copyWith(parentId: root.id),
        root.id: root.copyWith(childIds: [target.id]),
      },
      rootNodeId: root.id,
    );

    final handle = await pumpAppScreen(
      tester,
      Builder(
        builder: (context) =>
            SequenceTree(colors: NightshadeColors.of(context)),
      ),
      size: const Size(1000, 800),
      extraOverrides: [
        currentSequenceProvider.overrideWith((_) => editor),
        sequenceExecutionStateProvider
            .overrideWith((ref) => SequenceExecutionState.idle),
      ],
      settle: false,
    );
    // Live validation is debounced 500 ms.
    await tester.pump(const Duration(milliseconds: 800));

    final issues = handle.container.read(liveValidationProvider).issues;
    expect(issues, isNotEmpty, reason: 'no issues to surface');
    final nodeIssue = issues.firstWhere((i) => i.affectedNodeId != null);

    await tester.tap(find.byTooltip('Show sequence issues'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(SequenceIssuesDialog), findsOneWidget);
    for (final issue in issues) {
      expect(
        find.text(issue.title),
        findsOneWidget,
        reason: '"${issue.title}" is counted in the badge but not listed',
      );
    }

    // An issue that names a node jumps to it.
    await tester.tap(find.text(nodeIssue.title));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SequenceIssuesDialog), findsNothing);
    expect(
      handle.container.read(selectedNodeIdProvider),
      nodeIssue.affectedNodeId,
    );
  });
}
