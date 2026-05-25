import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/scheduler/widgets/integration_goals_editor.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

void main() {
  testWidgets('new scheduler goals use Smart Night exposure recommendations',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          integrationGoalProgressProvider.overrideWith(
            (ref, targetId) async => const <IntegrationGoalProgress>[],
          ),
          smartNightExposureContextProvider.overrideWith(
            (ref) async => const SmartNightExposureContext(
              camera: CameraExposureSpec(
                readNoiseE: 1.5,
                fullWellE: 18000,
                qePeak: 0.8,
              ),
              bortleClass: 5,
              focalLengthMm: 480,
              apertureMm: 80,
              pixelSizeMicrons: 3.76,
              availableFilterNames: ['Ha', 'L'],
            ),
          ),
        ],
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: IntegrationGoalsEditor(
              targetId: 42,
              targetName: 'North America Nebula',
              availableFilters: ['Ha', 'L'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('180'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ha').last);
    await tester.pumpAndSettle();

    expect(find.text('300'), findsOneWidget);
    expect(find.text('180'), findsNothing);
  });
}
