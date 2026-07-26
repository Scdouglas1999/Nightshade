import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/session_review/auto_integration_service.dart';
import 'package:nightshade_app/screens/settings/widgets/image_grading_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

Future<HarnessHandle> _pumpSettings(WidgetTester tester) async {
  final database = mockDatabase();
  await database.settingsDao.setSettings({
    'image_grading_enabled': 'true',
    'image_grading_hfr_threshold_px': '3.5',
    'image_grading_max_consecutive_rejects': '3',
    kAutoIntegrateSettingKey: 'false',
  });
  addTearDown(database.close);
  return pumpAppScreen(
    tester,
    const ImageGradingSettings(),
    size: const Size(900, 1000),
    database: database,
    settle: false,
  );
}

Future<void> _pumpWrites(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('thresholds commit on submit and clamp the visible value',
      (tester) async {
    final handle = await _pumpSettings(tester);
    await tester.pump();
    final field = find.byKey(
      const ValueKey('image-grading-hfr-threshold'),
    );
    await tester.ensureVisible(field);

    await tester.enterText(field, '999');
    await tester.pump();
    expect(
      handle.container
          .read(appSettingsProvider)
          .value!
          .imageGradingHfrThresholdPx,
      3.5,
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpWrites(tester);
    expect(
      handle.container
          .read(appSettingsProvider)
          .value!
          .imageGradingHfrThresholdPx,
      50,
    );
    expect(tester.widget<TextField>(field).controller!.text, '50.00');
  });

  testWidgets('required blank input restores the committed value',
      (tester) async {
    final handle = await _pumpSettings(tester);
    await tester.pump();
    final field = find.byKey(const ValueKey('image-grading-max-rejects'));
    await tester.ensureVisible(field);

    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(tester.widget<TextField>(field).controller!.text, '3');
    expect(find.text('A value is required.'), findsOneWidget);
    expect(
      handle.container
          .read(appSettingsProvider)
          .value!
          .imageGradingMaxConsecutiveRejects,
      3,
    );
  });

  testWidgets('clearing an optional threshold disables only that check',
      (tester) async {
    final handle = await _pumpSettings(tester);
    await tester.pump();
    final field = find.byKey(
      const ValueKey('image-grading-star-count-minimum'),
    );
    await tester.ensureVisible(field);

    await tester.enterText(field, '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpWrites(tester);

    expect(
      handle.container
          .read(appSettingsProvider)
          .value!
          .imageGradingStarCountMin,
      isNull,
    );
  });

  testWidgets('auto-integration toggle persists immediately', (tester) async {
    final handle = await _pumpSettings(tester);
    await tester.pump();
    final toggle = find.byKey(const ValueKey('auto-integrate-switch'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await _pumpWrites(tester);

    expect(
      await handle.database.settingsDao.getSetting(kAutoIntegrateSettingKey),
      'true',
    );
  });
}
