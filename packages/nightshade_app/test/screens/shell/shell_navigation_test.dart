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
