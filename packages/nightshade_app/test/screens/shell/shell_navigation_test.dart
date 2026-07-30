import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/shell_navigation.dart';

void main() {
  group('ShellNavigation', () {
    test('primaryDestinations leads with the nightly-imaging tools', () {
      // The rail leads with what an imager touches every night. Framing,
      // Planetarium, Your Sky and Constellation are nested inside Plan Tonight;
      // Science is folded into Analytics; Settings is reached from the gear —
      // none of them hold a rail slot. Guiding + Weather are first-class again.
      expect(ShellNavigation.primaryDestinations, hasLength(8));
      expect(
        ShellNavigation.primaryRoutes,
        [
          '/dashboard',
          '/equipment',
          '/imaging',
          '/sequencer',
          '/guiding',
          '/weather',
          '/planner',
          '/analytics',
        ],
      );
    });

    test('bottomNavigationDestinations has exactly six core slots', () {
      expect(ShellNavigation.bottomNavigationDestinations, hasLength(6));
      final routes = ShellNavigation.bottomNavigationDestinations
          .map((d) => d.route)
          .toList();
      expect(routes, [
        '/dashboard',
        '/equipment',
        '/imaging',
        '/sequencer',
        '/guiding',
        '/planner',
      ]);
      expect(routes, isNot(contains('/transients')));
      expect(routes, isNot(contains('/settings')));
    });

    test('primaryIndexForLocation resolves planner and ignores query', () {
      expect(
        ShellNavigation.primaryIndexForLocation('/planner?tab=scheduler'),
        6,
      );
      expect(ShellNavigation.primaryRouteForIndex(6), '/planner');
    });

    // A lit rail item is the shell's strongest claim about where the operator
    // is. `primaryIndexForLocation` used to be exact-match only and the shell
    // defaulted an unmatched location to 0, so every route no rail destination
    // hosts — Tonight, the Flat Wizard, the mosaic / session-review /
    // stack-result viewers, /diagnostics/dump, /settings/plate-solving — lit up
    // Dashboard while showing something else entirely.
    test('non-rail routes select nothing rather than falling back to Dashboard',
        () {
      for (final location in [
        '/tonight',
        '/flat-wizard',
        '/mosaic',
        '/mosaic/7',
        '/session-review?session=3',
        '/stack-result?id=9',
        '/diagnostics/dump',
        '/settings',
        '/settings/plate-solving',
        '/polar-alignment',
        '/tutorial/first-night',
      ]) {
        expect(
          ShellNavigation.primaryIndexForLocation(location),
          -1,
          reason: '$location must not highlight a rail destination',
        );
      }
    });

    test('a sub-route resolves to the destination that hosts it', () {
      // The image-ready notification deep link renders the Imaging screen.
      expect(
        ShellNavigation.primaryIndexForLocation('/imaging/preview/42'),
        ShellNavigation.primaryRoutes.indexOf('/imaging'),
      );
      expect(
        ShellNavigation.primaryIndexForLocation('/imaging/preview/42?x=1'),
        ShellNavigation.primaryRoutes.indexOf('/imaging'),
      );
    });

    test('locationIsUnder matches on segment boundaries only', () {
      expect(ShellNavigation.locationIsUnder('/planner', '/planner'), isTrue);
      expect(
        ShellNavigation.locationIsUnder('/planner?tab=discover', '/planner'),
        isTrue,
      );
      expect(
        ShellNavigation.locationIsUnder('/planner/queue', '/planner'),
        isTrue,
      );
      // A sibling route that merely shares a prefix is NOT nested.
      expect(
        ShellNavigation.locationIsUnder('/planner-archive', '/planner'),
        isFalse,
      );
      expect(
        ShellNavigation.locationIsUnder('/imaging', '/dashboard'),
        isFalse,
      );
    });

    test('every primary route still resolves to its own index', () {
      for (var i = 0; i < ShellNavigation.primaryRoutes.length; i++) {
        expect(
          ShellNavigation.primaryIndexForLocation(
            ShellNavigation.primaryRoutes[i],
          ),
          i,
        );
      }
    });

    test('isBottomNavRoute covers consolidated routes only', () {
      expect(ShellNavigation.isBottomNavRoute('/guiding'), isTrue);
      expect(ShellNavigation.isBottomNavRoute('/weather'), isTrue);
      // Settings, Science and the folded surfaces are no longer rail routes.
      expect(ShellNavigation.isBottomNavRoute('/settings'), isFalse);
      expect(ShellNavigation.isBottomNavRoute('/science'), isFalse);
      expect(ShellNavigation.isBottomNavRoute('/transients'), isFalse);
      expect(ShellNavigation.isBottomNavRoute('/polar-alignment'), isFalse);
    });
  });
}
