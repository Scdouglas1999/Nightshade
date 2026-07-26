// Regression: the "Set location" call to action must land on the Location
// section, not the top of Settings.
//
// With no site on record this button is the dashboard's primary remedy. It used
// to navigate to a bare '/settings', which opens the General panel and leaves
// the user hunting the sidebar for the one field the button just offered to set.
// The rest of the app already deep-links with '/settings?section=location'.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/dashboard/widgets/standby/tonight_targets_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('"Set location" deep-links to the Location settings section',
      (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(900, 700);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final visited = <String>[];
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => Scaffold(
            body: Builder(
              builder: (context) =>
                  TonightTargetsCard(colors: NightshadeColors.of(context)),
            ),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) {
            visited.add(state.uri.toString());
            return const Scaffold(body: Text('settings stub'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(
          theme: NightshadeTheme.dark,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A virgin database has lat/lon at 0/0, so the card offers "Set location".
    expect(find.text('Set location'), findsOneWidget);

    await tester.tap(find.text('Set location'));
    await tester.pumpAndSettle();

    expect(visited, ['/settings?section=location']);
  });
}
