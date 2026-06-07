import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/src/rendering/render_quality.dart';
import 'package:nightshade_planetarium/src/rendering/sky_renderer.dart';

SkyCanvasPainter _painterAt(DateTime utc) => SkyCanvasPainter(
      viewState:
          const SkyViewState(centerRA: 6, centerDec: 10, fieldOfView: 60),
      config: const SkyRenderConfig(),
      qualityConfig: const RenderQualityConfig.balanced(),
      stars: const [],
      dsos: const [],
      constellations: const [],
      milkyWayPoints: null,
      planets: const [],
      observationTime: utc,
      latitude: 40,
      longitude: -75, // ~EST, solar offset −5h
    );

void main() {
  group('celestialVisibility (daytime star fade)', () {
    test('full daylight hides deep-sky content (factor 0)', () {
      // Local noon in winter at 40°N/75°W → sun well above the horizon.
      expect(_painterAt(DateTime.utc(2026, 12, 21, 17)).celestialVisibility,
          0.0);
    });

    test('astronomical night shows it at full strength (factor 1)', () {
      // Local midnight in winter → sun far below −18°.
      expect(_painterAt(DateTime.utc(2026, 12, 21, 5)).celestialVisibility,
          1.0);
    });

    test('twilight is a partial fade (0 < factor < 1)', () {
      // Sweep the dawn hours; at least one sampled time must land in twilight.
      var sawPartial = false;
      for (final h in [10, 11, 12]) {
        final v = _painterAt(DateTime.utc(2026, 12, 21, h, 30))
            .celestialVisibility;
        if (v > 0.0 && v < 1.0) sawPartial = true;
      }
      expect(sawPartial, isTrue,
          reason: 'expected a twilight sample with a partial fade');
    });
  });
}
