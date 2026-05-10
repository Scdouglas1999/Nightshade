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
import '../screens/polar_alignment/polar_alignment_screen.dart';
import '../screens/transients/transients_screen.dart';
import '../screens/planner/planner_screen.dart';
import '../screens/diagnostics/diagnostics_screen.dart';
import 'page_transitions.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/dashboard',
    routes: [
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
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: AnalyticsScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
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
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: PlannerScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
          GoRoute(
            path: '/diagnostics',
            name: 'diagnostics',
            pageBuilder: (context, state) => const CustomTransitionPage(
              child: DiagnosticsScreen(),
              transitionsBuilder: PageTransitions.slideFadeTransition,
              transitionDuration: Duration(milliseconds: 300),
            ),
          ),
        ],
      ),
    ],
  );
});
