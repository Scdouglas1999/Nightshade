// Widget test for the imaging GuidingPanel's per-axis PEAK guide-error
// readout (Phase G quick win).
//
// Background: peak RA/Dec are already tracked in the rolling guide stats
// (Phd2GuideStats.peakRa/peakDec) but, before this change, only the three RMS
// tiles were surfaced. The panel now renders a second stat row showing the
// per-axis peak excursion alongside the RMS figures.
//
// Scope: drive the panel with a guideStatsProvider seeded to known peak values
// and assert the formatted tiles render. The values are formatted to two
// decimals + an arcsecond suffix, matching the existing RMS tiles, so the
// assertions pin both the labels and the seeded numbers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/guiding_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../../harness/harness.dart';

/// A [GuiderStateNotifier] seeded connected + guiding so the panel renders its
/// stats section (rather than the disconnected warning state).
class _ConnectedGuiderNotifier extends GuiderStateNotifier {
  _ConnectedGuiderNotifier(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const GuiderState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'simulator:guider:0',
      isGuiding: true,
      rmsRa: 0.42,
      rmsDec: 0.37,
      rmsTotal: 0.56,
    );
  }
}

/// A [GuideStatsNotifier] pinned to a known snapshot carrying explicit peak
/// values, so the peak tiles have deterministic content to assert on without
/// pumping synthetic GuideStep events through the backend event stream.
class _SeededGuideStatsNotifier extends GuideStatsNotifier {
  _SeededGuideStatsNotifier(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const Phd2GuideStats(
      rmsRa: 0.42,
      rmsDec: 0.37,
      rmsTotal: 0.56,
      peakRa: 1.23,
      peakDec: 0.89,
      snr: 18.0,
      starMass: 4200,
      frameCount: 100,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders per-axis PEAK guide error from seeded stats',
      (tester) async {
    await pumpAppScreen(
      tester,
      const GuidingPanel(colors: NightshadeColors.dark),
      // Mobile-portrait surface keeps the scrolling panel laid out without the
      // built-in-guider-only sections expanding the tree.
      size: const Size(380, 900),
      extraOverrides: [
        guiderStateProvider.overrideWith(_ConnectedGuiderNotifier.new),
        guideStatsProvider.overrideWith(_SeededGuideStatsNotifier.new),
        // Keep the built-in-guider-only config/star sections out of the tree so
        // the test pins exactly the stat tiles it owns.
        isBuiltinGuiderProvider.overrideWithValue(false),
      ],
      settle: false,
    );
    // Drain the initial frames (the panel polls/animates; settle would time out).
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }

    // The new peak row labels.
    expect(find.text('RA Peak'), findsOneWidget,
        reason: 'The RA peak tile must render alongside RA RMS.');
    expect(find.text('Dec Peak'), findsOneWidget,
        reason: 'The Dec peak tile must render alongside Dec RMS.');

    // The seeded peak values, formatted to two decimals + arcsecond suffix.
    expect(find.text('1.23"'), findsOneWidget,
        reason: 'Peak RA must render the seeded value verbatim.');
    expect(find.text('0.89"'), findsOneWidget,
        reason: 'Peak Dec must render the seeded value verbatim.');
  });
}
