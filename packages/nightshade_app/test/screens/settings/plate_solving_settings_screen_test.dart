// Widget + model tests for the Plate Solving settings UX layer
// (W6-SOLVER-UX §6.1).
//
// Imports the model leaf path rather than the public `nightshade_core`
// barrel because the v2.5.0-hardening base SHA carries unrelated
// `framing_provider` / `scheduler_provider` breakage that prevents the
// barrel from compiling. Once that is repaired this should switch to
// `package:nightshade_core/nightshade_core.dart` — both surfaces export
// the same `PlateSolverDetection` / `PlateSolverInfo` types.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/plate_solving_settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/solver_detection_card.dart';
// SolverDetectionCard imports the model leaf directly to avoid a circular
// dependency on the core barrel; the screen-level tests below need the
// detection / preference providers, so they reach in through the barrel.
import 'package:nightshade_core/src/models/plate_solver.dart';
import 'package:nightshade_core/src/providers/plate_solver_provider.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Future<void> _pumpCard(
  WidgetTester tester, {
  required PlateSolverDetection detection,
  PlateSolverInfo? verifyInfo,
  String? verifyError,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(900, 1200);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SolverDetectionCard(
              detection: detection,
              astapVerifyInfo: verifyInfo,
              astapVerifyError: verifyError,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SolverDetectionCard', () {
    testWidgets('shows install link when no solver is detected',
        (tester) async {
      await _pumpCard(
        tester,
        detection: const PlateSolverDetection(),
      );

      expect(
        find.textContaining('ASTAP not installed'),
        findsOneWidget,
        reason: 'Banner must call out missing ASTAP plainly',
      );
      expect(
        find.textContaining('Download ASTAP'),
        findsOneWidget,
        reason: 'Install link must surface so users can act on the banner',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows green ready banner with catalog when ASTAP found',
        (tester) async {
      await _pumpCard(
        tester,
        detection: const PlateSolverDetection(
          astapPath: r'C:\Program Files\astap\astap.exe',
          catalogName: 'V17',
          catalogMagnitudeLimit: 17.0,
          catalogPath: r'C:\Program Files\astap',
        ),
      );

      expect(
        find.textContaining('ASTAP detected'),
        findsOneWidget,
        reason: 'Ready banner must announce ASTAP detection',
      );
      expect(
        find.textContaining('V17'),
        findsOneWidget,
        reason: 'Catalog name must appear in the title',
      );
      expect(
        find.textContaining('mag 17'),
        findsOneWidget,
        reason: 'Magnitude limit must be formatted into the title',
      );
      expect(
        find.text(r'C:\Program Files\astap\astap.exe'),
        findsOneWidget,
        reason: 'Path must appear so user can confirm the right install',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows catalog-missing warning when ASTAP path has no catalog',
        (tester) async {
      await _pumpCard(
        tester,
        detection: const PlateSolverDetection(
          astapPath: '/opt/astap/astap',
        ),
      );

      expect(
        find.textContaining('catalog missing'),
        findsOneWidget,
        reason: 'Must surface the catalog-missing distinct state',
      );
      expect(
        find.text('/opt/astap/astap'),
        findsOneWidget,
        reason: 'Path must still surface so user can verify it',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('surfaces verify-info banner when verify succeeded',
        (tester) async {
      await _pumpCard(
        tester,
        detection: const PlateSolverDetection(
          astapPath: r'C:\Program Files\astap\astap.exe',
          catalogName: 'V17',
          catalogMagnitudeLimit: 17.0,
          catalogPath: r'C:\Program Files\astap',
        ),
        verifyInfo: const PlateSolverInfo(
          path: r'C:\Program Files\astap\astap.exe',
          flavour: 'ASTAP',
          versionLine: 'ASTAP version 2024.05.10',
        ),
      );

      expect(
        find.textContaining('ASTAP version 2024.05.10'),
        findsOneWidget,
        reason: 'Verify banner must surface the binary version line',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('surfaces verify error when verify failed', (tester) async {
      await _pumpCard(
        tester,
        detection: const PlateSolverDetection(
          astapPath: r'C:\Program Files\astap\astap.exe',
          catalogName: 'V17',
          catalogMagnitudeLimit: 17.0,
          catalogPath: r'C:\Program Files\astap',
        ),
        verifyError: 'astap.exe exited with status 127',
      );

      expect(
        find.textContaining('astap.exe exited with status 127'),
        findsOneWidget,
        reason: 'Verify error must render verbatim so user can diagnose',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('PlateSolvingSettingsScreen empty states', () {
    testWidgets(
        'renders the 3-step quick-start beneath the banner when no solver '
        'is detected', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plateSolverDetectionProvider.overrideWith(
              (ref) async => const PlateSolverDetection(),
            ),
            plateSolverPreferenceProvider.overrideWith(
              (ref) async => const PlateSolverPreference(),
            ),
          ],
          child: MaterialApp(
            theme: NightshadeTheme.dark,
            home: const PlateSolvingSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      // Settle the FutureProviders that the screen awaits.
      await tester.pump(const Duration(milliseconds: 200));

      // The detection card itself surfaces "ASTAP not installed".
      expect(
        find.textContaining('ASTAP not installed'),
        findsOneWidget,
        reason: 'Detection banner still surfaces the missing-solver title',
      );

      // The new quick-start panel adds the three guided steps.
      expect(find.text('Get started in 3 steps'), findsOneWidget);
      expect(find.text('Install ASTAP'), findsOneWidget);
      expect(find.text('Download a star catalog'), findsOneWidget);
      expect(find.text('Click Re-scan'), findsOneWidget);
      expect(find.textContaining('V17 is recommended'), findsOneWidget);

      // Each step also exposes its own action button.
      expect(
        find.widgetWithText(NightshadeButton, 'Open ASTAP download page'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(NightshadeButton, 'Open ASTAP catalog page'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(NightshadeButton, 'Re-scan now'),
        findsOneWidget,
      );
    });

    testWidgets(
        'shows the catalog-missing hint with a "Browse for catalog '
        'directory" button when ASTAP is detected but no catalog',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 1400);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plateSolverDetectionProvider.overrideWith(
              (ref) async => const PlateSolverDetection(
                astapPath: r'C:\Program Files\astap\astap.exe',
              ),
            ),
            plateSolverPreferenceProvider.overrideWith(
              (ref) async => const PlateSolverPreference(
                catalogPath: r'C:\Program Files\astap',
              ),
            ),
          ],
          child: MaterialApp(
            theme: NightshadeTheme.dark,
            home: const PlateSolvingSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.textContaining(r'Searching for catalogs in C:\Program Files'),
        findsOneWidget,
        reason: 'Catalog hint must name the directory being probed',
      );
      expect(
        find.widgetWithText(
            NightshadeButton, 'Browse for catalog directory'),
        findsOneWidget,
      );
      // The three-step quick-start must NOT render when ASTAP is detected.
      expect(find.text('Get started in 3 steps'), findsNothing);
    });
  });

  group('PlateSolverChoice serialization', () {
    test('round-trips through serialized form', () {
      for (final choice in PlateSolverChoice.values) {
        final round = PlateSolverChoice.fromSerialized(choice.serialized);
        expect(round, choice);
      }
    });

    test('unknown values collapse to auto', () {
      expect(PlateSolverChoice.fromSerialized('nonsense'),
          PlateSolverChoice.auto);
      expect(PlateSolverChoice.fromSerialized(''), PlateSolverChoice.auto);
    });
  });

  group('PlateSolverDetection', () {
    test('hasAnySolver is false when nothing detected', () {
      const det = PlateSolverDetection();
      expect(det.hasAnySolver, false);
      expect(det.astapReady, false);
    });

    test('astapReady requires both executable and catalog', () {
      const noCatalog = PlateSolverDetection(astapPath: '/opt/astap/astap');
      expect(noCatalog.hasAnySolver, true);
      expect(noCatalog.astapReady, false);

      const ready = PlateSolverDetection(
        astapPath: '/opt/astap/astap',
        catalogPath: '/opt/astap',
      );
      expect(ready.astapReady, true);
    });
  });
}
