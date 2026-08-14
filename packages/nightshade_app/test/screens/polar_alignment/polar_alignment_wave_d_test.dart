// Wave D re-drive of the polar-alignment screen: three surfaces that
// contradicted each other on the SAME screenshot.
//
//  * IMG-13 — the status headline read "Slewing to point 1 of 3" while the
//    detail line and the footer read "Slewing to point 2...". The mount was
//    moving to point 2, so the headline was the one that was wrong.
//  * IMG-16 — after a completed run the bullseye printed "No measurement yet"
//    and put the marker back at dead centre, while the row directly beneath it
//    read Azimuth 3.2" · Altitude 0.6" · Total 3.2".
//  * ND-3 — that same card showed a green "Alignment Complete — Final error:
//    3.2"" beside a red "Worse" chip, with Before and After both rendering
//    3.2": a verdict graded off a hundredth of an arcsecond, below the
//    resolution either number is printed at.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/screens/polar_alignment/polar_alignment_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/pump_app_screen.dart';

class _FixedAlignmentNotifier extends PolarAlignmentStateNotifier {
  _FixedAlignmentNotifier(super.ref, PolarAlignmentState fixed) {
    // ignore: invalid_use_of_protected_member
    state = fixed;
  }
}

class _SiteSettings extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async =>
      const AppSettingsState(latitude: 40, longitude: -75);
}

const _config = PolarAlignmentConfig(autoCompleteThreshold: 30.0);

PolarAlignmentError _error({
  required double azimuth,
  required double altitude,
  required double total,
}) =>
    PolarAlignmentError(
      azimuthError: azimuth,
      altitudeError: altitude,
      totalError: total,
      currentRa: 0,
      currentDec: 89,
      targetRa: 0,
      targetDec: 90,
      timestamp: DateTime(2026, 8, 13, 22, 53),
    );

/// The run from `shots/s42-tppa-done.png`, to the numbers on the screenshot.
PolarAlignmentState get _completedRun => PolarAlignmentState(
      phase: PolarAlignPhase.complete,
      config: _config,
      startedAt: DateTime(2026, 8, 13, 22, 52),
      statusMessage: 'Complete! Error 3.2" below threshold for 3s',
      initialError: _error(azimuth: 3.14, altitude: 0.54, total: 3.19),
      currentError: _error(azimuth: 3.16, altitude: 0.61, total: 3.22),
    );

GoRouter _router() => GoRouter(
      initialLocation: '/polar-alignment',
      routes: [
        GoRoute(
          path: '/polar-alignment',
          builder: (_, __) => const PolarAlignmentScreen(),
        ),
      ],
    );

Future<void> _pumpScreen(
  WidgetTester tester,
  PolarAlignmentState alignmentState,
) async {
  await pumpAppScreen(
    tester,
    MaterialApp.router(
      theme: NightshadeTheme.dark,
      routerConfig: _router(),
    ),
    size: const Size(1400, 900),
    settle: false,
    extraOverrides: [
      appSettingsProvider.overrideWith(_SiteSettings.new),
      polarAlignmentStateProvider.overrideWith(
        (ref) => _FixedAlignmentNotifier(ref, alignmentState),
      ),
    ],
  );
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the slew headline names the point being slewed to',
      (tester) async {
    await _pumpScreen(
      tester,
      PolarAlignmentState(
        phase: PolarAlignPhase.measuring,
        config: _config,
        startedAt: DateTime(2026, 8, 13, 22, 52),
        // Exactly what the run published at the instant the audit sampled it:
        // the message names point 2, `currentPoint` still holds the point that
        // has been MEASURED.
        statusMessage: 'Slewing to point 2...',
        currentPoint: 1,
      ),
    );

    expect(find.text('Slewing to point 2 of 3'), findsOneWidget);
    expect(
      find.text('Slewing to point 1 of 3'),
      findsNothing,
      reason: 'the headline named the point behind the one the mount is '
          'moving to, beside a detail line naming the right one',
    );
  });

  testWidgets('a completed run plots its measurement instead of denying it',
      (tester) async {
    await _pumpScreen(tester, _completedRun);

    expect(
      find.text('No measurement yet'),
      findsNothing,
      reason: 'the run finished with a 3.2" result printed on the same screen',
    );
    // The numeric row it contradicted is still there.
    expect(find.text('Total'), findsOneWidget);
    expect(find.textContaining('3.2"'), findsWidgets);
  });

  testWidgets('a change below the displayed resolution is not "Worse"',
      (tester) async {
    await _pumpScreen(tester, _completedRun);

    expect(find.text('Alignment Complete'), findsOneWidget);
    expect(
      find.text('Worse'),
      findsNothing,
      reason: '0.03" is below the tenth of an arcsecond both numbers are '
          'printed at, so grading it a regression contradicts the headline',
    );
    expect(find.text('No change'), findsOneWidget);
  });

  testWidgets('a real regression is still called Worse', (tester) async {
    await _pumpScreen(
      tester,
      PolarAlignmentState(
        phase: PolarAlignPhase.complete,
        config: _config,
        startedAt: DateTime(2026, 8, 13, 22, 52),
        initialError: _error(azimuth: 3.1, altitude: 0.5, total: 3.2),
        currentError: _error(azimuth: 12.0, altitude: 4.0, total: 12.6),
      ),
    );

    expect(find.text('Worse'), findsOneWidget);
  });
}
