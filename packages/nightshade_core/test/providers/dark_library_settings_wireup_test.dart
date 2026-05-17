import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/database/database.dart';
import 'package:nightshade_core/src/providers/dark_library_provider.dart';
import 'package:nightshade_core/src/providers/database_provider.dart';
import 'package:nightshade_core/src/services/calibration_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Dark library / calibration unification (§2.1 WIRE-UP #6)', () {
    late ProviderContainer container;
    late NightshadeDatabase database;

    setUp(() {
      database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('autoDarkSubtractEnabledProvider reads calibrationSettings', () async {
      // Why: previously this provider read `dark_library.auto_subtract`
      // while the calibration pipeline read `calibration.auto_calibrate`.
      // After the unification they must share the same backing value.
      final notifier = container.read(calibrationSettingsProvider.notifier);
      await notifier.setAutoCalibrate(true);

      expect(container.read(autoDarkSubtractEnabledProvider), isTrue);

      await notifier.setAutoCalibrate(false);
      expect(container.read(autoDarkSubtractEnabledProvider), isFalse);
    });

    test(
        'legacy dark_library.auto_subtract migrates into calibration on load',
        () async {
      // Pre-seed the legacy key directly into the settings DAO so we
      // simulate an upgrade from a build that wrote there. Drift seeds
      // default settings on first open; use insertOrReplace so the test
      // works whether or not a default is present.
      await database.into(database.appSettings).insert(
            AppSettingsCompanion.insert(
              key: 'dark_library.auto_subtract',
              value: 'true',
            ),
            mode: InsertMode.insertOrReplace,
          );

      // Invalidate the settings cache so the calibration notifier reads
      // the freshly-seeded legacy value on next read.
      container.invalidate(allSettingsProvider);
      // Force the async load microtask to run.
      await Future<void>.delayed(Duration.zero);
      // Reading the calibration notifier should observe the legacy
      // value, lift it forward into calibration.auto_calibrate, then
      // delete the legacy key.
      final notifier = container.read(calibrationSettingsProvider.notifier);
      // Wait until the migration write completes.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Calibration store now reports the migrated value.
      expect(notifier.state.autoCalibrate, isTrue);

      // Legacy key is gone.
      final legacy = await database
          .customSelect(
            'SELECT value FROM app_settings WHERE key = ?',
            variables: [
              const Variable<String>('dark_library.auto_subtract'),
            ],
          )
          .get();
      expect(legacy, isEmpty);
    });
  });
}
