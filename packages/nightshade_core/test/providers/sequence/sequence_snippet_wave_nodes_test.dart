import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/models/sequence/template_snippet.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';
import 'package:nightshade_core/src/providers/template_snippet_provider.dart';

ProviderContainer _newContainer() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('custom snippets serialize TargetScheduler and SmartExposure fields',
      () {
    final smart = SmartExposureNode(
      id: 'smart',
      name: 'Ha/OIII Plan',
      parentId: 'scheduler',
      orderIndex: 0,
      plans: const [
        FilterPlan(
          filterName: 'Ha',
          filterIndex: 4,
          count: 12,
          durationSecs: 300,
          gain: 101,
          offset: 20,
          ditherEvery: 2,
        ),
      ],
      rotateFilters: false,
      ditherOnFilterChange: true,
      integrationBudgetSecs: 3600,
      batchSize: 3,
    );
    final scheduler = TargetSchedulerNode(
      id: 'scheduler',
      name: 'Tonight Scheduler',
      childIds: const ['smart'],
      parentId: 'root',
      orderIndex: 0,
      altitudeWeight: 0.4,
      moonDistanceWeight: 0.2,
      transitProximityWeight: 0.15,
      darknessWeight: 0.15,
      airmassWeight: 0.1,
      minScoreToRun: 42,
      recomputeEveryNExposures: 2,
      finishIterationOnSwitch: false,
      swapOnConditionsBelow: 52,
      swapHysteresisSecs: 240,
      brightnessTierPreferences: const BrightnessTierPreferences(
        faintMinScore: 75,
        mediumMinScore: 55,
        brightMinScore: 35,
      ),
      maxConditionsScoreAgeSecs: 420,
    );
    final root = InstructionSetNode(
      id: 'root',
      name: 'Sequence',
      childIds: const ['scheduler'],
    );
    final sequence = Sequence.create(
      name: 'Snippet Source',
      rootNodeId: 'root',
      nodes: {
        root.id: root,
        scheduler.id: scheduler,
        smart.id: smart,
      },
    );

    final snippet = createSnippetFromSelection(
      name: 'Smart Scheduler',
      description: 'Scheduler with smart exposure child',
      category: SnippetCategory.filterSequence,
      iconName: 'layers',
      nodeIds: const ['scheduler'],
      sequence: sequence,
    );

    final schedulerJson = snippet.nodeData.single;
    expect(schedulerJson['nodeType'], 'TargetScheduler');
    expect(schedulerJson['minScoreToRun'], 42);
    expect(schedulerJson['recomputeEveryNExposures'], 2);
    expect(schedulerJson['finishIterationOnSwitch'], isFalse);
    expect(schedulerJson['swapOnConditionsBelow'], 52);
    expect(schedulerJson['swapHysteresisSecs'], 240);
    expect(schedulerJson['maxConditionsScoreAgeSecs'], 420);
    final tierPrefs =
        schedulerJson['brightnessTierPreferences'] as Map<String, dynamic>;
    expect(tierPrefs['faint_min_score'], 75);
    expect(tierPrefs['medium_min_score'], 55);
    expect(tierPrefs['bright_min_score'], 35);

    final smartJson =
        (schedulerJson['children'] as List).single as Map<String, dynamic>;
    expect(smartJson['nodeType'], 'SmartExposure');
    expect(smartJson['rotateFilters'], isFalse);
    expect(smartJson['ditherOnFilterChange'], isTrue);
    expect(smartJson['integrationBudgetSecs'], 3600);
    expect(smartJson['batchSize'], 3);
    final planJson =
        (smartJson['plans'] as List).single as Map<String, dynamic>;
    expect(planJson['filter_name'], 'Ha');
    expect(planJson['duration_secs'], 300);
    expect(planJson['dither_every'], 2);
  });

  test('snippet insertion rebuilds TargetScheduler and SmartExposure nodes',
      () {
    final container = _newContainer();
    final editor = container.read(currentSequenceProvider.notifier)
      ..createSequence();

    final snippet = TemplateSnippet.custom(
      name: 'Imported Smart Scheduler',
      description: 'Uses canonical smart nodes',
      iconName: 'layers',
      nodeData: [
        {
          'id': 'scheduler-old',
          'nodeType': 'target_scheduler',
          'name': 'Scheduler',
          'altitudeWeight': 0.35,
          'moonDistanceWeight': 0.25,
          'transitProximityWeight': 0.2,
          'darknessWeight': 0.1,
          'airmassWeight': 0.1,
          'minScoreToRun': 55,
          'recomputeEveryNExposures': 3,
          'finishIterationOnSwitch': false,
          'swap_on_conditions_below': 48,
          'swap_hysteresis_secs': 210,
          'brightness_tier_preferences': {
            'faint_min_score': 72,
            'medium_min_score': 51,
            'bright_min_score': 29,
          },
          'max_conditions_score_age_secs': 360,
          'children': [
            {
              'id': 'smart-old',
              'nodeType': 'smart_exposure',
              'name': 'Smart Exposure',
              'plans': [
                {
                  'filter_name': 'OIII',
                  'filter_index': 5,
                  'count': 8,
                  'duration_secs': 240,
                  'gain': 101,
                  'offset': 20,
                  'binning': 'One',
                  'dither_every': 2,
                },
              ],
              'rotateFilters': false,
              'ditherOnFilterChange': true,
              'integrationBudgetSecs': 1920,
              'batchSize': 2,
            },
          ],
        },
      ],
    );

    editor.insertSnippet(snippet);

    final sequence = container.read(currentSequenceProvider)!;
    final scheduler =
        sequence.nodes.values.whereType<TargetSchedulerNode>().single;
    expect(scheduler.minScoreToRun, 55);
    expect(scheduler.recomputeEveryNExposures, 3);
    expect(scheduler.finishIterationOnSwitch, isFalse);
    expect(scheduler.swapOnConditionsBelow, 48);
    expect(scheduler.swapHysteresisSecs, 210);
    expect(scheduler.maxConditionsScoreAgeSecs, 360);
    expect(scheduler.brightnessTierPreferences.faintMinScore, 72);
    expect(scheduler.brightnessTierPreferences.mediumMinScore, 51);
    expect(scheduler.brightnessTierPreferences.brightMinScore, 29);

    final smart = sequence.nodes.values.whereType<SmartExposureNode>().single;
    expect(smart.parentId, scheduler.id);
    expect(smart.plans, hasLength(1));
    expect(smart.plans.single.filterName, 'OIII');
    expect(smart.plans.single.durationSecs, 240);
    expect(smart.rotateFilters, isFalse);
    expect(smart.ditherOnFilterChange, isTrue);
    expect(smart.integrationBudgetSecs, 1920);
    expect(smart.batchSize, 2);
  });
}
