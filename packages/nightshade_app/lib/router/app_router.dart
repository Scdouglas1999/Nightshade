import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/shell/app_shell.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/equipment/equipment_screen.dart';
import '../screens/imaging/imaging_screen.dart';
import '../screens/guiding/guiding_screen.dart';
import '../screens/sequencer/sequencer_screen.dart';
import '../screens/planetarium/planetarium_screen.dart';
import '../screens/framing/framing_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/flat_wizard/flat_wizard_screen.dart';
import '../screens/weather/weather_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/plate_solving_settings_screen.dart';
import '../screens/polar_alignment/polar_alignment_screen.dart';
import '../screens/transients/transients_screen.dart';
import '../screens/planner/planner_screen.dart';
import '../screens/scheduler/scheduler_screen.dart';
import '../screens/diagnostics/diagnostics_screen.dart';
import '../screens/diagnostics/diagnostic_dump_screen.dart';
import '../screens/tutorial/first_night_wizard_route.dart';
import '../screens/onboarding/onboarding_screen.dart';
import 'page_transitions.dart';

/// Builder for the phone-tailored dashboard route (audit §3.5).
///
/// The mobile app injects this when it boots so the router can resolve
/// `/mobile-dashboard` without `packages/nightshade_app` taking a hard
/// dependency on `apps/mobile`. Defaults to a placeholder so the route
/// always exists (helpful when the desktop GoRouter is exercised in
/// tests), but the placeholder should never render in production.
WidgetBuilder mobileDashboardBuilder = (context) {
  return const Scaffold(
    body: Center(
      child: Text(
        'Mobile dashboard is only available on phone builds.\n'
        'apps/mobile.main wires the real builder.',
        textAlign: TextAlign.center,
      ),
    ),
  );
};

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
      // Phone-tailored dashboard lives outside the shell because it
      // brings its own scaffold + bottom-nav and the desktop AppShell
      // would double-up the chrome and steal the bottom 78 px from the
      // sticky sequencer footer.
      GoRoute(
        path: '/mobile-dashboard',
        name: 'mobile-dashboard',
        builder: (context, state) => mobileDashboardBuilder(context),
      ),
      // First-run equipment onboarding wizard. Sits outside the AppShell
      // so the new user is not distracted by the side-nav while they
      // configure their first profile. `EquipmentOnboardingLauncher`
      // routes here automatically when there are no profiles yet.
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: DashboardScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/equipment',
            name: 'equipment',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: EquipmentScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/imaging',
            name: 'imaging',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: ImagingScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
            routes: [
              // Deep-link target for `image_ready` notification taps
              // (audit §3.8). The image identifier is passed through so the
              // imaging screen can highlight the new capture; today the
              // imaging screen reads :imageId from GoRouterState if it
              // wants to scroll or focus that frame.
              GoRoute(
                path: 'preview/:imageId',
                name: 'imaging-preview',
                pageBuilder: (context, state) => const CustomTransitionPage(
                  child: ImagingScreen(),
                  transitionsBuilder: PageTransitions.slideFadeTransition,
                  transitionDuration: Duration(milliseconds: 300),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/guiding',
            name: 'guiding',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: GuidingScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/sequencer',
            name: 'sequencer',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: SequencerScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/planetarium',
            name: 'planetarium',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: PlanetariumScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/framing',
            name: 'framing',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: FramingScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            pageBuilder: (context, state) {
              final tabQuery = state.uri.queryParameters['tab'];
              return CustomTransitionPage(
                child: AnalyticsScreen(initialTabQuery: tabQuery),
                transitionsBuilder: PageTransitions.slideFadeTransition,
                transitionDuration: const Duration(milliseconds: 300),
              );
            },
          ),
          GoRoute(
            path: '/flat-wizard',
            name: 'flat-wizard',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: FlatWizardScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/weather',
            name: 'weather',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: WeatherScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: SettingsScreen(),
              transitionsBuilder: PageTransitions.scaleFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
            routes: [
              // W6-SOLVER-UX §6.1 — dedicated plate-solver setup page.
              // Reachable from the centering / framing / polar alignment
              // "Plate solver not configured" banners.
              GoRoute(
                path: 'plate-solving',
                name: 'settings-plate-solving',
                pageBuilder: (context, state) => const CustomTransitionPage(
                  child: PlateSolvingSettingsScreen(),
                  transitionsBuilder: PageTransitions.slideFadeTransition,
                  transitionDuration: Duration(milliseconds: 300),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/polar-alignment',
            name: 'polar-alignment',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: PolarAlignmentScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/transients',
            name: 'transients',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: TransientsScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/planner',
            name: 'planner',
            pageBuilder: (context, state) {
              final tabQuery = state.uri.queryParameters['tab'];
              return CustomTransitionPage(
                child: PlannerScreen(initialTabQuery: tabQuery),
                transitionsBuilder: PageTransitions.slideFadeTransition,
                transitionDuration: const Duration(milliseconds: 300),
              );
            },
          ),
          // DEPRECATED: use /planner?tab=scheduler. Kept for one release for
          // deep-link compatibility — Scheduler merged into Plan Tonight as
          // a tab (§UX consolidation, W8-SCHED-MERGE).
          GoRoute(
            path: '/scheduler',
            name: 'scheduler',
            redirect: (context, state) => '/planner?tab=scheduler',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: SchedulerScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          // DEPRECATED: use /analytics?tab=diagnostics. Kept for one release
          // for deep-link compatibility.
          GoRoute(
            path: '/diagnostics',
            name: 'diagnostics',
            redirect: (context, state) => '/analytics?tab=diagnostics',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: DiagnosticsScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          // Bug-report bundle: zip up logs/profile/sequence/system info into
          // one attachment. Lives at /diagnostics/dump (not under /settings)
          // so support links can deep-link past the settings tree.
          // See audit-observe.md §4c / CQ-W6-DIAG-DUMP.
          GoRoute(
            path: '/diagnostics/dump',
            name: 'diagnostics-dump',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: DiagnosticDumpScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          // First-night wizard entry. The route renders the dashboard
          // underneath and opens the wizard as a modal dialog on top —
          // this is how Settings → Help → "First Night Walkthrough" and
          // the auto-launch flow both reach the wizard. Dismissing the
          // dialog returns the user to /dashboard.
          GoRoute(
            path: '/tutorial/first-night',
            name: 'tutorial-first-night',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: FirstNightWizardRoute(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
    ],
  );
});
