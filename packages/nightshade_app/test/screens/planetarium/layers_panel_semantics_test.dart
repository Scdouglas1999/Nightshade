// Regression: SKY-17 — the planetarium's sky-layer switches exposed no state.
//
// Found live. One accessibility dump of the open Layers panel listed twelve
// rows as `panel: <name> [DISABLED]` — DSO labels, Constellation lines,
// Milky Way, Coordinate grid, Ecliptic, Meridian and the rest — beside two that
// reported as proper toggles with an on/off state. A screen-reader user was
// told that twelve of the fourteen sky layers could not be operated, and none
// of them said whether they were on.
//
// Cause: each row is a label Text and a Switch under one InkWell with nothing
// merging them, so the name and the state landed in different nodes and the
// named one carried no action. Same defect SettingRow was fixed for.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/widgets/redesign/layers_panel.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

/// A tall window so the whole layer list is built: the panel is a lazy
/// ListView and an off-screen row has no semantics to inspect.
void _tallWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 2400);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _surface() {
  return const ProviderScope(
    child: MaterialApp(
      home: Scaffold(body: SizedBox(width: 360, child: LayersPanel())),
    ),
  );
}

void main() {
  testWidgets('every sky layer reports its name, its state and its action',
      (tester) async {
    final handle = tester.ensureSemantics();
    _tallWindow(tester);
    await tester.pumpWidget(_surface());
    await tester.pump();

    // Rows spread across three groups of the panel, including several of the
    // ones the live dump named.
    for (final label in const [
      'Stars',
      'Constellation lines',
      'Coordinate grid',
      'Ecliptic',
    ]) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(MergeSemantics),
      );
      expect(row, findsOneWidget, reason: '$label is not one merged node');
      expect(
        tester.getSemantics(row.first),
        isSemantics(
          label: label,
          hasToggledState: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
        reason: '$label must say what it is, whether it is on, and that it '
            'can be operated',
      );
    }

    handle.dispose();
  });

  testWidgets('a layer that is on reports itself toggled', (tester) async {
    final handle = tester.ensureSemantics();
    _tallWindow(tester);
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 360, child: LayersPanel())),
        ),
      ),
    );
    await tester.pump();

    final on = container.read(skyRenderConfigProvider).showStars;
    final row = find
        .ancestor(
          of: find.text('Stars'),
          matching: find.byType(MergeSemantics),
        )
        .first;
    expect(tester.getSemantics(row), isSemantics(isToggled: on));

    await tester.tap(row);
    await tester.pump();
    expect(tester.getSemantics(row), isSemantics(isToggled: !on));

    handle.dispose();
  });
}
