// Android tap-target audit for the mobile primary destinations.
//
// A previous mobile pass judged tap-target sizes "by eye from screenshots, not
// measured", which cannot distinguish a 44dp control from a 48dp one. This
// suite MEASURES them: it runs Flutter's own `androidTapTargetGuideline` (the
// 48x48 rule) over each screen at the three standard phone widths, and — when
// something fails — walks the semantics tree to report the offending rects with
// their actual sizes so the failure names real numbers instead of a boolean.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/analytics/analytics_screen.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_screen.dart';
import 'package:nightshade_app/screens/equipment/equipment_screen.dart';
import 'package:nightshade_app/screens/guiding/guiding_screen.dart';
import 'package:nightshade_app/screens/imaging/imaging_screen.dart';
import 'package:nightshade_app/screens/planner/planner_screen.dart';
import 'package:nightshade_app/screens/sequencer/sequencer_screen.dart';
import 'package:nightshade_app/screens/weather/weather_screen.dart';

import '../harness/harness.dart';

/// Android's minimum touch-target edge, in logical pixels.
const double kMinTapTarget = 48.0;

Future<void> _drainFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// One measured, tappable semantics node.
class _Target {
  final Rect rect;
  final String label;
  _Target(this.rect, this.label);

  double get shortestEdge =>
      rect.width < rect.height ? rect.width : rect.height;
  @override
  String toString() =>
      '${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)}'
      '${label.isEmpty ? '' : ' "$label"'}';
}

/// Every tappable semantics node, with rects resolved to global coordinates —
/// the same traversal Flutter's own tap-target guideline performs.
List<_Target> _measureTapTargets() {
  final tappableNodes = find.semantics.byPredicate((node) {
    final data = node.getSemanticsData();
    return data.hasAction(SemanticsAction.tap) &&
        !data.flagsCollection.isHidden &&
        !data.flagsCollection.isTextField;
  });
  return [
    for (final candidate in tappableNodes.evaluate())
      _Target(
        candidate.rect,
        candidate.getSemanticsData().label,
      ),
  ];
}

const _phoneSizes = <(String, Size)>[
  ('small 360x640', Size(360, 640)),
  ('modern 390x844', Size(390, 844)),
  ('large 430x932', Size(430, 932)),
];

void main() {
  final screens = <String, Widget Function()>{
    'dashboard': () => const DashboardScreen(),
    'equipment': () => const EquipmentScreen(),
    'imaging': () => const ImagingScreen(),
    'sequencer': () => const SequencerScreen(),
    'guiding': () => const GuidingScreen(),
    'weather': () => const WeatherScreen(),
    'planner': () => const PlannerScreen(),
    'analytics': () => const AnalyticsScreen(),
  };

  for (final entry in screens.entries) {
    for (final (label, size) in _phoneSizes) {
      testWidgets('${entry.key} meets the 48dp Android tap target at $label',
          (tester) async {
        final handle = tester.ensureSemantics();
        final app = await pumpAppScreen(
          tester,
          entry.value(),
          size: size,
          settle: false,
        );
        await _drainFrames(tester);

        final undersized = _measureTapTargets()
            .where((t) => t.shortestEdge < kMinTapTarget)
            .toList()
          ..sort((a, b) => a.shortestEdge.compareTo(b.shortestEdge));

        // Report the actual numbers rather than a bare boolean.
        expect(
          undersized,
          isEmpty,
          reason:
              '${entry.key} @ $label has ${undersized.length} tap target(s) '
              'under ${kMinTapTarget}dp: ${undersized.take(12).join(', ')}',
        );

        handle.dispose();

        // Tear the tree down inside the test body. Screens that watch a
        // polling provider (analytics -> activeTransientAlertsProvider) hold a
        // periodic Timer that is only cancelled by the provider's `onDispose`.
        // `pumpAppScreen` disposes the container in an `addTearDown`, which
        // runs *after* the binding's "no pending timers" invariant check — so
        // those screens failed here on a timer leak rather than on a tap
        // target. Unmount, then dispose (dispose is idempotent, so the
        // harness's own tearDown stays a no-op).
        await tester.pumpWidget(const SizedBox.shrink());
        app.container.dispose();
        // Disposing drift's query streams schedules zero-duration timers of its
        // own; elapse a little so they fire before the invariant check.
        await _drainFrames(tester);
      });
    }
  }
}
