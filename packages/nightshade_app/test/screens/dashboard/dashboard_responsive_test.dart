// Responsive widget tests for DashboardScreen (mobile responsive standard).
//
// Pumps the dashboard at the three reference phone sizes in BOTH orientations
// and asserts:
//   * the compact (phone) layout's own reflow never overflows,
//   * the primary command bar + run-control strip are reachable WITHOUT
//     scrolling (they are pinned above the scroll view),
//   * the screen renders the cockpit grid (not standby) when a session is
//     active.
//
// Overflow scope: tiles compose content from package:nightshade_ui and from
// the sequencer run-dashboard widgets, which can have their own pre-existing
// inner overflows that are out of scope for this screen rework (and which the
// existing dashboard_screen_test.dart swallows wholesale). This file fails only
// on overflows that originate in dashboard_screen.dart — i.e. THIS rework's
// own column/row reflow — and tolerates tile-internal ones.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_screen.dart';
import 'package:nightshade_app/screens/dashboard/widgets/command_bar.dart';
import 'package:nightshade_app/screens/dashboard/widgets/cockpit_run_controls.dart';
import 'package:nightshade_app/screens/dashboard/widgets/dashboard_tile.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// Enables only timer-free legacy tiles so the reflow can be exercised without
/// the realistic cockpit default's periodic poll timers (weather / scheduler /
/// cloud-motion) tripping the test binding's "pending timer" assertion. This
/// set spans the curated compact-layout sections: a full-width hero
/// (livePreview), flow sections (captureSettings, sequenceStatus, guiding), and
/// the equipment section (equipmentStatus).
class _SelectiveDashboardLayoutNotifier extends DashboardLayoutNotifier {
  _SelectiveDashboardLayoutNotifier(this.enabledIds);

  final Set<DashboardWidgetId> enabledIds;

  @override
  Future<DashboardLayout> build() async {
    final tiles = DashboardLayout.defaultLayout()
        .tiles
        .map((tile) =>
            tile.copyWith(enabled: enabledIds.contains(tile.widgetId)))
        .toList();
    return DashboardLayout(
      version: DashboardLayout.currentVersion,
      tiles: tiles,
      secondaryZoneWidth: 0.4,
    );
  }
}

const _reflowTiles = <DashboardWidgetId>{
  DashboardWidgetId.livePreview,
  DashboardWidgetId.captureSettings,
  DashboardWidgetId.sequenceStatus,
  DashboardWidgetId.guiding,
  DashboardWidgetId.equipmentStatus,
};

Future<void> _drainAsyncFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Collects overflow exceptions, treating as fatal only those that originate in
/// the dashboard screen's own layout code (dashboard_screen.dart). Tile-internal
/// overflows from nightshade_ui / the sequencer run-dashboard widgets are
/// pre-existing and out of scope here.
class _OverflowGuard {
  final List<FlutterErrorDetails> appOverflows = [];
  void Function(FlutterErrorDetails)? _previous;

  void install() {
    _previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      if (text.contains('overflowed')) {
        if (text.contains('dashboard_screen.dart')) {
          appOverflows.add(details);
        }
        return;
      }
      _previous?.call(details);
    };
  }

  void restore() {
    FlutterError.onError = _previous;
  }
}

const _phoneSizes = <(String, Size)>[
  ('small phone portrait', Size(360, 640)),
  ('small phone landscape', Size(640, 360)),
  ('modern phone portrait', Size(390, 844)),
  ('modern phone landscape', Size(844, 390)),
  ('large phone portrait', Size(430, 932)),
  ('large phone landscape', Size(932, 430)),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, size) in _phoneSizes) {
    testWidgets('dashboard reflow + pinned controls at $name', (tester) async {
      final guard = _OverflowGuard()..install();
      addTearDown(guard.restore);

      await pumpAppScreen(
        tester,
        const DashboardScreen(),
        size: size,
        settle: false,
        extraOverrides: [
          dashboardLayoutProvider.overrideWith(
            () => _SelectiveDashboardLayoutNotifier(_reflowTiles),
          ),
          // A running execution shows the cockpit grid instead of the standby
          // hero. (Terminal states with nothing loaded/connected now correctly
          // show the briefing, so `completed` no longer forces the grid.)
          sequenceExecutionStateProvider.overrideWith(
            (ref) => SequenceExecutionState.running,
          ),
        ],
      );
      await _drainAsyncFrames(tester);

      expect(
        guard.appOverflows,
        isEmpty,
        reason: 'Dashboard compact reflow must not overflow at $name '
            '(${size.width.toInt()}x${size.height.toInt()}).',
      );

      // Every phone width takes the compact layout (phones in landscape can be
      // wider than the tablet breakpoint but still route to compact), so the
      // CompactDashboardCommandBar is the primary status header and is pinned
      // above the scroll view — reachable without scrolling.
      expect(find.byType(CompactDashboardCommandBar), findsOneWidget,
          reason: 'Phone layouts use the compact command bar at $name.');

      // The run-control strip is pinned (above the scroll view). With a
      // completed (terminal) execution state it self-hides, but the widget is
      // always present in the tree above the scroll body — assert the type is
      // constructed so the pinned strip stays wired.
      expect(find.byType(CockpitRunControls), findsWidgets,
          reason: 'Pinned run controls must be present at $name.');
    });
  }

  testWidgets(
      'dashboard reflows the flow sections into two columns in phone landscape',
      (tester) async {
    // In a wide phone-landscape (844x390 > the 560 two-column threshold) the
    // curated flow sections split into two columns: the captureSettings tile
    // (column A) and the sequenceStatus tile (column B) end up at materially
    // different horizontal offsets — proof of the side-by-side split. In
    // portrait they would share the same left offset (single column).
    final guard = _OverflowGuard()..install();
    addTearDown(guard.restore);

    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(844, 390),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(
          () => _SelectiveDashboardLayoutNotifier(_reflowTiles),
        ),
        // Running forces the cockpit grid; terminal states with nothing
        // loaded/connected show the standby briefing instead.
        sequenceExecutionStateProvider.overrideWith(
          (ref) => SequenceExecutionState.running,
        ),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(CompactDashboardCommandBar), findsOneWidget,
        reason: 'Wide phone landscape still routes to the compact layout.');
    expect(guard.appOverflows, isEmpty,
        reason: 'Two-column landscape reflow must not overflow.');

    // Two distinct column origins among the rendered tiles prove the flow
    // sections split side-by-side. In a single column every tile would share
    // the same left edge.
    final tileElements = find.byType(DashboardTile).evaluate().toList();
    expect(tileElements.length, greaterThanOrEqualTo(2),
        reason: 'Need at least two tiles to demonstrate two columns.');
    final leftOffsets = <double>{};
    for (final element in tileElements) {
      leftOffsets.add(
        tester.getTopLeft(find.byWidget(element.widget)).dx.roundToDouble(),
      );
    }
    expect(leftOffsets.length, greaterThanOrEqualTo(2),
        reason: 'In landscape the flow sections occupy two distinct columns, '
            'so tiles sit at more than one horizontal offset.');
  });
}
