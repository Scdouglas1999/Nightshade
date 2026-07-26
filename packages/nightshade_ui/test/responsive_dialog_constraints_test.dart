import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('desktop minimums shrink to fit a phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late BoxConstraints constraints;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            constraints = Responsive.dialogConstraints(
              context,
              preferredWidth: 560,
              preferredHeight: 480,
              minWidth: 400,
              minHeight: 500,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(constraints.minWidth, 324);
    expect(constraints.maxWidth, 324);
    expect(constraints.minHeight, 480);
    expect(constraints.maxHeight, 480);
  });

  testWidgets('minimums remain unchanged when the viewport has room', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late BoxConstraints constraints;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            constraints = Responsive.dialogConstraints(
              context,
              preferredWidth: 560,
              preferredHeight: 480,
              minWidth: 400,
              minHeight: 300,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(constraints.minWidth, 400);
    expect(constraints.maxWidth, 560);
    expect(constraints.minHeight, 300);
    expect(constraints.maxHeight, 480);
  });
}
