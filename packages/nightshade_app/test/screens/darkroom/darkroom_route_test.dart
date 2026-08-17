// The Darkroom's place in the shell: a real route inside the ShellRoute, a
// screen the notification filter can name, and deliberately no rail slot.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/router/app_router.dart';
import 'package:nightshade_app/screens/shell/shell_navigation.dart';
import 'package:nightshade_core/nightshade_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('/darkroom is a named route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    expect(
      router.namedLocation(
        'darkroom',
        queryParameters: const {'recipe': '12'},
      ),
      '/darkroom?recipe=12',
    );
  });

  test('the rail lights nothing while the Darkroom is up', () {
    // −1 is the correct answer for every route no rail destination hosts. The
    // Darkroom is always about one master, so a rail slot would lead to a
    // screen with nothing to open; defaulting to 0 would light Dashboard and
    // make the rail claim the operator is somewhere they are not.
    expect(ShellNavigation.primaryIndexForLocation('/darkroom'), -1);
    expect(
      ShellNavigation.primaryIndexForLocation('/darkroom?recipe=12'),
      -1,
    );
    expect(ShellNavigation.isBottomNavRoute('/darkroom'), isFalse);
  });

  test('the screen tracker names the Darkroom', () {
    // Without the arm this reads as `unknown`, and the smart notification
    // filter would pop "your draft is ready" over the screen showing it.
    expect(locationToAppScreen('/darkroom'), AppScreen.darkroom);
    expect(locationToAppScreen('/darkroom?master=3'), AppScreen.darkroom);
  });
}
