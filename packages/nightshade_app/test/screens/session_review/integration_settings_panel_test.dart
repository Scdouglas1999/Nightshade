// Widget tests for the Session Review integration-settings panel.
//
// The panel is a pure controlled widget (no providers): it renders the
// smart-default preset chips + a live readout, exposes an Advanced expander,
// and reports every edit through `onChanged` without mutating its own state.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/widgets/integration_settings_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Widget _harness({required Widget child}) {
  return MaterialApp(
    theme: ThemeData(extensions: const [NightshadeColors.dark]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders preset chips and the live sub-count readout',
      (tester) async {
    await tester.pumpWidget(_harness(
      child: IntegrationSettingsPanel(
        settings: IntegrationSettings.defaults,
        subCount: 30,
        onChanged: (_) {},
      ),
    ));
    await tester.pump();

    // All five presets are offered.
    for (final preset in IntegrationPreset.values) {
      expect(find.text(preset.label), findsOneWidget);
    }
    // 30 subs resolves the auto rule to linear-fit and shows it in the readout.
    expect(find.textContaining('30 accepted subs'), findsOneWidget);
    expect(find.textContaining('Linear fit'), findsOneWidget);
  });

  testWidgets('tapping a preset reports the materialised settings',
      (tester) async {
    IntegrationSettings? reported;
    await tester.pumpWidget(_harness(
      child: IntegrationSettingsPanel(
        settings: IntegrationSettings.defaults,
        subCount: 5,
        onChanged: (s) => reported = s,
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Maximum Quality'));
    await tester.pump();

    expect(reported, isNotNull);
    expect(reported!.sourcePreset, IntegrationPreset.maximumQuality);
    expect(reported!.resampler, Resampler.lanczos3);
  });

  testWidgets('few subs (<8) resolves auto rejection to percentile clip',
      (tester) async {
    await tester.pumpWidget(_harness(
      child: IntegrationSettingsPanel(
        settings: IntegrationSettings.defaults,
        subCount: 5,
        onChanged: (_) {},
      ),
    ));
    await tester.pump();

    expect(find.textContaining('Percentile clip'), findsOneWidget);
  });

  testWidgets('advanced expander reveals the per-knob controls',
      (tester) async {
    await tester.pumpWidget(_harness(
      child: IntegrationSettingsPanel(
        settings: IntegrationSettings.defaults,
        subCount: 12,
        onChanged: (_) {},
      ),
    ));
    await tester.pump();

    // Advanced groups are hidden until the expander is tapped.
    expect(find.text('ALIGNMENT'), findsNothing);

    await tester.tap(find.text('Advanced settings'));
    await tester.pumpAndSettle();

    expect(find.text('ALIGNMENT'), findsOneWidget);
    expect(find.text('PIXEL REJECTION'), findsOneWidget);
    expect(find.text('Transform model'), findsOneWidget);
  });
}
