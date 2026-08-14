// Regression (D-4): an open right-docked panel must not cover the planetarium's
// time transport.
//
// Live evidence at a 900x900 window with the Layers drawer open: the drawer is
// pinned to the right edge from x=620, while the transport stayed centred on the
// FULL 900 px canvas at x 432-700. The result was a clock rendered `18:46:` with
// the seconds behind the drawer and a fast-forward button that could not be
// clicked at all, because the drawer took the pointer. No overlap at 1600x900,
// and none at 420x900 where the drawer becomes a full-width sheet — which is why
// this pins the mid width specifically.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/planetarium_screen.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The Layers/Plan drawer width the shell docks at 900 px
/// (`clampPanelWidth(900, fraction: 0.30, min: 280, max: 380)`).
const double _drawerWidth = 280;
const Size _window = Size(900, 900);

Future<void> _pumpSlot(WidgetTester tester, double dockedWidth) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: SizedBox(
              width: _window.width,
              height: _window.height,
              child: Stack(
                children: [
                  PlanetariumTransportSlot(
                    colors: NightshadeColors.of(context),
                    compact: false,
                    dockedWidth: dockedWidth,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the transport clears an open drawer at 900 px', (tester) async {
    tester.view.physicalSize = _window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSlot(tester, _drawerWidth);

    final transport = tester.getRect(find.byType(TimeControlPanel));
    expect(
      transport.right,
      lessThanOrEqualTo(_window.width - _drawerWidth),
      reason: 'the fast-forward button sat behind the drawer and could not be '
          'clicked',
    );
    expect(transport.width, greaterThan(0));
  });

  testWidgets(
      'with no drawer open the transport is centred on the whole '
      'canvas', (tester) async {
    tester.view.physicalSize = _window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpSlot(tester, 0);

    final transport = tester.getRect(find.byType(TimeControlPanel));
    expect(
      transport.center.dx,
      closeTo(_window.width / 2, 1.0),
      reason: 'the inset is load-bearing, not a constant shift',
    );
  });
}
