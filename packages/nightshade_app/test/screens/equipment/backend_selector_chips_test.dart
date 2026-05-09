import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/equipment/widgets/backend_selector_chips.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  test('unsupportedBackendReasonFor gates ASCOM COM off Linux', () {
    expect(
      unsupportedBackendReasonFor(
        DriverType.ascom,
        PlatformCapabilityMatrix.linux,
      ),
      contains('Windows COM drivers'),
    );
    expect(
      unsupportedBackendReasonFor(
        DriverType.alpaca,
        PlatformCapabilityMatrix.linux,
      ),
      isNull,
    );
  });

  testWidgets('BackendSelectorChips disables unsupported platform backends',
      (tester) async {
    DriverType? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: NightshadeTheme.dark,
        home: Scaffold(
          body: Center(
            child: BackendSelectorChips(
              availableBackends: const [
                DriverType.ascom,
                DriverType.alpaca,
              ],
              selectedBackend: DriverType.alpaca,
              recommendedBackend: DriverType.alpaca,
              currentPlatform: PlatformCapabilityMatrix.linux,
              onBackendSelected: (backend) {
                selected = backend;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('ASCOM COM'), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);

    await tester.tap(find.text('ASCOM COM'));
    await tester.pump();
    expect(selected, isNull);

    await tester.tap(find.text('Alpaca'));
    await tester.pump();
    expect(selected, DriverType.alpaca);
  });
}
