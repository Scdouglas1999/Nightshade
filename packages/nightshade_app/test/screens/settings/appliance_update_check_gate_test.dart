// "Check for Updates" must not be offered to an appliance with nowhere to
// check.
//
// Reproduced live against a paired headless appliance: the version card said
// "No update server configured (set NIGHTSHADE_UPDATE_SERVER)" and the button
// was still enabled. Pressing it produced a GREEN snackbar
// ("Check request accepted") at the same instant as the status card flipped to
// "Update failed" with "Last error: UpdateException: Update server URL not
// configured" — a contradictory pair of answers to one press, and an alarming
// "Update failed" state manufactured out of a check that never ran.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nightshade_app/screens/settings/widgets/update_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

class _MockNetworkBackend extends Mock implements NetworkBackend {}

class _FixedBackendNotifier extends BackendNotifier {
  _FixedBackendNotifier(super.ref, NightshadeBackend backend) : super() {
    state = backend;
  }
}

RemoteVersionInfo _version({String? updateServerUrl}) => RemoteVersionInfo(
      currentVersion: '6.1.0',
      buildNumber: 25,
      platform: 'linux',
      updateServerUrl: updateServerUrl,
    );

Future<void> _pump(WidgetTester tester, _MockNetworkBackend backend) async {
  when(() => backend.getUpdateStatus())
      .thenAnswer((_) async => const RemoteUpdateStatus(state: 'idle'));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        backendProvider
            .overrideWith((ref) => _FixedBackendNotifier(ref, backend)),
      ],
      child: MaterialApp(
        theme: NightshadeTheme.dark,
        home: const Scaffold(body: UpdateSettings(isMobile: true)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

NightshadeButton _checkButton(WidgetTester tester) =>
    tester.widget<NightshadeButton>(
      find.widgetWithText(NightshadeButton, 'Check for Updates'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the check is disabled when the rig has no update server',
      (tester) async {
    final backend = _MockNetworkBackend();
    when(() => backend.getSystemVersion())
        .thenAnswer((_) async => _version(updateServerUrl: null));

    await _pump(tester, backend);

    expect(find.textContaining('No update server configured'), findsOneWidget);
    expect(_checkButton(tester).onPressed, isNull);
  });

  testWidgets('the check is offered when the rig has an update server',
      (tester) async {
    final backend = _MockNetworkBackend();
    when(() => backend.getSystemVersion()).thenAnswer(
      (_) async => _version(updateServerUrl: 'https://updates.example.com'),
    );

    await _pump(tester, backend);

    expect(_checkButton(tester).onPressed, isNotNull);
  });
}
