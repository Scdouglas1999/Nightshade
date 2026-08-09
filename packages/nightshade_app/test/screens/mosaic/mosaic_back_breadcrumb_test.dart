// Regression guard for: "The mosaic project screen's back breadcrumb always
// says 'Mosaic projects' even when it returns somewhere else".
//
// The label was a bare string literal beside the back button, but the handler
// POPS: reached from the Collaborative Sky mosaic detail (Join mosaic), from
// Framing, or from the sequencer mosaic wizard, pressing '< Mosaic projects'
// returns to THAT screen, not to the projects list. Only an empty stack — where
// the handler falls back to context.go('/mosaic') — really lands there.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/mosaic/mosaic_project_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

/// The remote guard renders the screen's chrome (including the back bar) with
/// no database work, which is all this test needs.
List<Override> _overrides() => [
      backendProvider.overrideWith(
        (ref) => _FixedBackendNotifier(ref, _MockNetworkBackend()),
      ),
      mosaicProjectsDaoProvider.overrideWith(
        (ref) => throw StateError('no DAO work in this test'),
      ),
    ];

Widget _app(Widget home) => ProviderScope(
      overrides: [..._overrides()],
      child: MaterialApp(theme: NightshadeTheme.dark, home: home),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'an empty stack promises the projects list, because it goes there',
      (tester) async {
    await tester.pumpWidget(_app(
      const MosaicProjectScreen(projectId: 42, artifactsBaseDir: '/m'),
    ));
    await tester.pump();

    expect(find.text('Mosaic projects'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('pushed on top of another screen it says Back', (tester) async {
    await tester.pumpWidget(_app(
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                // Stands in for the Collaborative Sky mosaic detail, which
                // pushes exactly this route after "Join mosaic".
                builder: (_) => const MosaicProjectScreen(
                  projectId: 42,
                  artifactsBaseDir: '/m',
                ),
              ),
            ),
            child: const Text('join'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('join'));
    await tester.pumpAndSettle();

    expect(find.text('Mosaic projects'), findsNothing,
        reason: 'this control returns to whatever pushed it, not to the list');
    expect(find.text('Back'), findsOneWidget);

    // ...and it really does return there.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('join'), findsOneWidget);
  });
}
