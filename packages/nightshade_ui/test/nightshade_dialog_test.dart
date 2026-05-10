import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Future<void> _showDialog(WidgetTester tester, Widget dialog) async {
  await tester.pumpWidget(MaterialApp(
    theme: NightshadeTheme.dark,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => dialog,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders title, icon, body content', (tester) async {
    await _showDialog(
        tester,
        const NightshadeDialog(
          title: 'Settings',
          icon: LucideIcons.settings,
          child: Text('Body content goes here'),
        ));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Body content goes here'), findsOneWidget);
    expect(find.byIcon(LucideIcons.settings), findsOneWidget);
  });

  testWidgets('close button pops route by default', (tester) async {
    await _showDialog(
        tester,
        const NightshadeDialog(
          title: 'Settings',
          child: Text('Body'),
        ));
    expect(find.byType(NightshadeDialog), findsOneWidget);

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(find.byType(NightshadeDialog), findsNothing);
  });

  testWidgets('close button calls onClose when provided', (tester) async {
    var calls = 0;
    await _showDialog(
        tester,
        NightshadeDialog(
          title: 'Settings',
          onClose: () => calls++,
          child: const Text('Body'),
        ));

    await tester.tap(find.byIcon(LucideIcons.x));
    await tester.pumpAndSettle();
    expect(calls, 1);
    // onClose owns lifecycle — dialog should still be visible.
    expect(find.byType(NightshadeDialog), findsOneWidget);
  });

  testWidgets('actions slot renders provided widgets', (tester) async {
    await _showDialog(
        tester,
        NightshadeDialog(
          title: 'Confirm',
          actions: [
            NightshadeButton(
                label: 'Cancel',
                variant: ButtonVariant.outline,
                onPressed: () {}),
            NightshadeButton(label: 'OK', onPressed: () {}),
          ],
          child: const Text('Are you sure?'),
        ));

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('hideCloseButton hides the close icon', (tester) async {
    await _showDialog(
        tester,
        const NightshadeDialog(
          title: 'No close',
          showCloseButton: false,
          child: Text('Body'),
        ));
    expect(find.byIcon(LucideIcons.x), findsNothing);
  });

  testWidgets('close button has accessible semantics', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await _showDialog(
          tester,
          const NightshadeDialog(
            title: 'A11y',
            child: Text('Body'),
            closeButtonSemanticsLabel: 'Dismiss settings',
          ));

      // Locate the explicit Semantics wrapper we added around the close
      // IconButton — the tooltip and the wrapper both surface 'Dismiss
      // settings', but we want to assert the wrapper's button flag.
      final semantics = tester.getSemantics(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Dismiss settings',
        ),
      );
      expect(semantics.flagsCollection.isButton, isTrue);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('body is scrollable when content overflows', (tester) async {
    tester.view.physicalSize = const Size(800, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _showDialog(
        tester,
        NightshadeDialog(
          title: 'Tall',
          height: 320,
          child: Column(
            children: List.generate(
              20,
              (i) => SizedBox(height: 40, child: Text('Row $i')),
            ),
          ),
        ));

    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
