import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/widgets/mobile_widgets.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('clear cancels a pending search and updates the input affordance',
      (tester) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => SizedBox(
                height: 600,
                child: MobileSearchSheet(
                  colors: NightshadeColors.of(context),
                  scrollController: scrollController,
                  onObjectSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'M4');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 400));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileSearchSheet)),
    );
    final state = container.read(objectSearchProvider);
    expect(find.text('M4'), findsNothing);
    expect(find.byTooltip('Clear search'), findsNothing);
    expect(state.query, isEmpty);
    expect(state.results, isEmpty);
    expect(state.isSearching, isFalse);
    expect(tester.takeException(), isNull);
  });
}
