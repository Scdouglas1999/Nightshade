import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nightshade_core/nightshade_core.dart'
    show FirstLaunchCoachStatus, firstLaunchCoachStatusProvider;
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../shell/shell_chrome.dart';
import 'first_launch_coach_panel.dart';

/// Mounts the [FirstLaunchCoachPanel] above the app shell whenever the
/// first-launch coach's persisted status is [FirstLaunchCoachStatus.pending].
///
/// ## Why this exists
///
/// The rich progressive first-launch coach must float over *every* route and
/// survive navigation, so — exactly like [OnboardingTourReplayLauncher] — it is
/// mounted as a sibling above the shell in a [Stack] rather than as a route.
/// That way the user can navigate to `/equipment`, `/settings`, the plate-solver
/// settings, etc. to satisfy each checklist step while the coach stays pinned in
/// place, ticking checkmarks as the readiness engine reports progress.
///
/// ## Reactive contract (no restart needed)
///
/// This launcher watches [firstLaunchCoachStatusProvider] and renders the panel
/// only on `pending`. The status provider is the single hinge for the coach's
/// lifecycle:
///   * The Settings → Help "replay coach" control resets the persisted row and
///     invalidates this provider, which re-mounts the panel immediately.
///   * Dismissing the coach persists the `dismissed` status and invalidates the
///     provider, tearing the panel back down on the next rebuild — the user
///     opted out, so the surface must collapse at once.
///   * Completing the coach is intentionally different. The panel persists the
///     `completed` status but does **not** invalidate this provider, so the
///     gate stays on the `pending` it already read and the celebration body
///     (with its "Capture first light" hand-off) remains mounted for the rest
///     of this session. The persisted `completed` flag suppresses the
///     auto-launch on the next run instead. If this launcher re-resolved the
///     gate to `completed` mid-session it would unmount the very celebration
///     the user just earned, so the no-invalidate-on-complete contract is
///     load-bearing here.
///
/// Because the gate is a pure provider watch, there is no need for the 800ms
/// defer used by route-redirect launchers (which exists to let recovery /
/// onboarding dialogs win the navigator on startup). This is an in-[Stack]
/// overlay that simply gates on a provider, so it neither fights the navigator
/// nor needs to wait for it.
///
/// When the status is anything other than `pending` — including while the DAO
/// read is still in flight, or on a transient read error — the launcher returns
/// [child] unchanged. A returning or finished user therefore never sees the
/// coach and there is no empty hit-test region floating over the shell.
class FirstLaunchCoachLauncher extends ConsumerWidget {
  const FirstLaunchCoachLauncher({super.key, required this.child});

  final Widget child;

  /// Bounded desktop width, matching [ReadinessDashboardOverlay] so the coach
  /// and the readiness card share a consistent floating-card footprint and read
  /// as one family of top-anchored status surfaces.
  static const double _desktopWidth = 480.0;
  static const double _horizontalMargin = NightshadeTokens.spaceLg;
  static const double _topMargin = NightshadeTokens.spaceMd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only overlay the coach on an explicit `pending` status. Loading and error
    // states fail closed to "do not show": the coach is a non-critical setup
    // aid and must never wedge the app or flash on a transient read error.
    final show = ref.watch(firstLaunchCoachStatusProvider).valueOrNull ==
        FirstLaunchCoachStatus.pending;

    if (!show) {
      return child;
    }

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isMobile =
                  constraints.maxWidth < NightshadeTokens.breakpointTablet;
              final cardWidth = isMobile
                  ? constraints.maxWidth - (_horizontalMargin * 2)
                  : _desktopWidth;

              return SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: ShellChrome.useBottomNavigation(constraints.maxWidth)
                          ? _topMargin
                          : ShellChromeMetrics.titleBarHeight + _topMargin,
                      left: _horizontalMargin,
                      right: _horizontalMargin,
                    ),
                    child: SizedBox(
                      width: cardWidth,
                      child: const FirstLaunchCoachPanel(),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
