// The Imaging capture bar at a NARROW window, with the rig the operator
// actually had connected.
//
// At 900x900 with a filter wheel and stats — the two clusters that consume the
// width — the bar is cut after `Dur 2 s`: the gain chip, all seven filter chips
// and the Stretch toggle sit past the right edge with no scrollbar, arrow or
// overflow affordance, and the filter chips drop out of the accessibility tree
// entirely. Nothing logs `RenderFlex overflowed` for it, and a width sweep that
// pumps the bar with NO filter wheel and no stats never reproduces it.
//
// At that width the trailing controls must also still publish their role and
// enabled state: undeclared, the gain chip reports [DISABLED] while live, and
// Loop / Snapshot expose as panels rather than buttons.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/imaging_bottom_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _ConnectedWheel extends FilterWheelStateNotifier {
  _ConnectedWheel(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = const FilterWheelState(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'sim_filterwheel_1',
      deviceName: 'Simulated Filter Wheel',
      currentPosition: 4,
      filterNames: ['L', 'R', 'G', 'B', 'Ha', 'OIII', 'SII'],
    );
  }
}

class _ConnectedCamera extends CameraStateNotifier {
  _ConnectedCamera(super.ref) {
    // ignore: invalid_use_of_protected_member
    state = state.copyWith(
      connectionState: DeviceConnectionState.connected,
      deviceId: 'sim_camera_1',
      deviceName: 'Simulated Camera',
      temperature: -10,
    );
  }
}

Future<void> _pumpBanner(WidgetTester tester, double width) async {
  await pumpAppScreen(
    tester,
    Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        width: width,
        child: Builder(
          builder: (context) => ImagingBottomBanner(
            colors: context.nightshadeColors,
            isLooping: false,
            isSingleCapture: false,
            isSavingCapture: false,
            isStoppingCapture: false,
            onSnapshot: () {},
            onToggleLoop: () {},
          ),
        ),
      ),
    ),
    size: Size(width, 900),
    settle: false,
    extraOverrides: <Override>[
      filterWheelStateProvider.overrideWith(_ConnectedWheel.new),
      cameraStateProvider.overrideWith(_ConnectedCamera.new),
    ],
  );
  await tester.pump(const Duration(milliseconds: 50));
}

/// The bar's own horizontal scroll view.
Finder get _bannerScrollable => find
    .descendant(
      of: find.byType(ImagingBottomBanner),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in const [900.0, 820.0, 760.0]) {
    testWidgets(
      'every control is reachable at ${width.toInt()} dp with 7 filters',
      (tester) async {
        await _pumpBanner(tester, width);
        expect(tester.takeException(), isNull);

        final banner = tester.getRect(find.byType(ImagingBottomBanner));

        // The two ends of the bar and the clusters the finding named: the
        // gain chip, the last filter, and the stretch toggle.
        for (final target in <Finder>[
          find.textContaining('G100'),
          find.text('SII'),
          find.text('Stretch'),
        ]) {
          expect(
            target,
            findsWidgets,
            reason: 'control missing from the bar at $width dp',
          );
          await tester.scrollUntilVisible(
            target.first,
            -160,
            scrollable: _bannerScrollable,
          );
          await tester.pump();
          final rect = tester.getRect(target.first);
          expect(
            rect.left >= banner.left - 0.5 && rect.right <= banner.right + 0.5,
            isTrue,
            reason: 'control still outside the bar after scrolling at '
                '$width dp: $rect vs $banner',
          );
        }
      },
    );
  }

  testWidgets('the bar scrolls rather than hiding controls at 900 dp',
      (tester) async {
    await _pumpBanner(tester, 900);

    final scrollable = _bannerScrollable;
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'with seven filters at 900 dp the bar does not fit, so it must '
          'offer scroll extent instead of laying controls out past its edge',
    );
    expect(position.axis, Axis.horizontal);

    // Reachable is not discoverable: the bar scrolled silently, so a
    // screenshot of it read as "cut off with no affordance". The scrollbar is
    // the affordance.
    expect(
      find.descendant(
        of: find.byType(ImagingBottomBanner),
        matching: find.byType(Scrollbar),
      ),
      findsOneWidget,
      reason: 'the capture bar must show that it scrolls',
    );
  });

  testWidgets('the capture and gain controls publish button semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBanner(tester, 900);

    // Snapshot and Loop are buttons, not panels.
    for (final label in const ['Snapshot', 'Loop']) {
      expect(
        find.bySemanticsLabel(label),
        findsWidgets,
        reason: '$label must be reachable by its label',
      );
      final node = tester.getSemantics(find.bySemanticsLabel(label).first);
      expect(
        node.hasFlag(SemanticsFlag.isButton),
        isTrue,
        reason: '$label reached assistive tech as a panel, not a button',
      );
      expect(
        node.hasFlag(SemanticsFlag.hasEnabledState) &&
            node.hasFlag(SemanticsFlag.isEnabled),
        isTrue,
        reason: '$label is live with the camera connected and must say so',
      );
    }

    // The gain chip opens the exposure popover; it reported [DISABLED].
    final gain = find.bySemanticsLabel(RegExp('Exposure settings'));
    expect(gain, findsWidgets);
    final gainNode = tester.getSemantics(gain.first);
    expect(
      gainNode.hasFlag(SemanticsFlag.hasEnabledState) &&
          gainNode.hasFlag(SemanticsFlag.isEnabled),
      isTrue,
      reason: 'the gain chip is live — it must not publish as disabled',
    );

    handle.dispose();
  });

  testWidgets('the active filter is published as selected', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpBanner(tester, 1400);

    final active = tester.getSemantics(find.text('Ha').first);
    expect(
      active.hasFlag(SemanticsFlag.hasSelectedState) &&
              active.hasFlag(SemanticsFlag.isSelected) ||
          active.hasFlag(SemanticsFlag.isChecked),
      isTrue,
      reason: 'with Ha in the beam the tree gave a screen reader no way to '
          'know which filter was selected',
    );

    handle.dispose();
  });
}
