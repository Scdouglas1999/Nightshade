// Regression: with no appliance connected, Settings › Appliance Catalogs
// rendered a single sentence — "Connect to a remote appliance to manage its
// catalogs. This is separate from the phone's own planetarium catalogs." — and
// nothing else. On the Linux/Windows desktop build there is no phone, and the
// page carried no button, picker or link to the connection flow it named, so
// the leaf was inert and its only sentence was about a different platform.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/rig_catalog_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

/// A local (non-network) backend: exactly the desktop-with-no-appliance case.
class _MockLocalBackend extends Mock implements NightshadeBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

Future<GoRouter> _pump(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (_, __) =>
            const Scaffold(body: RigCatalogSettings(isMobile: true)),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider.overrideWith(
          (ref) => _FixedBackendNotifier(ref, _MockLocalBackend()),
        ),
      ],
      child: MaterialApp.router(
        theme: NightshadeTheme.dark,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the not-connected page never calls this machine a phone',
      (tester) async {
    await _pump(tester);

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' ');
    expect(texts.toLowerCase(), isNot(contains('phone')));
    expect(texts, contains("this device's own planetarium catalogs"));
  });

  testWidgets('the not-connected page offers a way to reach the connect flow',
      (tester) async {
    final router = await _pump(tester);

    final connect =
        find.widgetWithText(NightshadeButton, 'Connect an appliance');
    expect(connect, findsOneWidget);
    expect(tester.widget<NightshadeButton>(connect).onPressed, isNotNull);

    await tester.tap(connect);
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      '/settings?section=remote-access',
    );
  });
}
