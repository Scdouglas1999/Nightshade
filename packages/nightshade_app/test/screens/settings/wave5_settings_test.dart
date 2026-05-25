// Wave 5 Agent 5 / Pack M — widget tests for the new settings categories
// (Adaptive Exposure, Pre-flight Checks) and the NotificationNode
// transport-override UI.
//
// Why this file is separate from settings_screen_test.dart: the existing
// settings test file is large and tightly scoped to a curated set of
// behaviour assertions. Pack M's tests target the *category routing*
// (new sidebar entries → correct content widget) and the *new strictness
// radio* — both are additive and don't interact with the pre-existing
// scenarios. Keeping them in a separate file keeps blast-radius small
// for future edits.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/adaptive_exposure_settings.dart';
import 'package:nightshade_app/screens/settings/widgets/preflight_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

/// In-memory stub of [AppSettingsNotifier] — same pattern as the main
/// settings_screen_test. Tests inject an initial state and exercise
/// real setter methods (which still write to the in-memory DAO).
class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._initial);
  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    defaultOnError?.call(details);
  };
  addTearDown(() {
    FlutterError.onError = defaultOnError;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'sidebar_lists_adaptive_exposure_and_preflight_checks: the two new '
      'Wave 5 categories appear after Image Grading in the sidebar',
      (tester) async {
    _swallowKnownOverflows();
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

    expect(find.text('Adaptive Exposure'), findsOneWidget,
        reason:
            'The "Adaptive Exposure" sidebar entry must exist — Wave 5 '
            'Agent 2 built the widget but Pack M is responsible for the '
            'routing entry.');
    expect(find.text('Pre-flight Checks'), findsOneWidget,
        reason:
            'The "Pre-flight Checks" sidebar entry must exist — Wave 5 '
            'Agent 3 added the setting but Pack M owns the UI surface.');
  });

  testWidgets(
      'tapping_adaptive_exposure_renders_widget: the sidebar entry maps to '
      'AdaptiveExposureSettings in the content pane',
      (tester) async {
    _swallowKnownOverflows();
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

    // Find the sidebar entry — the first match is the sidebar; the
    // pane has not rendered yet so there is only one.
    await tester.tap(find.text('Adaptive Exposure').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(AdaptiveExposureSettings), findsOneWidget,
        reason:
            'Tapping Adaptive Exposure must swap the content pane to '
            'AdaptiveExposureSettings — otherwise the case-index dispatch '
            'in _buildContent has drifted.');
  });

  testWidgets(
      'tapping_preflight_checks_renders_widget_with_strictness_radio: the '
      'sidebar entry maps to PreflightSettings and the radio group exists',
      (tester) async {
    _swallowKnownOverflows();
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

    await tester.tap(find.text('Pre-flight Checks').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byType(PreflightSettings), findsOneWidget,
        reason:
            'Tapping Pre-flight Checks must render PreflightSettings.');
    // The radio group has three Radio<PreflightStrictness> widgets.
    expect(find.byType(Radio<PreflightStrictness>), findsNWidgets(3),
        reason:
            'PreflightSettings must surface three strictness options '
            '(lax / normal / strict).');
  });

  testWidgets(
      'changing_preflight_strictness_updates_settings: tapping the Strict '
      'option moves AppSettingsState.preflightStrictness to strict',
      (tester) async {
    _swallowKnownOverflows();
    const initial = AppSettingsState(); // default = normal
    expect(initial.preflightStrictness, PreflightStrictness.normal,
        reason: 'Sanity: default is normal.');

    final handle = await pumpAppScreen(
      tester,
      const SettingsScreen(),
      size: const Size(1280, 800),
      extraOverrides: [
        appSettingsProvider.overrideWith(
          () => _StubAppSettingsNotifier(initial),
        ),
      ],
    );

    await tester.tap(find.text('Pre-flight Checks').first);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The Strict option carries a ValueKey we can target deterministically.
    final strictRow = find.byKey(const ValueKey('preflightStrictness_strict'));
    expect(strictRow, findsOneWidget,
        reason: 'The Strict option row must carry its ValueKey.');
    await tester.tap(strictRow);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    final state = handle.container.read(appSettingsProvider).value;
    expect(state, isNotNull);
    expect(state!.preflightStrictness, PreflightStrictness.strict,
        reason:
            'Tapping the Strict option must call '
            'setPreflightStrictness(PreflightStrictness.strict).');
  });
}
