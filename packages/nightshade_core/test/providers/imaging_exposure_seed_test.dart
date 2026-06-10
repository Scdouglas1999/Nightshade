import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/imaging/imaging_models.dart';
import 'package:nightshade_core/src/providers/imaging_provider.dart';
import 'package:nightshade_core/src/providers/profiles_provider.dart';
import 'package:nightshade_core/src/providers/session_optimizer_provider.dart';
import 'package:nightshade_core/src/services/session_optimizer_service.dart';
import 'package:nightshade_core/src/services/smart_night/exposure_calculator.dart';

/// A pure-value Smart Night context used as the recommendation source. The
/// physics model rounds the recommendation to a clean value; with this rig the
/// floor (30 s) dominates, so [SmartNightExposureContext.recommendForFilter]
/// returns 30 s for the default (null) filter.
const _seedContext = SmartNightExposureContext(
  camera: CameraExposureSpec(readNoiseE: 1.4, fullWellE: 50000, qePeak: 0.85),
  bortleClass: 8,
  focalLengthMm: 384,
  apertureMm: 80,
  pixelSizeMicrons: 3.76,
  userCapSeconds: 240,
  floorSeconds: 30,
);

/// Builds a container wired with an active profile and a Smart Night context.
///
/// [defaultGain]/[defaultOffset] populate the profile so the gain/offset
/// seeding branch has values to push; [withContext] toggles whether the Smart
/// Night recommendation is available.
ProviderContainer _buildContainer({
  required int profileId,
  int? defaultGain,
  int? defaultOffset,
  bool withContext = true,
}) {
  return ProviderContainer(
    overrides: [
      activeEquipmentProfileProvider.overrideWithValue(
        EquipmentProfileModel(
          id: profileId,
          name: 'Test rig',
          focalLength: 384,
          aperture: 80,
          defaultGain: defaultGain,
          defaultOffset: defaultOffset,
        ),
      ),
      smartNightExposureContextProvider.overrideWith(
        (ref) async => withContext ? _seedContext : null,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeds gain/offset and Smart Night exposure when the user has not '
      'edited anything', () async {
    final container = _buildContainer(
      profileId: 11,
      defaultGain: 200,
      defaultOffset: 30,
    );
    addTearDown(container.dispose);

    expect(
      container.read(exposureSettingsUserDirtyProvider),
      isFalse,
      reason: 'dirty flag must default to false',
    );

    await container.read(smartNightExposureContextProvider.future);
    container.read(syncExposureFromProfileProvider);
    await Future<void>.delayed(Duration.zero);

    final settings = container.read(exposureSettingsProvider);
    expect(settings.gain, 200, reason: 'profile defaultGain should seed');
    expect(settings.offset, 30, reason: 'profile defaultOffset should seed');
    expect(settings.frameType, FrameType.light);
    expect(
      settings.exposureTime,
      30,
      reason: 'Smart Night recommendation should seed the light exposure',
    );
  });

  test(
    'skips all seeding and preserves user values when dirty flag is set',
    () async {
      final container = _buildContainer(
        profileId: 12,
        defaultGain: 200,
        defaultOffset: 30,
      );
      addTearDown(container.dispose);

      // Simulate a manual edit: user picked their own values and the UI flipped
      // the dirty flag (the flip itself lives in camera_panel / camera_presets).
      container.read(exposureSettingsProvider.notifier).state = container
          .read(exposureSettingsProvider)
          .copyWith(exposureTime: 45, gain: 77, offset: 11);
      container.read(exposureSettingsUserDirtyProvider.notifier).state = true;

      await container.read(smartNightExposureContextProvider.future);
      container.read(syncExposureFromProfileProvider);
      await Future<void>.delayed(Duration.zero);

      final settings = container.read(exposureSettingsProvider);
      expect(settings.exposureTime, 45, reason: 'manual exposure preserved');
      expect(
        settings.gain,
        77,
        reason: 'manual gain preserved (no profile seed)',
      );
      expect(
        settings.offset,
        11,
        reason: 'manual offset preserved (no profile seed)',
      );
    },
  );

  test('exposureTime == 120 no longer governs: a dirty 120 s light frame is not '
      're-seeded by Smart Night', () async {
    final container = _buildContainer(profileId: 13);
    addTearDown(container.dispose);

    // The old heuristic re-seeded any 120 s light frame. With the dirty flag
    // set, the literal 120 s default the user deliberately chose must survive.
    expect(
      container.read(exposureSettingsProvider).exposureTime,
      120,
      reason: 'sanity: the no-recommendation fallback default is still 120',
    );
    container.read(exposureSettingsUserDirtyProvider.notifier).state = true;

    await container.read(smartNightExposureContextProvider.future);
    container.read(syncExposureFromProfileProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(exposureSettingsProvider).exposureTime,
      120,
      reason: 'dirty 120 s light frame must not be re-seeded to 30 s',
    );
  });
}
