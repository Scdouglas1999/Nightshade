import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/widgets/autofocus_progress_overlay.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../harness/pump_app_screen.dart';

/// Regression cover for the defect that stopped the whole app from ever idling.
///
/// [AutofocusProgressOverlay] is mounted once in the app shell, so it is alive
/// on every screen for the entire session and its State is never disposed. It
/// used to call `_pulseController.repeat(reverse: true)` unconditionally in
/// `initState`, which re-scheduled a frame on every vsync from launch to quit —
/// measured natively at ~45 frames per second while completely idle, with the
/// GPU 2% busy and nothing to draw. The pulse it was animating is only ever
/// built while an autofocus run is actually in progress.
///
/// The invariant these tests pin: the overlay animates when, and only when,
/// there is a live autofocus run to animate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'the shell-mounted overlay lets the app idle when no autofocus '
      'is running', (tester) async {
    await pumpAppScreen(
      tester,
      const Stack(children: [AutofocusProgressOverlay()]),
      settle: false,
    );

    await _expectIdlesAtRest(tester, 'an idle AutofocusProgressOverlay');
  });

  testWidgets('the overlay still idles after an autofocus run finishes',
      (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const Stack(children: [AutofocusProgressOverlay()]),
      settle: false,
    );

    final overlay = handle.container.read(autofocusOverlayProvider.notifier)
      ..onAutofocusStarted()
      ..toggleMinimized();
    await tester.pump();
    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason: 'The overlay must still pulse during a live autofocus run — '
          'gating the animation on real state must not remove the animation.',
    );

    overlay.dismiss();
    await _expectIdlesAtRest(
      tester,
      'an AutofocusProgressOverlay after the run ended',
    );
  });
}

/// Fails unless the tree has genuinely come to rest — nothing is animating and
/// nothing has asked for another frame.
Future<void> _expectIdlesAtRest(WidgetTester tester, String what) async {
  const explanation =
      'This means a widget is animating at rest. A running Ticker schedules a '
      'frame on every vsync, so the app never idles and EVERY screen renders '
      'at a degraded framerate — find the running Ticker and gate it on real '
      'state (see OnScreenAnimationGate in nightshade_ui).';

  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  } on FlutterError {
    fail('$what never stopped scheduling frames. $explanation');
  }

  expect(
    tester.binding.transientCallbackCount,
    0,
    reason: '$what left a frame callback registered after settling. '
        '$explanation',
  );
  expect(
    tester.binding.hasScheduledFrame,
    isFalse,
    reason: '$what still has a frame scheduled after settling. $explanation',
  );
}
