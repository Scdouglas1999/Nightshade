// A device class that discovery found nothing for has to say the same amount
// as one it did.
//
// Live finding: cover calibrators and switches — the two classes with no
// simulator — collapsed to a bare italic "No switches found" line with a
// refresh icon, while every other class got a titled section and an "N found"
// count. Nothing on screen said which backends had been asked, whether any of
// them had errored, or how to add a device that lives on another machine —
// even though the app log recorded "Discovery complete for Switch: 0 devices,
// 0 backend errors".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/widgets/discovery_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// Pins the discovery state so the section chrome can be asserted without
/// running a real scan.
class _StubDiscoveryNotifier extends UnifiedDiscoveryNotifier {
  _StubDiscoveryNotifier(super.ref, UnifiedDiscoveryState seed) {
    state = seed;
  }
}

UnifiedDiscoveryState _scannedNothing() {
  return UnifiedDiscoveryState(
    backendStates: {
      DriverType.native: BackendDiscoveryState(
        backend: DriverType.native,
        status: DiscoveryStatus.completed,
        completedAt: DateTime(2026, 8, 4, 21),
      ),
      DriverType.indi: const BackendDiscoveryState(
        backend: DriverType.indi,
        status: DiscoveryStatus.error,
        error: 'INDI server connection failed',
      ),
    },
  );
}

Future<void> _pumpExpandedPanel(WidgetTester tester) async {
  await pumpAppScreen(
    tester,
    const SingleChildScrollView(child: DiscoveryPanel()),
    size: const Size(1280, 1600),
    settle: false,
    extraOverrides: [
      unifiedDiscoveryProvider.overrideWith(
        (ref) => _StubDiscoveryNotifier(ref, _scannedNothing()),
      ),
    ],
  );
  await tester.pump();
  await tester.tap(find.text('Expand'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a class with no results keeps the section chrome and a count',
      (tester) async {
    await _pumpExpandedPanel(tester);

    expect(find.text('SWITCHES'), findsOneWidget);
    expect(find.text('COVER / CALIBRATORS'), findsOneWidget);
    // Every class reports a count, including the empty ones.
    expect(find.text('0 found'), findsWidgets);
  });

  testWidgets('an empty class names the backends it searched and which failed',
      (tester) async {
    await _pumpExpandedPanel(tester);

    // Enum-declaration order (ascom, alpaca, indi, native, simulator) so the
    // list is stable between scans rather than following map insertion.
    expect(find.text('Searched: INDI (failed), Native'), findsWidgets);
    expect(
      find.textContaining('Settings → Connection'),
      findsWidgets,
      reason: 'a class with nothing found must offer a route to adding one',
    );
  });

  // The empty-class header is the widest this Row ever gets: icon + the
  // longest class name + the count + the rescan button. Before the `Expanded`
  // around the title it overflowed a 360dp phone by 24px — and every other
  // test in this file runs at 1280, where it fitted either way.
  testWidgets('the empty-class section fits a 360dp phone', (tester) async {
    await pumpAppScreen(
      tester,
      const SingleChildScrollView(child: DiscoveryPanel()),
      size: const Size(360, 1600),
      settle: false,
      extraOverrides: [
        unifiedDiscoveryProvider.overrideWith(
          (ref) => _StubDiscoveryNotifier(ref, _scannedNothing()),
        ),
      ],
    );
    await tester.pump();
    // Below the phone breakpoint the header drops its "Expand" label, so the
    // header itself is the expand affordance.
    await tester.tap(find.text('DISCOVERY'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.takeException(),
      isNull,
      reason: 'the empty-class header must not overflow at phone width',
    );
    // And the chrome the fix is about is actually on screen at this width.
    expect(find.text('COVER / CALIBRATORS'), findsOneWidget);
    expect(find.byTooltip('Scan for switches'), findsOneWidget);
  });
}
