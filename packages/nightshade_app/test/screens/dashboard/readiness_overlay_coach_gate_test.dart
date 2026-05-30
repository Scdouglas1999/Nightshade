// Widget tests for the dashboard's first-launch-coach gate on the
// ReadinessDashboardOverlay (Rich Progressive First-Launch Guide, C8).
//
// Both the progressive first-launch coach and the per-issue readiness nudge
// anchor top-centre. To avoid two stacked surfaces fighting for the same
// region, DashboardScreen suppresses the ReadinessDashboardOverlay while the
// coach is active (firstLaunchCoachStatusProvider == pending):
//
//   * NEW user (coach pending) -> coach owns top-centre; the readiness
//     overlay is NOT mounted.
//   * RETURNING user (coach completed/dismissed) -> the readiness overlay IS
//     mounted (it still self-collapses when the rig is fully ready, but that
//     is the overlay's own concern, not the gate's).
//
// These tests pin exactly that gate. They override firstLaunchCoachStatusProvider
// to each terminal/pending value and assert the ReadinessDashboardOverlay
// widget's presence/absence. We assert on the overlay *widget type* (which the
// gate mounts or omits) rather than its rendered card, so the test isolates the
// C8 gate from the overlay's independent "is there anything outstanding?"
// collapse logic.
//
// The dashboard layout is forced to an all-disabled layout for the same reason
// as dashboard_screen_test.dart: the default layout's Tonight tile / wide clock
// pull nightshade_planetarium's observationTimeProvider, whose periodic timer
// never stops and trips the post-test timer-leak invariant. Keeping the surface
// < 900 wide also avoids the embedded DashboardClockWidget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_layout_provider.dart';
import 'package:nightshade_app/screens/dashboard/dashboard_screen.dart';
import 'package:nightshade_app/screens/dashboard/widgets/readiness_dashboard_overlay.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// A DashboardLayoutNotifier override that returns a layout with every tile
/// disabled, so no tile transitively pulls observationTimeProvider's periodic
/// timer. Mirrors the all-disabled notifier in dashboard_screen_test.dart.
class _AllDisabledDashboardLayoutNotifier extends DashboardLayoutNotifier {
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

/// Drive several frames so AsyncValue providers (dashboardLayoutProvider and
/// the overridden firstLaunchCoachStatusProvider future) resolve and the
/// screen commits a stable frame. pumpAndSettle is unsafe here because the
/// dashboard's status-pulse animations never settle.
Future<void> _drainAsyncFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Drop cosmetic "RenderFlex overflowed" errors at the cramped test surface;
/// re-forward everything else so a real regression still trips takeException.
void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) {
      return;
    }
    defaultOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = defaultOnError;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'coach pending suppresses the ReadinessDashboardOverlay (new user sees '
      'only the coach)', (tester) async {
    _swallowKnownOverflows();

    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 600),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(
          _AllDisabledDashboardLayoutNotifier.new,
        ),
        firstLaunchCoachStatusProvider.overrideWith(
          (ref) async => FirstLaunchCoachStatus.pending,
        ),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(ReadinessDashboardOverlay), findsNothing,
        reason:
            'While the first-launch coach is pending it owns the top-centre '
            'surface; the dashboard must not also mount the readiness overlay, '
            'or a new user would see two stacked cards.');
  });

  testWidgets(
      'coach completed mounts the ReadinessDashboardOverlay (returning user '
      'still gets the per-issue nudge)', (tester) async {
    _swallowKnownOverflows();

    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 600),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(
          _AllDisabledDashboardLayoutNotifier.new,
        ),
        firstLaunchCoachStatusProvider.overrideWith(
          (ref) async => FirstLaunchCoachStatus.completed,
        ),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(ReadinessDashboardOverlay), findsOneWidget,
        reason:
            'Once the coach is completed the gate opens and the dashboard must '
            'mount the readiness overlay again; suppressing it for a returning '
            'user would hide outstanding setup work.');
  });

  testWidgets(
      'coach dismissed also mounts the ReadinessDashboardOverlay', (tester) async {
    _swallowKnownOverflows();

    await pumpAppScreen(
      tester,
      const DashboardScreen(),
      size: const Size(780, 600),
      settle: false,
      extraOverrides: [
        dashboardLayoutProvider.overrideWith(
          _AllDisabledDashboardLayoutNotifier.new,
        ),
        firstLaunchCoachStatusProvider.overrideWith(
          (ref) async => FirstLaunchCoachStatus.dismissed,
        ),
      ],
    );
    await _drainAsyncFrames(tester);

    expect(find.byType(ReadinessDashboardOverlay), findsOneWidget,
        reason:
            'Dismissing the coach is a terminal state that opens the gate, '
            'exactly like completing it; the readiness overlay must mount.');
  });
}
