import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/src/coordinate_system.dart';
import 'package:nightshade_planetarium/src/services/mosaic_planner.dart';

void main() {
  group('MosaicPlanner', () {
    test('generates finite panel centers near celestial pole', () {
      final plan = MosaicPlanner.generateRectangularMosaic(
        center: const CelestialCoordinate(ra: 12, dec: 90),
        rows: 2,
        columns: 2,
        panelFovWidth: 2,
        panelFovHeight: 2,
      );

      for (final panel in plan.panels) {
        expect(panel.center.ra.isFinite, isTrue);
        expect(panel.center.dec.isFinite, isTrue);
        expect(panel.center.ra, greaterThanOrEqualTo(0));
        expect(panel.center.ra, lessThan(24));

        for (final corner in panel.corners) {
          expect(corner.ra.isFinite, isTrue);
          expect(corner.dec.isFinite, isTrue);
          expect(corner.ra, greaterThanOrEqualTo(0));
          expect(corner.ra, lessThan(24));
        }
      }
    });
  });
}
