// NEW-C2's third site — the Sequencer palette tabs are role-less.
//
// Wave D (WD-SEQ-N3) fixed the missing enabled state; Wave F re-read the tree
// and found the node still says `panel: Nodes / Tab 1 of 3`. Flutter's TabBar
// does set `role: SemanticsRole.tab`, but on an ANCESTOR node — the node that
// carries the label, and therefore the node an AT-SPI client reads, is the
// merged one built by `_ToolboxPanel._tabLabel`.
//
// `_ToolboxPanel` is private to SequencerScreen and cannot be pumped on its
// own, and pumping the whole screen for a semantics flag is not a trade worth
// making, so this guard reads the widget's source. It is deliberately narrow:
// it asserts that the ONE builder every palette tab goes through declares both
// a role and an enabled state, which is exactly what the live tree was missing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every palette tab label declares a role and an enabled state', () {
    final file = File(
      'lib/screens/sequencer/sequencer_screen_parts/toolbox_panel.dart',
    );
    expect(file.existsSync(), isTrue,
        reason: 'run from packages/nightshade_app');
    final source = file.readAsStringSync();

    final start = source.indexOf('Widget _tabLabel(');
    expect(start, greaterThan(0), reason: 'the shared tab-label builder moved');
    final body = source.substring(start, source.indexOf('@override', start));

    expect(
      body,
      contains('button: true'),
      reason: 'NEW-C2: the tree read `panel: Nodes / Tab 1 of 3` — no role',
    );
    expect(
      body,
      contains('enabled: true'),
      reason: 'WD-SEQ-N3: and before that, no enabled state either',
    );
    expect(
      body,
      contains('selected:'),
      reason: 'which of the three is current has to be published too',
    );
  });

  test('all three tabs go through that one builder', () {
    final source = File(
      'lib/screens/sequencer/sequencer_screen_parts/toolbox_panel.dart',
    ).readAsStringSync();
    for (final label in const ['Nodes', 'Snippets', 'Queue']) {
      expect(
        source,
        contains("_tabLabel("),
        reason: 'the builder is the single place the role is declared',
      );
      expect(
        RegExp("_tabLabel\\(\\d+, '$label'").hasMatch(source),
        isTrue,
        reason: 'the $label tab must not hand-roll its own label widget',
      );
    }
  });
}
