// The sequencer tree's motion (spec §9).
//
// Two things are worth testing about an animation and neither is what it looks
// like. The first is that it is not there at all when the platform has asked
// for no motion — a transition that "only" runs for 120 ms is still motion on
// screen, and the failure mode is silent. The second is the structure the
// motion depends on: a repeating animation lives inside an
// `OnScreenAnimationGate`, and the gate decides whether to keep running by
// watching whether its child PAINTS — so a `RepaintBoundary` on the wrong side
// of it stops the animation two ticks in and nothing says so.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree/ledger_columns.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequencer_density.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

/// Flipped at runtime so a single tree can be driven through a density change
/// without rebuilding the ProviderScope under it.
final _testDensityProvider =
    StateProvider<SequencerDensity>((ref) => SequencerDensity.ledger);

/// The dashed line an inter-row drop zone shows while a drag is in flight, and
/// the heights the zone animates between. Mirrors the tree's own constants.
const ValueKey<String> _dropZoneDashes = ValueKey<String>('drop-zone-dashes');
const double _dropZoneActiveHeight = 28.0;

/// The ledger row's own height, as the tree's private constant fixes it.
const double _ledgerRowHeight = 28.0;

/// Root -> "M 42" -> "Broadband" -> subs of differing length.
///
/// The lengths differ on purpose: exposures that share a capture spec fold
/// into ONE row in Ledger (spec §6), and a container whose children are a
/// single folded row proves very little about collapsing it.
({Sequence sequence, String loopId, String targetId, List<String> subIds})
    _tree({int subs = 4}) {
  final target = TargetHeaderNode(
    name: 'M 42',
    targetName: 'Orion',
    raHours: 5.5,
    decDegrees: -5.4,
  );
  final loop = LoopNode(
    name: 'Broadband',
    conditionType: LoopConditionType.count,
    repeatCount: 1,
  );
  final root = InstructionSetNode(name: 'Root');
  final exposures = <SequenceNode>[
    for (var i = 0; i < subs; i++)
      ExposureNode(name: 'Sub $i', durationSecs: 60.0 + i, count: 1)
          .copyWith(parentId: loop.id, orderIndex: i),
  ];
  return (
    sequence: Sequence.create(
      name: 'Motion',
      rootNodeId: root.id,
      nodes: {
        for (final exposure in exposures) exposure.id: exposure,
        loop.id: loop.copyWith(
          parentId: target.id,
          orderIndex: 0,
          childIds: [for (final exposure in exposures) exposure.id],
        ),
        target.id: target.copyWith(
          parentId: root.id,
          orderIndex: 0,
          childIds: [loop.id],
        ),
        root.id: root.copyWith(childIds: [target.id]),
      },
    ),
    loopId: loop.id,
    targetId: target.id,
    subIds: [for (final exposure in exposures) exposure.id],
  );
}

Future<HarnessHandle> _pumpTree(
  WidgetTester tester, {
  required Sequence sequence,
  bool disableAnimations = false,
  Size size = const Size(1200, 900),
  SequenceProgressNotifier? progress,
  SequenceExecutionState executionState = SequenceExecutionState.idle,
}) async {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = sequence;

  final handle = await pumpAppScreen(
    tester,
    Builder(
      builder: (context) {
        final tree = SequenceTree(colors: NightshadeColors.of(context));
        if (!disableAnimations) return tree;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: tree,
        );
      },
    ),
    size: size,
    // Live validation debounces 500 ms; drain frames by hand instead.
    settle: false,
    extraOverrides: [
      currentSequenceProvider.overrideWith((_) => notifier),
      sequenceExecutionStateProvider.overrideWith((ref) => executionState),
      // The minute clock is a real periodic stream; in the fake-async zone its
      // timer outlives every pump and fails teardown.
      ledgerClockProvider.overrideWith((ref) => const Stream<DateTime>.empty()),
      if (progress != null)
        sequenceProgressProvider.overrideWith((_) => progress),
      sequencerDensityProvider
          .overrideWith((ref) => ref.watch(_testDensityProvider)),
    ],
  );
  await tester.pump();
  await tester.pump();
  expect(tester.takeException(), isNull);
  return handle;
}

/// Live validation runs on a 500 ms debounce; without a drain the binding
/// fails the test on a pending timer at teardown.
Future<void> _drainValidationDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
}

/// The chevron on a named container row.
Finder _chevronOf(String name) => find.ancestor(
      of: find.text(name),
      matching: find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == _ledgerRowHeight,
      ),
    );

