import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/sequencer/widgets/run_dashboard/broadcast_panel.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('active broadcast renders a scannable QR for the broadcast URL',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveStackingBroadcastServiceProvider.overrideWith((ref) {
            final service = LiveStackingBroadcastService(ref);
            service.activate(
              LiveStackingNode(
                broadcastPath: '/stack',
                broadcastPort: 8123,
              ),
            );
            return service;
          }),
          liveStackingKillSwitchBridgeProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: BroadcastPanel(),
          ),
        ),
      ),
    );
    await tester.pump();

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.semanticsLabel, 'Broadcast QR: http://localhost:8080/stack');
    expect(find.byIcon(Icons.qr_code_2), findsNothing);
  });
}
