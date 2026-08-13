import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// The hover show-delay must be cancellable.
///
/// It used to be a bare `Future.delayed`, so a tooltip disposed mid-delay left
/// a live timer holding the state object. `flutter_test` fails a test that ends
/// with a pending timer, which is what pins this.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(body: Center(child: child)),
  );

  const trigger = Key('trigger');
  const anchor = ColoredBox(
    key: trigger,
    color: Color(0xFF224466),
    child: SizedBox(width: 60, height: 24),
  );

  Future<TestGesture> hover(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byKey(trigger)));
    await tester.pump();
    return gesture;
  }

  testWidgets('disposing mid-delay leaves no pending timer', (tester) async {
    await tester.pumpWidget(
      host(const NightshadeTooltip(message: 'Stack & Share', child: anchor)),
    );

    await hover(tester);
    // Part-way into the 300 ms wait, so the delay is still outstanding.
    await tester.pump(const Duration(milliseconds: 100));

    await tester.pumpWidget(host(const SizedBox()));
    // Test teardown asserts there is no timer left running.
  });

  testWidgets('leaving before the delay elapses never shows the tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const NightshadeTooltip(message: 'Stack & Share', child: anchor)),
    );

    final gesture = await hover(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveTo(Offset.zero);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Stack & Share'), findsNothing);
  });

  testWidgets('hovering past the delay still shows the tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const NightshadeTooltip(message: 'Stack & Share', child: anchor)),
    );

    await hover(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Stack & Share'), findsOneWidget);
  });
}
