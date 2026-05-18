import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nightshade_core/src/models/sequence/sequence_models.dart';
import 'package:nightshade_core/src/providers/sequence/target_progress_provider.dart';
import 'package:nightshade_core/src/providers/sequence_provider.dart';

/// Tests for the per-target execution progress rollup.

ProviderContainer _container({
  required Sequence sequence,
  SequenceProgress progress = const SequenceProgress(),
}) {
  final container = ProviderContainer(overrides: [
    currentSequenceProvider.overrideWith((ref) {
      final notifier = CurrentSequenceNotifier();
      // ignore: invalid_use_of_protected_member
      notifier.state = sequence;
      return notifier;
    }),
    sequenceProgressProvider.overrideWith((ref) {
      final n = SequenceProgressNotifier();
      // ignore: invalid_use_of_protected_member
      n.state = progress;
      return n;
    }),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Build "Root → Target → Exposure(60s ×8) + Exposure(120s ×4)" so the
/// totals are 12 frames (8+4) and 8·60+4·120 = 480+480 = 960s
/// integration. Returns the target id for the assertions.
({Sequence sequence, String targetId, String firstExpoId, String secondExpoId})
    _buildTwoExposureTarget() {
  final expo1 = ExposureNode(durationSecs: 60, count: 8, name: 'a');
  final expo2 = ExposureNode(durationSecs: 120, count: 4, name: 'b');
  final target = TargetHeaderNode(
    targetName: 'M31',
    raHours: 0,
    decDegrees: 0,
  );
  final root = InstructionSetNode(name: 'Root');
  final tree = <String, SequenceNode>{
    expo1.id: expo1.copyWith(parentId: target.id),
    expo2.id: expo2.copyWith(parentId: target.id),
    target.id:
        target.copyWith(parentId: root.id, childIds: [expo1.id, expo2.id]),
    root.id: root.copyWith(childIds: [target.id]),
  };
  return (
    sequence: Sequence(name: 'Test', nodes: tree, rootNodeId: root.id),
    targetId: target.id,
    firstExpoId: expo1.id,
    secondExpoId: expo2.id,
  );
}

void main() {
  group('targetExecutionProgressProvider', () {
    test('empty when target id not in sequence', () {
      final t = _buildTwoExposureTarget();
      final c = _container(sequence: t.sequence);
      final p = c.read(targetExecutionProgressProvider('missing-id'));
      expect(p, same(TargetExecutionProgress.empty));
    });

    test('plan totals match exposure counts before any frame completes', () {
      final t = _buildTwoExposureTarget();
      final c = _container(sequence: t.sequence);
      final p = c.read(targetExecutionProgressProvider(t.targetId));
      expect(p.totalFrames, 12);
      expect(p.completedFrames, 0);
      expect(p.totalIntegrationSecs, 960);
      expect(p.completedIntegrationSecs, 0);
      expect(p.fraction, 0.0);
    });

    test('completed exposure attributes all frames', () {
      final t = _buildTwoExposureTarget();
      final c = _container(
        sequence: t.sequence,
        progress: SequenceProgress(
          nodeStatuses: {t.firstExpoId: NodeStatus.success},
        ),
      );
      final p = c.read(targetExecutionProgressProvider(t.targetId));
      expect(p.completedFrames, 8); // expo1 done
      expect(p.completedIntegrationSecs, 480);
      // 8/12 ≈ 0.667
      expect(p.fraction, closeTo(8 / 12, 1e-9));
    });

    test('running exposure attributes partial frames from percent', () {
      final t = _buildTwoExposureTarget();
      // expo1 (count=8) at 50% -> 4 frames done.
      final c = _container(
        sequence: t.sequence,
        progress: SequenceProgress(
          nodeStatuses: {t.firstExpoId: NodeStatus.running},
          nodeProgressPercent: {t.firstExpoId: 50.0},
        ),
      );
      final p = c.read(targetExecutionProgressProvider(t.targetId));
      expect(p.completedFrames, 4);
      expect(p.completedIntegrationSecs, 4 * 60);
    });

    test('skipped/failure exposures contribute zero completed frames', () {
      final t = _buildTwoExposureTarget();
      final c = _container(
        sequence: t.sequence,
        progress: SequenceProgress(
          nodeStatuses: {
            t.firstExpoId: NodeStatus.skipped,
            t.secondExpoId: NodeStatus.failure,
          },
        ),
      );
      final p = c.read(targetExecutionProgressProvider(t.targetId));
      expect(p.completedFrames, 0);
      expect(p.completedIntegrationSecs, 0);
    });

    test('hasPlannedFrames mirrors totalFrames > 0', () {
      const empty = TargetExecutionProgress.empty;
      expect(empty.hasPlannedFrames, isFalse);
      const filled = TargetExecutionProgress(
        totalFrames: 1,
        completedFrames: 0,
        totalIntegrationSecs: 30,
        completedIntegrationSecs: 0,
      );
      expect(filled.hasPlannedFrames, isTrue);
    });
  });
}