Future<void> _toggleCollapse(WidgetTester tester, String rowName) async {
  await tester.tap(
    find
        .descendant(
          of: _chevronOf(rowName).last,
          matching: find.byIcon(LucideIcons.chevronDown),
        )
        .first,
  );
}

/// The number of live animation tickers in the tree.
///
/// Zero after a single pump is what "this transition has no duration" means in
/// a way a test can see — an assertion on a widget's opacity would pass just as
/// happily against an animation that is merely very fast.
int _runningAnimations(WidgetTester tester) =>
    tester.binding.transientCallbackCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with animations disabled', () {
    testWidgets('a collapse lands whole in a single pump', (tester) async {
      final built = _tree();
      await _pumpTree(
        tester,
        sequence: built.sequence,
        disableAnimations: true,
      );
      expect(find.text('Sub 0'), findsOneWidget);
      expect(_runningAnimations(tester), 0, reason: 'precondition');

      await _toggleCollapse(tester, 'Broadband');
      await tester.pump();

      expect(find.text('Sub 0'), findsNothing);
      expect(_runningAnimations(tester), 0);

      await _toggleCollapse(tester, 'Broadband');
      await tester.pump();

      expect(find.text('Sub 0'), findsOneWidget);
      expect(_runningAnimations(tester), 0);
      await _drainValidationDebounce(tester);
    });

    testWidgets('a density switch lands whole in a single pump',
        (tester) async {
      final built = _tree();
      final handle = await _pumpTree(
        tester,
        sequence: built.sequence,
        disableAnimations: true,
      );

      // Ledger draws every node as a 28 px line with four readout columns;
      // Comfortable draws the target as a card. One pump has to be the whole
      // journey.
      expect(find.text('Filter / exp'), findsOneWidget);
      handle.container.read(_testDensityProvider.notifier).state =
          SequencerDensity.comfortable;
      await tester.pump();

      expect(find.text('Filter / exp'), findsNothing);
      // A cross-fade in flight has BOTH row sets mounted, so a step's name is
      // on screen twice for the length of it. One is the end state.
      //
      // (A ticker count would be the sharper probe here as it is elsewhere in
      // this group, but Comfortable mounts widgets this workstream does not own
      // and one of them keeps a ticker registered without ever asking for a
      // frame — counting here would be asserting about them.)
      expect(find.text('Sub 0'), findsOneWidget);
      await _drainValidationDebounce(tester);
    });

    testWidgets('hovering a row lands whole in a single pump', (tester) async {
      final built = _tree();
      await _pumpTree(
        tester,
        sequence: built.sequence,
        disableAnimations: true,
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Sub 0')));
      await tester.pump();

      expect(_runningAnimations(tester), 0);
      await _drainValidationDebounce(tester);
    });

    testWidgets('the row fill has no duration at all', (tester) async {
      final built = _tree();
      await _pumpTree(
        tester,
        sequence: built.sequence,
        disableAnimations: true,
      );

      final shell = find.ancestor(
        of: find.text('Sub 0'),
        matching: find.byType(AnimatedContainer),
      );
      expect(
        tester.widget<AnimatedContainer>(shell.first).duration,
        Duration.zero,
      );
      await _drainValidationDebounce(tester);
    });
    testWidgets('the running row breathes not at all', (tester) async {
      final built = _tree();
      final progress = SequenceProgressNotifier();
      await _pumpTree(
        tester,
        sequence: built.sequence,
        disableAnimations: true,
        progress: progress,
        executionState: SequenceExecutionState.running,
      );

      progress.updateNodeStatus(built.subIds.first, NodeStatus.running);
      progress.updateNodeProgress(built.subIds.first, 40, '');
      await tester.pump();

      expect(
        find.byType(OnScreenAnimationGate),
        findsNothing,
        reason: 'a repeat cannot be shortened to nothing, so it never starts',
      );
      expect(_runningAnimations(tester), 0);
      await _drainValidationDebounce(tester);
    });
  });

  group('with animations enabled', () {
    testWidgets('a collapse clips its children away without overflowing',
        (tester) async {
      final built = _tree();
      await _pumpTree(tester, sequence: built.sequence);

      await _toggleCollapse(tester, 'Broadband');
      await tester.pump();
      expect(
        find.text('Sub 0'),
        findsOneWidget,
        reason: 'the rows leave over the token, not between two frames',
      );

      await tester.pumpAndSettle();
      expect(find.text('Sub 0'), findsNothing);
      expect(
        tester.takeException(),
        isNull,
        reason: 'the block is clipped, never laid out at an in-between size',
      );
      await _drainValidationDebounce(tester);
    });

    testWidgets('collapsing does not move the rows above it', (tester) async {
      final built = _tree();
      await _pumpTree(tester, sequence: built.sequence);

      final before = tester.getRect(find.text('M 42'));
      await _toggleCollapse(tester, 'Broadband');
      // Mid-flight is where a bottom-aligned shrink would show: the block
      // closing upwards drags everything above it with it.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(find.text('M 42')), before);

      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('M 42')), before);
      await _drainValidationDebounce(tester);
    });

    testWidgets(
        'the running marker breathes inside a gate, with the '
        'RepaintBoundary OUTSIDE it', (tester) async {
      final built = _tree();
      final progress = SequenceProgressNotifier();
      await _pumpTree(
        tester,
        sequence: built.sequence,
        progress: progress,
        executionState: SequenceExecutionState.running,
      );

      progress.updateNodeStatus(built.subIds.first, NodeStatus.running);
      await tester.pump();

      final gate = find.byType(OnScreenAnimationGate);
      expect(gate, findsOneWidget);

      // The boundary must be the gate's PARENT, not something inside it. A
      // boundary within the gate makes the marker its own compositing layer,
      // the marker's repaints stop reaching the gate's paint observer, and the
      // gate concludes the animation is invisible and stops it — silently.
      Element? parent;
      tester.element(gate).visitAncestorElements((element) {
        parent = element;
        return false;
      });
      expect(parent!.widget, isA<RepaintBoundary>());
      expect(
        find.descendant(of: gate, matching: find.byType(RepaintBoundary)),
        findsNothing,
      );

      // And it is actually running: the breath is the one loop in the tree, so
      // if the order were wrong this is the assertion that would notice.
      double opacityOf(Finder gate) => tester
          .widget<Opacity>(
              find.descendant(of: gate, matching: find.byType(Opacity)).first)
          .opacity;
      final first = opacityOf(gate);
      await tester.pump(const Duration(milliseconds: 500));
      expect(opacityOf(gate), isNot(first));

      progress.updateNodeStatus(built.subIds.first, NodeStatus.success);
      await tester.pumpAndSettle();
      expect(
        find.byType(OnScreenAnimationGate),
        findsNothing,
        reason: 'nothing loops once the run has left the row',
      );
      await _drainValidationDebounce(tester);
    });

    testWidgets('drop zones grow to their active height when a drag starts',
        (tester) async {
      final built = _tree();
      await _pumpTree(tester, sequence: built.sequence);

      expect(
        find.byKey(_dropZoneDashes),
        findsNothing,
        reason: 'at rest a zone has no height and nothing in it',
      );

      // A stationary press arms the long-press drag; `timedDrag` moves inside
      // the 150 ms window and the drag never arms.
      final start = tester.getCenter(find.text('Sub 0'));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(start + const Offset(0, 8));

      await tester.pump(const Duration(milliseconds: 16));
      final growing = tester.getSize(find.byKey(_dropZoneDashes).first).height;
      expect(
        growing,
        lessThan(_dropZoneActiveHeight),
        reason: 'the zones grow into place rather than appearing at full size',
      );

      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(_dropZoneDashes).first).height,
        _dropZoneActiveHeight,
      );

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(_dropZoneDashes), findsNothing);
      await _drainValidationDebounce(tester);
    });

    testWidgets('a density switch cross-fades both row sets', (tester) async {
      final built = _tree();
      final handle = await _pumpTree(tester, sequence: built.sequence);

      handle.container.read(_testDensityProvider.notifier).state =
          SequencerDensity.comfortable;
      await tester.pump();

      // Mid-fade both row sets are mounted — which is what makes the
      // single-pump assertion in the disabled group above mean something.
      expect(find.text('Sub 0'), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(find.text('Sub 0'), findsOneWidget);
      await _drainValidationDebounce(tester);
    });

    testWidgets('hover and selection travel on the short token',
        (tester) async {
      final built = _tree();
      await _pumpTree(tester, sequence: built.sequence);

      final shell = find.ancestor(
        of: find.text('Sub 0'),
        matching: find.byType(AnimatedContainer),
      );
      expect(
        tester.widget<AnimatedContainer>(shell.first).duration,
        NightshadeTokens.durationFast,
        reason: 'the fill and the selection ring are one animation, and it is '
            'the shortest token there is',
      );
      await _drainValidationDebounce(tester);
    });
  });
}
