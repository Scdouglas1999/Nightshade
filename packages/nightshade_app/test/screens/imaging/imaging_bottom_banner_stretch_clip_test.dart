// The banner MEASURES its natural width and scrolls only when it genuinely does
// not fit. No dp threshold can be right: with auto-stretch ON the trailing
// cluster grows by a method dropdown plus the advanced-settings icon button, and
// whether the intrinsically-sized children fit depends on runtime content (stats
// text, filter names, locale, text scale). Above a wrong threshold the fixed
// children overflow the wide Row and the advanced-settings button is
// hard-clipped to a sliver that still swallows clicks, with no scroll to recover
// it.
//
// The sweep below covers the widths that actually overflow; widths already in
// the scrolling branch cannot catch this.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/imaging/widgets/imaging_bottom_banner.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _StretchOn extends AutoStretchSettingsNotifier {
  _StretchOn(super.ref) {
    state = state.copyWith(enabled: true);
  }
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required double width,
  required bool stretchEnabled,
}) async {
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
    size: Size(width + 200, 700),
    settle: false,
    extraOverrides: [
      if (stretchEnabled)
        autoStretchSettingsProvider.overrideWith(_StretchOn.new),
    ],
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // The band the audit measured, plus its edges.
  for (final width in const [740.0, 760.0, 780.0, 800.0, 816.0]) {
    testWidgets('auto-stretch on at ${width.toInt()} dp does not clip',
        (tester) async {
      await _pumpBanner(tester, width: width, stretchEnabled: true);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the banner must not overflow at $width dp',
      );
      // The advanced-settings button exists and can be brought fully inside
      // the bar. In the wide branch it was sliced by the right edge with no
      // way to reveal it; here scrolling recovers it completely.
      final settingsIcon = find.descendant(
        of: find.byType(ImagingBottomBanner),
        matching: find.byIcon(NightshadeIcons.settings2),
      );
      expect(settingsIcon, findsOneWidget);
      await tester.scrollUntilVisible(
        settingsIcon,
        -120,
        scrollable: find.descendant(
          of: find.byType(ImagingBottomBanner),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump();
      final banner = tester.getRect(find.byType(ImagingBottomBanner));
      final icon = tester.getRect(settingsIcon);
      expect(
        icon.left >= banner.left - 0.5 && icon.right <= banner.right + 0.5,
        isTrue,
        reason: 'the advanced-stretch button stays clipped by the bar edge: '
            '$icon vs $banner',
      );
    });
  }

  // The widths that actually overflowed, measured on the real ImagingScreen:
  // with stretch ON the wide branch needed ~1004 dp inner and overflowed at 920,
  // 940, 960 and 1000 dp; with stretch OFF it still overflowed at 820 dp. A
  // hardcoded threshold is what let these through.
  for (final width in const [820.0, 920.0, 940.0, 960.0, 1000.0, 1280.0]) {
    for (final stretchEnabled in const [true, false]) {
      final label = stretchEnabled ? 'on' : 'off';
      testWidgets(
          'auto-stretch $label at ${width.toInt()} dp does not overflow',
          (tester) async {
        await _pumpBanner(
          tester,
          width: width,
          stretchEnabled: stretchEnabled,
        );

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the banner overflowed at $width dp with auto-stretch $label; '
              'a threshold-based fork is what made this width-dependent',
        );

        // Every trailing control must be inside the bar, reachable, at every
        // width — scrolling if need be, but never sliced by the edge.
        final trailing = find.descendant(
          of: find.byType(ImagingBottomBanner),
          matching: find.text('Stretch'),
        );
        expect(trailing, findsOneWidget);
        final scrollable = find.descendant(
          of: find.byType(ImagingBottomBanner),
          matching: find.byType(Scrollable),
        );
        if (scrollable.evaluate().isNotEmpty) {
          await tester.scrollUntilVisible(trailing, -120,
              scrollable: scrollable);
          await tester.pump();
        }
        final banner = tester.getRect(find.byType(ImagingBottomBanner));
        final rect = tester.getRect(trailing);
        expect(
          rect.left >= banner.left - 0.5 && rect.right <= banner.right + 0.5,
          isTrue,
          reason: 'trailing control clipped by the bar edge at $width dp '
              '(stretch $label): $rect vs $banner',
        );
      });
    }
  }

  testWidgets('auto-stretch off has no advanced button to clip at 740 dp',
      (tester) async {
    await _pumpBanner(tester, width: 740, stretchEnabled: false);

    expect(tester.takeException(), isNull);
    // The narrower trailing cluster is why 720 dp was ever a sufficient
    // threshold: with auto-stretch off the method dropdown and the advanced
    // button do not exist, so nothing can be clipped and the wide layout is
    // still the right choice at this width.
    expect(
      find.descendant(
        of: find.byType(ImagingBottomBanner),
        matching: find.byIcon(NightshadeIcons.settings2),
      ),
      findsNothing,
    );
    expect(find.text('Stretch'), findsOneWidget);
  });
}
