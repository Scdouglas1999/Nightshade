// Regression (D-3): every time-transport control must carry its own accessible
// name on the BUTTON node, and the one that stops time must report that it has.
//
// Live AT-SPI dump of the planetarium transport, taken from the running desktop
// build:
//
//   panel: Aug 13, 2026 [DISABLED]
//   button:            <- rewind / rate down
//   button:            <- step back 1 h
//   button:            <- play / pause
//   button:            <- step forward 1 h
//   button:            <- fast forward / rate up
//   button: NOW
//   button: TONIGHT
//
// Five bare buttons with empty names, no toggle state on play/pause, and the
// date chip — the control that opens the date picker — reported as an inert
// disabled panel. The only signal that time was stopped was the string PAUSED
// merged into an unrelated text panel, so the pause fix was invisible to
// assistive tech.
//
// `IconButton(tooltip:)` is why: the tooltip's `Semantics(label:)` is not a
// container, so it is absorbed by some ancestor node rather than by the button's
// own — producing a named panel beside an unnamed button, which is precisely
// what the dump shows. The assertions below therefore check the property an
// assistive client actually consumes: ONE node carrying the name, the button
// role and the tap action together.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_planetarium/src/providers/planetarium_providers.dart';
import 'package:nightshade_planetarium/src/widgets/time_control_panel.dart';

Future<ProviderContainer> _pumpTransport(WidgetTester tester) async {
  final container = ProviderContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: Center(child: TimeControlPanel())),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Every node in the compiled semantics tree, as an assistive client sees it.
List<SemanticsData> _tree(WidgetTester tester) {
  // `pipelineOwner`, not `rootPipelineOwner`: the test binding attaches the
  // widget tree's semantics owner to the former, and the root's is empty.
  // ignore: deprecated_member_use
  final root = tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
  final out = <SemanticsData>[];
  void visit(SemanticsNode node) {
    out.add(node.getSemanticsData());
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return out;
}

/// Is there one node that is named [name] AND is an enabled, tappable button?
bool _namedButton(List<SemanticsData> tree, String name, {bool? toggled}) {
  return tree.any((d) {
    if (!d.label.contains(name)) return false;
    if (!d.hasFlag(SemanticsFlag.isButton)) return false;
    if (!d.hasAction(SemanticsAction.tap)) return false;
    if (toggled == null) return true;
    return d.hasFlag(SemanticsFlag.hasToggledState) &&
        d.hasFlag(SemanticsFlag.isToggled) == toggled;
  });
}

void main() {
  testWidgets('every transport button carries its own name', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await _pumpTransport(tester);

    final tree = _tree(tester);
    for (final name in const [
      'Slower', // rewind / rate down
      'Back 1 hour',
      'Pause',
      'Forward 1 hour',
      'Faster', // fast forward / rate up
      'NOW',
      'TONIGHT',
    ]) {
      expect(
        _namedButton(tree, name),
        isTrue,
        reason:
            '"$name" must be the name of the button node itself, not of a '
            'panel beside it',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    handle.dispose();
  });

  testWidgets('play/pause reports whether the sky is held', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await _pumpTransport(tester);

    expect(_namedButton(_tree(tester), 'Pause', toggled: false), isTrue);

    await tester.tap(find.byIcon(LucideIcons.pause));
    await tester.pump();

    expect(container.read(observationTimeProvider).isPaused, isTrue);
    expect(
      _namedButton(_tree(tester), 'Play', toggled: true),
      isTrue,
      reason: 'a screen reader must be able to tell that time is stopped',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    handle.dispose();
  });

  testWidgets('the date chip is a button, not an inert panel', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await _pumpTransport(tester);

    final node = tester.getSemantics(find.byIcon(LucideIcons.calendar));
    final data = node.getSemanticsData();
    expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
    expect(data.hint, contains('Choose a date'));

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    handle.dispose();
  });
}
