// Audit C6 — SmartExposure per-row filter-name validation tests.
//
// Covers SmartExposureFilterUnknownRule: each enabled SmartExposure row
// whose `filterName` is non-empty must reference a filter present in the
// active equipment profile. Tests also pin down interaction with the
// pre-existing empty-filter and missing-wheel rules so we don't
// double-count or paper over their findings.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/profiles_provider.dart';
import 'package:nightshade_core/src/providers/sequence/rules/smart_exposure_rules.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_validation.dart';

/// Build a single-node sequence wrapping the given SmartExposure node.
Sequence _sequenceWith(SmartExposureNode node) {
  return Sequence.create(
    id: 'seq',
    name: 'test',
    nodes: {node.id: node},
    rootNodeId: node.id,
  );
}

/// Compose a SmartExposureNode from a list of (filterName, count) pairs so
/// individual tests stay readable.
SmartExposureNode _smartNode(
  List<FilterPlan> plans, {
  bool isEnabled = true,
}) {
  return SmartExposureNode(
    id: 'smart-1',
    name: 'Smart Exposure',
    isEnabled: isEnabled,
    plans: plans,
  );
}

/// Spin up a ProviderContainer with the given filter list on the active
/// profile. Pass `profileFilters = null` to leave the profile null
/// entirely (the "no active profile" path).
ProviderContainer _container({required List<String>? profileFilters}) {
  final container = ProviderContainer(
    overrides: [
      activeEquipmentProfileProvider.overrideWithValue(
        profileFilters == null
            ? null
            : EquipmentProfileModel(
                name: 'Test Rig',
                focalLength: 600,
                aperture: 80,
                filterNames: profileFilters,
              ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Drive a closure with a real Riverpod [Ref] so a [ValidationContext] can
/// be constructed. Mirrors the helper in sequence_validation_ref_aware_test.
T _withRef<T>(ProviderContainer container, T Function(Ref ref) body) {
  final probe = Provider<T>((ref) => body(ref));
  return container.read(probe);
}

List<ValidationIssue> _runRule(
  ProviderContainer container,
  Sequence sequence,
) {
  final rule = SmartExposureFilterUnknownRule();
  return _withRef(
    container,
    (ref) => rule.validate(sequence, ValidationContext(ref)),
  );
}

void main() {
  group('SmartExposureFilterUnknownRule', () {
    test('row with filter present in profile = no issue', () {
      final container = _container(profileFilters: ['L', 'R', 'G', 'B']);
      final node = _smartNode([
        const FilterPlan(filterName: 'L', count: 5, durationSecs: 60),
        const FilterPlan(filterName: 'R', count: 5, durationSecs: 120),
      ]);
      expect(_runRule(container, _sequenceWith(node)), isEmpty);
    });

    test('row with unknown filter raises one error per offending row', () {
      final container = _container(profileFilters: ['L', 'R', 'G', 'B']);
      final node = _smartNode([
        const FilterPlan(filterName: 'L', count: 5, durationSecs: 60),
        const FilterPlan(filterName: 'OIII', count: 5, durationSecs: 300),
        const FilterPlan(filterName: 'SII', count: 5, durationSecs: 300),
      ]);

      final issues = _runRule(container, _sequenceWith(node));
      expect(issues, hasLength(2));

      final oiii = issues.firstWhere(
        (i) => i.description.contains('"OIII"'),
        orElse: () => fail('Expected an issue mentioning OIII'),
      );
      expect(oiii.severity, ValidationSeverity.error);
      expect(oiii.category, ValidationCategory.equipment);
      expect(oiii.title, 'SmartExposure plan filter not in profile');
      expect(oiii.affectedNodeId, node.id);
      // Per-row diagnostics: must cite the 1-based row index and the
      // available set so the user knows exactly what's wrong.
      expect(oiii.description, contains('plan 2'));
      expect(oiii.description, contains('Available: L, R, G, B'));
      expect(oiii.resolutionHint, contains('OIII'));

      final sii = issues.firstWhere((i) => i.description.contains('"SII"'));
      expect(sii.description, contains('plan 3'));
      expect(sii.affectedNodeId, node.id);
    });

    test('comparison is case-insensitive (matches FilterInWheelRule)', () {
      final container = _container(profileFilters: ['L', 'Ha']);
      // Profile has "Ha"; row asks for "ha" — should be accepted.
      final node = _smartNode([
        const FilterPlan(filterName: 'ha', count: 5, durationSecs: 60),
      ]);
      expect(_runRule(container, _sequenceWith(node)), isEmpty);
    });

    test('empty filter name is left to the existing empty-filter rule', () {
      // SmartExposureNegativeCountRule already flags empty filterName as
      // an error. The new rule must NOT also fire for that row — otherwise
      // we'd double-count the same problem.
      final container = _container(profileFilters: ['L', 'R']);
      final node = _smartNode([
        const FilterPlan(filterName: '', count: 5, durationSecs: 60),
      ]);

      final unknownIssues = _runRule(container, _sequenceWith(node));
      expect(unknownIssues, isEmpty);

      // The existing empty-filter rule still fires — proves we didn't
      // accidentally silence it.
      final emptyRule = SmartExposureNegativeCountRule();
      final emptyIssues = emptyRule.validate(_sequenceWith(node));
      expect(
        emptyIssues.where((i) => i.title.contains('no filter')),
        hasLength(1),
      );
    });

    test('disabled SmartExposure node is ignored', () {
      final container = _container(profileFilters: ['L', 'R']);
      final node = _smartNode(
        [const FilterPlan(filterName: 'OIII', count: 5, durationSecs: 300)],
        isEnabled: false,
      );
      expect(_runRule(container, _sequenceWith(node)), isEmpty);
    });

    test('no active profile = silent (the missing-wheel rule reports it)', () {
      // When the profile is null, SmartExposureFilterWheelMissingRule emits
      // an info issue explaining the check was skipped. This rule defers to
      // that instead of double-reporting; verifying behaviour here pins
      // that contract in place.
      final container = _container(profileFilters: null);
      final node = _smartNode([
        const FilterPlan(filterName: 'OIII', count: 5, durationSecs: 300),
      ]);
      expect(_runRule(container, _sequenceWith(node)), isEmpty);
    });

    test('profile with empty filter list = silent (missing-wheel rule fires)',
        () {
      // Empty filter list means "no wheel configured" — the existing
      // SmartExposureFilterWheelMissingRule covers that. This rule should
      // not pile on with N redundant per-row errors.
      final container = _container(profileFilters: const []);
      final node = _smartNode([
        const FilterPlan(filterName: 'L', count: 5, durationSecs: 60),
        const FilterPlan(filterName: 'R', count: 5, durationSecs: 60),
      ]);
      expect(_runRule(container, _sequenceWith(node)), isEmpty);
    });

    test('rule is wired into defaultRefAwareSequenceValidators', () {
      // Audit guard: a sibling rule existed but wasn't registered for an
      // entire release. Pinning registration in a test catches regressions
      // where someone removes the entry while keeping the class.
      expect(
        defaultRefAwareSequenceValidators
            .whereType<SmartExposureFilterUnknownRule>(),
        hasLength(1),
      );
    });
  });

  group('SmartExposureUnboundedLoopRule', () {
    SmartExposureNode loopNode({
      required double budgetSecs,
      String parentId = 'root',
    }) {
      return SmartExposureNode(
        id: 'smart-1',
        parentId: parentId,
        loopUntilStopped: true,
        integrationBudgetSecs: budgetSecs,
        plans: const [FilterPlan(filterName: 'L', durationSecs: 60)],
      );
    }

    test('loop mode with no budget and no target window = error', () {
      final node = loopNode(budgetSecs: 0);
      final issues =
          SmartExposureUnboundedLoopRule().validate(_sequenceWith(node));
      expect(issues, hasLength(1));
      expect(issues.single.severity, ValidationSeverity.error);
      expect(issues.single.title, 'SmartExposure loop is unbounded');
    });

    test('loop mode with a positive integration budget = no issue', () {
      final node = loopNode(budgetSecs: 7200);
      expect(
        SmartExposureUnboundedLoopRule().validate(_sequenceWith(node)),
        isEmpty,
      );
    });

    test('loop mode under a target with endWhen = no issue', () {
      final target = TargetHeaderNode(
        id: 'target',
        targetName: 'M51',
        raHours: 13.5,
        decDegrees: 47.2,
        childIds: const ['smart-1'],
        endWhen: const TargetTrigger.altitudeBelow(20),
      );
      final node = loopNode(budgetSecs: 0, parentId: 'target');
      final sequence = Sequence.create(
        id: 'seq',
        name: 'test',
        nodes: {target.id: target, node.id: node},
        rootNodeId: target.id,
      );
      expect(
        SmartExposureUnboundedLoopRule().validate(sequence),
        isEmpty,
      );
    });

    test('loop mode under a target with endBefore = no issue', () {
      final target = TargetHeaderNode(
        id: 'target',
        targetName: 'M51',
        raHours: 13.5,
        decDegrees: 47.2,
        childIds: const ['smart-1'],
        endBefore: DateTime.utc(2030, 1, 1, 6),
      );
      final node = loopNode(budgetSecs: 0, parentId: 'target');
      final sequence = Sequence.create(
        id: 'seq',
        name: 'test',
        nodes: {target.id: target, node.id: node},
        rootNodeId: target.id,
      );
      expect(
        SmartExposureUnboundedLoopRule().validate(sequence),
        isEmpty,
      );
    });

    test('non-loop SmartExposure is never flagged by this rule', () {
      final node = SmartExposureNode(
        id: 'smart-1',
        plans: const [FilterPlan(filterName: 'L', count: 10, durationSecs: 60)],
      );
      expect(
        SmartExposureUnboundedLoopRule().validate(_sequenceWith(node)),
        isEmpty,
      );
    });

    test('rule is wired into defaultSequenceValidators', () {
      expect(
        defaultSequenceValidators.whereType<SmartExposureUnboundedLoopRule>(),
        hasLength(1),
      );
    });
  });
}
