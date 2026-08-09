// The constellation filter must be usable by someone who does not have the
// IAU abbreviation table memorised.
//
// It used to be a bare DropdownButton listing up to 88 rows of "Constellation:
// And", "Constellation: Aql", "Constellation: CVn" — abbreviations only, the
// words "Constellation: " repeated on every row eating the width, and no
// type-ahead. Now it is a searchable dialog showing the full name with the
// abbreviation in tow, so both spellings match.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  const available = ['And', 'Aql', 'CVn', 'Cas', 'Cyg', 'UMa'];

  Future<Future<String?>> openPicker(WidgetTester tester) async {
    Future<String?>? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                result = showConstellationPickerForTest(
                  context: context,
                  colors: NightshadeColors.of(context),
                  available: available,
                  selected: null,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result!;
  }

  testWidgets('rows show the full name, not a bare abbreviation',
      (tester) async {
    final pending = await openPicker(tester);
    pending.ignore();

    expect(find.text('Canes Venatici (CVn)'), findsOneWidget);
    expect(find.text('Andromeda (And)'), findsOneWidget);
    // The redundant per-row prefix is gone.
    expect(find.textContaining('Constellation: And'), findsNothing);
  });

  testWidgets('typing a full name filters the list and picks the abbreviation',
      (tester) async {
    final pending = await openPicker(tester);

    await tester.enterText(find.byType(TextField), 'ursa');
    await tester.pumpAndSettle();

    expect(find.text('Ursa Major (UMa)'), findsOneWidget);
    expect(find.text('Andromeda (And)'), findsNothing);

    await tester.tap(find.text('Ursa Major (UMa)'));
    await tester.pumpAndSettle();

    // The filter still speaks abbreviations — that is what catalog rows store.
    expect(await pending, 'UMa');
  });

  testWidgets('search also matches the abbreviation', (tester) async {
    final pending = await openPicker(tester);
    pending.ignore();

    await tester.enterText(find.byType(TextField), 'cvn');
    await tester.pumpAndSettle();

    expect(find.text('Canes Venatici (CVn)'), findsOneWidget);
    expect(find.text('Cassiopeia (Cas)'), findsNothing);
  });

  testWidgets('"Any constellation" clears the filter without a dismiss',
      (tester) async {
    final pending = await openPicker(tester);

    await tester
        .tap(find.widgetWithText(NightshadeButton, 'Any constellation'));
    await tester.pumpAndSettle();

    // Empty string, not null: null is a barrier dismiss and must be a no-op.
    expect(await pending, '');
  });
}
