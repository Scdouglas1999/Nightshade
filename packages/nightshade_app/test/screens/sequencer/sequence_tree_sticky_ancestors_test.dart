// Sticky ancestors (spec §5): the target and loop a row belongs to stay on
// screen after their own rows have scrolled past the top of the viewport.
//
// Every case drives the real scroll view — the pins are computed from live
// render boxes, so a synthesized scroll offset would prove nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree/ledger_columns.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequencer_density.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

/// A viewport short enough that a target's own row leaves it after a modest
/// scroll, which is the whole condition the feature turns on.
const Size _shortCanvas = Size(1200, 300);

/// Root -> "M 42" -> "Broadband" -> 30 exposures: ~900 px of ledger rows in a
/// 300 px viewport, three levels deep.
Sequence _tallSequence() {
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
  final exposures = <ExposureNode>[
    for (var i = 0; i < 30; i++)
      ExposureNode(name: 'Sub $i', durationSecs: 60, count: 1)
          .copyWith(parentId: loop.id, orderIndex: i),
  ];
  return Sequence.create(
    name: 'Tall',
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
  );
}

Future<void> _pumpTree(
  WidgetTester tester,
  Sequence sequence, {
  SequencerDensity density = SequencerDensity.ledger,
  bool disableAnimations = false,
}) async {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = sequence;

  await pumpAppScreen(
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
    size: _shortCanvas,
    // Live validation debounces 500 ms; drain frames by hand instead.
    settle: false,
    extraOverrides: [
      currentSequenceProvider.overrideWith((_) => notifier),
      sequenceExecutionStateProvider
          .overrideWith((ref) => SequenceExecutionState.idle),
      // The minute clock is a real periodic stream whose timer outlives every
      // pump in the fake-async zone.
      ledgerClockProvider.overrideWith((ref) => const Stream<DateTime>.empty()),
      sequencerDensityProvider.overrideWith((ref) => density),
    ],
  );
  await _drain(tester);
}

/// Drain the validation debounce, the scroll's ballistic phase and the
/// post-frame sticky pass in one go.
///
/// The leading zero-length pump matters: an `ensureVisible` started by the
/// frame before this one has not ticked yet, and its controller takes its
/// start time from its FIRST tick — jumping the clock a second without that
/// tick leaves the animation at zero and the tree exactly where it was.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  // A pin created by the previous frame's post-frame pass takes its first tick
  // in the frame above; this is the one that carries its entrance to the end.
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _scrollBy(WidgetTester tester, double dy) async {
  await tester.drag(find.byType(Scrollable).first, Offset(0, dy));
  await _drain(tester);
}

Finder _pinnedStack() => find.byKey(sequenceStickyAncestorsKey);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nothing pins until an ancestor row scrolls out of view',
      (tester) async {
    await _pumpTree(tester, _tallSequence());

    expect(_pinnedStack(), findsNothing);
    expect(find.text('M 42'), findsOneWidget);
  });

  testWidgets('scrolling past the target pins it, and scrolling back unpins it',
      (tester) async {
    await _pumpTree(tester, _tallSequence());

    await _scrollBy(tester, -400);
    expect(_pinnedStack(), findsOneWidget);
    expect(
      find.descendant(of: _pinnedStack(), matching: find.text('M 42')),
      findsOneWidget,
      reason: 'the operator must still be able to see which target these '
          'subs belong to',
    );
    expect(
      find.descendant(of: _pinnedStack(), matching: find.text('Broadband')),
      findsOneWidget,
      reason: 'the loop is an ancestor too, and pins under the target',
    );
    expect(
      tester.getTopLeft(_pinnedStack()).dy,
      tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
      reason: 'the entrance slide has to end flush with the viewport top, not '
          '6 px above it',
    );

    await _scrollBy(tester, 400);
    expect(_pinnedStack(), findsNothing);
  });

  testWidgets('a pinned row is out of the accessibility traversal order',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpTree(tester, _tallSequence());
    await _scrollBy(tester, -400);

    expect(_pinnedStack(), findsOneWidget);
    // The tree announces the target exactly once — through its real row, which
    // is scrolled away but still mounted. The pin adds no second node, or a
    // reader would hear every ancestor twice.
    expect(find.bySemanticsLabel(RegExp('M 42')), findsOneWidget);
    expect(
      find.descendant(
        of: _pinnedStack(),
        matching: find.bySemanticsLabel(RegExp('M 42')),
      ),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('tapping a pinned row brings its real row back to the top',
      (tester) async {
    await _pumpTree(tester, _tallSequence());
    await _scrollBy(tester, -400);
    expect(_pinnedStack(), findsOneWidget);

    await tester.tap(
      find.descendant(of: _pinnedStack(), matching: find.text('M 42')),
      // The pinned row is deliberately behind an IgnorePointer — the tap
      // belongs to the stack around it, which is what receives this.
      warnIfMissed: false,
    );
    await _drain(tester);

    expect(
      _pinnedStack(),
      findsNothing,
      reason: 'the real row is back on screen, so nothing stands in for it',
    );
    final viewportTop =
        tester.getTopLeft(find.byType(SingleChildScrollView)).dy;
    expect(
      tester.getTopLeft(find.text('M 42')).dy,
      greaterThanOrEqualTo(viewportTop),
    );
  });

  testWidgets('compact density pins a single-line ancestor row',
      (tester) async {
    await _pumpTree(
      tester,
      _tallSequence(),
      density: SequencerDensity.compact,
    );

    // Compact keeps the cards, and the target's card is several hundred pixels
    // tall, so it takes a longer scroll to clear the viewport than a 28 px
    // ledger row does.
    await _scrollBy(tester, -900);
    expect(_pinnedStack(), findsOneWidget);
    expect(
      find.descendant(of: _pinnedStack(), matching: find.text('Orion')),
      findsOneWidget,
      reason: 'the pin names the target its card names',
    );
  });

  testWidgets('comfortable density never pins', (tester) async {
    await _pumpTree(
      tester,
      _tallSequence(),
      density: SequencerDensity.comfortable,
    );

    await _scrollBy(tester, -900);
    expect(_pinnedStack(), findsNothing);
  });

  testWidgets('the pinned stack builds with animations disabled',
      (tester) async {
    await _pumpTree(tester, _tallSequence(), disableAnimations: true);

    await _scrollBy(tester, -400);
    expect(_pinnedStack(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
