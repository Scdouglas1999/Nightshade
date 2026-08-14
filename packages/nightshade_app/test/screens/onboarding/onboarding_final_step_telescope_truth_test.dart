// WD-N3: the wizard's closing step re-asserted a library scope the user had
// already edited away from.
//
// Live on 2026-08-13: step 8 → Choose from telescope library → Askar FRA400,
// then focal length ctrl+a → 1234. The optics step correctly flipped its badge
// to "Askar FRA400 — edited". Step 13 ("You're all set") then read
// "Telescope  Askar FRA400" beside "Image scale 0.77 arcsec/px" — a scale
// computed from 1234 mm, which is not that scope's focal length. The honest
// marker was dropped exactly where the wizard makes its closing statement
// about the rig.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/onboarding/steps/next_steps_step.dart';
import 'package:nightshade_core/nightshade_core.dart';
// ignore: implementation_imports
import 'package:nightshade_core/src/providers/hardware_presets_provider.dart';
import 'package:nightshade_ui/nightshade_ui.dart';

Future<ProviderContainer> _pumpFinalStep(WidgetTester tester) async {
  final db = NightshadeDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 1600);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: Consumer(builder: (ctx, ref, _) {
        container = ProviderScope.containerOf(ctx);
        return MaterialApp(
          theme: NightshadeTheme.dark,
          home: Scaffold(
            body: OnboardingNextStepsStep(onNavigate: (_) {}),
          ),
        );
      }),
    ),
  );
  await tester.pump();
  await container.read(onboardingDraftProvider.notifier).loaded;
  await tester.pumpAndSettle();
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an untouched library scope is named plainly', (tester) async {
    final container = await _pumpFinalStep(tester);
    final preset =
        container.read(hardwarePresetsServiceProvider).allTelescopes().first;
    await container
        .read(onboardingDraftProvider.notifier)
        .applyTelescopePreset(preset);
    await tester.pumpAndSettle();

    expect(find.text(preset.displayName), findsOneWidget);
    expect(find.text('${preset.displayName} — edited'), findsNothing);
  });

  testWidgets('an edited library scope keeps its "edited" marker to the end',
      (tester) async {
    final container = await _pumpFinalStep(tester);
    final notifier = container.read(onboardingDraftProvider.notifier);
    final preset =
        container.read(hardwarePresetsServiceProvider).allTelescopes().first;
    await notifier.applyTelescopePreset(preset);
    await notifier.setOpticalTrain(focalLengthMm: 1234);
    await tester.pumpAndSettle();

    expect(
      find.text(preset.displayName),
      findsNothing,
      reason: 'the rig no longer has that scope’s focal length',
    );
    expect(find.text('${preset.displayName} — edited'), findsOneWidget);
  });

  testWidgets('a hand-entered rig still reports its focal length',
      (tester) async {
    final container = await _pumpFinalStep(tester);
    await container
        .read(onboardingDraftProvider.notifier)
        .setOpticalTrain(focalLengthMm: 530, apertureMm: 100);
    await tester.pumpAndSettle();

    expect(find.text('530 mm'), findsOneWidget);
  });
}
