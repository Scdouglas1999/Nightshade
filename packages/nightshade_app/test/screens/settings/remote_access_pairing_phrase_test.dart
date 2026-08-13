// SET-18: "Start pairing mode to show a QR code and pairing phrase on this
// screen" produced a QR and nothing else — no phrase, no expiry, no way to
// leave pairing mode, and the whole card reduced in the accessibility tree to
// "panel: Pair phones and tablets" plus a disabled empty text node, so a blind
// operator had no path to pair a phone at all.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/pairing_screen.dart';
import 'package:nightshade_app/screens/settings/widgets/remote_access_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

import '../../harness/harness.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  _StubAppSettingsNotifier(this._initial);

  final AppSettingsState _initial;

  @override
  Future<AppSettingsState> build() async => _initial;
}

/// Pairing parked mid-session with a live code and a known expiry.
class _StubPairingNotifier extends PairingNotifier {
  _StubPairingNotifier(String? pairingCode, Duration? remaining) {
    state = PairingState(
      pairingCode: pairingCode,
      expiresAt:
          remaining == null ? null : DateTime.now().add(remaining + oneSecond),
    );
  }

  /// The countdown floors to whole seconds, so a hair of slack keeps the
  /// rendered `mm:ss` off a boundary.
  static const oneSecond = Duration(milliseconds: 900);
}

class _StubWebServerNotifier extends WebServerStateNotifier {
  _StubWebServerNotifier(WebServerState seed) {
    super.state = seed;
    _locked = true;
  }

  bool _locked = false;

  @override
  set state(WebServerState value) {
    if (_locked) return;
    super.state = value;
  }
}

const _running = WebServerState(
  isRunning: true,
  actualPort: 8080,
  configuredPort: 8080,
  bindLocalOnly: false,
  requiresAuthentication: true,
  dashboardAvailable: true,
  serverFingerprint: 'abcdef0123456789abcdef0123456789',
  localIp: '192.168.1.50',
);

Future<void> _pumpRemoteAccess(
  WidgetTester tester, {
  required String? pairingCode,
  Duration? remaining,
}) async {
  final database = mockDatabase();
  addTearDown(database.close);
  await pumpAppScreen(
    tester,
    const RemoteAccessSettings(),
    size: const Size(900, 1600),
    database: database,
    extraOverrides: [
      appSettingsProvider.overrideWith(
        () => _StubAppSettingsNotifier(
          const AppSettingsState(webServerEnabled: true),
        ),
      ),
      pairingProvider
          .overrideWith((ref) => _StubPairingNotifier(pairingCode, remaining)),
      webServerStateProvider
          .overrideWith((ref) => _StubWebServerNotifier(_running)),
    ],
    settle: false,
  );
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pairing mode shows the phrase, its expiry and a way out',
      (tester) async {
    await _pumpRemoteAccess(
      tester,
      pairingCode: 'NOVA-NEBULA-2638',
      remaining: const Duration(minutes: 4, seconds: 1),
    );

    expect(
      find.text('NOVA-NEBULA-2638'),
      findsOneWidget,
      reason: 'the card promises a pairing phrase alongside the QR',
    );
    expect(find.textContaining('Expires in 4:01'), findsOneWidget);
    expect(
      find.widgetWithText(NightshadeButton, 'Stop pairing mode'),
      findsOneWidget,
      reason: 'navigating away was the only exit from pairing mode',
    );
  });

  testWidgets('the phrase is text, so assistive tech can read it',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpRemoteAccess(
      tester,
      pairingCode: 'NOVA-NEBULA-2638',
      remaining: const Duration(minutes: 4, seconds: 1),
    );

    final phrase = tester.getSemantics(find.text('NOVA-NEBULA-2638'));
    expect(
      '${phrase.label}${phrase.value}',
      contains('NOVA-NEBULA-2638'),
      reason: 'the QR image is the one part of this card AT cannot convey',
    );
    expect(find.bySemanticsLabel(RegExp('Expires in 4:01')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('before pairing starts the card still offers only Start',
      (tester) async {
    await _pumpRemoteAccess(tester, pairingCode: null);

    expect(
      find.widgetWithText(NightshadeButton, 'Stop pairing mode'),
      findsNothing,
    );
  });
}
