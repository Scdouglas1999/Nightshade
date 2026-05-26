import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:nightshade_app/screens/dashboard/widgets/smart_night_prompt_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    as planetarium;
import 'package:nightshade_ui/nightshade_ui.dart';

class _AutoPromptOffSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState(
        smartNightAutoPromptEnabled: false,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('suppresses the dashboard prompt when a pending draft exists',
      (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Backyard rig',
            focalLength: 600,
            aperture: 80,
            filterNames: ['L'],
          ),
        ),
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
        smartNightPromptGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final now = DateTime.now();
    await container.read(smartNightDraftServiceProvider).savePending(
          profileId: '7',
          astronomicalDay:
              now.hour < 12 ? now.subtract(const Duration(days: 1)) : now,
          plan: _plan('M51'),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SmartNightPromptCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build tonight\'s Smart Night plan?'), findsNothing);
    expect(find.text('Build Plan'), findsNothing);
  });

  testWidgets('hides the dashboard prompt when auto-prompt is disabled',
      (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        appSettingsProvider.overrideWith(_AutoPromptOffSettingsNotifier.new),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Backyard rig',
            focalLength: 600,
            aperture: 80,
            filterNames: ['L'],
          ),
        ),
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
        smartNightPromptGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SmartNightPromptCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resume tonight\'s Smart Night plan?'), findsNothing);
    expect(find.text('Load Plan'), findsNothing);
  });

  testWidgets('overflow menu persists the auto-prompt opt-out', (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Backyard rig',
            focalLength: 600,
            aperture: 80,
            filterNames: ['L'],
          ),
        ),
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
        smartNightPromptGraceProvider.overrideWithValue(Duration.zero),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SmartNightPromptCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(LucideIcons.moreVertical));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't ask again on connect"));
    await tester.pumpAndSettle();

    final settings = await container.read(appSettingsProvider.future);
    expect(settings.smartNightAutoPromptEnabled, isFalse);
    expect(find.text('Resume tonight\'s Smart Night plan?'), findsNothing);
  });

  testWidgets('waits through the equipment-ready grace period before showing',
      (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Backyard rig',
            focalLength: 600,
            aperture: 80,
            filterNames: ['L'],
          ),
        ),
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SmartNightPromptCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hardware ready - build tonight\'s plan?'), findsNothing);
    expect(find.text('Build Plan'), findsNothing);
  });

  testWidgets('hides the prompt when the active equipment profile is incomplete',
      (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        smartNightPromptGraceProvider.overrideWithValue(Duration.zero),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Incomplete rig',
            focalLength: 600,
            aperture: 0,
            filterNames: ['L'],
          ),
        ),
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SmartNightPromptCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hardware ready - build tonight\'s plan?'), findsNothing);
    expect(find.text('Build Plan'), findsNothing);
  });

  testWidgets('suppresses the dashboard prompt while a sequence is active',
      (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        sequenceExecutionStateProvider.overrideWith(
          (ref) => SequenceExecutionState.running,
        ),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Backyard rig',
            focalLength: 600,
            aperture: 80,
            filterNames: ['L'],
          ),
        ),
        appObserverLocationProvider.overrideWithValue(
          const LocationSettings(latitude: 40, longitude: -75),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    final now = DateTime.now();
    await container.read(smartNightDraftServiceProvider).savePending(
          profileId: '7',
          astronomicalDay:
              now.hour < 12 ? now.subtract(const Duration(days: 1)) : now,
          plan: _plan('M51'),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: NightshadeTheme.dark,
          home: const Scaffold(
            body: SmartNightPromptCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resume tonight\'s Smart Night plan?'), findsNothing);
    expect(find.text('Load Plan'), findsNothing);
  });
}

SmartNightPlan _plan(String targetName) {
  final root = InstructionSetNode(
    id: 'root',
    name: 'Smart Night Root',
    childIds: const ['target'],
  );
  final target = TargetHeaderNode(
    id: 'target',
    name: targetName,
    targetName: targetName,
    raHours: 13.5,
    decDegrees: 47.2,
    parentId: 'root',
  );
  final start = DateTime.now();
  final end = start.add(const Duration(hours: 5));
  return SmartNightPlan(
    sequence: Sequence.create(
      name: 'Smart Night $targetName',
      rootNodeId: 'root',
      nodes: {
        root.id: root,
        target.id: target,
      },
    ),
    plannedTargets: [
      SmartNightPlannedTarget(
        suggestion: TargetSuggestion(
          targetId: 42,
          targetName: targetName,
          catalogId: targetName,
          raHours: 13.5,
          decDegrees: 47.2,
          totalScore: 91,
          reasoning: 'Excellent tonight.',
          visibility: planetarium.TargetVisibilityInfo(
            currentAltitude: 72,
            currentAzimuth: 180,
            transitAltitude: 78,
            transitTime: start.add(const Duration(hours: 2)),
            airmass: 1.1,
            moonDistance: 100,
            hoursAboveMinAlt: 5,
          ),
        ),
        windowStart: start,
        windowEnd: end,
        filterPlans: const [
          SmartNightFilterPlan(
            filterName: 'L',
            count: 12,
            durationSecs: 120,
          ),
        ],
        integrationSecs: 1440,
        rationale: 'Best target tonight.',
      ),
    ],
    totalIntegrationSecs: 1440,
    estimatedWallClockSecs: 1800,
    warnings: const [],
    strategy: SmartNightStrategy.autoLrgb,
    settings: const SmartNightSettings(),
    context: SmartNightContext(windowStart: start, windowEnd: end),
  );
}
