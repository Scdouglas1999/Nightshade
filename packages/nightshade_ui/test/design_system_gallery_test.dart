import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  Future<void> pumpGallery(
    WidgetTester tester, {
    required ThemeData theme,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(theme: theme, home: const NightshadeDesignSystemGallery()),
    );
    await tester.pump();
  }

  testWidgets('renders core component gallery in dark theme', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.dark,
      size: const Size(1280, 1500),
    );

    expect(find.text('Design System Gallery'), findsOneWidget);
    expect(find.text('Color Palette'), findsOneWidget);
    expect(find.text('Typography'), findsOneWidget);
    expect(find.text('Telemetry Lg — Hero live values'), findsOneWidget);
    expect(find.text('Buttons'), findsOneWidget);
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Status Dots'), findsOneWidget);
    // Every remaining section is a component from 05; the pre-Observatory
    // ones (Cards, the pill Tabs, Navigation, Decorations, the old chips and
    // Alerts) are gone, and the sheet's own sections are what the gallery
    // shows in their place.
    expect(find.text('Cards'), findsNothing);
    expect(find.text('Tabs'), findsNothing);
    expect(find.text('Navigation'), findsNothing);
    expect(find.text('Decorations'), findsNothing);
    expect(find.text('Chips and Status Pills'), findsNothing);
    expect(find.text('Alerts'), findsNothing);
    expect(find.text('Panels and wells'), findsOneWidget);
    expect(find.text('Readouts'), findsOneWidget);
    expect(find.text('Underline tabs'), findsOneWidget);
    expect(find.text('Chips and status dots'), findsOneWidget);
    expect(find.text('Banner'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-button-primary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gallery-dropdown')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-instrument-pill')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders compact width without build errors', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.light,
      size: const Size(390, 900),
    );

    expect(find.text('Buttons'), findsOneWidget);
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Banner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders red night theme gallery', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.redNight,
      size: const Size(900, 900),
    );

    expect(find.text('Chips and status dots'), findsOneWidget);
    expect(find.text('Night band'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery controls update representative states', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.dark,
      size: const Size(1280, 2200),
    );

    expect(find.text('Sample actions: 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-button-primary')));
    await tester.pump();
    expect(find.text('Sample actions: 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-button-secondary')));
    await tester.pump();
    expect(find.text('Sample actions: 2'), findsOneWidget);

    expect(
      tester
          .widget<NightshadeDropdown>(
            find.byKey(const ValueKey('gallery-dropdown')),
          )
          .value,
      'Camera',
    );
    // `pump`, never `pumpAndSettle`: the gallery renders a shimmer, which by
    // design never settles. The extra frame is the popover's 120ms fade.
    await tester.tap(find.byKey(const ValueKey('gallery-dropdown')));
    await tester.pump();
    await tester.pump(NightshadeTokens.durationSmooth);
    await tester.tap(find.text('Mount').last);
    await tester.pump();
    await tester.pump(NightshadeTokens.durationSmooth);
    expect(
      tester
          .widget<NightshadeDropdown>(
            find.byKey(const ValueKey('gallery-dropdown')),
          )
          .value,
      'Mount',
    );

    expect(
      tester.widget<NightshadeCheckbox>(find.byType(NightshadeCheckbox)).value,
      isTrue,
    );
    await tester.tap(find.byType(NightshadeCheckbox));
    await tester.pump();
    expect(
      tester.widget<NightshadeCheckbox>(find.byType(NightshadeCheckbox)).value,
      isFalse,
    );

    expect(
      tester
          .widget<NightshadeSwitch>(
            find.byKey(const ValueKey('gallery-switch')),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('gallery-switch')));
    await tester.pump();
    expect(
      tester
          .widget<NightshadeSwitch>(
            find.byKey(const ValueKey('gallery-switch')),
          )
          .value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
