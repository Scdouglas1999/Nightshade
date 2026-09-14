import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/widgets/camera_sensor_specs_dialog.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// What the chain resolves for a camera nothing publishes: the state the
/// dialog is opened in when the user has to supply the figures themselves.
final _unknownCamera = CameraSensorSpecResolver().resolve(
  const CameraSensorSpecInputs(cameraName: 'MysteryCam', gain: 10),
);

/// What it resolves for the owner's camera: every field already filled in from
/// ZWO's published specification, so the dialog is a correction surface.
final _publishedCamera = CameraSensorSpecResolver().resolve(
  const CameraSensorSpecInputs(cameraName: 'ASI1600MM-Cool', gain: 139),
);

Future<void> _pumpDialog(
  WidgetTester tester, {
  required ResolvedCameraSensorSpecs specs,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => CameraSensorSpecsDialog.show(context, specs),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester, String key) {
  final field = tester.widget<NightshadeTextField>(
    find.byKey(Key('camera-sensor-spec-$key')),
  );
  return field.controller!.text;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => registerFallbackValue(<String, String>{}));

  testWidgets('the dialog persists a camera hardware override', (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _unknownCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-pixel-size')),
      '4.63',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-read-noise')),
      '2.1',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-full-well')),
      '42000',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-qe')),
      '0.72',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-gain')),
      '10',
    );
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    final raw = await db.settingsDao.getSetting(
      HardwareSpecsService.cameraOverridesSettingKey,
    );
    final overrides = jsonDecode(raw!) as List<dynamic>;
    final override = overrides.single as Map<String, dynamic>;

    expect(override['model'], 'MysteryCam');
    expect(override['pixelSizeMicrons'], 4.63);
    expect(override['qePeak'], 0.72);
    final point = (override['gainPoints'] as List).single as Map;
    expect(point['gain'], 10);
    expect(point['readNoiseE'], 2.1);
    expect(point['fullWellE'], 42000);
  });

  testWidgets('the dialog arrives prefilled with what resolved', (
    tester,
  ) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _publishedCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    // ZWO's published figures for the owner's camera, so the user corrects
    // rather than transcribes a datasheet.
    expect(_fieldText(tester, 'model'), 'ZWO ASI1600MM');
    expect(_fieldText(tester, 'pixel-size'), '3.8');
    expect(_fieldText(tester, 'width'), '4656');
    expect(_fieldText(tester, 'height'), '3520');
    expect(_fieldText(tester, 'read-noise'), '1.2');
    expect(_fieldText(tester, 'full-well'), '20000');
    expect(_fieldText(tester, 'qe'), '0.6');
  });

  testWidgets('each field says where its value came from', (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _publishedCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    expect(
      find.text('The published pixel pitch for ZWO ASI1600MM.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('quotes only at 30 dB gain'),
      findsOneWidget,
    );
  });

  testWidgets('an unpublished field says so instead of looking empty', (
    tester,
  ) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _unknownCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    expect(
      find.textContaining('Not published for this camera'),
      findsWidgets,
    );
  });

  testWidgets('read noise without a gain is refused', (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _unknownCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-pixel-size')),
      '4.63',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-read-noise')),
      '2.1',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-full-well')),
      '42000',
    );
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('gain that read noise and full well'),
      findsOneWidget,
    );
    expect(
      await db.settingsDao.getSetting(
        HardwareSpecsService.cameraOverridesSettingKey,
      ),
      isNull,
    );
  });

  testWidgets('a QE above 1 is refused', (tester) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _unknownCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-pixel-size')),
      '4.63',
    );
    await tester.enterText(
        find.byKey(const Key('camera-sensor-spec-qe')), '60');
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    expect(find.textContaining('0.6 means 60%'), findsOneWidget);
  });

  testWidgets('correcting one field keeps the rest of what resolved', (
    tester,
  ) async {
    final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await _pumpDialog(
      tester,
      specs: _publishedCamera,
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    // The user measured their own read noise and changes only that.
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-read-noise')),
      '3.6',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-gain')),
      '0',
    );
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    final raw = await db.settingsDao.getSetting(
      HardwareSpecsService.cameraOverridesSettingKey,
    );
    final override = (jsonDecode(raw!) as List).single as Map<String, dynamic>;
    expect(override['pixelSizeMicrons'], 3.8);
    expect(override['qePeak'], 0.6);
    expect(override['sensorWidthPx'], 4656);
    final point = (override['gainPoints'] as List).single as Map;
    expect(point['gain'], 0);
    expect(point['readNoiseE'], 3.6);
    expect(point['fullWellE'], 20000);
  });

  testWidgets('the remote dialog writes the imaging host', (tester) async {
    final backend = _MockNetworkBackend();
    when(backend.getSmartNightSettings).thenAnswer((_) async => const {});
    Map<String, String>? written;
    when(() => backend.updateSmartNightSettings(any())).thenAnswer((
      invocation,
    ) async {
      written = (invocation.positionalArguments.single as Map).cast();
    });

    await _pumpDialog(
      tester,
      specs: _unknownCamera,
      overrides: [
        backendProvider.overrideWith(
          (ref) => _FixedBackendNotifier(ref, backend),
        ),
      ],
    );

    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-pixel-size')),
      '3.76',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-read-noise')),
      '1.5',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-full-well')),
      '19000',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-qe')),
      '0.9',
    );
    await tester.enterText(
      find.byKey(const Key('camera-sensor-spec-gain')),
      '10',
    );
    await tester.tap(find.text('Save specs'));
    await tester.pumpAndSettle();

    expect(written, isNotNull);
    final raw = written![HardwareSpecsService.cameraOverridesSettingKey];
    final overrides = jsonDecode(raw!) as List<dynamic>;
    expect((overrides.single as Map)['model'], 'MysteryCam');
    verify(() => backend.updateSmartNightSettings(any())).called(1);
  });
}
