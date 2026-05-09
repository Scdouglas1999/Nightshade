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
      MaterialApp(
        theme: theme,
        home: const NightshadeDesignSystemGallery(),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders core component gallery in dark theme', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.dark,
      size: const Size(1280, 1000),
    );

    expect(find.text('Design System Gallery'), findsOneWidget);
    expect(find.text('Buttons'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Inputs'), findsOneWidget);
    expect(find.text('Tabs'), findsOneWidget);
    expect(find.text('Chips and Status Pills'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('gallery-button-primary')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-dropdown')), findsOneWidget);
    expect(find.byKey(const ValueKey('gallery-status-active')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('gallery-status-success')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('gallery-status-inactive')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gallery-alert-info')), findsOneWidget);
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
    expect(find.text('Alerts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders red night theme gallery', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.redNight,
      size: const Size(900, 900),
    );

    expect(find.text('Chips and Status Pills'), findsOneWidget);
    expect(find.text('Self-test complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery controls update representative states', (tester) async {
    await pumpGallery(
      tester,
      theme: NightshadeTheme.dark,
      size: const Size(1280, 1000),
    );

    expect(find.text('Sample actions: 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-button-primary')));
    await tester.pump();
    expect(find.text('Sample actions: 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gallery-status-active')));
    await tester.pump();
    expect(find.text('Sample actions: 2'), findsOneWidget);

    await tester.tap(find.widgetWithText(NightshadeButton, 'View'));
    await tester.pump();
    expect(find.text('Sample actions: 3'), findsOneWidget);

    expect(
      tester
          .widget<SubTabButton>(
            find.widgetWithText(SubTabButton, 'Guiding'),
          )
          .isSelected,
      isFalse,
    );
    await tester.tap(find.widgetWithText(SubTabButton, 'Guiding'));
    await tester.pump();
    expect(
      tester
          .widget<SubTabButton>(
            find.widgetWithText(SubTabButton, 'Guiding'),
          )
          .isSelected,
      isTrue,
    );

    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
          .value,
      'Camera',
    );
    await tester.tap(find.byKey(const ValueKey('gallery-dropdown')));
    await tester.pump();
    await tester.tap(find.text('Mount').last);
    await tester.pump();
    expect(
      tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
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
      tester.widget<NightshadeSwitch>(find.byType(NightshadeSwitch)).value,
      isTrue,
    );
    await tester.tap(find.byType(NightshadeSwitch));
    await tester.pump();
    expect(
      tester.widget<NightshadeSwitch>(find.byType(NightshadeSwitch)).value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });
}
