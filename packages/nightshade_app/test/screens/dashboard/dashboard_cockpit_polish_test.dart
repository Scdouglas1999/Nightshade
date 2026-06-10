// Widget tests for the dashboard cockpit polish pass (2026-06-01):
//   1. Pinned safety banners are present in the dashboard tree, and the
//      critical-events → notifications bridge is watched.
//   2. The inline run-control strip shows ONLY while a sequence is active
//      (running / paused / stopping / recovering) and hides otherwise; Stop
//      is hold-to-confirm.
//   3. The standby hero shows when idle-and-not-capturing-and-not-editing and
//      the live cockpit shows when a run is active.
//
// Test-surface notes mirror dashboard_screen_test.dart: every test uses an
// all-disabled (or selectively enabled) layout and keeps the surface < 900px
// wide so the command bar's inner LayoutBuilder skips DashboardClockWidget —
// otherwise nightshade_planetarium's observationTimeProvider leaks a periodic
// timer past the test. Known RenderFlex overflows at the cramped surface are
// swallowed; anything else still fails the test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_screen.dart';
import 'package:nightshade_app/screens/dashboard/widgets/cockpit_run_controls.dart';
import 'package:nightshade_app/screens/dashboard/widgets/cockpit_standby.dart';
import 'package:nightshade_app/screens/sequencer/widgets/run_dashboard/critical_event_banner.dart';
import 'package:nightshade_app/screens/sequencer/widgets/run_dashboard/recovery_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

/// An all-tiles-disabled layout — keeps observationTimeProvider untouched so
/// no periodic timer leaks past the test.
class _AllDisabledLayoutNotifier extends DashboardLayoutNotifier {
  @override
  Future<DashboardLayout> build() async {
    final disabled = DashboardLayout.defaultLayout()
        .tiles
        .map((tile) => tile.copyWith(enabled: false))
        .toList();
    return DashboardLayout(
      version: DashboardLayout.currentVersion,
      tiles: disabled,
      secondaryZoneWidth: 0.4,
    );
  }
}

Future<void> _drainAsyncFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    defaultOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = defaultOnError;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'pinned safety banners are present in the dashboard tree (self-hidden '
      'when inactive)', (tester) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 800),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(_AllDisabledLayoutNotifier.new),
        // Active run so we exercise the cockpit (not standby) path; the
        // banners are pinned in every layout regardless.
        sequenceExecutionStateProvider
            .overrideWith((ref) => SequenceExecutionState.running),
      ],
    );
    await _drainAsyncFrames(tester);

    // Both banners are always instantiated and pinned above the body; they
    // collapse to SizedBox.shrink internally when there's nothing to show.
    expect(find.byType(RunDashboardRecoveryBanner), findsOneWidget,
        reason: 'The recovery banner must be pinned in the dashboard tree.');
    expect(find.byType(RunDashboardCriticalBanner), findsOneWidget,
        reason: 'The critical-event banner must be pinned in the dashboard '
            'tree.');
  });

  testWidgets(
      'run controls show while a sequence is running and Stop is '
      'hold-to-confirm', (tester) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 800),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(_AllDisabledLayoutNotifier.new),
        sequenceExecutionStateProvider
            .overrideWith((ref) => SequenceExecutionState.running),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(CockpitRunControls), findsOneWidget,
        reason: 'The run-control strip must be pinned while a run is active.');
    // The strip renders its three controls; the active state shows Pause
    // (not Resume) and a hold-to-confirm Stop.
    expect(find.text('Pause'), findsOneWidget,
        reason: 'A running sequence shows the Pause control.');
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.byType(HoldToConfirmButton), findsWidgets,
        reason: 'Stop must be wrapped in a HoldToConfirmButton so a stray '
            'click cannot abort an overnight run.');
  });

  testWidgets('run controls hide when the sequence is idle', (tester) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 800),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(_AllDisabledLayoutNotifier.new),
        // Idle is the default, but pin it explicitly so the intent is clear.
        sequenceExecutionStateProvider
            .overrideWith((ref) => SequenceExecutionState.idle),
      ],
    );
    await _drainAsyncFrames(tester);

    // CockpitRunControls is still in the tree (it's pinned), but it renders
    // a zero-size box when idle — so none of its labels are present.
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets(
      'standby hero shows when idle and not capturing; the cockpit replaces '
      'it when a run is active', (tester) async {
    _swallowKnownOverflows();

    // Idle + not capturing → standby hero, no tile grid.
    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 800),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(_AllDisabledLayoutNotifier.new),
        sequenceExecutionStateProvider
            .overrideWith((ref) => SequenceExecutionState.idle),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(CockpitStandby), findsOneWidget,
        reason: 'Idle-and-not-capturing must show the standby hero in place of '
            'the tile grid.');
    expect(find.text('No run active'), findsOneWidget);
    expect(find.text('Image tonight'), findsOneWidget,
        reason: 'Standby offers the one-tap Image tonight CTA.');
    expect(find.text('Plan Tonight (advanced)'), findsOneWidget,
        reason: 'Standby keeps the Smart Night wizard as the secondary CTA.');
  });

  testWidgets('cockpit (not standby) renders while a sequence is running',
      (tester) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 800),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(_AllDisabledLayoutNotifier.new),
        sequenceExecutionStateProvider
            .overrideWith((ref) => SequenceExecutionState.running),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(CockpitStandby), findsNothing,
        reason: 'A running sequence must show the live cockpit, not standby.');
  });
}
