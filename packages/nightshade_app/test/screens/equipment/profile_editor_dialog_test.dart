import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/dialogs/profile_editor_dialog.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('new profile editor exposes its complete single-page form',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: ProfileEditorDialog(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('New Profile'), findsOneWidget);
    expect(find.text('Profile Identity'), findsOneWidget);
    expect(find.text('Optical Train'), findsOneWidget);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Camera Defaults'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save Changes'), findsOneWidget);
  });
}
