// SCI-44: on Session Review the SELECTED tab rendered as a grey chip with
// dimmed text while the unselected one kept bright text — the state read
// inverted against every other tab strip in the app. Measured off the evidence
// crop: the selected chip painted #212630 (surfaceHover) over its #5B9EC4
// primary fill, because the app theme sets an OPAQUE `hoverColor`, and the
// pointer rests on whichever chip was just clicked. The symmetry the report
// noted ("with Workbench open, Workbench is the dim one") is that pointer.
//
// The same nodes were exposed to assistive tech as `panel: Workbench` with no
// selected state, so neither the pixels nor the tree said which tab was live.

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/session_review_controller.dart';
import 'package:nightshade_app/screens/session_review/session_review_screen.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _bar(
    SessionReviewViewMode mode, void Function(SessionReviewViewMode) f) {
  return ProviderScope(
    child: MaterialApp(
      theme: NightshadeTheme.dark,
      home: Scaffold(
        body: SessionReviewViewToggleBar(mode: mode, onChanged: f),
      ),
    ),
  );
}

/// The Material that paints the chip carrying [label].
Material _chipMaterial(WidgetTester tester, String label) {
  return tester.widget<Material>(
    find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hovering the selected tab cannot repaint it as unselected',
      (tester) async {
    await tester.pumpWidget(
      _bar(SessionReviewViewMode.workbench, (_) {}),
    );
    await tester.pump();

    final selected = _chipMaterial(tester, 'Workbench');
    expect(selected.color, NightshadeColors.dark.primary);

    // Park the pointer on the selected chip, exactly as a click leaves it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Workbench')));
    await tester.pumpAndSettle();

    final inkWell = tester.widget<InkWell>(
      find
          .ancestor(of: find.text('Workbench'), matching: find.byType(InkWell))
          .first,
    );
    final hover = inkWell.hoverColor;
    expect(
      hover,
      isNotNull,
      reason: 'the app theme hoverColor is opaque and would erase the fill',
    );
    expect(
      hover!.a,
      lessThan(1.0),
      reason: 'a hover tint must sit ON the selection, not replace it',
    );
    expect(_chipMaterial(tester, 'Workbench').color,
        NightshadeColors.dark.primary);
  });

  testWidgets('each tab announces its role and whether it is selected',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_bar(SessionReviewViewMode.workbench, (_) {}));
    await tester.pump();

    expect(
      tester.getSemantics(find.text('Workbench')),
      matchesSemantics(
        label: 'Workbench',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        isEnabled: true,
        isFocusable: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Narrative')),
      matchesSemantics(
        label: 'Narrative',
        isButton: true,
        isSelected: false,
        hasSelectedState: true,
        isEnabled: true,
        isFocusable: true,
        hasEnabledState: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('tapping an unselected tab still switches view', (tester) async {
    SessionReviewViewMode? picked;
    await tester.pumpWidget(
      _bar(SessionReviewViewMode.workbench, (m) => picked = m),
    );
    await tester.tap(find.text('Narrative'));
    await tester.pump();
    expect(picked, SessionReviewViewMode.narrative);
  });
}
