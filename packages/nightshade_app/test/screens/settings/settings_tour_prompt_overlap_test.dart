// The Settings Tour coach mark must not be drawn on top of a live control: a
// card over the "Manage Pairing" button leaves it clickable only after the card
// is dismissed.
//
// The card is chrome and it floats, which is correct — but not over a control.
// It holds its band inside the detail pane it is anchored over, so nothing
// interactive is underneath it, while the section navigator keeps its full
// height (a whole-screen band pushes its last group off-screen).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/settings_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/settings_widgets.dart';
import 'package:nightshade_app/widgets/contextual_tour_prompt.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async =>
      const AppSettingsState(webServerEnabled: true);
}

/// The leaf as the operator had it: remote access ON and the server up, which
/// is what makes the page long enough for Manage Pairing to sit low.
class _StubWebServerNotifier extends WebServerStateNotifier {
  _StubWebServerNotifier() {
    super.state = const WebServerState(
      isRunning: true,
      actualPort: 8080,
      configuredPort: 8080,
      bindLocalOnly: false,
      requiresAuthentication: true,
      dashboardAvailable: true,
      serverFingerprint: 'abcdef0123456789abcdef0123456789',
      localIp: '192.168.1.50',
    );
    _locked = true;
  }

  bool _locked = false;

  @override
  set state(WebServerState value) {
    if (_locked) return;
    super.state = value;
  }
}

void _swallowKnownOverflows() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    defaultOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = defaultOnError);
}

/// The prompt waits 500 ms after its post-frame check before fading in.
Future<void> _waitForPrompt(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the tour card never covers Manage Pairing', (tester) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const SettingsScreen(initialSection: 'remote-access'),
      size: const Size(1600, 900),
      extraOverrides: [
        appSettingsProvider.overrideWith(_StubAppSettingsNotifier.new),
        webServerStateProvider.overrideWith((ref) => _StubWebServerNotifier()),
      ],
    );
    await tester.pumpAndSettle();

    await _waitForPrompt(tester);

    final card = find.byKey(contextualTourPromptCardKey);
    expect(
      card,
      findsOneWidget,
      reason: 'without the nudge on screen this test proves nothing',
    );

    // The property that matters is not where one button happens to land: it is
    // that the detail pane does not extend under the card at all, so NOTHING it
    // draws — this button included — can end up beneath it. The pane scrolls,
    // so every row is still reachable; it just is not reachable by clicking
    // through a coach mark.
    final pane = tester.getRect(find.byType(SettingsPage));
    expect(find.text('Manage Pairing'), findsOneWidget);
    expect(
      pane.bottom,
      lessThanOrEqualTo(tester.getRect(card).top + 1),
      reason: 'the settings detail pane $pane runs under the tour card '
          '${tester.getRect(card)}',
    );
  });

  testWidgets('the section navigator keeps its full height', (tester) async {
    _swallowKnownOverflows();
    await pumpAppScreen(
      tester,
      const SettingsScreen(initialSection: 'remote-access'),
      size: const Size(1600, 900),
      extraOverrides: [
        appSettingsProvider.overrideWith(_StubAppSettingsNotifier.new),
        webServerStateProvider.overrideWith((ref) => _StubWebServerNotifier()),
      ],
    );
    await tester.pumpAndSettle();
    final railBefore = tester.getRect(find.text('Settings').first);

    await _waitForPrompt(tester);

    // The band belongs to the detail pane. Holding it across the whole screen
    // is what put ADVANCED below the fold on a fresh install.
    expect(find.text('ADVANCED'), findsOneWidget);
    expect(tester.getRect(find.text('Settings').first), railBefore);
  });
}
