// Live finding: on the pushed Mosaic projects screen the "< Back" affordance
// only responded on the chevron. The word "Back" was a plain Text sitting
// OUTSIDE the IconButton, so a press on the part that reads as the control did
// nothing — measured on the running app: clicking the label left "Multi-panel
// mosaics" on screen, clicking the chevron 28 px to its left popped the screen.
//
// Also pinned here: the empty state used to send the operator to Framing or the
// Planetarium while "New mosaic" sat in this screen's own header.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_controller.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_projects_list_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _pushedList({List<MosaicProject> projects = const []}) => ProviderScope(
      overrides: [
        mosaicProjectsListProvider.overrideWith((ref) async => projects),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MosaicProjectsListScreen(),
                  ),
                ),
                child: const Text('open list'),
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The row is a bare InkWell: it publishes a tap action but no button role, so
  // a screen reader announced "Back" as static text with nothing to say it can
  // be activated.
  testWidgets('the "< Back" row announces itself as a button', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_pushedList());
    await tester.tap(find.text('open list'));
    await tester.pumpAndSettle();

    final data = tester.getSemantics(find.text('Back')).getSemanticsData();
    expect(
      data.hasFlag(SemanticsFlag.isButton),
      isTrue,
      reason: 'the back affordance must carry the button role',
    );
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);

    semantics.dispose();
  });

  testWidgets('tapping the word "Back" leaves the screen', (tester) async {
    await tester.pumpWidget(_pushedList());
    await tester.tap(find.text('open list'));
    await tester.pumpAndSettle();

    expect(find.text('Mosaic projects'), findsOneWidget);

    // The label, not the chevron. This is the press that used to be swallowed.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(
      find.text('Mosaic projects'),
      findsNothing,
      reason: 'the whole "< Back" row is one control, not a live icon beside '
          'an inert word',
    );
    expect(find.text('open list'), findsOneWidget);
  });

  testWidgets('the empty state points at the action on this screen',
      (tester) async {
    await tester.pumpWidget(_pushedList());
    await tester.tap(find.text('open list'));
    await tester.pumpAndSettle();

    expect(find.text('No mosaic projects yet'), findsOneWidget);
    expect(
      find.widgetWithText(NightshadeButton, 'New mosaic'),
      findsNWidgets(2),
      reason: 'the header action plus one in the empty state, where an '
          'operator with nothing on screen is actually looking',
    );
  });
}
