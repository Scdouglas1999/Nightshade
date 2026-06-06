import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/sequence/sequence_executor/frame_attribution.dart';

/// Pins the fix for the P0 where scheduler-captured frames were written with
/// `target_id=NULL` (so integration goals never completed and the engine
/// imaged one target all night) and `exposureDuration=1.0` (corrupting all
/// integration-time accounting). [resolveFrameAttribution] must recover both
/// the catalog target id and the real exposure length from the producing node
/// and the sequence tree.
void main() {
  group('resolveFrameAttribution', () {
    test('scheduler-shaped tree (childIds only) resolves target id + duration',
        () {
      // Mirrors SchedulerEngine.buildSequenceForCandidate: a TargetHeader that
      // carries the DB target id and lists its children, with NO explicit
      // parentId on the children (parentOf is derived from childIds).
      final seq = Sequence.create(
        name: 'sched',
        rootNodeId: 't',
        nodes: {
          't': TargetHeaderNode(
            id: 't',
            targetName: 'M31',
            raHours: 0.71,
            decDegrees: 41.27,
            catalogTargetId: 42,
            childIds: const ['slew', 'exp'],
          ),
          'slew': SlewNode(id: 'slew', useTargetCoords: true),
          'exp': ExposureNode(id: 'exp', durationSecs: 300.0, count: 20),
        },
      );

      final a = resolveFrameAttribution(seq, 'exp');
      expect(a.targetId, 42);
      expect(a.exposureSecs, 300.0);
    });

    test('resolves target id through an intervening container node', () {
      final seq = Sequence.create(
        name: 'nested',
        rootNodeId: 't',
        nodes: {
          't': TargetHeaderNode(
            id: 't',
            targetName: 'NGC 7000',
            raHours: 20.97,
            decDegrees: 44.5,
            catalogTargetId: 7,
            childIds: const ['loop'],
          ),
          'loop': InstructionSetNode(id: 'loop', name: 'Loop')
              .copyWith(childIds: const ['exp']),
          'exp': ExposureNode(id: 'exp', durationSecs: 120.0),
        },
      );

      final a = resolveFrameAttribution(seq, 'exp');
      expect(a.targetId, 7);
      expect(a.exposureSecs, 120.0);
    });

    test('manual sequence with no catalog id leaves target id null', () {
      final seq = Sequence.create(
        name: 'manual',
        rootNodeId: 't',
        nodes: {
          't': TargetHeaderNode(
            id: 't',
            targetName: 'Custom',
            raHours: 5.0,
            decDegrees: -5.0,
            // catalogTargetId intentionally omitted -> null
            childIds: const ['exp'],
          ),
          'exp': ExposureNode(id: 'exp', durationSecs: 60.0),
        },
      );

      final a = resolveFrameAttribution(seq, 'exp');
      expect(a.targetId, isNull);
      // Duration is still recovered even without a target id.
      expect(a.exposureSecs, 60.0);
    });

    test('SmartExposure resolves duration from the currently-exposing filter',
        () {
      final seq = Sequence.create(
        name: 'smart',
        rootNodeId: 't',
        nodes: {
          't': TargetHeaderNode(
            id: 't',
            targetName: 'M42',
            raHours: 5.59,
            decDegrees: -5.39,
            catalogTargetId: 3,
            childIds: const ['smart'],
          ),
          'smart': SmartExposureNode(
            id: 'smart',
            plans: const [
              FilterPlan(filterName: 'Ha', durationSecs: 600.0),
              FilterPlan(filterName: 'OIII', durationSecs: 300.0),
            ],
          ),
        },
      );

      expect(
        resolveFrameAttribution(seq, 'smart', currentFilter: 'OIII').exposureSecs,
        300.0,
      );
      expect(
        resolveFrameAttribution(seq, 'smart', currentFilter: 'Ha').exposureSecs,
        600.0,
      );
      // Target id still resolves regardless of filter.
      expect(
        resolveFrameAttribution(seq, 'smart', currentFilter: 'Ha').targetId,
        3,
      );
      // Unknown / absent filter -> null duration, not a fabricated value.
      expect(
        resolveFrameAttribution(seq, 'smart', currentFilter: 'SII').exposureSecs,
        isNull,
      );
      expect(resolveFrameAttribution(seq, 'smart').exposureSecs, isNull);
    });

    test('non-exposure producing node yields null duration (not a fake value)',
        () {
      final seq = Sequence.create(
        name: 'mixed',
        rootNodeId: 't',
        nodes: {
          't': TargetHeaderNode(
            id: 't',
            targetName: 'X',
            raHours: 1.0,
            decDegrees: 1.0,
            catalogTargetId: 9,
            childIds: const ['delay'],
          ),
          'delay': DelayNode(id: 'delay'),
        },
      );

      final a = resolveFrameAttribution(seq, 'delay');
      expect(a.targetId, 9);
      expect(a.exposureSecs, isNull);
    });

    test('unknown node id resolves to nulls without throwing', () {
      final seq = Sequence.create(
        name: 'empty',
        rootNodeId: 't',
        nodes: {
          't': TargetHeaderNode(
            id: 't',
            targetName: 'X',
            raHours: 1.0,
            decDegrees: 1.0,
            catalogTargetId: 1,
            childIds: const [],
          ),
        },
      );

      final a = resolveFrameAttribution(seq, 'does-not-exist');
      expect(a.targetId, isNull);
      expect(a.exposureSecs, isNull);
    });
  });
}
