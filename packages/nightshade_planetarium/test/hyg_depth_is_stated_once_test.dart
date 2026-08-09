// Regression: the app stated three different depths for the same bundled star
// catalog, all wrong in the same direction.
//
// Reached from the planetarium's Layers panel > Deep stars > Install, the
// Catalog Settings sheet described the installed HYG Star Database as
// "119.6k objects, 32.4 MB, Version 4.2, Package Complete, Depth mag <= 15.0",
// two cards further down the Deep-Star Tier card called the same catalog's
// floor "~mag 11.5", and the Layers panel said "stars below mag 11.5 are
// unavailable". 15.0 is the LOADER'S inclusion filter mislabelled "Depth";
// counting the shipped file (119,626 rows) the per-magnitude gain turns over
// after 9. "Package: Complete" beside "Depth: mag <= 15.0" told the user that
// the nearly-empty field at an imaging FOV was the real sky.
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_planetarium/nightshade_planetarium.dart';

void main() {
  test('the catalog-package depth chip quotes HYG\'s real completeness', () {
    expect(CatalogPackage.complete.starMagnitudeLimit, kHygFaintFloorMag);
    expect(kHygFaintFloorMag, 9.0);
  });

  test('nothing claims the old 15.0 or 11.5 depth', () {
    for (final package in CatalogPackage.values) {
      expect(
        package.starMagnitudeLimit,
        lessThanOrEqualTo(kHygFaintFloorMag),
        reason: '${package.name} claims a depth HYG cannot deliver',
      );
    }
  });
}
