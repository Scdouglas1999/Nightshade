// Exposure triggers are stored ON exposure nodes. The toolbar's bell opened
// the configuration dialog regardless, so on a sequence with no exposure node
// a user could add "Guiding RMS > 2" -> Abort", press Save, get a success
// snackbar — and keep nothing, because the write loop had no nodes to write
// to. Reopening the dialog showed "No triggers configured".
//
// These tests drive the real toolbar: the action must be disabled with the
// reason visible when there is nowhere to store a trigger, and must actually
// persist onto the exposure node when there is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_toolbar.dart';
import 'package:nightshade_app/screens/sequencer/widgets/trigger_configuration_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

Sequence _sequence({required bool withExposure}) {
  final root = InstructionSetNode(name: 'Sequence');
  final nodes = <String, SequenceNode>{};
  if (withExposure) {
    final exposure = ExposureNode(name: 'Lum', durationSecs: 60, count: 5);
    nodes[exposure.id] = exposure.copyWith(parentId: root.id);
    nodes[root.id] = root.copyWith(childIds: [exposure.id]);
  } else {
    nodes[root.id] = root;
  }
  return Sequence.create(name: 'T', nodes: nodes, rootNodeId: root.id);
}

Future<HarnessHandle> _pumpToolbar(
  WidgetTester tester, {
  required bool withExposure,
}) async {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = _sequence(withExposure: withExposure);

  return pumpAppScreen(
    tester,
    Builder(
      builder: (context) => SequenceToolbar(
        colors: NightshadeColors.of(context),
      ),
    ),
    size: const Size(1600, 900),
    extraOverrides: [
      currentSequenceProvider.overrideWith((_) => notifier),
      sequenceExecutionStateProvider
          .overrideWith((ref) => SequenceExecutionState.idle),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'with no exposure node the action is disabled and says why',
    (tester) async {
      await _pumpToolbar(tester, withExposure: false);

      final action = find.byTooltip(
        'Exposure Triggers (add an exposure node first)',
      );
      expect(action, findsOneWidget);

      // Disabled, not merely labelled: tapping must not open the dialog.
      await tester.tap(action, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TriggerConfigurationDialog), findsNothing);
    },
  );

  testWidgets(
    'with an exposure node the dialog opens, names its owner, and Save '
    'actually writes the trigger onto that node',
    (tester) async {
      final handle = await _pumpToolbar(tester, withExposure: true);

      await tester.tap(find.byTooltip('Exposure Triggers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TriggerConfigurationDialog), findsOneWidget);
      // The dialog states what it is editing.
      expect(
        find.text('Applies to the exposure node "Lum".'),
        findsOneWidget,
      );

      await tester.tap(find.text('Add Trigger'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final exposure = handle.container
          .read(currentSequenceProvider)!
          .nodes
          .values
          .whereType<ExposureNode>()
          .single;
      expect(
        exposure.triggers,
        isNotEmpty,
        reason: 'Save must land on the node that runs the trigger',
      );
    },
  );
}
