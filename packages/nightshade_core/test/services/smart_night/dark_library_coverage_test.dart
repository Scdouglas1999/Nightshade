import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  group('SmartNightDarkLibraryCoverage', () {
    late NightshadeDatabase database;
    late SmartNightDarkLibraryCoverage coverage;

    const profile = EquipmentProfileModel(
      id: 1,
      name: 'Mono rig',
      focalLength: 350,
      aperture: 71,
      cameraName: 'ZWO ASI2600MM Pro',
      defaultGain: 100,
      defaultOffset: 50,
      defaultBinX: 1,
      defaultBinY: 1,
      defaultCoolingTemp: -10,
      filterNames: ['L', 'R', 'G', 'B'],
    );
    const exposureContext = SmartNightExposureContext(
      camera: CameraExposureSpec(
        readNoiseE: 1.4,
        fullWellE: 50000,
        qePeak: 0.8,
      ),
      bortleClass: 3,
      focalLengthMm: 350,
      apertureMm: 71,
      pixelSizeMicrons: 3.76,
      availableFilterNames: ['L', 'R', 'G', 'B'],
      userCapSeconds: 245,
      floorSeconds: 45,
    );

    setUp(() {
      database = NightshadeDatabase.forTesting(NativeDatabase.memory());
      coverage = SmartNightDarkLibraryCoverage(
        darkLibraryService: DarkLibraryService(DarkLibraryDao(database)),
      );
    });

    tearDown(() async {
      await database.close();
    });

    test('uses Smart Night exposure recommendations for required durations',
        () async {
      final expectedDuration =
          exposureContext.recommendForFilter('L').seconds.toStringAsFixed(0);

      final notes = await coverage.missingNotes(
        profile: profile,
        strategy: SmartNightStrategy.oscOneShot,
        settings: const SmartNightSettings(),
        exposureContext: exposureContext,
        minCoverage: 10,
      );

      expect(notes, isNotEmpty);
      expect(notes.first, contains('duration=${expectedDuration}s'));
      if (expectedDuration != '120') {
        expect(notes.first, isNot(contains('duration=120s')));
      }
    });

    test('returns no notes when a matching master exists', () async {
      // L / R / G / B no longer share a single exposure: the calculator now
      // models per-channel sky brightness (blue sees the darkest sky and needs
      // the longest sub), so an autoLrgb plan requires a dark master at each
      // distinct duration. Seed one master per unique required duration so the
      // library is genuinely fully covered.
      final dao = DarkLibraryDao(database);
      final requiredDurations = <double>{
        for (final filter in const ['L', 'R', 'G', 'B'])
          exposureContext.recommendForFilter(filter).seconds,
      };
      var index = 0;
      for (final duration in requiredDurations) {
        await dao.addEntry(DarkLibraryCompanion.insert(
          filePath: '/tmp/master_$index.fits',
          exposureTime: duration,
          frameType: const Value('dark'),
          temperature: const Value(-10),
          gain: const Value(100),
          offset: const Value(50),
          binX: const Value(1),
          binY: const Value(1),
          masterDarkPath: Value('/tmp/master_$index.fits'),
          masterFrameCount: const Value(20),
        ));
        index++;
      }

      final notes = await coverage.missingNotes(
        profile: profile,
        strategy: SmartNightStrategy.autoLrgb,
        settings: const SmartNightSettings(),
        exposureContext: exposureContext,
        minCoverage: 10,
      );

      expect(notes, isEmpty);
    });
  });
}
