// The Ledger gutter map (spec §7): an always-on overview column at the right
// edge of the tree, in place of the toggled 80 px strip below it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_minimap.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequence_tree/ledger_columns.dart';
import 'package:nightshade_app/screens/sequencer/widgets/sequencer_density.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

const Size _canvas = Size(1200, 300);

/// Root -> "M 42" -> "Broadband" -> [subs]. Tall enough that the tree scrolls,
/// which is what gives the gutter a viewport rectangle to move.
///
/// Every sub is a different length on purpose: exposures that share a capture
/// spec are a RUN, and in Ledger a run is one folded row (spec §6), so
/// identical subs would give the gutter three rows to map instead of
/// twenty-two — and a tree that fits its viewport has nothing to scroll, which
/// is the one condition every case here needs.
({Sequence sequence, List<String> exposureIds}) _tallSequence() {
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
    for (var i = 0; i < 20; i++)
      ExposureNode(name: 'Sub $i', durationSecs: 60.0 + i, count: 1)
          .copyWith(parentId: loop.id, orderIndex: i),
  ];
  return (
    sequence: Sequence.create(
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
    ),
    exposureIds: [for (final exposure in exposures) exposure.id],
  );
}

Future<HarnessHandle> _pumpTree(
  WidgetTester tester,
  Sequence sequence, {
  SequencerDensity density = SequencerDensity.ledger,
  bool minimapVisible = false,
}) async {
  final notifier = CurrentSequenceNotifier();
  // ignore: invalid_use_of_protected_member
  notifier.state = sequence;

  final handle = await pumpAppScreen(
    tester,
    Builder(
      builder: (context) => SequenceTree(colors: NightshadeColors.of(context)),
    ),
    size: _canvas,
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
      minimapVisibleProvider.overrideWith((ref) => minimapVisible),
    ],
  );
  await _drain(tester);
  return handle;
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

Finder _gutter() => find.byKey(sequenceGutterMapKey);

ScrollPosition _treePosition(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// The rectangle the gutter's painter draws for the viewport, computed from the
/// live scroll position through the same pure function the painter uses.
Rect? _viewportRect(WidgetTester tester) => sequenceMapViewportRect(
      offset: _treePosition(tester).pixels,
      viewportDimension: _treePosition(tester).viewportDimension,
      maxScrollExtent: _treePosition(tester).maxScrollExtent,
      size: tester.getSize(_gutter()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ledger draws a 34 px gutter', (tester) async {
    await _pumpTree(tester, _tallSequence().sequence);

    expect(_gutter(), findsOneWidget);
    expect(tester.getSize(_gutter()).width, 34.0);
  });

  testWidgets('comfortable draws no gutter', (tester) async {
    await _pumpTree(
      tester,
      _tallSequence().sequence,
      density: SequencerDensity.comfortable,
    );

    expect(_gutter(), findsNothing);
  });

  testWidgets('compact draws no gutter', (tester) async {
    await _pumpTree(
      tester,
      _tallSequence().sequence,
      density: SequencerDensity.compact,
    );

    expect(_gutter(), findsNothing);
  });

  testWidgets('the 80 px strip stays out of ledger even with the toggle on',
      (tester) async {
    await _pumpTree(tester, _tallSequence().sequence, minimapVisible: true);

    expect(_gutter(), findsOneWidget);
    expect(
      find.byType(SequenceMinimap),
      findsNothing,
      reason: 'two copies of the same map is one map too many',
    );
  });

  testWidgets('compact still answers to the minimap toggle', (tester) async {
    await _pumpTree(
      tester,
      _tallSequence().sequence,
      density: SequencerDensity.compact,
      minimapVisible: true,
    );

    expect(find.byType(SequenceMinimap), findsOneWidget);
  });

  testWidgets('the gutter announces itself as a position, not as blocks',
      (tester) async {
    final handle = tester.ensureSemantics();
    final built = _tallSequence();
    await _pumpTree(tester, built.sequence);

    expect(find.bySemanticsLabel('Sequence overview'), findsOneWidget);
    final node =
        tester.getSemantics(find.bySemanticsLabel('Sequence overview'));
    expect(node.value, 'row 1 of 22');

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await _drain(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Sequence overview')).value,
      isNot('row 1 of 22'),
      reason: 'the readout has to follow the scroll, or it is decoration',
    );
    handle.dispose();
  });

  testWidgets('the viewport rectangle follows the scroll offset',
      (tester) async {
    final built = _tallSequence();
    await _pumpTree(tester, built.sequence);

    // Both samples are taken with the ancestor stack already pinned. The stack
    // covers the top of the viewport, so the scroll content reserves its
    // height while it is up (spec §5) — fewer rows are on screen and the
    // rectangle is honestly shorter for it. Comparing a no-pins sample against
    // a pinned one would be comparing two different viewports, and the
    // invariant this case is about is the one WITHIN a viewport: the rectangle
    // slides down the gutter without changing size.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
    await _drain(tester);
    expect(find.byKey(sequenceStickyAncestorsKey), findsOneWidget);

    final before = _viewportRect(tester);
    expect(before, isNotNull);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await _drain(tester);
    expect(find.byKey(sequenceStickyAncestorsKey), findsOneWidget);

    final after = _viewportRect(tester);
    expect(after!.top, greaterThan(before!.top));
    expect(after.height, closeTo(before.height, 0.01));
  });

  testWidgets('tapping the bottom of the gutter selects the last row',
      (tester) async {
    final built = _tallSequence();
    final handle = await _pumpTree(tester, built.sequence);

    final rect = tester.getRect(_gutter());
    await tester.tapAt(Offset(rect.center.dx, rect.bottom - 1));
    await _drain(tester);

    expect(
      handle.container.read(selectedNodeIdProvider),
      built.exposureIds.last,
    );
    expect(
      tester.getTopLeft(find.text('Sub 19')).dy,
      greaterThanOrEqualTo(
        tester.getTopLeft(find.byType(SingleChildScrollView)).dy,
      ),
      reason: 'selecting a row off screen without bringing it on screen is a '
          'selection the operator cannot see',
    );
  });

  testWidgets('dragging the gutter scrolls the tree', (tester) async {
    final built = _tallSequence();
    await _pumpTree(tester, built.sequence);

    expect(_treePosition(tester).pixels, 0);
    final rect = tester.getRect(_gutter());
    await tester.dragFrom(
      Offset(rect.center.dx, rect.top + 4),
      const Offset(0, 60),
    );
    await _drain(tester);

    expect(_treePosition(tester).pixels, greaterThan(0));
  });
}
