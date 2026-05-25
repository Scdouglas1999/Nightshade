import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/shell_navigation.dart';

void main() {
  group('ShellNavigation', () {
    test('primaryDestinations exposes eleven desktop side-nav routes', () {
      expect(ShellNavigation.primaryDestinations, hasLength(11));
      expect(
        ShellNavigation.primaryRoutes,
        [
          '/dashboard',
          '/equipment',
          '/imaging',
          '/guiding',
          '/sequencer',
          '/planetarium',
          '/framing',
          '/analytics',
          '/flat-wizard',
          '/weather',
          '/planner',
        ],
      );
    });

    test('bottomNavigationDestinations has thirteen mobile slots', () {
      expect(ShellNavigation.bottomNavigationDestinations, hasLength(13));
      final routes = ShellNavigation.bottomNavigationDestinations
          .map((d) => d.route)
          .toList();
      expect(routes, contains('/transients'));
      expect(routes, contains('/settings'));
      expect(routes, contains('/dashboard'));
    });

    test('primaryIndexForLocation resolves planner and ignores query', () {
      expect(
        ShellNavigation.primaryIndexForLocation('/planner?tab=scheduler'),
        10,
      );
      expect(ShellNavigation.primaryRouteForIndex(10), '/planner');
    });

    test('isBottomNavRoute includes transients and settings', () {
      expect(ShellNavigation.isBottomNavRoute('/transients'), isTrue);
      expect(ShellNavigation.isBottomNavRoute('/settings'), isTrue);
      expect(ShellNavigation.isBottomNavRoute('/polar-alignment'), isFalse);
    });
  });
}
