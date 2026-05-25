import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_app/screens/dashboard/widgets/tonight_card.dart';
import 'package:nightshade_core/nightshade_core.dart';
import 'package:nightshade_core/src/database/database.dart' as db;
import 'package:nightshade_planetarium/nightshade_planetarium.dart'
    as planetarium;
import 'package:nightshade_ui/nightshade_ui.dart';

class _FakeSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettingsState> build() async => const AppSettingsState(
        latitude: 40,
        longitude: -75,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Tonight card resumes a pending Smart Night draft',
      (tester) async {
    final database = db.NightshadeDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        appSettingsProvider.overrideWith(_FakeSettingsNotifier.new),
        activeEquipmentProfileProvider.overrideWithValue(
          const EquipmentProfileModel(
            id: 7,
            name: 'Backyard rig',
            focalLength: 600,
            aperture: 80,
            filterNames: ['L'],
          ),
        ),
        tonightSuggestionsProvider.overrideWith((ref) async => const []),
        planetarium.twilightTimesProvider.overrideWithValue(
          planetarium.TwilightTimes(
            astronomicalDusk: DateTime(2026, 5, 22, 21),
            astronomicalDawn: DateTime(2026, 5, 23, 5),
          ),
        ),
        planetarium.moonInfoProvider.overrideWithValue(
          const planetarium.MoonTimes(
            illumination: 22,
            phaseName: 'Waning Crescent',
          ),
        ),
        planetarium.observationTimeProvider.overrideWith(
          (ref) => planetarium.ObservationTimeNotifier()
            ..setTime(DateTime(2026, 5, 22, 20)),
        ),
      ],
    );
    var cleanedUp = false;
    Future<void> cleanup() async {
      if (cleanedUp) return;
      cleanedUp = true;
      container.dispose();
      await database.close();
    }

    addTearDown(cleanup);

    final now = DateTime.now();
    final draft =
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
            body: TonightCard(colors: NightshadeColors.dark),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('View tonight\'s plan'), findsOneWidget);

    await tester.tap(find.text('View tonight\'s plan'));
    await tester.pumpAndSettle();

    expect(container.read(currentSequenceProvider)?.name, 'Smart Night M51');
    final updated =
        await container.read(smartNightDraftServiceProvider).loadById(draft.id);
    expect(updated?.status, SmartNightDraftStatus.pending,
        reason: 'Viewing a saved Smart Night plan should keep it pending; '
            'only an explicit start/run action should mark the draft started.');

    await tester.pumpWidget(const SizedBox.shrink());
    await cleanup();
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
    sequence: Sequence(
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
