import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/sequence/rules/exposure_rules.dart';
import 'package:nightshade_core/src/providers/sequence/rules/structure_rules.dart';
import 'package:nightshade_core/src/providers/sequence/rules/target_rules.dart';
import 'package:nightshade_core/src/providers/sequence/rules/timing_rules.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_validation.dart';

/// Pure-validator tests. Each rule gets a positive (fires) and a negative
/// (clean) case. Ref-aware rules live in a separate test file because they
/// need a ProviderContainer wiring.

/// Build a minimal sequence with one root container and the given children
/// dropped under it.
Sequence _sequenceWith(List<SequenceNode> children, {String name = 'Test'}) {
  final root = InstructionSetNode(name: 'Root');
  final nodes = <String, SequenceNode>{root.id: root};
  final childIds = <String>[];
  for (final child in children) {
    final placed = child.copyWith(parentId: root.id);
    nodes[placed.id] = placed;
    childIds.add(placed.id);
  }
  final rootWithChildren = root.copyWith(childIds: childIds);
  nodes[root.id] = rootWithChildren;
  return Sequence(
    name: name,
    nodes: nodes,
    rootNodeId: root.id,
  );
}

ValidationIssue _findIssue(List<ValidationIssue> issues, String title) {
  return issues.firstWhere(
    (i) => i.title == title,
    orElse: () => fail('Expected issue "$title" but found ${issues.map((i) => i.title).toList()}'),
  );
}

