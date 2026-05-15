// Smoke tests for the non-GPU paths of PlanetariumScreen.
//
// Scope (CQ-W5-WIDGET-TESTS-PLAN, intentionally narrow):
//
//   1. getDsoDisplayInfo_messier  — pure helper at the top of
//      planetarium_screen.dart returns the Messier designation when the
//      DSO carries an `M\d+` catalog id. This is the function the popup
//      and finder-chart code use to render the object label; getting it
//      wrong silently mislabels every DSO on the sky.
//
//   2. getDsoDisplayInfo_ngc_ic   — same helper falls back to the NGC/IC
//      designation when no Messier id is available. Covers the second
//      branch and verifies the catalog tag returned alongside the name.
//
//   3. observationTimeProvider_pause — calling
//      `setSpeedMultiplier(0)` on the planetarium's time-control state
//      notifier flips `isRealTime` to false and pins the
//      `speedMultiplier`. This is the state mutation the space-bar
//      keyboard shortcut and the TimeControlPanel play/pause button rely
//      on; if it regresses, the whole "scrub through tonight" workflow
//      stops responding.
//
// Why no widget pump of the full PlanetariumScreen here: the screen
// fans out to ~30 providers (stars, DSOs, mount/rotator state, Bortle
// class, horizon profile, performance monitor, etc.) and a GPU sky
// renderer that pulls shaders from disk. A meaningful render-time smoke
// test would require stubbing every one of those — out of scope for a
// 25-minute hygiene pass. The three tests below cover the deterministic
// non-GPU paths the screen and its keyboard shortcuts touch.
//
// See: docs/code-quality/audit-tests.md §1.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/planetarium/planetarium_screen.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  group('getDsoDisplayInfo', () {
    test('getDsoDisplayInfo_messier: returns Messier number + "M" tag '
        'when catalogIds contains M\\d+', () {
      // M31 with an explicit Messier catalog id. The helper should
      // prefer the Messier designation over the bare `id` so the UI
      // shows "M31" instead of the raw NGC number.
      const m31 = DeepSkyObject(
        id: 'NGC224',
        name: 'Andromeda Galaxy',
        coordinates: CelestialCoordinate(ra: 0.712, dec: 41.269),
        type: DsoType.galaxy,
        catalogIds: ['M31', 'NGC224'],
      );

      final (displayName, catalogTag) = getDsoDisplayInfo(m31);

      expect(displayName, 'M31',
          reason: 'Messier objects must surface their M-number, not the '
              'NGC fallback, because that is the label most observers '
              'recognise.');
      expect(catalogTag, 'M',
          reason: 'Catalog tag drives the badge colour in ObjectInfoPopup; '
              'Messier objects must tag as "M".');
    });

    test('getDsoDisplayInfo_ngc_ic: returns NGC designation + "NGC" tag '
        'for non-Messier DSOs', () {
      // NGC 7000 (North America Nebula) has no Messier number. The
      // helper should fall through the Messier branch and return the
      // NGC id with the "NGC" tag.
      const ngc7000 = DeepSkyObject(
        id: 'NGC7000',
        name: 'North America Nebula',
        coordinates: CelestialCoordinate(ra: 20.97, dec: 44.33),
        type: DsoType.emissionNebula,
        catalogIds: ['NGC7000'],
      );

      final (displayName, catalogTag) = getDsoDisplayInfo(ngc7000);

      expect(displayName, 'NGC7000',
          reason: 'Non-Messier NGC objects must surface their NGC '
              'designation as the primary display name.');
      expect(catalogTag, 'NGC',
          reason: 'Catalog tag must reflect the NGC catalogue so the '
              'popup badge colour matches.');
    });
  });

  group('observationTimeProvider', () {
    test('observationTimeProvider_pause: setSpeedMultiplier(0) clears '
        'isRealTime and freezes the time stream', () {
      // Why ProviderContainer not pumpWidget: this is a state-level
      // test of the notifier the space-bar handler in
      // planetarium_screen.dart drives. Pumping a full widget tree
      // would drag in twilightTimesProvider, observerLocationProvider,
      // and the GPU sky renderer for no extra coverage.
      final container = ProviderContainer();
      // Why dispose: ObservationTimeNotifier owns a periodic Timer
      // (lib/src/providers/planetarium_providers.dart §147). Without
      // dispose, the timer keeps firing and the test framework reports
      // a pending timer at teardown.
      addTearDown(container.dispose);

      final initial = container.read(observationTimeProvider);
      expect(initial.isRealTime, isTrue,
          reason: 'Notifier seeds itself into real-time mode so a fresh '
              'planetarium session reflects wall-clock time.');
      expect(initial.speedMultiplier, 1.0,
          reason: 'Default multiplier is 1x so observation time advances '
              'one second per real second when in real-time mode.');

      // Mirror the space-bar pause path: setSpeedMultiplier(0) is what
      // _handleKeyEvent calls when the time stream is currently real-
      // time and the user wants to freeze the sky.
      container
          .read(observationTimeProvider.notifier)
          .setSpeedMultiplier(0);

      final paused = container.read(observationTimeProvider);
      expect(paused.isRealTime, isFalse,
          reason: 'Pause must drop out of real-time mode; otherwise the '
              'periodic timer would overwrite the frozen instant on the '
              'next tick.');
      expect(paused.speedMultiplier, 0.0,
          reason: 'Multiplier must persist exactly the requested value '
              'so subsequent ticks contribute zero delta and the time '
              'remains frozen.');
    });
  });
}
