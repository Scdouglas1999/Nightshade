// WF-SS-N2: the pairing screen trapped the nav rail while the rail claimed to
// move.
//
// Live evidence: Settings ▸ Remote Access ▸ Manage Pairing, then click
// "Dashboard" in the left rail. The rail row repainted as selected, and 14 s
// later `tree` still returned `header: Remote Connection Pairing`; a second
// click changed nothing; the screen's own back arrow then landed on the
// Dashboard rather than on Remote Access — proof that the `go` HAD taken
// effect underneath the screen that stayed on top.
//
// Mechanism: the screen was pushed with `Navigator.push(MaterialPageRoute(...))`
// onto the shell's navigator, so it is not part of go_router's match list.
// `go()` rebuilds that list and the pushed route rides above the result. A
// route registered under the same `ShellRoute` and entered with `push` IS part
// of the list, and `go()` replaces it.
//
// Both halves are pinned here: the framework behaviour that made the trap, and
// the app's own wiring.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nightshade_app/router/app_router.dart';

Widget _shell(BuildContext context, Widget child) {
  return Scaffold(
    body: Row(
      children: [
        // The nav rail: one destination, driven exactly as AppShell drives it.
        TextButton(
          onPressed: () => context.go('/dashboard'),
          child: const Text('rail:Dashboard'),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/settings',
    routes: [
      ShellRoute(
        builder: (context, state, child) => _shell(context, child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const Text('DASHBOARD'),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, __) => TextButton(
              onPressed: () => context.push('/pairing'),
              child: const Text('open pairing (routed)'),
            ),
          ),
          GoRoute(
            path: '/pairing',
            builder: (_, __) => const Text('PAIRING'),
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('a rail destination escapes a routed pairing push',
      (tester) async {
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open pairing (routed)'));
    await tester.pumpAndSettle();
    expect(find.text('PAIRING'), findsOneWidget);

    await tester.tap(find.text('rail:Dashboard'));
    await tester.pumpAndSettle();

    expect(
      find.text('PAIRING'),
      findsNothing,
      reason: 'the rail said it moved, so it must actually move',
    );
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  testWidgets('back from pairing returns to the screen that opened it',
      (tester) async {
    // The second half of the same finding: the in-screen back arrow "lands on
    // the destination the rail had silently re-pointed to underneath" — it
    // went to the Dashboard, not back to Remote Access. With pairing on the
    // match list, back is a router pop and lands where it came from.
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open pairing (routed)'));
    await tester.pumpAndSettle();

    final pairingContext = tester.element(find.text('PAIRING'));
    Navigator.of(pairingContext).maybePop();
    await tester.pumpAndSettle();

    expect(find.text('open pairing (routed)'), findsOneWidget);
    expect(find.text('DASHBOARD'), findsNothing);
  });

  test('the app registers pairing as a shell route', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    addTearDown(router.dispose);

    expect(router.configuration.namedLocation('pairing'), '/pairing');
  });
}
