import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/session_review/session_review_controller.dart';
import 'package:nightshade_app/screens/session_review/session_review_screen.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('remote review is guarded before its local DAO controller starts',
      (tester) async {
    const scope = SessionReviewScope.session(42);
    final backend = _MockNetworkBackend();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWith(
            (ref) => _FixedBackendNotifier(ref, backend),
          ),
          sessionReviewControllerProvider(scope).overrideWith(
            (ref) => throw StateError(
              'The local SessionReviewController must not start remotely',
            ),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const SessionReviewScreen(scope: scope),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Open Session Review on the imaging host'),
      findsOneWidget,
    );
    expect(find.textContaining('Remote Session Review is unavailable'),
        findsOneWidget);
  });
}
