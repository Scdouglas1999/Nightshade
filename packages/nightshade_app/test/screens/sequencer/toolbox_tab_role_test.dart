// The Sequencer palette switch must publish a role and a state, not just a
// label.
//
// It used to be a Material `TabBar`, which sets `role: SemanticsRole.tab` on an
// ANCESTOR node while the node that carries the LABEL — the one an AT-SPI
// client reads — dumped as `panel: Nodes / Tab 1 of 3`. The screen worked
// around that with its own `_tabLabel` builder.
//
// Wave 3 replaced the strip with `SegmentedControl`, which annotates every
// segment with `button` + `enabled` + `selected` + `label` itself (its own
// tests in `nightshade_ui` pin that). What is left to guard here is that this
// screen keeps using it, and does not drift back to a bare TabBar with an
// unnamed label node.
//
// `_ToolboxPanel` is private to SequencerScreen and cannot be pumped on its
// own, and pumping the whole screen for a semantics flag is not a trade worth
// making, so this guard reads the widget's source.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the palette switch is a SegmentedControl, not a bare TabBar', () {
    final file = File(
      'lib/screens/sequencer/sequencer_screen_parts/toolbox_panel.dart',
    );
    expect(file.existsSync(), isTrue,
        reason: 'run from packages/nightshade_app');
    final source = file.readAsStringSync();

    expect(
      source,
      contains('SegmentedControl('),
      reason: 'the palette switch must be the shared segmented control, which '
          'names and roles each segment',
    );
    expect(
      source,
      isNot(contains('TabBar(')),
      reason: 'a Material TabBar puts the role on an ancestor of the node that '
          'carries the label, so the label node reads as a role-less panel',
    );
  });
}
