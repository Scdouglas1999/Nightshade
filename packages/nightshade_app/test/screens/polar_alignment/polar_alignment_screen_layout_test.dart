import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/polar_alignment/polar_alignment_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

GoRouter _router(Widget screen) {
  return GoRouter(
    initialLocation: '/polar-alignment',
    routes: [
      GoRoute(
        path: '/polar-alignment',
        builder: (_, __) => screen,
      ),
      GoRoute(
        path: '/settings/plate-solving',
        builder: (_, __) =>
            const Scaffold(body: Text('plate-solving settings stub')),
      ),
      GoRoute(
        path: '/imaging',
        builder: (_, __) => const Scaffold(body: Text('imaging stub')),
      ),
    ],
  );
}

void main() {
  testWidgets(
    'PolarAlignmentScreen idle layout does not overflow at 800x600',
    (tester) async {
      await pumpAppScreen(
        tester,
        MaterialApp.router(
          theme: NightshadeTheme.dark,
          routerConfig: _router(const PolarAlignmentScreen()),
        ),
        size: const Size(800, 600),
        settle: false,
        extraOverrides: [
          plateSolverDetectionProvider.overrideWith(
            (ref) async => const PlateSolverDetection(
              astapPath: r'C:\Program Files\astap\astap.exe',
              catalogPath: r'C:\Program Files\astap',
            ),
          ),
        ],
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester.takeException(),
        isNull,
        reason: 'Layout should not overflow at mount-tab dialog dimensions',
      );

      expect(find.text('Three-Point Polar Alignment'), findsOneWidget);
    },
  );

  testWidgets(
    'PolarAlignmentScreen uses medium stacked layout without overflow',
    (tester) async {
      await pumpAppScreen(
        tester,
        MaterialApp.router(
          theme: NightshadeTheme.dark,
          routerConfig: _router(const PolarAlignmentScreen()),
        ),
        size: const Size(900, 700),
        settle: false,
        extraOverrides: [
          plateSolverDetectionProvider.overrideWith(
            (ref) async => const PlateSolverDetection(
              astapPath: r'C:\Program Files\astap\astap.exe',
              catalogPath: r'C:\Program Files\astap',
            ),
          ),
        ],
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    },
  );
}
