// Regression: the Deep-Star Tier card must quote the same HYG floor the
// HYG/deep-tier merge seam actually uses.
//
// The card hard-coded "~mag 11.5" while the seam (kHygFaintFloorMag) had
// already been corrected to 9.0 and the Layers panel was reporting 9.0 — so the
// settings sheet contradicted the running renderer about where the bundled
// catalog stops. It also called a self-hosted URL form an install.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/deep_star_catalog_card.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

import '../../harness/pump_app_screen.dart';

void main() {
  late Directory catalogDir;

  setUp(() async {
    catalogDir = await Directory.systemTemp.createTemp('deep_star_card');
    await CatalogManager.instance.initialize(catalogDir.path);
  });

  tearDown(() async {
    if (catalogDir.existsSync()) await catalogDir.delete(recursive: true);
  });

  testWidgets('the card states the real HYG floor and that nothing is hosted',
      (tester) async {
    await pumpAppScreen(
      tester,
      const DeepStarCatalogCard(),
      size: const Size(700, 900),
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('~mag 11.5'), findsNothing);
    expect(
      find.textContaining(
        'mag ${kHygFaintFloorMag.toStringAsFixed(1)}',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('No tileset is published yet'), findsOneWidget);
  });
}
