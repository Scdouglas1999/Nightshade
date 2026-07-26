import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/glance_mode_toggle.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _FailingGlanceModeNotifier extends GlanceModeNotifier {
  _FailingGlanceModeNotifier(super.ref);

  @override
  Future<void> toggle() => Future<void>.error(StateError('write failed'));
}

void main() {
  testWidgets('failed persistence is reported and leaves the toggle off',
      (tester) async {
    late _FailingGlanceModeNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          glanceModeProvider.overrideWith((ref) {
            notifier = _FailingGlanceModeNotifier(ref);
            return notifier;
          }),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => GlanceModeToggle(
                colors: NightshadeColors.of(context),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(GlanceModeToggle));
    await tester.pumpAndSettle();

    expect(
        find.text('Could not save the Glance mode setting.'), findsOneWidget);
    expect(notifier.state, isFalse);
  });
}
