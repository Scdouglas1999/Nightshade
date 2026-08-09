// Settings → Connection must let the operator say WHERE the Alpaca server is.
//
// Shipped state: the page carried "Query Alpaca on startup / Include the
// configured Alpaca server in automatic startup discovery" with no address row
// anywhere, and `grep -rn setAlpacaServerHost packages/nightshade_app` returned
// nothing — so the address `unified_discovery_provider` consults was pinned to
// the stored default localhost:11111 for the life of the install, while the
// same page recommends Alpaca for cross-platform rigs that typically live on
// another machine on the LAN.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/settings/widgets/connection_settings.dart';
import 'package:nightshade_core/nightshade_core.dart';

import '../../harness/harness.dart';

class _StubAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the Alpaca address is shown and can be changed', (tester) async {
    final handle = await pumpAppScreen(
      tester,
      const ConnectionSettings(),
      size: const Size(1280, 1600),
      extraOverrides: [
        appSettingsProvider.overrideWith(_StubAppSettingsNotifier.new),
      ],
    );
    await tester.pumpAndSettle();

    final row = find.text('Alpaca Server Address');
    expect(row, findsOneWidget);
    expect(
      find.textContaining('localhost:11111'),
      findsWidgets,
      reason: 'the row must show the address discovery will actually use',
    );

    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    // The Configure button belonging to the Alpaca row: INDI's row (present on
    // Linux/macOS) renders the same label above it.
    await tester.tap(find.text('Configure').last);
    await tester.pumpAndSettle();

    expect(find.text('Alpaca Server Configuration'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('alpaca-host-field')),
      '192.168.1.47',
    );
    await tester.enterText(
      find.byKey(const ValueKey('alpaca-port-field')),
      '32323',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final settings = handle.container.read(appSettingsProvider).requireValue;
    expect(settings.alpacaServerHost, '192.168.1.47');
    expect(settings.alpacaServerPort, 32323);
    // And the page now reports the address that was stored.
    expect(find.textContaining('192.168.1.47:32323'), findsWidgets);
  });

  testWidgets('a malformed port is refused rather than coerced', (
    tester,
  ) async {
    final handle = await pumpAppScreen(
      tester,
      const ConnectionSettings(),
      size: const Size(1280, 1600),
      extraOverrides: [
        appSettingsProvider.overrideWith(_StubAppSettingsNotifier.new),
      ],
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Alpaca Server Address'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Configure').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('alpaca-port-field')),
      '99999',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Port must be between 1 and 65535.'), findsOneWidget);
    expect(
      handle.container.read(appSettingsProvider).requireValue.alpacaServerPort,
      11111,
    );
  });
}
