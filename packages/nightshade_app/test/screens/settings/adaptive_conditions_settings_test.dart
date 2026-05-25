import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/adaptive_conditions_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._initial);

  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

Future<void> _openAdaptiveConditions(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Adaptive Conditions'),
    240,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text('Adaptive Conditions').first);
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'tapping_adaptive_conditions_renders_widget: the sidebar entry maps '
      'to AdaptiveConditionsSettings', (tester) async {
    await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(const AppSettingsState()),
        ),
      ],
    );

    await _openAdaptiveConditions(tester);

    expect(find.byType(AdaptiveConditionsSettings), findsOneWidget);
  });

  testWidgets(
      'adaptive_conditions_controls_update_existing_settings: changing '
      'defaults persists through AppSettingsNotifier setters', (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(const AppSettingsState()),
        ),
      ],
    );

    await _openAdaptiveConditions(tester);

    expect(find.text('Enabled for new schedulers'), findsOneWidget);
    expect(find.text('Score floor'), findsOneWidget);
    expect(find.text('Swap hysteresis'), findsOneWidget);
    expect(find.text('Transparency weight'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('adaptiveSwapEnabledToggle')));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('adaptiveSwapThresholdInput')),
      '62',
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('adaptiveSwapTransparencyWeightInput')),
      '0.55',
    );
    await tester.pumpAndSettle();

    final state = handle.container.read(appSettingsProvider).value;
    expect(state, isNotNull);
    expect(state!.adaptiveSwapEnabledByDefault, isTrue);
    expect(state.adaptiveSwapDefaultThreshold, 62.0);
    expect(state.conditionsScoreWeights['transparency'], 0.55);
  });
}
