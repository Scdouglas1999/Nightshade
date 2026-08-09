// Regression: the home button's tooltip must describe where home actually is.
//
// The reset action was fixed long ago to centre on the observer's ZENITH,
// because RA 0h / Dec 0 sat 14 deg below the horizon at the audited site and
// "reset view" therefore pointed the map at the ground. The tooltip was never
// updated and went on promising "center 0,0" — observed live: pressing the
// reset hotkey moved the centre to RA 10h34m45s / Dec +40 00' at LST 10:34,
// the zenith, not 0,0.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/widgets/redesign/command_bar.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';
import '../../harness/mock_database.dart' show inMemoryDatabaseOverride;

void main() {
  testWidgets('the home button does not promise RA 0h / Dec 0', (tester) async {
    await pumpAppScreen(
      tester,
      PlanetariumCommandBar(
        compact: false,
        layersOpen: false,
        panelOpen: false,
        showFov: false,
        onToggleLayers: () {},
        onTogglePanel: () {},
        onOpenSearch: () {},
        onToggleFov: () {},
        onResetView: () {},
        onExportChart: () {},
      ),
      size: const Size(1400, 200),
      settle: false,
    );
    await tester.pump();

    final tooltips = tester
        .widgetList<NightshadeTooltip>(find.byType(NightshadeTooltip))
        .map((t) => t.message)
        .toList();

    expect(tooltips, contains('Reset view (zenith, FOV 60)'));
    expect(
      tooltips.where((m) => m.contains('0,0')),
      isEmpty,
      reason: 'reset centres on the zenith, from skyViewHomeCenterProvider',
    );
  });

  test('the reset home really is the zenith, not RA 0h / Dec 0', () {
    final container =
        ProviderContainer(overrides: [inMemoryDatabaseOverride()]);
    addTearDown(container.dispose);
    container
        .read(observerLocationProvider.notifier)
        .setLocation(latitude: 40.0, longitude: -105.0);

    final (_, dec) = container.read(skyViewHomeCenterProvider);
    expect(dec, closeTo(40.0, 0.001));
  });
}
