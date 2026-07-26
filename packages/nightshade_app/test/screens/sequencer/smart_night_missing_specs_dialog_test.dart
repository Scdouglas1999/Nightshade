import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/sequencer/widgets/smart_night_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(<String, String>{}));

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

  testWidgets('remote missing specs dialog writes the imaging host',
      (tester) async {
    final backend = _MockNetworkBackend();
    when(backend.getSmartNightSettings).thenAnswer((_) async => const {});
    Map<String, String>? written;
    when(() => backend.updateSmartNightSettings(any())).thenAnswer(
      (invocation) async {
        written = (invocation.positionalArguments.single as Map).cast();
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const SmartNightMissingSpecsDialog(
                    cameraName: 'RemoteCam',
                    defaultGain: 10,
                    colors: NightshadeColors.dark,
                  ),
                ),
                child: const Text('open remote'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open remote'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-pixel-size')),
      '3.76',
    );
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-read-noise')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-full-well')),
      '19000',
    );
    await tester.enterText(
      find.byKey(const Key('smart-night-spec-qe')),
      '0.9',
    );
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    expect(written, isNotNull);
    final raw = written![HardwareSpecsService.cameraOverridesSettingKey];
    final overrides = jsonDecode(raw!) as List<dynamic>;
    expect((overrides.single as Map)['model'], 'RemoteCam');
    verify(() => backend.updateSmartNightSettings(any())).called(1);
  });
}
