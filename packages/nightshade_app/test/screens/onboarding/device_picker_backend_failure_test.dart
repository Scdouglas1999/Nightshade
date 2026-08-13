// SET-1: on step 3 of the first run, the backend row rendered a green
// "Native (0)" beside a bare red warning chip for Alpaca and another for INDI —
// no count, no message, nothing clickable, and the accessibility tree carried
// only "panel: Alpaca", so the alarm was invisible to a screen reader too. Two
// unexplained red warnings on the third screen of the product.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/camera_step.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/pump_app_screen.dart';

/// Discovery parked with Native complete and Alpaca failed, the shape the
/// finding was observed in.
class _MixedDiscoveryNotifier extends UnifiedDiscoveryNotifier {
  _MixedDiscoveryNotifier(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = UnifiedDiscoveryState(
      backendStates: {
        DriverType.native: const BackendDiscoveryState(
          backend: DriverType.native,
          status: DiscoveryStatus.completed,
        ),
        DriverType.alpaca: const BackendDiscoveryState(
          backend: DriverType.alpaca,
          status: DiscoveryStatus.error,
          error: 'No Alpaca server answered on this network',
        ),
      },
    );
  }

  @override
  Future<void> discoverAll({
    bool includeIndi = true,
    bool includeAlpaca = true,
  }) async {}
}

void main() {
  testWidgets('a failed backend states its reason on screen and to AT',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAppScreen(
      tester,
      const OnboardingCameraStep(),
      size: const Size(1280, 900),
      extraOverrides: [
        unifiedDiscoveryProvider.overrideWith(_MixedDiscoveryNotifier.new),
      ],
      settle: false,
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.textContaining('No Alpaca server answered on this network'),
      findsWidgets,
      reason: 'a red chip whose only explanation is a hover tooltip is an '
          'unexplained alarm',
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'Alpaca: nothing answered — No Alpaca server answered'),
      ),
      findsWidgets,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Native: scan complete, 0 found')),
      findsOneWidget,
      reason: 'a clean backend must be distinguishable from a failed one',
    );

    handle.dispose();
  });
}
