import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/imaging/imaging_models.dart';
import 'package:nightshade_core/src/providers/imaging_provider.dart';
import 'package:nightshade_core/src/providers/profiles_provider.dart';
import 'package:nightshade_core/src/providers/session_optimizer_provider.dart';
import 'package:nightshade_core/src/services/session_optimizer_service.dart';
import 'package:nightshade_core/src/services/smart_night/exposure_calculator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'imaging light-frame defaults use Smart Night exposure context',
    () async {
      final container = ProviderContainer(
        overrides: [
          activeEquipmentProfileProvider.overrideWithValue(
            const EquipmentProfileModel(
              id: 7,
              name: 'Test rig',
              focalLength: 384,
              aperture: 80,
              defaultGain: 100,
              defaultOffset: 50,
            ),
          ),
          smartNightExposureContextProvider.overrideWith(
            (ref) async => const SmartNightExposureContext(
              camera: CameraExposureSpec(
                readNoiseE: 1.4,
                fullWellE: 50000,
                qePeak: 0.85,
              ),
              bortleClass: 8,
              focalLengthMm: 384,
              apertureMm: 80,
              pixelSizeMicrons: 3.76,
              userCapSeconds: 240,
              floorSeconds: 30,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(smartNightExposureContextProvider.future);
      container.read(syncExposureFromProfileProvider);
      await Future<void>.delayed(Duration.zero);

      final settings = container.read(exposureSettingsProvider);
      expect(settings.frameType, FrameType.light);
      expect(settings.exposureTime, 30);
      expect(settings.gain, 100);
      expect(settings.offset, 50);
    },
  );

  test('imaging Smart Night sync preserves manual exposure edits', () async {
    final container = ProviderContainer(
      overrides: [
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 8,
            name: 'Test rig',
            focalLength: 384,
            aperture: 80,
          ),
        ),
        smartNightExposureContextProvider.overrideWith(
          (ref) async => const SmartNightExposureContext(
            camera: CameraExposureSpec(
              readNoiseE: 1.4,
              fullWellE: 50000,
              qePeak: 0.85,
            ),
            bortleClass: 8,
            focalLengthMm: 384,
            apertureMm: 80,
            pixelSizeMicrons: 3.76,
            userCapSeconds: 240,
            floorSeconds: 30,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    // A manual exposure edit flips the user-dirty flag (the UI does this in
    // camera_panel / camera_presets); that flag — not a value heuristic — is
    // what now gates Smart Night re-seeding.
    container.read(exposureSettingsProvider.notifier).state = container
        .read(exposureSettingsProvider)
        .copyWith(exposureTime: 45);
    container.read(exposureSettingsUserDirtyProvider.notifier).state = true;
    await container.read(smartNightExposureContextProvider.future);
    container.read(syncExposureFromProfileProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(exposureSettingsProvider).exposureTime, 45);
  });
}
