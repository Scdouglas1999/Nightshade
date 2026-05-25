import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/smart_night_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('missing specs dialog persists a camera hardware override',
      (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const SmartNightMissingSpecsDialog(
                    cameraName: 'MysteryCam',
                    defaultGain: 10,
                    colors: NightshadeColors.dark,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('smart-night-spec-pixel-size')),
      '4.63',
    );
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-read-noise')),
      '2.1',
    );
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-full-well')),
      '42000',
    );
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-qe')),
      '0.72',
    );
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    final raw = await db.settingsDao
        .getSetting(HardwareSpecsService.cameraOverridesSettingKey);
    final overrides = jsonDecode(raw!) as List<dynamic>;
    final override = overrides.single as Map<String, dynamic>;

    expect(override['model'], 'MysteryCam');
    expect(override['pixelSizeMicrons'], 4.63);
    expect(override['qePeak'], 0.72);
    expect((override['gainPoints'] as List).single['readNoiseE'], 2.1);
    expect((override['gainPoints'] as List).single['fullWellE'], 42000);
  });
}
