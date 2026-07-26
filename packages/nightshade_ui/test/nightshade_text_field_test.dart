import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    theme: NightshadeTheme.dark,
    home: Scaffold(body: child),
  );

  testWidgets('exposes keyboard privacy controls', (tester) async {
    await tester.pumpWidget(
      wrap(
        const NightshadeTextField(autocorrect: false, enableSuggestions: false),
      ),
    );

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  testWidgets('obscured fields disable correction and suggestions by default', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const NightshadeTextField(obscureText: true)));

    final field = tester.widget<EditableText>(find.byType(EditableText));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });
}
