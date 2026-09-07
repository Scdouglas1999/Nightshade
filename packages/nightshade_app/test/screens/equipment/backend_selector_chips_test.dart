import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
    expect(find.byIcon(LucideIcons.ban), findsOneWidget);

    await tester.tap(find.text('ASCOM COM'));
    await tester.pump();
    expect(selected, isNull);

    await tester.tap(find.text('Alpaca'));
    await tester.pump();
    expect(selected, DriverType.alpaca);
  });

  testWidgets('an unsupported backend reads as a disabled button to a11y',
      (tester) async {
    final handle = tester.ensureSemantics();

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
              onBackendSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    // The same refusal the ban icon makes, reaching assistive tech.
    expect(
      tester.getSemantics(find.text('ASCOM COM')),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: false,
        label: 'ASCOM COM',
        hint: 'Unsupported on this platform: '
            '${unsupportedBackendReasonFor(DriverType.ascom, PlatformCapabilityMatrix.linux)}',
        hasSelectedState: true,
        isSelected: false,
      ),
    );

    expect(
      tester.getSemantics(find.text('Alpaca')),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        label: 'Alpaca',
        hint: DriverType.alpaca.description,
        hasSelectedState: true,
        isSelected: true,
      ),
    );

    handle.dispose();
  });
}
