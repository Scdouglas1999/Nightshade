import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/shell/shell_navigation.dart';

void main() {
  group('ShellNavigation', () {
    test('primaryDestinations exposes the consolidated desktop side-nav', () {
      expect(ShellNavigation.primaryDestinations, hasLength(8));
      expect(
        ShellNavigation.primaryRoutes,
        [
          '/dashboard',
          '/equipment',
          '/imaging',
          '/sequencer',
          '/analytics',
          '/science',
          '/planner',
          '/settings',
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
        '/science',
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
      expect(ShellNavigation.isBottomNavRoute('/science'), isTrue);
      expect(ShellNavigation.isBottomNavRoute('/settings'), isTrue);
      expect(ShellNavigation.isBottomNavRoute('/transients'), isFalse);
      expect(ShellNavigation.isBottomNavRoute('/polar-alignment'), isFalse);
    });
  });
}
