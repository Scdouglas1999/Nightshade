import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/adaptive_conditions_settings.dart';
import 'package:nightshade_app/widgets/tutorial_keys/settings_keys.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// The sidebar's scrollable (the keyed grouped ListView).
Finder get _sidebar => find.descendant(
      of: find.byKey(SettingsTutorialKeys.categories),
      matching: find.byType(Scrollable),
    );

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._initial);

  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

Future<void> _openAdaptiveConditions(WidgetTester tester) async {
  // The sidebar is grouped + collapsible; Adaptive Conditions lives in the
  // (collapsed-by-default) "Automation & Safety" group. Expand the group, then
  // select the section. ensureVisible scrolls each target fully into the
  // sidebar viewport so the tap lands inside its hit-test box.
  final groupHeader = find.text('AUTOMATION & SAFETY');
  await tester.scrollUntilVisible(groupHeader, 100, scrollable: _sidebar);
  await tester.tap(groupHeader);
  await tester.pumpAndSettle(const Duration(milliseconds: 300));

  final sectionItem = find.text('Adaptive Conditions').first;
  await tester.scrollUntilVisible(sectionItem, 100, scrollable: _sidebar);
  // scrollUntilVisible stops as soon as the row is partially visible (often
  // pinned to the viewport edge); ensureVisible fully reveals it so the tap
  // lands inside its hit-test box.
  await tester.ensureVisible(sectionItem);
  await tester.pumpAndSettle(const Duration(milliseconds: 200));
  await tester.tap(sectionItem);
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