void main() {
  group('EmptySequenceRule', () {
    final rule = EmptySequenceRule();

    test('fires on empty sequence', () {
      final s = Sequence(name: 'Empty');
      final issues = rule.validate(s);
      expect(issues, hasLength(1));
      expect(issues.single.severity, ValidationSeverity.error);
      expect(issues.single.title, 'Empty Sequence');
      expect(issues.single.category, ValidationCategory.structure);
    });

    test('clean on non-empty sequence', () {
      final s = _sequenceWith([ExposureNode()]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('MissingRootNodeRule', () {
    final rule = MissingRootNodeRule();

    test('fires when nodes exist but no root', () {
      final exp = ExposureNode();
      final s = Sequence(
        name: 'NoRoot',
        nodes: {exp.id: exp},
      );
      final issues = rule.validate(s);
      expect(issues.single.severity, ValidationSeverity.error);
      expect(issues.single.title, 'No Root Node');
    });

    test('clean when root is present', () {
      final s = _sequenceWith([ExposureNode()]);
      expect(rule.validate(s), isEmpty);
    });

    test('does not double-fire on empty sequence', () {
      final s = Sequence(name: 'Empty');
      expect(rule.validate(s), isEmpty);
    });
  });

  group('OrphanedNodesRule', () {
    final rule = OrphanedNodesRule();

    test('fires when an unreachable node exists', () {
      final root = InstructionSetNode(name: 'Root');
      final orphan = ExposureNode();
      final s = Sequence(
        name: 'Test',
        nodes: {root.id: root, orphan.id: orphan},
        rootNodeId: root.id,
      );
      final issues = rule.validate(s);
      expect(issues, hasLength(1));
      expect(issues.single.severity, ValidationSeverity.warning);
      expect(issues.single.title, 'Orphaned Nodes');
    });

    test('clean when all nodes are reachable', () {
      final s = _sequenceWith([ExposureNode()]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('EmptyContainerRule', () {
    final rule = EmptyContainerRule();

    test('fires on empty Loop container', () {
      final loop = LoopNode(name: 'Loop');
      final s = _sequenceWith([loop]);
      final issues = rule.validate(s);
      expect(issues.single.title, 'Empty Container');
      expect(issues.single.affectedNodeId, isNotNull);
    });

    test('does not fire on empty TargetHeaderNode (EmptyTargetRule owns that)',
        () {
      final target = TargetHeaderNode(targetName: 'M31', raHours: 0, decDegrees: 0);
      final s = _sequenceWith([target]);
      // No Empty Container issue — EmptyTargetRule covers targets.
      final issues = rule.validate(s);
      expect(
          issues.where((i) => i.affectedNodeId == target.id), isEmpty);
    });

    test('clean on non-empty container', () {
      final exp = ExposureNode();
      final loop = LoopNode(name: 'Loop', childIds: [exp.id]);
      // Manually build to keep linkage tidy
      final s = Sequence(
        name: 'T',
        nodes: {loop.id: loop, exp.id: exp.copyWith(parentId: loop.id)},
        rootNodeId: loop.id,
      );
      expect(rule.validate(s), isEmpty);
    });
  });

  group('UnboundedLoopRule', () {
    final rule = UnboundedLoopRule();

    test('forever loop with no cap is ERROR', () {
      final loop = LoopNode(
        name: 'Forever',
        conditionType: LoopConditionType.forever,
      );
      final s = _sequenceWith([loop]);
      final issues = rule.validate(s);
      expect(issues, hasLength(1));
      expect(issues.single.severity, ValidationSeverity.error);
      expect(issues.single.title, 'Unbounded Loop');
    });

    test('whileDark loop with no cap is ERROR', () {
      final loop = LoopNode(
        name: 'WD',
        conditionType: LoopConditionType.whileDark,
      );
      final s = _sequenceWith([loop]);
      final issues = rule.validate(s);
      expect(issues.single.severity, ValidationSeverity.error);
    });

    test('forever loop with maxSafetyIterations is clean', () {
      final loop = LoopNode(
        name: 'Forever',
        conditionType: LoopConditionType.forever,
        maxSafetyIterations: 1000,
      );
      final s = _sequenceWith([loop]);
      expect(rule.validate(s), isEmpty);
    });

    test('whileDark loop with repeatUntil is clean', () {
      final loop = LoopNode(
        name: 'WD',
        conditionType: LoopConditionType.whileDark,
        repeatUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      final s = _sequenceWith([loop]);
      expect(rule.validate(s), isEmpty);
    });

    test('forever loop with repeatUntilAltitude is clean', () {
      final loop = LoopNode(
        name: 'F',
        conditionType: LoopConditionType.forever,
        repeatUntilAltitude: 30.0,
      );
      final s = _sequenceWith([loop]);
      expect(rule.validate(s), isEmpty);
    });

    test('count-based loop is clean (not unbounded)', () {
      final loop = LoopNode(
        name: 'Count',
        conditionType: LoopConditionType.count,
        repeatCount: 5,
      );
      final s = _sequenceWith([loop]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('TargetCoordinatesRule', () {
    final rule = TargetCoordinatesRule();

    test('fires on invalid RA', () {
      final t = TargetHeaderNode(targetName: 'X', raHours: 25, decDegrees: 0);
      final s = _sequenceWith([t]);
      final issues = rule.validate(s);
      expect(_findIssue(issues, 'Invalid RA').severity,
          ValidationSeverity.error);
    });

    test('fires on invalid Dec', () {
      final t =
          TargetHeaderNode(targetName: 'X', raHours: 12, decDegrees: 95);
      final s = _sequenceWith([t]);
      final issues = rule.validate(s);
      expect(_findIssue(issues, 'Invalid Dec').severity,
          ValidationSeverity.error);
    });

    test('clean on valid coords', () {
      final t = TargetHeaderNode(targetName: 'M31', raHours: 0.7, decDegrees: 41);
      final s = _sequenceWith([t]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('SlewCoordinatesRule', () {
    final rule = SlewCoordinatesRule();

    test('fires on invalid custom RA', () {
      final n = SlewNode(useTargetCoords: false, customRa: 30, customDec: 0);
      final s = _sequenceWith([n]);
      final issues = rule.validate(s);
      expect(_findIssue(issues, 'Invalid Slew RA').severity,
          ValidationSeverity.error);
    });

    test('does not fire when using target coords', () {
      final n = SlewNode(useTargetCoords: true);
      final s = _sequenceWith([n]);
      expect(rule.validate(s), isEmpty);
    });

    test('clean on valid custom coords', () {
      final n = SlewNode(useTargetCoords: false, customRa: 12, customDec: 0);
      final s = _sequenceWith([n]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('EmptyTargetRule', () {
    final rule = EmptyTargetRule();

    test('fires on target with no children', () {
      final t = TargetHeaderNode(targetName: 'M31', raHours: 0, decDegrees: 0);
      final s = _sequenceWith([t]);
      final issues = rule.validate(s);
      expect(issues, hasLength(1));
      expect(issues.single.title, 'Empty Target');
      expect(issues.single.affectedNodeId, t.id);
    });

    test('clean on target with children', () {
      final exp = ExposureNode();
      final t = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
        childIds: [exp.id],
      );
      final s = Sequence(
        name: 'T',
        nodes: {t.id: t, exp.id: exp.copyWith(parentId: t.id)},
        rootNodeId: t.id,
      );
      expect(rule.validate(s), isEmpty);
    });
  });

  group('LowAltitudeLimitRule', () {
    final rule = LowAltitudeLimitRule();

    test('fires when minAltitude < 10', () {
      final t = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
        minAltitude: 5,
      );
      final s = _sequenceWith([t]);
      final issues = rule.validate(s);
      expect(issues.single.severity, ValidationSeverity.warning);
      expect(issues.single.title, 'Very Low Altitude Limit');
    });

    test('clean when minAltitude >= 10', () {
      final t = TargetHeaderNode(
        targetName: 'M31',
        raHours: 0,
        decDegrees: 0,
        minAltitude: 20,
      );
      final s = _sequenceWith([t]);
      expect(rule.validate(s), isEmpty);
    });

    test('clean when minAltitude is null', () {
      final t = TargetHeaderNode(targetName: 'M31', raHours: 0, decDegrees: 0);
      final s = _sequenceWith([t]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('NoTargetForExposuresRule', () {
    final rule = NoTargetForExposuresRule();

    test('fires when there are exposures but no targets', () {
      final s = _sequenceWith([ExposureNode()]);
      final issues = rule.validate(s);
      expect(issues.single.title, 'No Targets Defined');
    });

    test('clean when targets are present', () {
      final t = TargetHeaderNode(targetName: 'M31', raHours: 0, decDegrees: 0);
      final s = _sequenceWith([t]);
      expect(rule.validate(s), isEmpty);
    });

    test('clean when no exposures', () {
      final s = _sequenceWith([SlewNode(useTargetCoords: true)]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('ExposureParamsRule', () {
    final rule = ExposureParamsRule();

    test('fires on duration <= 0', () {
      final e = ExposureNode(durationSecs: 0, count: 5);
      final s = _sequenceWith([e]);
      final issues = rule.validate(s);
      expect(_findIssue(issues, 'Invalid Exposure Time').severity,
          ValidationSeverity.error);
    });

    test('fires on count <= 0', () {
      final e = ExposureNode(durationSecs: 60, count: 0);
      final s = _sequenceWith([e]);
      final issues = rule.validate(s);
      expect(_findIssue(issues, 'Invalid Frame Count').severity,
          ValidationSeverity.error);
    });

    test('warns on very long exposure', () {
      final e = ExposureNode(durationSecs: 3600, count: 1);
      final s = _sequenceWith([e]);
      final issues = rule.validate(s);
      expect(_findIssue(issues, 'Very Long Exposure').severity,
          ValidationSeverity.warning);
    });

    test('clean on sensible exposure', () {
      final e = ExposureNode(durationSecs: 60, count: 10);
      final s = _sequenceWith([e]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('HighBinningRule', () {
    final rule = HighBinningRule();

    test('fires on 3x3 binning', () {
      final e = ExposureNode(binning: BinningMode.three);
      final s = _sequenceWith([e]);
      final issues = rule.validate(s);
      expect(issues.single.severity, ValidationSeverity.info);
      expect(issues.single.title, 'High Binning');
    });

    test('clean on 1x1 binning', () {
      final e = ExposureNode(binning: BinningMode.one);
      final s = _sequenceWith([e]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('NoExposuresRule', () {
    final rule = NoExposuresRule();

    test('fires when no enabled exposures exist', () {
      final n = SlewNode(useTargetCoords: true);
      final s = _sequenceWith([n]);
      final issues = rule.validate(s);
      expect(issues.single.title, 'No Exposures');
    });

    test('clean when an enabled exposure exists', () {
      final s = _sequenceWith([ExposureNode()]);
      expect(rule.validate(s), isEmpty);
    });

    test('does not fire on empty sequence (EmptySequenceRule covers it)', () {
      final s = Sequence(name: 'E');
      expect(rule.validate(s), isEmpty);
    });
  });

  group('LongTotalIntegrationRule', () {
    final rule = LongTotalIntegrationRule();

    test('fires when total integration > 8 hours', () {
      // 10x exposures of 3600s each = 36000s total, well over 28800.
      final e = ExposureNode(durationSecs: 3600, count: 10);
      final s = _sequenceWith([e]);
      final issues = rule.validate(s);
      expect(issues.single.title, 'Very Long Sequence');
    });

    test('clean when total integration <= 8 hours', () {
      final e = ExposureNode(durationSecs: 60, count: 10);
      final s = _sequenceWith([e]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('WaitTimePastRule', () {
    final rule = WaitTimePastRule();

    test('fires when waitUntil is in the past', () {
      final n = WaitTimeNode(
        waitUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final s = _sequenceWith([n]);
      final issues = rule.validate(s);
      expect(issues.single.title, 'Wait Time Passed');
    });

    test('clean when waitUntil is in the future', () {
      final n = WaitTimeNode(
        waitUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      final s = _sequenceWith([n]);
      expect(rule.validate(s), isEmpty);
    });

    test('clean when waitUntil is null', () {
      final n = WaitTimeNode();
      final s = _sequenceWith([n]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('LoopEndTimePastRule', () {
    final rule = LoopEndTimePastRule();

    test('fires when repeatUntil is in the past', () {
      final n = LoopNode(
        name: 'L',
        repeatUntil: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final s = _sequenceWith([n]);
      final issues = rule.validate(s);
      expect(issues.single.title, 'Loop End Time Passed');
    });

    test('clean when repeatUntil is in the future', () {
      final n = LoopNode(
        name: 'L',
        repeatUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      final s = _sequenceWith([n]);
      expect(rule.validate(s), isEmpty);
    });
  });

  group('Public API: validateSequence (top-level)', () {
    test('runs all default structural rules', () {
      // Sequence with two issues: empty + no root.
      final s = Sequence(name: 'X');
      final issues = validateSequence(s);
      // EmptySequence + (NoRootNode is suppressed because EmptySequence fires
      // first, by design)
      expect(issues.any((i) => i.title == 'Empty Sequence'), isTrue);
      expect(issues.first.severity, ValidationSeverity.error);
    });

    test('result has stable hashCode + value equality', () {
      const a = ValidationIssue(
        severity: ValidationSeverity.error,
        category: ValidationCategory.structure,
        title: 'X',
        description: 'd',
      );
      const b = ValidationIssue(
        severity: ValidationSeverity.error,
        category: ValidationCategory.structure,
        title: 'X',
        description: 'd',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ValidationResult', () {
    test('groups issues by affected node', () {
      const a = ValidationIssue(
        severity: ValidationSeverity.warning,
        category: ValidationCategory.targets,
        title: 'A',
        description: 'd',
        affectedNodeId: 'node-1',
      );
      const b = ValidationIssue(
        severity: ValidationSeverity.error,
        category: ValidationCategory.targets,
        title: 'B',
        description: 'd',
        affectedNodeId: 'node-1',
      );
      final result = ValidationResult(
        issues: const [a, b],
        validatedAt: DateTime.now(),
      );
      expect(result.issuesByNodeId['node-1'], hasLength(2));
      expect(result.worstSeverityForNode('node-1'), ValidationSeverity.error);
    });

    test('worstSeverityForNode returns null for unknown node', () {
      final result = ValidationResult.empty();
      expect(result.worstSeverityForNode('missing'), isNull);
    });
  });
}
