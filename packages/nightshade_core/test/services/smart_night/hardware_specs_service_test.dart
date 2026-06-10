import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/services/smart_night/hardware_specs_service.dart';

void main() {
  group('HardwareSpecsService', () {
    const service = HardwareSpecsService();

    test('matches known camera aliases and returns gain-specific specs', () {
      final match = service.matchCamera(
        cameraName: 'ZWO ASI2600MM Pro',
        gain: 100,
      );

      expect(match, isNotNull);
      expect(match!.spec.model, 'ZWO ASI2600MM Pro');
      expect(match.exposureSpec.readNoiseE, closeTo(1.5, 0.001));
      expect(match.exposureSpec.fullWellE, closeTo(18700, 0.001));
      expect(match.exposureSpec.qePeak, closeTo(0.91, 0.001));
      expect(match.pixelSizeMicrons, closeTo(3.76, 0.001));
    });

    test('interpolates camera gain points when the exact gain is unknown', () {
      final match = service.matchCamera(cameraName: 'ASI2600MC', gain: 50);

      expect(match, isNotNull);
      expect(match!.spec.model, 'ZWO ASI2600MC Pro');
      expect(match.exposureSpec.readNoiseE, closeTo(2.5, 0.001));
      expect(match.exposureSpec.fullWellE, closeTo(34350, 0.001));
    });

    test('returns null for unmatched cameras instead of inventing specs', () {
      final match = service.matchCamera(
        cameraName: 'Mystery Camera 42',
        gain: 100,
      );

      expect(match, isNull);
    });

    test('prioritizes user override specs over bundled catalog entries', () {
      const service = HardwareSpecsService(
        cameraOverrides: [
          CameraHardwareSpec(
            model: 'ZWO ASI2600MM Pro',
            aliases: ['ASI2600MM'],
            pixelSizeMicrons: 4.5,
            qePeak: 0.75,
            defaultGain: 10,
            gainPoints: [
              CameraGainPoint(gain: 10, readNoiseE: 2.2, fullWellE: 30000),
            ],
          ),
        ],
      );

      final match = service.matchCamera(cameraName: 'ASI2600MM', gain: 10);

      expect(match, isNotNull);
      expect(match!.pixelSizeMicrons, closeTo(4.5, 0.001));
      expect(match.exposureSpec.readNoiseE, closeTo(2.2, 0.001));
      expect(match.exposureSpec.fullWellE, closeTo(30000, 0.001));
      expect(match.exposureSpec.qePeak, closeTo(0.75, 0.001));
    });

    test('parses camera override specs from JSON', () {
      final spec = CameraHardwareSpec.fromJson({
        'model': 'Mystery Camera 42',
        'aliases': ['MysteryCam'],
        'pixelSizeMicrons': 4.63,
        'qePeak': 0.72,
        'defaultGain': 10,
        'gainPoints': [
          {'gain': 10, 'readNoiseE': 2.1, 'fullWellE': 42000},
        ],
      });

      expect(spec.model, 'Mystery Camera 42');
      expect(spec.aliases, ['MysteryCam']);
      expect(spec.gainPoints.single.fullWellE, 42000);
    });

    test('serializes camera override specs to JSON', () {
      const spec = CameraHardwareSpec(
        model: 'Mystery Camera 42',
        aliases: ['MysteryCam'],
        pixelSizeMicrons: 4.63,
        qePeak: 0.72,
        defaultGain: 10,
        gainPoints: [
          CameraGainPoint(gain: 10, readNoiseE: 2.1, fullWellE: 42000),
        ],
      );

      final restored = CameraHardwareSpec.fromJson(spec.toJson());

      expect(restored.model, spec.model);
      expect(restored.aliases, spec.aliases);
      expect(restored.pixelSizeMicrons, spec.pixelSizeMicrons);
      expect(restored.qePeak, spec.qePeak);
      expect(restored.defaultGain, spec.defaultGain);
      expect(restored.gainPoints.single.readNoiseE, 2.1);
    });
  });
}
