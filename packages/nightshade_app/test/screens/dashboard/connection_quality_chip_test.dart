import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/connection_quality_chip.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import '../../harness/mock_database.dart' show inMemoryDatabaseOverride;

void main() {
  testWidgets('quality stream failure is never labeled Local', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryDatabaseOverride(),
          connectionQualityProvider.overrideWith(
            (ref) => Stream<ConnectionQuality>.error(
              StateError('quality unavailable'),
            ),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: ConnectionQualityChip(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Error'), findsOneWidget);
    expect(find.text('Local'), findsNothing);
  });

  // A failed "Connect to Server" leaves a DisconnectedBackend installed, which
  // is not a NetworkBackend. Collapsing "not a NetworkBackend" into
  // ConnectionQuality.local puts a quiet grey "Local" chip on the command bar
  // while the shell's red banner two rows above says the app is not connected —
  // and the chip is the one the operator reads to answer "is this machine
  // driving my mount".
  //
  // Drives the REAL provider off the real backendProvider, so a label lookup
  // alone cannot satisfy this.
  testWidgets('a machine with no backend is not labelled Local',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inMemoryDatabaseOverride(),
          backendProvider.overrideWith(
              (ref) => _PinnedBackend(ref, DisconnectedBackend())),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: ConnectionQualityChip(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Local'),
      findsNothing,
      reason: 'nothing is attached — every device call fails',
    );
    expect(find.text('No backend'), findsOneWidget);
  });
}

class _PinnedBackend extends BackendNotifier {
  _PinnedBackend(super.ref, NightshadeBackend backend) {
    // ignore: invalid_use_of_protected_member
    state = backend;
  }
}
